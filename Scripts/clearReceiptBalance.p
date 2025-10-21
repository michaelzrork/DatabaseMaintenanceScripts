/*------------------------------------------------------------------------
    File        : clearReceiptBalance.p
    Purpose     : 

    Syntax      : 

    Description : Clear Receipt Balances on Household

    Author(s)   : michaelzr
    Created     : 1/1/24
    Notes       : THIS DID NOT WORK PROPERLY AND HAS NOT BEEN USED TO FIX ANY ISSUES
                  I ENDED UP USING clearDiscountFeeHistory.p INSTEAD, SINCE THE ISSUE WAS REVOLVED AROUND A BUG THAT CAUSED
                  THE CHARGEHISTORY RECORD TO USE THE DISCOUNT FEE PERCENTAGE AS THE FEEHISTORY AMOUNT
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

define variable numFeeRecs     as integer no-undo.
define variable amountPaid     as decimal no-undo.
define variable hhNum          as integer no-undo.
define variable amountCharged  as decimal no-undo.
define variable numReceiptRecs as integer no-undo.
define variable numDetailRecs  as integer no-undo.
assign
    numFeeRecs     = 0
    amountPaid     = 0
    hhNum          = 46 // CUSTOMER HOUSEHOLD NUMBER
    // hhNum          = 35 // MY TEST HH
    amountCharged  = 0
    numReceiptRecs = 0
    numDetailRecs  = 0.
    
define buffer bufChargeHistory for ChargeHistory.

define temp-table ttReceipts no-undo
    field receiptNumber as integer
    index receiptNumber receiptNumber. 

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Table,ID,ParentID,Receipt Number,Original Amount Charged,Original Discount Amount,Amount Paid,New Amount Charged,").

feehist-loop:
for each ChargeHistory no-lock where ChargeHistory.RecordStatus = "Charge" and ChargeHistory.PaymentHousehold = hhNum and ChargeHistory.FeeAmount > 0 and ChargeHistory.TimeCount ne 0 and ChargeHistory.Quantity ne 0:
    assign 
        amountPaid = 0.
    find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
    if available Charge then 
    do:
        if Charge.RecordStatus <> "Charge" then next feehist-loop.
        find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
        if available TransactionDetail and TransactionDetail.RecordStatus = "Change" then next feehist-loop.
        for each bufChargeHistory no-lock where bufChargeHistory.RecordStatus = "Paid" and bufChargeHistory.ParentRecord = ChargeHistory.ParentRecord:
            amountPaid = amountPaid + bufChargeHistory.FeePaid.
        end.
        if amountPaid < (ChargeHistory.FeeAmount - ChargeHistory.DiscountAmount) then run fixAmountCharged(ChargeHistory.ID).
    end.    
end.  

for each ttReceipts no-lock:
    amountCharged = 0.
    for each ChargeHistory no-lock where ChargeHistory.ReceiptNumber = ttReceipts.receiptNumber and ChargeHistory.RecordStatus = "Charge" and ChargeHistory.TimeCount <> 0 and ChargeHistory.Quantity <> 0:
        amountCharged = amountCharged + ChargeHistory.FeeAmount - ChargeHistory.DiscountAmount.
    end.
    find first PaymentReceipt no-lock where PaymentReceipt.ReceiptNumber = ttReceipts.receiptNumber no-error no-wait.
    if available PaymentReceipt then run fixReceiptAmount(PaymentReceipt.ID).
    for each TransactionDetail no-lock where TransactionDetail.CurrentReceipt = ttReceipts.receiptNumber and TransactionDetail.FullyPaid = no:
        run setToPaid(TransactionDetail.ID).
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "clearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "clearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIX AMOUNT CHARGED
procedure fixAmountCharged:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
        do:
            run put-stream(
                // Table
                "~"" + "ChargeHistory"
                // ID
                + "~",~"" + string(bufChargeHistory.ID)
                // ParentID
                + "~",~"" + getString(string(bufChargeHistory.ParentRecord)) + " (Charge)"
                // ReceiptNumber
                + "~",~"" + getString(string(bufChargeHistory.ReceiptNumber))
                // Original Amount Charged
                + "~",~"" + getString(string(bufChargeHistory.FeeAmount))
                // Original Discount
                + "~",~"" + getString(string(bufChargeHistory.DiscountAmount))
                // Amount Paid
                + "~",~"" + getString(string(amountPaid))             
                // New Amount Charged
                + "~",~"" + getString(string(amountPaid + bufChargeHistory.DiscountAmount))
                + "~",").
            assign
                bufChargeHistory.FeeAmount = amountPaid + bufChargeHistory.DiscountAmount
                numFeeRecs                = numFeeRecs + 1.
            find first ttReceipts no-lock where ttReceipts.receiptNumber = bufChargeHistory.ReceiptNumber no-error no-wait.
            if not available ttReceipts then create ttReceipts.
            assign 
                ttReceipts.receiptNumber = bufChargeHistory.ReceiptNumber.
        end.
    end.
end procedure.

// FIX RECEIPT AMOUNT
procedure fixReceiptAmount:
    define input parameter inpID as int64 no-undo.
    define buffer bufPaymentReceipt for PaymentReceipt.
    do for bufPaymentReceipt transaction:
        find first bufPaymentReceipt exclusive-lock where bufPaymentReceipt.ID = inpID no-error no-wait.
        if available bufPaymentReceipt then 
        do:
            run put-stream(
                // Table
                "~"" + "PaymentReceipt"
                // ID
                + "~",~"" + getString(string(bufPaymentReceipt.ID))
                // ParentID
                + "~",~"" + "N/A"
                // ReceiptNumber
                + "~",~"" + getString(string(bufPaymentReceipt.ReceiptNumber))
                // Original Amount Charged
                + "~",~"" + getString(string(bufPaymentReceipt.FeeAmount))
                // Original Discount
                + "~",~"" + "N/A"
                // Amount Paid
                + "~",~"" + getString(string(bufSAreceipt.FeePaid))             
                // New Amount Charged
                + "~",~"" + getString(string(amountCharged))
                + "~",").
            assign
                bufPaymentReceipt.FeeAmount = amountCharged
                numReceiptRecs         = numReceiptRecs + 1.
        end.
    end.
end procedure.

// SET TRANSACTIONDETAIL RECORD TO FULLY PAID
procedure setToPaid:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then 
        do:
            run put-stream(
                // Table
                "~"" + "TransactionDetail"
                // ID
                + "~",~"" + string(bufTransactionDetail.ID)
                // ParentID
                + "~",~"" + "N/A"
                // ReceiptNumber
                + "~",~"" + getString(string(bufTransactionDetail.CurrentReceipt))
                // Original Amount Charged
                + "~",~"" + (if bufTransactionDetail.FullyPaid = no then "Fully Paid = False" else "Fully Paid = True")
                // Original Discount
                + "~",~"" + "N/A"
                // Amount Paid
                + "~",~"" + "N/A"             
                // New Amount Charged
                + "~",~"" + "Fully Paid = True"
                + "~",").
            assign 
                bufTransactionDetail.FullyPaid = true
                numDetailRecs         = numDetailRecs + 1.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "clearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "clearReceiptBalance.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Clear Receipt Balances on Household " + string(hhNum)
            BufActivityLog.Detail2       = "Check Document Center for clearReceiptBalanceLog for a log of Records Changed"
            bufActivityLog.Detail3       = "Number of Fees Adjusted: " + string(numFeeRecs)
            bufActivityLog.Detail4       = "Number of Receipts Adjusted: " + string(numReceiptRecs)
            bufActivityLog.Detail5       = "Number of TransactionDetail records Adjusted: " + string(numDetailRecs).
    end.
end procedure.