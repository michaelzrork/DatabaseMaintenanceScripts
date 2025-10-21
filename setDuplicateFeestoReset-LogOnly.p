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
define variable numFeesReset   as integer   no-undo.
define variable feesSetToReset as integer   no-undo.
define variable feeList        as character no-undo.
define variable foundFee       as logical   no-undo.
assign
    feelist      = ""
    numFeesReset = 0
    foundFee     = false.
    
define temp-table ttResetFees no-undo
    field FeeID as int64
    index FeeID FeeID.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Household Number,Fee Order,ParentID,Item Description,CloneID,Fee ID,Fee Description,ReceiptNumber,RecordStatus,LogDate,UserName").

fee-loop:
for each Charge no-lock where Charge.RecordStatus = "Charge" by Charge.ID:
    find ttResetFees where ttResetFees.FeeID = Charge.ID no-error.
    if available ttResetFees then next fee-loop.
    find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
    run checkForDuplicateFee(Charge.ID,Charge.ParentRecord,Charge.CloneID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "duplicateFeeLogOnly" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "duplicateFeeLogOnly" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
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
    foundFee = false.
    dupe-loop:
    for each bufCharge no-lock where bufCharge.ID <> inpID and bufCharge.ParentRecord = feeParentID and bufCharge.CloneID = feeCloneID and bufCharge.RecordStatus = "Charge" by bufCharge.ID while foundFee = false:
        find ttResetFees where ttResetFees.FeeID = bufCharge.ID no-error.
        if available ttResetFees then next dupe-loop.
        do:
        // CHECK THE LOGDATE, AND SET THE OLDEST ONE TO RESET
            if bufCharge.LogDate ge Charge.LogDate then run setFeeToReset(Charge.ID).
            else run setFeeToReset(bufCharge.ID).
        end.
    end.
end.

// SET FEE STATUS TO RESET
procedure setFeeToReset:
    define input parameter inpID as int64 no-undo.
    define buffer bufCharge for Charge.
    do for bufCharge transaction:
        find first bufCharge exclusive-lock where bufCharge.ID = inpID no-error no-wait.
        if available bufCharge then 
        do:
            find ttResetFees where ttResetFees.FeeID = bufCharge.ID no-error.
            if not available ttResetFees then 
            do: 
                create ttResetFees.
                assign
                    ttResetFees.FeeID = bufCharge.ID.
                // ADD RECORD TO LOG "Household Number,LogDate,ParentID,Item Description,CloneID,Fee ID,Fee Description,ReceiptNumber,Old RecordStatus,New RecordStatus,UserName"
                run put-stream((if available TransactionDetail then string(TransactionDetail.EntityNumber) else "TransactionDetail Record Not Found") + "," + string(bufCharge.LogDate) + "," + string(bufCharge.ParentRecord) + "," + (if available TransactionDetail then replace(TransactionDetail.Description,",","") else "TransactionDetail Record Not Found") + "," + string(bufCharge.CloneID) + "," + string(bufCharge.ID) + "," + replace(bufCharge.Description,",","") + "," + string(bufCharge.ReceiptNumber) + "," + bufCharge.RecordStatus + "," + "Reset" + "," + bufCharge.UserName).
                assign
                    foundFee     = true
                    numFeesReset = numFeesReset + 1.
                    // bufCharge.RecordStatus = "Reset".
                
            end.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "duplicateFeeLogOnly" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.Detail2       = "Check Document Center for " + "duplicateFeeLogOnly" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_*.csv" + " for a log of Records Changed"
            bufActivityLog.Detail3       = "Number of Fees Set To Reset: " + string(numFeesReset).
    end.
end procedure.