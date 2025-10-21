/*------------------------------------------------------------------------
    File        : clearMyDumbEmails.p
    Purpose     : Remove fake email addresses records

    Syntax      : 

    Description : To set any email address that is using the fake email address pattern (x@x.) to blank

    Author(s)   : michaelzr
    Created     : 12/29/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable householdEmail     as character no-undo.
define variable primaryCheck       as logical   no-undo.
define variable numFMEmailsCleared as integer   no-undo.
define variable numHHEmailsCleared as integer   no-undo.
define variable numEmailsDeleted   as integer   no-undo.
define variable hhNum              as int       no-undo.
define variable hhID               as int64     no-undo.
define variable personID           as int64     no-undo.

assign
    householdEmail     = ""
    numFMEmailsCleared = 0
    numHHEmailsCleared = 0
    numEmailsDeleted   = 0
    hhNum              = 0
    hhID               = 0
    personID           = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// DISABLES AUTOMATIC VERIFICATION EMAIL PROMPTS WHEN UPDATING THE EMAIL ADDRESSES
disable triggers for load of EmailContact.

// REMOVE SAHOUSEHOLD EMAIL ADDRESSES
for each Account no-lock:
    run removeSAHouseholdEmail(Account.ID).
end.

// REMOVE SAPERSON EMAIL ADDRESSES
for each Member no-lock:
    run removeSAPersonEmail(Member.ID).
end.

// DELETE SAEMAILADDRESS RECORDS
for each EmailContact no-lock:
    run deleteSAEmailAddressRecord(EmailContact.ID).
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// REMOVE THE PERSON EMAIL ADDRESS
procedure removeSAPersonEmail:
    define input parameter inpid as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpid no-error no-wait.
        if available bufMember then 
        do:
            // ADD TO NUMBER OF EMAILS CLEARED COUNT
            numFMEmailsCleared = numFMEmailsCleared + 1.
            
            // BLANK OUT THE EMAIL ADDRESS
            bufMember.PrimaryEmailAddress = "".
        end.
    end.
end. 

// REMOVE THE HOUSEHOLD EMAIL ADDRESS
procedure removeSAHouseholdEmail:
    define input parameter inpid as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then 
        do:
            // ADD TO NUMBER OF EMAILS CLEARED COUNT
            numHHEmailsCleared = numHHEmailsCleared + 1.
            
            // BLANK OUT THE EMAIL ADDRESS
            bufAccount.PrimaryEmailAddress = "".
        end.
    end.
end. 

// DELETE THE EMAIL ADDRESS RECORD
procedure deleteSAEmailAddressRecord:
    define input parameter inpid as int64 no-undo.
    define buffer bufEmailContact for EmailContact.
    do for bufEmailContact transaction:
        find first bufEmailContact exclusive-lock where bufEmailContact.ID = inpid no-error no-wait.
        if available bufEmailContact then 
        do:
            // ADD TO NUMBER OF EMAILS DELETED COUNT 
            numEmailsDeleted = numEmailsDeleted + 1.
            // DELETE THE SAEMAILADDRESS TABLE RECORD
            delete bufEmailContact.
        end.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "clearMyDumbEmails.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Clear all emails from database"
            bufActivityLog.Detail2       = "Number of Member emails removed: " + string(numFMEmailsCleared)
            bufActivityLog.Detail3       = "Number of Account emails removed: " + string(numHHEmailsCleared)
            bufActivityLog.Detail4       = "Number of EmailContact records removed: " + string(numEmailsDeleted).
            
    end.
end procedure.