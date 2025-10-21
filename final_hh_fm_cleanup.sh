#!/bin/bash
echo "Cleaning up remaining HH and FM patterns..."

find . -name "*.p" -type f | while read file; do
    # HH in variable names
    sed -i 's/\bnumHHEmailsCleared\b/numAccountEmailsCleared/g' "$file"
    sed -i 's/\bsyncHHEmailtoPrimaryGuardian\b/syncAccountEmailtoPrimaryGuardian/g' "$file"
    sed -i 's/\bsyncHHPhoneToPrimaryGuardian\b/syncAccountPhoneToPrimaryGuardian/g' "$file"
    sed -i 's/\bsyncHHCategoryAndFeecodeByZip\b/syncAccountCategoryAndFeecodeByZip/g' "$file"
    sed -i 's/\bHHDRbal\b/AccountDRbal/g' "$file"
    sed -i 's/\bHHCRbal\b/AccountCRbal/g' "$file"
    
    # FM in variable names
    sed -i 's/\bnumFMEmailsCleared\b/numMemberEmailsCleared/g' "$file"
    sed -i 's/\bttFMName\b/ttMemberName/g' "$file"
    sed -i 's/\bFMadjustments\b/MemberAdjustments/g' "$file"
done

echo "Done!"
