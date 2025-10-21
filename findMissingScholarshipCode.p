/*------------------------------------------------------------------------
    File        : findMissingScholarshipCode.p
    Purpose     : 

    Syntax      : 

    Description : xDescription

    Author(s)   : michaelzr
    Created     : 
    Notes       : To use this template:
                    - Start with a save as! (I've forgotten this step and needed to recreate this template many times!)
                    - Do a find/replace all for findMissingScholarshipCode and xDescription to update all locations these are mentioned; these will print in the audit log and the logfile will be named findMissingScholarshipCodeLog 
                    - Replace the put-stream field headers with your actual headers; this is the first row of your logfile
                    - Update the second put-stream with the appropriate fields for your log and place it within your main block or procedure
                    - Don't forget to add a creation date and update the Author!
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
define variable numRecs                 as integer   no-undo.
define variable cListScholarShipPayCode as character no-undo.

assign
    numRecs                 = 0
    cListScholarShipPayCode = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ReceiptNumber,FeeHist ID,FeeHist Paycode,ReceiptPayment ID,ReceiptPayment Paycode,Scholarship Code").

/*** BUILD SCHOLARSHIP PAYCODE LIST ***/
for each PaymentMethod no-lock where PaymentMethod.RecordType = "Scholarship":
    cListScholarShipPayCode = List(PaymentMethod.PayCode, cListScholarShipPayCode).
end.

for each ChargeHistory no-lock where lookup(ChargeHistory.PayCode,cListScholarshipPaycode) <> 0 and ChargeHistory.RecordStatus = "Paid":
    for each PaymentTransaction no-lock where PaymentTransaction.ParentTable = "ChargeHistory" and PaymentTransaction.ParentRecord = ChargeHistory.ID:
        if PaymentTransaction.ScholarshipCode = "" or PaymentTransaction.ScholarshipCode = ? then run put-stream("~"" +
                /*ReceiptNumber*/
                getString(string(ChargeHistory.ReceiptNumber))
                + "~",~"" + 
                /*FeeHist ID*/
                getString(string(ChargeHistory.ID))
                + "~",~"" + 
                /*FeeHist Paycode*/
                getString(ChargeHistory.PayCode)
                + "~",~"" + 
                /*ReceiptPayment ID*/
                getString(string(PaymentTransaction.ID))
                + "~",~"" + 
                /*ReceiptPayment Paycode*/
                getString(PaymentTransaction.Paycode)
                + "~",~"" + 
                /*Scholarship Code*/
                getString(PaymentTransaction.ScholarshipCode)
                + "~",").
    end.
    if not available PaymentTransaction then run put-stream("~"" +
                /*ReceiptNumber*/
                getString(string(ChargeHistory.ReceiptNumber))
                + "~",~"" + 
                /*FeeHist ID*/
                getString(string(ChargeHistory.ID))
                + "~",~"" + 
                /*FeeHist Paycode*/
                getString(ChargeHistory.PayCode)
                + "~",~"" + 
                /*ReceiptPayment ID*/
                "No PaymentReceipt Payment record available"
                + "~",~"" + 
                /*ReceiptPayment Paycode*/
                ""
                + "~",~"" + 
                /*Scholarship Code*/
                ""
                + "~",").
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingScholarshipCodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingScholarshipCodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingScholarshipCodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingScholarshipCode.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "xDescription"
            BufActivityLog.Detail2       = "Check Document Center for findMissingScholarshipCodeLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.