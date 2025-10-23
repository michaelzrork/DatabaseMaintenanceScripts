# Database Maintenance Scripts

A collection of **167 production Progress ABL scripts** built over 2+ years to automate data operations, detect fraud, and maintain data integrity across enterprise SaaS databases serving 1,000+ public recreation and facility management organizations.

---

## Overview

These scripts represent 2+ years of backend development work, progressing from basic CRUD operations under guidance (late 2022) to complex multi-table operations and original algorithm design (2023-2025).

**Production Environment:**
- Progress OpenEdge database (RDBMS)
- Vermont Systems RecTrac/WebTrac platform
- 1,000+ customer databases
- Processing scale: Hundreds to millions of records

**Engineering Practices:**
- Transaction safety (all operations wrapped in transactions)
- Comprehensive audit logging (ActivityLog entries tracking changes)
- CSV log files for detailed change tracking
- Dry-run mode capability (`LogOnly` flag in template)
- Systematic testing (demo database → production)
- Iterative improvement based on edge case discovery

---

## Script Categories

The 167 scripts are organized by function:

### Data Discovery & Validation (23 scripts)
Scripts beginning with `find*` - Identify data issues, missing records, or generate reports
- `findDuplicateTeeTimes.p` - Detect scheduling conflicts
- `findMissingCreditCardHistory.p` - Identify payment processing gaps
- `findOrphanedRecords.p` - Locate records with broken relationships
- `findEmailVerificationsSentAfterVerified.p` - Audit email verification process

### Data Correction & Updates (19 scripts)
Scripts beginning with `fix*` - Repair data integrity issues
- `fixCommonEmailDomainTypos.p` - Correct email typos (gmail.cmo → gmail.com)
- `fixHouseholdPhoneNumber.p` - Standardize phone number formatting
- `fixPrimaryGuardianRelationshipCode.p` - Correct family relationship data

### Record Deletion & Cleanup (21 scripts)
Scripts beginning with `delete*` - Remove invalid, duplicate, or orphaned data
- `deleteDuplicateMailingAddressRecords.p` - Eliminate duplicate addresses
- `deleteOrphanedRecords.p` - Remove records with no parent relationships
- `deletePendingFeeHistory.p` - Clean up incomplete transaction records

### Business Logic Enforcement (13 scripts)
Scripts beginning with `set*` - Enforce business rules and update statuses
- `setActiveFamilyMemberToInactive_HHCheck.p` - Update member status based on household status
- `setDuplicateFeestoReset-ChargeStatusOnly.p` - Reset duplicate charge records
- `setNewHHToTaxable.p` - Apply tax status to new accounts

### Field-Level Changes (12 scripts)
Scripts beginning with `change*` - Modify specific field values
- `changeFeeCode.p` - Update fee structure assignments
- `changeGLCodes.p` - Modify general ledger codes for accounting
- `changeStatusToInactive.p` - Bulk status updates

### Data Synchronization (7 scripts)
Scripts beginning with `sync*` - Ensure consistency across related records
- `syncHHEmailtoPrimaryGuardian.p` - Keep household and member emails in sync
- `syncFamilyMemberStatusToHHStatus.p` - Cascade status changes
- `syncPhoneType.p` - Standardize phone type classifications

### Duplicate Merging (8 scripts)
Scripts beginning with `merge*` - Consolidate duplicate records
- `mergeDuplicateFMs.p` - Merge duplicate family members within accounts
- `mergeQuestionResponses.p` - Consolidate survey/registration responses
- `mergeGuestHouseholdFamilyMembers.p` - Merge guest account duplicates

### Record Purging & Archival (6 scripts)
Scripts beginning with `purge*` - Remove obsolete data systematically
- `purgeEntityLink.p` - Remove old relationship records
- `purgeMailingAddressRecordsWithNoAccountLink.p` - Clean orphaned addresses

### Batch Updates (9 scripts)
Scripts beginning with `update*` - Bulk field modifications
- `updateCategoryandFeeCodebyZip.p` - Geographic-based pricing updates
- `updateLastActiveDate.p` - Maintain activity tracking
- `updatePaycodes.p` - Mass payment method updates

