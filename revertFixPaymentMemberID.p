/*------------------------------------------------------------------------
    File        : revertClearReceiptBalance.p
    Purpose     : 

    Syntax      : 

    Description : Revert Clear Receipt Balance

    Author(s)   : michaelzr
    Created     : 1/1/24
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
    logfileTime = time
    counter     = 0.
    
// FILE IMPORT STUFF

{Includes/ProcessingConfig.i}
{Includes/TransactionDetailStatusList.i}
{Includes/TTVals.i}
{Includes/Screendef.i "reference-only"}  
{Includes/AvailableCredit.i}
{Includes/AvailableScholarship.i} 
{Includes/ModuleList.i} 
{Includes/TTProfile.i}

define variable importFileName as character no-undo.
define variable importfile     as char      no-undo.  
define variable tmpcode1       as char      no-undo. 

def stream exp.

def temp-table ttImport no-undo 
    field PaymentTransactionID        as int64
    field PaymentLogID        as int64
    field OriginalPersonID          as int64
    field MemberID                as int64
    field OriginalScholarshipAmount as decimal
    index PaymentTransactionID PaymentTransactionID
    index PaymentLogID PaymentLogID
    index MemberID         MemberID.
    
assign 
    importFileName = "fixPaymentMemberIDLog.txt"
    tmpcode1       = "\Import\" + importFileName.


// EVERYTHING ELSE
define variable numReceiptPaymentRecs as integer no-undo.
define variable numPaymentHistoryRecs as integer no-undo.
define variable numPersonRecs         as integer no-undo.
assign
    numReceiptPaymentRecs = 0
    numPaymentHistoryRecs = 0
    numPersonRecs         = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// GRAB INPUT FILE FROM DOCUMENT CENTER IMPORT
CreateFile (tmpcode1, false, sessionTemp(), true, false) no-error. 

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Starting Process " + string(counter) + ",,,,").

assign
    Importfile = sessionTemp() + importFileName.

run put-stream (" 1 Importfile = " + Importfile + ",,,,").

// CHECK FOR IMPORT FILE
if search(Importfile) = ? then 
do:
    // IF NOT FOUND, CREATE ERROR RECORD AND END
    run ActivityLog("; Program aborted: " + Importfile + " not found!").
    run put-stream (" 1 Importfile Problem" + Importfile + " not found!,,,,").
    SaveFileToDocuments(inpfile-loc, "\Reports\", "", no, yes, yes, "Report").  
    return.
end.   
 
// SET IMPORT FILE
input stream exp from value(importfile) no-echo.

// RESET COUNTER FOR IMPORT LOOP
assign 
    counter = 0.

// CREATE TEMP TABLE FROM INPUT FILE VALUES
import-loop:
repeat transaction:
    create ttImport.
    import stream exp delimiter "," ttImport  no-error.
    counter = counter + 1.
end.

// CLOSE INPUT STREAM
input stream exp close.  

// LOG NUMBER OF RECORDS IMPORTED FROM IMPORT FILE
run put-stream ("ttImport Records imported =  " + string(counter) + ",,,,").

// RESET COUNTER FOR LOGFILE
assign 
    counter = 0.
  
// SET CHANGES HEADER
run put-stream(",,,,").
run put-stream("Table,ID,Current Value,Restored Value,").
  
// REVERT CHANGES
ttImport-loop:
for each ttImport:
    run revertReceiptPayment(ttImport.PaymentTransactionID,ttImport.OriginalPersonID).
    run revertPaymentHistory(ttImport.PaymentLogID,ttImport.OriginalPersonID).
    run revertScholarshipAmount(ttImport.MemberID,ttImport.OriginalScholarshipAmount).
end.

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "revertClearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "revertClearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.
    
// FROM GRADE BUMP; CAME AFTER LOG FILE
DeleteBlob(tmpcode1).

// CREATE AUDIT LOG RECORD
run ActivityLog("").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/*REVERT SARECEIPTPAYMENT*/
procedure revertReceiptPayment:
    define input parameter inpID as int64 no-undo.
    define input parameter revertedPersonID as int64 no-undo.
    define variable oldPersonID as int64 no-undo.
    define buffer bufPaymentTransaction for PaymentTransaction.
    do for bufPaymentTransaction transaction:
        find first bufPaymentTransaction exclusive-lock where bufPaymentTransaction.ID = inpID no-error no-wait.
        if available bufPaymentTransaction then 
        do:
            assign
                numReceiptPaymentRecs               = numReceiptPaymentRecs + 1
                oldPersonID                         = bufPaymentTransaction.PaymentMemberID
                bufPaymentTransaction.PaymentMemberID = revertedPersonID.
                
            run put-stream("~"" +
                /*Table*/
                "PaymentTransaction"
                + "~",~"" +
                /*ID*/
                string(inpID)
                + "~",~"" +
                /*Current Value*/
                string(oldPersonID)
                + "~",~"" +
                /*Restored Value*/
                string(revertedPersonID)
                + "~",").
        end.
    end.
end procedure.

/*REVERT SAPAYMENTHISTORY*/
procedure revertPaymentHistory:
    define input parameter inpID as int64 no-undo.
    define input parameter revertedPersonID as int64 no-undo.
    define variable oldPersonID as int64 no-undo.
    define buffer bufPaymentLog for PaymentLog.
    do for bufPaymentLog transaction:
        find first bufPaymentLog exclusive-lock where bufPaymentLog.ID = inpID no-error no-wait.
        if available bufPaymentLog then 
        do:
            assign
                numPaymentHistoryRecs            = numPaymentHistoryRecs + 1
                oldPersonID                      = bufPaymentLog.MemberLinkID
                bufPaymentLog.MemberLinkID = revertedPersonID.
            run put-stream("~"" +
                /*Table*/
                "PaymentLog"
                + "~",~"" +
                /*ID*/
                string(inpID)
                + "~",~"" +
                /*Current Value*/
                string(oldPersonID)
                + "~",~"" +
                /*Restored Value*/
                string(revertedPersonID)
                + "~",").
        end.
    end.
end procedure.

/*REVERT SAPERSON SCHOLARSHIP AMOUNT*/
procedure revertScholarshipAmount:
    define input parameter inpID as int64 no-undo.
    define input parameter revertedAmount as decimal no-undo.
    define variable oldAmount as decimal no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then 
        do:
            assign
                numPersonRecs                 = numPersonRecs + 1
                oldAmount                     = bufMember.ScholarshipAmount
                bufMember.ScholarshipAmount = bufMember.ScholarshipAmount - revertedAmount.
            run put-stream("~"" +
                /*Table*/
                "Member"
                + "~",~"" +
                /*ID*/
                string(inpID)
                + "~",~"" +
                /*Current Value*/
                string(oldAmount)
                + "~",~"" +
                /*Restored Value*/
                string(revertedAmount)
                + "~",").
        end.
    end.
end procedure.
        

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "revertClearReceiptBalanceLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
    define input parameter logDetail as character no-undo.
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "revertClearReceiptBalance.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Revert Clear Receipt Balance" + logDetail
            BufActivityLog.Detail2       = "Check Document Center for revertClearReceiptBalanceLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of PaymentTransaction records reverted: " + string(numReceiptPaymentRecs)
            bufActivityLog.Detail4       = "Number of PaymentLog records reverted: " + string(numPaymentHistoryRecs)
            bufActivityLog.Detail5       = "Number of Member records reverted: " + string(numPersonRecs).
    end.
end procedure.