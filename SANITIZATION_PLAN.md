# Repository Sanitization Plan

## Overview
This document outlines all naming convention updates needed to remove vendor-specific terminology and replace with generic database terms.

---

## Table Name Mappings

### Core Tables
| Old Name | New Name | Rationale |
|----------|----------|-----------|
| `SAHousehold` | `Account` | Generic account/customer entity |
| `SAPerson` | `Member` | Generic member/user entity |
| `SAEmailAddress` | `EmailContact` | Generic email contact entity |
| `SALink` | `Relationship` | Generic relationship/association |
| `SAFee` | `Charge` | Generic charge/fee entity |
| `SAFeeHistory` | `ChargeHistory` | Generic charge history |
| `SADetail` | `TransactionDetail` | Generic transaction detail |
| `SAReceipt` | `PaymentReceipt` | Generic payment receipt |
| `SAReceiptpayment` | `PaymentTransaction` | Generic payment transaction |
| `SAControlAccountHistory` | `AccountBalanceLog` | Generic account balance log |
| `SAGLDistribution` | `LedgerEntry` | Generic GL/ledger entry |
| `SABillingDetail` | `BillingStatement` | Generic billing statement |
| `SAProfileField` | `CustomField` | Generic custom field |
| `SACrossReference` | `EntityLink` | Generic entity link/xref |
| `SAAddress` | `MailingAddress` | Generic mailing address |
| `SABlobfile` | `BinaryFile` | Generic binary file storage |
| `SADocument` | `Document` | Generic document entity |
| `SAEmergencyContact` | `EmergencyContact` | Generic emergency contact |
| `SACreditCardHistory` | `CardTransactionLog` | Generic CC transaction log |
| `SAAnswer` | `Response` | Generic response/answer |
| `SAConflict` | `Conflict` | Generic conflict entity |
| `SASearchIndex` | `SearchCache` | Generic search cache |

---

## Procedure Name Updates

### Pattern: `SetSALink` → `SetRelationship`
**Files affected:**
- `mergeDuplicateFMs.p` (line 135)
- `mergeDuplicateFMFromXRef.p` (line 125)
- `mergeGuestHouseholdFamilyMembers.p` (line 149)

**Example change:**
```progress
// BEFORE:
procedure SetSALink:
    define input parameter inpID as int64 no-undo.
    ...

// AFTER:
procedure SetRelationship:
    define input parameter inpID as int64 no-undo.
    ...
```

### Pattern: `createSAEmailaddress` → `createEmailContact`
**Files affected:**
- `syncHHEmailtoPrimaryGuardian.p` (line 134)
- `fixCommonEmailDomainTypos.p` (line 276)
- `myDumbEmailThing.p` (line 287)
- `changeEmailAddressesToBlackList.p` (multiple)

**Example change:**
```progress
// BEFORE:
procedure createSAEmailaddress:
    define input parameter i64ParentID as int64 no-undo.
    ...

// AFTER:
procedure createEmailContact:
    define input parameter i64ParentID as int64 no-undo.
    ...
```

### Pattern: `deleteSA*` → `delete*` (specific entity)
**Files affected:**
- `cancelFacilityReservation.p`: `deleteSAFeeHistory` → `deleteChargeHistory`
- `cancelFacilityReservation.p`: `DeleteSAFee` → `deleteCharge`
- `cancelFacilityReservation.p`: `deleteSAConflict` → `deleteConflict`
- `cancelFacilityReservation.p`: `deleteSABillingDetail` → `deleteBillingStatement`
- `cancelFacilityReservation.p`: `purgeSAAnswer` → `purgeResponse`
- `deleteEntityLink.p`: `deleteSACrossReference` → `deleteEntityLink`
- `deleteOrphanedRecords.p`: `deleteSALink` → `deleteRelationship`
- `deleteOrphanedRecords.p`: `deleteSAPerson` → `deleteMember`
- `deleteOrphanedRecords.p`: `deleteSAHousehold` → `deleteAccount`
- `deletePendingFees.p`: `deleteSAReceipt` → `deletePaymentReceipt`
- `deletePendingFees.p`: `fixSADetail` → `fixTransactionDetail`
- `deletePendingFees.p`: `DeleteSAFeeHistory` → `deleteChargeHistory`
- `deletePendingFees.p`: `LogSAFeeHistory` → `logChargeHistory`
- `deletePendingFees.p`: `deleteSAFee` → `deleteCharge`
- `deleteEntityLinkForInactiveMembers.p`: `deleteSACrossReference` → `deleteEntityLink`
- `updatePrimaryGuardianRelationshipCode.p`: `deleteSALink` → `deleteRelationship`
- `updatePrimaryGuardianRelationshipCode.p`: `deleteSAHousehold` → `deleteAccount`
- `updatePrimaryGuardianRelationshipCode.p`: `deleteSAPerson` → `deleteMember`
- `closePaymentReceiptInProcess.p`: `deleteSAReceiptpayment` → `deletePaymentTransaction`
- `closePaymentReceiptInProcess.p`: `deleteSAControlAccountHistory` → `deleteAccountBalanceLog`
- `deleteDuplicateCustomFieldRecords.p`: `deleteSAProfileField` → `deleteCustomField`

