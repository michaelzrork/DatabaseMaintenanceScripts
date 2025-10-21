define variable xDescription as character no-undo.
define variable programName as character no-undo.

assign 
    programName  = "updatePaycodes" // Prints in Audit Log and used for logfile name
    xDescription = "Update paycodes to new payment codes". // Prints in Audit Log when included as input parameter  

/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 
   Notes       : 
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
define variable numMiscIncRecs        as integer   no-undo.

assign
    inpfile-num           = 1
    logfileDate           = today
    logfileTime           = time
    
    numReceiptPaymentRecs = 0
    numFeeHistRecs        = 0
    numCCHistRecs         = 0
    numRefundRecs         = 0
    numGLDistRecs         = 0
    numMiscIncRecs        = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
run put-stream (
    "Table," +
    "ID," +
    "Receipt Number," +
    "Old Paycode," +
    "New Paycode,"
    ).
    
/* LOOP THROUGH EACH TABLE, CHANGING THE PAY CODES AS IT FINDS THEM */

/* PaymentTransaction */
for each PaymentTransaction no-lock where PaymentTransaction.Paycode ge "03" and PaymentTransaction.PayCode le "10" and PaymentTransaction.PostingDate le 2/27/2024:
    case PaymentTransaction.PayCode:
        when "03" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then 
                run assignSAReceiptPayment(PaymentTransaction.ID,"04").
            
        when "04" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then
                run assignSAReceiptPayment(PaymentTransaction.ID,"03").
            
        when "05" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then
                run assignSAReceiptPayment(PaymentTransaction.ID,"06").
            
        when "07" then 
            if PaymentTransaction.PostingDate le 1/18/2024 then 
                run assignSAReceiptPayment(PaymentTransaction.ID,"JournalPayment").
             
        when "08" then 
            if PaymentTransaction.PostingDate le 1/18/2024 then 
                run assignSAReceiptPayment(PaymentTransaction.ID,"80").
             
        when "09" then 
            if PaymentTransaction.PostingDate le 2/27/2024 then 
                run assignSAReceiptPayment(PaymentTransaction.ID,"21").
            
        when "10" then 
            if PaymentTransaction.PostingDate le 1/18/2024 then 
                run assignSAReceiptPayment(PaymentTransaction.ID,"11").      
    end.
end.

/* ChargeHistory */
for each ChargeHistory no-lock where ChargeHistory.Paycode ge "03" and ChargeHistory.PayCode le "10" and ChargeHistory.LogDate le 2/27/2024:
    case ChargeHistory.PayCode:
        when "03" then 
            if ChargeHistory.LogDate le 2/27/2024 then 
                run assignSAFeeHistory(ChargeHistory.ID,"04").
            
        when "04" then 
            if ChargeHistory.LogDate le 2/27/2024 then
                run assignSAFeeHistory(ChargeHistory.ID,"03").
            
        when "05" then 
            if ChargeHistory.LogDate le 2/27/2024 then
                run assignSAFeeHistory(ChargeHistory.ID,"06").
            
        when "07" then 
            if ChargeHistory.LogDate le 1/18/2024 then 
                run assignSAFeeHistory(ChargeHistory.ID,"JournalPayment").
             
        when "08" then 
            if ChargeHistory.LogDate le 1/18/2024 then 
                run assignSAFeeHistory(ChargeHistory.ID,"80").
             
        when "09" then 
            if ChargeHistory.LogDate le 2/27/2024 then 
                run assignSAFeeHistory(ChargeHistory.ID,"21").
            
        when "10" then 
            if ChargeHistory.LogDate le 1/18/2024 then 
                run assignSAFeeHistory(ChargeHistory.ID,"11").      
    end.
end.

/* LedgerEntry */
for each LedgerEntry no-lock where LedgerEntry.Paycode ge "03" and LedgerEntry.PayCode le "10" and LedgerEntry.PostingDate le 2/27/2024:
    case LedgerEntry.PayCode:
        when "03" then 
            if LedgerEntry.PostingDate le 2/27/2024 then 
                run assignSAGLDistribution(LedgerEntry.ID,"04").
            
        when "04" then 
            if LedgerEntry.PostingDate le 2/27/2024 then
                run assignSAGLDistribution(LedgerEntry.ID,"03").
            
        when "05" then 
            if LedgerEntry.PostingDate le 2/27/2024 then
                run assignSAGLDistribution(LedgerEntry.ID,"06").
            
        when "07" then 
            if LedgerEntry.PostingDate le 1/18/2024 then 
                run assignSAGLDistribution(LedgerEntry.ID,"JournalPayment").
             
        when "08" then 
            if LedgerEntry.PostingDate le 1/18/2024 then 
                run assignSAGLDistribution(LedgerEntry.ID,"80").
             
        when "09" then 
            if LedgerEntry.PostingDate le 2/27/2024 then 
                run assignSAGLDistribution(LedgerEntry.ID,"21").
            
        when "10" then 
            if LedgerEntry.PostingDate le 1/18/2024 then 
                run assignSAGLDistribution(LedgerEntry.ID,"11").      
    end.
