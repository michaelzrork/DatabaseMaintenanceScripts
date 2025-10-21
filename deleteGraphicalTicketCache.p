/*------------------------------------------------------------------------
    File        : deleteGraphicalTicketSACache.p
    Purpose     : 

    Syntax      : 

    Description : Delete Web Graphical Cache Records

    Author(s)   : michaelzrork
    Created     : 2/20/25
    Notes       : 
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

for each Cache exclusive-lock where Cache.design begins "WebGraphical":
    delete Cache.
    assign 
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
            bufActivityLog.SourceProgram = "deleteGraphicalTicketSACache.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Delete Web Graphical Cache Records"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.