### Pattern: `updateSA*` → `update*`
**Files affected:**
- `deletePendingFeeHistory-Fix 1069246.p`: `updateSAFee` → `updateCharge`
- `deletePendingFeeHistoryWithNoReceipt.p`: `updateSAFee` → `updateCharge`
- `mergeGuestHouseholdFamilyMembers.p`: `UpdateSAEmergencyContact` → `updateEmergencyContact`
- `mergeGuestHouseholdFamilyMembers.p`: `updateLeagueSALink` → `updateLeagueRelationship`
- `mergeGuestHouseholdFamilyMembers.p`: `UpdateSACreditCardHistory` → `updateCardTransactionLog`
- `mergeGuestHouseholdFamilyMembers.p`: `UpdateSADocument` → `updateDocument`
- `mergeGuestHouseholdFamilyMembers.p`: `UpdateSABlobFile` → `updateBinaryFile`
- `mergeGuestHouseholdFamilyMembers.p`: `DeleteSABlobFile` → `deleteBinaryFile`
- `mergeGuestHouseholdFamilyMembers.p`: `UpdateSAHouseholdAddress` → `updateMailingAddress`

### Pattern: `purgeSA*` → `purge*`
**Files affected:**
- `purgeMailingAddress.p`: `purgeSAAddress` → `purgeMailingAddress`
- `purgeMailingAddress.p`: `purgeSAHouseholdAddress` → `purgeMailingAddress`
- `purgeMailingAddressRecordsWithNoAccountLink.p`: `purgeSAAddress` → `purgeMailingAddress`
- `purgeMailingAddressRecordsWithNoAccountLink.p`: `purgeSAHouseholdAddress` → `purgeMailingAddress`

### Pattern: `removeSA*` → `remove*`
**Files affected:**
- `removeDuplicateFamilyMemberEmail.p`: `removeDupelicateSAPersonEmail` → `removeDuplicateMemberEmail`
- `removeDuplicateFamilyMemberEmail.p`: `deleteSAEmailAddressRecord` → `deleteEmailContact`
- `clearMyDumbEmails.p`: `removeSAPersonEmail` → `removeMemberEmail`
- `clearMyDumbEmails.p`: `removeSAHouseholdEmail` → `removeAccountEmail`
- `clearMyDumbEmails.p`: `deleteSAEmailAddressRecord` → `deleteEmailContact`

### Pattern: `adjustSALinks` → `adjustRelationships`
**Files affected:**
- `mergeGuestHouseholdFamilyMembers.p` (line 320)

---

## Loop Label Updates

### Pattern: `salink-loop` → `relationship-loop`
**Files affected:**
- `mergeDuplicateFMs.p` (line 83, 89)
- `deleteOrphanedRecords.p` (line 92)

**Example change:**
```progress
// BEFORE:
salink-loop:
for each Relationship no-lock:
    if not available Member then next salink-loop.
end.

// AFTER:
relationship-loop:
for each Relationship no-lock:
    if not available Member then next relationship-loop.
end.
```

### Pattern: `saxref-loop` → `entitylink-loop`
**Files affected:**
- `mergeGuestHouseholdFamilyMembers.p` (line 1848)

### Pattern: `SALinkLoop` → `RelationshipLoop`
**Files affected:**
- `removeDuplicateFamilyMemberEmail.p` (line 60)

---

## Buffer Definition Updates

