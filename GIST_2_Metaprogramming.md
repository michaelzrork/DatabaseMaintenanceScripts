# Dynamic Metaprogramming for Duplicate Record Resolution
## DeleteDuplicateSearchCacheRecords.p

**Language:** Progress ABL (4GL)
**Lines of Code:** 367
**Purpose:** Generic duplicate detection system using handle-based dynamic programming and runtime table introspection

---

## Business Problem

The search index cache table (SearchCache) was accumulating duplicate records:
- Multiple search cache entries pointing to the same parent record (Account, Member, Reservation, etc.)
- Search performance degrading due to duplicate word indexes
- No way to determine which duplicate was "correct" without comparing timestamps
- Parent records span 30+ different table types—needed generic solution

---

## Technical Challenge: The Metaprogramming Approach

**Problem:** How do you write ONE script that can handle duplicates across 30+ different parent tables without hardcoding each table's structure?

**Solution:** Dynamic handle-based programming—creating buffers, queries, and field references at runtime.

---

## Core Architecture

### 1. Main Deduplication Logic

```progress
for each SearchCache no-lock:
    assign
        lastCreatedDate = datetime(NameVal("LastCreated",
                                           SearchCache.MiscInformation,
                                           chr(31), chr(30))).

    run findDuplicateRecord(SearchCache.ID,
                           SearchCache.ParentRecord,
                           SearchCache.ParentTable).
end.
```

**Key insight:** Each SearchCache record stores:
- `ParentTable` (string) - Which table it references (e.g., "Account", "Member")
- `ParentRecord` (int64) - The ID in that table
- `MiscInformation` - Delimited string with "LastCreated" timestamp

### 2. Duplicate Detection with Timestamp Comparison

```progress
procedure findDuplicateRecord:
    define input parameter inpID as int64 no-undo.
    define input parameter cParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.
    define buffer bufSearchCache for SearchCache.

    do for bufSearchCache transaction:
        /* Find another SearchCache record with same parent */
        for first bufSearchCache no-lock
            where bufSearchCache.ID <> inpID
            and bufSearchCache.ParentRecord = cParentID:

            assign
                bufLastCreatedDate = datetime(NameVal("LastCreated",
                                                      bufSearchCache.MiscInformation,
                                                      chr(31), chr(30))).

            /* Keep the NEWER record, delete the older */
            if bufLastCreatedDate >= lastCreatedDate then
                run deleteDuplicateRecord(SearchCache.ID,      /* Delete original */
                                         lastCreatedDate,
                                         bufSearchCache.ID,    /* Keep this one */
                                         bufLastCreatedDate,
                                         bufSearchCache.WordIndex).
            else
                run deleteDuplicateRecord(bufSearchCache.ID,   /* Delete duplicate */
                                         bufLastCreatedDate,
                                         SearchCache.ID,       /* Keep original */
                                         lastCreatedDate,
                                         SearchCache.WordIndex).
        end.
    end.
end procedure.
```

**Why this matters:** "Last write wins" conflict resolution—common pattern in distributed systems.

### 3. The Metaprogramming Magic: Dynamic Table Introspection

This is the advanced part—querying any table by name at runtime:

```progress
procedure findDescription:
    define input parameter cParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.

    define variable hBuffer as handle no-undo.
    define variable hQuery as handle no-undo.
    define variable hField as handle no-undo.
    define variable cQuery as character no-undo.

    /* CREATE A BUFFER FOR THE TABLE AT RUNTIME */
    create buffer hBuffer for table cParentTable.

    /* CREATE A DYNAMIC QUERY */
    create query hQuery.
    hQuery:set-buffers(hBuffer).

    /* BUILD QUERY STRING DYNAMICALLY */
    cQuery = substitute("for each &1 no-lock where &1.ID = &2",
                       cParentTable,
                       cParentID).

    /* EXECUTE THE QUERY */
    hQuery:query-prepare(cQuery).
    hQuery:query-open().
    hQuery:get-first().

    if not hQuery:query-off-end then
        run extractDescriptionField(hBuffer).

    /* CLEANUP */
    hQuery:query-close().
    delete object hQuery.
    delete object hBuffer.
end procedure.
```

**What's happening here:**
1. **Runtime type creation** - `create buffer hBuffer for table cParentTable`
   - If `cParentTable = "Account"`, creates an Account buffer
   - If `cParentTable = "Member"`, creates a Member buffer
   - All at runtime—no compile-time knowledge needed!

