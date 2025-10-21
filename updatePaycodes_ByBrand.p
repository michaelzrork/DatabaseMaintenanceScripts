define variable xDescription as character no-undo.
define variable programName as character no-undo.

assign 
    programName  = "updatePaycodes_LogOnly" // Prints in Audit Log and used for logfile name
    xDescription = "Update paycodes to new payment codes". // Prints in Audit Log when included as input parameter  

/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 3/3/25
   Notes       : 
       
       ****** THIS WAS SO CLOSE, BUT JUST ISN'T GOING TO CUT IT *******
       TOO MANY RECORDS WILL BE SKIPPED AND THERE IS TOO MUCH AMBIGUITY IN FINDING THE CORRECT MATCHING RECORDS WHEN FINDING THE CREDIT CARD PAYCODE FIRST
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num           as integer   no-undo.
define variable inpfile-loc           as character no-undo.
define variable counter               as integer   no-undo.
define variable ixLog                 as integer   no-undo. 
define variable logfileDate           as date      no-undo.
define variable logfileTime           as integer   no-undo.
define variable numReceiptPaymentRecs as integer   no-undo. 
define variable numFeeHistRecs        as integer   no-undo.
define variable numCCHistRecs         as integer   no-undo.
define variable numRefundRecs         as integer   no-undo.
define variable numGLDistRecs         as integer   no-undo.
define variable newPaycode            as character no-undo.
define variable oldPaycode            as character no-undo.
define variable ccHistoryID           as int64     no-undo.
define variable glDistID              as int64     no-undo.
define variable feeHistID             as int64     no-undo.

assign
    inpfile-num           = 1
    logfileDate           = today
    logfileTime           = time
    oldPaycode            = ""
    newPaycode            = ""
    ccHistoryID           = 0
    feeHistID             = 0
    numReceiptPaymentRecs = 0
    numFeeHistRecs        = 0
    numCCHistRecs         = 0
    numRefundRecs         = 0
    numGLDistRecs         = 0.
    
define temp-table ttChangeRecord
    field id               as int64
    field xTable           as character 
    field receiptNum       as integer 
    field receiptPaymentID as int64
    index id               id
    index receiptPaymentID receiptPaymentID
    index xTable           xTable
    index receiptNum       receiptNum.
    
empty temp-table ttChangeRecord.

/*************************************************************************
                                FUNCTIONS
*************************************************************************/
        
/* SET THE PAYCODE OF THE SACREDITCARDHSTORY RECORD BASED ON THE CC BRAND */        
function getPaycode returns character (inpID as int64):
    define variable brandPaycode as character no-undo.
    
    assign 
        brandPaycode = "".
    
    define buffer bufCardTransactionLog for CardTransactionLog.
    define buffer bufPaymentTransaction    for PaymentTransaction.
    do for bufCardTransactionLog transaction:
        
        find first bufCardTransactionLog no-lock where bufCardTransactionLog.ID = inpID no-error no-wait.        
        if available bufCardTransactionLog then 
        do:     
            case bufCardTransactionLog.CreditCardBrand:
                when "American Express" or 
                when "Amex" then 
                    assign 
                        brandPaycode = "03".
                when "Discover" then
                    assign 
                        brandPaycode = "06".
                when "Master Card" or 
                when "MasterCard" then 
                    assign 
                        brandPaycode = "05".
                when "Visa" then 
                    assign 
                        brandPaycode = "04".
                otherwise
                assign
                    brandPaycode = "".
            end.   
        end.
            
        /* IF NO CC HIST RECORD AVAILABLE, SET THE PAYCODE TO THE CURRENT ONE AND WE'LL ASSIGN IT LATER */
        if not available bufCardTransactionLog then
            assign
                brandPaycode = "".
        
        return brandPaycode.
    end.
end.

