/*------------------------------------------------------------------------
    File        : findMissingPrepayPaycode.p
    Purpose     : 

    Syntax      : 

    Description : Finds any Installment Bill prepayments with a missing paycode

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
define variable numRecs           as integer   no-undo.
define variable ibBillDate        as character no-undo.
define variable ibReceiptNumber   as integer   no-undo.
define variable ibRecordStatus    as character no-undo.
define variable ibHousehold       as integer   no-undo.
define variable prepayAmount      as decimal   no-undo.
define variable itemDescription   as character no-undo.
define variable prepayPaymentType as character no-undo.
define variable fmName            as character no-undo.
define variable prepayPaycode     as character no-undo.
assign
    numRecs           = 0
    ibReceiptNumber   = 0
    ibRecordStatus    = ""
    ibHousehold       = 0
    prepayAmount      = 0
    itemDescription   = ""
    prepayPaymentType = ""
    fmName            = ""
    prepayPaycode     = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Household Number,Name,ReceiptNumber,Item,Bill Date,Bill Status,Prepay Payment Type,Prepay Amount,Prepay Paycode,").

for each PaymentTransaction no-lock where PaymentTransaction.paycode = "None" and PaymentTransaction.paymenttype begins "Pre" and SAreceiptPayment.receiptnumber = 0:
    assign
        ibBillDate        = ?
        ibReceiptNumber   = 0
        ibHousehold       = 0
        ibRecordStatus    = ""
        prepayAmount      = 0
        prepayPaymentType = ""
        itemDescription   = ""
        fmName            = ""
        prepayPaycode     = "".
    find first ChargeHistory no-lock where ChargeHistory.ID = PaymentTransaction.ParentRecord no-error no-wait.
    if available ChargeHistory then 
    do:
        assign 
            ibBillDate        = if ChargeHistory.BillDate = ? then "No Date" else string(ChargeHistory.BillDate)
            ibReceiptNumber   = if ChargeHistory.ReceiptNumber = ? then 0 else ChargeHistory.ReceiptNumber
            ibRecordStatus    = getString(ChargeHistory.RecordStatus)
            ibHousehold       = if ChargeHistory.PaymentHousehold = ? then 0 else ChargeHistory.PaymentHousehold
            prepayAmount      = if PaymentTransaction.Amount = ? then 0 else PaymentTransaction.Amount
            prepayPaymentType = getString(PaymentTransaction.PaymentType)
            prepayPaycode     = getString(PaymentTransaction.Paycode).
        find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
        if available Charge then find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
        if available TransactionDetail then 
        do:
            assign 
                itemDescription = getString(TransactionDetail.Description)
                fmName          = getString(TransactionDetail.FirstName) + " " + getString(TransactionDetail.LastName)
                numRecs = numRecs + 1.
            run put-stream ("~"" + string(ibHousehold) + "~",~"" + fmName + "~",~"" + string(ibReceiptNumber) + "~",~"" + itemDescription + "~",~"" + ibBillDate + "~",~"" + ibRecordStatus + "~",~"" + prepayPaymentType + "~",~"" + string(prepayAmount) + "~",~"" + prepayPaycode + "~",").
        end.
        
    end.
end.

if numRecs = 0 then run put-stream("No prepay Installment Bill records found with missing paycode").
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingPrepayPaycodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingPrepayPaycodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingPrepayPaycodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingPrepayPaycode.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Finds any Installment Bill prepayments with a missing paycode"
            BufActivityLog.Detail2       = "Check Document Center for findMissingPrepayPaycodeLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.