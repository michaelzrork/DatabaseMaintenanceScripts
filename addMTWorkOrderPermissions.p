/*------------------------------------------------------------------------
    File        : addMTWorkOrderPermissions.p
    Purpose     : 

    Syntax      : 

    Description : Add Permissions to Work Orders

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

for each MTWorkOrder no-lock where MTWorkOrder.Permissions = "":
    run addPermissions(MTWorkOrder.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// ADD PERMISSIONS TO WORK ORDER
procedure addPermissions:
    define input parameter inpID as int64 no-undo.
    define buffer bufMTWorkOrder for MTWorkOrder.
    do for bufMTWorkOrder transaction:
        find first bufMTWorkOrder exclusive-lock where bufMTWorkOrder.ID = inpID no-error no-wait.
        if available bufMTWorkOrder then assign 
                numRecs                    = numRecs + 1
                bufMTWorkOrder.Permissions = "ParksMaintenance".
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "addMTWorkOrderPermissions.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Add Permissions to Work Orders"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.