/* GET SACREDITCARDHISTORY ID */
function getCCHistID returns int64 (inpID as int64, receiptNum as integer, cPaycode as character, paymentAmount as decimal, sibID as int64):
    define variable totalPaid as decimal no-undo.
    define buffer bufCardTransactionLog for CardTransactionLog.
    define buffer bufPaymentTransaction    for PaymentTransaction.
    
    do for bufCardTransactionLog transaction:
        
        for each bufPaymentTransaction no-lock where bufPaymentTransaction.ReceiptNumber = receiptNum and bufPaymentTransaction.Paycode = cPaycode and bufPaymentTransaction.SiblingID = sibID:
            totalPaid = totalPaid + bufSAreceiptPayment.Amount.  
        end.
            
        for each bufCardTransactionLog no-lock where bufCardTransactionLog.ReceiptNumber = receiptNum
            and bufCardTransactionLog.PayCode = cPaycode and bufCardTransactionLog.Amount = totalPaid:
                    
            find first ttChangeRecord where ttChangeRecord.xTable = "CardTransactionLog" and ttChangeRecord.id = bufCardTransactionLog.ID no-error no-wait.
            if not available ttChangeRecord then 
            do:
                create ttChangeRecord.
                assign 
                    ttChangeRecord.xTable     = "CardTransactionLog"
                    ttChangeRecord.id         = bufCardTransactionLog.ID
                    ttChangeRecord.receiptNum = receiptNum.
                return bufCardTransactionLog.ID.
            end.   
            if available ttChangeRecord then 
            do:
                create ttChangeRecord.
                assign 
                    ttChangeRecord.xTable           = "CardTransactionLog"
                    ttChangeRecord.id               = bufCardTransactionLog.ID
                    ttChangeRecord.receiptPaymentID = inpID.
            end. 
                
        end.
        return 0.
    end.
end.