### Pattern: `buf*SALink` → `buf*Relationship`
**Files affected:**
- `changeWebUserNameToPrimary_LogOnly.p`:
  - `bufChildSALink` → `bufChildRelationship`
  - `bufParentSALink` → `bufParentRelationship`
- `changeWebUserNameToPrimary.p`:
  - `bufChildSALink` → `bufChildRelationship`
  - `bufParentSALink` → `bufParentRelationship`

### Pattern: `buf*SAHousehold` → `buf*Account`
**Files affected:**
- `mergeGuestHouseholdFamilyMembers.p`:
  - `bufToSAHousehold` → `bufToAccount`
  - `bufFromSAHousehold` → `bufFromAccount`

### Pattern: `bufBlobfile` → `bufBinaryFile`
**Files affected:**
- `mergeGuestHouseholdFamilyMembers.p` (line 1239): `bufBlobfile for SABlobfile` → `bufBinaryFile for BinaryFile`

---

## Business Logic Program References

### Pattern: `Business/HouseholdMerge.p` → `Business/MergeAccounts.p`
**Files affected:**
- `mergeDuplicateFMs.p` (multiple calls)
- `mergeDuplicateFMFromXRef.p` (multiple calls)
- `mergeGuestHouseholdFamilyMembers.p` (if present)

**Example change:**
```progress
// BEFORE:
setData("HouseholdMerge_FromHousehold", string(mergeHHnum)).
setData("HouseholdMerge_ToHousehold", string(mergeHHnum)).
run Business/HouseholdMerge.p.

// AFTER:
setData("AccountMerge_FromAccount", string(mergeAccountNum)).
setData("AccountMerge_ToAccount", string(mergeAccountNum)).
run Business/MergeAccounts.p.
```

### Pattern: `Business/SADetailFeeCalc.p` → `Business/CalculateTransactionTotal.p`
**Files affected:**
- `deletePendingFees.p` (line 462)

**Example change:**
```progress
// BEFORE:
run Business/SADetailFeeCalc.p ("TransactionDetail", "TotalDue", ?, "", "", TransactionDetail.ID, output TotalDue).

// AFTER:
run Business/CalculateTransactionTotal.p ("TransactionDetail", "TotalDue", ?, "", "", TransactionDetail.ID, output TotalDue).
```

### Pattern: `Business/DeleteSACriteria.p` → `Business/DeleteFilter.p`
**Files affected:**
- Multiple files with filter/criteria deletion

### Pattern: `Business/SpecialSessionEnd.p` → `Business/EndSession.p`
**Files affected:**
- `endSessions.p`

---

## Include File Updates

### Pattern: `{Includes/ttHouseholdMerge.i}` → `{Includes/ttAccountMerge.i}`
**Files affected:**
- `mergeDuplicateFMs.p`
- `mergeDuplicateFMFromXRef.p`

**Example change:**
```progress
// BEFORE:
{Includes/ttHouseholdMerge.i}

// AFTER:
{Includes/ttAccountMerge.i}
```

---

## Comment Updates

### Pattern: Comments with old table names
**Search patterns:**
- `SAHOUSEHOLD` → `ACCOUNT`
- `SAPERSON` → `MEMBER`
- `SAEMAILADDRESS` → `EMAILCONTACT`
- `SALINK` → `RELATIONSHIP`

**Files to check:** ALL .p files

**Example change:**
```progress
// BEFORE:
/* SYNC SAPERSON EMAIL WITH SAHOUSEHOLD IF OUT OF SYNC */

// AFTER:
/* SYNC MEMBER EMAIL WITH ACCOUNT IF OUT OF SYNC */
```

---

## setData() Parameter Updates

### Pattern: `HouseholdMerge_*` → `AccountMerge_*`
**Files affected:**
- `mergeDuplicateFMs.p`
- `mergeDuplicateFMFromXRef.p`

**Parameters to update:**
```progress
// BEFORE:
setData("HouseholdMerge_FromHousehold", ...)
setData("HouseholdMerge_ToHousehold", ...)
setData("FamilyMemberMerge_FamilyFromGrid", ...)

// AFTER:
setData("AccountMerge_FromAccount", ...)
setData("AccountMerge_ToAccount", ...)
setData("MemberMerge_MemberFromGrid", ...)
```

---

## Variable Name Updates

### Pattern: `mergeHHnum` → `mergeAccountNum`
**Files affected:**
- `mergeDuplicateFMs.p`
- Related merge scripts

