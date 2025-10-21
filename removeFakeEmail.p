/*------------------------------------------------------------------------
    File        : removeFakeEmail.p
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

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ix          as integer   no-undo. 

inpfile-num = 1.

// EVERYTHING ELSE

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

// CREATE SAEMAILADDRESS LOG FILE FIELDS
run put-stream ("RecordID,Table,EmailAddress,PrimaryEmailAddress,HouseholdNumber,ParentTable,HouseholdID,PersonID,MiscInformation,WordIndex,SubType,SiteCode,SiteArea,SiteCategory,Permissions").

// DELETE SAEMAILADDRESS RECORDS
for each EmailContact no-lock where EmailContact.EmailAddress matches "*x*@x*" or EmailContact.Emailaddress matches "*@x*x*":
    hhNum = 0.
    hhID = 0.
    if EmailContact.ParentTable = "Account" then find first Account no-lock where Account.ID = EmailContact.ParentRecord no-wait no-error.
    if available Account then assign
        hhNum = Account.EntityNumber
        hhID = Account.ID.
    if EmailContact.ParentTable = "SAperson" then
        for first Relationship no-lock where Relationship.ParentTable = "Account" and Relationship.ChildTableID = EmailContact.MemberLinkID and Relationship.ChildTable = "SAperson":
            hhID = Relationship.ParentTableID.
            find first Account no-lock where Account.ID = hhID no-error no-wait.
            if available SAhousehold then hhNum = Account.EntityNumber.
        end.
    // DELETE THE SAEMAILADDRESS RECORDS
    run deleteSAEmailAddressRecord(EmailContact.ID).
end.

// REMOVE SAHOUSEHOLD EMAIL ADDRESSES
for each Account no-lock where Account.Primaryemailaddress matches "*x*@x*" or Account.Primaryemailaddress matches "*@x*x*":
    personID = 0.
    for first Relationship no-lock where Relationship.ParentTable = "Account" and Relationship.ParentTableID = Account.ID and Relationship.Primary = true and Relationship.ChildTable = "SAperson":
        personID = Relationship.ChildTableID.
    end.
    // REMOVE THE EMAIL FROM THE HOUSEHOLD RECORD
    run removeSAHouseholdEmail(Account.ID).
end.

// REMOVE SAPERSON EMAIL ADDRESSES
for each Member no-lock where Member.Primaryemailaddress matches "*x*@x*" or Member.Primaryemailaddress matches "*@x*x*":
    hhID = 0.
    hhNum = 0.
    for first Relationship no-lock where Relationship.ParentTable = "Account" and Relationship.ChildTableID = Member.ID and Relationship.ChildTable = "SAperson":
        hhID = Relationship.ParentTableID.
        find first Account no-lock where Account.ID = hhID no-error no-wait.
        if available SAhousehold then hhNum = Account.EntityNumber.
    end.
    // REMOVE THE EMAIL FROM THE FAMILY MEMBER
    run removeSAPersonEmail(Member.ID).
end.
  
// CREATE LOG FILE
do ix = 1 to inpfile-num:
    if search(sessiontemp() + "EmailRecordsUpdated" + string(ix) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "EmailRecordsUpdated" + string(ix) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
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

        // FIND THE RECORD OF THE PERSON IN THE LOOP
        find first bufMember exclusive-lock where bufMember.ID = inpid no-error no-wait.
        if available bufMember then 
        do:
            
            // CREATE LOG ENTRY "RecordID,Table,EmailAddress,PrimaryEmailAddress,HouseholdNumber,ParentTable,HouseholdID,PersonID"
            run put-stream (string(bufMember.ID) + ",Member," + string(bufMember.PrimaryEmailAddress) + ",yes," + (if hhNum > 0 then string(hhNum) else "") + ",Account," + (if hhID > 0 then string(hhID) else "") + "," + string(bufMember.ID) + ",,,,,,,").

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

        // FIND THE RECORD OF THE PERSON IN THE LOOP
        find first bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then 
        do:
            
            // CREATE LOG ENTRY "RecordID,Table,EmailAddress,PrimaryEmailAddress,HouseholdNumber,ParentTable,HouseholdID,PersonID"
            run put-stream (string(bufAccount.ID) + ",Account," + string(bufAccount.PrimaryEmailAddress) + ",yes," + string(bufAccount.EntityNumber) + ",Account," + string(bufAccount.ID) + "," + (if personID > 0 then string(personID) else "") + ",,,,,,,").

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
        // FIND THE EMAIL ADDRESS RECORD THAT MATCHES THE PERSON IN THE LOOP
        find first bufEmailContact exclusive-lock where bufEmailContact.ID = inpid no-error no-wait.
        if available bufEmailContact then 
        do:
            // CREATE LOG ENTRY "RecordID,Table,EmailAddress,PrimaryEmailAddress,HouseholdNumber,ParentTable,HouseholdID,PersonID,MiscInformation,WordIndex,SubType,SiteCode,SiteArea,SiteCategory,Permissions"
            run put-stream (string(bufEmailContact.ID) + ",EmailContact," + string(bufEmailContact.EmailAddress) + "," + string(bufEmailContact.PrimaryEmailAddress) + "," + (if hhNum > 0 then string(hhNum) else "") + "," + string(bufEmailContact.ParentTable) + "," + (if bufEmailContact.ParentTable = "Account" then string(bufEmailContact.ParentRecord) else "") + "," + string(bufEmailContact.MemberLinkID) + "," + string(bufEmailContact.MiscInformation) + "," + string(bufEmailContact.WordIndex) + string(bufEmailContact.SubType) + string(bufEmailContact.SiteCode) + string(bufEmailContact.SiteArea) + string(bufEmailContact.SiteCategory) + string(bufEmailContact.Permissions)).
            // ADD TO NUMBER OF EMAILS DELETED COUNT 
            numEmailsDeleted = numEmailsDeleted + 1.
            // DELETE THE SAEMAILADDRESS TABLE RECORD
            delete bufEmailContact.
        end.
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "EmailRecordsUpdated" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 15000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "removeFakeEmail"
            bufActivityLog.LogDate       = today
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Set current fake emails to blank"
            bufActivityLog.Detail2       = "Number of Member emails removed: " + string(numFMEmailsCleared)
            bufActivityLog.Detail3       = "Number of Account emails removed: " + string(numHHEmailsCleared).
        bufActivityLog.Detail4       = "Number of EmailContact records removed: " + string(numEmailsDeleted).
            
    end.
end procedure.