/* FIND THE SAGLDISTRIBUTION ID */
function getGLDistID returns int64 (inpID as int64):
    define buffer bufPaymentTransaction        for PaymentTransaction.
    define buffer bufChargeHistory            for ChargeHistory.
    define buffer bufCharge                   for Charge.
    define buffer bufAccountBalanceLog for AccountBalanceLog.
    define buffer bufLedgerEntry        for LedgerEntry.
    
    do for bufPaymentTransaction transaction:
        find first bufPaymentTransaction no-lock where bufPaymentTransaction.ID = inpid no-error no-wait.
        if available bufPaymentTransaction then find first bufChargeHistory no-lock where bufChargeHistory.ID = bufPaymentTransaction.ParentRecord no-error no-wait.
        if available bufChargeHistory then 
        do: 
            /* FOR RECORDS WITH A SPECIAL LINK TABLE OF SACONTROLACCOUNTHISTORY BECAUSE THESE WILL NOT HAVE AN SAFEEHISTORY.ParentRecord */
            if bufPaymentTransaction.SpecialLinkTable = "AccountBalanceLog" then 
            do:
                find first bufAccountBalanceLog no-lock where bufAccountBalanceLog.ID = bufPaymentTransaction.SpecialLinkID no-error no-wait.
                if available bufAccountBalanceLog then
                    for each bufLedgerEntry no-lock where bufLedgerEntry.DetailLinkID = bufAccountBalanceLog.ParentRecord
                        and bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                        and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                        and bufLedgerEntry.FeeLinkID = bufChargeHistory.ParentRecord
                        and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                        and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                        find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                        if not available ttChangeRecord then 
                        do:
                            create ttChangeRecord.
                            assign 
                                ttChangeRecord.xTable     = "LedgerEntry"
                                ttChangeRecord.ID         = bufLedgerEntry.ID
                                ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                        end.
                        return bufLedgerEntry.ID.
                    end.
                if not available bufLedgerEntry then 
                    for each bufLedgerEntry no-lock where bufLedgerEntry.DetailLinkID = bufAccountBalanceLog.ParentRecord
                        and bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                        and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                        and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                        and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                        find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                        if not available ttChangeRecord then 
                        do:
                            create ttChangeRecord.
                            assign 
                                ttChangeRecord.xTable     = "LedgerEntry"
                                ttChangeRecord.ID         = bufLedgerEntry.ID
                                ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                            return bufLedgerEntry.ID.
                        end.
                    end.
                if not available bufLedgerEntry then 
                    for each bufLedgerEntry no-lock where bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                        and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                        and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                        and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                        find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                        if not available ttChangeRecord then 
                        do:
                            create ttChangeRecord.
                            assign 
                                ttChangeRecord.xTable     = "LedgerEntry"
                                ttChangeRecord.ID         = bufLedgerEntry.ID
                                ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                            return bufLedgerEntry.ID.
                        end.
                    end.
            end.
            
            /* FOR RECORDS WHERE THE SAFEEHISTORY.ParentRecord WILL POINT TO AN SAFEE RECORD */
            else 
            do:
                if bufChargeHistory.ParentRecord <> 0 then find first bufCharge no-lock where bufCharge.ID = bufChargeHistory.ParentRecord no-error no-wait.
                if available bufCharge then 
                do:
                    for each bufLedgerEntry no-lock where bufLedgerEntry.DetailLinkID = bufCharge.ParentRecord
                        and bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                        and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                        and bufLedgerEntry.FeeLinkID = bufCharge.ID
                        and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                        and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                        find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                        if not available ttChangeRecord then 
                        do:
                            create ttChangeRecord.
                            assign 
                                ttChangeRecord.xTable     = "LedgerEntry"
                                ttChangeRecord.ID         = bufLedgerEntry.ID
                                ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                            return bufLedgerEntry.ID.
                        end.
                    end.
                    if not available bufLedgerEntry then                     
                        for each bufLedgerEntry no-lock where bufLedgerEntry.DetailLinkID = bufCharge.ParentRecord
                            and bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                            and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                            and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                            and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                            find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                            if not available ttChangeRecord then 
                            do:
                                create ttChangeRecord.
                                assign 
                                    ttChangeRecord.xTable     = "LedgerEntry"
                                    ttChangeRecord.ID         = bufLedgerEntry.ID
                                    ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                                return bufLedgerEntry.ID.
                            end.
                        end.
                    if not available bufLedgerEntry then                     
                        for each bufLedgerEntry no-lock where bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                            and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                            and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                            and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                            find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                            if not available ttChangeRecord then 
                            do:
                                create ttChangeRecord.
                                assign 
                                    ttChangeRecord.xTable     = "LedgerEntry"
                                    ttChangeRecord.ID         = bufLedgerEntry.ID
                                    ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                                return bufLedgerEntry.ID.
                            end.
                        end.
                end.
                else 
                    for each bufLedgerEntry no-lock where bufLedgerEntry.ReceiptNumber = bufPaymentTransaction.ReceiptNumber
                        and bufLedgerEntry.PayCode = bufPaymentTransaction.Paycode
                        and bufLedgerEntry.Amount = bufPaymentTransaction.Amount
                        and bufLedgerEntry.SiblingID = bufPaymentTransaction.SiblingID:
                        find first ttChangeRecord no-lock where ttChangeRecord.xTable = "LedgerEntry" and ttChangeRecord.ID = bufLedgerEntry.ID no-error no-wait.
                        if not available ttChangeRecord then 
                        do:
                            create ttChangeRecord.
                            assign 
                                ttChangeRecord.xTable     = "LedgerEntry"
                                ttChangeRecord.ID         = bufLedgerEntry.ID
                                ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber.
                            return bufLedgerEntry.ID.
                        end.
                    end. 
            end.
        end.
        
        /* IF AN SAGLDISTRIBUTION RECORD IS UNABLE TO BE FOUND, RETURN 0 */
        return 0.
        
    end.
end.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
run put-stream (
    "Receipt Number," +
    "Date," +
    "PaymentTransaction.ID," +
    "Old ReceiptPayment Paycode," +
    "ChargeHistory.ID," +
    "Old FeeHist Paycode," +
    "CardTransactionLog.ID," +
    "Old CCHistory Paycode," +
    "CC Brand," +
    "LedgerEntry.ID," +
    "Old GLDist Paycode," +
    "Reversal.ID," +
    "Old Refund Paycode," +
    "New Paycode,").

