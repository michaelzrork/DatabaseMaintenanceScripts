/*------------------------------------------------------------------------
    File        : revertClearReceiptBalance.p
    Purpose     : 

    Syntax      : 

    Description : Revert Clear Receipt Balance

    Author(s)   : michaelzr
    Created     : 1/1/24
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
    logfileTime = time
    counter     = 0.
    
// FILE IMPORT STUFF

{Includes/ProcessingConfig.i}
{Includes/TransactionDetailStatusList.i}
{Includes/TTVals.i}
{Includes/Screendef.i "reference-only"}  
{Includes/AvailableCredit.i}
{Includes/AvailableScholarship.i} 
{Includes/ModuleList.i} 
{Includes/TTProfile.i}

define variable importFileName as character no-undo.
define variable importfile     as char      no-undo.  
define variable tmpcode1       as char      no-undo. 

def stream exp.

def temp-table ttImport no-undo 
    field xTable    as character 
    field xID       as int64
    field origValue as character 
    index xTable xTable 
    index xID    xID.
    
assign 
    importFileName = "clearReceiptBalance2.txt"
    tmpcode1       = "\Import\" + importFileName.


// EVERYTHING ELSE
define variable numFeeHistRecs as integer no-undo.
define variable numReceiptRecs as integer no-undo.
define variable numDetailRecs  as integer no-undo.
assign
    numFeeHistRecs = 0
    numReceiptRecs = 0
    numDetailRecs  = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// GRAB INPUT FILE FROM DOCUMENT CENTER IMPORT
CreateFile (tmpcode1, false, sessionTemp(), true, false) no-error. 

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Starting Process " + string(counter) + ",,,,").

assign
    Importfile = sessionTemp() + importFileName.

run put-stream (" 1 Importfile = " + Importfile + ",,,,").

// CHECK FOR IMPORT FILE
if search(Importfile) = ? then 
do:
    // IF NOT FOUND, CREATE ERROR RECORD AND END
    run ActivityLog("; Program aborted: " + Importfile + " not found!").
    run put-stream (" 1 Importfile Problem" + Importfile + " not found!,,,,").
    SaveFileToDocuments(inpfile-loc, "\Reports\", "", no, yes, yes, "Report").  
    return.
end.   
 
// SET IMPORT FILE
input stream exp from value(importfile) no-echo.

// RESET COUNTER FOR IMPORT LOOP
assign 
    counter = 0.

// CREATE TEMP TABLE FROM INPUT FILE VALUES
import-loop:
repeat transaction:
    create ttImport.
    import stream exp delimiter "," ttImport  no-error.
    counter = counter + 1.
end.

// CLOSE INPUT STREAM
input stream exp close.  

// LOG NUMBER OF RECORDS IMPORTED FROM IMPORT FILE
run put-stream ("ttImport Records imported =  " + string(counter) + ",,,,").

// RESET COUNTER FOR LOGFILE
assign 
    counter = 0.
  
// SET CHANGES HEADER
run put-stream(",,,,").
run put-stream("Table,ID,Current Value,Restored Value,").
  
// REVERT CHANGES
ttImport-loop:
for each ttImport:
    if ttImport.xTable = "" then delete ttImport.
    if ttImport.xTable = "Table" then next ttImport-loop.
    case ttImport.xTable:
        when "ChargeHistory" then run revertFeeHist(ttImport.xID,decimal(ttImport.origValue)).
        when "PaymentReceipt" then run revertReceipt(ttImport.xID,decimal(ttImport.origValue)).
        when "TransactionDetail" then run revertDetail(ttImport.xID,ttImport.origValue).
    end.
end.

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "revertClearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "revertClearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.
    
// FROM GRADE BUMP; CAME AFTER LOG FILE
DeleteBlob(tmpcode1).

// CREATE AUDIT LOG RECORD
run ActivityLog("").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure revertFeeHist:
    define input parameter inpID as int64 no-undo.
    define input parameter origAmount as decimal no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
        do:
            run put-stream(
                // TABLE
                "ChargeHistory" + "," + 
                // ID
                getString(string(bufChargeHistory.ID)) + "," +
                // VALUE TO REVERT
                getString(string(bufChargeHistory.FeeAmount)) + "," +
                // RESTORED ORIGINAL VALUE
                getString(string(origAmount)) + ","
                ).
            assign 
                bufChargeHistory.FeeAmount = origAmount
                numFeeHistRecs            = numFeeHistRecs + 1.
        end.
    end.
end procedure.

// RESTORE SARECEIPT
procedure revertReceipt:
    define input parameter inpID as int64 no-undo.
    define input parameter origAmount as decimal no-undo.
    define buffer bufPaymentReceipt for PaymentReceipt.
    do for bufPaymentReceipt transaction:
        find first bufPaymentReceipt exclusive-lock where bufPaymentReceipt.ID = inpID no-error no-wait.
        if available bufPaymentReceipt then 
        do:
            run put-stream(
                // TABLE
                "PaymentReceipt" + "," + 
                // ID
                getString(string(bufPaymentReceipt.ID)) + "," +
                // VALUE TO REVERT
                getString(string(bufPaymentReceipt.FeeAmount)) + "," +
                // RESTORED ORIGINAL VALUE
                getString(string(origAmount)) + ","
                ).
            assign 
                bufPaymentReceipt.FeeAmount = origAmount
                numReceiptRecs         = numReceiptRecs + 1.
        end.
    end.
end procedure.

// RESTORE TRANSACTIONDETAIL FULLY PAID STATUS
procedure revertDetail:
    define input parameter inpID as int64 no-undo.
    define input parameter origValue as logical no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then 
        do:
            run put-stream(
                // TABLE
                "TransactionDetail" + "," + 
                // ID
                getString(string(bufTransactionDetail.ID)) + "," +
                // VALUE TO REVERT
                (if bufTransactionDetail.FullyPaid = true then "true" else "false") + "," +
                // RESTORED ORIGINAL VALUE
                (if origValue = false then "false" else "true") + ","
                ).
            assign 
                bufTransactionDetail.FullyPaid = origValue
                numDetailRecs        = numDetailRecs + 1.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "revertClearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
    define input parameter logDetail as character no-undo.
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "revertClearReceiptBalance.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Revert Clear Receipt Balance" + logDetail
            BufActivityLog.Detail2       = "Check Document Center for revertClearReceiptBalanceLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of ChargeHistory records reverted: " + string(numFeeHistRecs)
            bufActivityLog.Detail4       = "Number of PaymentReceipt records reverted: " + string(numReceiptRecs)
            bufActivityLog.Detail5       = "Number of TransactionDetail records reverted: " + string(numDetailRecs).
    end.
end procedure.