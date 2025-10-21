/*------------------------------------------------------------------------
    File        : clearARScheduleTable.p
    Purpose     : 

    Syntax      : 

    Description : Clear all records from the ARSchedule table

    Author(s)   : michaelzrork
    Created     : 06/26/24
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recNum as integer no-undo.

assign
    recNum = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each ARSchedule no-lock:
    run deleteARSchedule(ARSchedule.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE ARSchedule RECORD
procedure deleteARSchedule:
    define input parameter inpID as int64 no-undo.
    define buffer bufARSchedule for ARSchedule.
    do for bufARSchedule transaction:
        find first bufARSchedule exclusive-lock where bufARSchedule.id = inpID no-error no-wait.
        if available bufARSchedule then 
        do:
            recNum = recNum + 1.
            delete bufARSchedule.
        end.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "clearARScheduleTable.p"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Clear all records from the ARSchedule table"
            bufActivityLog.Detail2       = "Number of Records Deleted: " + string(recNum).
    end.
end procedure.