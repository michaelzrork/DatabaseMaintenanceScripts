/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "closeSAReceiptInProcess" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Closes all PaymentReceipt records without a session ID that are currently ~'In Process~'''"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s)   : 
   Created     : 
   Notes       : 
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i} 
{Includes/TransactionDetailCartStatusList.i}
{Includes/TransactionDetailStatusList.i}
{Includes/InterfaceData.i}

function ParseList character (inputValue as char) forward.
function RoundUp returns decimal(dValue as decimal,precision as integer) forward.
function AddCommas returns character (dValue as decimal) forward.

define stream   ex-port.
define variable inpfile-num     as integer   no-undo init 1.
define variable inpfile-loc     as character no-undo.
define variable counter         as integer   no-undo.
define variable ixLog           as integer   no-undo. 
define variable logfileDate     as date      no-undo.
define variable logfileTime     as integer   no-undo.
define variable LogOnly         as logical   no-undo init false.

define variable numRecs         as integer   no-undo init 0. 

define variable HH              as integer   no-undo.
define variable adminEmail      as char      no-undo.
define variable emailID         as int64     no-undo.
define variable charTime        as char      no-undo.
define variable clerk           as char      no-undo.
define variable timeFormat      as char      no-undo.
define variable dateFormat      as char      no-undo.
define variable removedItemList as char      no-undo.
define variable tmpItem         as char      no-undo.
define variable lineBreak       as char      no-undo.
define variable eCheck          as logical   no-undo.
define variable tmpItemCount    as integer   no-undo.
define variable ccList          as char      no-undo.
define variable ix              as int       no-undo.
define variable iy              as int       no-undo.
  
define variable cc_ok           as log       no-undo.
define variable cc_VoidOrRefund as char      no-undo.
define variable cc_msg          as char      no-undo.

assign
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false
    logfileDate = today
    logfileTime = time.
    
define buffer BufSAreceipt for PaymentReceipt.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
/* I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER */
run put-stream (
    "ID," +
    "Receipt Number," +
    "Posting Date," +
    "Description," +
    "Username," +
    "HH Num," +
    "Fee Amount," +
    "Fee Paid," +
    "WordIndex," +
    "Interface Type," +
    "New Record Status,").

