/*------------------------------------------------------------------------
    File        : changeStatusToInactive.p
    Purpose     : 

    Syntax      : 

    Description : Change CYStaff recordstatus from Resigned to Inactive

    Author(s)   : michaelzrork
    Created     : 12/16/2024
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

for each CYStaffProvider no-lock where CYStaffProvider.RecordStatus = "Resigned":
    run updateStatus(CYStaffProvider.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// UPDATE STAFF RECORD STATUS
procedure updateStatus:
    define input parameter inpID as int64 no-undo.
    define buffer bufCYStaffProvider for CYStaffProvider.
    do for bufCYStaffProvider transaction:
        find first bufCYStaffProvider exclusive-lock where bufCYStaffProvider.ID = inpID no-error no-wait.
        if available bufCYStaffProvider then assign
                numRecs                         = numRecs + 1
                bufCYStaffProvider.RecordStatus = "Inactive".
    end.
end procedure.


// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "changeStatusToInactive.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Change CYStaff recordstatus from Resigned to Inactive"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.