2. **Dynamic SQL construction** - `substitute("for each &1 where &1.ID = &2")`
   - Builds query string on-the-fly
   - Like prepared statements but more powerful

3. **Handle-based operations** - `hQuery:query-prepare(cQuery)`
   - Treating queries as first-class objects
   - Similar to reflection in Java/C# or metaprogramming in Python

### 4. Field Introspection with Fallback Logic

```progress
procedure extractDescriptionField:
    define input parameter hBuffer as handle no-undo.
    define variable hField as handle no-undo.

    /* SPECIAL CASE: Golf tee times need two fields */
    if cParentTable = "GRTeeTime" then
    do:
        hField = hBuffer:buffer-field("TeeTimeDate") no-error.
        hField2 = hBuffer:buffer-field("GolfCourse") no-error.
        if valid-handle(hField) and valid-handle(hField2) then
            itemDescription = "Tee Time for Golf Course " +
                            string(hField2:buffer-value) + " on " +
                            string(hField:buffer-value).
    end.

    /* STANDARD CASE: Try common description fields in order */
    else
    do:
        /* Try #1: ShortDescription */
        hField = hBuffer:buffer-field("ShortDescription") no-error.
        if valid-handle(hField) then
            itemDescription = hField:buffer-value.

        /* Try #2: Description */
        else
        do:
            hField = hBuffer:buffer-field("Description") no-error.
            if valid-handle(hField) then
                itemDescription = hField:buffer-value.

            /* Try #3: ComboKey */
            else
            do:
                hField = hBuffer:buffer-field("ComboKey") no-error.
                if valid-handle(hField) then
                    itemDescription = hField:buffer-value.
                else
                    itemDescription = "No Description Found".
            end.
        end.
    end.
end procedure.
```

**Why this is sophisticated:**
- **Field existence checking** - `hBuffer:buffer-field("ShortDescription") no-error`
  - Returns handle if field exists, invalid handle if not
  - Prevents runtime errors when tables have different schemas

- **Graceful degradation** - Falls back through multiple field names
  - Like trying `obj.shortDescription || obj.description || obj.name`

- **Dynamic value access** - `hField:buffer-value`
  - Reads field value through handle (not direct field reference)

---

## Why This Demonstrates Advanced Programming

### 1. Abstraction & Reusability
Instead of 30 separate scripts like:
```progress
/* Bad approach - 30 nearly-identical scripts */
deleteDuplicateAccountSearchCache.p
deleteDuplicateMemberSearchCache.p
deleteDuplicateReservationSearchCache.p
/* ... 27 more ... */
```

You have ONE generic script that handles all cases:
```progress
/* Good approach - single reusable solution */
DeleteDuplicateSearchCacheRecords.p  /* Works for ANY parent table */
```

### 2. Reflection-like Capabilities
Similar patterns in other languages:

**Java Reflection:**
```java
Class<?> clazz = Class.forName(tableName);
Field field = clazz.getDeclaredField("ShortDescription");
Object value = field.get(instance);
```

**Python Metaprogramming:**
```python
table_class = globals()[table_name]
instance = table_class.query.filter_by(id=parent_id).first()
description = getattr(instance, 'short_description',
                     getattr(instance, 'description', 'No Description'))
```

**This Progress ABL code:**
```progress
create buffer hBuffer for table cParentTable.
hField = hBuffer:buffer-field("ShortDescription") no-error.
if valid-handle(hField) then
    itemDescription = hField:buffer-value.
```

### 3. Handle-Based Programming
Handles are like pointers to database objects:
- **Buffer handles** - Reference to a table/record set
- **Query handles** - Reference to a query object
- **Field handles** - Reference to a specific field

This enables:
- **Runtime polymorphism** - Same code works for different types
- **Dynamic dispatch** - Method calls resolved at runtime
- **Type safety** - `valid-handle()` prevents null pointer errors

---

## Performance Considerations

### Why This Approach is Efficient

1. **Single pass through SearchCache** - No nested loops
2. **Transaction scoping** - `do for bufSearchCache transaction` for atomic deletes
3. **Index usage** - Finds duplicates by ParentRecord (indexed field)
4. **Early termination** - `for first bufSearchCache` stops after finding one duplicate

### Potential Bottlenecks Addressed

**Problem:** Creating buffers/queries on every iteration is expensive
**Solution:** Only calls `findDescription()` when logging (commented out in production)

