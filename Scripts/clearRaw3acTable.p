/*------------------------------------------------------------------------
    File        : clearRaw3acTable.p
    Purpose     : 

    Syntax      : 

    Description : Clear all records from the Raw3ac table

    Author(s)   : michaelzrork
    Created     : 
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

for each Raw3ac no-lock where Raw3ac.Key1A = "SearchIndexBuilder":
    run deleteRaw3ac(Raw3ac.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE RAW3AC RECORD
procedure deleteRaw3ac:
    define input parameter inpID as int64 no-undo.
    define buffer bufRaw3ac for Raw3ac.
    do for bufRaw3ac transaction:
        find first bufRaw3ac exclusive-lock where bufRaw3ac.id = inpID no-error no-wait.
        if available bufRaw3ac then 
        do:
            recNum = recNum + 1.
            delete bufRaw3ac.
        end.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "clearRaw3acTable.p"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Clear all records from the Raw3ac table"
            bufActivityLog.Detail2       = "Number of Records Deleted: " + string(recNum).
    end.
end procedure.