/* RECEIPT PAYMENT LOOP - CREATE TEMP TABLE OF ALL RECORDS BEING CHANGED WITH THEIR OLD AND NEW PAYCODES */ 
for each PaymentTransaction no-lock where PaymentTransaction.Paycode ge "03" and PaymentTransaction.PayCode le "10" and PaymentTransaction.PostingDate le 2/27/2024:
    assign
        ccHistoryID = 0
        glDistID    = 0
        feeHistID   = PaymentTransaction.ParentRecord
        oldPaycode  = PaymentTransaction.Paycode
        newPaycode  = "".
    
    case PaymentTransaction.PayCode:
        
        when "03" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then 
            do:
                assign
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "04".
                run updatePaycode(PaymentTransaction.ID).
            end.
            
        when "04" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then
            do:
                assign
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "03".
                run updatePaycode(PaymentTransaction.ID).
            end.
            
        when "05" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then
            do:
                assign 
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "06".
                run updatePaycode(PaymentTransaction.ID).
            end.
            
        when "07" then 
            if PaymentTransaction.PostingDate le 1/18/2024 then 
            do:
                assign 
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "JournalPayment".
                run updatePaycode(PaymentTransaction.ID).
            end.
             
        when "08" then 
            if PaymentTransaction.PostingDate le 1/17/2024 then 
            do:
                assign 
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "80".
                run updatePaycode(PaymentTransaction.ID).
            end.
             
        when "09" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then 
            do:
                assign 
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "21".
                run updatePaycode(PaymentTransaction.ID).
            end.
            
        when "10" then 
            if PaymentTransaction.PostingDate le 1/18/2024 then 
            do:
                assign 
                    glDistID    = getGLDistID(PaymentTransaction.ID)
                    ccHistoryID = if PaymentTransaction.SpecialLinkTable = "CardTransactionLog" then PaymentTransaction.SpecialLinkID else (if index(PaymentTransaction.miscinformation,"CCHistoryLinkID") <> 0 then int64(nameVal("CCHistoryLinkID",PaymentTransaction.miscinformation,"=",chr(30))) else 0)
                    ccHistoryID = if ccHistoryID <> 0 then ccHistoryID else getCCHistID(PaymentTransaction.ID,PaymentTransaction.ReceiptNumber,PaymentTransaction.Paycode,PaymentTransaction.Amount,PaymentTransaction.SiblingID)
                    newPaycode  = if ccHistoryID = 0 then "" else getPaycode(ccHistoryID).
                if newPaycode = "" then newPaycode = "11".
                run updatePaycode(PaymentTransaction.ID).
            end.
            
    end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog(xDescription,

    "Check Document Center for " + programName + "Log for a log of Records Changed",

    "Number of Records Changed: " + string(numReceiptPaymentRecs + numFeeHistRecs + numCCHistRecs + numRefundRecs + numGLDistRecs),

    "PaymentTransaction: " + 
    string(numReceiptPaymentRecs) + 
    "; ChargeHistory: " + 
    string(numFeeHistRecs) + 
    "; LedgerEntry: " + 
    string(numGLDistRecs) + 
    "; CardTransactionLog: " + 
    string(numCCHistRecs) + 
    "; Reversal: " + 
    string(numRefundRecs)
    ).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/                                                                     

