/*------------------------------------------------------------------------
    File        : findMissingWorkOrderID.p
    Purpose     : 

    Syntax      : 

    Description : Find Missing Workorder ID from Workorder Details

    Author(s)   : michaelzr
    Created     : 
    Notes       : To use this template:
                    - Start with a save as! (I've forgotten this step and needed to recreate this template many times!)
                    - Do a find/replace all for findMissingWorkOrderID and Find Missing Workorder ID from Workorder Details to update all locations these are mentioned; these will print in the audit log and the logfile will be named findMissingWorkOrderIDLog 
                    - Replace the put-stream field headers with your actual headers; this is the first row of your logfile
                    - Update the second put-stream with the appropriate fields for your log and place it within your main block or procedure
                    - Don't forget to add a creation date and update the Author!
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

// CREATE LOG FILE FIELD HEADERS
run put-stream ("MTWorkOrderDetails.ID,MTWorkOrderDetails.ParentRecord,MTWorkOrderDetails.TaskCode,MTWorkOrderDetails.RecordStatus,MTWorkOrderDetails.AssetCode,MTWorkOrderDetails.AssetType,").

for each MTWorkOrderDetails no-lock where MTWorkOrderDetails.ParentTable = "MTWorkOrder":
    find first MTWorkOrder no-lock where MTWorkOrder.ID = MTWorkOrderDetails.ParentRecord no-error no-wait.
    if not available MTWorkOrder then
    do:
        assign 
            numRecs = numRecs + 1.
         run put-stream(getString(string(MTWorkOrderDetails.ID)) + "," + getString(string(MTWorkOrderDetails.ParentRecord)) + "," + getString(MTWorkOrderDetails.TaskCode) + "," + getString(MTWorkOrderDetails.RecordStatus) + "," + getString(MTWorkOrderDetails.AssetCode) + "," + getString(MTWorkOrderDetails.AssetType) + ",").
    end.
end.
    
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingWorkOrderIDLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingWorkOrderIDLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingWorkOrderIDLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingWorkOrderID.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Missing Workorder ID from Workorder Details"
            BufActivityLog.Detail2       = "Check Document Center for findMissingWorkOrderIDLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.