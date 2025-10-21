/*------------------------------------------------------------------------
    File        : findDuplicateVerificationEmails.p
    Purpose     : 

    Syntax      : 

    Description : Find Email Verification emails sent after the email address was verified

    Author(s)   : michaelzr
    Created     : 1/8/25
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
define variable useDate as date    no-undo.
assign
    numRecs = 0
    useDate = 12/30/2024.
    
define buffer bufEmailOutbox for EmailOutbox.

define temp-table ttEmailAddress no-undo
    field emailAddress as character 
    index emailAddress emailAddress.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Email Address,Verified Date/Time,First Verification Sent Date,Duplicate Verification Sent Date,Duplicate Verification Sent Time").

// USE THIS WITHIN YOUR MAIN BLOCK OR PROCEDURE TO ADD THE LOGFILE RECORDS

email-loop:
for each EmailOutbox no-lock where EmailOutbox.EmailBody matches "*Please verify your email address*" and EmailOutbox.DateSent ge useDate and EmailOutbox.UserName = "WWW":
    find first ttEmailAddress no-lock where ttEmailAddress.emailAddress = EmailOutbox.EmailTo no-error no-wait.
    if available ttEmailAddress then next email-loop.
    create ttEmailAddress.
    assign 
        ttEmailAddress.emailAddress = EmailOutbox.EmailTo.
    for first EmailContact no-lock where EmailContact.EmailAddress = EmailOutbox.EmailTo and EmailContact.ParentTable = "Member" and EmailContact.Verified = true:
        for each bufEmailOutbox no-lock where bufEmailOutbox.EmailTo = EmailOutbox.EmailTo and bufEmailOutbox.EmailBody matches "*Please verify your email address*" and bufEmailOutbox.DateSent ge useDate and bufEmailOutbox.ID <> EmailOutbox.ID and bufEmailOutbox.UserName = "WWW":
            assign 
                numrecs = numRecs + 1.
            run put-stream("~"" + 
                /*Email Address*/
                getString(EmailOutbox.EmailTo) + "~",~"" + 
                /*Verified Date/Time*/
                getString(string(EmailContact.LastVerifiedDateTime)) + "~",~"" + 
                /*First Verification Sent Date*/
                getString(string(EmailOutbox.DateSent)) + "~",~"" + 
                /*First Verification Sent Time*/
                getString(string(EmailOutbox.SentTime / 60)) + "~",~"" +
                /*Duplicate Verification Sent Date*/
                getString(string(bufEmailOutbox.DateSent)) + "~",~"" +
                /*Duplicate Verification Sent Time*/
                getString(string(bufEmailOutbox.SentTime / 60))
                + "~",").
        end.
    end.
end.

  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findDuplicateVerificationEmailsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findDuplicateVerificationEmailsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findDuplicateVerificationEmailsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findDuplicateVerificationEmails.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Email Verification emails sent after the email address was verified"
            BufActivityLog.Detail2       = "Check Document Center for findDuplicateVerificationEmailsLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.