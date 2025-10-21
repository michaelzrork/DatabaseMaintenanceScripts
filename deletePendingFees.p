/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "deletePendingFees" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Deletes Pending fees with no due option set"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 3/28/25
   Notes       : - There have been many attempts to write a quick fix to resolve this issue, but I think this is the cleanest and easiest way to do it
                 - Unlike previous attempts, the goal of this one is to just delete any Pending fee without a due option, regardless of if it's still in the Active/Pending
                   record status, or if it's been updated to Charge/Charge
                 - This will use the ParentID Charge.DueOption to confirm if it was legitimately supposed to be a Pending fee, if not, the ChargeHistory and Charge get deleted
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

function ParseList character (inputValue as char) forward.
function RoundUp returns decimal(dValue as decimal,precision as integer) forward.
function AddCommas returns character (dValue as decimal) forward.

define stream   ex-port.
define variable InpFile-Num        as integer   no-undo init 1.
define variable InpFile-Loc        as character no-undo init "".
define variable Counter            as integer   no-undo init 0.
define variable ixLog              as integer   no-undo init 1. 
define variable LogfileDate        as date      no-undo.
define variable LogfileTime        as integer   no-undo.
define variable ActivityLogID         as int64     no-undo init 0.
define variable LogOnly            as logical   no-undo init false.
define variable FeeHistDeleted     as integer   no-undo init 0. 
define variable FeesDeleted        as integer   no-undo init 0.
define variable numMissingDetail   as integer   no-undo init 0.
define variable numMissingFee      as integer   no-undo init 0.
define variable FeeHistSkipped     as integer   no-undo init 0.
define variable FeeSkipped         as integer   no-undo init 0.
define variable DeleteFeeHist      as logical   no-undo init true.
define variable DeleteFee          as logical   no-undo init true.
define variable hhNum              as int64     no-undo init 0.
define variable DetailID           as int64     no-undo init 0.
define variable DetailDescription  as character no-undo init "".
define variable DetailReceiptList  as character no-undo init "".
define variable DetailRecordStatus as character no-undo init "".
define variable cModule            as character no-undo init "".
define variable FeeID              as int64     no-undo init 0.
define variable FeeLogDate         as date      no-undo init ?.
define variable FeeReceiptNumber   as integer   no-undo init 0.
define variable FeeRecordStatus    as character no-undo init "".
define variable cFeeType           as character no-undo init "".
define variable cTransactionType   as character no-undo init "".
define variable cFeeGroupCode      as character no-undo init "".
define variable dFeeAmount         as decimal   no-undo init 0.
define variable FeeParentID        as int64     no-undo init 0.
define variable xCloneID           as int64     no-undo init 0.
define variable NoteValue          as character no-undo init "".
define variable TotalDue           as decimal   no-undo init 0.
define variable isFullyPaid        as logical   no-undo init false.
define variable numChargeFeeHist   as integer   no-undo init 0.
define variable ClientCode             as character no-undo init "".
define variable cLastID            as character no-undo init "".
define variable LastTable          as character no-undo init "".
define variable numRecs            as integer   no-undo init 0.
define variable numDetail          as integer   no-undo init 0.
define variable chargeIDs          as character no-undo init "".
define variable numGLDist          as integer   no-undo init 0.
define variable numReceipt         as integer   no-undo init 0.
define variable HasPayment         as logical   no-undo init false.
define variable feeHistLogged      as integer   no-undo init 0.
define variable TotalPaid          as decimal   no-undo init 0.
define variable TotalCharged       as decimal   no-undo init 0.
define variable ChargeFeeAmount    as decimal   no-undo init 0.

assign
    LogfileDate = today
    LogfileTime = time
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false.
    
define temp-table ttCharge
    field ID as int64
    index ID ID.
    
define temp-table ttDetail
    field ID as int64
    index ID ID.
    
define temp-table ttDeletedRecord
    field ID as int64 
    index ID ID.
    
define buffer BufFeeHist for ChargeHistory.

find first CustomField no-lock where CustomField.FieldName = "ClientID" no-error no-wait.
if available CustomField then assign ClientCode = getString(CustomField.FieldValue).

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

