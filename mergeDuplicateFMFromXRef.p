/*------------------------------------------------------------------------
    File        : mergeDuplicateFMFromXRef.p
    Purpose     : Merge duplicate Member within the same HH

    Syntax      : 

    Description : After a account import added a leading 0 to the Xref, duplicate family members
                  were created that need to be merged into one another. The duplicate family members
                  all have the same Xref as the originals (which matches the Account num), but with the 
                  leading 0.

    Author(s)   : michaelzr
    Created     : 1/10/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i} 
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i}
{Includes/ttAccountMerge.i}
{Includes/ModuleList.i}

define variable dupeFirstName   as character no-undo.
define variable origFirstName   as character no-undo.
define variable dupeLastName    as character no-undo.
define variable origLastName    as character no-undo.
define variable dupeDateOfBirth as date      no-undo.
define variable origDateOfBirth as date      no-undo.
define variable dupeGender      as character no-undo. 
define variable origGender      as character no-undo.
define variable mergeAccountNum      as integer   no-undo. 
define variable numRecs         as integer   no-undo.
define variable dupeMemberID        as int64     no-undo.
define variable dupeOrderNum    as integer   no-undo.
define variable origOrderNum    as integer   no-undo.
define variable origMemberID        as int64     no-undo.
define variable accountID            as int64     no-undo.
define variable ix              as integer   no-undo.
assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

xref-loop:
for each EntityLink no-lock where EntityLink.ExternalID = "0" + string(EntityLink.EntityNumber) by EntityLink.MemberLinkID:
    assign
        /* RESET VARIABLES */
        dupeFirstName   = ""
        origFirstName   = ""
        dupeLastName    = ""
        origLastName    = ""
        dupeDateOfBirth = ?
        origDateOfBirth = ?
        dupeGender      = ""
        origGender      = ""
        mergeAccountNum      = 0
        dupeMemberID        = 0
        dupeOrderNum    = 0
        origOrderNum    = 0
        origMemberID        = 0
        accountID            = 0
        ix              = 0
        /* ASSIGN NEW VALUES */
        mergeAccountNum      = EntityLink.EntityNumber
        dupeMemberID        = EntityLink.MemberLinkID.
        
    /* FIND ACCOUNT ID */
    for first Account no-lock where Account.EntityNumber = mergeAccountNum:
        assign 
            accountID = Account.ID.
    end.
    
    for each Relationship no-lock where Relationship.ParentTableID = accountID and Relationship.RecordType = "Account" by Relationship.Order:
        assign 
            ix = ix + 1.
        if ix ne SaLink.Order then
            run SetRelationship(SaLink.id, Relationship.Primary, ix, Relationship.Relationship).   
    end.
    
    if accountID = 0 then next xref-loop.
    
    /* FIND DUPE PERSON ORDER NUMBER */
    for first Relationship no-lock where Relationship.ChildTableID = dupeMemberID and Relationship.ParentTableID = accountID and Relationship.RecordType = "Account" and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
        dupeOrderNum = Relationship.Order.
    end.
    
    /* FIND DUPE PERSON RECORD */
    find first Member no-lock where Member.ID = dupeMemberID no-error no-wait.
    if not available Member then next xref-loop.
    assign
        dupeFirstName   = Member.FirstName
        dupeLastName    = Member.LastName
        dupeDateOfBirth = Member.Birthday
        dupeGender      = Member.Gender.
    run findOriginalFMID.
    
    if origMemberID = 0 or origMemberID = dupeMemberID then next xref-loop. 
    
    run mergeMember.
    
    /* CHECK FOR TERTIARY MEMBERS */
    for each Relationship no-lock where Relationship.ChildTableID <> origMemberID and Relationship.ParentTableID = accountID and Relationship.RecordType = "Account" and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member" by Relationship.Order:
        run checkForAdditionalFMs(Relationship.ID).
        if dupeOrderNum > 0 then run mergeMember.
    end.
        
end.

run ActivityLog.


    

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SET RELATIONSHIP ORDER
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