end.

/* CardTransactionLog */
for each CardTransactionLog no-lock where CardTransactionLog.Paycode ge "03" and CardTransactionLog.PayCode le "10" and CardTransactionLog.ProcessDate le 2/27/2024:
    case CardTransactionLog.PayCode:
        when "03" then 
            if CardTransactionLog.ProcessDate le 2/27/2024 then 
                run assignSACreditCardHistory(CardTransactionLog.ID,"04").
            
        when "04" then 
            if CardTransactionLog.ProcessDate le 2/27/2024 then
                run assignSACreditCardHistory(CardTransactionLog.ID,"03").
            
        when "05" then 
            if CardTransactionLog.ProcessDate le 2/27/2024 then
                run assignSACreditCardHistory(CardTransactionLog.ID,"06").
            
        when "07" then 
            if CardTransactionLog.ProcessDate le 1/18/2024 then 
                run assignSACreditCardHistory(CardTransactionLog.ID,"JournalPayment").
             
        when "08" then 
            if CardTransactionLog.ProcessDate le 1/18/2024 then 
                run assignSACreditCardHistory(CardTransactionLog.ID,"80").
             
        when "09" then 
            if CardTransactionLog.ProcessDate le 2/27/2024 then 
                run assignSACreditCardHistory(CardTransactionLog.ID,"21").
            
        when "10" then 
            if CardTransactionLog.ProcessDate le 1/18/2024 then 
                run assignSACreditCardHistory(CardTransactionLog.ID,"11").      
    end.
end.

/* Reversal */
for each Reversal no-lock where Reversal.Paycode ge "03" and Reversal.PayCode le "10" and Reversal.CancelDate le 2/27/2024:
    case Reversal.PayCode:
        when "03" then 
            if Reversal.CancelDate le 2/27/2024 then 
                run assignSARefund(Reversal.ID,"04").
            
        when "04" then 
            if Reversal.CancelDate le 2/27/2024 then
                run assignSARefund(Reversal.ID,"03").
            
        when "05" then 
            if Reversal.CancelDate le 2/27/2024 then
                run assignSARefund(Reversal.ID,"06").
            
        when "07" then 
            if Reversal.CancelDate le 1/18/2024 then 
                run assignSARefund(Reversal.ID,"JournalPayment").
             
        when "08" then 
            if Reversal.CancelDate le 1/18/2024 then 
                run assignSARefund(Reversal.ID,"80").
             
        when "09" then 
            if Reversal.CancelDate le 2/27/2024 then 
                run assignSARefund(Reversal.ID,"21").
            
        when "10" then 
            if Reversal.CancelDate le 1/18/2024 then 
                run assignSARefund(Reversal.ID,"11").      
    end.
end.

/* OtherRevenue */
for each OtherRevenue no-lock where OtherRevenue.Paycode ge "03" and OtherRevenue.PayCode le "10" and OtherRevenue.PostingDate le 2/27/2024:
    case OtherRevenue.PayCode:
        when "03" then 
            if OtherRevenue.PostingDate le 2/27/2024 then 
                run assignSAMiscIncome(OtherRevenue.ID,"04").
            
        when "04" then 
            if OtherRevenue.PostingDate le 2/27/2024 then
                run assignSAMiscIncome(OtherRevenue.ID,"03").
            
        when "05" then 
            if OtherRevenue.PostingDate le 2/27/2024 then
                run assignSAMiscIncome(OtherRevenue.ID,"06").
            
        when "07" then 
            if OtherRevenue.PostingDate le 1/18/2024 then 
                run assignSAMiscIncome(OtherRevenue.ID,"JournalPayment").
             
        when "08" then 
            if OtherRevenue.PostingDate le 1/18/2024 then 
                run assignSAMiscIncome(OtherRevenue.ID,"80").
             
        when "09" then 
            if OtherRevenue.PostingDate le 2/27/2024 then 
                run assignSAMiscIncome(OtherRevenue.ID,"21").
            
        when "10" then 
            if OtherRevenue.PostingDate le 1/18/2024 then 
                run assignSAMiscIncome(OtherRevenue.ID,"11").      
    end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

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
    string(numRefundRecs) +
    "; OtherRevenue: " +
    string(numMiscIncRecs)
    ).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure assignSAFeeHistory:
    def input parameter inpid as int64 no-undo.
    def input parameter newPaycode as char no-undo.
    def buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find bufChargeHistory exclusive-lock where bufChargeHistory.id = inpid no-error no-wait.
        if available bufChargeHistory then 
        do:
            run put-stream(
                /*Table*/
                "ChargeHistory" + "," +
                /*ID*/
                getString(string(bufChargeHistory.ID)) + "," +
                /*Receipt Number*/
                getString(string(bufChargeHistory.ReceiptNumber)) + "," +
                /*Old Paycode*/
                getString(bufChargeHistory.PayCode) + "," +
                /*New Paycode*/
                newPaycode + ","
                ).
            assign 
                bufChargeHistory.PayCode = newPaycode
                numFeeHistRecs = numFeeHistRecs + 1.
            release bufChargeHistory.
        end.
    end.
