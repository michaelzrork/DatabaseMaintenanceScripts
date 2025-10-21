/*------------------------------------------------------------------------
    File        : syncHHCategoryAndFeecodeByZip.p
    Purpose     : 

    Syntax      : 

    Description : Sync Household Category and Feecode by Zip Code

    Author(s)   : michaelzr
    Created     : 2/28/25
    Notes       : - This is a rewritten version of updateCategoryegoryandFeeCodebyZip that is intended to be a universal fix
                  - Unlike the original version, this will create a logfile of changed households and family members
                  - Will skip updating Family Member categories and fee codes if the Household profile value is set to "Do Not Sync Family Members"
                    (Profile Assignments > Household profile > "Family Member Option: If The Household Category Changes, On Save:")
                  - Will set the Non-Resident category to what the NoZipMatchCategory is set to
                    (Profile Assignments > Static Parameters > "Default Category If No Address Check Match")
                    - Will default to the NoZipMatchCategory when the category is missing, the zip code is missing, or the address record category cannot be found
                  - Will skip all Guest, Internal, and Model households
                  - Before updating any familiy members where the household category matches the NoZipMatchCategory it will check if the family member
                    is in any Active, non-NoZipMatchCategory households; if they are, it will not update the family member since they will be updated to a Resident category
                    when that household is run (we don't want to change family members back and forth, so we default to not the Non Res categories
                    
                  Todo list:
                    - Add Teams logic and procedure
                  
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo. 
define variable logfileDate as date      no-undo.
define variable logfileTime as integer   no-undo. 

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time.

// EVERYTHING ELSE
define variable numHHCatRecs       as integer   no-undo.
define variable numFMCatRecs       as integer   no-undo.
define variable numHHFeecodeRecs   as integer   no-undo.
define variable numFMFeecodeRecs   as integer   no-undo.
define variable noZipMatchCategory as character no-undo.
define variable hhCheck            as logical   no-undo.
define variable hhID               as int64     no-undo.
define variable hhNum              as integer   no-undo.
define variable hhCategory         as character no-undo.
define variable hhFeecodes         as character no-undo.
define variable fmID               as int64     no-undo.
define variable fmCategory         as character no-undo.
define variable fmFeecodes         as character no-undo.
define variable recCount           as integer   no-undo.
define variable newCategory        as character no-undo.
define variable skipHouseholds     as character no-undo.
define variable ix                 as integer   no-undo.

assign
    numHHCatRecs       = 0
    numFMCatRecs       = 0
    numHHFeecodeRecs   = 0
    numFMFeecodeRecs   = 0
    noZipMatchCategory = TrueVal(ProfileChar("Static Parameters","NoZipMatchCategory"))
    hhCheck            = no
    hhID               = 0
    hhNum              = 0
    hhCategory         = ""
    hhFeeCodes         = ""
    fmID               = 0
    fmCategory         = ""
    fmFeeCodes         = ""
    recCount           = 0
    newCategory        = ""
    skipHouseholds     = "999999999".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CHECK IS THERE ARE ADDRESSES IN ADDRESS MANAGEMENT */
find first MailingAddress no-lock no-error no-wait.
if not available MailingAddress then
do:
    run ActivityLog("Program Aborted","There are no MailingAddress records available. Cannot sync Household Category. Add addresses in Address Management and run this program again.","","").
    return.
end.

/* CHECK THAT A NO ZIP CODE MATCH CATEGORY IS SET */
if noZipMatchCategory = "" then 
do:
    run ActivityLog("Program Aborted","There is no default Category set for no match zip codes. Set this value in Profile Assignments > Static Parameters > Misc Settings > ~"Default Category If No Address Check Match~" then run this program again.","","").
    return.
end.

/* CONFIRM THAT THE CATEGORY SET FOR THE NO MATCH CATEGORY IS VALID */
for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = noZipMatchCategory:
end.
if not available LookupCode then
do:
    run ActivityLog("Program Aborted","The default Category set for no match zip codes does not exist. Update this value in Profile Assignments > Static Parameters > Misc Settings > ~"Default Category If No Address Check Match~" then run this program again.","","").
    return.
