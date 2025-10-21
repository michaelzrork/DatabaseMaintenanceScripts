/*------------------------------------------------------------------------
    File        : deleteEmailContactRecords.p
    Purpose     : 

    Syntax      : 

    Description : Deletes EmailContact Records

    Author(s)   : 
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs as integer no-undo.
numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each EmailContact exclusive-lock where EmailContact.OptInIP = "Account Import":
    delete EmailContact.
end.
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "deleteEmailContactRecords.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Deletes EmailContact Records"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.