end procedure.

procedure assignSAReceiptPayment:
    def input parameter inpid as int64 no-undo.
    def input parameter newPaycode as char no-undo.
    def buffer bufPaymentTransaction for PaymentTransaction.
    do for bufPaymentTransaction transaction:
        find bufPaymentTransaction exclusive-lock where bufPaymentTransaction.id = inpid no-error no-wait.
        if available bufPaymentTransaction then 
        do:
            run put-stream(
                /*Table*/
                "PaymentTransaction" + "," +
                /*ID*/
                getString(string(bufPaymentTransaction.ID)) + "," +
                /*Receipt Number*/
                getString(string(bufPaymentTransaction.ReceiptNumber)) + "," +
                /*Old Paycode*/
                getString(bufPaymentTransaction.PayCode) + "," +
                /*New Paycode*/
                newPaycode + ","
                ).
            assign
                bufPaymentTransaction.PayCode = newPaycode
                numReceiptPaymentRecs = numReceiptPaymentRecs + 1.
            release bufPaymentTransaction.
        end.
    end.
end procedure.

procedure assignSAMiscIncome:
    def input parameter inpid as int64 no-undo.
    def input parameter newPaycode as char no-undo.
    def buffer bufOtherRevenue for OtherRevenue.
    do for bufOtherRevenue transaction:
        find bufOtherRevenue exclusive-lock where bufOtherRevenue.id = inpid no-error no-wait.
        if available bufOtherRevenue then 
        do:
            run put-stream(
                /*Table*/
                "OtherRevenue" + "," +
                /*ID*/
                getString(string(bufOtherRevenue.ID)) + ",~"" +
                /*Receipt Number*/
                getString(string(bufOtherRevenue.ReceiptList)) + "~"," +
                /*Old Paycode*/
                getString(bufOtherRevenue.PayCode) + "," +
                /*New Paycode*/
                newPaycode + ","
                ).
            assign 
                bufOtherRevenue.PayCode = newPaycode
                numMiscIncRecs = numMiscIncRecs + 1.
            release bufOtherRevenue.
        end.
    end.
end procedure.

procedure assignSARefund:
    def input parameter inpid as int64.
    def input parameter newPaycode as char no-undo.
    def buffer bufReversal for Reversal.
    do for bufReversal transaction:
        find bufReversal exclusive-lock where bufReversal.id = inpid no-error no-wait.
        if available bufReversal then 
        do:
            run put-stream(
                /*Table*/
                "Reversal" + "," +
                /*ID*/
                getString(string(bufReversal.ID)) + "," +
                /*Receipt Number*/
                getString(string(bufReversal.ReceiptNumber)) + "," +
                /*Old Paycode*/
                getString(bufReversal.PayCode) + "," +
                /*New Paycode*/
                newPaycode +
                ",").
            assign
                bufReversal.PayCode = newPaycode
                numRefundRecs = numRefundRecs + 1.
            release bufReversal.
        end.
    end.
end procedure.

procedure assignSAGLDistribution:
    def input parameter inpid as int64.
    def input parameter newPaycode as char no-undo.
    def buffer bufLedgerEntry for LedgerEntry.
    do for bufLedgerEntry transaction:
        find bufLedgerEntry exclusive-lock where bufLedgerEntry.id = inpid no-error no-wait.
        if available bufLedgerEntry then
        do:
            run put-stream(
                /*Table*/
                "LedgerEntry" + "," +
                /*ID*/
                getString(string(bufLedgerEntry.ID)) + "," +
                /*Receipt Number*/
                getString(string(bufLedgerEntry.ReceiptNumber)) + "," +
                /*Old Paycode*/
                getString(bufLedgerEntry.PayCode) + "," +
                /*New Paycode*/
                newPaycode +
                ",").
            assign 
                bufLedgerEntry.PayCode = newPaycode
                numGLDistRecs               = numGLDistRecs + 1.
            release bufLedgerEntry.
        end.
    end.
end procedure.

procedure assignSACreditCardHistory:
    def input parameter inpid as int64.
    def input parameter newPaycode as char no-undo.
    def buffer bufCardTransactionLog for CardTransactionLog.
    do for bufCardTransactionLog transaction:
        find bufCardTransactionLog exclusive-lock where bufCardTransactionLog.id = inpid no-error no-wait.
        if available bufCardTransactionLog then
        do:
            run put-stream(
                /*Table*/
                "CardTransactionLog" + "," +
                /*ID*/
                getString(string(bufCardTransactionLog.ID)) + "," +
                /*Receipt Number*/
                getString(string(bufCardTransactionLog.ReceiptNumber)) + "," +
                /*Old Paycode*/
                getString(bufCardTransactionLog.PayCode) + "," +
                /*New Paycode*/
                newPaycode +
                ",").
            assign 
                bufCardTransactionLog.PayCode = newPaycode
                numCCHistRecs               = numCCHistRecs + 1.
            release bufCardTransactionLog.
        end.
    end.
end procedure.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
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