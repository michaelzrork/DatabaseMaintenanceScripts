/*------------------------------------------------------------------------
    
    File        : updateCategoryandFeeCodebyZip.p 
    Purpose     : To sync all households and family member catetorgies and feecodes by zip 

    Syntax      : 

    Description : Uses the Address Table to match the correct category and feecode to all
                  households, family members, and teams, based on the zip code

    Author(s)   : michaelzrork
    Created     : late 2022/early2023
    Notes       : - This will only work if there are only two cateogories: Res and Non-res, and they must be defined (and are case sensitive)         
                  03/10/23 - Updated to do hhCheck on Family Members in Non-Resident HHs so that if they are also linked to a Resident HH they are not changed to Non-Res         
                  06/14/23 - Added logic to work with zip+4, checking just the first 5 of the zip code using substring
                  02/29/24 - Minor tweaks to the code, added lookup for Non-Res category from static parameters
                  
                  
                  ***************** THIS PROGRAM HAS BEEN REPLACED BY SYNCHHCATEGORYANDFEECODE.P *****************
                  
                  WHILE THIS WILL STILL WORK, AND HAS THE TEAMS SYNC OPTION, THE OTHER ONE MAY BE A BETTER SOLUTION
                  
                  DIFFERENCES:
                      - This program will update linked Teams, while the new one will not (yet)
                      - This program hard codes the Resident and Non-Resident categories and must be updated for each customer it is compiled for while
                        the new one finds them based on data in the system
                      - The new program will work for multiple Categories, not just Resident and Non-Resident, as it will pull whatever category is set in Address Management
                      - The new program will look for the default No Zip Match Category, as set in Static Parameters, and treat it as the non-resident 
                        category when making a determination for updating categories
                      - The new program logic for Non-Res categories is as such:
                        - If the household has no zip code, they are given the no match category
                        - If the household zip code cannot be found in address management, they are given the no match category
                        - If the address match category is not in the system, they are set to the no match category
                      - The new program will skip guest, internal, and model households. This program will not.
                      - In the new program, if the Household profile is set to "Do Not Sync Family Members", then it will only update the Household Category and fee codes
                  
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define variable numHouseholdRecords as integer no-undo.
define variable numPersonRecords as integer no-undo.
define variable numTeamRecords as integer no-undo.
define variable nonResCategory as character no-undo.
define variable nonResFeeCode as character no-undo.
define variable resCategory as character no-undo.
define variable resFeeCode as character no-undo.
define variable residentZipCodeList as character no-undo.
define variable newCategory as character no-undo.
define variable newFeeCode as character no-undo.
define variable feecodetoReplace as character no-undo.
define variable hhCheck as character no-undo.
define variable householdID as integer no-undo.
residentZipCodeList = "".


// UPDATE THESE VARIABLES TO MATCH DATABASE CODES
assign
resCategory = "RESIDENT"
nonResCategory = "NON-RESIDENT".
// MIGHT BE ABLE TO USE THIS TO PULL THE NON-RES CODE, BUT I'M NOT SURE YET HOW TO ALSO GRAB THE RES CODE AUTOMATICALLY
// INSTEAD OF HARDCODING THE RES/NR CODES, IT MIGHT BE BETTER TO NOT EVEN HAVE A LIST, AND JUST LOOP BY ZIP CODE FROM ADDRESS MANAGEMENT
// nonResCategory = TrueVal(ProfileChar("Static Parameters","NoZipMatchCategory")). 

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// LOOKS UP DEFAULT FEECODES FOR RESIDENT CATEGORY AND INITIALIZES resFeeCode
for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = resCategory:
    resFeeCode = LookupCode.DefaultFeeCodes.
end.

// LOOKS UP DEFAULT FEECODES FOR NON-RES CATEGORY AND INITIALIZES nonResFeeCode
for first LookupCode no-lock where LookupCode.RecordType = "Category" and LookupCode.RecordCode = nonResCategory.
    nonResFeeCode = LookupCode.DefaultFeeCodes.
end.

// CREATES A LIST OF ALL RESIDENT ZIP CODES IN THE ADDRESS TABLE
for each MailingAddress no-lock where MailingAddress.Category = resCategory:
    if lookup(MailingAddress.ZipCode,residentZipCodeList) = 0 then
        residentZipCodeList = list(MailingAddress.ZipCode,residentZipCodeList).
end.


resHHLoop:  // FOR EACH HH WITH ZIP CODE IN residentZipCodeList, CHECK IF THEY ARE SET TO NON-RES AND SET THEM TO RESIDENT
    for each Account no-lock where lookup(substring(Account.PrimaryZipCode,1,5),residentZipCodeList) > 0: 
        newCategory = resCategory.
        newFeeCode = resFeeCode.
        feecodetoReplace = nonResFeeCode.
        if Account.Category <> resCategory or lookup(resFeeCode,Account.CodeValue) = 0 or lookup(nonResFeeCode,Account.CodeValue) > 0 then run updateHousehold (Account.id).
        // ALSO CHANGE THE FM LINKED IN Member OR LSTeam
        resFMLoop:
            for each Relationship no-lock where Relationship.ParentTableID = Account.id:
                if Relationship.Childtable = "Member" then 
                    do:
                        for first Member no-lock where Member.id = Relationship.ChildTableID and (Member.Category <> resCategory or lookup(resFeeCode,Member.CodeValue) = 0 or lookup(nonResFeeCode,Member.CodeValue) > 0):
                            run updatePerson (Member.id).
                        end.
                    end. // SAPERSON UPDATE
                else if Relationship.Childtable = "LSTeam" then 
                    do:
                        for first LSTeam no-lock where LSTeam.id = Relationship.ChildTableID and (LSTeam.Category <> resCategory or lookup(resFeeCode,LSTeam.CodeValue) = 0 or lookup(nonResFeeCode,LSTeam.CodeValue) > 0):
                            run updateTeam (LSTeam.id).
                        end. // LSTeam UPDATE
                    end. // LSTeam LOOKUP
                else next resFMLoop.
            end. // resFMLoop            
    end. // resHHLoop
            
nonResHHLoop:   // FOR EACH HH WITH ZIP CODE not IN residentZipCodeList, CHECK IF THEY ARE SET TO RESIDENT AND SET THEM TO NON-RES
    for each Account no-lock where lookup(substring(Account.PrimaryZipCode,1,5),residentZipCodeList) = 0:
        householdID = Account.ID.
        newCategory = nonResCategory.
        newFeeCode = nonResFeeCode.
        feecodetoReplace = resFeeCode.
        if Account.Category <> nonResCategory or lookup(nonResFeeCode,Account.CodeValue) = 0 or lookup(resFeeCode,Account.CodeValue) > 0 then run updateHousehold (Account.id).
        // ALSO CHANGE THE FAMILY MEMBER LINKED IN PERSON OR TEAMS TABLES
        nonResFMLoop:
            for each Relationship no-lock where Relationship.ParentTableID = Account.id:
                if Relationship.Childtable = "Member" then 
                    do:
                        for first Member no-lock where Member.id = Relationship.ChildTableID and (Member.Category <> nonResCategory or lookup(nonResFeeCode,Member.CodeValue) = 0 or lookup(resFeeCode,Member.CodeValue) > 0):
                            hhCheck = "continue".
                            run additionalHHCheck(Member.id).
                            if hhCheck = "skip" then next nonResFMLoop.
                            run updatePerson (Member.id).
                        end.
                    end. // SAPERSON UPDATE
                else if Relationship.Childtable = "LSTeam" then 
                    do:
                        for first LSTeam no-lock where LSTeam.id = Relationship.ChildTableID and (LSTeam.Category <> nonResCategory or lookup(nonResFeeCode,LSTeam.CodeValue) = 0 or lookup(resFeeCode,LSTeam.CodeValue) > 0):
                            hhCheck = "continue".
                            run additionalHHcheck(LSTeam.id).
                            if hhCheck = "skip" then next nonResFMLoop.
                            run updateTeam (LSTeam.id).
                        end.
                    end. // LSTEAM UPDATE
                else next nonResFMLoop.
            end. // FM-LOOP    
    end. // nonResHHLoop
    
run ActivityLog.


/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure additionalHHCheck: // CHECKS FOR LINKED RES HH AND SKIPS FM AND TEAM UPDATE IF FOUND
    define input parameter inpid as int64 no-undo.
    define variable secondaryHouseholdID as integer no-undo.
    define buffer bufRelationship for Relationship.
    for each bufRelationship no-lock where bufRelationship.ChildTableID = inpid and bufRelationship.ChildTable = "Member" and bufRelationship.ParentTable = "Account" and bufRelationship.ParentTableID <> householdID and hhCheck = "continue":
        secondaryHouseholdID = bufRelationship.ParentTableID.
        if can-find(first Account where Account.ID = secondaryHouseholdID and Account.Category = resCategory) then hhCheck = "skip".
    end. // END FOR EACH
end procedure.

procedure updateHousehold: // FOR EACH HH PASSED THROUGH, SET THE Account CATEGORY AND FEECODE TO newCategory AND newFeeCode
    define input parameter inpid as int64.
    define variable countVar as int no-undo.
    define variable oldFeeCodes as character no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.id = inpid no-error no-wait.
        if available bufAccount then assign
            numHouseholdRecords = numHouseholdRecords + 1
            bufAccount.Category = newCategory
            oldFeeCodes = bufAccount.CodeValue
            bufAccount.CodeValue = newFeeCode.
            // IF THE FEECODE FROM THE LIST IS NOT THE ONE WE'RE REPLACING AND NOT THE NEW ONE WE JUST ADDED, ADD IT TO THE LIST
            count-loop:
                do countVar = 1 to num-entries(oldFeeCodes):
                    if entry(countVar,oldFeeCodes) = feecodetoReplace or entry(countVar,OldFeeCodes) = newFeeCode then next count-loop.
                    assign bufAccount.CodeValue = bufSAhousehold.CodeValue + "," + entry(countVar,oldFeeCodes).
                end.
    end.
end procedure.

procedure updatePerson: // FOR EACH PERSON ID PASSED THROUGH (AS THE ChildTableID), SET THE Member CATEGORY AND FEECODE TO newCategory AND newFeeCode
    define input parameter inpid as int64.
    define variable countVar as int no-undo.
    define variable oldFeeCodes as character no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find bufMember exclusive-lock where bufMember.id = inpid no-error no-wait.
        if available bufMember then assign
            numPersonRecords = numPersonRecords + 1
            bufMember.Category = newCategory
            oldFeeCodes = bufMember.CodeValue
            bufMember.CodeValue = newFeeCode.
            // IF THE FEECODE FROM THE LIST IS NOT THE ONE WE'RE REPLACING AND NOT THE NEW ONE WE JUST ADDED, ADD IT TO THE LIST
            count-loop:
                do countVar = 1 to num-entries(oldFeeCodes):
                    if entry(countVar,oldFeeCodes) = feecodetoReplace or entry(countVar,oldFeeCodes) = newFeeCode then next count-loop.
                    bufMember.CodeValue = bufMember.CodeValue + "," + entry(countVar,oldFeeCodes).
                end.
    end.
end procedure.

procedure updateTeam: // FOR EACH TEAM ID PASSED THROUGH (AS THE ChildTableID), SET THE LSTeam CATEGORY AND FEECODE TO newCategory AND newFeeCode
    def input parameter inpid as int64.
    define variable countVar as int no-undo.
    def var oldFeeCodes as character no-undo.
    def buffer bufLSTeam for LSTeam.
    do for bufLSTeam transaction:
        find bufLSTeam exclusive-lock where bufLSTeam.id = inpid no-error no-wait.
        if available bufLSTeam then assign
            numTeamRecords = numTeamRecords + 1
            bufLSTeam.Category = newCategory
            oldFeeCodes = bufLSTeam.CodeValue
            bufLSTeam.CodeValue = newFeeCode.
            // IF THE FEECODE FROM THE LIST IS NOT THE ONE WE'RE REPLACING AND NOT THE NEW ONE WE JUST ADDED, ADD IT TO THE LIST
            count-loop:
                do countVar = 1 to num-entries(oldFeeCodes):
                    if entry(countVar,oldFeeCodes) = feecodetoReplace or entry(countVar,oldFeeCodes) = newFeeCode then next count-loop.
                    bufLSTeam.CodeValue = bufLSTeam.CodeValue + "," + entry(countVar,oldFeeCodes).
                end.
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "updateCategoryandFeeCodebyZip.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Update Category and Fee Codes based on Zip Code Residency"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numHouseholdRecords) + " Households, " + string(numPersonRecords) + " Family Members, " + string(numTeamRecords) + " Teams; Total records adjusted: " + string(numHouseholdRecords + numPersonRecords + numTeamRecords).
    end.
  
end procedure.