### Pattern: `hhID` → `accountID`
**Files affected:**
- Multiple scripts using household ID variables

### Pattern: `fmID` → `memberID`
**Files affected:**
- Multiple scripts using family member ID variables

---

## Estimated Impact by File Category

### **HIGH PRIORITY** (Files in GIST documentation):
1. ✅ `InactivateBadActorHHs_Today-7.p` - Minimal changes (variables only)
2. ✅ `deleteDuplicateSearchCache.p` - No SA* naming found
3. ⚠️ `mergeDuplicateFMs.p` - **NEEDS MAJOR UPDATES**
   - `SetSALink` → `SetRelationship`
   - `salink-loop` → `relationship-loop`
   - `Business/HouseholdMerge.p` → `Business/MergeAccounts.p`
   - `{Includes/ttHouseholdMerge.i}` → `{Includes/ttAccountMerge.i}`
   - All HouseholdMerge setData parameters
4. ⚠️ `fixCommonEmailDomainTypos.p` - **NEEDS UPDATES**
   - `createSAEmailaddress` → `createEmailContact`
   - Buffer name `bufAccount for SAhousehold` → `bufAccount for Account`
   - Comments
5. ⚠️ `syncHHEmailtoPrimaryGuardian.p` - **NEEDS UPDATES**
   - `createSAEmailaddress` → `createEmailContact`
   - Comments with SAPERSON/SAHOUSEHOLD

### **MEDIUM PRIORITY** (Supporting scripts):
- `mergeDuplicateFMFromXRef.p`
- `mergeGuestHouseholdFamilyMembers.p` (extensive updates needed)
- `changeWebUserNameToPrimary.p`
- `deleteOrphanedRecords.p`
- `deletePendingFees.p`

### **LOW PRIORITY** (Other scripts):
- All other 165+ scripts with minor SA* references

---

## Recommended Sanitization Sequence

### Phase 1: Core Scripts (for GIST documentation)
1. `mergeDuplicateFMs.p`
2. `fixCommonEmailDomainTypos.p`
3. `syncHHEmailtoPrimaryGuardian.p`

### Phase 2: Supporting Scripts
4. `mergeDuplicateFMFromXRef.p`
5. `changeWebUserNameToPrimary.p`
6. `deleteOrphanedRecords.p`

### Phase 3: Remaining Scripts
7. Batch update all other scripts using find/replace

---

## Testing Strategy

After each update:
1. ✅ Verify syntax (no compile errors)
2. ✅ Check procedure names are consistent
3. ✅ Verify loop labels match their jumps
4. ✅ Check buffer definitions match table usage
5. ✅ Update GIST documentation files

---

## Question for Review

**Should we sanitize Business/* program names?**

**Option A: Sanitize (recommended)**
```progress
run Business/MergeAccounts.p.
run Business/CalculateTransactionTotal.p.
run Business/DeleteFilter.p.
run Business/EndSession.p.
```
- ✅ Pro: Completely vendor-agnostic
- ❌ Con: These programs don't exist (they're references to proprietary code)
- ⚠️ Impact: Makes it clear these are "example/reference" calls

**Option B: Keep as generic placeholders**
```progress
run Business/HouseholdMerge.p.  // Reference to proprietary merge logic
run Business/SADetailFeeCalc.p. // Reference to proprietary calculation
```
- ✅ Pro: Shows integration with existing system
- ❌ Con: Still contains vendor naming (SA*)
- ⚠️ Impact: Might confuse readers about what's real vs. example

**Option C: Comment them as external**
```progress
run Business/MergeAccounts.p.  /* External business logic API */
run Business/CalculateTransactionTotal.p.  /* External calculation service */
```
- ✅ Pro: Clear these are external dependencies
- ✅ Pro: Uses sanitized names
- ✅ Pro: Shows architectural separation

**Recommendation: Option C** - Sanitize the names AND add comments clarifying they're external APIs.

---

## Next Steps

**Please review and approve:**
1. ✅ Do the table name mappings look correct?
2. ✅ Should we update Business/* program names (see question above)?
3. ✅ Are there any other naming patterns you want to change?
4. ✅ Should we tackle this in phases or all at once?

**Once approved, I will:**
1. Update the 5 GIST files first (Phase 1)
2. Update supporting scripts (Phase 2)
3. Batch update remaining scripts (Phase 3)
4. Commit all changes with detailed commit message
