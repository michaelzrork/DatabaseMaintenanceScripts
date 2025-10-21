/*------------------------------------------------------------------------
    File        : changeFeeCode.p
    Purpose     : 

    Syntax      : 

    Description : Change Account and Member feecode from CS to NN

    Author(s)   : michaelzr
    Created     : 6/18/24
    Notes       : While this should work just fine, I realized after writing it that we don't need it, as code conversion can already do this.
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable oldFeeCode as character no-undo.
define variable newFeeCode as character no-undo.
define variable numHHRecs  as integer   no-undo.
define variable numFMRecs  as integer   no-undo.
assign
    oldFeeCode = "CS"
    newFeeCode = "NN"
    numHHRecs  = 0
    numFMRecs  = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// ACCOUNT LOOP
for each Account no-lock where index(Account.CodeValue,oldFeeCode) > 0:
    run updateHHFeeCode(Account.ID).
end.

// PERSON LOOP
for each Member no-lock where index(Member.CodeValue,oldFeeCode) > 0:
    run updateFMFeeCode(Member.ID).
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// UPDATE Account FEE CODE
procedure updateHHFeeCode:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then 
            assign
                numHHRecs              = numHHRecs + 1
                bufAccount.CodeValue = replace(bufAccount.CodeValue,oldFeeCode,newFeeCode).
    end.
end.

// UPDATE Member FEE CODE
procedure updateFMFeeCode:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpid no-error no-wait.
        if available bufMember then 
            assign
                numHHRecs           = numFMRecs + 1
                bufMember.CodeValue = replace(bufMember.CodeValue,oldFeeCode,newFeeCode).
    end.
end.  

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "changeFeeCode.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Change Account and Member feecode from " + oldFeeCode + " to " + newFeeCode
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numHHRecs).
    end.
end procedure.