receipt-loop:
for each PaymentReceipt no-lock where PaymentReceipt.RecordStatus = "In Process" and PaymentReceipt.WordIndex contains "SessionID:,": 
    
    find first psopenticket no-lock where PSOpenTicket.ReceiptNumber = PaymentReceipt.ReceiptNumber no-error.  
    if available psopenticket then next receipt-loop.
        
    tmpItemCount = 0.
    for each TransactionDetail no-lock where TransactionDetail.CurrentReceipt = PaymentReceipt.ReceiptNumber:      
        HH = TransactionDetail.EntityNumber.
        /*** Need to place this above RemoveFromCart.p since that will delete the TransactionDetail record so we no longer
         *** have it when we build this list.
        ***/
        tmpItemCount = tmpItemCount + 1.
        if tmpItemCount lt 16 then assign
                tmpItem         = TransactionDetail.FileLinkCode1 + (if not isempty(TransactionDetail.filelinkcode2) then ("-" + TransactionDetail.filelinkcode2) else "") +
              (if not isempty(TransactionDetail.filelinkcode3) then ("-" + TransactionDetail.filelinkcode3) else "")
                removedItemLIst = list(removedItemList,tmpItem).
        run Business/RemoveFromCart.p (TransactionDetail.ID, {&SADetailRemoved}, yes). 
    end.
    
    if tmpItemCount gt 15 then removedItemList = removedItemList + "Plus " + string(tmpItemCount - 15) + " more...".

    for each SAReceiptpayment no-lock where SAReceiptpayment.receiptnumber = PaymentReceipt.ReceiptNumber:
        run deleteSAReceiptPayment (rowid(SAReceiptpayment)).
    end.

    /*** THESE SHOULD BE DELETED IN REMOVEFROMCART.P SINCE THEY ARE TIED TO TransactionDetail BUT THIS IS A FALL BACK JUST TO BE SAFE ***/
    for each LedgerEntry no-lock where LedgerEntry.receiptnumber = PaymentReceipt.ReceiptNumber:
        run deleteSAGLDistribution (rowid(LedgerEntry)).
    end.

    /*** THESE SHOULD BE DELETED IN REMOVEFROMCART.P SINCE THEY ARE TIED TO SADETAIL BUT THIS IS A FALL BACK JUST TO BE SAFE ***/  
    for each AccountBalanceLog no-lock where AccountBalanceLog.EntityNumber = HH and
        AccountBalanceLog.receiptnumber = PaymentReceipt.ReceiptNumber:
        run deleteSAControlAccountHistory (rowid(AccountBalanceLog)).
    end.    

    find first BufReceipt exclusive-lock where BufReceipt.ReceiptNumber = PaymentReceipt.ReceiptNumber no-error no-wait.
    if available BufReceipt then assign BufReceipt.RecordStatus = "Cancelled".
  
    timeFormat = GetDataTrue({&TimeFormat}).
    dateFormat = GetDataTrue({&DateFormat}). 

    assign 
        ccList = "".
    cchist-loop:
    for each CardTransactionLog no-lock where CardTransactionLog.ReceiptNumber = PaymentReceipt.ReceiptNumber:
        if lookup(CardTransactionLog.recordstatus,"Settled,Authorized,PreTip") = 0 or
            CardTransactionLog.amount = CardTransactionLog.AmountRefunded then next cchist-loop.
        cclist = uniquelist(string(CardTransactionLog.ID),cclist,",").
    end.
  
    if ccList <> "" then
    do ix = 1 to num-entries(ccList):
        find first sacreditcardhistory no-lock where CardTransactionLog.ID = int64(entry(ix,ccList)) no-error.
        if available CardTransactionLog then 
        do:
    
            find first Permission no-lock use-index userName where Permission.UserName = CardTransactionLog.UserName no-error.
            find first PaymentMethod no-lock where PaymentMethod.PayCode = CardTransactionLog.PayCode no-error.
            if available PaymentMethod and PaymentMethod.RecordType = "eCheck" then eCheck = true.
      
            /*** Try to void or refund the credit card sale - not possible with a refund **/
            //run business/cc_SessionCleaner.p (CardTransactionLog.ID, CardTransactionLog.DeviceCodeLink, output cc_ok, output cc_VoidOrRefund, output cc_msg).
  
            run ActivityLog("RecTrac Session Ended - Credit Card Auth Exists",
                "Receipt Number: " + string(PaymentReceipt.ReceiptNumber) + ", " + 
                "Clerk: " + CardTransactionLog.UserName + (if available Permission then ("-" + Permission.Name) else "") + ", " + 
                "Date: " + string(CardTransactionLog.ProcessDate,dateFormat) + ", " +
                "Time: " + string(CardTransactionLog.PostingTime,timeFormat) + ", " +
                "Household Number: " + string(HH),
                "Items Involved in Session: " + trim(removedItemLIst,","),
                (if eCheck then mess("ERR-603","eCheck") else mess("ERR-603","Credit Card"))).
        end.    
    end.  /*** CHECK FOR CREDIT CARD HISTORY RECORDS THAT HAVE BEEN AUTH/SETTLED/PRETIP TO WARN ABOUT THE SESSION ENDING ***/
    
    numRecs = numRecs + 1.
    
    run put-stream ("~"" +
        /*ID*/
        getString(string(PaymentReceipt.ID))
        + "~",~"" +
        /*Receipt Number*/
        getString(string(PaymentReceipt.ReceiptNumber))
        + "~",~"" +
        /*Posting Date*/
        getString(string(PaymentReceipt.PostingDate))
        + "~",~"" +
        /*Description*/
        getString(PaymentReceipt.Description)
        + "~",~"" +
        /*Username*/
        getString(PaymentReceipt.UserName)
        + "~",~"" +
        /*HH Num*/
        getString(string(PaymentReceipt.EntityNumber))
        + "~",~"" +
        /*Fee Amount*/
        getString(string(PaymentReceipt.FeeAmount))
        + "~",~"" +
        /*Fee Paid*/
        getString(string(PaymentReceipt.FeePaid))
        + "~",~"" +
        /*WordIndex*/
        getString(PaymentReceipt.WordIndex)
        + "~",~"" +
        /*Interface Type*/
        getString(PaymentReceipt.InterfaceType)
        + "~",~"" +
        /*New Record Status*/
        getString(PaymentReceipt.RecordStatus)
        + "~",").
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Check Document Center for " + {&ProgramName} + "Log for a log of Records Changed","Number of Records Found: " + addCommas(numRecs),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteSAReceiptpayment: 
    def input parameter InpRowid as rowid no-undo.
    def buffer BufReceiptpayment for SAReceiptpayment. 
    do for BufReceiptpayment transaction: 
        find first BufReceiptpayment exclusive-lock where rowid(BufReceiptpayment) = inprowid no-error no-wait.
        if available BufReceiptpayment then  delete BufReceiptpayment.
    end. 
end procedure.

procedure deleteSAGLDistribution: 
    def input parameter InpRowid as rowid no-undo.
    def buffer BufLedgerEntry for LedgerEntry. 
    do for BufLedgerEntry transaction: 
        find first BufLedgerEntry exclusive-lock where rowid(BufLedgerEntry) = inprowid no-error no-wait.
        if available BufLedgerEntry then delete BufLedgerEntry.
    end. 
end procedure.

procedure deleteSAControlAccountHistory: 
    def input parameter InpRowid as rowid no-undo.
    def buffer BufControlAccountHistory for AccountBalanceLog. 
    do for BufControlAccountHistory transaction: 
        find first BufControlAccountHistory exclusive-lock where rowid(BufControlAccountHistory) = inprowid no-error no-wait.
        if available BufControlAccountHistory then delete BufControlAccountHistory.
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
    define input parameter logDetail1 as character no-undo.
    define input parameter logDetail2 as character no-undo.
    define input parameter logDetail3 as character no-undo.
    define input parameter logDetail4 as character no-undo.
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = {&ProgramName} + ".r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail1
            bufActivityLog.Detail2       = logDetail2
            bufActivityLog.Detail3       = logDetail3
            bufActivityLog.Detail4       = logDetail4.
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