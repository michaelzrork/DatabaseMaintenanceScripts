/*------------------------------------------------------------------------
    File        : setWorkorderToComplete.p
    Purpose     : 

    Syntax      : 

    Description : Set Workorder records to complete

    Author(s)   : michaelzrork
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs   as integer no-undo.
define variable checkDate as date    no-undo.

assign
    numRecs   = 0
    checkDate = 4/01/2024.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each MTWorkOrder no-lock where MTWorkOrder.OpenDate < checkDate and MTWorkOrder.RecordStatus <> "Complete" and MTWorkOrder.RecordStatus <> "Rejected":
    run setToComplete(MTWorkOrder.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure setToComplete:
    define input parameter inpID as int64 no-undo.
    define buffer bufMTWorkOrder for MTWorkOrder.
    do for bufMTWorkOrder transaction:
        find first bufMTWorkOrder exclusive-lock where bufMTWorkOrder.ID = inpid no-error no-wait.
        if available bufMTWorkOrder then assign
                numRecs                     = numRecs + 1
                bufMTWorkOrder.RecordStatus = "Complete"
                bufMTWorkOrder.CloseDate    = checkDate.
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "setWorkorderToComplete.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Set Workorder records to complete"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.