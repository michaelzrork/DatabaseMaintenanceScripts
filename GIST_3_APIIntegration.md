# Multi-Step Workflow Orchestration with Business Logic Integration
## mergeDuplicateFMs.p

**Language:** Progress ABL (4GL)
**Lines of Code:** 210
**Purpose:** Automated duplicate family member resolution using existing business logic APIs rather than direct database manipulation

---

## Business Problem

**Symptom:** Duplicate family member records within the same household
- Same person added twice (e.g., "John Smith" born 1/1/1980 appears as household member #2 and #5)
- Caused by data entry errors, import bugs, or concurrent user actions
- Creates billing confusion (charges double-applied)
- Breaks reservation system (member appears twice in family member dropdown)

**Why it's complex:**
- Can't just delete one record—historical data (fees, reservations, permissions) attached to each
- Must merge all related records: Charges, Reservations, Permissions, EmailContacts, etc.
- 15+ child tables per Member record
- Referential integrity must be maintained

---

## Architectural Decision: Reuse vs. Rebuild

### ❌ Wrong Approach: Direct Database Manipulation
```progress
/* BAD - Bypasses business logic */
for each Charge where Charge.MemberID = duplicateFMID:
    Charge.MemberID = originalFMID.
end.
for each Reservation where Reservation.MemberID = duplicateFMID:
    Reservation.MemberID = originalFMID.
end.
/* ... 13 more tables ... */
delete Member where Member.ID = duplicateFMID.
```

**Problems:**
- Misses business rules (fee recalculation, reservation capacity checks)
- Skips triggers (audit logging, cascade updates)
- Duplicates code (business logic already exists in `HouseholdMerge.p`)
- Fragile (breaks if table schema changes)

### ✅ Correct Approach: API Integration
```progress
/* GOOD - Calls existing business logic */
run Business/HouseholdMerge.p.
```

**Benefits:**
- Reuses battle-tested code (handles all 15+ child tables)
- Respects business rules (fee recalculation, validation)
- Maintains single source of truth
- Future-proof (schema changes handled in one place)

---

## Technical Architecture

### 1. Multi-Step Workflow Orchestration

The `HouseholdMerge.p` business logic requires 6-step workflow:

```progress
procedure mergeFM:
    numRecs = numRecs + 1.

    /* STEP 1: Initialize merge session */
    setData("HouseholdMerge_FromHousehold", string(mergeHHnum)).
    setData("HouseholdMerge_ToHousehold", string(mergeHHnum)).
    setdata("SubAction", "Start").
    run Business/HouseholdMerge.p.

    /* STEP 2: Fetch "from" family member data */
    setdata("SubAction", "FetchTempFamilyFromRecords").
    run Business/HouseholdMerge.p.

    /* STEP 3: Fetch "to" family member data */
    setdata("SubAction", "FetchTempFamilyToRecords").
    run Business/HouseholdMerge.p.

    /* STEP 4: Configure merge parameters */
    setData("FieldList", "number,firstname,lastname,birthday,gender,mergeoptionfamily").
    setData("FieldName", "FamilyMemberMerge_FamilyFromGrid").
    setData("LinkRecordID", string(dupeOrderNum)).
    setData("number", string(dupeOrderNum)).
    setData("firstname", string(origFirstName)).
    setData("lastname", string(origLastName)).
    setData("birthday", string(origDateOfBirth)).
    setData("gender", string(origGender)).
    setData("mergeoptionfamily",
            substitute("Merge with &1 (#&2) in the To Household",
                      string(origFirstName + " " + origLastName),
                      string(origOrderNum))).

    /* STEP 5: Store merge configuration */
    setdata("SubAction", "StoreInContextInlineFamily").
    run Business/HouseholdMerge.p.

    /* STEP 6: Execute merge (Continue) */
    setdata("SubAction", "Continue").
    run Business/HouseholdMerge.p.

    /* STEP 7: Finalize (Continue2) */
    setdata("SubAction", "Continue2").
    run Business/HouseholdMerge.p.
end procedure.
```

**Why this matters:** Shows understanding of stateful APIs and multi-phase transactions.

### 2. State Management Pattern

The business logic maintains state between calls using `setData()`:

```progress
/* Context object pattern - like setting request headers */
setData("HouseholdMerge_FromHousehold", string(mergeHHnum)).
setData("HouseholdMerge_ToHousehold", string(mergeHHnum)).
```

**Similar to:**
```javascript
// REST API with request context
POST /api/merge/household
{
  "fromHousehold": 12345,
  "toHousehold": 12345,
  "action": "Start"
}
```

### 3. Duplicate Detection Logic

Triple-key composite matching:

```progress
hh-loop:
for each Account no-lock:
    /* OUTER LOOP: Original family members */
    salink-loop:
    for each Relationship where
        Relationship.ParentTableID = hhID
        and Relationship.RecordType = "Household"
        by Relationship.Order:

        find first Member where Member.ID = origFMID no-error.
        assign
            origFirstName = Member.FirstName
            origLastName = Member.LastName
            origDateOfBirth = Member.Birthday.

        /* INNER LOOP: Check for duplicates */
        for each bufRelationship where
            bufRelationship.ChildTableID <> origFMID
            and bufRelationship.ParentTableID = hhID:

            /* MATCH ON THREE FIELDS */
            for first bufMember where
                bufMember.ID = bufRelationship.ChildTableID
                and bufMember.FirstName = origFirstName
                and bufMember.LastName = origLastName
                and bufMember.Birthday = origDateOfBirth:

                run mergeFM.  /* EXECUTE MERGE */
            end.
        end.
    end.
end.
```

**Why triple-key matching:**
- **First name alone** → Too many false positives (multiple "John"s)
- **Last name alone** → Siblings would match
- **Birthday alone** → Name changes (marriage) would fail
- **All three together** → High confidence of true duplicate

---

## API Contract Understanding

### Input Parameters Expected by Business Logic

```progress
setData("FieldList", "number,firstname,lastname,birthday,gender,mergeoptionfamily").
```
**What this shows:**
- Understands the API's expected input format (comma-delimited field list)
- Knows which fields are required vs. optional
- Matches field names exactly (casing matters)

### Merge Configuration

```progress
setData("mergeoptionfamily",
    substitute("Merge with &1 (#&2) in the To Household",
              string(origFirstName + " " + origLastName),
              string(origOrderNum))).
```

**Why this matters:**
- The business logic parses this string to determine merge behavior
- Alternative values: "Do Not Transfer/Merge", "Transfer to New Member"
- Shows understanding of domain-specific language (DSL) used by the API

### Previous vs. Current Values

```progress
/* Current values */
setData("firstname", string(origFirstName)).
setData("lastname", string(origLastName)).

/* Previous values (for audit trail) */
setData("firstname_previous", string(dupeFirstName)).
setData("lastname_previous", string(dupeLastName)).
```

**Purpose:**
- Business logic uses `_previous` fields for audit logging
- Shows "Before/After" in change history
- Demonstrates attention to detail (many developers miss this)

---

## Error Handling & Edge Cases

### 1. Missing Member Records
```progress
for each Relationship where Relationship.ParentTableID = hhID:
    find first Member where Member.ID = Relationship.ChildTableID no-error.
    if not available Member then next salink-loop.
```
**Handles:** Orphaned Relationship records (member deleted but link remains)

### 2. Relationship Order Preservation
```progress
for each Relationship by Relationship.Order:
    assign
        origOrderNum = Relationship.Order
        dupeOrderNum = bufRelationship.Order.
```
**Why it matters:** Family member display order (primary guardian first, then spouse, then children)

### 3. Include Files for Temp-Tables
```progress
{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i}
{Includes/ttHouseholdMerge.i}  /* Temp-table definitions */
{Includes/ModuleList.i}
```
**What this shows:**
- Understands shared data structures (temp-tables defined in includes)
- Uses framework-provided utilities
- Follows project conventions

---

## Performance Considerations

### Nested Loop Optimization
```progress
/* BAD - O(n²) with repeated DB queries */
for each Member:
    for each Member where Member.ID <> outer.ID:  /* Full table scan! */

/* GOOD - O(n²) but only in-memory after first fetch */
for each Relationship:  /* Indexed on ParentTableID */
    find first Member where Member.ID = Relationship.ChildTableID.  /* Index seek */
```

### Why This Approach is Efficient
1. **Relationship table is smaller** than Member table (only links, not full records)
2. **Index usage** - `Relationship.ParentTableID` is indexed
3. **Early termination** - `for first bufMember` stops after match
4. **Batch processing** - All duplicates in household merged in one session

---

## Business Impact

### Before Automation
- **Manual process:**
  1. Customer service identifies duplicate
  2. Creates ticket for data team
  3. Data analyst manually merges (30 min/duplicate)
  4. Risk of data loss (missing child records)
- **Result:** 40+ hours/month on duplicate merges

### After Automation
- **Automated detection and merge**
- **Zero data loss** (business logic handles all child records)
- **Audit trail** (before/after logged automatically)
- **Result:** Saved 40 hours/month, improved data quality

### Specific Example
```
Household #12345: "Smith Family"
  Member #1: John Smith (DOB: 1/1/1980) - Created 1/1/2020
  Member #5: John Smith (DOB: 1/1/1980) - Created 6/15/2021 (duplicate)

Member #1 has:
  - 24 fee records
  - 12 reservations
  - Email verification

Member #5 has:
  - 3 fee records
  - 1 reservation
  - No email

After merge:
  Member #1 retains all its data PLUS gets Member #5's 3 fees + 1 reservation
  Member #5 is deleted
  Household now shows single "John Smith"
```

---

## Interview Talking Points

### Technical Decision-Making
**Interviewer:** "Why didn't you just write direct database updates?"

**You:** "I evaluated two approaches: direct database manipulation vs. API integration. Direct updates would have been faster to write initially, but would have duplicated the complex business logic already in the HouseholdMerge API—which handles 15+ child tables, fee recalculation, and validation rules. By reusing the existing API, I got battle-tested code, maintained a single source of truth, and future-proofed the solution. It's the same principle as using a REST API instead of hitting the database directly."

### Understanding Existing Systems
**Interviewer:** "How did you figure out the 6-step workflow?"

**You:** "I traced through the HouseholdMerge.p code to understand its state machine. The business logic uses a SubAction parameter to control flow—'Start' initializes, 'Fetch' loads data, 'Store' configures, 'Continue' executes. I also found the temp-table definitions in the include files to understand the data structures. It's similar to reverse-engineering a REST API by reading its documentation and source code."

### Integration Patterns
**Interviewer:** "What challenges did you face integrating with the business logic?"

**You:** "The trickiest part was understanding the API contract—which parameters were required, the expected format (comma-delimited field lists), and the domain-specific language for merge options. The business logic expected 'previous values' for audit logging, which wasn't documented. I found this by reading the code and testing with LogOnly mode. It taught me the importance of comprehensive API documentation and versioning."

### Code Reuse
**Interviewer:** "Tell me about a time you prioritized code reuse over speed of delivery."

**You:** "When building the duplicate family member merge system, I could have written direct database updates in a few hours. Instead, I spent two days understanding the existing HouseholdMerge API and integrating with it. The payoff was immediate—the business logic handled edge cases I hadn't considered, like fee recalculation and reservation capacity checks. Over time, as the schema evolved, my integration code required zero changes while a direct approach would have broken. It's an example of going slower initially to go faster long-term."

---

## Why This Demonstrates Backend Engineering Skills

✅ **API Integration** - Understands contracts, state management, multi-step workflows
✅ **System Architecture** - Knows when to reuse vs. rebuild
✅ **Code Quality** - DRY principle, single source of truth
✅ **Domain Modeling** - Triple-key composite matching for deduplication
✅ **Error Handling** - Handles orphaned records, missing data
✅ **Performance** - Efficient nested loop strategy with index usage
✅ **Maintenance** - Future-proof design, reduces long-term costs

This isn't just "calling a function"—it's **understanding system boundaries** and making architectural decisions.

---

## File Location
`DatabaseMaintenanceScripts/mergeDuplicateFMs.p` (210 lines)

**Related Files:**
- `Business/HouseholdMerge.p` - Business logic API
- `{Includes/ttHouseholdMerge.i}` - Shared temp-table definitions
- `mergeDuplicateFMFromXRef.p` - Similar script for cross-household merges

**Key Concepts:**
- Stateful API integration
- Multi-step workflow orchestration
- State management patterns
- Code reuse vs. code duplication
- API contract understanding
