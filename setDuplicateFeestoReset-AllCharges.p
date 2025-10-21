/*------------------------------------------------------------------------
    File        : deletePendingFeeHistory.p
    Purpose     : 

    Syntax      : 

    Description : Deleted ChargeHistory records with a record status of 'Pending' and receipt number of 0

    Author(s)   : michaelzr
    Created     : 5/29/2024
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
define variable dupSAFeeRecs  as integer   no-undo.
define variable firstFeeFound as integer   no-undo.
define variable feeList       as character no-undo.
define variable hasDuplicate  as logical   no-undo.
assign
    feelist       = ""
    hasDuplicate  = false
    dupSAFeeRecs  = 0
    firstFeeFound = 0.


/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Account Number,Fee Order,ParentID,Item Description,CloneID,Fee ID,Fee Description,ReceiptNumber,RecordStatus,LogDate,UserName").

fee-loop:
for each Charge no-lock where Charge.RecordStatus = "Charge":
    if lookup(trim(string(Charge.ID)),feeList) > 0 then next fee-loop. 
    find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
    hasDuplicate = false.
    run checkForDuplicateFee(Charge.ID,Charge.ParentRecord,Charge.CloneID).
    if hasDuplicate then 
    do:
        firstFeeFound = firstFeeFound + 1.
        run put-stream((if available TransactionDetail then string(TransactionDetail.EntityNumber) else "TransactionDetail Record Not Found")+ "," + "First Fee" + "," + string(Charge.ParentRecord) + "," + (if available TransactionDetail then TransactionDetail.Description else "TransactionDetail Record Not Found") + "," + string(Charge.CloneID) + "," + string(Charge.ID) + "," + Charge.Description + "," + string(Charge.ReceiptNumber) + "," + Charge.RecordStatus + "," + string(Charge.LogDate) + "," + Charge.UserName).
        run addDuplicateToLog(Charge.ID,Charge.ParentRecord,Charge.CloneID).
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "duplicateFeeLogTEST" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "duplicateFeeLogTEST" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// CHECK FOR DUPLICATE FEES
procedure checkForDuplicateFee:
    define input parameter inpID as int64 no-undo.
    define input parameter feeParentID as int64 no-undo.
    define input parameter feeCloneID as int64 no-undo.
    define buffer bufCharge for Charge.
    for first bufCharge no-lock where bufCharge.ID <> inpID and bufCharge.ParentRecord = feeParentID and bufCharge.CloneID = feeCloneID and bufCharge.RecordStatus = "Charge":
        hasDuplicate = true.
    end. 
end.

// WRITE DUPLICATE FEE LOG
procedure addDuplicateToLog:
    define input parameter inpID as int64 no-undo.
    define input parameter feeParentID as int64 no-undo.
    define input parameter feeCloneID as int64 no-undo.
    define buffer bufCharge for Charge.
    for each bufCharge no-lock where bufCharge.ID <> inpID and bufCharge.ParentRecord = feeParentID and bufCharge.CloneID = feeCloneID and bufCharge.RecordStatus = "Charge":
        feeList = list(trim(string(bufCharge.ID)),feeList).
        hasDuplicate = true.
        dupSAFeeRecs = dupSAFeeRecs + 1.
        run put-stream((if available TransactionDetail then string(TransactionDetail.EntityNumber) else "TransactionDetail Record Not Found")+ "," + "Duplicate Fee" + "," + string(bufCharge.ParentRecord) + "," + (if available TransactionDetail then TransactionDetail.Description else "TransactionDetail Record Not Found") + "," + string(bufCharge.CloneID) + "," + string(bufCharge.ID) + "," + bufCharge.Description + "," + string(bufCharge.ReceiptNumber) + "," + bufCharge.RecordStatus + "," + string(bufCharge.LogDate) + "," + bufCharge.UserName).
    end. 
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "duplicateFeeLogTEST" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 15000 then 
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
            BufActivityLog.SourceProgram = "setDuplicateFeestoReset.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Set Duplicate Fees to Reset"
            BufActivityLog.Detail2       = "Check Document Center for " + "duplicateFeeLogTEST" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_*.csv" + " for a log of Records Changed"
            bufActivityLog.Detail3       = "Number of Original Fees Found: " + string(firstFeeFound) + "; Number of Duplicate Charge Records: " + string(dupSAFeeRecs).
    end.
end procedure.