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
define variable numSAFeeHistoryRecsDeleted as integer no-undo.
assign
    numSAFeeHistoryRecsDeleted = 0.

// EVERYTHING ELSE


/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Household Number,ChargeHistory.ID,ChargeHistory.RecordStatus,ChargeHistory.ReceiptNumber,ChargeHistory.ParentTable,ChargeHistory.ParentRecord,Charge.Description,Charge.FeeGroupCode,Charge.ReceiptNumber,Charge.RecordStatus,Charge.InstallmentBillingOption,Charge.ParentTable,Charge.ParentRecord,TransactionDetail.Description,TransactionDetail.ContractID,Agreement.ShortDescription").

// ChargeHistory Loop
for each ChargeHistory no-lock where ChargeHistory.RecordStatus = "Pending" and Receiptnumber = 0 and ChargeHistory.PaymentHousehold = 1069246:
    run deleteSAFeeHistory(ChargeHistory.ID).
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

// DELETE FEE HISTORY RECORD
procedure deleteSAFeeHistory:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
        do:
            find first Charge no-lock where Charge.ID = bufChargeHistory.ParentRecord no-error no-wait.
            if available Charge then find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
            if available TransactionDetail then find first Agreement no-lock where Agreement.ID = TransactionDetail.ContractID no-error no-wait.
            run put-stream(string(bufChargeHistory.PaymentHousehold) + "," + string(bufChargeHistory.ID) + "," + bufChargeHistory.RecordStatus + "," + string(bufChargeHistory.ReceiptNumber) + "," +
                bufChargeHistory.ParentTable + "," + string(bufChargeHistory.ParentRecord)  + "," + (if not available Charge then "No Charge Record" else Charge.Description) + "," + (if not available Charge then "No Charge Record" else Charge.FeeGroupCode) + "," + (if not available Charge then "No Charge Record" else string(Charge.ReceiptNumber)) + "," + (if not available Charge then "No Charge Record" else Charge.RecordStatus) + "," + (if not available Charge then "No Charge Record" else Charge.InstallmentBillingOption) + "," + 
                (if not available Charge then "No Charge Record" else Charge.ParentTable) + "," + (if not available Charge then "No Charge Record" else string(Charge.ParentRecord))  + "," + (if not available TransactionDetail then "No TransactionDetail Record" else TransactionDetail.Description)  + "," + 
                (if not available TransactionDetail then "No TransactionDetail Record" else string(TransactionDetail.ContractID)) + "," + (if not available Agreement then "No Agreement Record" else Agreement.ShortDescription)).
            numSAFeeHistoryRecsDeleted = numSAFeeHistoryRecsDeleted + 1.
            delete bufChargeHistory.
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
            BufActivityLog.Detail3       = "Number of ChargeHistory Records Deleted: " + string(numSAFeeHistoryRecsDeleted).
    end.
end procedure.