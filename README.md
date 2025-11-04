# Database Maintenance Scripts - Production ABL Code

Collection of production scripts written during my time as Operations Software Support Engineer at Vermont Systems (2021-2025). These scripts processed millions of records across 100+ customer databases with zero unrecoverable data corruption incidents.

**Tech Stack:** Progress OpenEdge ABL (4GL), SQL, Database Administration

---

## 🎯 Key Achievements

| Achievement | Impact |
|-------------|--------|
| **Fraud Detection System** | Deployed in 24 hours during active incident across 8+ organizations |
| **$1M Phantom Fees Recovery** | Resolved 7-year data corruption bug, zero data loss |
| **Payment Refund Fix** | Corrected 10+ year household member allocation flaw |
| **Automation Template** | 160+ deployments, zero unrecoverable incidents, 70% time reduction |

---

## Table of Contents
- [Fraud Detection System](#fraud-detection-system)
- [Data Corruption Cleanup - $1M Phantom Fees](#data-corruption-cleanup---1m-phantom-fees)
- [Category/Fee Code Sync System](#categoryfee-code-sync-system)
- [Household Member Payment Fix](#household-member-payment-fix)
- [Script Template Framework](#script-template-framework)
- [Development Approach](#development-approach)
- [Technical Notes](#technical-notes)
- [Full Script Inventory](#full-script-inventory)
- [About This Repository](#about-this-repository)

---

## Fraud Detection System

**Problem:** Active security incident - merchant accounts compromised, fraudulent transactions occurring across 8+ customer organizations. Payment gateway credentials exposed. Bad actors creating fake households to test stolen credit cards in real-time.

**Approach:** 
- Built pattern-matching detection system examining account creation patterns, email validation, name analysis, and transaction history
- Developed configurable lookback period system built into filename (e.g., `InactivateBadActorHHs_Today-7.p`) as workaround for system limitation preventing direct user input
- Created layered detection logic:
  - Email pattern analysis (gibberish domains, known bad actor addresses)
  - Name validation (detecting keyboard-mashing patterns like "asd", "fdg")
  - Birthday cross-referencing against known bad actor profiles
  - Card holder name verification against household members
  - Address validation (households with coordinates flagged as legitimate)
  - Transaction history analysis (internal vs. external payment methods)

**Solution:**
- Deployed detection system in 24 hours during active incident
- Identified and inactivated fraudulent households across 8+ organizations
- Balanced detection accuracy with false-positive rates through multi-layer checks
- Generated comprehensive CSV logs of all inactivated accounts for customer review
- Logged settled transactions separately for potential refund processing
- Enabled restoration of merchant accounts and prevented further financial loss

**Impact:** 
- Stopped ongoing fraud within 48 hours of incident start
- Restored service for affected customers
- Provided audit trail for finance teams and law enforcement
- Created reusable detection framework for future incidents

**Code:** [View InactivateBadActorHHs_Today-7.p](Scripts/InactivateBadActorHHs_Today-7.p)

---

## Data Corruption Cleanup - $1M Phantom Fees

**Problem:** 7-year data corruption bug creating phantom fees on customer accounts. Session state contamination was triggering wrong MemberIDs on hundreds of daily transactions, causing incorrect scholarship payment refunds and fee assessments. Customers complained for years but root cause remained unidentified.

**Approach:**
- Analyzed 15,000+ historical records to identify corruption patterns
- Traced issue to session state management flaw where `CURRENT-MEMBER-ID` variable wasn't properly scoped between concurrent transactions
- Mapped relationships between affected accounts, transactions, and fee records to build comprehensive cleanup logic
- Designed multi-phase approach with comprehensive edge case handling:
  - Pending fees without due options (primary target)
  - Orphaned records with missing parent transactions
  - Payment history reconciliation for scholarship refunds
  - TransactionDetail FullyPaid status recalculation
  - Charge/ChargeHistory relationship validation

**Solution:**
- Built diagnostic logic identifying all records affected by the session state bug
- Created cleanup system with LogOnly mode, comprehensive logging, and transaction-level rollback capabilities
- Implemented safety checks preventing deletion of legitimate fees (cross-referenced against payment records, activity logs, and account history)
- Coordinated with engineering team to implement permanent fix in application code
- Generated detailed CSV logs showing before/after state for every modified record

**Impact:** 
- Safely deleted over $1M in false balances across multiple customer databases
- Maintained near-100% customer satisfaction through proactive communication and phased rollout
- Provided engineering team with detailed root cause analysis and reproduction steps, enabling permanent fix
- Eliminated years of customer frustration and incorrect billing

**Code:** [View deletePendingFees.p](Scripts/deletePendingFees.p)

---

## Category/Fee Code Sync System

**Problem:** Customer organizations needed automated system to sync household categories and fee codes based on ZIP code residency (Resident vs Non-Resident status). Original implementation was brittle, hard-coded, and didn't handle edge cases, requiring manual intervention for exceptions.

**Approach - Version 1 (updateCategoryAndFeeCodebyZip.p):**
- Hard-coded Resident/Non-Resident categories (required recompilation per customer)
- Simple ZIP code lookup against Address Management tables
- Updated households, family members, and linked teams
- Basic logic without comprehensive edge case handling

**Approach - Version 2 (syncHHCategoryAndFeecodeByZip.p):**
- Complete rewrite based on production performance analysis and customer feedback
- Dynamic category lookup from system configuration (eliminated all hard-coding)
- Comprehensive edge case handling:
  - Family members in multiple households (prioritized Resident status across all households)
  - Missing ZIP codes (assigned default category from Static Parameters)
  - ZIP codes not in Address Management (safe fallback logic)
  - Guest/Internal/Model households (automatically excluded via CustomField lookup)
  - Profile-based sync options (respecting "Do Not Sync Family Members" preference)
  - ZIP+4 format support (intelligent substring matching)
- Generated detailed CSV log files with before/after audit trails for all changes
- Added comprehensive Activity Log updates with real-time progress tracking

**Solution:**
- 300+ lines of defensive code with extensive error handling
- Processed entire customer database (thousands of records) safely in single execution
- Comprehensive logging showing every change: original values → new values with record IDs
- Configurable behavior based on customer profile settings
- Eliminated need for customer-specific versions (one script works across all databases)

**Impact:** 
- Eliminated manual category management for multiple customers (hundreds of hours saved annually)
- Reduced support tickets related to incorrect residency status by ~80%
- Enabled automated annual residency verification processes
- CSV logs provided accountability and easy rollback capability if needed
- Script became template for other automated sync operations

**Code:** 
- [View syncHHCategoryAndFeecodeByZip.p](Scripts/syncHHCategoryAndFeecodeByZip.p) (Version 2 - production)
- [View updateCategoryAndFeeCodebyZip.p](Scripts/updateCategoryAndFeeCodebyZip.p) (Version 1 - original for comparison)

---

## Household Member Payment Fix

**Problem:** Payment disbursement logic flaw causing split payment refunds to credit incorrect household members. When scholarships were refunded, money went to wrong family member due to flawed household relationship logic. Issue existed for 10+ years, causing persistent customer complaints and requiring manual corrections by finance staff.

**Approach:**
- Built diagnostic script to identify all affected records across customer databases
- Analyzed payment processing source code to understand the relationship logic flaw
- Traced data flow: scholarship application → payment → refund → household member allocation
- Identified root cause: PaymentTransaction.PaymentMemberID and PaymentLog.MemberLinkID were being set to wrong household member when TransactionDetail.PatronLinkID didn't match
- Documented exact reproduction steps and conditions triggering the bug

**Solution:**
- **Phase 1:** Research script (`findReceiptPaymentWithWrongMemberID.p`) identified pattern affecting multiple customers
  - Cross-referenced PaymentTransaction, PaymentLog, ChargeHistory, Charge, and TransactionDetail records
  - Generated comprehensive CSV with household context and member relationships
  - Identified both scholarship and gift certificate payment types
- **Phase 2:** Fix script (`fixPaymentMemberID.p`) corrected the data
  - Updated PaymentTransaction.PaymentMemberID to match TransactionDetail.PatronLinkID
  - Corrected PaymentLog.MemberLinkID for scholarship records
  - Adjusted Member.ScholarshipAmount to reflect accurate balances
  - Full transaction safety with rollback capabilities
- **Phase 3:** Provided engineering team with detailed root cause analysis and proposed programmatic fix with pseudo-code
- Engineering team implemented permanent fix in production code based on findings

**Impact:**
- Corrected incorrect member allocations across multiple customer databases
- 10+ year customer complaint resolved permanently
- Prevented future incorrect refund allocations through application-level fix
- CSV logs provided complete audit trail for finance reconciliation
- Eliminated manual correction workload for support and finance teams

**Code:** 
- [View findReceiptPaymentWithWrongMemberID.p](Scripts/findReceiptPaymentWithWrongMemberID.p) (diagnostic/research)
- [View fixPaymentMemberID.p](Scripts/fixPaymentMemberID.p) (implementation)

---

## Script Template Framework

**Problem:** Need for standardized, production-safe script structure that support team could use confidently. Too many one-off scripts without consistent safety mechanisms led to anxiety around running scripts in customer databases and occasional incidents requiring rollback.

**Approach:**
Created reusable template with built-in safety mechanisms:
- **LogOnly Mode:** Append "LogOnly" to program name to preview all changes without committing transactions
- **Demo Database Testing:** Test mode using customer demo database before touching production
- **Dry-Run Preview:** Full execution with comprehensive logging but no data commits
- **Activity Log Integration:** Real-time progress updates with last-processed record ID for resumability
- **CSV Audit Trails:** Comprehensive before/after logs with all field changes and record IDs
- **Transaction Safety:** Explicit transaction blocks with buffer patterns and error handling
- **Row-Level Locking:** Prevented race conditions in high-volume batch operations
- **Input Validation:** Pre-flight checks for required configuration before execution
- **Client Code Tracking:** Automatic customer identification in all log files
- **Pagination Support:** Automatic log file splitting at 100,000 records to prevent memory issues

**Solution:**
- Template adopted team-wide for all new script development
- Standardized Activity Log format: Detail1-5 fields for consistent reporting
- Built-in helper functions (ParseList, RoundUp, AddCommas) for data formatting
- Document Center integration for automatic log file storage
- Reduced script development time from days to hours
- Enabled junior support staff to confidently handle complex data operations

**Impact:**
- Established production safety culture within support team
- Reduced anxiety around running scripts in customer databases
- Zero data corruption incidents across 160+ script deployments using this template
- Enabled team to handle 3x ticket volume without additional headcount
- Reduced manual intervention time by 70%
- Created knowledge base of reusable patterns and practices

**Code:** [View _ProgramTemplate.p](Templates/_ProgramTemplate.p)

---

## Development Approach

### Safety-First Philosophy

All scripts followed a rigorous safety process to ensure production stability and data integrity.

**Standard Script Deployment Process:**
1. **Template-based development** - Start with standardized safety patterns and proven utility functions
2. **Demo database testing** - Full validation with realistic data volumes matching production scale
3. **LogOnly execution** - Dry-run in production environment with comprehensive logging but zero commits
4. **Log review and validation** - Verify expected behavior, identify edge cases, confirm record counts
5. **Phased production rollout** - Start with single customer, monitor results, expand gradually
6. **Results verification** - Confirm changes match expectations, validate data integrity
7. **Edge case documentation** - Update script logic and comments for discovered scenarios

**Root Cause Analysis:**
- SQL queries to identify data patterns and anomalies
- Source code review to understand application logic flaws
- Customer data analysis to trace issue history
- Cross-table relationship mapping to prevent cascade failures

### Collaboration Model

These scripts weren't built in isolation:
- **Engineering Partnership:** Provided detailed root cause analysis and reproduction steps for permanent fixes
- **Customer Communication:** Proactive updates throughout phased rollouts, setting expectations and gathering feedback
- **Support Team Enablement:** Documentation and training to allow team members to run scripts confidently
- **Cross-functional Coordination:** Worked with finance, operations, and management on high-impact changes

### Quality Metrics

- **Zero unrecoverable data corruption incidents** across 160+ script deployments
- **Near-100% customer satisfaction** through proactive communication and careful rollout strategies
- **3x ticket volume capacity** enabled without additional headcount
- **70% reduction** in manual intervention time for routine data operations
- **Dozens of permanent fixes** implemented by engineering team based on script findings

### Development Progression

**Late 2022 - Learning Phase:**
- Started with guidance from senior developers
- Basic CRUD scripts (change, update, clear operations)
- Simple single-table updates with minimal validation
- Following existing patterns and team conventions

**2023 - Independence:**
- Began designing scripts independently based on ticket requirements
- More complex multi-table operations with relationship preservation
- Added comprehensive logging and error handling
- Developed reusable template pattern from common needs

**2024-2025 - Complexity & Algorithm Design:**
- Original algorithm design (fraud detection pattern matching)
- Complex merge operations with data consolidation
- Multi-criteria analysis and decision trees
- Self-configuring scripts with dynamic behavior
- Production optimization based on real-world performance
- Object-oriented integration with Vermont Systems' Business Object layer

---

## Technical Notes

### About Progress OpenEdge ABL

- **4GL supporting both procedural and object-oriented programming** with built-in database integration
- **Hybrid development approach** using both paradigms based on task requirements:
  - OOP when integrating with Vermont Systems' business logic layer
  - Procedural for direct database maintenance and bulk operations
- **Integrated transaction management** with explicit transaction blocks and rollback capabilities
- **Used in enterprise SaaS systems**, particularly in recreation management and government sectors
- **Strong typing** with support for both object references and traditional buffers (record references)

### Development Approach by Task Type

**Object-Oriented Scripts (Business Logic Integration):**
- Leveraged Vermont Systems' Business Object layer (BO classes)
- Example: `bulkSendWebInvite.p` - Used AccountBO, MemberBO, LinkBO, WebInvitesBO
- Object lifecycle management: instantiation, method calls, validation through business layer
- Encapsulated business rules: email validation, permission setting, invite sending
- Benefits: Reused existing validation logic, maintained consistency with application behavior

**Procedural Scripts (Database Maintenance):**
- Direct table access for data correction, cleanup, and bulk operations
- Examples: Most find*, fix*, delete*, sync* scripts
- Transaction-wrapped operations with explicit commit/rollback control
- Temp-tables for in-memory processing, deduplication, and intermediate results
- Buffer patterns for record locking and safe concurrent access
- Benefits: Performance optimization for bulk operations, granular control over transactions

**Design Decision Criteria:**
- Use OOP when: Leveraging existing business logic, sending emails, enforcing application-level rules
- Use procedural when: Bulk updates, data cleanup, performance-critical operations, bypassing application overhead

### Development Environment

- **Progress Developer Studio** (Eclipse-based IDE) for script development and debugging
- **Customer demo databases** for comprehensive testing before production deployment
- **Production deployment** via manual execution with comprehensive logging and monitoring
- **Version control** through Bitbucket (read-only access for investigating released application versions)
- **No automated testing framework** - safety through comprehensive manual testing and LogOnly mode

### Safety Practices in Production

- **All scripts tested in demo environment first** with realistic customer data volumes
- **LogOnly mode for every production execution** - review logs before committing changes
- **Comprehensive logging to Activity Log tables** - real-time progress tracking and audit trail
- **Transaction blocks with explicit error handling** - rollback on any exception
- **Coordination with engineering team** for systemic fixes requiring application changes
- **Phased rollout strategy** - start small, monitor, expand gradually
- **Customer communication plan** - set expectations, provide updates, gather feedback

### Why Progress ABL?

While not as widely known as modern languages, Progress ABL is used by thousands of enterprise organizations in government, recreation, healthcare, and education sectors. The principles demonstrated here - defensive programming, comprehensive logging, transaction safety, and customer-centric deployment - translate directly to any backend engineering role.

**Transferable Skills:**
- Transaction management and data integrity
- Production debugging and troubleshooting
- Database relationship understanding
- Batch processing optimization
- Error handling and recovery strategies
- Customer communication during high-impact changes
- Choosing appropriate paradigms (OOP vs procedural) based on task requirements

---

## Full Script Inventory

This repository represents 160+ production scripts across multiple categories:

### Script Categories by Function

- **Data Discovery & Validation** (23 scripts) - `find*` prefix - Identify data issues, missing records, generate reports
- **Data Correction & Updates** (19 scripts) - `fix*` prefix - Repair data integrity issues
- **Record Deletion & Cleanup** (21 scripts) - `delete*` prefix - Remove invalid, duplicate, or orphaned data
- **Business Logic Enforcement** (13 scripts) - `set*` prefix - Enforce business rules and update statuses
- **Field-Level Changes** (12 scripts) - `change*` prefix - Modify specific field values
- **Data Synchronization** (7 scripts) - `sync*` prefix - Ensure consistency across related records
- **Duplicate Merging** (8 scripts) - `merge*` prefix - Consolidate duplicate records
- **Record Purging & Archival** (6 scripts) - `purge*` prefix - Remove obsolete data systematically
- **Batch Updates** (9 scripts) - `update*` prefix - Bulk field modifications
- **Plus:** Clear (9), Remove (6), Reset (3), Revert (3), Add (3), Bulk operations with OOP integration

*Featured scripts above represent the most technically complex and business-impactful work.*

### Example Scripts by Category

**Data Discovery:**
- `findDuplicateTeeTimes.p` - Detect scheduling conflicts
- `findMissingCreditCardHistory.p` - Identify payment processing gaps
- `findOrphanedRecords.p` - Locate records with broken relationships
- `findReceiptPaymentWithWrongMemberID.p` - Research payment allocation issues

**Data Correction:**
- `fixCommonEmailDomainTypos.p` - Correct email typos (gmail.cmo → gmail.com)
- `fixHouseholdPhoneNumber.p` - Standardize phone number formatting
- `fixPrimaryGuardianRelationshipCode.p` - Correct family relationship data
- `fixPaymentMemberID.p` - Correct payment member allocation

**Record Cleanup:**
- `deleteDuplicateMailingAddressRecords.p` - Eliminate duplicate addresses
- `deleteOrphanedRecords.p` - Remove records with no parent relationships
- `deletePendingFees.p` - Clean up phantom fees from session state bug

**Business Logic:**
- `setActiveFamilyMemberToInactive_HHCheck.p` - Update member status based on household status
- `setDuplicateFeestoReset-ChargeStatusOnly.p` - Reset duplicate charge records
- `setNewHHToTaxable.p` - Apply tax status to new accounts

**OOP Integration:**
- `bulkSendWebInvite.p` - Bulk web invite sending using Business Objects (AccountBO, MemberBO, LinkBO, WebInvitesBO)

---

## About This Repository

These scripts represent 2.5 years of production database engineering work supporting 100+ enterprise customers. Each script solved real business problems, handled edge cases comprehensively, and prioritized data safety above all else.

The work demonstrated here includes:
- **Root cause analysis and debugging** - tracing issues through complex database relationships and application logic
- **Database relationship mastery** - understanding multi-table dependencies and data integrity constraints
- **Transaction safety and data integrity** - building defensive code with comprehensive rollback capabilities
- **Hybrid programming approach** - using OOP for business logic integration, procedural for database operations
- **Customer communication and trust-building** - managing expectations during high-impact data operations
- **Engineering collaboration** - providing detailed analysis that led to permanent application-level fixes
- **Production operations maturity** - building systems that enable team scaling without proportional headcount growth

### Key Takeaways

This repository demonstrates:

1. **Production Engineering Experience** - Code that runs on real systems with real customer data
2. **Safety-First Approach** - Transaction management, comprehensive logging, dry-run validation, rollback capabilities
3. **Paradigm Flexibility** - Using OOP for business logic, procedural for database operations, choosing appropriately per task
4. **Problem-Solving Ability** - Original algorithm design (fraud detection), complex multi-table operations
5. **Iterative Improvement** - Scripts evolved through production use and edge case discovery
6. **Business Impact** - Automated hundreds of hours of manual work, prevented data corruption, enabled fraud mitigation
7. **Growth Trajectory** - Clear progression from guided work (2022) to independent complex systems (2024-2025)

**Want to see more?** Check out my other projects demonstrating modern tech stacks:
- [GoalsTracker](http://github.com/michaelzrork/GoalsTracker) - C# / ASP.NET Core Razor Pages
- [Rebrickable WebView](http://github.com/michaelzrork/Rebrickable_WebView) - Android / Kotlin
- [Bag of Holding](http://github.com/michaelzrork/BagOfHolding) - Python / CustomTkinter

---

## Contact

**Michael Rork**  
📧 michaelzrork@gmail.com  
💼 [LinkedIn](http://linkedin.com/in/michaelzrork)  
📍 South Burlington, VT

Currently seeking Backend Engineer or Software Developer roles in Vermont or remote.