### Data Operations (Miscellaneous)
- Scripts beginning with `clear*` (9 scripts) - Clear specific field values
- Scripts beginning with `remove*` (6 scripts) - Selective data removal
- Scripts beginning with `reset*` (3 scripts) - Return fields to default state
- Scripts beginning with `revert*` (3 scripts) - Undo previous script changes
- Scripts beginning with `add*` (3 scripts) - Add missing data or create records

---

## Featured Scripts

### 1. Fraud Detection Algorithm
**Filename:** `InactivateBadActorHHs_Today-7.p`

**Purpose:** Identify stolen credit card testing patterns in real-time registration systems

**Business Impact:** Enabled 8+ organizations to restore merchant accounts shut down by fraudulent activity

**Technical Implementation:**

**Multi-Factor Risk Analysis:**
The algorithm analyzes multiple risk indicators to identify fraudulent accounts:

1. **Registration Timing Patterns**
   - Rapid sequential account creation (timing clusters)
   - Configurable lookback period (filename-based: Today-7, Today-1, etc.)
   - Self-extracting date range from audit logs

2. **Naming Pattern Detection**
   - Known fraudulent name patterns (e.g., names starting with "asd")
   - Email address validation (@example.com domains flagged)
   - Known bad actor email addresses

3. **Payment Analysis**
   - Credit card decline patterns
   - Card holder name vs. family member name matching
   - Settled vs. declined transaction ratios
   - Payment method restrictions (in-house vs. online)

4. **Geographic & Demographic Validation**
   - Household coordinate checking (valid addresses vs. fake)
   - Birthday pattern matching (12/31/1969 as common test value)
   - Address validation logic

5. **Transaction History Correlation**
   - Cross-references settled transactions for refund logging
   - Generates detailed CSV reports with all transaction data
   - Links fraudulent accounts across multiple criteria

**Key Features:**
- **Configurable lookback period** - Filename-based date range (e.g., `Today-7.p` checks last 7 days)
- **Self-configuring** - Reads its own filename from audit logs to determine date range
- **Low false-positive rate** - Multiple validation layers prevent legitimate user flagging
- **Production safety** - LogOnly mode for validation before execution
- **Comprehensive logging** - CSV files with all analyzed households and transaction details
- **Refund tracking** - Logs settled transactions for financial reconciliation

**Code Structure (783 lines):**
```
Lines 1-80:   Configuration & variable definitions
Lines 83-100: Self-configuring date calculation from filename
Lines 111-138: Temp-table definitions for data processing
Lines 133-138: WebTrac interface configuration lookup
Lines 140-735: Main processing loop with multi-factor analysis
Lines 737-752: CSV log file generation
Lines 754-802: Audit log procedures
Lines 804-870: Utility functions (parsing, rounding, formatting)
```

**Production Usage:**
- Deployed to 8+ customer databases during active fraud incidents
- Variable lookback period enabled rapid response:
  - Single-day analysis during active attacks
  - Multi-day historical pattern analysis
  - Trend identification across time periods

**Edge Cases Handled:**
- Legitimate bulk registrations (camps, sports leagues)
- International users with different naming conventions
- System-generated test accounts
- Legitimate payment declines
- Shared card holder names

**Impact:** Organizations demonstrated fraud mitigation to credit card processors, restoring payment processing capabilities within days instead of weeks.

---

### 2. Duplicate Family Member Merger
**Filename:** `mergeDuplicateFMs.p`

**Purpose:** Merge duplicate member records within the same household while maintaining all relationship data

**Business Challenge:** 
Customer databases accumulated duplicate family members due to:
- Multiple registration channels (web, phone, in-person)
- Staff data entry errors
- Self-service registration duplication
- Parent vs. guardian registration conflicts

**Technical Implementation:**

**Matching Logic:**
Identifies duplicates based on:
- Same household (ParentTableID)
- Matching first name
- Matching last name
- Matching birthday
- Optional: matching gender

