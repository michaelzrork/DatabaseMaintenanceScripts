/*------------------------------------------------------------------------
    File        : deletePendingFeeHistory.p
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

inpfile-num = 1.

// AUDIT LOG STUFF
define variable numPendingFeesDeleted as integer  no-undo.
define variable numRelatedFeesDeleted as integer  no-undo.
define variable numSAFeeRecsUpdated   as integer  no-undo.
define variable saFeeIDList           as character  no-undo.
define variable ix                    as integer  no-undo.

assign
    numPendingFeesDeleted = 0
    numRelatedFeesDeleted = 0
    numSAFeeRecsUpdated   = 0
    ix                    = 0.
    

// EVERYTHING ELSE

&GLOBAL-DEFINE SaFeeHistPaid         "Paid"
&GLOBAL-DEFINE SaFeeHistBilled       "Billed"
&GLOBAL-DEFINE SaFeeHistCancelled    "Cancelled"
&GLOBAL-DEFINE SaFeeHistAccrual      "Accrual"

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// LOGS ARE OUT OF WHACK! NEED TO RETHINK HOW TO CREATE THEM AND THE ORDER OF WHICH THEY ARE CREATED!!!
// FINISHING THE LOGIC FIRST - FIXING THE FIRST RUN OF RECORDS TO MATCH LOGIC OF UPDATED VERSION
// CONSIDER CHANGES FOR UPDATING TO V3

{Includes/ChargeHistoryStatusList.i}

// CREATE LOG FILE FIELDS
run put-stream ("Account Number,ChargeHistory.ID,ChargeHistory.RecordStatus,ChargeHistory.ReceiptNumber,ChargeHistory.ParentTable,ChargeHistory.ParentRecord,Charge.Description,Charge.FeeGroupCode,Charge.ReceiptNumber,Charge.RecordStatus,Charge.InstallmentBillingOption,Charge.ParentTable,Charge.ParentRecord,TransactionDetail.Description,TransactionDetail.ContractID,Agreement.ShortDescription").

// ChargeHistory Loop
do ix = 1 to num-entries(saFeeIDList):
    for first Charge no-lock where Charge.ID = int64(entry(ix,saFeeIDList)):
        find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
        if available TransactionDetail then find first Agreement no-lock where Agreement.ID = TransactionDetail.ContractID no-error no-wait.
        for each ChargeHistory no-lock where ChargeHistory.ParentRecord = Charge.ID and lookup(ChargeHistory.RecordStatus,"Paid,Billed,Cancelled,Accrual") = 0:
            run deleteChargeHistory(ChargeHistory.ID).
            if lookup(Charge.RecordStatus,"Charge,Reset") > 0 then run updateSAFee(Charge.ID).
        end.
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deletePendingFeeHistoryLog" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deletePendingFeeHistoryLog" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// DELETE PENDING FEE HISTORY RECORD
procedure deleteChargeHistory:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
        do:
            run put-stream(string(bufChargeHistory.PaymentHousehold) + "," + string(bufChargeHistory.ID) + "," + bufChargeHistory.RecordStatus + "," + string(bufChargeHistory.ReceiptNumber) + "," +
                bufChargeHistory.ParentTable + "," + string(bufChargeHistory.ParentRecord)  + "," + (if not available Charge then "No Charge Record" else Charge.Description) + "," + (if not available Charge then "No Charge Record" else Charge.FeeGroupCode) + "," + (if not available Charge then "No Charge Record" else string(Charge.ReceiptNumber)) + "," + (if not available Charge then "No Charge Record" else Charge.RecordStatus) + "," + (if not available Charge then "No Charge Record" else Charge.InstallmentBillingOption) + "," + 
                (if not available Charge then "No Charge Record" else Charge.ParentTable) + "," + (if not available Charge then "No Charge Record" else string(Charge.ParentRecord))  + "," + (if not available TransactionDetail then "No TransactionDetail Record" else TransactionDetail.Description)  + "," + 
                (if not available TransactionDetail then "No TransactionDetail Record" else string(TransactionDetail.ContractID)) + "," + (if not available Agreement then "No Agreement Record" else Agreement.ShortDescription)).
            numPendingFeesDeleted = numPendingFeesDeleted + 1.
            delete bufChargeHistory.
        end.
    end.
end procedure.

// DELETE RELATED FEE HISTORY RECORD
procedure deleteRelatedFees:
    define input parameter inpID as int64 no-undo.
    define input parameter feeID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        for each bufChargeHistory exclusive-lock where bufChargeHistory.ID <> inpID and bufChargeHistory.ParentRecord = feeID:
            run put-stream(string(bufChargeHistory.PaymentHousehold) + "," + string(bufChargeHistory.ID) + "," + bufChargeHistory.RecordStatus + "," + string(bufChargeHistory.ReceiptNumber) + "," +
                bufChargeHistory.ParentTable + "," + string(bufChargeHistory.ParentRecord)  + "," + (if not available Charge then "No Charge Record" else Charge.Description) + "," + (if not available Charge then "No Charge Record" else Charge.FeeGroupCode) + "," + (if not available Charge then "No Charge Record" else string(Charge.ReceiptNumber)) + "," + (if not available Charge then "No Charge Record" else Charge.RecordStatus) + "," + (if not available Charge then "No Charge Record" else Charge.InstallmentBillingOption) + "," + 
                (if not available Charge then "No Charge Record" else Charge.ParentTable) + "," + (if not available Charge then "No Charge Record" else string(Charge.ParentRecord))  + "," + (if not available TransactionDetail then "No TransactionDetail Record" else TransactionDetail.Description)  + "," + 
                (if not available TransactionDetail then "No TransactionDetail Record" else string(TransactionDetail.ContractID)) + "," + (if not available Agreement then "No Agreement Record" else Agreement.ShortDescription)).
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
            run put-stream(string(ChargeHistory.PaymentHousehold) + "," + string(ChargeHistory.ID) + "," + ChargeHistory.RecordStatus + "," + string(ChargeHistory.ReceiptNumber) + "," +
                ChargeHistory.ParentTable + "," + string(ChargeHistory.ParentRecord)  + "," + (if not available bufCharge then "No Charge Record" else bufCharge.Description) + "," + (if not available bufCharge then "No Charge Record" else bufCharge.FeeGroupCode) + "," + (if not available bufCharge then "No Charge Record" else string(bufCharge.ReceiptNumber)) + "," + (if not available bufCharge then "No Charge Record" else bufCharge.RecordStatus) + "," + (if not available bufCharge then "No Charge Record" else bufCharge.InstallmentBillingOption) + "," + 
                (if not available bufCharge then "No Charge Record" else bufCharge.ParentTable) + "," + (if not available bufCharge then "No Charge Record" else string(bufCharge.ParentRecord))  + "," + (if not available TransactionDetail then "No TransactionDetail Record" else TransactionDetail.Description)  + "," + 
                (if not available TransactionDetail then "No TransactionDetail Record" else string(TransactionDetail.ContractID)) + "," + (if not available Agreement then "No Agreement Record" else Agreement.ShortDescription)).
            assign
                numSAFeeRecsUpdated   = numSAFeeRecsUpdated + 1
                bufCharge.RecordStatus = "NoCharge".
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deletePendingFeeHistoryLog" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 15000 then 
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
            BufActivityLog.SourceProgram = "deletePendingFeeHistory.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Deleted ChargeHistory records with a record status of 'Pending' and receipt number of 0"
            BufActivityLog.Detail2       = "Check Document Center for deletePendingFeeHistoryLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Pending ChargeHistory Records Deleted: " + string(numPendingFeesDeleted)
            bufActivityLog.Detail4       = "Number of Related ChargeHistory Records Deleted: " + string(numRelatedFeesDeleted)
            bufActivityLog.Detail5       = "Number of Charge Records Updated: " + string(numSAFeeRecsUpdated).
    end.
end procedure.