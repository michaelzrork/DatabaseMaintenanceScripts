/*------------------------------------------------------------------------
    File        : changeGLCodes.p
    Purpose     : CHANGE GL CODES IN SAGLDISTRIBUTION RECORDS

    Syntax      : 

    Description : SWAPS OUT THE GL CODE IN THE SAGLDISTRIBUTION TABLE WITH A NEW ONE

    Author(s)   : MICHAELZRORK
    Created     : JAN 2023 
    Notes       : THIS WAS MEANT TO CORRECT A BUG, BUT WAS NOT NEEDED
                  THE SAME THING SHOULD BE DOABLE WITH A BULK FEE CHANGE
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable oldGLcode1  as int no-undo.
define variable oldGLcode2  as int no-undo.
define variable newGLcode   as int no-undo.
define variable recordCount as int no-undo.

oldGLcode1 = 1.
oldGLcode2 = 11.
newGLcode = 9.
recordCount = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each LedgerEntry no-lock where LedgerEntry.AccountCode = oldGLcode1 or LedgerEntry.AccountCode = oldGLcode2:
    run updateGLrecords (LedgerEntry.id).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure updateGLrecords:
    define input parameter inpid as int.
    define buffer bufLedgerEntry for LedgerEntry.
    do for bufLedgerEntry transaction:
        find bufLedgerEntry exclusive-lock where bufLedgerEntry.id = inpid no-error no-wait.
            if available bufLedgerEntry then assign
            recordCount = recordCount + 1
            bufLedgerEntry.AccountCode = newGLCode.
    end.
end procedure.        

procedure ActivityLog:     
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "changeGLCodes"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Update LedgerEntry GL Code"
            BufActivityLog.Detail2       = string(recordCount) + " records adjusted".
    end.
end procedure.