/* UPDATE PAYCODE */
procedure updatePaycode:
    define input parameter inpID as int64 no-undo.
    define buffer bufPaymentTransaction    for PaymentTransaction.
    define buffer bufCardTransactionLog for CardTransactionLog.
    define buffer bufChargeHistory        for ChargeHistory.
    define buffer bufReversal            for Reversal.
    define buffer bufLedgerEntry    for LedgerEntry.
    define variable oldReceiptPayment as character no-undo.
    define variable oldCCHist         as character no-undo.
    define variable oldFeeHist        as character no-undo.
    define variable oldRefund         as character no-undo.
    define variable oldGLDist         as character no-undo.
    do for bufPaymentTransaction transaction:
        
        assign 
            oldReceiptPayment = ""
            oldCCHist         = ""
            oldFeeHist        = ""
            oldRefund         = ""
            oldGLDist         = "".
        
        find first bufPaymentTransaction exclusive-lock where bufPaymentTransaction.ID = inpID no-error no-wait.
        if available bufPaymentTransaction then 
        do:
            assign 
                numReceiptPaymentRecs = numReceiptPaymentRecs + 1
                oldReceiptPayment     = bufPaymentTransaction.Paycode.
                //bufPaymentTransaction.Paycode = newPaycode.

            if ccHistoryID <> 0 then find first bufCardTransactionLog exclusive-lock where bufCardTransactionLog.ID = ccHistoryID no-error no-wait.
            if available bufCardTransactionLog then
                assign
                    numCCHistRecs = numCCHistRecs + 1
                    oldCCHist     = bufCardTransactionLog.PayCode.
                    //bufCardTransactionLog.PayCode = if bufCardTransactionLog.Paycode <> "System-Payment" then newPaycode else bufCardTransactionLog.Paycode.
            
            if feeHistID <> 0 then find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = feeHistID no-error no-wait.
            if available bufChargeHistory then 
                assign
                    numFeeHistRecs = numFeeHistRecs + 1
                    oldFeeHist     = bufChargeHistory.Paycode.
                    //bufChargeHistory.Paycode = if bufChargeHistory.Paycode <> "System-Payment" then newPaycode else bufChargeHistory.Paycode.
            
            if glDistID <> 0 then find first bufLedgerEntry exclusive-lock where bufLedgerEntry.ID = glDistID no-error no-wait.
            if available bufLedgerEntry then
                assign
                    numGLDistRecs = numGLDistRecs + 1
                    oldGLDist     = bufLedgerEntry.Paycode.
                    //bufLedgerEntry.Paycode = if bufLedgerEntry.Paycode <> "System-Payment" then newPaycode else bufLedgerEntry.PayCode.
            
            find first bufReversal exclusive-lock where bufReversal.PaymentID = bufPaymentTransaction.ID no-error no-wait.
            if available bufReversal then 
                assign
                    numRefundRecs = numRefundRecs + 1
                    oldRefund     = bufReversal.PayCode. 
                    //bufReversal.PayCode = if bufReversal.PayCode <> "System-Payment" then newPaycode else bufReversal.Paycode.
                    
            run put-stream("~"" +
                /*Receipt Number*/
                getString(string(bufPaymentTransaction.ReceiptNumber))
                + "~",~"" +
                /*Date*/
                getString(string(bufPaymentTransaction.PostingDate))
                + "~",~"" +
                /*PaymentTransaction.ID*/
                getString(string(bufPaymentTransaction.ID))
                + "~",~"" +
                /*Old ReceiptPayment Paycode*/
                oldReceiptPayment
                + "~",~"" +
                /*ChargeHistory.ID*/
                (if available bufChargeHistory then getString(string(bufChargeHistory.ID)) else "")
                + "~",~"" +
                /*Old FeeHist Paycode*/
                oldFeeHist 
                + "~",~"" +
                /*CardTransactionLog.ID*/
                (if available bufCardTransactionLog then getString(string(bufCardTransactionLog.ID))
                else (if can-find(ttChangeRecord where ttChangeRecord.xTable = "CardTransactionLog" and ttChangeRecord.receiptNum = bufPaymentTransaction.ReceiptNumber) 
                then "Check Receipt: " + string(bufPaymentTransaction.ReceiptNumber) 
                else ""))
                + "~",~"" +
                /*Old CCHistory Paycode*/
                oldCCHist      
                + "~",~"" +
                /*CC Brand*/
                (if available bufCardTransactionLog then getString(bufCardTransactionLog.CreditCardBrand) else "")
                + "~",~"" +
                /*LedgerEntry.ID*/
                (if available bufLedgerEntry then getString(string(bufLedgerEntry.ID)) else "")
                + "~",~"" +
                /*Old GLDist Paycode*/
                oldGLDist
                + "~",~"" +
                /*Reversal.ID*/
                (if available bufReversal then getString(string(bufReversal.ID)) else "")
                + "~",~"" +
                /*Old Refund Paycode*/
                oldRefund
                + "~",~"" +
                /*New Paycode*/
                newPaycode
                + "~",").
        end.
    end.
end.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
    counter = counter + 1.
    if counter gt 50000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    define input parameter logDetail1 as character no-undo.
    define input parameter logDetail2 as character no-undo.
    define input parameter logDetail3 as character no-undo.
    define input parameter logDetail4 as character no-undo.
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = programName + ".r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail1
            bufActivityLog.Detail2       = logDetail2
            bufActivityLog.Detail3       = logDetail3
            bufActivityLog.Detail4       = logDetail4.
    end.
end procedure.
