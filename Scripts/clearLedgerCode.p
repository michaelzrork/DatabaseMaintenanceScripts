/*------------------------------------------------------------------------
    File        : clearSAGLCode.p
    Purpose     : 

    Syntax      : 

    Description : Clear SAGLCodes from db

    Author(s)   : michaelzrork
    Created     : 
    Notes       : Written to clear my db of bad imports to test again
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs as integer no-undo.

assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each LedgerCode exclusive-lock where LedgerCode.AccountCode < 999999990 and LedgerCode.AccountCode > 102:
    delete LedgerCode.
    numRecs = numRecs + 1.
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/



// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "clearSAGLCode.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Clear SAGLCodes from db"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.