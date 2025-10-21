/*------------------------------------------------------------------------
    File        : changeResignedToInactive.p
    Purpose     : 

    Syntax      : 

    Description : Change RecordStatus from Resigned to Inactive in CYStaffProvider table

    Author(s)   : michaelzrork
    Created     : 10/21/2024
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
    run changeRecordStatus(CYStaffProvider.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHANGE RECORD STATUS
procedure changeRecordStatus:
    define input parameter inpID as int64 no-undo.
    define buffer bufCYStaffProvider for CYStaffProvider.
    do for bufCYStaffProvider transaction:
        find first bufCYStaffProvider exclusive-lock where bufCYStaffProvider.ID = inpID no-error no-wait.
        if available bufCYStaffProvider then 
        do:
            assign 
                bufCYStaffProvider.RecordStatus = "Inactive".
            numRecs = numRecs + 1.
        end.
    end.
end.
        

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "changeResignedToInactive.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Change RecordStatus from Resigned to Inactive in CYStaffProvider table"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.