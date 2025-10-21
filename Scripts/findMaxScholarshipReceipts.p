/*------------------------------------------------------------------------
    File        : findMaxScholarshipReceipts.p
    Purpose     : 

    Syntax      : 

    Description : Find receipts where customer paid more than the max scholarship limit

    Author(s)   : michaelzr
    Created     : 7/22/2024
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
define variable numRecs            as integer   no-undo.
define variable scholarshipPaycode as character no-undo.
define variable amountPaid         as decimal   no-undo.
define variable amountCharged      as decimal   no-undo.
define variable feeDescription     as character no-undo.
define variable itemID             as int64     no-undo.
define variable itemCode           as character no-undo.
define variable itemDescription    as character no-undo.
define variable percentPaid        as decimal   no-undo.
define variable hhNum              as integer   no-undo.
assign
    scholarshipPaycode = "RecAssist24,RecAssist23,RecAssist"
    amountPaid         = 0
    amountCharged      = 0
    numRecs            = 0
    percentPaid        = 0
    hhNum              = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Payment ChargeHistory ID,Charge ID,Log Date,Log Time,HH Num,Receipt Number,User,Fee Description,Paycode,Amount Charged,Amount Paid,Amount Paid Over 80%,Percentage Paid by Scholarship,Item Code,Item Description,").

for each ChargeHistory no-lock where lookup(ChargeHistory.PayCode,scholarshipPayCode) > 0 and ChargeHistory.RecordStatus = "Paid" and ChargeHistory.FeePaid > 0:
    assign 
        amountPaid    = ChargeHistory.FeePaid
        amountCharged = 0.
    find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
    if available Charge then assign
            feeDescription = trueval(replace(Charge.Description,",",""))
            itemID         = Charge.ParentRecord
            itemCode       = getString(replace(Charge.ParentCode,",","")).
    find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
    if available TransactionDetail then assign
            itemDescription = getString(replace(TransactionDetail.Description,",",""))
            hhNum           = TransactionDetail.EntityNumber.
    run findChargeFee(ChargeHistory.ID,ChargeHistory.ParentRecord,ChargeHistory.ReceiptNumber).
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
    define input parameter inpID as int64 no-undo.
    define input parameter cParentID as int64 no-undo.
    define input parameter cReceiptNumber as integer no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    for first bufChargeHistory no-lock where bufChargeHistory.ID <> inpID and bufChargeHistory.ParentRecord = cParentID and bufChargeHistory.ReceiptNumber = cReceiptNumber and bufChargeHistory.RecordStatus = "Charge":
        assign 
            amountCharged = bufChargeHistory.FeeAmount
            percentPaid   = (amountPaid / amountCharged) * 100.
            // "Payment ChargeHistory ID,Charge ID,Log Date,Log Time,HH Num,Receipt Number,User,Fee Description,Paycode,Amount Charged,Amount Paid,Amount Paid Over 80%,Percentage Paid by Scholarship,Item Code,Item Description,"
        if amountPaid > (amountCharged * 0.80) then 
        do:
            numRecs = numRecs + 1.
            run put-stream (string(ChargeHistory.ID) + "," + string(cParentID) + "," + string(ChargeHistory.LogDate) + "," + string(ChargeHistory.LogTime / 86400) + "," + string(hhNum) + "," + string(cReceiptNumber) + "," + ChargeHistory.UserName + "," + feeDescription + "," + ChargeHistory.PayCode + "," + string(amountCharged) + "," + string(amountPaid) + "," + string(amountPaid - (amountCharged * 0.80)) + "," + string(percentPaid) + "%" + "," + itemCode + "," + itemDescription + ",").
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