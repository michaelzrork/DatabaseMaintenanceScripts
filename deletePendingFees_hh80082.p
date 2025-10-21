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
define variable NumRelatedFeeHist  as integer   no-undo init 0.
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
    
define buffer bufFeeHist for ChargeHistory.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

run ActivityLog({&ProgramDescription},"Program in Progress","Number of ChargeHistory Records Deleted So Far: " + string(FeeHistDeleted) + "; Skipped So Far: " + string(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + string(FeesDeleted) + "; Skipped So Far: " + string(FeeSkipped),"Number of Related ChargeHistory Records So Far: " + string(NumRelatedFeeHist) + "; Number of Missing Charge Records So Far: " + string(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + string(NumMissingDetail)).

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

/* FIND EVERY SAFEEHISTORY RECORD THAT IS CURRENTLY IN PENDING STATUS OR THAT HAS BEEN IN PENDING STATUS THAT WAS NOT A PRE-PAID BILL */
feehist-loop:
for each ChargeHistory no-lock where ChargeHistory.paymenthousehold = 80082 and (ChargeHistory.recordstatus = "Pending" or (index(SAFeeHIstory.notes,"Pending Fees") > 0 and index(ChargeHistory.MiscInformation,"OriginalReceipt") > 0)) and ChargeHistory.RecordStatus <> "Billed":
    
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
    
    /* ONLY MOVE ON IF THE SAFEE DOES NOT HAVE THE DUE OPTION SET */
    for first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord:
        if Charge.DueOption <> "" and Charge.DueOption <> "Not Applicable" then next feehist-loop.
        
        /* SET SAFEE VARIABLES */
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
            
            /* SET SADETAIL VARIABLES */
            assign
                DetailID           = TransactionDetail.ID
                DetailReceiptList  = TransactionDetail.ReceiptList
                hhNum              = TransactionDetail.EntityNumber
                DetailDescription  = TransactionDetail.Description
                DetailRecordStatus = TransactionDetail.RecordStatus
                cModule            = TransactionDetail.Module
                DeleteFeeHist      = true
                NoteValue          = "ChargeHistory Deleted; Charge and TransactionDetail Records Found".
                
            /* ADD SADETAIL RECORD TO TEMP TABLE TO BE RECALCULATED LATER */
            find first ttDetail no-lock where ttDetail.ID = TransactionDetail.ID no-error.
            if not available ttDetail then 
            do:
                create ttDetail.
                assign 
                    ttDetail.ID = TransactionDetail.ID.
            end.
        end.
        
        if not available TransactionDetail then 
        do:
            /* SET MISSING SADETAIL VARIABLES */
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
                
                /* ADD SADETAIL RECORD TO TEMP TABLE TO BE RECALCULATED LATER */
                find first ttDetail no-lock where ttDetail.ID = Charge.ParentRecord no-error.
                if not available ttDetail then 
                do:
                    create ttDetail.
                    assign 
                        ttDetail.ID = Charge.ParentRecord.
                end.
            end.
            
            /* IF SADETAIL NOT AVAILABLE AND NOT LOCKED, DELETE THE SAFEEHISTORY RECORD */
            else
            do:
                assign 
                    NumMissingDetail = NumMissingDetail + 1
                    DeleteFeeHist    = true
                    NoteValue        = "ChargeHistory Deleted; Charge Found, TransactionDetail Record Missing".
            end.
        end.
        
        /* FIND ANY OTHER FEE HISTORY RECORD LINKED TO THE SAME PARENT ID THAT MIGHT BE LEGITIMATE AND SKIP ADDING THE SAFEE TO THE LIST TO DELETE IF SO */
        for each bufFeeHist no-lock where bufFeeHist.ID <> ChargeHistory.ID and bufFeeHist.ParentRecord = ChargeHistory.ParentRecord and bufFeeHist.RecordStatus <> "Pending" and index(bufFeeHist.MiscInformation,"OriginalReceipt") = 0  and index(bufFeeHist.notes,"Pending Fees") = 0:
            assign
                NumRelatedFeeHist = NumRelatedFeeHist + 1
                DeleteFee         = false.       
            /* ADD FEE HISTORY RECORD TO LOG FOR REVIEW */
            run deleteSAFeeHistory(bufFeeHist.ID,"Additonal ChargeHistory Records Found; Charge Record Skiped",no).
        end.
        
        /* IF NO ADDITIONAL SAFEEHISTORY RECORDS WERE FOUND THAT ARE/WERE NOT PENDING, DELETE THE SAFEE RECORD AS WELL */
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
        end.
        
        /* IF ADDITIONAL SAFEEHISTORY RECORDS WERE FOUND, COUNT THE SAFEE AS SKIPPED */
        /* THIS IS ALSO WHERE WE MIGHT TRY TO CHECK THE BALANCE AND DECIDE WHAT TO DO IF THE BALANCE DROPS BELOW ZERO */
        else 
        do:
            assign 
                FeeSkipped = FeeSkipped + 1.
        /*            // ADD DELETE SAFEEHISTORY WITH UNDO HERE, THEN RUN THE FEE CALC                                                          */
        /*            /* CHECK THE BALANCE */                                                                                                   */
        /*            TotalDue   = 0.                                                                                                           */
        /*            find first TransactionDetail exclusive-lock where TransactionDetail.ID = ttDetail.ID no-error.                                              */
        /*            run Business/SADetailFeeCalc.p ("TransactionDetail", "TotalDue", ?, "", "", TransactionDetail.ID, output TotalDue).                         */
        /*            // UNDO THE DELETED FEE HERE                                                                                              */
        /*            if TotalDue < 0 then                                                                                                      */
        /*            do:                                                                                                                       */
        /*                run deleteSAFeeHistory(bufFeeHist.ID,"ChargeHistory Record Not Deleted; Would cause balance due to drop below 0",no).*/
        /*                next feehist-loop.                                                                                                    */
        /*            end.                                                                                                                      */
        end.
    
    end.
   
    /* IF THE PARENT ID OF THE SAFEEHISTORY RECORD DOESN'T FIND AN SAFEE RECORD, CHECK TO SEE IF IT'S AN SADETAIL ID */
    if not available Charge then 
    do:
        /* ASSIGN MISSING SAFEE VARIABLES */
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
            
        /* IF SAFEE LOCKED, SKIP DELETING THE SAFEEHISTORY RECORD */
        if locked Charge then 
        do:
            assign
                FeeID         = ChargeHistory.ParentRecord
                DeleteFeeHist = false
                NoteValue     = "ChargeHistory Skipped; Charge Record Locked".
        end.
        
        /* IF NOT AVAILABLE SAFEE AND NOT LOCKED, CHECK SAFEEHISTORY PARENT ID AGAINST SADETAIL */
        else 
        do:
            find first TransactionDetail no-lock where TransactionDetail.ID = ChargeHistory.ParentRecord no-error.
        
            /* IF SADETAIL FOUND LOG FEE HISTORY TO REVIEW, BUT DON'T DELETE IT */
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
                /* IF SADETAIL RECORD FOUND, BUT LOCKED, LOG IT TO REVIEW LATER AND DON'T DELETE IT */
                if locked TransactionDetail then 
                do:
                    assign
                        NumMissingFee = NumMissingFee + 1
                        DetailID      = ChargeHistory.ParentRecord
                        DeleteFeeHist = false
                        NoteValue     = "ChargeHistory Skipped; No Charge Record Found, TransactionDetail Record Locked".
                end.
                
                /* IF SADETAIL RECORD NOT FOUND, DELETE SAFEEHISTORY */
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

    run deleteSAFeeHistory(ChargeHistory.ID,NoteValue,DeleteFeeHist).
     
    run UpdateActivityLog({&ProgramDescription},"Program in Progress","Number of ChargeHistory Records Deleted So Far: " + string(FeeHistDeleted) + "; Skipped So Far: " + string(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + string(FeesDeleted) + "; Skipped So Far: " + string(FeeSkipped),"Number of Related ChargeHistory Records So Far: " + string(NumRelatedFeeHist) + "; Number of Missing Charge Records So Far: " + string(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + string(NumMissingDetail)).  
       
end.

/* ONCE DONE WITH THE SAFEEHISTORY RECORDS, DELETE THE CORRESPONDING SAFEE RECORDS */
for each ttCharge no-lock:
    find first Charge no-lock where Charge.ID = ttCharge.ID no-error.
    if available Charge then run deleteSAFee(Charge.ID).
    run UpdateActivityLog({&ProgramDescription},"Program in Progress","Number of ChargeHistory Records Deleted So Far: " + string(FeeHistDeleted) + "; Skipped So Far: " + string(FeeHistSkipped),"Number of Charge Records Deleted So Far: " + string(FeesDeleted) + "; Skipped So Far: " + string(FeeSkipped),"Number of Related ChargeHistory Records So Far: " + string(NumRelatedFeeHist) + "; Number of Missing Charge Records So Far: " + string(NumMissingFee) + ", Missing TransactionDetail Records So Far: " + string(NumMissingDetail)).
end.

/* RECALC SADETAIL FULLY PAID STATUS */
if not LogOnly then 
    for each ttDetail no-lock:
        assign 
            TotalDue = 0.
        find first TransactionDetail exclusive-lock where TransactionDetail.ID = ttDetail.ID no-error.
        run Business/SADetailFeeCalc.p ("TransactionDetail", "TotalDue", ?, "", "", TransactionDetail.ID, output TotalDue).  
        assign 
            TransactionDetail.FullyPaid = if totalDue gt 0 then false else true.
    end.
  
/* CREATE LOG FILE */
do ixLog = 1 to InpFile-Num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(LogfileDate),"/","-") + "_" + string(LogfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(LogfileDate),"/","-") + "_" + string(LogfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run UpdateActivityLog({&ProgramDescription},"Program Complete; Check Document Center for a log of Records Changed","Number of ChargeHistory Records Deleted: " + string(FeeHistDeleted) + "; Skipped: " + string(FeeHistSkipped),"Number of Charge Records Deleted: " + string(FeesDeleted) + "; Skipped: " + string(FeeSkipped),"Number of related ChargeHistory records: " + string(NumRelatedFeeHist) + "; Number of Missing Charge Records: " + string(NumMissingFee) + ", Missing TransactionDetail Records: " + string(NumMissingDetail)).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/
    
/* DELETE FEE HISTORY */
procedure deleteSAFeeHistory:
    define input parameter inpID as int64 no-undo.
    define input parameter LogNotes as character no-undo.
    define input parameter DeleteFeeHistory as logical no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        if LogOnly then 
        do:
            find first bufChargeHistory no-lock where bufChargeHistory.ID = inpID no-error.
            if available bufChargeHistory then 
            do:
                if DeleteFeeHistory then 
                    assign 
                        FeeHistDeleted = FeeHistDeleted + 1.
                else assign FeeHistSkipped = FeeHistSkipped + 1.
            
                run put-stream ("~"" +
                    /*ChargeHistory.ID*/
                    getString(string(bufChargeHistory.ID))
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
                    getString(string(bufChargeHistory.ReceiptNumber))
                    + "~",~"" +
                    /*ChargeHistory.LogDate*/
                    getString(string(bufChargeHistory.LogDate))
                    + "~",~"" +
                    /*ChargeHistory.RecordStatus*/
                    getString(bufChargeHistory.RecordStatus)
                    + "~",~"" +
                    /*ChargeHistory.FeeAmount*/
                    getString(string(bufChargeHistory.FeeAmount))
                    + "~",~"" +
                    /*ChargeHistory.FeePaid*/
                    getString(string(bufChargeHistory.FeePaid))
                    + "~",~"" +
                    /*ChargeHistory.DiscountAmount*/
                    getString(string(bufChargeHistory.DiscountAmount))
                    + "~",~"" +
                    /*ChargeHistory.BillDate*/
                    getString(string(bufChargeHistory.BillDate))
                    + "~",~"" +
                    /*ChargeHistory.Notes*/
                    getString(parseList(bufChargeHistory.Notes))
                    + "~",~"" +
                    /*ChargeHistory.MiscInformation*/
                    getString(parseList(bufChargeHistory.MiscInformation))
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
            end.
        end.
        else 
        do:
            find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error.
            if available bufChargeHistory then 
            do:
                if DeleteFeeHistory then 
                    assign 
                        FeeHistDeleted = FeeHistDeleted + 1.
                else assign FeeHistSkipped = FeeHistSkipped + 1.
            
                run put-stream ("~"" +
                    /*ChargeHistory.ID*/
                    getString(string(bufChargeHistory.ID))
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
                    getString(string(bufChargeHistory.ReceiptNumber))
                    + "~",~"" +
                    /*ChargeHistory.LogDate*/
                    getString(string(bufChargeHistory.LogDate))
                    + "~",~"" +
                    /*ChargeHistory.RecordStatus*/
                    getString(bufChargeHistory.RecordStatus)
                    + "~",~"" +
                    /*ChargeHistory.FeeAmount*/
                    getString(string(bufChargeHistory.FeeAmount))
                    + "~",~"" +
                    /*ChargeHistory.FeePaid*/
                    getString(string(bufChargeHistory.FeePaid))
                    + "~",~"" +
                    /*ChargeHistory.DiscountAmount*/
                    getString(string(bufChargeHistory.DiscountAmount))
                    + "~",~"" +
                    /*ChargeHistory.BillDate*/
                    getString(string(bufChargeHistory.BillDate))
                    + "~",~"" +
                    /*ChargeHistory.Notes*/
                    getString(parseList(bufChargeHistory.Notes))
                    + "~",~"" +
                    /*ChargeHistory.MiscInformation*/
                    getString(parseList(bufChargeHistory.MiscInformation))
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
            
                if DeleteFeeHistory then delete bufChargeHistory.
            end.
        end.
    end.
end procedure.     

procedure deleteSAFee:
    define input parameter inpID as int64 no-undo.
    define buffer bufCharge for Charge.
    do for bufCharge transaction:
        if LogOnly then 
        do:
            find first bufCharge no-lock where bufCharge.ID = inpID no-error.
            if available bufCharge then 
            do:
                assign 
                    FeesDeleted = FeesDeleted + 1.
            end.
        end.
        else 
        do:
            find first bufCharge exclusive-lock where bufCharge.ID = inpID no-error.
            if available bufCharge then 
            do:
                assign 
                    FeesDeleted = FeesDeleted + 1.
                delete bufCharge.
            end.
        end.
    end.
end procedure.
             
/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
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