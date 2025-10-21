/*------------------------------------------------------------------------
    File        : findMissingSAFeeHistory.p
    Purpose     : 

    Syntax      : 

    Description : Find Missing ChargeHistory records using the PaymentReceipt SpecialLinkID

    Author(s)   : michaelzr
    Created     : 
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
define variable numRecs            as integer no-undo.
define variable numDetailRecs      as integer no-undo.
define variable numFeeRecs         as integer no-undo.
define variable numFeeHistRecs     as integer no-undo.
define variable numGLDistRecs      as integer no-undo.
define variable numControlAcctRecs as integer no-undo.
define variable numRefundRecs      as integer no-undo.
assign
    numRecs            = 0
    numDetailRecs      = 0
    numFeeRecs         = 0
    numFeeHistRecs     = 0
    numGLDistRecs      = 0
    numControlAcctRecs = 0
    numRefundRecs      = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("PaymentTransaction ID" +
    ",PaymentTransaction Posting Date" +
    ",PaymentTransaction Receipt Number" +
    ",PaymentTransaction Amount Paid" +
    ",PaymentTransaction Paycode" +
    ",PaymentTransaction ParentID (ChargeHistory.ID)" +
    ",#TransactionDetail Records" +
    ",#Charge Records" +
    ",#ChargeHistory Records" +
    ",#LedgerEntry Records" +
    ",$AccountBalanceLog Records" +
    ",#Reversal Records" +
    ",").

for each PaymentTransaction no-lock where PaymentTransaction.ParentRecord <> ? and PaymentTransaction.ParentRecord <> 0 and PaymentTransaction.ParentTable = "ChargeHistory":
    find first ChargeHistory no-lock where ChargeHistory.ID = PaymentTransaction.ParentRecord no-error no-wait.
    if not available ChargeHistory then 
    do:
          
        assign 
            numRecs            = numRecs + 1
            numDetailRecs      = 0
            numFeeRecs         = 0
            numFeeHistRecs     = 0
            numGLDistRecs      = 0
            numControlAcctRecs = 0
            numRefundRecs      = 0.
        for each TransactionDetail no-lock where lookup(string(PaymentTransaction.ReceiptNumber),TransactionDetail.ReceiptList) > 0:
            numDetailRecs = numDetailRecs + 1.
        end.
        for each Charge no-lock where Charge.ReceiptNumber = PaymentTransaction.ReceiptNumber:
            numFeeRecs = numFeeRecs + 1.
        end.
        for each ChargeHistory no-lock where ChargeHistory.ReceiptNumber = PaymentTransaction.ReceiptNumber:
            numFeeHistRecs = numFeeHistRecs + 1.
        end.
        for each LedgerEntry no-lock where LedgerEntry.ReceiptNumber = PaymentTransaction.ReceiptNumber:
            numGLDistRecs = numGLDistRecs + 1.
        end.
        for each AccountBalanceLog no-lock where AccountBalanceLog.ReceiptNumber = PaymentTransaction.ReceiptNumber:
            numControlAcctRecs = numControlAcctRecs + 1.
        end.
        for each Reversal no-lock where Reversal.ReceiptNumber = PaymentTransaction.ReceiptNumber:
            numRefundRecs = numRefundRecs + 1.
        end.
        run put-stream("~"" +
            /*PaymentTransaction ID*/
            getString(string(PaymentTransaction.ID))
            + "~",~"" + 
            /*PaymentTransaction Posting Date*/
            getString(string(PaymentTransaction.PostingDate))
            + "~",~"" +
            /*PaymentTransaction Receipt Number*/
            getString(string(PaymentTransaction.ReceiptNumber))
            + "~",~"" +
            /*PaymentTransaction Amount Paid*/
            getString(string(PaymentTransaction.Amount))
            + "~",~"" +
            /*PaymentTransaction Paycode*/
            getString(string(PaymentTransaction.Paycode))
            + "~",~"" +
            /*PaymentTransaction ParentID (ChargeHistory.ID)*/
            getString(string(PaymentTransaction.ParentRecord))
            + "~",~"" +
            /*Number of TransactionDetail Records*/
            string(numDetailRecs)
            + "~",~"" +
            /*Number of Charge Records*/
            string(numFeeRecs)
            + "~",~"" +
            /*Number of ChargeHistory Records*/
            string(numFeeHistRecs)
            + "~",~"" +
            /*Number of LedgerEntry Records*/
            string(numGLDistRecs)
            + "~",~"" +
            /*Number of AccountBalanceLog Records*/
            string(numControlAcctRecs)
            + "~",~"" +
            /*Number of Reversal Records*/
            string(numRefundRecs)
            + "~",").
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingSAFeeHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingSAFeeHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingSAFeeHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingSAFeeHistory.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Missing ChargeHistory records using the PaymentReceipt SpecialLinkID"
            BufActivityLog.Detail2       = "Check Document Center for findMissingSAFeeHistoryLog for a log of Records Found"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.