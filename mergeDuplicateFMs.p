/*------------------------------------------------------------------------
    File        : mergeDuplicateFMs.p
    Purpose     : Merge duplicate FM within the same HH

    Syntax      : 

    Description : This merges duplicate family members within the same household that match first name, last name, and birthday.

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
{Includes/ttHouseholdMerge.i}
{Includes/ModuleList.i}

define variable dupeFirstName     as character no-undo.
define variable origFirstName     as character no-undo.
define variable dupeLastName      as character no-undo.
define variable origLastName      as character no-undo.
define variable dupeDateOfBirth   as date      no-undo.
define variable origDateOfBirth   as date      no-undo.
define variable dupeGender        as character no-undo. 
define variable origGender        as character no-undo.
define variable mergeHHnum        as integer   no-undo. 
define variable numRecs           as integer   no-undo.
define variable dupeFMID          as int64     no-undo.
define variable dupeOrderNum      as integer   no-undo.
define variable origOrderNum      as integer   no-undo.
define variable origFMID          as int64     no-undo.
define variable hhID              as int64     no-undo.
define variable ix                as integer   no-undo.

define variable SubAction         as character no-undo.
define variable MergeOption       as character no-undo init "transfer". 
define variable FromHHNumber      as integer   no-undo.
define variable FromHHID          as int64     no-undo.
define variable ToHHNumber        as integer   no-undo.
define variable ToHHID            as int64     no-undo.  
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
define variable ContinueError     as character no-undo.     
define variable ModelHHList       as character no-undo.
define variable InternalHHList    as character no-undo.
define variable ModelHHModuleList as character no-undo.
define variable ModuleList        as character no-undo. 
define variable NewFileName       as character no-undo.
define variable InternalHH        as character no-undo.

define buffer bufToSAHousehold   for Account.
define buffer bufFromSAHousehold for Account. 
    
assign
    numRecs  = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* HOUSEHOLD LOOP */
for each Account no-lock:
    assign 
        mergehhNum = Account.EntityNumber 
        hhID       = Account.ID.
    
    /* SET ORIGINAL FAMILY MEMBER TO MERGE INTO */
    salink-loop:
    for each Relationship no-lock where Relationship.ParentTableID = hhID and Relationship.RecordType = "Household" by Relationship.Order:
        assign
            origFMID     = Relationship.ChildTableID
            origOrderNum = Relationship.Order.    
        find first Member no-lock where Member.ID = origFMID no-error no-wait.
        if not available Member then next salink-loop.
        if available Member then assign
                origFMID        = Member.ID
                origFirstName   = Member.FirstName
                origLastName    = Member.LastName
                origDateOfBirth = Member.Birthday
                origGender      = Member.Gender.
                
        define buffer bufRelationship   for Relationship.
        define buffer bufMember for Member.
    
        /* FIND DUPLICATE FAMILY MEMBERS */
        for each bufRelationship no-lock where bufRelationship.ChildTableID <> origFMID and bufRelationship.ParentTableID = hhID and bufRelationship.RecordType = "Household" and bufRelationship.ParentTable = "Account" and bufRelationship.ChildTable = "Member" by bufRelationship.Order:
            /* RESET VARIABLES */
            assign
                dupeOrderNum    = 0
                dupeFMID        = 0
                dupeFirstName   = ""
                dupeLastName    = ""
                dupeDateOfBirth = ?
                dupeGender      = "".

            /* IF SAPERSON RECORD MATCHES ORIGINAL FIRST NAME, LAST NAME, AND BIRTHDAY, SET AS DUPLICATE FM AND MERGE INTO ORIGINAL */
            for first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID and bufMember.FirstName = origFirstName and bufMember.LastName = origLastName and bufMember.Birthday = origDateOfBirth:
                assign
                    dupeOrderNum    = bufRelationship.Order
                    dupeFMID        = bufMember.ID
                    dupeFirstName   = bufMember.FirstName
                    dupeLastName    = bufMember.LastName
                    dupeDateOfBirth = bufMember.Birthday
                    dupeGender      = bufMember.Gender.
            end. 

            if dupeOrderNum > 0 then run mergeFM.
        
        end. // DUPLICATE FM LOOP
    end. // SALINK LOOP
end. // HOUSEHOLD LOOP

run ActivityLog("Merged duplicate family members within the same HH").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* SET SALINK ORDER */
procedure SetSALink:
  
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

/* SEND FAMILY MEMBERS TO HH TRANSFER MERGE PROGRAM */
procedure mergeFM:
    
    numRecs = numRecs + 1. 
    
    setData("HouseholdMerge_FromHousehold",string(mergeHHnum)). 
    setData("HouseholdMerge_ToHousehold",string(mergeHHnum)).  
    setdata("SubAction","Start").
    run Business/HouseholdMerge.p.

    setdata("SubAction","FetchTempFamilyFromRecords").
    run Business/HouseholdMerge.p. 
    
    setdata("SubAction","FetchTempFamilyToRecords").
    run Business/HouseholdMerge.p.

    setData("FieldList","number,firstname,lastname,birthday,gender,mergeoptionfamily"). 
    setData("FieldName","FamilyMemberMerge_FamilyFromGrid").
    setData("LinkRecordID",string(dupeOrderNum)).
    setData("number",string(dupeOrderNum)).
    setData("firstname",string(origFirstName)).
    setData("lastname",string(origLastName)).
    setData("birthday",string(origDateOfBirth)).
    setData("gender",string(origGender)).  
    setData("mergeoptionfamily",string(substitute("Merge with &1 (#&2) in the To Household",string(origFirstName + " " + origLastName),string(origOrderNum)))).
    setData("number_previous",string(dupeOrderNum)).
    setData("firstname_previoius",string(dupeFirstName)).
    setData("lastname_previous",string(dupeLastName)).
    setData("birthday_previous",string(dupeDateOfBirth)).
    setData("gender_previous",string(dupeGender)).  
    setData("mergeoptionfamily_previous","Do Not Transfer/Merge").
    
    setdata("SubAction","StoreInContextInlineFamily").
    run Business/HouseholdMerge.p. 
    
    setdata("SubAction","Continue").
    run Business/HouseholdMerge.p.
   
    setdata("SubAction","Continue2").
    run Business/HouseholdMerge.p.

end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY SADETAIL RECORDS WERE CHANGED */
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