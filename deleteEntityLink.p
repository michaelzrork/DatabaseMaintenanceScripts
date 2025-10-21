/*------------------------------------------------------------------------
    File        : deleteSACrossReference.p
    Purpose     : Delete accidental Cross Reference records

    Syntax      : 

    Description : 

    Author(s)   : michaelzr
    Created     : 12/5/2023
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

for each EntityLink no-lock where EntityLink.memberlinkid = 0 and EntityLink.EntityNumber < 88376:
    run deleteSACrossReference(EntityLink.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteSACrossReference:
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
            bufActivityLog.SourceProgram = "deleteSACrossReference.p"
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Delete EntityLink Records where MemberLinkID = 0 and HouseholdNumber < 88376"
            bufActivityLog.Detail2       = "Number of records deleted: " + string(recCount).
    end.
end procedure.