#!/bin/bash
echo "Cleaning up remaining hh-prefixed variables..."

find . -name "*.p" -type f | while read file; do
    # Lowercase hh prefix variables
    sed -i 's/\bhhName\b/accountName/g' "$file"
    sed -i 's/\bhhStatus\b/accountStatus/g' "$file"
    sed -i 's/\bhhCheck\b/accountCheck/g' "$file"
    sed -i 's/\bhhCategory\b/accountCategory/g' "$file"
    sed -i 's/\bhhFeecodes\b/accountFeecodes/g' "$file"
    sed -i 's/\bhhFeeCode\b/accountFeeCode/g' "$file"
    sed -i 's/\bhhZip\b/accountZip/g' "$file"
    
    # Mixed case HH prefix variables
    sed -i 's/\bHHImportant\b/AccountImportant/g' "$file"
    sed -i 's/\bHHCheck\b/AccountCheck/g' "$file"
done

echo "Done!"
