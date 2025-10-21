/*------------------------------------------------------------------------
    File        : clearDiscountFeeHistory.p
    Purpose     : 

    Syntax      : 

    Description : Clear Discount Fee History without a Standard Fee

    Author(s)   : michaelzr
    Created     : 1/3/2025
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
define variable isFullyPaid as logical   no-undo.

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time.

// EVERYTHING ELSE
define variable numClearedFeeHist       as integer no-undo.
define variable clearedFees             as decimal no-undo.
define variable clearedNotFullyPaidFees as decimal no-undo.
define variable numDetailRecs           as integer no-undo.
define variable hhNum                   as integer no-undo.
define variable numSkippedDiscounts     as integer no-undo. 

assign
    numClearedFeeHist       = 0
    clearedNotFullyPaidFees = 0
    clearedFees             = 0
    numDetailRecs           = 0
    numSkippedDiscounts     = 0
    hhNum                   = 46.
    
define buffer bufCharge for Charge.

def temp-table ttDetail no-undo 
    field TransactionDetailID as int64 
    index TransactionDetailID TransactionDetailID.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Table,Record ID,ChargeHistory Receipt Number,Original Fee Amount,Original Discount Amount,New Fee Amount,Charge ID,Charge Receipt Number,Charge Description,Charge Record Status,PaymentReceipt ID for ChargeHistory Receipt,PaymentReceipt Fee Amount for ChargeHistory Receipt,PaymentReceipt Fee Paid for ChargeHistory Receipt,TransactionDetail ID,TransactionDetail Description,TransactionDetail Current Receipt,TransactionDetail Record Status,TransactionDetail Fully Paid Status,").

feehist-loop:
for each ChargeHistory no-lock where ChargeHistory.PaymentHousehold = hhNum and ChargeHistory.FeeAmount > 0 and ChargeHistory.DiscountAmount = 0 and ChargeHistory.RecordStatus = "Charge":
    find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
    if available Charge and Charge.FeeType begins "Discount" then 
    do:
        find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
        if available TransactionDetail and TransactionDetail.FullyPaid = false then 
        do:
            assign 
                isFullyPaid = TransactionDetail.FullyPaid.
            // IF THERE IS ANOTHER FEE ASSOCIATED WITH THIS TRANSACTIONDETAIL RECORD THAT ISN'T A DISCOUNT, SKIP IT 
            for first bufCharge no-lock where bufCharge.ParentRecord = Charge.ParentRecord and not bufCharge.FeeType begins "Discount":
                assign 
                    numSkippedDiscounts = numSkippedDiscounts + 1.
                next feehist-loop.
            end.
            if not available bufCharge then 
            do:
                find first PaymentReceipt no-lock where PaymentReceipt.ReceiptNumber = ChargeHistory.ReceiptNumber no-error no-wait.
                run clearFeeHistAmount(ChargeHistory.ID).
                if isFullyPaid = false then find first ttDetail no-lock where ttDetail.TransactionDetailID = TransactionDetail.ID no-error no-wait.
                if not available ttDetail then create ttDetail.
                assign 
                    ttDetail.TransactionDetailID = TransactionDetail.ID. 
            end.
        end.
    end. 
end.

for each ttDetail no-lock:
    find first TransactionDetail no-lock where TransactionDetail.ID = ttDetail.TransactionDetailID no-error no-wait.
    if available TransactionDetail and TransactionDetail.FullyPaid = false then run setFullyPaid(TransactionDetail.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "clearDiscountFeeHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "clearDiscountFeeHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CLEAR FEE HISTORY FEE AMOUNT FOR DISCOUNT FEES
procedure clearFeeHistAmount:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
        do:
            run put-stream("~"" +
                // Table
                "ChargeHistory" + "~",~"" +
                // Record ID
                getString(string(bufChargeHistory.ID)) + "~",~"" +
                //ChargeHistory Receipt Number,
                getString(string(bufChargeHistory.ReceiptNumber)) + "~",~"" +
                // Original Fee Amount
                getString(string(bufChargeHistory.FeeAmount)) + "~",~"" +
                // Original Discount Amount
                getString(string(bufChargeHistory.DiscountAmount)) + "~",~"" +
                // New Fee Amount
                "0" + "~",~"" +
                // Charge ID
                getString(string(Charge.ID)) + "~",~"" +
                // Charge Receipt Number
                getString(string(Charge.ReceiptNumber)) + "~",~"" +
                // Charge Description
                getString(Charge.Description) + "~",~"" +
                // Charge Record Status
                getString(Charge.RecordStatus) + "~",~"" +
                // PaymentReceipt ID for ChargeHistory Receipt
                getString(string(PaymentReceipt.ID)) + "~",~"" +
                // PaymentReceipt Fee Amount for ChargeHistory Receipt
                getString(string(PaymentReceipt.FeeAmount)) + "~",~"" +
                // PaymentReceipt Fee Paid for ChargeHistory Receipt
                getString(string(PaymentReceipt.FeePaid)) + "~",~"" +
                // TransactionDetail ID
                getString(string(TransactionDetail.ID)) + "~",~"" +
                // TransactionDetail Description
                getString(TransactionDetail.Description) + "~",~"" +
                // TransactionDetail Current Receipt
                getString(string(TransactionDetail.CurrentReceipt)) + "~",~"" +
                // TransactionDetail Record Status
                getString(TransactionDetail.RecordStatus) + "~",~"" +
                // TransactionDetail Fully Paid Status
                (if isFullyPaid = true then "Yes" else "No")
                + "~",").
            assign
                clearedFees               = clearedFees + bufChargeHistory.FeeAmount
                clearedNotFullyPaidFees   = clearedNotFullyPaidFees + (if isFullyPaid = false then bufChargeHistory.FeeAmount else 0)
                bufChargeHistory.FeeAmount = 0
                numClearedFeeHist         = numClearedFeeHist + 1.
        end.
    end.
end procedure.

// SET TRANSACTIONDETAIL RECORD TO FULLY PAID
procedure setFullyPaid:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then 
        do:
            run put-stream("~"" +
                // Table
                "TransactionDetail" + "~",~"" +
                // Record ID
                getString(string(bufTransactionDetail.ID)) + "~",~"" +
                // ChargeHistory Receipt Number
                "N/A" + "~",~"" +
                // Original Fee Amount
                "N/A" + "~",~"" +
                // Original Discount Amount
                "N/A" + "~",~"" +
                // New Fee Amount
                "N/A" + "~",~"" +
                // Charge ID
                "N/A" + "~",~"" +
                // Charge Receipt Number
                "N/A" + "~",~"" +
                // Charge Description
                "N/A" + "~",~"" +
                // Charge Record Status
                "N/A" + "~",~"" +
                // PaymentReceipt ID for ChargeHistory Receipt
                "N/A" + "~",~"" +
                // PaymentReceipt Fee Amount for ChargeHistory Receipt
                "N/A" + "~",~"" +
                // PaymentReceipt Fee Paid for ChargeHistory Receipt
                "N/A" + "~",~"" +
                // TransactionDetail ID
                getString(string(bufTransactionDetail.ID)) + "~",~"" +
                // TransactionDetail Description
                getString(bufTransactionDetail.Description) + "~",~"" +
                // TransactionDetail Current Receipt
                getString(string(bufTransactionDetail.CurrentReceipt)) + "~",~"" +
                // TransactionDetail Record Status
                getString(bufTransactionDetail.RecordStatus) + "~",~"" +
                // TransactionDetail Fully Paid Status
                (if bufTransactionDetail.FullyPaid = false then "No" else "Yes")
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
    inpfile-loc = sessiontemp() + "clearDiscountFeeHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(600)" skip.
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
            BufActivityLog.SourceProgram = "clearDiscountFeeHistory.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Clear Discount Fee History without a Standard Fee"
            BufActivityLog.Detail2       = "Check Document Center for clearDiscountFeeHistoryLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of ChargeHistory Discounts Cleared: " + string(numClearedFeeHist)
            bufActivityLog.Detail4       = "Total Fee Amount Cleared: " + string(clearedFees) + "; Not Fully Paid Fee Amount Cleared: " + string(clearedNotFullyPaidFees)
            bufActivityLog.Detail5       = "Number of ChargeHistory Discounts Skipped: " + string(numSkippedDiscounts)
            bufActivityLog.Detail6       = "Number of TransactionDetail records set to Fully Paid: " + string(numDetailRecs).
    end.
end procedure.