```progress
/* Disabled for performance - only needed for detailed logging */
/* run findDescription(cParentID, cParentTable). */
```

---

## Conflict Resolution Strategy

**Timestamp-based "Last Write Wins"**
```progress
if bufLastCreatedDate >= lastCreatedDate then
    /* Keep newer, delete older */
else
    /* Keep older, delete newer */
```

**Why this pattern matters:**
- Same conflict resolution as Amazon DynamoDB, Cassandra, Riak
- Avoids complex merge logic
- Deterministic outcome (no randomness)

**Tradeoffs:**
- ✅ Simple, fast, predictable
- ✅ No manual intervention needed
- ❌ Might delete data if timestamps wrong
- ❌ Assumes "newer = better" (true for search cache)

---

## CSV Logging Output

```csv
Parent ID,Parent Table,Deleted Record ID,Deleted Last Created Date,Duplicate Record ID,Duplicate Last Created Date,Deleted WordIndex,Duplicate WordIndex
12345,Account,98765,2024-01-15 10:30:45,98766,2024-01-15 10:31:22,"smith john household",smith john household
67890,Member,54321,2024-01-14 09:15:30,54322,2024-01-14 09:16:01,"jane doe member active",jane doe member active
```

**Why comprehensive logging matters:**
- Audit trail of all deletions
- Can restore records if conflict resolution wrong
- Shows which tables had most duplicates (data quality insights)

---

## Production Safeguards

### 1. Framework Integration
```progress
{Includes/Framework.i}
{Includes/BusinessLogic.i}

function AddCommas returns character (dValue as decimal) forward.

define variable ActivityLogID as int64 no-undo init 0.
define variable LogOnly as logical no-undo init false.
```

### 2. Progress Tracking
```progress
run UpdateActivityLog(
    {&ProgramDescription},
    "Program in Progress; Last Record ID - SearchCache: " + getString(cLastID),
    "Number of Duplicate Records Deleted So Far: " + addCommas(numRecs),
    "", ""
)
```

### 3. Auto-Chunking Large Files
```progress
counter = counter + 1.
if counter gt 100000 then
do:
    inpfile-num = inpfile-num + 1.
    counter = 0.
end.
```
Prevents memory issues and makes files manageable.

---

## Interview Talking Points

### Technical Sophistication
**Interviewer:** "Tell me about a time you had to solve a problem that required going beyond basic CRUD operations."

**You:** "I built a generic duplicate resolution system that needed to work across 30+ different database tables without hardcoding each table's structure. I used handle-based metaprogramming to create buffers and queries at runtime, with field introspection to handle different schemas gracefully. It's similar to Java reflection or Python's `getattr()`, but in a 4GL database language. The system processes millions of records using timestamp-based conflict resolution—the same 'last write wins' pattern used in distributed databases like DynamoDB."

### Architecture & Design
**Interviewer:** "How do you approach code reusability?"

**You:** "Instead of writing 30 separate scripts for different table types, I created one generic solution using abstraction. The script accepts the table name as a runtime parameter and dynamically creates the appropriate buffer/query handles. This reduced code duplication by 30x and made the system easier to maintain—adding support for a new table type requires zero code changes."

### Problem-Solving
**Interviewer:** "What was the biggest challenge in implementing this?"

**You:** "The trickiest part was handling schema differences across tables. Not every table has a 'Description' field—some use 'ShortDescription', others use 'ComboKey'. I implemented a waterfall fallback pattern with field existence checking to handle these variations gracefully. It's defensive programming that prevents runtime errors while maintaining functionality across diverse schemas."

---

## Why This Demonstrates Backend Engineering Skills

✅ **Metaprogramming** - Runtime type creation and method dispatch
✅ **Design Patterns** - Strategy pattern (conflict resolution), Template Method (generic processing)
✅ **Database Expertise** - Handle-based programming, dynamic queries
✅ **Distributed Systems Concepts** - "Last write wins" conflict resolution
✅ **Code Quality** - Abstraction, reusability, defensive programming
✅ **Performance** - Efficient algorithms, transaction scoping

This demonstrates **senior-level thinking**—solving classes of problems, not individual instances.

---

## File Location
`DatabaseMaintenanceScripts/DeleteDuplicateSearchCacheRecords.p` (367 lines)

**Related Concepts:**
- Handle-based programming (Progress ABL advanced feature)
- Runtime polymorphism
- Reflection/introspection
- Conflict resolution strategies
- Generic programming patterns
