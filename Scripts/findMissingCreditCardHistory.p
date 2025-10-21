/*------------------------------------------------------------------------
    File        : findMissingCreditCardHistory.p
    Purpose     : 

    Syntax      : 

    Description : Find Split Credit Card Payments

    Author(s)   : michaelzr
    Created     : 1/16/25
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
define variable numRecs as integer no-undo.
assign
    numRecs = 0.
    
define buffer bufCardTransactionLog for CardTransactionLog.
    
define temp-table ttReceiptNum no-undo
    field receiptNumber as integer
    index receiptNumber receiptNumber.
 

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Note,ChargeHistory.ID,ChargeHistory.SpecialLinkID,CardTransactionLog.").

for each ChargeHistory no-lock where ChargeHistory.SpecialLinkTable = "CardTransactionLog" and ChargeHistory.SpecialLinkID <> ? and ChargeHistory.SpecialLinkID <> 0:
    find first CardTransactionLog no-lock where CardTransactionLog.ID = ChargeHistory.SpecialLinkID no-error no-wait.
    if available CardTransactionLog then do:
        if CardTransactionLog.PayCode = 0
        end.
        if not available CardTransactionLog then run put-stream(/*Note*/
                                                                 "Missing CardTransactionLog Record"
                                                                 + "," +
                                                                 /*ChargeHistory.ID*/
                                                                 getString(string(ChargeHistory.ID))
                                                                 + "," +
                                                                 /*ChargeHistory.SpecialLinkID*/
                                                                 getString(string(ChargeHistory.SpecialLinkID))
                                                                 
                                                                 + ",")

CCHist-loop:
for each CardTransactionLog no-lock where CardTransactionLog.PayCode = "03" and CardTransactionLog.ProcessDate le 2/27/2024 and CardTransactionLog.RecordStatus = "Settled":
    find first ttReceiptNum no-lock where ttReceiptNum.receiptNumber = CardTransactionLog.ReceiptNumber no-error no-wait.
    if not available ttReceiptNum then 
    do:
        for first bufCardTransactionLog no-lock where bufCardTransactionLog.ReceiptNumber = CardTransactionLog.ReceiptNumber and bufCardTransactionLog.ID <> CardTransactionLog.ID and bufCardTransactionLog.RecordStatus = "Settled":
            create ttReceiptNum.
            assign 
                numRecs                    = numRecs + 1
                ttReceiptNum.receiptNumber = CardTransactionLog.ReceiptNumber.
        end.
    end.
end.

for each ttReceiptNum:
    run put-stream(string(ttReceiptNum.receiptNumber)).
end.
    
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingCreditCardHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingCreditCardHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingCreditCardHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingCreditCardHistory.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Split Credit Card Payments"
            BufActivityLog.Detail2       = "Check Document Center for findMissingCreditCardHistoryLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.