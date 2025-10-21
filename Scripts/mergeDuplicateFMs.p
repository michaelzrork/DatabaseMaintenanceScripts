/*------------------------------------------------------------------------
    File        : mergeDuplicateFMs.p
    Purpose     : Merge duplicate members within the same account

    Syntax      :

    Description : This merges duplicate members within the same account that match first name, last name, and birthday.

    Author(s)   : michaelzr
    Created     : 1/10/2024
    Notes       : Modified from mergeDuplicateFMFromXRef.p on 2/25/25
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i}
{Includes/ttAccountMerge.i}
{Includes/ModuleList.i}

define variable dupeFirstName     as character no-undo.
define variable origFirstName     as character no-undo.
define variable dupeLastName      as character no-undo.
define variable origLastName      as character no-undo.
define variable dupeDateOfBirth   as date      no-undo.
define variable origDateOfBirth   as date      no-undo.
define variable dupeGender        as character no-undo. 
define variable origGender        as character no-undo.
define variable mergeAccountNum   as integer   no-undo.
define variable numRecs           as integer   no-undo.
define variable dupeMemberID      as int64     no-undo.
define variable dupeOrderNum      as integer   no-undo.
define variable origOrderNum      as integer   no-undo.
define variable origMemberID      as int64     no-undo.
define variable accountID         as int64     no-undo.
define variable ix                as integer   no-undo.

define variable SubAction         as character no-undo.
define variable MergeOption       as character no-undo init "transfer".
define variable FromAccountNumber as integer   no-undo.
define variable FromAccountID     as int64     no-undo.
define variable ToAccountNumber   as integer   no-undo.
define variable ToAccountID       as int64     no-undo.  
define variable ChangeStaffInfo   as logical   no-undo. 
define variable DisplayMerge      as logical   no-undo.
define variable DateFormat        as character no-undo.
define variable TimeFormat        as character no-undo.
define variable iy                as integer   no-undo.
define variable ConflictCount     as integer   no-undo.
define variable Good-Hist         as logical   no-undo.
define variable SessionID         as character no-undo.
define variable SubsessionID      as character no-undo. 
define variable emnum             as integer   no-undo.
define variable photo-check       as logical   no-undo.
define variable ContinueError        as character no-undo.
define variable ModelAccountList     as character no-undo.
define variable InternalAccountList  as character no-undo.
define variable ModelAccountModuleList as character no-undo.
define variable ModuleList           as character no-undo.
define variable NewFileName          as character no-undo.
define variable InternalAccount      as character no-undo.

define buffer bufToAccount   for Account.
define buffer bufFromAccount for Account. 
    
assign
    numRecs  = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* ACCOUNT LOOP */
for each Account no-lock:
    assign
        mergeAccountNum = Account.EntityNumber
        accountID       = Account.ID.

    /* SET ORIGINAL MEMBER TO MERGE INTO */
    relationship-loop:
    for each Relationship no-lock where Relationship.ParentTableID = accountID and Relationship.RecordType = "Household" by Relationship.Order:
        assign
            origMemberID = Relationship.ChildTableID
            origOrderNum = Relationship.Order.
        find first Member no-lock where Member.ID = origMemberID no-error no-wait.
        if not available Member then next relationship-loop.
        if available Member then assign
                origMemberID    = Member.ID
                origFirstName   = Member.FirstName
                origLastName    = Member.LastName
                origDateOfBirth = Member.Birthday
                origGender      = Member.Gender.

        define buffer bufRelationship for Relationship.
        define buffer bufMember for Member.

        /* FIND DUPLICATE MEMBERS */
        for each bufRelationship no-lock where bufRelationship.ChildTableID <> origMemberID and bufRelationship.ParentTableID = accountID and bufRelationship.RecordType = "Household" and bufRelationship.ParentTable = "Account" and bufRelationship.ChildTable = "Member" by bufRelationship.Order:
            /* RESET VARIABLES */
            assign
                dupeOrderNum    = 0
                dupeMemberID    = 0
                dupeFirstName   = ""
                dupeLastName    = ""
                dupeDateOfBirth = ?
                dupeGender      = "".

            /* IF MEMBER RECORD MATCHES ORIGINAL FIRST NAME, LAST NAME, AND BIRTHDAY, SET AS DUPLICATE MEMBER AND MERGE INTO ORIGINAL */
            for first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID and bufMember.FirstName = origFirstName and bufMember.LastName = origLastName and bufMember.Birthday = origDateOfBirth:
                assign
                    dupeOrderNum    = bufRelationship.Order
                    dupeMemberID    = bufMember.ID
                    dupeFirstName   = bufMember.FirstName
                    dupeLastName    = bufMember.LastName
                    dupeDateOfBirth = bufMember.Birthday
                    dupeGender      = bufMember.Gender.
            end.

            if dupeOrderNum > 0 then run mergeMember.

        end. // DUPLICATE MEMBER LOOP
    end. // RELATIONSHIP LOOP