**Merge Process:**
```
1. For each household:
   - Identify primary member (earliest Relationship.Order)
   - Find duplicate members matching name/birthday
   
2. For each duplicate found:
   - Create AccountMerge record specifying transfer operation
   - Transfer all child records to primary member:
     * Program enrollments
     * Membership history
     * Transaction history
     * Payment records
     * Custom field data
     * Document attachments
   
3. Update or delete duplicate member record
4. Log all changes to CSV file
5. Create audit trail in ActivityLog
```

**Related Tables Updated:**
- Relationship (parent-child links)
- Member (primary record)
- Enrollment (program registrations)
- FeeHistory (transaction records)
- Payment (payment records)
- CustomFieldValue (custom data)
- EntityLink (document associations)
- And others as needed

**Safety Mechanisms:**
- Uses built-in AccountMerge system (proven merge logic)
- Transaction-wrapped (all-or-nothing operation)
- Comprehensive logging of all changes
- Record count validation
- Demo database testing required before production

**Code Structure (210 lines):**
```
Lines 1-71:   Setup & variable definitions
Lines 73-136: Account and member identification loops
Lines 138-180: Duplicate detection and merge execution
Lines 182-210: Logging and cleanup procedures
```

**Production Scale:**
- Merged hundreds of duplicate members across customer databases
- Handled complex scenarios (multiple duplicates per household)
- Processed varying data quality (incomplete vs. complete records)

**Impact:** Reduced data quality issues, prevented registration confusion, cleaned up reporting anomalies from duplicate records.

---

### 3. Data Synchronization System
**Filename:** `syncHHEmailtoPrimaryGuardian.p`

**Purpose:** Synchronize household email addresses with primary guardian member records

**Business Context:**
Email addresses were becoming out of sync between household and member records due to:
- UI bug when deleting household emails
- Direct database edits
- Data import issues
- Trigger failures in edge cases

**Technical Approach:**

**Sync Logic:**
```
1. Find all primary guardians (Relationship.Primary = true)
2. Compare Account.PrimaryEmailAddress vs. Member.PrimaryEmailAddress
3. If different:
   - Update Member email to match Account
   - Sync verification status
   - Sync opt-in status
   - Trigger updates WebUserName.EmailAddress automatically
   - Trigger updates EmailContact record automatically
4. Log all changes
```

**Design Decisions:**
- Account email treated as source of truth (where bug occurred)
- Preserves Account-side edits (even if typos)
- Trigger-aware (lets database triggers handle cascading updates)
- Automatically verifies synced emails (business rule)

**Safety Features:**
- Read-only on Account records (no accidental household changes)
- Comprehensive logging of all syncs
- Preserves email history
- No data deletion (only updates)

**Code Structure (197 lines):**
```
Lines 1-59:  Configuration and logging setup
Lines 60-79: Main sync loop
Lines 80-197: Email update procedures with field-level changes
```

**Production Results:**
- Fixed hundreds of out-of-sync email records
- Prevented communication issues
- Restored email verification accuracy
- Used as post-update maintenance step

**Iterative Improvements:**
- Originally deleted member emails when household email blank
- Updated to sync instead (preserves data)
- Added opt-in status sync
- Added verification status sync
- Added detailed logging for troubleshooting

**Impact:** Restored email data consistency, prevented communication failures, enabled reliable email verification tracking.

---

## Reusable Script Template System

**Filename:** `_ProgramTemplate.p` (in Templates folder)

All 167 scripts built from common template providing standardized patterns:

**Template Features:**

1. **Configuration Block**
```progress
&global-define ProgramName "scriptName"
&global-define ProgramDescription "What this does"

LogOnly flag - Dry-run mode without database changes
```

2. **Comprehensive Logging**
```progress
- CSV log files (detailed change tracking)
- ActivityLog entries (audit trail)
- Progress tracking (last record ID)
- Record counts (validation)
```

3. **Transaction Safety**
```progress
- All changes wrapped in transactions
- Rollback on error
- Validation before commit
```

4. **Utility Functions**
```progress
- ParseList() - Handle delimited data
- RoundUp() - Decimal precision
- AddCommas() - Number formatting
- getString() - Null-safe string conversion
```

5. **Standard Procedures**
```progress
- put-stream() - CSV file generation
- ActivityLog() - Create audit entries
- UpdateActivityLog() - Update progress
```

