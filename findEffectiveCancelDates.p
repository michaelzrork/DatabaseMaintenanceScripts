/*------------------------------------------------------------------------
    File        : findEffectiveCancelDates.p
    Purpose     : 

    Syntax      : 

    Description : Find passes with potential stripped effective cancel date

    Author(s)   : michaelzr
    Created     : 06/21/24
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
    
define buffer bufTransactionDetail for TransactionDetail.

define temp-table ttTransactionDetailID no-undo
    field TransactionDetailID as int64
    index TransactionDetailID TransactionDetailID.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Account Number,Name,Description,Effective Cancel Receipt").

// FIND PASSES WITH EFFECTIVE CANCEL DATES
for each Account no-lock:    
    for each TransactionDetail no-lock where TransactionDetail.Module = "PM" and TransactionDetail.EndDate ge today and TransactionDetail.EffectiveCancelDate <> ? and TransactionDetail.EntityNumber = Account.EntityNumber:
        detail-loop:
        for each bufTransactionDetail no-lock where bufTransactionDetail.PatronLinkID <> TransactionDetail.PatronLinkID and bufTransactionDetail.EntityNumber = TransactionDetail.EntityNumber and bufTransactionDetail.Module = "PM" and bufTransactionDetail.EffectiveCancelDate = ? and bufTransactionDetail.EndDate ge today and bufTransactionDetail.RecordStatus = "Active" and index(bufTransactionDetail.ReceiptList,string(TransactionDetail.CurrentReceipt)) > 0:
            find ttTransactionDetailID where ttTransactionDetailID.TransactionDetailID = bufTransactionDetail.ID no-error.
            if available ttTransactionDetailID then next detail-loop.
            create ttTransactionDetailID.
            assign 
                ttTransactionDetailID.TransactionDetailID = bufTransactionDetail.ID.
            // WRITE LOG FILE
            run put-stream (string(bufTransactionDetail.EntityNumber) + "," + bufTransactionDetail.FirstName + " " + bufTransactionDetail.LastName + "," + bufTransactionDetail.Description + "," + string(TransactionDetail.CurrentReceipt)).
            numRecs = numRecs + 1.
        end.
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findEffectiveCancelDatesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findEffectiveCancelDatesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findEffectiveCancelDatesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findEffectiveCancelDates.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find passes with potential stripped effective cancel date"
            BufActivityLog.Detail2       = "Check Document Center for " + "findEffectiveCancelDatesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_*.csv" + " for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.