end. // ACCOUNT LOOP

run ActivityLog("Merged duplicate members within the same account").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* SET RELATIONSHIP ORDER */
procedure SetRelationship:

    define input parameter inpID as int64 no-undo.
    define input parameter isprimary as logical no-undo.
    define input parameter order as int no-undo.
    define input parameter relationship as char no-undo.

    def buffer buf-Relationship for Relationship.

    do for buf-Relationship transaction:
        find buf-Relationship exclusive-lock where buf-Relationship.id =  inpID no-error no-wait.
        if available buf-Relationship then assign
                buf-Relationship.Primary      = isprimary
                buf-Relationship.Order        = order
                buf-Relationship.Relationship = relationship.
    end.
end procedure.

/* SEND MEMBERS TO ACCOUNT TRANSFER MERGE PROGRAM */
procedure mergeMember:
    
    numRecs = numRecs + 1.

    setData("AccountMerge_FromAccount", string(mergeAccountNum)).
    setData("AccountMerge_ToAccount", string(mergeAccountNum)).
    setdata("SubAction", "Start").
    run Business/MergeAccounts.p.  /* External business logic API */

    setdata("SubAction", "FetchTempMemberFromRecords").
    run Business/MergeAccounts.p.  /* External business logic API */

    setdata("SubAction", "FetchTempMemberToRecords").
    run Business/MergeAccounts.p.  /* External business logic API */

    setData("FieldList", "number,firstname,lastname,birthday,gender,mergeoptionmember").
    setData("FieldName", "MemberMerge_MemberFromGrid").
    setData("LinkRecordID", string(dupeOrderNum)).
    setData("number", string(dupeOrderNum)).
    setData("firstname", string(origFirstName)).
    setData("lastname", string(origLastName)).
    setData("birthday", string(origDateOfBirth)).
    setData("gender", string(origGender)).
    setData("mergeoptionmember", string(substitute("Merge with &1 (#&2) in the To Account", string(origFirstName + " " + origLastName), string(origOrderNum)))).
    setData("number_previous", string(dupeOrderNum)).
    setData("firstname_previous", string(dupeFirstName)).
    setData("lastname_previous", string(dupeLastName)).
    setData("birthday_previous", string(dupeDateOfBirth)).
    setData("gender_previous", string(dupeGender)).
    setData("mergeoptionmember_previous", "Do Not Transfer/Merge").

    setdata("SubAction", "StoreInContextInlineMember").
    run Business/MergeAccounts.p.  /* External business logic API */

    setdata("SubAction", "Continue").
    run Business/MergeAccounts.p.  /* External business logic API */

    setdata("SubAction", "Continue2").
    run Business/MergeAccounts.p.  /* External business logic API */

end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    define input parameter logDetail as character no-undo.
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "mergeDuplicateFMs.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = logDetail
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.