/*------------------------------------------------------------------------
    File        : findEmailVerificationsSentAfterVerified.p
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
define variable numRecs      as integer   no-undo.
define variable hhNum        as integer   no-undo.
define variable hhID         as int64     no-undo.
define variable runDate      as date      no-undo.
define variable fmName       as character no-undo.
define variable personID     as int64     no-undo.
define variable hasSameEmail as logical   no-undo.

assign
    numRecs      = 0
    hhNum        = 0
    hhID         = 0
    personID     = 0
    fmName       = ""
    hasSameEmail = false
    runDate      = 12/30/2024.
    
define buffer bufEmailContact for EmailContact.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Household ID
                ,Household Number
                ,Person ID
                ,Name
                ,Email Address
                ,Family Members with Same Email?
                ,Last Verified Date/Time
                ,Verification Sent Date
                ,Verification Email Date Sent
                ,Verification Email Time Sent
                ,").

// USE THIS WITHIN YOUR MAIN BLOCK OR PROCEDURE TO ADD THE LOGFILE RECORDS
for each EmailContact no-lock where EmailContact.Verified = true and EmailContact.ParentTable = "Member" and EmailContact.VerificationSentDate < today - 365:
    for first bufEmailContact no-lock where bufEmailContact.EmailAddress = EmailContact.EmailAddress and bufEmailContact.ParentTable = "Account" and bufEmailContact.MemberLinkID = EmailContact.MemberLinkID:
        assign 
            hhID = bufEmailContact.ParentRecord.
        find first Account no-lock where Account.ID = bufEmailContact.ParentRecord no-error no-wait.
        if available Account then assign 
                hhNum = Account.EntityNumber.
        for each Relationship no-lock where Relationship.ParentTableID = hhID and Relationship.ChildTableID <> EmailContact.MemberLinkID while hasSameEmail = false:
            find first Member no-lock where Member.PrimaryEmailAddress = EmailContact.EmailAddress no-error no-wait.
            if available Member then assign hasSameEmail = true.
        end.
    end.
    if not available bufEmailContact then 
    do:
        find first Relationship no-lock where Relationship.ChildTableID = EmailContact.MemberLinkID no-error no-wait.
        if available Relationship then find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
        if available Account then assign
                hhID  = Account.ID
                hhNum = Account.EntityNumber.
        for each Relationship no-lock where Relationship.ParentTableID = hhID and Relationship.ChildTableID <> EmailContact.MemberLinkID while hasSameEmail = false:
            find first Member no-lock where Member.PrimaryEmailAddress = EmailContact.EmailAddress no-error no-wait.
            if available Member then assign hasSameEmail = true.
        end.
    end.
    find first Member no-lock where Member.ID = EmailContact.MemberLinkID no-error no-wait.
    if available Member then assign
            personID = Member.ID
            fmName   = trim(getString(Member.FirstName) + " " + getString(Member.LastName)).
    for each EmailOutbox no-lock where EmailOutbox.EmailTo = EmailContact.EmailAddress and EmailOutbox.EmailBody matches "*Please verify your email address*" and EmailOutbox.DateSent ge runDate:
        if EmailOutbox.SentTime ge int(mtime(EmailContact.LastVerifiedDateTime) / 1000) then 
        do:
            assign 
                numrecs = numRecs + 1.
            run put-stream("~"" +
                /*Household ID*/
                getString(string(hhID)) + "~",~"" +
                /*Household Number*/
                getString(string(hhNum)) + "~",~"" +
                /*Person ID*/
                getString(string(PersonID)) + "~",~"" +
                /*Name*/
                getString(fmName) + "~",~"" +
                /*Email Address*/
                getString(EmailContact.EmailAddress) + "~",~"" +
                /*Family Members with Same Email?*/
                (if hasSameEmail = true then "Yes" else "No") + "~",~"" +
                /*Last Verified Date/Time*/
                getString(string(EmailContact.LastVerifiedDateTime)) + "~",~"" +
                /*Verification Sent Date*/
                getString(string(EmailContact.VerificationSentDate)) + "~",~"" +
                /*Verification Email Date Sent*/
                getString(string(EmailOutbox.DateSent)) + "~",~"" +
                /*Verification Email Time Sent*/ 
                getString(string(if EmailOutbox.SentTime = 0 then 0 else (EmailOutbox.SentTime / 60)))
                + "~",").
        end.
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findEmailVerificationsSentAfterVerifiedLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findEmailVerificationsSentAfterVerifiedLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findEmailVerificationsSentAfterVerifiedLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findEmailVerificationsSentAfterVerified.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Email Verification emails sent after the email address was verified"
            BufActivityLog.Detail2       = "Check Document Center for findEmailVerificationsSentAfterVerifiedLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.