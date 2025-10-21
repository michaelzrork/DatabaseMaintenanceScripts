/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "fixPaymentMemberID" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Fix the incorrect PaymentMemberID on PaymentTransaction and MemberLinkID on PaymentLog"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */

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
define variable scholarshipList as character no-undo init "".

assign
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false
    logfileDate = today
    logfileTime = time.

assign
    logfileDate     = today
    logfileTime     = time.
    
define buffer bufPaymentLog for PaymentLog.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
run put-stream (
    "Date," +
    "Receipt Number," +
    "Account Number," +
    "PaymentTransaction ID," +
    "PaymentLog ID," +
    "Original Person ID," +
    "Member ID," +
    "Name," +
    "Payment Amount," +
    "Original Scholarship Amount," +
    "New Scholarship Amount,"
    ).

/* FIND ALL SCHOLARSHIP PAY CODES */
for each PaymentMethod no-lock where PaymentMethod.RecordType = "Scholarship":
    assign 
        scholarshipList = uniqueList(PaymentMethod.PayCode,scholarshipList,",").
end.

/* RECEIPT PAYMENT LOOP */
payment-loop:
for each PaymentTransaction no-lock where PaymentTransaction.PaymentMemberID <> 0 and PaymentTransaction.PaymentType = "Payment":
    if lookup(PaymentTransaction.Paycode,scholarshipList) > 0 then 
    do:
        for first PaymentLog no-lock where PaymentLog.RecordType = "Scholarship" and PaymentLog.ReceiptNumber = PaymentTransaction.ReceiptNumber and PaymentLog.MemberLinkID = PaymentTransaction.PaymentMemberID and PaymentLog.Amount = (PaymentTransaction.Amount - (PaymentTransaction.Amount * 2)):
            if PaymentLog.ParentTable = "TransactionDetail" then find first TransactionDetail no-lock where TransactionDetail.ID = PaymentLog.ParentRecord.
            if available TransactionDetail and TransactionDetail.PatronLinkID <> PaymentTransaction.PaymentMemberID and TransactionDetail.EntityNumber = PaymentTransaction.PaymentHousehold then run fixPaymentID(PaymentTransaction.ID,PaymentLog.ID,TransactionDetail.PatronLinkID).
        end.
    end.
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

/* FIX PAYMENT MEMBER ID */
procedure fixPaymentID:
    define input parameter receiptPaymentID as int64 no-undo.
    define input parameter paymentHistoryID as int64 no-undo.
    define input parameter personID as int64 no-undo.
    
    define variable originalPersonID as int64   no-undo.
    define variable originalAmount   as decimal no-undo.
    
    define buffer bufPaymentTransaction for PaymentTransaction.
    define buffer bufPaymentLog for PaymentLog.
    define buffer bufMember         for Member.
    
    assign 
        originalPersonID = 0
        originalAmount   = 0.
    
    do for bufPaymentTransaction transaction:
        
        find first bufPaymentTransaction exclusive-lock where bufPaymentTransaction.ID = receiptPaymentID no-error no-wait.
        if available bufPaymentTransaction then 
        do:
            assign
                numRecs                             = numRecs + 1
                originalPersonID                    = bufPaymentTransaction.PaymentMemberID
                bufPaymentTransaction.PaymentMemberID = personID.
    
            find first bufPaymentLog exclusive-lock where bufPaymentLog.ID = paymentHistoryID no-error no-wait.
            if available bufPaymentLog then 
            do:
                assign
                    bufPaymentLog.MemberLinkID = personID.
       
                find first bufMember exclusive-lock where bufMember.ID = personID no-error no-wait.
                if available bufMember then 
                do:
                    assign
                        originalAmount                = bufMember.ScholarshipAmount
                        bufMember.ScholarshipAmount = bufMember.ScholarshipAmount + bufPaymentLog.Amount.
                        
                    /* LOG RECORD */
                    run put-stream ("~"" +
                        /*Date*/
                        getString(string(bufPaymentTransaction.PostingDate))
                        + "~",~"" +
                        /*Receipt Number*/
                        getString(string(bufPaymentTransaction.ReceiptNumber))
                        + "~",~"" +
                        /*Account Number*/
                        getString(string(bufPaymentTransaction.PaymentHousehold))
                        + "~",~"" +
                        /*PaymentTransaction ID*/
                        getString(string(bufPaymentTransaction.ID))
                        + "~",~"" +
                        /*PaymentLog ID*/
                        getString(string(bufPaymentLog.ID))
                        + "~",~"" +
                        /*Original Person ID*/
                        getString(string(originalPersonID))
                        + "~",~"" +
                        /*Member ID*/
                        getString(string(bufMember.ID))
                        + "~",~"" +
                        /*Name*/
                        trim(getString(bufMember.FirstName) + " " + getString(bufMember.LastName))
                        + "~",~"" +
                        /*Payment Amount*/
                        getString(string(bufPaymentLog.Amount))
                        + "~",~"" +
                        /*Original Scholarship Amount*/
                        getString(string(originalAmount))
                        + "~",~"" +
                        /*New Scholarship Amount*/
                        getString(string(bufMember.ScholarshipAmount))
                        + "~",").
                end.
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