run ActivityLog({&ProgramDescription},"Program in Progress","Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(feeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).

/* CREATE LOG FILE FIELD HEADERS */
/* I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER */
run put-stream (
    "ChargeHistory.ID," +
    "LogNotes," +
    "HouseholdNumber," +
    "Module," +
    "TransactionDetail.ID," +
    "TransactionDetail.Description," +
    "TransactionDetail.RecordStatus," +
    "TransactionDetail.ReceiptList," +
    "ChargeHistory.ReceiptNumber," +
    "ChargeHistory.LogDate," +
    "ChargeHistory.RecordStatus," +
    "ChargeHistory.FeeAmount," +
    "ChargeHistory.FeePaid," +
    "ChargeHistory.DiscountAmount," + 
    "ChargeHistory.TimeCount," +
    "ChargeHistory.Quantity," +
    "ChargeHistory.BillDate," +
    "ChargeHistory.Notes," +
    "ChargeHistory.MiscInformation," +
    "Charge.ID," +
    "Charge.LogDate," +
    "Charge.ReceiptNumber," +
    "Charge.RecordStatus," +
    "Charge.FeeType," +
    "Charge.TransactionType," +
    "Charge.FeeGroupCode," +
    "Charge.Amount," +
    "Charge.ParentRecord," +
    "Charge.CloneID,").

/* FIND EVERY CHARGEHISTORY RECORD THAT IS CURRENTLY IN PENDING STATUS OR THAT HAS BEEN IN PENDING STATUS THAT WAS NOT A PRE-PAID BILL */
feehist-loop:
for each ChargeHistory no-lock where (ChargeHistory.recordstatus = "Pending" or (index(ChargeHistory.notes,"Pending Fees") > 0 and index(ChargeHistory.MiscInformation,"OriginalReceipt") > 0)) and ChargeHistory.RecordStatus <> "Billed":
    
    /* RESET VARIABLES */
    assign
        DeleteFeeHist      = true
        DeleteFee          = true
        hhNum              = 0
        DetailID           = 0
        DetailDescription  = ""
        DetailReceiptList  = ""
        DetailRecordStatus = ""
        cModule            = ""
        FeeID              = 0
        FeeLogDate         = ?
        FeeReceiptNumber   = 0
        FeeRecordStatus    = ""
        cFeeType           = ""
        cTransactionType   = ""
        cFeeGroupCode      = ""
        dFeeAmount         = 0
        FeeParentID        = 0
        xCloneID           = 0
        NoteValue          = "".
    
    /* ONLY MOVE ON IF THE CHARGE DOES NOT HAVE THE DUE OPTION SET */
    for first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord:
        if Charge.DueOption <> "" and Charge.DueOption <> "Not Applicable" then next feehist-loop.
        
        /* SET CHARGE VARIABLES */
        assign
            FeeID            = Charge.ID
            FeeLogDate       = Charge.LogDate
            FeeReceiptNumber = Charge.ReceiptNumber
            FeeRecordStatus  = Charge.RecordStatus
            cFeeType         = Charge.FeeType
            cTransactionType = Charge.TransactionType
            cFeeGroupCode    = Charge.FeeGroupCode
            dFeeAmount       = Charge.Amount
            FeeParentID      = Charge.ParentRecord
            xCloneID         = Charge.CloneID.
    
        /* AND WE DON'T NEED TO WORRY ABOUT FEES FOR TRANSACTIONS THAT ARE NOT YET COMPLETE */
        for first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord:
            if not TransactionDetail.Complete then next feehist-loop.
            
            /* SET TRANSACTIONDETAIL VARIABLES */
            assign
                DetailID           = TransactionDetail.ID
                DetailReceiptList  = TransactionDetail.ReceiptList
                hhNum              = TransactionDetail.EntityNumber
                DetailDescription  = TransactionDetail.Description
                DetailRecordStatus = TransactionDetail.RecordStatus
                cModule            = TransactionDetail.Module
                DeleteFeeHist      = true
                NoteValue          = "ChargeHistory Deleted; Charge and TransactionDetail Records Found".
                
            /* ADD TRANSACTIONDETAIL RECORD TO TEMP TABLE TO BE RECALCULATED LATER */
            find first ttDetail no-lock where ttDetail.ID = TransactionDetail.ID no-error no-wait.
            if not available ttDetail then 
            do:
                create ttDetail.
                assign 
                    ttDetail.ID = TransactionDetail.ID.
            end.
        end.
        
        if not available TransactionDetail then 
        do:
            /* SET MISSING TRANSACTIONDETAIL VARIABLES */
            assign
                DetailID           = Charge.ParentRecord
                DetailReceiptList  = "N/A"
                hhNum              = ChargeHistory.PaymentHousehold
                DetailDescription  = "N/A"
                DetailRecordStatus = "N/A"
                cModule            = Charge.Module.
                
            /* IF LOCKED, LOG AND DELETE */
            if locked TransactionDetail then 
            do:
                assign
                    DeleteFeeHist = true
                    NoteValue     = "ChargeHistory Deleted; Charge Record Found, TransactionDetail Record Locked".
                
                /* ADD TRANSACTIONDETAIL RECORD TO TEMP TABLE TO BE RECALCULATED LATER */
                find first ttDetail no-lock where ttDetail.ID = Charge.ParentRecord no-error no-wait.
                if not available ttDetail then 
                do:
                    create ttDetail.
                    assign 
                        ttDetail.ID = Charge.ParentRecord.
                end.
            end.
            
            /* IF TRANSACTIONDETAIL NOT AVAILABLE AND NOT LOCKED, DELETE THE CHARGEHISTORY RECORD */
            else
            do:
                assign 
                    NumMissingDetail = NumMissingDetail + 1
                    DeleteFeeHist    = true
                    NoteValue        = "ChargeHistory Deleted; Charge Found, TransactionDetail Record Missing".
            end.
        end.
        
        assign
            HasPayment   = false
            DeleteFee    = true
            TotalPaid    = 0
            TotalCharged = 0.

        /* FIND ANY PAID FEE HISTORY RECORD LINKED TO THE SAME PARENT ID */
        paid-loop:
        for each BufFeeHist no-lock where BufFeeHist.ParentRecord = ChargeHistory.ParentRecord
            and BufFeeHist.RecordStatus = "Paid"
            and BufFeeHist.ID <> ChargeHistory.ID:
            if index(getString(BufFeeHist.MiscInformation),"OriginalReceipt") = 0 and index(getString(BufFeeHist.Notes),"Pending Fees") = 0 then 
            do:
                /* IF RECORD FOUND WITH PAYMENT SKIP DELETING CHARGE RECORD AND TRIGGER UPDATE OF TIME COUNT AND QUANTITY ON RELATED CHARGE RECORD */
                assign
                    TotalPaid  = TotalPaid + BufFeeHist.FeePaid
                    DeleteFee  = if BufFeeHist.FeePaid = 0 then true else false // IF THE PAID AMOUNT IS $0 THEN WE CAN STILL DELETE THE CHARGE RECORD
                    HasPayment = if BufFeeHist.FeePaid = 0 then false else true. // IF THE PAID AMOUNT IS $0 THEN DO NOT COUNT AS A PAYMENT AND DELETE THE CHARGEHISTORY RECORD
            
                /* IF $0 PAYMENT THEN  */
                if HasPayment then run logChargeHistory(BufFeeHist.ID,"Paid ChargeHistory Record Found; Charge Record Skipped").
                else run deleteChargeHistory(BufFeeHist.ID,"Paid ChargeHistory Record Deleted with $0 Paid; Charge Record Not Skipped",yes).
            end.
        end.
        
        /* FIND ALL OTHER RELATED FEE HISTORY RECORDS */
        charge-loop:
        for each BufFeeHist no-lock where BufFeeHist.ParentRecord = ChargeHistory.ParentRecord
            and BufFeeHist.ID <> ChargeHistory.ID 
            and BufFeeHist.RecordStatus = "Charge":
            if index(getString(BufFeeHist.MiscInformation),"OriginalReceipt") = 0 and index(getString(BufFeeHist.Notes),"Pending Fees") = 0 then 
            do:
                /* GRAB TOTAL CHARGED FOR CURRENT RECORD */
                assign
                    ChargeFeeAmount = BufFeeHist.FeeAmount * BufFeeHist.Quantity * BufFeeHist.TimeCount.
                    
                /* IF THERE HAS BEEN NO PAYMENT THEN CHECK THE CHARGE FEE AMOUNT */
                if not HasPayment then 
                do:
                    /* IF CHARGE AMOUNT EQUALS ZERO, DELETE THE CHARGE FEE HISTORY RECORD */
                    if ChargeFeeAmount = 0 then 
                    do:
                        run deleteChargeHistory(BufFeeHist.ID,"Charge ChargeHistory Record Deleted, No Paid Record and $0 in Fee Amount; Charge Record Not Skipped",yes).
                        next charge-loop.
                    end.
                    /* IF THE CHARGE RECORD HAS A FEE AMOUNT, LOG AS POTENTIAL VALID FEE */
                    else 
                    do:
                        assign 
                            DeleteFee = false.
                        run logChargeHistory(BufFeeHist.ID,"Charge ChargeHistory Record Logged, No Paid Record; Charge Record Skipped").
                        next charge-loop.
                    end.
                end.
                
                /* IF THERE HAS BEEN A PAYMENT, CALCULATE TOTAL CHARGED */
                else 
                do:
                    if ChargeFeeAmount = 0 and BufFeeHist.FeeAmount <> 0 then 
                    do:
                        /* UPDATE THE TIME COUNT AND QUANTITY */
                        assign
                            TotalCharged = TotalCharged + (BufFeeHist.FeeAmount * ChargeHistory.Quantity * ChargeHistory.TimeCount). 
                        run fixCounts(BufFeeHist.ID,ChargeHistory.TimeCount,ChargeHistory.Quantity).
                    end.
                    else if ChargeFeeAmount = 0 and BufFeeHist.FeeAmount = 0 then 
                        do:
                            /* DELETE $0 CHARGE RECORD */
                            run deleteChargeHistory(BufFeeHist.ID,"Charge ChargeHistory Record Deleted, Paid Record Found with $0 Charge Fee Amount; Charge Record Not Skipped").
                        end.
                        else if ChargeFeeAmount <> 0 then 
                            do:
                                assign
                                    TotalCharged = TotalCharged + ChargeFeeAmount
                                    DeleteFee    = false.
                                run logChargeHistory(BufFeeHist.ID,"Charge ChargeHistory Record Logged, Paid Record Found; Charge Record Skipped").
                            end.
                end.
            end.
        end.
        
        if HasPayment and TotalCharged - TotalPaid <> 0 and (ChargeHistory.FeeAmount * ChargeHistory.Quantity * ChargeHistory.TimeCount) - TotalPaid = 0 and TotalPaid <> 0 then 
        do:
            assign 
                NoteValue     = replace(NoteValue,"ChargeHistory Deleted","Pending ChargeHistory Record Not Deleted, Paid Record Found with No Charge Record")
                DeleteFeeHist = false.
        end.
        
        /* IF NO ADDITIONAL CHARGEHISTORY RECORDS WERE FOUND THAT ARE/WERE NOT PENDING, DELETE THE CHARGE RECORD AS WELL */
        if DeleteFee then 
        do:
            /* CHECK TO SEE IF WE'VE ALREADY LOGGED THE FEE TO BE DELETED - WE DON'T NEED TO TRY TO DELETE IT TWICE */
            find first ttCharge no-lock where ttCharge.ID = Charge.ID no-error no-wait.
            if not available ttCharge then
            do:
                create ttCharge.
                assign
                    ttCharge.ID = Charge.ID.
            end.
            
            for each SAGLDIstribution no-lock where LedgerEntry.FeeLinkID = Charge.ID and LedgerEntry.ReceiptNumber = ChargeHistory.ReceiptNumber:
                run deleteGLDistribution(LedgerEntry.ID).
            end.
            
            for each PaymentReceipt no-lock where PaymentReceipt.ReceiptNumber = ChargeHistory.ReceiptNumber:
                run deleteSAReceipt(PaymentReceipt.ID).
            end.
            
        end.
        
        /* IF ADDITIONAL CHARGEHISTORY RECORDS WERE FOUND, COUNT THE CHARGE AS SKIPPED */
        else 
        do:
            assign 
                FeeSkipped = FeeSkipped + 1.
        end.
    
    end.
   
    /* IF THE PARENT ID OF THE CHARGEHISTORY RECORD DOESN'T FIND AN CHARGE RECORD, CHECK TO SEE IF IT'S AN TRANSACTIONDETAIL ID */
    if not available Charge then 
    do:
        /* ASSIGN MISSING CHARGE VARIABLES */
        assign
            FeeID              = 0
            FeeLogDate         = ?
            FeeReceiptNumber   = 0
            FeeRecordStatus    = "N/A"
            cFeeType           = "N/A"
            cTransactionType   = "N/A"
            cFeeGroupCode      = "N/A"
            dFeeAmount         = 0
            FeeParentID        = 0
            xCloneID           = 0
            DetailID           = 0
            DetailReceiptList  = "N/A"
            hhNum              = ChargeHistory.PaymentHousehold
            DetailDescription  = "N/A"
            DetailRecordStatus = "N/A"
            cModule            = "N/A".
            
        /* IF CHARGE LOCKED, SKIP DELETING THE CHARGEHISTORY RECORD */
        if locked Charge then 
        do:
            assign
                FeeID         = ChargeHistory.ParentRecord
                DeleteFeeHist = false
                NoteValue     = "ChargeHistory Skipped; Charge Record Locked".
        end.
        
        /* IF NOT AVAILABLE CHARGE AND NOT LOCKED, CHECK CHARGEHISTORY PARENT ID AGAINST TRANSACTIONDETAIL */
        else 
        do:
            find first TransactionDetail no-lock where TransactionDetail.ID = ChargeHistory.ParentRecord no-error no-wait.
        
            /* IF TRANSACTIONDETAIL FOUND LOG FEE HISTORY TO REVIEW, BUT DON'T DELETE IT */
            if available TransactionDetail then 
            do:
                assign 
                    NumMissingFee      = NumMissingFee + 1
                    DetailID           = TransactionDetail.ID
                    DetailReceiptList  = TransactionDetail.ReceiptList
                    hhNum              = TransactionDetail.EntityNumber
                    DetailDescription  = TransactionDetail.Description
                    DetailRecordStatus = TransactionDetail.RecordStatus
                    cModule            = TransactionDetail.Module
                    DeleteFeeHist      = false
                    NoteValue          = "ChargeHistory Skipped; No Charge Record Found, TransactionDetail Record Found".
            end.
        
            if not available TransactionDetail then 
            do:        
                /* IF TRANSACTIONDETAIL RECORD FOUND, BUT LOCKED, LOG IT TO REVIEW LATER AND DON'T DELETE IT */
                if locked TransactionDetail then 
                do:
                    assign
                        NumMissingFee = NumMissingFee + 1
                        DetailID      = ChargeHistory.ParentRecord
                        DeleteFeeHist = false
                        NoteValue     = "ChargeHistory Skipped; No Charge Record Found, TransactionDetail Record Locked".
                end.
                
                /* IF TRANSACTIONDETAIL RECORD NOT FOUND, DELETE CHARGEHISTORY */
                else
                do:
                    assign 
                        NumMissingFee    = NumMissingFee + 1
                        NumMissingDetail = NumMissingDetail + 1
                        feeID            = ChargeHistory.ParentRecord
                        DeleteFeeHist    = true
                        NoteValue        = "ChargeHistory Deleted; No Charge or TransactionDetail Records Found".
                end.
            end.
        end.
    end.

    run deleteChargeHistory(ChargeHistory.ID,NoteValue,DeleteFeeHist).
    
end.

/* ONCE DONE WITH THE CHARGEHISTORY RECORDS, DELETE THE CORRESPONDING CHARGE RECORDS */
for each ttCharge no-lock:
    find first Charge no-lock where Charge.ID = ttCharge.ID no-error no-wait.
    if available Charge then 
    do:
        run deleteCharge(Charge.ID).
    end.
end.

/* RECALC TRANSACTIONDETAIL FULLY PAID STATUS */
if not LogOnly then 
do:
    for each ttDetail no-lock:
        assign 
            TotalDue = 0.
        find first TransactionDetail no-lock where TransactionDetail.ID = ttDetail.ID no-error no-wait.
        run Business/CalculateTransactionTotal.p  /* External calculation service */ ("TransactionDetail", "TotalDue", ?, "", "", TransactionDetail.ID, output TotalDue).  
        assign 
            isFullyPaid = if totalDue gt 0 then false else true.
        if TransactionDetail.FullyPaid <> isFullyPaid then run fixSADetail(TransactionDetail.ID,isFullyPaid).
    end.
end.

/* UPDATE AUDIT LOG TO SAY THE LOGFILE IS BEING CREATED */
run UpdateActivityLog({&ProgramDescription},
    "Program in Progress; Logfile is being created...",
    "Number of ChargeHistory Records Deleted: " + addCommas(FeeHistDeleted) + "; Skipped: " + addCommas(FeeHistSkipped),
    "Number of Charge Records Deleted: " + addCommas(FeesDeleted) + "; Skipped: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted: " + addCommas(numReceipt),
    "Number of Related ChargeHistory Records Logged: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated: " + addCommas(numDetail)). 
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run UpdateActivityLog({&ProgramDescription},"Program Complete; Check Document Center for a log of Records Changed","Number of ChargeHistory Records Deleted: " + addCommas(FeeHistDeleted) + "; Skipped: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted: " + addCommas(FeesDeleted) + "; Skipped: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated: " + addCommas(numDetail)).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* DELETE SARECEIPT */
procedure deletePaymentReceipt:
    define input parameter inpID as int64 no-undo.
    define buffer BufReceipt for PaymentReceipt.
    do for BufReceipt transaction:
        if LogOnly then 
        do:
            find first ttDeletedRecord no-lock where ttDeletedRecord.ID = inpID no-error no-wait.
            if available ttDeletedRecord then return.
            create ttDeletedRecord.
            assign 
                ttDeletedRecord.ID = inpID.
            find first BufReceipt no-lock where BufReceipt.ID = inpID no-error no-wait.
            if available BufReceipt then 
            do:
                assign 
                    cLastID   = getString(string(BufReceipt.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "PaymentReceipt". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                assign
                    numReceipt = numReceipt + 1.
            end.
        end.
        else 
        do:
            find first BufReceipt exclusive-lock where BufReceipt.ID = inpID no-error no-wait.
            if available BufReceipt then 
            do:
                assign 
                    cLastID   = getString(string(BufReceipt.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "PaymentReceipt". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                assign
                    numReceipt = numReceipt + 1.
                delete BufReceipt.
            end.
        end.
    end.
end procedure.

/* DELETE SAGLDISTRIBUTION */
procedure deleteGLDistribution:
    define input parameter inpID as int64 no-undo.
    define buffer BufLedgerEntry for LedgerEntry.
    do for BufLedgerEntry transaction:
        if LogOnly then 
        do:
            find first ttDeletedRecord no-lock where ttDeletedRecord.ID = inpID no-error no-wait.
            if available ttDeletedRecord then return.
            create ttDeletedRecord.
            assign 
                ttDeletedRecord.ID = inpID.
            find first BufLedgerEntry no-lock where BufLedgerEntry.ID = inpID no-error no-wait.
            if available BufLedgerEntry then 
            do:
                assign 
                    cLastID   = getString(string(BufLedgerEntry.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "LedgerEntry". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                assign 
                    numGLDist = numGLDist + 1.
            end.
        end.
        else 
        do:
            find first BufLedgerEntry exclusive-lock where BufLedgerEntry.ID = inpID no-error no-wait.
            if available BufLedgerEntry then 
            do:
                assign 
                    cLastID   = getString(string(BufLedgerEntry.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "LedgerEntry". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                assign 
                    numGLDist = numGLDist + 1.
                delete BufLedgerEntry.
            end.
        end.
    end.
end procedure.


/* FIX TRANSACTIONDETAIL FULLY PAID TOGGLE */
procedure fixTransactionDetail:
    define input parameter inpID as int64 no-undo.
    define input parameter isPaid as logical no-undo.
    define buffer BufTransactionDetail for TransactionDetail.
    do for BufTransactionDetail transaction:
        find first TransactionDetail exclusive-lock where TransactionDetail.ID = inpID no-error no-wait.
        if available TransactionDetail then 
        do:
            assign 
                cLastID   = getString(string(BufTransactionDetail.ID)) // REPLACE 0 WITH TABLENAME.ID 
                LastTable = "TransactionDetail". // REPLACE <TABLE NAME> WITH THE TALBE NAME
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
            assign 
                numDetail          = numDetail + 1
                TransactionDetail.FullyPaid = isPaid.
        end.
    end.
end procedure.
    
    
/* UPDATE TIME COUNT AND QUANTITY OF CHARGE RECORD */
procedure fixCounts:
    define input parameter inpID as int64 no-undo.
    define input parameter dTimeCount as decimal no-undo.
    define input parameter dQuantity as decimal no-undo.
    define buffer BufChargeHistory for ChargeHistory.
    do for BufChargeHistory transaction:
        if LogOnly then 
        do:
            for first BufChargeHistory no-lock where BufChargeHistory.ID = inpID:
                
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(BufChargeHistory.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "ChargeHistory". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                    
                run put-stream ("~"" +
                    /*ChargeHistory.ID*/
                    getString(string(BufChargeHistory.ID))
                    + "~",~"" +
                    /*LogNotes*/
                    "Charge ChargeHistory Record Updated with Time Count and Quantity; Charge Record Skipped"
                    + "~",~"" +
                    /*HouseholdNumber*/
                    getString(string(hhNum))
                    + "~",~"" +
                    /*Module*/
                    getString(cModule)
                    + "~",~"" +
                    /*TransactionDetail.ID*/
                    getString(string(DetailID))
                    + "~",~"" +
                    /*TransactionDetail.Description*/
                    getString(DetailDescription)
                    + "~",~"" +
                    /*TransactionDetail.RecordStatus*/
                    getString(DetailRecordStatus)
                    + "~",~"" +
                    /*TransactionDetail.ReceiptList*/
                    getString(replace(DetailReceiptList,",",", "))
                    + "~",~"" +
                    /*ChargeHistory.ReceiptNumber*/
                    getString(string(BufChargeHistory.ReceiptNumber))
                    + "~",~"" +
                    /*ChargeHistory.LogDate*/
                    getString(string(BufChargeHistory.LogDate))
                    + "~",~"" +
                    /*ChargeHistory.RecordStatus*/
                    getString(BufChargeHistory.RecordStatus)
                    + "~",~"" +
                    /*ChargeHistory.FeeAmount*/
                    getString(string(BufChargeHistory.FeeAmount))
                    + "~",~"" +
                    /*ChargeHistory.FeePaid*/
                    getString(string(BufChargeHistory.FeePaid))
                    + "~",~"" +
                    /*ChargeHistory.DiscountAmount*/
                    getString(string(BufChargeHistory.DiscountAmount))
                    + "~",~"" +
                    /*ChargeHistory.TimeCount*/
                    "Old: " + getString(string(BufChargeHistory.TimeCount)) + "; New: " + string(dQuantity)
                    + "~",~"" +
                    /*ChargeHistory.Quantity*/
                    "Old: " + getString(string(BufChargeHistory.Quantity)) + "; New: " + string(dTimeCount)
                    + "~",~"" +
                    /*ChargeHistory.BillDate*/
                    getString(string(BufChargeHistory.BillDate))
                    + "~",~"" +
                    /*ChargeHistory.Notes*/
                    getString(parseList(BufChargeHistory.Notes))
                    + "~",~"" +
                    /*ChargeHistory.MiscInformation*/
                    getString(parseList(BufChargeHistory.MiscInformation))
                    + "~",~"" +
                    /*Charge.ID*/
                    getString(string(FeeID))
                    + "~",~"" +
                    /*Charge.LogDate*/
                    getString(string(FeeLogDate))
                    + "~",~"" +
                    /*Charge.ReceiptNumber*/
                    getString(string(FeeReceiptNumber))
                    + "~",~"" +
                    /*Charge.RecordStatus*/
                    getString(FeeRecordStatus)
                    + "~",~"" +
                    /*Charge.FeeType*/
                    getString(cFeeType)
                    + "~",~"" +
                    /*Charge.TransactionType*/
                    getString(cTransactionType)
                    + "~",~"" +
                    /*Charge.FeeGroupCode*/
                    getString(cFeeGroupCode)
                    + "~",~"" +
                    /*Charge.Amount*/
                    getString(string(dFeeAmount))
                    + "~",~"" +
                    /*Charge.ParentRecord*/
                    getString(string(FeeParentID))
                    + "~",~"" +
                    /*Charge.CloneID*/
                    getString(string(xCloneID))
                    + "~",").
                assign 
                    numChargeFeeHist = numChargeFeeHist + 1.
            end.
        end.
        else 
        do:
            for first BufChargeHistory exclusive-lock where BufChargeHistory.ID = inpID:
                
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(BufChargeHistory.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "ChargeHistory". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                    
                run put-stream ("~"" +
                    /*ChargeHistory.ID*/
                    getString(string(BufChargeHistory.ID))
                    + "~",~"" +
                    /*LogNotes*/
                    "Charge ChargeHistory Record Updated with Time Count and Quantity"
                    + "~",~"" +
                    /*HouseholdNumber*/
                    getString(string(hhNum))
                    + "~",~"" +
                    /*Module*/
                    getString(cModule)
                    + "~",~"" +
                    /*TransactionDetail.ID*/
                    getString(string(DetailID))
                    + "~",~"" +
                    /*TransactionDetail.Description*/
                    getString(DetailDescription)
                    + "~",~"" +
                    /*TransactionDetail.RecordStatus*/
                    getString(DetailRecordStatus)
                    + "~",~"" +
                    /*TransactionDetail.ReceiptList*/
                    getString(replace(DetailReceiptList,",",", "))
                    + "~",~"" +
                    /*ChargeHistory.ReceiptNumber*/
                    getString(string(BufChargeHistory.ReceiptNumber))
                    + "~",~"" +
                    /*ChargeHistory.LogDate*/
                    getString(string(BufChargeHistory.LogDate))
                    + "~",~"" +
                    /*ChargeHistory.RecordStatus*/
                    getString(BufChargeHistory.RecordStatus)
                    + "~",~"" +
                    /*ChargeHistory.FeeAmount*/
                    getString(string(BufChargeHistory.FeeAmount))
                    + "~",~"" +
                    /*ChargeHistory.FeePaid*/
                    getString(string(BufChargeHistory.FeePaid))
                    + "~",~"" +
                    /*ChargeHistory.DiscountAmount*/
                    getString(string(BufChargeHistory.DiscountAmount))
                    + "~",~"" +
                    /*ChargeHistory.TimeCount*/
                    "Old: " + getString(string(BufChargeHistory.TimeCount)) + "; New: " + string(dQuantity)
                    + "~",~"" +
                    /*ChargeHistory.Quantity*/
                    "Old: " + getString(string(BufChargeHistory.Quantity)) + "; New: " + string(dTimeCount)
                    + "~",~"" +
                    /*ChargeHistory.BillDate*/
                    getString(string(BufChargeHistory.BillDate))
                    + "~",~"" +
                    /*ChargeHistory.Notes*/
                    getString(parseList(BufChargeHistory.Notes))
                    + "~",~"" +
                    /*ChargeHistory.MiscInformation*/
                    getString(parseList(BufChargeHistory.MiscInformation))
                    + "~",~"" +
                    /*Charge.ID*/
                    getString(string(FeeID))
                    + "~",~"" +
                    /*Charge.LogDate*/
                    getString(string(FeeLogDate))
                    + "~",~"" +
                    /*Charge.ReceiptNumber*/
                    getString(string(FeeReceiptNumber))
                    + "~",~"" +
                    /*Charge.RecordStatus*/
                    getString(FeeRecordStatus)
                    + "~",~"" +
                    /*Charge.FeeType*/
                    getString(cFeeType)
                    + "~",~"" +
                    /*Charge.TransactionType*/
                    getString(cTransactionType)
                    + "~",~"" +
                    /*Charge.FeeGroupCode*/
                    getString(cFeeGroupCode)
                    + "~",~"" +
                    /*Charge.Amount*/
                    getString(string(dFeeAmount))
                    + "~",~"" +
                    /*Charge.ParentRecord*/
                    getString(string(FeeParentID))
                    + "~",~"" +
                    /*Charge.CloneID*/
                    getString(string(xCloneID))
                    + "~",").
                assign 
                    BufChargeHistory.TimeCount = dTimeCount
                    BufChargeHistory.Quantity  = dQuantity
                    numChargeFeeHist          = numChargeFeeHist + 1.
            end.
        end.
    end.
end procedure.
    
/* DELETE FEE HISTORY */
procedure DeleteSAFeeHistory:
    define input parameter inpID as int64 no-undo.
    define input parameter LogNotes as character no-undo.
    define input parameter DeleteFeeHistory as logical no-undo.
    define buffer BufChargeHistory for ChargeHistory.
    do for BufChargeHistory transaction:
        if LogOnly then 
        do:
            find first ttDeletedRecord no-lock where ttDeletedRecord.ID = inpID no-error no-wait.
            if available ttDeletedRecord then return.
            create ttDeletedRecord.
            assign 
                ttDeletedRecord.ID = inpID.
            find first BufChargeHistory no-lock where BufChargeHistory.ID = inpID no-error no-wait.
            if available BufChargeHistory then 
            do:
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(BufChargeHistory.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "ChargeHistory". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                
                run put-stream ("~"" +
                    /*ChargeHistory.ID*/
                    getString(string(BufChargeHistory.ID))
                    + "~",~"" +
                    /*LogNotes*/
                    LogNotes
                    + "~",~"" +
                    /*HouseholdNumber*/
                    getString(string(hhNum))
                    + "~",~"" +
                    /*Module*/
                    getString(cModule)
                    + "~",~"" +
                    /*TransactionDetail.ID*/
                    getString(string(DetailID))
                    + "~",~"" +
                    /*TransactionDetail.Description*/
                    getString(DetailDescription)
                    + "~",~"" +
                    /*TransactionDetail.RecordStatus*/
                    getString(DetailRecordStatus)
                    + "~",~"" +
                    /*TransactionDetail.ReceiptList*/
                    getString(replace(DetailReceiptList,",",", "))
                    + "~",~"" +
                    /*ChargeHistory.ReceiptNumber*/
                    getString(string(BufChargeHistory.ReceiptNumber))
                    + "~",~"" +
                    /*ChargeHistory.LogDate*/
                    getString(string(BufChargeHistory.LogDate))
                    + "~",~"" +
                    /*ChargeHistory.RecordStatus*/
                    getString(BufChargeHistory.RecordStatus)
                    + "~",~"" +
                    /*ChargeHistory.FeeAmount*/
                    getString(string(BufChargeHistory.FeeAmount))
                    + "~",~"" +
                    /*ChargeHistory.FeePaid*/
                    getString(string(BufChargeHistory.FeePaid))
                    + "~",~"" +
                    /*ChargeHistory.DiscountAmount*/
                    getString(string(BufChargeHistory.DiscountAmount))
                    + "~",~"" +
                    /*ChargeHistory.TimeCount*/
                    getString(string(BufChargeHistory.TimeCount))
                    + "~",~"" +
                    /*ChargeHistory.Quantity*/
                    getString(string(BufChargeHistory.Quantity))
                    + "~",~"" +
                    /*ChargeHistory.BillDate*/
                    getString(string(BufChargeHistory.BillDate))
                    + "~",~"" +
                    /*ChargeHistory.Notes*/
                    getString(parseList(BufChargeHistory.Notes))
                    + "~",~"" +
                    /*ChargeHistory.MiscInformation*/
                    getString(parseList(BufChargeHistory.MiscInformation))
                    + "~",~"" +
                    /*Charge.ID*/
                    getString(string(FeeID))
                    + "~",~"" +
                    /*Charge.LogDate*/
                    getString(string(FeeLogDate))
                    + "~",~"" +
                    /*Charge.ReceiptNumber*/
                    getString(string(FeeReceiptNumber))
                    + "~",~"" +
                    /*Charge.RecordStatus*/
                    getString(FeeRecordStatus)
                    + "~",~"" +
                    /*Charge.FeeType*/
                    getString(cFeeType)
                    + "~",~"" +
                    /*Charge.TransactionType*/
                    getString(cTransactionType)
                    + "~",~"" +
                    /*Charge.FeeGroupCode*/
                    getString(cFeeGroupCode)
                    + "~",~"" +
                    /*Charge.Amount*/
                    getString(string(dFeeAmount))
                    + "~",~"" +
                    /*Charge.ParentRecord*/
                    getString(string(FeeParentID))
                    + "~",~"" +
                    /*Charge.CloneID*/
                    getString(string(xCloneID))
                    + "~",").
                    
                if DeleteFeeHistory then 
                do: 
                    FeeHistDeleted = FeeHistDeleted + 1.
                end.
                else 
                do:
                    assign 
                        FeeHistSkipped = FeeHistSkipped + 1.
                end.
            end.
        end.
        else 
        do:
            find first BufChargeHistory exclusive-lock where BufChargeHistory.ID = inpID no-error no-wait.
            if available BufChargeHistory then 
            do:
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(BufChargeHistory.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "ChargeHistory". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
            
                run put-stream ("~"" +
                    /*ChargeHistory.ID*/
                    getString(string(BufChargeHistory.ID))
                    + "~",~"" +
                    /*LogNotes*/
                    LogNotes
                    + "~",~"" +
                    /*HouseholdNumber*/
                    getString(string(hhNum))
                    + "~",~"" +
                    /*Module*/
                    getString(cModule)
                    + "~",~"" +
                    /*TransactionDetail.ID*/
                    getString(string(DetailID))
                    + "~",~"" +
                    /*TransactionDetail.Description*/
                    getString(DetailDescription)
                    + "~",~"" +
                    /*TransactionDetail.RecordStatus*/
                    getString(DetailRecordStatus)
                    + "~",~"" +
                    /*TransactionDetail.ReceiptList*/
                    getString(replace(DetailReceiptList,",",", "))
                    + "~",~"" +
                    /*ChargeHistory.ReceiptNumber*/
                    getString(string(BufChargeHistory.ReceiptNumber))
                    + "~",~"" +
                    /*ChargeHistory.LogDate*/
                    getString(string(BufChargeHistory.LogDate))
                    + "~",~"" +
                    /*ChargeHistory.RecordStatus*/
                    getString(BufChargeHistory.RecordStatus)
                    + "~",~"" +
                    /*ChargeHistory.FeeAmount*/
                    getString(string(BufChargeHistory.FeeAmount))
                    + "~",~"" +
                    /*ChargeHistory.FeePaid*/
                    getString(string(BufChargeHistory.FeePaid))
                    + "~",~"" +
                    /*ChargeHistory.DiscountAmount*/
                    getString(string(BufChargeHistory.DiscountAmount))
                    + "~",~"" +
                    /*ChargeHistory.TimeCount*/
                    getString(string(BufChargeHistory.TimeCount))
                    + "~",~"" +
                    /*ChargeHistory.Quantity*/
                    getString(string(BufChargeHistory.Quantity))
                    + "~",~"" +
                    /*ChargeHistory.BillDate*/
                    getString(string(BufChargeHistory.BillDate))
                    + "~",~"" +
                    /*ChargeHistory.Notes*/
                    getString(parseList(BufChargeHistory.Notes))
                    + "~",~"" +
                    /*ChargeHistory.MiscInformation*/
                    getString(parseList(BufChargeHistory.MiscInformation))
                    + "~",~"" +
                    /*Charge.ID*/
                    getString(string(FeeID))
                    + "~",~"" +
                    /*Charge.LogDate*/
                    getString(string(FeeLogDate))
                    + "~",~"" +
                    /*Charge.ReceiptNumber*/
                    getString(string(FeeReceiptNumber))
                    + "~",~"" +
                    /*Charge.RecordStatus*/
                    getString(FeeRecordStatus)
                    + "~",~"" +
                    /*Charge.FeeType*/
                    getString(cFeeType)
                    + "~",~"" +
                    /*Charge.TransactionType*/
                    getString(cTransactionType)
                    + "~",~"" +
                    /*Charge.FeeGroupCode*/
                    getString(cFeeGroupCode)
                    + "~",~"" +
                    /*Charge.Amount*/
                    getString(string(dFeeAmount))
                    + "~",~"" +
                    /*Charge.ParentRecord*/
                    getString(string(FeeParentID))
                    + "~",~"" +
                    /*Charge.CloneID*/
                    getString(string(xCloneID))
                    + "~",").
                    
                if DeleteFeeHistory then 
                do: 
                    assign 
                        FeeHistDeleted = FeeHistDeleted + 1.
                    delete BufChargeHistory.
                end.
                else 
                do:
                    assign 
                        FeeHistSkipped = FeeHistSkipped + 1.
                end.
            end.
        end.
    end.
end procedure.     

/* DELETE FEE HISTORY */
procedure logChargeHistory:
    define input parameter inpID as int64 no-undo.
    define input parameter LogNotes as character no-undo.
    define buffer BufChargeHistory for ChargeHistory.
    do for BufChargeHistory transaction:
        find first BufChargeHistory no-lock where BufChargeHistory.ID = inpID no-error no-wait.
        if available BufChargeHistory then 
        do:
            /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
            assign 
                cLastID   = getString(string(BufChargeHistory.ID)) // REPLACE 0 WITH TABLENAME.ID 
                LastTable = "ChargeHistory". // REPLACE <TABLE NAME> WITH THE TALBE NAME
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                
            run put-stream ("~"" +
                /*ChargeHistory.ID*/
                getString(string(BufChargeHistory.ID))
                + "~",~"" +
                /*LogNotes*/
                LogNotes
                + "~",~"" +
                /*HouseholdNumber*/
                getString(string(hhNum))
                + "~",~"" +
                /*Module*/
                getString(cModule)
                + "~",~"" +
                /*TransactionDetail.ID*/
                getString(string(DetailID))
                + "~",~"" +
                /*TransactionDetail.Description*/
                getString(DetailDescription)
                + "~",~"" +
                /*TransactionDetail.RecordStatus*/
                getString(DetailRecordStatus)
                + "~",~"" +
                /*TransactionDetail.ReceiptList*/
                getString(replace(DetailReceiptList,",",", "))
                + "~",~"" +
                /*ChargeHistory.ReceiptNumber*/
                getString(string(BufChargeHistory.ReceiptNumber))
                + "~",~"" +
                /*ChargeHistory.LogDate*/
                getString(string(BufChargeHistory.LogDate))
                + "~",~"" +
                /*ChargeHistory.RecordStatus*/
                getString(BufChargeHistory.RecordStatus)
                + "~",~"" +
                /*ChargeHistory.FeeAmount*/
                getString(string(BufChargeHistory.FeeAmount))
                + "~",~"" +
                /*ChargeHistory.FeePaid*/
                getString(string(BufChargeHistory.FeePaid))
                + "~",~"" +
                /*ChargeHistory.DiscountAmount*/
                getString(string(BufChargeHistory.DiscountAmount))
                + "~",~"" +
                /*ChargeHistory.TimeCount*/
                getString(string(BufChargeHistory.TimeCount))
                + "~",~"" +
                /*ChargeHistory.Quantity*/
                getString(string(BufChargeHistory.Quantity))
                + "~",~"" +
                /*ChargeHistory.BillDate*/
                getString(string(BufChargeHistory.BillDate))
                + "~",~"" +
                /*ChargeHistory.Notes*/
                getString(parseList(BufChargeHistory.Notes))
                + "~",~"" +
                /*ChargeHistory.MiscInformation*/
                getString(parseList(BufChargeHistory.MiscInformation))
                + "~",~"" +
                /*Charge.ID*/
                getString(string(FeeID))
                + "~",~"" +
                /*Charge.LogDate*/
                getString(string(FeeLogDate))
                + "~",~"" +
                /*Charge.ReceiptNumber*/
                getString(string(FeeReceiptNumber))
                + "~",~"" +
                /*Charge.RecordStatus*/
                getString(FeeRecordStatus)
                + "~",~"" +
                /*Charge.FeeType*/
                getString(cFeeType)
                + "~",~"" +
                /*Charge.TransactionType*/
                getString(cTransactionType)
                + "~",~"" +
                /*Charge.FeeGroupCode*/
                getString(cFeeGroupCode)
                + "~",~"" +
                /*Charge.Amount*/
                getString(string(dFeeAmount))
                + "~",~"" +
                /*Charge.ParentRecord*/
                getString(string(FeeParentID))
                + "~",~"" +
                /*Charge.CloneID*/
                getString(string(xCloneID))
                + "~",").
                    
            assign 
                FeeHistLogged = FeeHistLogged + 1.
        end.
        
    end.
end procedure.     

procedure deleteSAFee:
    define input parameter inpID as int64 no-undo.
    define buffer BufCharge for Charge.
    do for BufCharge transaction:
        if LogOnly then 
        do:
            find first ttDeletedRecord no-lock where ttDeletedRecord.ID = inpID no-error no-wait.
            if available ttDeletedRecord then return.
            create ttDeletedRecord.
            assign 
                ttDeletedRecord.ID = inpID.
            find first BufCharge no-lock where BufCharge.ID = inpID no-error no-wait.
            if available BufCharge then 
            do:
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(BufCharge.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "Charge". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                
                assign 
                    FeesDeleted = FeesDeleted + 1.
            end.
        end.
        else 
        do:
            find first BufCharge exclusive-lock where BufCharge.ID = inpID no-error no-wait.
            if available BufCharge then 
            do:
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(BufCharge.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "Charge". // REPLACE <TABLE NAME> WITH THE TALBE NAME
                run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of ChargeHistory Records Deleted So Far: " + addCommas(FeeHistDeleted) + "; Skipped So Far: " + addCommas(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + addCommas(FeesDeleted) + "; Skipped So Far: " + addCommas(FeeSkipped) + "; Number of LedgerEntry Records Deleted So Far: " + addCommas(numGLDist) + "; Number of PaymentReceipt Records Deleted So Far: " + addCommas(numReceipt),"Number of Related ChargeHistory Records Logged So Far: " + addCommas(FeeHistLogged) + ", ChargeHistory Charge Records Updated: " + addCommas(numChargeFeeHist) + "; Number of Missing Charge Records So Far: " + addCommas(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + addCommas(NumMissingDetail) + "; Number of TransactionDetail Records FullyPaid Updated So Far: " + addCommas(numDetail)).
                
                assign 
                    FeesDeleted = FeesDeleted + 1.
                delete BufCharge.
            end.
        end.
    end.
end procedure.
             
/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port unformatted inpfile-info skip.
    counter = counter + 1.
    if counter gt 100000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    define input parameter LogDetail5 as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = {&ProgramName} + ".r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = LogDetail1
            BufActivityLog.Detail2       = LogDetail2
            BufActivityLog.Detail3       = LogDetail3
            BufActivityLog.Detail4       = LogDetail4
            BufActivityLog.Detail5       = LogDetail5.
        /* IF THIS IS THE FIRST AUDIT LOG ENTRY, UPDATE THE ID FIELD */
        if ActivityLogID = 0 then 
            assign
                ActivityLogID = BufActivityLog.ID.
    end.
end procedure.

/* UPDATE AUDIT LOG STATUS ENTRY */
procedure UpdateActivityLog:
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    define input parameter LogDetail5 as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        if ActivityLogID = 0 then return.
        find first BufActivityLog exclusive-lock where BufActivityLog.ID = ActivityLogID no-error no-wait.
        if available BufActivityLog then 
            assign
                BufActivityLog.LogDate = today
                BufActivityLog.LogTime = time
                BufActivityLog.Detail1 = LogDetail1
                BufActivityLog.Detail2 = LogDetail2
                BufActivityLog.Detail3 = LogDetail3
                BufActivityLog.Detail4 = LogDetail4
                BufActivityLog.Detail5 = LogDetail5.
    end.
end procedure.

/*************************************************************************
                            INTERNAL FUNCTIONS
*************************************************************************/

/* FUNCTION RETURNS A COMMA SEPARATED LIST FROM CHR(30) SEPARATED LIST IN A SINGLE VALUE */
function ParseList character (inputValue as char):
    if index(inputValue,chr(31)) > 0 and index(inputValue,chr(30)) > 0 then 
        return replace(replace(inputValue,chr(31),": "),chr(30),", ").
    else if index(inputValue,chr(30)) > 0 and index(inputValue,chr(31)) = 0 then
            return replace(inputValue,chr(30),": ").
        else if index(inputValue,chr(30)) = 0 and index(inputValue,chr(31)) > 0 then
                return replace(inputValue,chr(31),": ").
            else return inputValue.
end.

/* FUNCTION RETURNS A DECIMAL ROUNDED UP TO THE PRECISION VALUE */
function RoundUp returns decimal(dValue as decimal,precision as integer):
    define variable newValue  as decimal   no-undo.
    define variable decLoc    as integer   no-undo.
    define variable tempValue as character no-undo.
    define var      tempInt   as integer   no-undo.
    
    /* IF THE TRUNCATED VALUE MATCHES THE INPUT VALUE, NO ROUNDING IS NECESSARY; RETURN THE ORIGINAL VALUE */
    if dValue - truncate(dValue,precision) = 0 then
        return dValue.
            
    /* IF THE ORIGINAL VALUE MINUS THE TRUNCATED VALUE LEAVES A REMAINDER THEN ROUND UP */
    else 
    do:
        assign
            /* FINDS THE LOCATION OF THE DECIMAL SO IT CAN BE ADDED BACK IN LATER */
            decLoc    = index(string(truncate(dValue,precision)),".")
            /* TRUNCATES TO THE PRECISION POINT, DROPS THE DECIMAL, CONVERTS TO AN INT, THEN IF NEGATIVE SUBTRACTS ONE, IF POSITIVE ADDS ONE */
            tempValue = string(integer(replace(string(truncate(dValue,precision)),".","")) + if dValue < 0 then -1 else 1).
        /* ADDS THE DECIMAL BACK IN AT THE ORIGINAL LOCATION */
        assign 
            substring(tempValue,(if decLoc = 0 then length(tempValue) + 1 else decLoc),0) = ".".
        /* RETURNS THE RESULTING VALUE AS A DECIMAL */ 
        return decimal(tempValue).
    end.
end.

/* FUNCTION RETURNS A NUMBER AS A CHARACTER WITH ADDED COMMAS */
function AddCommas returns character (dValue as decimal):
    define variable absValue     as decimal   no-undo.
    define variable iValue       as integer   no-undo.
    define variable cValue       as character no-undo.
    define variable ix           as integer   no-undo.
    define variable decimalValue as character no-undo.
    define variable decLoc       as integer   no-undo.
    assign
        absValue     = abs(dValue)
        decLoc       = index(string(absValue),".")
        decimalValue = substring(string(absValue),(if decLoc = 0 then length(string(absValue)) + 1 else decLoc))
        iValue       = truncate(absValue,0)
        cValue       = string(iValue).
    do ix = 1 to roundUp(length(string(iValue)) / 3,0) - 1:
        assign 
            substring(cValue,length(string(iValue)) - ((ix * 3) - 1),0) = ",".
    end.
    return (if dValue < 0 then "-" else "") + cValue + decimalValue.
end.