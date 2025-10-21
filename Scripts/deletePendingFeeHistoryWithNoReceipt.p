/*------------------------------------------------------------------------
    File        : deletePendingFeeHistoryWithNoReceipt.p
    Purpose     : 

    Syntax      : 

    Description : Deleted ChargeHistory records with a record status of 'Pending' and receipt number of 0

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

// AUDIT LOG STUFF
define variable numPendingFeesDeleted as integer no-undo.
define variable numRelatedFeesDeleted as integer no-undo.
define variable numSAFeeRecsUpdated   as integer no-undo.
assign
    numPendingFeesDeleted = 0
    numRelatedFeesDeleted = 0
    numSAFeeRecsUpdated   = 0.

// EVERYTHING ELSE
define variable hhNum               as int64     no-undo.
define variable feeHistID           as int64     no-undo.
define variable feeHistReceipt      as integer   no-undo.
define variable feeID               as int64     no-undo.
define variable feeDescription      as character no-undo.
define variable feeGroup            as character no-undo.
define variable origFeeReceipt      as integer   no-undo.
define variable origFeeStatus       as character no-undo.
define variable feeBillingOption    as character no-undo.
define variable feeDueOption        as character no-undo.
define variable detailID            as int64     no-undo.
define variable detailDescription   as character no-undo.
define variable contractID          as int64     no-undo.
define variable contractDescription as character no-undo.
define variable feeType             as character no-undo.

assign 
    hhNum               = 0
    feeHistID           = 0
    feeHistReceipt      = 0
    feeID               = 0
    feeDescription      = ""
    feeGroup            = ""
    origFeeReceipt      = 0
    origFeeStatus       = ""
    feeBillingOption    = ""
    feeDueOption        = ""
    detailID            = 0
    detailDescription   = ""
    contractID          = 0
    contractDescription = ""
    feeType             = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Household Number,
                Modification,
                Table,
                Record ID,
                Record Status,
                Record Receipt Number,
                Fee Amount,
                Fee Paid,
                Charge ID,
                Fee Description,
                Fee Type,
                Fee Group,
                Original Fee Receipt Number,
                Original Fee Record Status,
                Installment Billing Option,
                TransactionDetail ID,
                Item Description,
                Contract ID,
                Contract Description,").

// ChargeHistory Loop
for each ChargeHistory no-lock where ChargeHistory.RecordStatus = "Pending" and ChargeHistory.Receiptnumber = 0:
    
    // FIND LINKED CHARGE, TRANSACTIONDETAIL, AND SACONTRACT FOR LOG FILES
    find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
    if available Charge then find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
    if available TransactionDetail then find first Agreement no-lock where Agreement.ID = TransactionDetail.ContractID no-error no-wait.
    
    // SET LOG FILE VARIABLES
    assign 
        hhNum               = ChargeHistory.PaymentHousehold
        feeHistID           = ChargeHistory.ID
        feeHistReceipt      = ChargeHistory.ReceiptNumber
        feeID               = ChargeHistory.ParentRecord
        feeDescription      = if available Charge then getString(Charge.Description) else "Charge Record Not Available"
        feeType             = if available Charge then getString(Charge.FeeType) else "Charge Record Not Available"
        feeGroup            = if available Charge then getString(Charge.FeeGroupCode) else "Charge Record Not Available"
        origFeeReceipt      = if available Charge then Charge.ReceiptNumber else 0
        origFeeStatus       = if available Charge then Charge.RecordStatus else "Charge Record Not Available"
        feeBillingOption    = if available Charge then Charge.InstallmentBillingOption else "Charge Record Not Available"
        feeDueOption        = if available Charge then Charge.DueOption else "Charge Record Not Available"
        detailID            = if available Charge then Charge.ParentRecord else 0
        detailDescription   = if available TransactionDetail then replace(TransactionDetail.Description,",","") else "TransactionDetail Record Not Available"
        contractID          = if available TransactionDetail then TransactionDetail.ContractID else 0
        contractDescription = if available Agreement then replace(Agreement.ShortDescription,",","") else "Agreement Record Not Available".
    
    
    // DELETE THE PENDING CHARGEHISTORY RECORD     
    run deletePendingFee(feeHistID).
    
    // DELETE THE OTHER CHARGEHISTORY RECORDS LINKED TO THE SAME CHARGE RECORD AS THE PENDING FEE, AS THEY ARE ALSO BAD
    // DO NOT DELETE PAID, BILLED, OR ACCRUED RECORDS
    run deleteRelatedFees(feeHistID).
    
    // CHANGE THE CHARGE TO 'NOCHARGE' AS THEY SHOULD HAVE BEEN IN THE FIRST PLACE
    // BY STARTING WITH THE PENDING FEES WITH A 0 RECEIPT, WE ENSURE WE ARE NOT CHANGING ANY CHARGES THAT WERE INTENTIONALLY SELECTED
    if Charge.RecordStatus = "Charge" then run updateSAFee(feeID).
    
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deletePendingFeeHistoryWithNoReceiptLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deletePendingFeeHistoryWithNoReceiptLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// DELETE PENDING FEE HISTORY RECORD
procedure deletePendingFee:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
        do:
            run put-stream("~"" +
                // Household Number
                getString(string(hhNum)) + "~",~"" +
                // Modification
                "Deleted Pending Fee" + "~",~"" +
                // Table
                "ChargeHistory" + "~",~"" +
                // Record ID
                getString(string(bufChargeHistory.ID)) + "~",~"" +
                // Record Status
                getString(bufChargeHistory.RecordStatus) + "~",~"" +
                // Record Receipt Number
                getString(string(bufChargeHistory.ReceiptNumber)) + "~",~"" +
                // Fee Amount
                getString(string(bufChargeHistory.FeeAmount)) + "~",~"" +
                // Fee Paid
                getString(string(bufChargeHistory.FeePaid)) + "~",~"" +
                // Charge ID
                getString(string(feeID)) + "~",~"" +
                // Fee Description
                getString(feeDescription) + "~",~"" +
                // Fee Type
                getString(feeType) + "~",~"" +
                // Fee Group
                getString(feeGroup) + "~",~"" +
                // Original Fee Receipt Number
                getString(string(origFeeReceipt)) + "~",~"" +
                // Original Fee Record Status
                getString(origFeeStatus) + "~",~"" +
                // Installment Billing Option
                getString(feeBillingOption) + "~",~"" +
                // TransactionDetail ID
                getString(string(detailID)) + "~",~"" +
                // Item Description
                getString(detailDescription) + "~",~"" +
                // Contract ID
                getString(string(contractID)) + "~",~"" + 
                // Contract Description
                getString(contractDescription) + "~",").
            numPendingFeesDeleted = numPendingFeesDeleted + 1.
            delete bufChargeHistory.
        end.
    end.
end procedure.

// DELETE RELATED FEE HISTORY RECORD
procedure deleteRelatedFees:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        for each bufChargeHistory exclusive-lock where bufChargeHistory.ID <> inpID and bufChargeHistory.ParentRecord = feeID:
            run put-stream("~"" + 
                // Household Number
                getString(string(hhNum)) + "~",~"" + 
                // Modification
                "Deleted Related Fee" + "~",~"" +
                // Table
                "ChargeHistory" + "~",~"" +
                // Record ID
                getString(string(bufChargeHistory.ID)) + "~",~"" +
                // Record Status
                getString(bufChargeHistory.RecordStatus) + "~",~"" +
                // Record Receipt Number
                getString(string(bufChargeHistory.ReceiptNumber)) + "~",~"" +
                // Fee Amount
                getString(string(bufChargeHistory.FeeAmount)) + "~",~"" +
                // Fee Paid
                getString(string(bufChargeHistory.FeePaid)) + "~",~"" +
                // Charge ID
                getString(string(feeID)) + "~",~"" +
                // Fee Description
                getString(feeDescription) + "~",~"" +
                // Fee Group
                getString(feeGroup) + "~",~"" +
                // Original Fee Receipt Number
                getString(string(origFeeReceipt)) + "~",~"" +
                // Original Fee Record Status
                getString(origFeeStatus) + "~",~"" +
                // Installment Billing Option
                getString(feeBillingOption) + "~",~"" +
                // TransactionDetail ID
                getString(string(detailID)) + "~",~"" +
                // Item Description
                getString(detailDescription) + "~",~"" +
                // Contract ID
                getString(string(contractID)) + "~",~"" +
                // Contract Description
                getString(contractDescription) + "~",").
            assign
                numRelatedFeesDeleted = numRelatedFeesDeleted + 1.
            delete bufChargeHistory.
        end.
    end.
end procedure.

// UPDATE FEE
procedure updateCharge:
    define input parameter inpID as int64 no-undo.
    define buffer bufCharge for Charge.
    do for bufCharge transaction:
        find first bufCharge exclusive-lock where bufCharge.ID = inpID no-error no-wait.
        if available bufCharge then 
        do:
            assign
                numSAFeeRecsUpdated   = numSAFeeRecsUpdated + 1
                bufCharge.RecordStatus = "NoCharge".
            run put-stream("~"" +
                // Household Number
                getString(string(hhNum)) + "~",~"" +
                // Modification
                "Update Fee to NoCharge" + "~",~"" +
                // Table
                "Charge" + "~",~"" +
                // Record ID
                getString(string(bufCharge.ID)) + "~",~"" +
                // Record Status
                getString(bufCharge.RecordStatus) + "~",~"" +
                // Record Receipt Number
                getString(string(bufCharge.ReceiptNumber)) + "~",~"" +
                // Fee Amount
                getString(string(bufCharge.Amount)) + "~",~"" +
                // Fee Paid
                "N/A" + "~",~"" +
                // Charge ID
                getString(string(feeID)) + "~",~"" +
                // Fee Description
                getString(feeDescription) + "~",~"" +
                // Fee Type
                getString(feeType) + "~",~"" +
                // Fee Group
                getString(feeGroup) + "~",~"" +
                // Original Fee Receipt Number
                getString(string(origFeeReceipt)) + "~",~"" +
                // Original Fee Record Status
                getString(origFeeStatus) + "~",~"" +
                // Installment Billing Option
                getString(feeBillingOption) + "~",~"" +
                // TransactionDetail ID
                getString(string(detailID)) + "~",~"" +
                // Item Description
                getString(detailDescription) + "~",~"" +
                // Contract ID
                getString(string(contractID)) + "~",~"" + 
                // Contract Description
                getString(contractDescription) + "~","). 
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deletePendingFeeHistoryWithNoReceiptLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "deletePendingFeeHistoryWithNoReceipt.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Deleted ChargeHistory records with a record status of 'Pending' and receipt number of 0"
            BufActivityLog.Detail2       = "Check Document Center for deletePendingFeeHistoryWithNoReceiptLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Pending ChargeHistory Records Deleted: " + string(numPendingFeesDeleted)
            bufActivityLog.Detail4       = "Number of Related ChargeHistory Records Deleted: " + string(numRelatedFeesDeleted)
            bufActivityLog.Detail5       = "Number of Charge Records Updated to 'No Charge': " + string(numSAFeeRecsUpdated).
    end.
end procedure.