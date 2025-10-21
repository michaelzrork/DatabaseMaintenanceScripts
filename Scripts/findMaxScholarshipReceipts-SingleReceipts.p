/*------------------------------------------------------------------------
    File        : findMaxScholarshipReceipts.p
    Purpose     : 

    Syntax      : 

    Description : Find receipts where customer paid more than the max scholarship limit

    Author(s)   : michaelzr
    Created     : 7/22/2024
    Notes       : Modified to look for receipts with a single item purchased or paid for
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
define variable numRecs                as integer   no-undo.
define variable scholarshipPaycodeList as character no-undo.
define variable amountPaid             as decimal   no-undo.
define variable amountCharged          as decimal   no-undo.
define variable feeDescription         as character no-undo.
define variable itemID                 as int64     no-undo.
define variable itemCode               as character no-undo.
define variable itemDescription        as character no-undo.
define variable percentPaid            as decimal   no-undo.
define variable hhNum                  as integer   no-undo.
define variable cReceiptNumber         as integer   no-undo.
define variable totalCharged           as decimal   no-undo.
define variable totalPaid              as decimal   no-undo.
assign
    scholarshipPaycodeList = "RecAssist24,RecAssist23,RecAssist"
    amountPaid             = 0
    amountCharged          = 0
    numRecs                = 0
    percentPaid            = 0
    hhNum                  = 0
    cReceiptNumber         = 0
    totalCharged           = 0
    totalPaid              = 0.
    
define temp-table ttReceiptNumber no-undo
    field ttReceiptNumber as integer
    index ttReceiptNumber ttReceiptNumber.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("HH Num,Receipt Number,Log Date, Log Time,User Name,Pay Code,Total Charged On Receipt,Total Paid by Scholarship,Total Paid Above 80%,Total Percent Paid,").

// LOOP THROUGH ALL FEES PAID BY SCHOLARSHIP
fee-loop:
for each ChargeHistory no-lock where lookup(ChargeHistory.PayCode,scholarshipPaycodeList) > 0 and ChargeHistory.RecordStatus = "Paid" and ChargeHistory.FeePaid > 0:
    find ttReceiptNumber where ttReceiptNumber.ttReceiptNumber = ChargeHistory.ReceiptNumber no-error.
    if available ttReceiptNumber then next fee-loop.
    assign 
        amountPaid     = ChargeHistory.FeePaid
        amountCharged  = 0
        totalPaid      = 0
        totalCharged   = 0
        cReceiptNumber = ChargeHistory.ReceiptNumber.
    find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
    if available Charge then assign
            feeDescription = trueval(replace(Charge.Description,",",""))
            itemID         = Charge.ParentRecord
            itemCode       = getString(replace(Charge.ParentCode,",","")).
    find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
    if available TransactionDetail then assign
            itemDescription = getString(replace(TransactionDetail.Description,",",""))
            hhNum           = TransactionDetail.EntityNumber.
    // FIND THE CHARGE FEE FOR THE PAID FEE
    run findChargeFee(ChargeHistory.ID,ChargeHistory.ParentRecord).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMaxScholarshipReceiptsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMaxScholarshipReceiptsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIND CHARGE FEE
procedure findChargeFee:
    define input parameter historyID as int64 no-undo.
    define input parameter feeID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    for first bufChargeHistory no-lock where bufChargeHistory.ID <> historyID and bufChargeHistory.ParentRecord = feeID and bufChargeHistory.ReceiptNumber = cReceiptNumber and bufChargeHistory.RecordStatus = "Charge":
        assign 
            amountCharged = bufChargeHistory.FeeAmount
            // CALCULATE PERCENTAGE OF FEE PAID BY SCHOLARSHIP
            percentPaid   = (amountPaid / amountCharged) * 100.
        // IF FEE PAID BY SCHOLARSHIP IS OVER 80%, FIND RECEIPT TOTALS
        if amountPaid > (amountCharged * 0.80) then run checkReceiptTotals. 
    end.  
end procedure.

// CHECK RECEIPT TOTALS
procedure checkReceiptTotals:
    define buffer bufChargeHistory for ChargeHistory.
    // FIND AND TOTAL EVERY FEE PAID BY SCHOLARSHIP ON THE GIVEN RECEIPT
    for each bufChargeHistory no-lock where bufChargeHistory.ReceiptNumber = cReceiptNumber and lookup(bufChargeHistory.PayCode,scholarshipPaycodeList) > 0 and bufChargeHistory.RecordStatus = "Paid":
        assign
            totalPaid = totalPaid + bufChargeHistory.FeePaid.
    end.
    // FIND AND TOTAL EVERY FEE CHARGED ON THE GIVEN RECEIPT
    for each bufChargeHistory no-lock where bufFeeHIstory.ReceiptNumber = cReceiptNumber and bufChargeHistory.RecordStatus = "Charge":
        totalCharged = totalCharged + bufChargeHistory.FeeAmount.
    end.
    // IF TOTAL PAID BY SCHOLARSHIP IS MORE THAN 80% OF TOTAL CHARGED, ADD IT TO THE LOG
    if totalPaid > (totalCharged * 0.8) then 
    do:
        find ttReceiptNumber where ttReceiptNumber.ttReceiptNumber = cReceiptNumber no-error.
        if not available ttReceiptNumber then 
        do: 
            create ttReceiptNumber.
            assign
                ttReceiptNumber.ttReceiptNumber = cReceiptNumber.
            numRecs = numRecs + 1.
            run put-stream(string(hhNum) + "," + string(cReceiptNumber) + "," + string(ChargeHistory.LogDate) + "," + string(ChargeHistory.LogTime / 86400) + "," + ChargeHistory.UserName + "," + ChargeHistory.PayCode + "," + string(totalCharged) + "," + string(totalPaid) + "," + string(totalPaid - (totalCharged * 0.80)) + "," + string((totalPaid / totalCharged) * 100) + "%" + ",").
        end.
    end.
end procedure.


// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMaxScholarshipReceiptsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMaxScholarshipReceipts.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find receipts where customer paid more than the max scholarship limit"
            BufActivityLog.Detail2       = "Check Document Center for findMaxScholarshipReceiptsLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.