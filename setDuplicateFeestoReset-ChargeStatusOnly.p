/*------------------------------------------------------------------------
    File        : deletePendingFeeHistory.p
    Purpose     : 

    Syntax      : 

    Description : Set Charge Records to Reset

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
define variable feesUpdated as integer no-undo.
assign
    feesUpdated = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Household Number,Item Description,ParentID,CloneID,Fee ID,Fee Description,Log Date,Record Receipt Number,Original Record Status,New Record Status,Original Previous Status,New Previous Status,Reset Fee Receipt Number,Reset Fee Record Status,Reset Fee Previous Status").

fee-loop:
for each Charge no-lock where Charge.CloneID <> 0 and Charge.RecordStatus = "Charge" by Charge.ID:
    find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
    run checkForDuplicateFee(Charge.ID,Charge.ParentRecord,Charge.CloneID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "setDuplicateFeestoResetLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "setDuplicateFeestoResetLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
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
    for first bufCharge no-lock where bufCharge.ID <> inpID and bufCharge.ParentRecord = feeParentID and bufCharge.CloneID = feeCloneID and bufCharge.RecordStatus = "Charge" and bufCharge.ReceiptNumber <> Charge.ReceiptNumber and bufCharge.LogDate ge Charge.LogDate by bufCharge.ID:
        run updateFeeStatus(Charge.ID,bufCharge.ReceiptNumber,"Reset","Reset",bufCharge.RecordStatus,bufCharge.PreviousStatus).
    end.
end.

// SET FEE STATUS TO RESET
procedure updateFeeStatus:
    define input parameter inpID as int64 no-undo.
    define input parameter resetReceipt as integer no-undo.
    define input parameter newRecordStatus as character no-undo.
    define input parameter newPreviousStatus as character no-undo.
    define input parameter resetRecordStatus as character no-undo.
    define input parameter resetPreviousStatus as character no-undo.
    define buffer bufCharge for Charge.
    do for bufCharge transaction:
        find first bufCharge exclusive-lock where bufCharge.ID = inpID no-error no-wait.
        if available bufCharge then 
        do:
            // Household Number,Item Description,ParentID,CloneID,Fee ID,Fee Description,Log Date,Record Receipt Number,Original Record Status,New Record Status,Original Previous Status,New Previous Status,Reset Fee Receipt Number,Reset Fee Record Status,Reset Fee Previous Status
            run put-stream((if available TransactionDetail then string(TransactionDetail.EntityNumber) else "TransactionDetail Record Not Found") + "," + (if available TransactionDetail then replace(TransactionDetail.Description,",","") else "TransactionDetail Record Not Found") + "," + string(bufCharge.ParentRecord) + "," + string(bufCharge.CloneID) + "," + string(bufCharge.ID) + "," + replace(bufCharge.Description,",","") + "," + string(bufCharge.LogDate) + "," + string(bufCharge.ReceiptNumber) + "," + bufCharge.RecordStatus + "," + newRecordStatus + "," + bufCharge.PreviousStatus + "," + newPreviousStatus + "," + string(resetReceipt) + "," + resetRecordStatus + "," + resetPreviousStatus).
            assign
                feesUpdated             = feesUpdated + 1
                bufCharge.RecordStatus   = newRecordStatus
                bufCharge.PreviousStatus = newPreviousStatus.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "setDuplicateFeestoResetLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "setDuplicateFeestoReset.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Set Charge Records to Reset"
            BufActivityLog.Detail2       = "Check Document Center for setDuplicateFeestoResetLog for a log of Records Changed"
            bufActivityLog.Detail3       = "Number of Fees Set To Reset: " + string(feesUpdated).
    end.
end procedure.