// FIND DUPLICATE XREF RECORD
procedure findOriginalFMID:
    define buffer bufRelationship   for Relationship.
    define buffer bufMember for Member.
    link-loop:
    for each bufRelationship no-lock where bufRelationship.ChildTableID <> dupeMemberID and bufRelationship.ParentTableID = accountID and bufRelationship.RecordType = "Account" and bufRelationship.ParentTable = "Account" and bufRelationship.ChildTable = "Member" by bufRelationship.Order:
        for first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID and bufMember.FirstName = dupeFirstName and bufMember.LastName = dupeLastName and bufMember.Birthday = dupeDateOfBirth:
            assign
                origOrderNum    = bufRelationship.Order
                origMemberID        = bufMember.ID
                origFirstName   = bufMember.FirstName
                origLastName    = bufMember.LastName
                origDateOfBirth = bufMember.Birthday
                origGender      = bufMember.Gender.
        end.
        if origOrderNum > 0 then leave link-loop.
    end. 
end procedure.

// CHECK FOR ADDITIONAL MEMBERS
procedure checkForAdditionalFMs:
    define input parameter inpID as int64 no-undo.
    define buffer bufRelationship   for Relationship.
    define buffer bufMember for Member.
    assign
        dupeOrderNum    = 0
        dupeMemberID        = 0
        dupeFirstName   = ""
        dupeLastName    = ""
        dupeDateOfBirth = ?
        dupeGender      = "".
    find first bufRelationship no-lock where bufRelationship.ID = inpID no-error no-wait.
    if not available bufRelationship then return.
    for first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID and bufMember.FirstName = origFirstName and bufMember.LastName = origLastName and bufMember.Birthday = origDateOfBirth:
        assign
            dupeOrderNum    = bufRelationship.Order
            dupeMemberID        = bufMember.ID
            dupeFirstName   = bufMember.FirstName
            dupeLastName    = bufMember.LastName
            dupeDateOfBirth = bufMember.Birthday
            dupeGender      = bufMember.Gender.
    end. 
end procedure.

// SEND FAMILY MEMBERS TO Account TRANSFER MERGE PROGRAM
procedure mergeMember:
    
    numRecs = numRecs + 1. 
    
    setData("HouseholdMerge_FromHousehold",string(mergeAccountNum)). 
    setData("HouseholdMerge_ToHousehold",string(mergeAccountNum)).  
    setdata("SubAction","Start").
    run business/HouseholdMerge.p.

    setdata("SubAction","FetchTempFamilyFromRecords").
    run business/HouseholdMerge.p. 
    
    setdata("SubAction","FetchTempFamilyToRecords").
    run business/HouseholdMerge.p.

    setData("FieldList","number,firstname,lastname,birthday,gender,mergeoptionfamily"). 
    setData("FieldName","FamilyMemberMerge_FamilyFromGrid").
    setData("LinkRecordID",string(dupeOrderNum)).
    setData("number",string(dupeOrderNum)).
    setData("firstname",string(origFirstName)).
    setData("lastname",string(origLastName)).
    setData("birthday",string(origDateOfBirth)).
    setData("gender",string(origGender)).  
    setData("mergeoptionfamily",string(substitute("Merge with &1 (#&2) in the To Account",string(origFirstName + " " + origLastName),string(origOrderNum)))).
    setData("number_previous",string(dupeOrderNum)).
    setData("firstname_previoius",string(dupeFirstName)).
    setData("lastname_previous",string(dupeLastName)).
    setData("birthday_previous",string(dupeDateOfBirth)).
    setData("gender_previous",string(dupeGender)).  
    setData("mergeoptionfamily_previous","Do Not Transfer/Merge").
    setdata("SubAction","StoreInContextInlineFamily").
    run business/HouseholdMerge.p. 
    
    setdata("SubAction","Continue").
    run business/HouseholdMerge.p.
   
    setdata("SubAction","Continue2").
    run business/HouseholdMerge.p.

end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY TRANSACTIONDETAIL RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "mergeDuplicateFMFromXRef.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Merge duplicate family members within the same HH"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.