**Benefits:**
- Consistent error handling across all scripts
- Predictable logging behavior
- Easy troubleshooting (standard log format)
- Rapid script development
- Production-safe by design

**Evolution:**
- Early scripts (late 2022): Basic structure, minimal logging
- Mid-period (2023): Added dry-run mode, better error handling
- Mature scripts (2024-2025): Full template with all safety features

**Impact:** Enabled development of 100+ production-safe scripts with consistent quality and safety practices.

---

## Development Progression

**Late 2022 - Learning Phase:**
- Started with guidance from senior developers
- Basic CRUD scripts (change, update, clear operations)
- Simple single-table updates
- Following existing patterns

**2023 - Independence:**
- Began designing scripts independently
- More complex multi-table operations
- Added comprehensive logging
- Developed reusable template pattern

**2024-2025 - Complexity & Algorithm Design:**
- Original algorithm design (fraud detection)
- Complex merge operations
- Multi-criteria analysis
- Self-configuring scripts
- Production optimization

---

## Production Engineering Practices

**Safety-First Approach:**
1. Write script using template
2. Test in demo database (identical schema, test data)
3. Run in production with `LogOnly` flag (dry-run validation)
4. Review logs for unexpected behavior
5. Execute in production with logging enabled
6. Verify results and handle exceptions
7. Document edge cases for future iterations

**Iterative Improvement:**
- Scripts evolved through production use
- Edge cases discovered led to enhanced validation
- Performance optimizations added based on actual usage
- Better error messages from user feedback
- Revert scripts created when fixes needed

**Production Mindset:**
- Code runs on real customer data
- Failures have business impact
- Quick troubleshooting essential (good logs)
- Safe failure modes (transaction rollback)
- Clear documentation for maintenance

**Learning & Growth:**
- Started with basic scripts under guidance
- Developed template pattern through experience
- Built increasingly complex systems
- Designed original algorithms
- Achieved independence in engineering decisions

---

## Technical Environment

**Language:** Progress ABL (OpenEdge Advanced Business Language)

**Database:** Progress OpenEdge RDBMS (relational database)

**Execution:** Batch processing via AppServer or command-line

**Scale:**
- Individual scripts: 50-800 lines of code
- Processing volume: Hundreds to millions of records per run
- Customer databases: 1,000+ production databases
- Deployment: Customer-specific execution on demand

**Development Tools:**
- Progress Developer Studio
- Git version control
- Internal code review
- Customer-specific testing environments

---

## Key Takeaways

This repository demonstrates:

1. **Production Engineering Experience** - Code that runs on real systems with real customer data
2. **Safety-First Approach** - Transaction management, comprehensive logging, dry-run validation, rollback capabilities
3. **Problem-Solving Ability** - Original algorithm design (fraud detection), complex multi-table operations
4. **Iterative Improvement** - Scripts evolved through production use and edge case discovery
5. **Business Impact** - Automated hundreds of hours of manual work, prevented data corruption, enabled fraud mitigation
6. **Growth Trajectory** - Clear progression from guided work (2022) to independent complex systems (2024-2025)

These scripts represent 2+ years of backend development work in a production SaaS environment, demonstrating the fundamentals of backend engineering: database operations, business logic implementation, transaction safety, error handling, and production debugging.

---

## Code Availability

Due to the proprietary nature of the Progress ABL codebase and customer data sensitivity, full source code for all scripts is not published in this repository. However, the detailed descriptions above provide comprehensive technical implementation information demonstrating the engineering principles and approaches used.

**For interview discussions, I can provide:**
- Detailed walkthroughs of algorithm design and implementation
- Architecture diagrams showing database relationships
- Anonymized code samples demonstrating key techniques
- Discussion of specific technical decisions and trade-offs
- Examples of edge case handling and iterative improvements

---

## Contact

**Michael Rork**  
Backend Engineer  
michaelzrork@gmail.com  
[LinkedIn](https://linkedin.com/in/michaelzrork) | [GitHub](https://github.com/michaelzrork)

Questions about these scripts or my backend engineering experience? Let's connect!