end.
    
/* FIND ALL INTERNAL AND MODEL HOUSEHOLDS */
profilefield-loop:
for each CustomField no-lock where CustomField.FieldName = "InternalHousehold" or CustomField.FieldName begins "ModelHousehold":
    if getString(CustomField.FieldValue) = "" then next profilefield-loop.
    do ix = 1 to num-entries(getString(CustomField.FieldValue)):
        skipHouseholds = uniquelist(entry(ix,getString(CustomField.FieldValue)),skipHouseholds,",").
    end. 
end.

/* CREATE LOG FILE FIELD HEADERS */
run put-stream ("Table,Record ID,Household Number,Zip Code,Original Category,New Category,Original Fee Code List,New Fee Code List,").

/* HOUSEHOLD LOOP */
HH-loop:
for each Account no-lock:
    
    /* IF THE HOUSEHOLD IS THE GUEST HOUSEHOLD OR AN INTERNAL OR MODEL HOUSEHOLD, SKIP */
    if lookup(string(Account.EntityNumber),skipHouseholds) > 0 then next HH-loop.
    
    assign 
        hhID        = Account.ID
        hhNum       = Account.EntityNumber
        hhCategory  = getString(Account.Category)
        hhFeeCodes  = getString(Account.CodeValue)
        newCategory = "".
        
    /* SET NEW CATEGORY */
    if not isEmpty(Account.PrimaryZipCode) then 
    do:
        find first MailingAddress no-lock where MailingAddress.ZipCode = Account.PrimaryZipCode no-error no-wait.
        if not available MailingAddress then find first MailingAddress no-lock where MailingAddress.ZipCode = substring(Account.PrimaryZipCode,1,5) no-error no-wait.
        
        if available MailingAddress then 
        do:
            for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = MailingAddress.Category:
                assign
                    newCategory = getString(MailingAddress.Category).
            end.
            if not available LookupCode then 
                assign
                    newCategory = noZipMatchCategory.
        end.
        else 
            assign 
                newCategory = noZipMatchCategory.
    end.
    else 
        assign
            newCategory = noZipMatchCategory.

    /* SYNC HH CATEGORY AND FEE CODES */          
    if hhCategory <> newCategory then run syncHHCat(yes).
    else run syncHHCat(no).
   
    /* CHECK FAMILY MEMBER CATEGORY SYNC OPTION FROM PROFILE AND SKIP FAMILY MEMBER SYNC IF SET TO NOT SYNC */
    if TrueVal(ProfileChar("Household","CategorySyncOption")) = "Do Not Sync Family Members" then next HH-loop.
    
    FM-loop:
    for each Relationship no-lock where Relationship.ParentTableID = hhID and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
        
        /* RESET HH CHECK */
        assign 
            hhCheck = no.
        
        /* CHECK FAMILY MEMBER FOR ADDITIONAL HOUSEHOLDS IF A NON-RESIDENT CATEGORY */
        if newCategory = noZipMatchCategory then run additionalHHCheck(Relationship.ChildTableID).
        
        /* IF ANOTHER ACTIVE, RESIDENT HH IS FOUND, SKIP THIS FAMILY MEMBER */
        if hhCheck = yes then next FM-loop.
        
        /* FIND MEMBER RECORD TO CHECK CATEGORY AND FEE CODES */
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
        if available Member then 
        do:
            assign
                fmID       = Member.ID
                fmCategory = Member.Category
                fmFeeCodes = Member.CodeValue.
                
            /* SYNC CATEGORY AND FEE CODES */
            if fmCategory <> newCategory then run syncFMCat(yes).
            else run syncFMCat(no).
        end.
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "syncHHCategoryAndFeecodeByZipLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "syncHHCategoryAndFeecodeByZipLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog("Sync Household Category and Feecode by Zip Code","Check Document Center for syncHHCategoryAndFeecodeByZipLog for a log of Records Changed","Number of HH Categories updated: " + string(numHHCatRecs) + "; Number of HH Feecodes updated: " + string(numHHFeecodeRecs) + "; Number of FM Categories updated: " + string(numFMCatRecs) + "; Number of FM Feecodes updated: " + string(numFMFeecodeRecs),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* SYNC HOUSEHOLD CATEGORY AND FEECODE */
procedure syncHHCat:
    define input parameter updateCategory as logical no-undo.
    define variable oldCategory      as character no-undo.
    define variable oldFeeCodeList   as character no-undo.
    define variable feeCodesToRemove as character no-undo.
    define variable feeCodesToAdd    as character no-undo.
    define variable ix               as integer   no-undo.
    define variable iy               as integer   no-undo.
    define variable feeCodesRemoved  as logical   no-undo.
    define variable feeCodesAdded    as logical   no-undo.
    define buffer bufAccount for Account.
    
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = hhID no-error no-wait.
        if available bufAccount then 
        do: 
            assign
                oldFeeCodeList   = getString(bufAccount.CodeValue)
                oldCategory      = getString(bufAccount.Category)
                feeCodesRemoved  = false
                feeCodesAdded    = false
                feeCodesToRemove = ""
                feeCodesToAdd    = "".
                            
            /* UPDATE THE HOUSEHOLD CATEGORY */
            if updateCategory then 
            do: 
                assign
                    bufAccount.Category = newCategory.
                    
                /* CREATE LIST OF FEE CODES TO REMOVE FROM DEFAULT FEE CODES OF OLD CATEGORY */
                for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = oldCategory:
                    assign 
                        feeCodesToRemove = getString(LookupCode.DefaultFeeCodes).
                end.
                if not available LookupCode then updateCategory = false.
            end.
            
            /* IF NOT UPDATING THE CATEGORY, CREATE LIST OF FEE CODES TO REMOVE FROM DEFAULT FEE CODES OF ALL CATEGORIES OTHER THAN THE CURRENT ONE */
            if not updateCategory then 
            do:
                for each LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode <> newCategory:
                    do ix = 1 to num-entries(LookupCode.DefaultFeeCodes):
                        assign 
                            feeCodesToRemove = uniqueList(entry(ix,LookupCode.DefaultFeeCodes),feeCodesToRemove,",").
                    end.
                end.
            end.
            
            /* CREATE LIST OF FEE CODES TO ADD FROM DEFAULT FEE CODES OF NEW CATEGORY */
            for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = newCategory:
                assign
                    feeCodesToAdd = (if getString(LookupCode.DefaultFeeCodes) = "" then "No Default Fee Codes Set" else getString(LookupCode.DefaultFeeCodes)).
            end.
            
            /* REMOVE ALL OLD FEE CODES */
            if feeCodesToRemove <> "" then 
            do ix = 1 to num-entries(feeCodesToRemove):
                if lookup(entry(ix,feeCodesToRemove),bufAccount.CodeValue) > 0 then
                    assign 
                        bufAccount.CodeValue = removeList(entry(ix,feeCodesToRemove),bufAccount.CodeValue)
                        feeCodesRemoved        = true.
            end.
            
            /* ADD THE NEW FEE CODES */
            if feeCodesToAdd <> "" and feeCodesToAdd <> "No Default Fee Codes Set" then 
            do iy = 1 to num-entries(getString(feeCodesToAdd)):
                if lookup(entry(iy,feeCodesToAdd),bufAccount.CodeValue) = 0 then
                    assign
                        bufAccount.CodeValue = uniquelist(entry(iy,feeCodesToAdd),bufAccount.CodeValue,",")
                        feeCodesAdded          = true.
            end.
            
            /* IF CHANGES WERE MADE, CREATE LOGFILE ENTRY */
            if bufAccount.Category <> oldCategory or bufAccount.CodeValue <> oldFeeCodeList then 
            do:
                assign 
                    numHHCatRecs     = numHHCatRecs + (if bufAccount.Category <> oldCategory then 1 else 0)
                    numHHFeeCodeRecs = numHHFeeCodeRecs + (if feeCodesRemoved or feeCodesAdded then 1 else 0).
                run put-stream("~"" +
                    /*Table*/
                    "Account"
                    + "~",~"" +
                    /*Record ID*/
                    getString(string(hhID))
                    + "~",~"" +
                    /*Household Number*/
                    getString(string(hhNum))
                    + "~",~"" +
                    /*Zip Code*/
                    getString(string(bufAccount.PrimaryZipCode))
                    + "~",~"" +
                    /*Original Category*/
                    (if oldCategory = "" then "No Category Set" else oldCategory)
                    + "~",~"" +
                    /*New Category*/
                    (if bufAccount.Category = oldCategory then "No Change" else getString(bufAccount.Category))
                    + "~",~"" +
                    /*Original Fee Code List*/
                    (if oldFeeCodeList = "" then "No Fee Codes Set" else oldFeeCodeList)
                    + "~",~"" +
                    /*New Fee Code List*/
                    trim((if bufAccount.CodeValue = oldFeeCodeList then "No Change" else getString(bufAccount.CodeValue)) + (if feeCodesToAdd = "No Default Fee Codes Set" then "; No Default Fee Codes Set" else ""),"; ")
                    + "~",").
            end.
        end.
    end.
end procedure.

    
/* SYNC FAMILY MEMBER CATEGORY AND FEECODE */
procedure syncFMCat:
    define input parameter updateCategory as logical no-undo.
    define variable oldCategory      as character no-undo.
    define variable oldFeeCodeList   as character no-undo.
    define variable feeCodesToRemove as character no-undo.
    define variable feeCodesToAdd    as character no-undo.
    define variable ix               as integer   no-undo.
    define variable iy               as integer   no-undo.
    define variable feeCodesRemoved  as logical   no-undo.
    define variable feeCodesAdded    as logical   no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = fmID no-error no-wait.
        if available bufMember then 
        do: 
            assign
                oldFeeCodeList   = getString(bufMember.CodeValue)
                oldCategory      = getString(bufMember.Category)
                feeCodesRemoved  = false
                feeCodesAdded    = false
                feeCodesToRemove = ""
                feeCodesToAdd    = "".
                            
            /* UPDATE THE HOUSEHOLD CATEGORY */
            if updateCategory then 
            do: 
                assign
                    bufMember.Category = newCategory.
                    
                /* CREATE LIST OF FEE CODES TO REMOVE FROM DEFAULT FEE CODES OF OLD CATEGORY */
                for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = oldCategory:
                    assign 
                        feeCodesToRemove = getString(LookupCode.DefaultFeeCodes).
                end.
                if not available LookupCode then updateCategory = false.
            end.
            
            /* IF NOT UPDATING THE CATEGORY, CREATE LIST OF FEE CODES TO REMOVE FROM DEFAULT FEE CODES OF ALL CATEGORIES OTHER THAN THE CURRENT ONE */
            if not updateCategory then 
            do:
                for each LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode <> newCategory:
                    do ix = 1 to num-entries(LookupCode.DefaultFeeCodes):
                        assign 
                            feeCodesToRemove = uniqueList(entry(ix,LookupCode.DefaultFeeCodes),feeCodesToRemove,",").
                    end.
                end.
            end.
            
            /* CREATE LIST OF FEE CODES TO ADD FROM DEFAULT FEE CODES OF NEW CATEGORY */
            for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = newCategory:
                assign
                    feeCodesToAdd = (if getString(LookupCode.DefaultFeeCodes) = "" then "No Default Fee Codes Set" else getString(LookupCode.DefaultFeeCodes)).
            end.
            
            /* REMOVE ALL OLD FEE CODES */
            if feeCodesToRemove <> "" then 
            do ix = 1 to num-entries(feeCodesToRemove):
                if lookup(entry(ix,feeCodesToRemove),bufMember.CodeValue) > 0 then
                    assign 
                        bufMember.CodeValue = removeList(entry(ix,feeCodesToRemove),bufMember.CodeValue)
                        feeCodesRemoved     = true.
            end.
            
            /* ADD THE NEW FEE CODES */
            if feeCodesToAdd <> "" and feeCodesToAdd <> "No Default Fee Codes Set" then 
            do iy = 1 to num-entries(getString(feeCodesToAdd)):
                if lookup(entry(iy,feeCodesToAdd),bufMember.CodeValue) = 0 then
                    assign
                        bufMember.CodeValue = uniquelist(entry(iy,feeCodesToAdd),bufMember.CodeValue,",")
                        feeCodesAdded       = true.
            end.
            
            /* IF CHANGES WERE MADE, CREATE LOGFILE ENTRY */
            if bufMember.Category <> oldCategory or bufMember.CodeValue <> oldFeeCodeList then 
            do:
                assign 
                    numFMCatRecs     = numFMCatRecs + (if bufMember.Category <> oldCategory then 1 else 0)
                    numFMFeeCodeRecs = numFMFeeCodeRecs + (if feeCodesRemoved or feeCodesAdded then 1 else 0).
                run put-stream("~"" +
                    /*Table*/
                    "Member"
                    + "~",~"" +
                    /*Record ID*/
                    getString(string(fmID))
                    + "~",~"" +
                    /*Household Number*/
                    getString(string(hhNum))
                    + "~",~"" +
                    /*Zip Code*/
                    (if getString(bufMember.PrimaryZipCode) <> "" then getString(string(bufMember.PrimaryZipCode)) else getString(Account.PrimaryZipCode))
                    + "~",~"" +
                    /*Original Category*/
                    (if oldCategory = "" then "No Category Set" else oldCategory)
                    + "~",~"" +
                    /*New Category*/
                    (if bufMember.Category = oldCategory then "No Change" else getString(bufMember.Category))
                    + "~",~"" +
                    /*Original Fee Code List*/
                    (if oldFeeCodeList = "" then "No Fee Codes Set" else oldFeeCodeList)
                    + "~",~"" +
                    /*New Fee Code List*/
                    (if bufMember.CodeValue = oldFeeCodeList then "No Change" else getString(bufMember.CodeValue)) + (if feeCodesToAdd = "No Default Fee Codes Set" then "; No Default Fee Codes Set" else "")
                    + "~",").
            end.
        end.
    end.
end procedure.

/* ADDITIONAL HOUSEHOLD CHECK */
procedure additionalHHCheck:
    define input parameter inpid as int64 no-undo.
    define buffer bufRelationship      for Relationship.
    define buffer bufAccount for Account.
    /* LOOK FOR PERSON IN ANY OTHER HOUSEHOLD */
    for each bufRelationship no-lock where bufRelationship.ChildTableID = inpid and bufRelationship.ChildTable = "Member" and bufRelationship.ParentTable = "Account" and bufRelationship.ParentTableID <> hhID while hhCheck = no:
        /* IF ADDITIONAL ACTIVE HOUSEHOLD IS FOUND THAT IS NOT A NON-RES HH, SKIP THIS PERSON AS THEY WILL BE UPDATED WITH THAT HH */ 
        if can-find(first bufAccount where bufAccount.ID = bufRelationship.ParentTableID and bufAccount.Category <> noZipMatchCategory and bufAccount.RecordStatus = "Active") then hhCheck = yes.
    end.
end procedure.


/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "syncHHCategoryAndFeecodeByZipLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 30000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.


/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "syncHHCategoryAndFeecodeByZip.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = logDetail1
            BufActivityLog.Detail2       = logDetail2
            BufActivityLog.Detail3       = logDetail3
            BufActivityLog.Detail4       = logDetail4.
    end.
end procedure.