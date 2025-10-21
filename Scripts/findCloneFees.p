/*------------------------------------------------------------------------
    File        : findCloneFees.p
    Purpose     : 

    Syntax      : 

    Description : Find all cloned fees for Standard Fees without a Revenue GL Code

    Author(s)   : michaelzr
    Created     : 7/12/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo. 
define variable logfileDate as date      no-undo.
define variable logfileTime as integer   no-undo. 

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time.

// EVERYTHING ELSE
define variable numRecs as integer no-undo.
assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("CloneID,Description,ID,LogDate,ParentID,ParentTable,ParentCode,").

// FEE LOOP
for each Charge no-lock where feetype = "Standard Fee" and revenueGLCode = 0 and cloneid = 0:
    run checkForClonedFees(Charge.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findCloneFeesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findCloneFeesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// 
procedure checkForClonedFees:
    define input parameter inpID as int64 no-undo.
    define variable feeFound as logical no-undo.
    define buffer bufCharge for Charge.
    feeFound = false.
    for each bufCharge no-lock where bufCharge.CloneID = inpID:
        assign feeFound = true.
    // CREATE LOG ENTRY "CloneID,Description,ID,LogDate,ParentID,ParentTable,ParentCode"
        run put-stream (string(bufCharge.CloneID) + "," + replace(bufCharge.Description,",","") + "," + string(bufCharge.ID) + "," + string(bufCharge.LogDate) + "," + string(bufCharge.ParentRecord) + "," + bufCharge.ParentTable + "," + bufCharge.ParentCode + ",").
        numRecs = numRecs + 1.
    end.
    if feeFound = false then run put-stream("No Cloned Fees found for Charge.ID " + string(inpID)).

end. 

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findCloneFeesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 30000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "findCloneFees.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find all cloned fees for Standard Fees without a Revenue GL Code"
            BufActivityLog.Detail2       = "Check Document Center for findCloneFeesLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.