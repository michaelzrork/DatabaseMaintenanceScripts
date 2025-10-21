/*------------------------------------------------------------------------
    File        : purgeSACrossReference.p
    Purpose     : 

    Syntax      : 

    Description : Purge all EntityLink Records

    Author(s)   : michaelzr
    Created     : 12/18/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recCount as integer no-undo.
recCount = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each EntityLink no-lock:
    run purgeSACrossReference(EntityLink.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure purgeSACrossReference:
    define input parameter inpid as int64.
    define buffer bufEntityLink for EntityLink.
    do for bufEntityLink transaction:
        find first bufEntityLink exclusive-lock where bufEntityLink.ID = inpid no-error no-wait.
        if available bufEntityLink then 
        do:
            recCount = recCount + 1.
            delete bufEntityLink.
        end.
    end.
end procedure.

procedure ActivityLog:
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "purgeSACrossReference.r"
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Purge all EntityLink Records"
            bufActivityLog.Detail2       = "Number of records deleted: " + string(recCount).
    end.
end procedure.