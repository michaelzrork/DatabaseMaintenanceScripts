/*------------------------------------------------------------------------
    File        : fixSAAddressResCat.p
    Purpose     : 

    Syntax      : 

    Description : Fix MailingAddress Resident Category

    Author(s)   : michaelzrork
    Created     : 11/5/2024
    Notes       : THIS IS UNNECESSARY - To do this fix within RecTrac, create a new Category then do a Code Conversion and merge that cat into the current res category
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs   as integer   no-undo.
define variable oldCode   as character no-undo.
define variable newCode   as character no-undo.
define variable numHHRecs as integer   no-undo.
define variable numFMRecs as integer   no-undo.

assign
    oldCode   = "HH Resident"
    newCode   = "RESIDENT"
    numRecs   = 0
    numHHRecs = 0
    numFMRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each MailingAddress no-lock where MailingAddress.Category = oldCode:
    run changeCode(MailingAddress.ID).
end.

for each Account no-lock where Account.Category = oldCode:
    run changeHHCat(Account.ID).
end.

for each Member no-lock where Member.Category = oldCode:
    run changeFMCat(Member.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHANGE ADDRESS MANAGEMENT CATEGORY
procedure changeCode:
    define input parameter inpID as int64 no-undo.
    define buffer bufMailingAddress for MailingAddress.
    do for bufMailingAddress transaction:
        find first bufMailingAddress exclusive-lock where bufMailingAddress.ID = inpID no-error no-wait.
        if available bufMailingAddress then assign
                bufMailingAddress.Category = newCode
                numRecs               = numRecs + 1.
    end.
end procedure.

// CHANGE HOUSEHOLD CATEGORY
procedure changeHHCat:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then assign 
                bufAccount.Category = newCode
                numHHRecs               = numHHRecs + 1.
    end.
end procedure.

// CHANGE FAMILY MEMBER CATEGORY
procedure changeFMCat:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then assign
                bufMember.Category = newCode
                numFMRecs            = numFMRecs + 1.
    end.
end procedure.


// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "fixSAAddressResCat.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Fix MailingAddress Resident Category"
            bufActivityLog.Detail2       = "Number of Address Records Adjusted: " + string(numRecs)
            bufActivityLog.Detail3       = "Number of Household Records Adjusted: " + string(numHHRecs)
            bufActivityLog.Detail4       = "Number of Family Member Records Adjusted: " + string(numFMRecs).
            
    end.
end procedure.