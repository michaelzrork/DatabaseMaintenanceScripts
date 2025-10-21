#!/bin/bash
echo "=== FINAL SANITIZATION PASS ==="

find . -name "*.p" -type f | while read file; do
    echo "Processing: $file"
    
    # 1. Household → Account (in comments, strings, but preserve "Family Member" with space)
    sed -i 's/\bHousehold\b/Account/g' "$file"
    sed -i 's/\bhousehold\b/account/g' "$file"
    sed -i 's/HOUSEHOLD/ACCOUNT/g' "$file"
    
    # 2. Variable names with HH prefix/suffix
    sed -i 's/\bmergeHHnum\b/mergeAccountNum/g' "$file"
    sed -i 's/\borigHHnum\b/origAccountNum/g' "$file"
    sed -i 's/\bdupeHHnum\b/dupeAccountNum/g' "$file"
    sed -i 's/\bFromHHNumber\b/FromAccountNumber/g' "$file"
    sed -i 's/\bToHHNumber\b/ToAccountNumber/g' "$file"
    sed -i 's/\bFromHHID\b/FromAccountID/g' "$file"
    sed -i 's/\bToHHID\b/ToAccountID/g' "$file"
    sed -i 's/\bhhID\b/accountID/g' "$file"
    sed -i 's/\bhhNum\b/accountNum/g' "$file"
    sed -i 's/\bHHNumber\b/AccountNumber/g' "$file"
    sed -i 's/\bHHID\b/AccountID/g' "$file"
    
    # 3. HH in comments and strings (various contexts)
    sed -i 's/\bHH Num\b/Account Num/g' "$file"
    sed -i 's/\bHH Number\b/Account Number/g' "$file"
    sed -i 's/\bHH Name\b/Account Name/g' "$file"
    sed -i 's/\bHH ID\b/Account ID/g' "$file"
    sed -i 's/ HH / Account /g' "$file"
    
    # 4. Variable names with FM prefix/suffix  
    sed -i 's/\borigFMID\b/origMemberID/g' "$file"
    sed -i 's/\bdupeFMID\b/dupeMemberID/g' "$file"
    sed -i 's/\bfromFMID\b/fromMemberID/g' "$file"
    sed -i 's/\btoFMID\b/toMemberID/g' "$file"
    sed -i 's/\bmergeFMID\b/mergeMemberID/g' "$file"
    
    # 5. FM in comments and procedure names
    sed -i 's/\bmergeFM\b/mergeMember/g' "$file"
    sed -i 's/\bFMAdjustments\b/MemberAdjustments/g' "$file"
    sed -i 's/ FM / Member /g' "$file"
    sed -i 's/duplicate FM /duplicate member /g' "$file"
    sed -i 's/Duplicate FM /Duplicate member /g' "$file"
    
    # 6. familymember (no space) → member
    sed -i 's/\bfamilymember\b/member/g' "$file"
    sed -i 's/\bFamilymember\b/Member/g' "$file"
    
    # 7. Raw3ac → ProcessQueue (generic temp processing table)
    sed -i 's/\bRaw3ac\b/ProcessQueue/g' "$file"
    sed -i 's/deleteRaw3ac/deleteProcessQueue/g' "$file"
    sed -i 's/clearRaw3acTable/clearProcessQueueTable/g' "$file"
    
    # 8. RecTrac/WebTrac → RecPortal/WebPortal
    sed -i 's/\bRecTrac\b/RecPortal/g' "$file"
    sed -i 's/\bWebTrac\b/WebPortal/g' "$file"
    sed -i 's/\bRecTracMobile\b/RecPortalMobile/g' "$file"
    sed -i 's/\bWebTracMobile\b/WebPortalMobile/g' "$file"
    
    # 9. deleteSACrossReference → deleteEntityLink
    sed -i 's/deleteSACrossReference/deleteEntityLink/g' "$file"
    sed -i 's/deleteSACrossReferenceForInactiveMembers/deleteEntityLinkForInactiveMembers/g' "$file"
    
    # 10. Specific string replacements in log headers
    sed -i 's/"Member ID,HH Num"/"Member ID,Account Num"/g' "$file"
    sed -i 's/"HH Name"/"Account Name"/g' "$file"
done

echo "=== FINAL SANITIZATION COMPLETE ==="
