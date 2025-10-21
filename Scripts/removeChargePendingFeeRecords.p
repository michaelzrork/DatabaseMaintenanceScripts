/*------------------------------------------------------------------------
    File        : removeChargePendingFees.p
    Purpose     : 

    Syntax      : 

    Description : 

    Author(s)   : michaelzr
    Created     : 
    Notes       : - Cloned from updatePendingFeeHistoryBills to fix records where the ChargeHistory record status was incorrectly set to Pending and then ChargePendingFees.p was run
                  - I need to research what ChargePendingFees.p does, so I can reverse those changes; my db edits have only zero'd out LedgerEntry, ChargeHistory, and PaymentReceipt, but are there more changes?
                  - Also necessary is a quick fix to fix the Charge records with Active status and the ChargeHistory records with Pending status, before the Charge Pending Fees program runs
                  - Both fixes will need some serious thought to ensure that I don't break anything. 
                  - It can be safely assumed that if a fee has a clone ID and a record status of Active that it's wrong. But what should it be is the question I need to figure out.
                  - It can also be safely assumed that if a fee history record is Pending, but the fee has no Due Option, that it is also wrong.
                    But what should that be? If the fee is Charge, should it be Charge? Or was the fee set to Charge incorrectly? If it's NoCharge, then should we delete the fee history?
                    Or was it set to NoCharge incorrectly?
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
define variable numRecs         as integer no-undo.
define variable numBills        as integer no-undo.
define variable numMissingBills as integer no-undo.
assign
    numRecs         = 0
    numBills        = 0
    numMissingBills = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Fee,HouseholdNumber,LogDate,ParentID,ID,ReceiptNumber,Description,Old Record Status,New RecordStatus,BillDate,Notes,Charge RecordStatus").

// FEEHISTORY LOOP
// STARTING WITH RECORDS WHERE THE NOTES MENTION "PENDING FEES", AS THESE ARE THE RECORDS TOUCHED BY CHARGEPENDINGFEES.P
for each ChargeHistory no-lock where index(ChargeHistory.Notes,"Pending Fees") > 0:
    for first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord and Charge.CloneID <> 0 and Charge.DueOption = "" and lookup(Charge.RecordStatus,"Active,Charge,NoCharge") > 0: // DO I NEED TO ACCOUNT FOR RECORDSTATUS HERE?
        // BELOW IS THE ORIGINAL CODE FOR THE BILLING CHANGE - NEED TO UPDATE THESE OR ADD NEW ONES; MIGHT NEED TO DO A QUERY HERE BEFORE MAKING CHANGES
        run updateFeeHistory(ChargeHistory.ID).
        run logBillingFee(ChargeHistory.ParentRecord).
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "removeChargePendingFeesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "removeChargePendingFeesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog3.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// UPDATE FEE HISTORY TO CHARGE
procedure updateFeeHistory:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.          
        if available bufChargeHistory then 
        do:
            // CREATE LOG ENTRY "Fee,HouseholdNumber,LogDate,ParentID,ID,ReceiptNumber,Description,Old Record Status,New RecordStatus,BillDate,Notes,Charge RecordStatus"
            run put-stream ("Pending Fee" + "," + string(bufChargeHistory.PaymentHousehold) + "," + string(bufChargeHistory.LogDate) + "," + string(bufChargeHistory.ParentRecord) + "," + string(bufFeeHIstory.ID) + "," + string(bufChargeHistory.ReceiptNumber) + "," + Charge.Description + "," + bufChargeHistory.RecordStatus + "," + "Charge" + "," + "" + "," + bufChargeHistory.Notes + "," + Charge.RecordStatus).
            assign
                numRecs = numRecs + 1.
                bufChargeHistory.RecordStatus = "Charge".
            
        end.
    end.
end. 

// CREATE BILLING RECORD LOGS
procedure logBillingFee:
    define input parameter inpID as int64 no-undo.
    define variable hasBill as logical no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        assign 
            hasBill = false.
        for each bufChargeHistory no-lock where bufChargeHistory.ParentRecord = inpID and index(bufChargeHistory.RecordStatus,"bill") > 0:
        // CREATE LOG ENTRY "Fee,HouseholdNumber,LogDate,ParentID,ID,ReceiptNumber,Description,Old Record Status,New RecordStatus,BillDate,Notes,Charge RecordStatus"
            run put-stream ("Billing Fee" + "," + string(bufChargeHistory.PaymentHousehold) + "," + string(bufChargeHistory.LogDate) + "," + string(bufChargeHistory.ParentRecord) + "," + string(bufFeeHIstory.ID) + "," + string(bufChargeHistory.ReceiptNumber) + "," + Charge.Description + "," + bufChargeHistory.RecordStatus + "," + "" + "," + (if bufChargeHistory.BillDate <> ? then string(bufChargeHistory.BillDate) else "No Bill Date") + "," + bufChargeHistory.Notes + "," + Charge.RecordStatus).
            assign
                hasBill  = true
                numBills = numBills + 1.
        end.
        if not hasBill then 
        do:
        // CREATE LOG ENTRY "Fee,HouseholdNumber,LogDate,ParentID,ID,ReceiptNumber,Description,Old Record Status,New RecordStatus,BillDate,Notes,Charge RecordStatus"
            run put-stream ("No Billing Fee Record" + "," + string(ChargeHistory.PaymentHousehold) + "," + string(ChargeHistory.LogDate) + "," + string(inpID) + "," + "" + "," + string(ChargeHistory.ReceiptNumber) + "," + Charge.Description + "," + "" + "," + "" + "," + "" + "," + "" + "," + Charge.RecordStatus).
            assign
                numMissingBills = numMissingBills + 1.
        end.
    end.
end.

// CREATE LOG FILE FOR removeChargePendingFees.p
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "removeChargePendingFeesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
procedure ActivityLog3:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "removeChargePendingFees.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Update Pending Bills to Charge"
            BufActivityLog.Detail2       = "Check Document Center for removeChargePendingFeesLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Adjusted: " + string(numRecs) + "; Number of Bills Found: " + string(numBills) + "; Number of Records with No Bill: " + string(numMissingBills).
    end.
end procedure.