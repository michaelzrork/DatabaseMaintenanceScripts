/*------------------------------------------------------------------------
    File        : mergeGuestHouseholdFamilyMembers.p
    Purpose     : Merge duplicate FM within the same HH

    Syntax      : 

    Description : 

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

define buffer bufToAccount   for Account.
define buffer bufFromAccount for Account. 
    
assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// ASSIGN NEW VALUES
mergeHHnum      = 999999999.

// FIND HOUSEHOLD ID
for first Account no-lock where Account.EntityNumber = mergeHHnum:
    assign 
        hhID = Account.ID.
    for first Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.Primary = false and Relationship.RecordType = "Household":
        assign
            dupeFMID = Relationship.ChildTableID.
        find first Member no-lock where Member.ID = dupeFMID no-error no-wait.
        if not available Member then 
        do:
            run ActivityLog("Dupe Member Record Not Available").
            return.
        end.
        assign
            dupeFirstName   = Member.FirstName
            dupeLastName    = Member.LastName
            dupeDateOfBirth = Member.Birthday
            dupeGender      = Member.Gender.
    end.
    for first Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.Primary = true and Relationship.RecordType = "Household":
        assign
            origFMID     = Relationship.ChildTableID
            origOrderNum = Relationship.Order.    
        find first Member no-lock where Member.ID = origFMID no-error no-wait.
        if not available Member then 
        do:
            run ActivityLog("Original Member Record Not Available").
            return.
        end.
        if available Member then assign
                origFMID        = Member.ID
                origFirstName   = Member.FirstName
                origLastName    = Member.LastName
                origDateOfBirth = Member.Birthday
                origGender      = Member.Gender.
    end.
end.

for each Relationship no-lock where Relationship.ParentTableID = hhID and Relationship.RecordType = "Household" by Relationship.Order:
    assign 
        ix = ix + 1.
    if ix ne SaLink.Order then
        run SetRelationship(SaLink.id, Relationship.Primary, ix, Relationship.Relationship).   
end.

// FIND DUPE PERSON ORDER NUMBER
for first Relationship no-lock where Relationship.ChildTableID = dupeFMID and Relationship.ParentTableID = hhID and Relationship.RecordType = "Household" and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
    dupeOrderNum = Relationship.Order.
end.

if origFMID = dupeFMID then 
do:
    run ActivityLog("Dupe and Original FM have same SAperson.ID").
    return.
end. 

run mergeFM.
// CHECK FOR TERTIARY MEMBERS
for each Relationship no-lock where Relationship.ChildTableID <> origFMID and Relationship.ParentTableID = hhID and Relationship.RecordType = "Household" and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member" by Relationship.Order:
    run checkForAdditionalFMs(Relationship.ID).
    if dupeOrderNum > 0 then run mergeFM.
end.

run ActivityLog("Merged duplicate family members within the same HH").

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



// CHECK FOR ADDITIONAL MEMBERS
procedure checkForAdditionalFMs:
    define input parameter inpID as int64 no-undo.
    define buffer bufRelationship   for Relationship.
    define buffer bufMember for Member.
    assign
        dupeOrderNum    = 0
        dupeFMID        = 0
        dupeFirstName   = ""
        dupeLastName    = ""
        dupeDateOfBirth = ?
        dupeGender      = "".
    find first bufRelationship no-lock where bufRelationship.ID = inpID no-error no-wait.
    if not available bufRelationship then return.
    for first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID and bufMember.FirstName = origFirstName and bufMember.LastName = origLastName and bufMember.Birthday = origDateOfBirth:
        assign
            dupeOrderNum    = bufRelationship.Order
            dupeFMID        = bufMember.ID
            dupeFirstName   = bufMember.FirstName
            dupeLastName    = bufMember.LastName
            dupeDateOfBirth = bufMember.Birthday
            dupeGender      = bufMember.Gender.
    end. 
end procedure.

// SEND FAMILY MEMBERS TO HH TRANSFER MERGE PROGRAM
procedure mergeFM:
    
    numRecs = numRecs + 1. 
    
    setData("HouseholdMerge_FromHousehold",string(mergeHHnum)). 
    setData("HouseholdMerge_ToHousehold",string(mergeHHnum)).  
    setdata("SubAction","Start").
    run HouseholdMerge.

    setdata("SubAction","FetchTempFamilyFromRecords").
    run HouseholdMerge. 
    
    setdata("SubAction","FetchTempFamilyToRecords").
    run HouseholdMerge.

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
    run HouseholdMerge. 
    
    setdata("SubAction","Continue").
    run HouseholdMerge.
   
    setdata("SubAction","Continue2").
    run HouseholdMerge.

end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY TRANSACTIONDETAIL RECORDS WERE CHANGED
procedure ActivityLog:
    define input parameter logDetail as character no-undo.
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "mergeGuestHouseholdFamilyMembers.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = logDetail
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.




procedure HouseholdMerge:

    /************************************************************************/
    /*  HouseholdMerge.p ------ RECTRAC SYSTEM                              */
    /*                          HOUSEHOLD MERGE (SINGLE HH) - BL            */
    /*          AUTHOR -------- ANDREW BOSE                                 */
    /*                          VERMONT SYSTEMS, INC.                       */
    /************************************************************************/
    /* ***************************  Definitions  ************************** */
     
  
         
    assign 
        SessionID       = SessionID()
        SubsessionID    = SubsessionID() 
        SubAction       = GetData({&SubAction})    
        FromHHNumber    = mergeHHnum
        ToHHNumber      = mergeHHnum
        ChangeStaffInfo = logical(GetData("HouseholdMerge_ChangeStaffInfo"))  
        DateFormat      = GetDataTrue({&DateFormat})
        TimeFormat      = GetDataTrue({&TimeFormat})
        ContinueError   = ""
        ModuleList      = {&FullModuleList}.
 
/*** GO THRU DAILY PROCESSING PROFILES AND GET INTERNAL & MODEL HOUSEHOLDS ***/
PROFILE-LOOP:
for each EntityProfile no-lock where 
    EntityProfile.RecordType = "Daily Processing":
  
    InternalHH = ProfileCharTrueDb(EntityProfile.ID, "InternalHousehold").
  
    if InternalHH > "" then
        InternalHHList = UniqueList(InternalHH,InternalHHList,",").
  
    /*** GET MODEL HOUSEHOLD LIST ***/
    do ix = 1 to num-entries(ModuleList):
    
        ModelHHModuleList = ProfileCharTrueDb(EntityProfile.ID, "ModelHousehold" + entry(ix,ModuleList)).
    
        if ModelHHModuleList > "" then
        do iy = 1 to num-entries(ModelHHModuleList):
            ModelHHList = UniqueList(entry(iy,ModelHHModuleList), ModelHHList, ",").  
        end.
    end.
end. /* END PROFILE-LOOP */

  

for first Account no-lock where Account.EntityNumber = ToHHNumber:
    mergeoption = "merge".
end.

run value(SubAction). 

if continueerror gt "" then 
do:
    SetData("ContinueError","ContinueError").
        SetData({&UIErrorMessage},continueerror ).
    return.
end.  

end procedure.

/* **********************  Internal Procedures  *********************** */

procedure adjustRelationships:
    /*------------------------------------------------------------------------------
     Purpose:
     Notes:
    ------------------------------------------------------------------------------*/
    define input parameter householdNo as int no-undo.
    define variable ix as integer no-undo.

    for first Account no-lock 
        where Account.EntityNumber = householdNo:
              
        for each Relationship no-lock 
            where Relationship.ParentTableID = Account.ID and
            Relationship.RecordType = "Household" by Relationship.Order:
            assign 
                ix = ix + 1.
            if ix ne SaLink.Order then
                run SetRelationship(SaLink.id, Relationship.Primary, ix, Relationship.Relationship).   
        end.
        ix = 0.            
        for each Relationship no-lock 
            where Relationship.ParentTableID = Account.ID and
            Relationship.RecordType = "Team" by Relationship.Order:
            assign 
                ix = ix + 1.
            if ix ne SaLink.Order then
                run SetRelationship(SaLink.id, Relationship.Primary, ix, Relationship.Relationship).   
        end. 
    end.  


end procedure.

procedure getNewLinkForFamily:
    /*------------------------------------------------------------------------------
     Purpose: It will retrive the newLink(SaLink.Order) 
     Notes: The order will be the one after the person is moved/merge with the other household
    ------------------------------------------------------------------------------*/
    define output parameter newLink as integer no-undo.
  
    if ttFamilyFrom.mergeoptionfamily begins "merge" then 
    do:
        run extractNumber(ttFamilyFrom.mergeoptionfamily, output newLink).
    end.  
    else
        for first ttFamilyToPreMerge where 
            ttFamilyToPreMerge.personid eq ttFamilyFrom.personid:
            newLink = ttFamilyToPreMerge.number.  
        end. 

end procedure.

procedure getNewLinkForTeam:
    /*------------------------------------------------------------------------------
     Purpose: It will retrive the newLink(SaLink.Order) 
     Notes: The order will be the one after the team is moved/merge with the other household
    ------------------------------------------------------------------------------*/
    define output parameter  newLink as integer no-undo.
  
    if ttTeamFrom.mergeoptionteam begins "merge" then 
    do:
        run extractNumber(ttTeamFrom.mergeoptionteam, output newLink).
    end.  
    else
        for first ttTeamToPreMerge where
            ttTeamToPreMerge.teamid eq ttTeamFrom.teamid:
            newLink = ttTeamToPreMerge.number.  
        end. 
     
end procedure.

procedure createPreMerge:
    /*------------------------------------------------------------------------------
     Purpose: It will create the pre Merge Transaction Detail records
     Notes:
    ------------------------------------------------------------------------------*/
    define input parameter originalId as int64 no-undo.
    define input parameter mergeOption as char no-undo. 
    define input parameter newID as int64 no-undo.
    define input parameter nameDescription as char no-undo.

    for each TransactionDetail no-lock where 
        TransactionDetail.EntityNumber = mergeHHnum and
        TransactionDetail.PatronLinkID = originalId and
        TransactionDetail.CartStatus = "Complete" and 
        TransactionDetail.Complete:
         
        if lookup(TransactionDetail.RecordStatus,"denied,cancelled,return") gt 0 then 
            next.  
        assign 
            good-hist = yes.
       
        if mergeOption eq "Merge" and lookup(TransactionDetail.Module,"AR,LS") ne 0
            and not TransactionDetail.Archived and newID <> originalId then 
        do:
            conflictcount = 0.
            run findconflict (TransactionDetail.id, newID). 
        
            if conflictcount gt 0 then 
                good-hist = no.
        end.
     
        create ttPreMerge.
        assign
            ttPreMerge.mergedesc = (if not good-hist then "CONFLICT:  " else 
                            if TransactionDetail.Archived then "ARCHIVED: " else "") + TransactionDetail.Description +
                            "  Status: " + TRANSACTIONDETAIL.RecordStatus + 
                            " (" + nameDescription + 
                            ") (From House: " + string(FromHHNumber) + " To House: " + string(ToHHnumber) + ")" 
            ttPreMerge.conflict  = if not good-hist then yes else no.
    end.

end procedure.

procedure extractNumber:
    /*------------------------------------------------------------------------------
     Purpose: It will extract the number from the option label
     Notes: The option label is of this type "Merge with <name> (#<number>) in the To Household"
    ------------------------------------------------------------------------------*/
    define input parameter stringValue as char no-undo.
    define output parameter number as int no-undo.

    stringValue = replace(stringValue,") in the To Household",'').
    number =  int(entry(num-entries(stringValue,"#"),stringValue,"#")) no-error.


end procedure.

procedure getMergeOptionForTeam:
    /*------------------------------------------------------------------------------
     Purpose: Set up default values for merge option
     Notes: If a team with the same name is found in the To Household, 
            then select merge with it by default
            Else select "Do not Transfer/Merge"
    ------------------------------------------------------------------------------*/    
    
    define input parameter teamname as char no-undo.
    define output parameter mergeValue as char init "Do Not Transfer/Merge".
  
    if ToHHNumber eq FromHHNumber then 
    do:
        mergeValue = "Do Not Transfer/Merge". 
        return.      
    end.
    for first ttTeamTo where ttTeamTo.teamname eq teamname:
        mergeValue = substitute("Merge with &1 (#&2) in the To Household",string(teamname),string(ttTeamTo.Number)).
    end.
end procedure.

procedure getMergeOptionForFamily:
    /*------------------------------------------------------------------------------
     Purpose: Set up default values for merge option
     Notes: If a person with the same name and birthday is found in the To Household, 
            then select merge with it by default
            else if is the primary one select "Do not Transfer/Merge"
            else select "Transfer Member into the To Household"
    ------------------------------------------------------------------------------*/       
    
    define output parameter mergeValue as char init "Do Not Transfer/Merge".
  
    if ToHHNumber eq FromHHNumber then
        return.      
  
    for first ttFamilyTo where 
        ttFamilyTo.firstname eq Member.FirstName and
        ttFamilyTo.lastname eq Member.LastName and
        ttFamilyTo.birthday eq string(Member.Birthday,"99/99/9999"):
        mergeValue = substitute("Merge with &1 (#&2) in the To Household",string(ttFamilyTo.FirstName + " " + ttFamilyTo.LastName),string(ttFamilyTo.Number)).
        return.
    end.
  
end procedure.

procedure makeNextAvailablePersonPrimary:
    /*------------------------------------------------------------------------------
     Purpose:
     Notes:
    ------------------------------------------------------------------------------*/
    define buffer bufSaLink         for SaLink.
    define buffer BufAccount    for SaHousehold.
    define buffer BufEmailAddress for EmailContact.
    define buffer BufPhone        for PhoneNumber.
    define buffer BufMember       for SaPerson.
    define variable primaryRelationship as char no-undo.

    primaryRelationship = ProfileCharTrue("Static Parameters","PrimeGuardSponsorCode").

    for each ttFamilyFromPreMerge by ttFamilyFromPreMerge.number:
        for first bufSaLink no-lock where 
            bufSaLink.ChildTableID = ttFamilyFromPreMerge.personid and
            bufSaLink.ChildTable = "Member" and
            bufSaLink.ParentTableID = FromHHID and
            bufSaLink.ParentTable = "Account" and           
            bufSaLink.Order = ttFamilyFromPreMerge.number:
            run SetRelationship(bufSaLink.id, yes, bufSaLink.Order, primaryRelationship).               
        end. 
        leave.    
    end.
    if not available ttFamilyFromPreMerge then return.

    do for BufAccount,BufEmailAddress,BufPhone transaction:
        find BufAccount exclusive-lock where BufAccount.id = FromHHID no-error no-wait.
        find BufMember no-lock where BufMember.id = ttFamilyFromPreMerge.personid no-error no-wait.
        if not available BufAccount or not available BufMember then return.
        assign
            BufAccount.firstname             = BufMember.firstname
            BufAccount.lastname              = BufMember.lastname
            BufAccount.primaryemailaddress   = BufMember.primaryemailaddress
            BufAccount.PrimaryPhoneNumber    = BufMember.PrimaryPhoneNumber
            BufAccount.PrimaryPhoneType      = BufMember.PrimaryPhoneType
            BufAccount.PrimaryPhoneExtension = BufMember.PrimaryPhoneExtension.
        if BufMember.primaryemailaddress gt "" then 
        do: 
            for first EmailContact no-lock where EmailContact.ParentRecord = FromHHID and
                EmailContact.PrimaryEmailAddress = yes:
                run updateSAPrimaryEmailAddress(EmailContact.id,BufAccount.primaryemailaddress, BufMember.id).
            end.
            if not available EmailContact then 
            do:
                create BufEmailAddress.
                assign
                    BufEmailAddress.emailaddress        = BufMember.primaryemailaddress
                    bufsaemailaddress.ParentRecord            = FromHHID
                    bufsaemailaddress.ParentTable         = "Account"
                    bufsaemailaddress.MemberLinkID      = BufMember.id
                    bufsaemailaddress.PrimaryEmailAddress = yes.
            end. 
        end.
        else 
            for first EmailContact no-lock where EmailContact.ParentRecord = FromHHID and
                EmailContact.PrimaryEmailAddress = yes:
                run purgeEmailContact(EmailContact.id).
            end.
        if BufMember.PrimaryPhoneNumber gt "" then 
        do:
            for first SaPhone no-lock where SaPhone.ParentRecord = FromHHID and
                PhoneNumber.PrimaryPhoneNumber = yes:
                run updatesaphoneprimary(PhoneNumber.id, BufMember.PrimaryPhoneNumber, BufMember.id,BufSaPerson.primaryphonetype,BufMember.primaryphoneextension).
            end.
            if not available SaPhone then 
            do:
                create BufPhone.
                assign
                    BufPhone.phonenumber        = BufMember.primaryphonenumber
                    BufPhone.phonetype          = BufMember.primaryphonetype
                    BufPhone.extension          = BufMember.primaryphoneextension
                    bufPhoneNumber.ParentRecord           = FromHHID
                    bufPhoneNumber.ParentTable        = "Account"
                    bufPhoneNumber.MemberLinkID     = BufMember.id
                    bufPhoneNumber.Primaryphonenumber = yes.
            end. 
        end.
        else 
            for first SaPhone no-lock where SaPhone.ParentRecord = FromHHID and
                PhoneNumber.PrimaryPhoneNumber = yes:
                run purgesaphone(SaPhone.id).
            end.      
    end. 
end procedure.

procedure Start: 
         
    if mergeoption ne "transfer" then 
    do:
        if GetDataTrue("GoBack") ne "yes" then 
        do:
            empty temp-table ttPreMerge.
            empty temp-table ttFamilyFrom.
            empty temp-table ttTeamFrom. 
            empty temp-table ttTeamTo.
            empty temp-table ttFamilyTo.   

            SetData("MergeOption", MergeOption).  
            SetData("HouseholdMerge_FromHHNumber", string(FromHHNumber)).
            SetData("HouseholdMerge_ToHHNumber", string(ToHHNumber)).
            SetData("HouseholdMerge_ChangeStaffInfo", string(ChangeStaffInfo)).
      
            run adjustSaLinks(FromHHNumber).
            run adjustSaLinks(ToHHNumber).
            run CreateToRecords (ToHHNumber).  
            run CreateFromRecords (FromHHNumber).    
            if FromHHNumber eq ToHHNumber then
                SetData("SameHousehold","yes").
            else
                RemoveData("SameHousehold").    
            if not can-find(first ttTeamFrom) then  
                SetData("DoNotShowTeams","yes").  
            else RemoveData("DoNotShowTeams").
 
            if not can-find(first ttFamilyFrom no-lock) then 
            do:
                SetData({&UIErrorMessage},"You need to have at least one member in the 'From' household").
                return.
            end.   
            run StoreInContext.
        end.
        RemoveData("GoBack").  
        SetData({&ScreenName},"FamilyMemberMerge").
    end.
    else 
    do:
        if GetDataTrue("ContinueTransfer") ne "yes" then 
        do:
            run Business/Dialog.p ("FileMaintenanceContinue", "Maintenance",
                substitute("Transfer Household #&1 to Household #&2. Are you sure you want to continue?",FromHHNumber,ToHHNumber),
                "ButtonContinue,ButtonCancel").
            CreateParam2(3, "FileMaintenanceContinue_ButtonContinue", "Click.Data", "Routine=Processing&Action=HouseholdMerge&SubAction=Start&ContinueTransfer=yes").
            CreateParam2(3, "FileMaintenanceContinue_ButtonContinue", "Click.Close", "Continue").
            SetData({&UIOperation}, "Dialog").
            return.
        end.  
        else 
        do:
            RemoveData("ContinueTransfer").
            run process4.
        end.  
    end.

end procedure. /* START END */

procedure Continue:
    define variable ProcessRunning as log     no-undo.
    define variable number         as integer no-undo.
    define variable number2        as integer no-undo.
  
    define buffer DupeMerge        for ttFamilyFrom.
    define buffer bufTTFamilyFrom  for ttFamilyFrom.
    define buffer bufTTTeamFrom    for ttTeamFrom.
    define buffer buf2TTFamilyFrom for ttFamilyFrom.
    define buffer buf2TTTeamFrom   for ttTeamFrom.
  
    ProcessRunning = no.
  
    for first ProgramSchedule no-lock where 
        ProgramSchedule.RecordStatus  = "Running"
        and ProgramSchedule.ProgramToRun = "Business/InstallmentBilling.p": 
        ContinueError = "Installment Billing is currently running. Try again later.".
        ProcessRunning = yes. 
    end.
    if ProcessRunning then return.
  
    for first ProgramSchedule no-lock where 
        ProgramSchedule.RecordStatus  = "Running"
        and ProgramSchedule.ProgramToRun = "Business/AutoMemberShipRenewal.p": 
        ContinueError = "Membership Auto Renewal is currently running. Try again later.".
        ProcessRunning = yes.
    end.
    if ProcessRunning then return.
  
    for first ProgramSchedule no-lock where 
        ProgramSchedule.RecordStatus  = "Running"
        and ProgramSchedule.ProgramToRun = "Business/HouseholdBalanceAutoPay.p": 
        ContinueError = "Household Balance Auto Pay is currently running. Try again later.".
        ProcessRunning = yes.
    end.
    if ProcessRunning then return.
  
    ContinueError = "".
    run GetFromContext. 
  
    if mergeOption = "merge" and FromHHNumber ne ToHHNumber then 
    do:
        for each ttFamilyFrom where ttFamilyFrom.mergeoptionfamily ne "Do not Transfer/Merge":    
            find first ttFamilyTo where ttFamilyTo.personId = ttFamilyFrom.personId no-error.
            if available ttFamilyTo then 
            do:
                number = 0.    
                if ttFamilyFrom.mergeoptionfamily begins "merge" then
                    run extractNumber(ttFamilyFrom.mergeoptionfamily, output number).
                if number = 0 or number ne ttFamilyTo.number then     
                    ContinueError = ttFamilyFrom.firstname + " " + ttFamilyFrom.lastname + 
                        " is in both the 'from' and the 'to' household but is being merged into a different person. This is not allowed.".
            end.    
        end. 
    end.
  
    if continueerror gt "" then 
    do:
        run StoreInContext.
        return.
    end.
  
    if mergeOption = "merge" and FromHHNumber eq ToHHNumber then 
    do:
        for each ttFamilyFrom where ttFamilyFrom.mergeoptionfamily ne "Do not Transfer/Merge": 
            run extractNumber(ttFamilyFrom.mergeoptionfamily, output number).
            if number eq ttFamilyFrom.number then next.
            for each bufTTFamilyFrom where 
                bufTTFamilyFrom.mergeoptionfamily ne "Do not Transfer/Merge" and
                bufTTFamilyFrom.number eq number:
                run extractNumber(bufTTFamilyFrom.mergeoptionfamily, output number2).
                if number2 ne bufTTFamilyFrom.number then 
                do:
                    for first buf2TTFamilyFrom no-lock where buf2TTFamilyFrom.number eq number2:  
                        ContinueError = "Family member merge conflict! Unable to merge " + ttFamilyFrom.firstname + " " + ttFamilyFrom.lastname + 
                            " with " + bufTTFamilyFrom.firstname + " " + bufTTFamilyFrom.lastname + " because " + bufTTFamilyFrom.firstname + " " + bufTTFamilyFrom.lastname +
                            " has already been set to merge with " + buf2TTFamilyFrom.firstname + " " + buf2TTFamilyFrom.lastname + ". Please adjust your merge settings and try again.".
                        run StoreInContext.
                        return.
                    end.    
                end.         
            end.
        end.
    
        for each ttTeamFrom where ttTeamFrom.mergeoptionteam ne "Do not Transfer/Merge": 
            run extractNumber(ttTeamFrom.mergeoptionteam, output number).
            if number eq ttTeamFrom.number then next.
            for each bufTTTeamFrom where 
                bufTTTeamFrom.mergeoptionteam ne "Do not Transfer/Merge" and
                bufTTTeamFrom.number eq number:
                run extractNumber(bufTTTeamFrom.mergeoptionteam, output number2).
                if number2 ne bufTTTeamFrom.number then 
                do:
                    for first buf2TTTeamFrom no-lock where buf2TTTeamFrom.number eq number2:  
                        ContinueError = "Team merge conflict! Unable to merge " + ttTeamFrom.teamname +
                            " with " + bufttTeamFrom.teamname + " because " + bufttTeamFrom.teamname  +
                            " has already been set to merge with " + buf2ttTeamFrom.teamname +  ". Please adjust your merge settings and try again.".
                        run StoreInContext.
                        return.   
                    end.     
                end.         
            end.
        end.        
    end.
  
    run process3.
  
end procedure. /* CONTINUE END */

procedure Continue2:

    run GetFromContext.
    run GetFromContext2.
  
    if mergeoption ne "transfer" then
        if can-find(first ttFamilyFromPreMerge) or FromHHNumber eq ToHHNumber then
            mergeoption = "partialmerge".
        else
            mergeoption = "fullmerge".
      
  
    /* one final check before we start merging.  We need to verify that if we are merging contracts */
    /* that we only merge if ALL the people tied to the contract are being merged.  If not then  */
    /* we need to stop the process now. */
  
    for each Agreement no-lock where Agreement.EntityNumber = FromHHNumber:
        if MergeOption = "partialmerge" then 
        do:
            for each TransactionDetail no-lock where TransactionDetail.ContractID = Agreement.ID:
                find first Member no-lock where Member.ID = TransactionDetail.PatronLinkID no-error.
                find first ttFamilyFrom where ttFamilyFrom.mergeoptionfamily ne "Do not Transfer/Merge" and ttFamilyFrom.personid = Member.ID no-error.
                if available ttFamilyFrom then 
                do:
                    SetData("Contracterror","Contracterror").
                    SetData({&UIErrorMessage}, Member.FirstName + " " + Member.LastName + " is linked to a contract for the household they currently are linked to and cannot be moved." ).
                    return.
                end.
            end.
        end.
    end. /*  FOR EACH END  */ 

    run process4.

end procedure. /* CONTINUE2 END */

procedure StoreInContextInlineTeam:
  
    run SaveHandleToContextInline("ChangeDataTeamFrom", "ttTeamFrom", temp-table ttTeamFrom:handle).  
       
end procedure.  /* STOREINCONTEXTINLINE END */

procedure StoreInContextInlineFamily:
  
    run SaveHandleToContextInline("ChangeDataFamilyFrom", "ttFamilyFrom", temp-table ttFamilyFrom:handle). 
       
end procedure.  /* STOREINCONTEXTINLINE END */

procedure SaveHandleToContextInline:
    define input parameter StoreFieldName as char no-undo.
    define input parameter ttTable as char no-undo.
    define input parameter ttHandle as handle no-undo.
 
    def var ix           as int    no-undo.
    def var FieldList    as char   no-undo.
    def var FieldName    as char   no-undo.  
    def var OldValue     as char   no-undo.
    def var NewValue     as char   no-undo.
    def var LinkRecordID as char   no-undo.
    def var TempBuffer   as handle no-undo.
    def var fnd          as log    no-undo. 

    if isEmpty(StoreFieldName) or isEmpty(ttTable) then return "error".

    GetDataTable(StoreFieldName, ttHandle). 
      
    assign
        FieldList    = GetDataTrue({&FieldList})
        LinkRecordID = GetDataTrue({&LinkRecordID}).
    
    RemoveData({&FieldName}).
    RemoveData({&FieldList}).  
  
    continueerror = "".  

    create buffer TempBuffer for table ttTable.  
    fnd = TempBuffer:find-first("where " + ttTable + ".DT_Rowid = '" + LinkRecordID + "'", no-lock).
    if not fnd then return "error".
  
    /* LOOP THROUGH THE FIELDS BEING SAVED */
    do ix = 1 to num-entries(FieldList):
        assign
            FieldName = entry(ix,FieldList)
            OldValue  = GetData(FieldName + "_previous")
            NewValue  = GetData(FieldName).
       
        if OldValue ne NewValue and NewValue ne ? then assign 
                TempBuffer:buffer-field(FieldName):buffer-value = NewValue.  
    end. /* LOOP THROUGH FIELD LIST END */ 
  
    delete object TempBuffer.  
    SetDataTable(StoreFieldName, ttHandle).
    return "".
  
end procedure.

procedure StoreInContext:
    
    SetDataTable("ChangeDataFamilyFrom", temp-table ttFamilyFrom:handle).
    SetDataTable("ChangeDataTeamFrom", temp-table ttTeamFrom:handle).
    SetDataTable("ChangeDataFamilyTo", temp-table ttFamilyTo:handle).
    SetDataTable("ChangeDataTeamTo", temp-table ttTeamTo:handle).
       
end procedure.

procedure StoreInContext2:
  
    SetDataTable("ChangeData2", temp-table ttPreMerge:handle).  
    SetDataTable("ChangeDataFamilyFromPreMerge", temp-table ttFamilyFromPreMerge:handle).
    SetDataTable("ChangeDataTeamFromPreMerge", temp-table ttTeamFromPreMerge:handle).
    SetDataTable("ChangeDataFamilyToPreMerge", temp-table ttFamilyToPreMerge:handle).
    SetDataTable("ChangeDataTeamToPreMerge", temp-table ttTeamToPreMerge:handle).     
end procedure.

procedure GetFromContext:  

    GetDataTable("ChangeDataFamilyFrom", temp-table ttFamilyFrom:handle).
    GetDataTable("ChangeDataTeamFrom", temp-table ttTeamFrom:handle).
    GetDataTable("ChangeDataFamilyTo", temp-table ttFamilyTo:handle).
    GetDataTable("ChangeDataTeamTo", temp-table ttTeamTo:handle).
          
end procedure.  /* GETFROMCONTEXT END */

procedure GetFromContext2:

    GetDataTable("ChangeDataFamilyFromPreMerge", temp-table ttFamilyFromPreMerge:handle).
    GetDataTable("ChangeDataFamilyToPreMerge", temp-table ttFamilyToPreMerge:handle).
    GetDataTable("ChangeDataTeamToPreMerge", temp-table ttTeamToPreMerge:handle).
    GetDataTable("ChangeDataTeamFromPreMerge", temp-table ttTeamFromPreMerge:handle).
     
end procedure.  /* GETFROMCONTEXT2 END */

procedure FetchRecords:
  
    define input parameter contextName as char. 
    define input parameter ttSource as handle. 
  
    define variable ttGridHandle as handle  no-undo.
    define variable Continue     as logical no-undo.
  
    ttGridHandle = SetDataHandle({&TTFetch}, "temp-table").
    Continue = GetDataTable(contextName, ttSource).
  
    if Continue then 
        ttGridHandle:copy-temp-table(ttSource). 

end procedure.

procedure FetchTempTeamToRecords:
    run FetchRecords("ChangeDataTeamTo",temp-table ttTeamTo:handle).
end procedure.

procedure FetchTempRecords2:
    run FetchRecords("ChangeData2",temp-table ttPreMerge:handle).
end procedure.

procedure FetchTempFamilyFromRecords:
    run FetchRecords("ChangeDataFamilyFrom",temp-table ttFamilyFrom:handle). 
end procedure.

procedure FetchTempFamilyToRecords:
    run FetchRecords("ChangeDataFamilyTo",temp-table ttFamilyTo:handle).
end procedure.

procedure FetchTempTeamFromRecords:
    run FetchRecords("ChangeDataTeamFrom",temp-table ttTeamFrom:handle).
end procedure.

procedure FetchTempFamilyFromPreMergeRecords:
    run FetchRecords("ChangeDataFamilyFromPreMerge",temp-table ttFamilyFromPreMerge:handle). 
end procedure.

procedure FetchTempFamilyToPreMergeRecords:
    run FetchRecords("ChangeDataFamilyToPreMerge",temp-table ttFamilyToPreMerge:handle).
end procedure.

procedure FetchTempTeamFromPreMergeRecords:
    run FetchRecords("ChangeDataTeamFromPreMerge",temp-table ttTeamFromPreMerge:handle).
end procedure.

procedure FetchTempTeamToPreMergeRecords:
    run FetchRecords("ChangeDataTeamToPreMerge",temp-table ttTeamToPreMerge:handle).
end procedure.

procedure CreateFromRecords:

    define input parameter HHNumber as integer no-undo.
    define variable ix         as integer   no-undo.
    define variable iy         as integer   no-undo.
    define variable mergeValue as character no-undo.
  
    for first Account no-lock 
        where Account.EntityNumber = HHNumber:
    
        for each Relationship no-lock 
            where Relationship.ParentTableID = Account.ID by Relationship.Order: 
            if Relationship.RecordType = "Household" then 
                for each Member no-lock where Member.ID = Relationship.ChildTableID:
                    run getMergeOptionForFamily(output mergeValue).    
                    create ttFamilyFrom. 
                    assign
                        ix                             = ix + 1
                        ttFamilyFrom.personid          = Member.ID        
                        ttFamilyFrom.firstname         = Member.FirstName
                        ttFamilyFrom.lastname          = Member.LastName
                        ttFamilyFrom.birthday          = string(Member.Birthday,"99/99/9999")
                        ttFamilyFrom.gender            = Member.Gender    
                        ttFamilyFrom.mergeoptionfamily = mergeValue
                        ttFamilyFrom.DT_Rowid          = string(ix)
                        ttFamilyFrom.number            = Relationship.Order
                        ttFamilyFrom.isPrimary         = SaLink.Primary.          
                end.
            else 
                if Relationship.RecordType = "Team" then 
                    for each LSTeam no-lock where LSTeam.ID = Relationship.ChildTableID:
                        run getMergeOptionForTeam(input LSTeam.TeamName, output mergeValue). 
                        create ttTeamFrom. 
                        assign
                            iy                         = iy + 1     
                            ttTeamFrom.teamname        = LSTeam.TeamName
                            ttTeamFrom.teamid          = LSTeam.id
                            ttTeamFrom.mergeoptionteam = mergeValue
                            ttTeamFrom.DT_Rowid        = string(iy)
                            ttTeamFrom.number          = Relationship.Order.          
                    end.  
        end.        
    end.

end procedure.

procedure CreateToRecords:

    define input parameter HHNumber as integer no-undo.

    for first Account no-lock 
        where Account.EntityNumber = HHNumber: 
    
        for each Relationship no-lock where Relationship.ParentTableID = Account.ID by salink.order:     
            if Relationship.RecordType = "Household" then
                for each Member no-lock where Member.ID = Relationship.ChildTableID: 
                    create ttFamilyTo. 
                    assign
                        ttFamilyTo.firstname = Member.FirstName
                        ttFamilyTo.lastname  = Member.LastName
                        ttFamilyTo.birthday  = string(Member.Birthday,"99/99/9999")
                        ttFamilyTo.gender    = Member.Gender
                        ttFamilyTo.personid  = Member.ID
                        ttFamilyTo.number    = salink.order.
                end.    
            else 
                if Relationship.RecordType = "Team" then 
                    for each LSTeam no-lock where LSTeam.ID = Relationship.ChildTableID: 
                        create ttTeamTo. 
                        assign
                            ttTeamTo.teamname = LSTeam.TeamName
                            ttTeamTo.teamid   = LSTeam.ID
                            ttTeamTo.number   = salink.order.        
                    end.  
        end.
    end.
end procedure.

procedure process3:

    assign 
        ConflictCount = 0.
  
    run pre-merge.
  
end procedure. /* PROCESS3 END */

procedure process4:

    run ProcessMerge.

    if ConflictCount gt 0 then 
        SetData({&UISuccessMessage},
            string(ConflictCount) + " conflicts existed during " + (if MergeOption = "Fullmerge" then "the full merge"
            else if mergeoption = "transfer" then "the transfer" else "the partial merge") + "! " +
            "You should review the converted household's Activity enrollments for " + 
            "duplicate enrollment(s).").
    else SetData({&UISuccessMessage}, "Household " +
            if MergeOption = "transfer" then "Transfer Complete!"
            else if MergeOption = "partialmerge" then "Partial Merge Complete!"
            else "Full Merge Complete!").
    
    SetData({&ScreenName},"HouseholdMerge").  

end procedure. /* PROCESS4 END */

procedure pre-merge: 
    define variable TempID            as int64     no-undo.
    define variable TempName          as char      no-undo.
    define variable TempBufName       as char      no-undo.
    define variable number            as integer   no-undo.
    define variable transferEveryTeam as logical   no-undo.
    define variable nameDescription   as character no-undo.
    define variable mergeOption       as character no-undo.
  
    /* copy all data to pre merge for to temp-tables */
    for each ttFamilyTo:
        create ttFamilyToPreMerge.
        buffer-copy ttFamilyTo to ttFamilyToPreMerge.
    end.
    for each ttTeamTo:
        create ttTeamToPreMerge.
        buffer-copy ttTeamTo to ttTeamToPreMerge.
    end.
    if FromhhNumber ne ToHHNumber then 
    do:
        for each ttFamilyFrom where not (ttFamilyFrom.mergeoptionfamily begins "Merge") :
            if ttFamilyFrom.mergeoptionfamily eq "Do Not Transfer/Merge" then 
            do:
        
                create ttFamilyFromPreMerge. 
                buffer-copy ttFamilyFrom to ttFamilyFromPreMerge.   
            end.    
            else 
            do:
                for each ttFamilyToPreMerge by ttFamilyToPreMerge.number descending:
                    number = ttFamilyToPreMerge.number.
                    leave.    
                end.
                number = number + 1.
                create ttFamilyToPreMerge.
                buffer-copy ttFamilyFrom to ttFamilyToPreMerge.
                ttFamilyToPreMerge.number = number.
            end.
        end.
  
        if not can-find(first ttFamilyFromPreMerge) then
            transferEveryTeam = yes.
  
        number = 0.  
  
        for each ttTeamFrom where not ttTeamFrom.mergeoptionteam begins "Merge" :
            if not transferEveryTeam and ttTeamFrom.mergeoptionteam eq "Do Not Transfer/Merge" then 
            do:
        
                create ttTeamFromPreMerge. 
                buffer-copy ttTeamFrom to ttTeamFromPreMerge.   
            end.    
            else 
            do:
                for each ttTeamToPreMerge by ttTeamToPreMerge.number descending:
                    number = ttTeamToPreMerge.number.
                    leave.    
                end.
                number = number + 1.
                create ttTeamToPreMerge.
                buffer-copy ttTeamFrom to ttTeamToPreMerge.
                ttTeamToPreMerge.number = number.
            end.
        end.
    end.
    else 
        for each ttFamilyFrom:
            if ttFamilyFrom.mergeoptionfamily eq "Do Not Transfer/Merge" then 
            do:
                create ttFamilyFromPreMerge. 
                buffer-copy ttFamilyFrom to ttFamilyFromPreMerge.   
            end.    
            else 
            do:
                run extractNumber(ttFamilyFrom.mergeoptionfamily,output number).
                if number eq  ttFamilyFrom.number then 
                do:
                    create ttFamilyFromPreMerge. 
                    buffer-copy ttFamilyFrom to ttFamilyFromPreMerge.   
                end.     
            end.
        end.
    for each ttFamilyFrom where ttFamilyFrom.mergeoptionfamily ne "Do Not Transfer/Merge" :
        if ttFamilyFrom.mergeoptionfamily begins "Merge" then 
        do:  
            run extractNumber(ttFamilyFrom.mergeoptionfamily,output number).
            if FromHHNumber eq ToHHNumber then 
            do:
                if number eq ttFamilyFrom.number then next.
                else 
                    for first ttFamilyToPreMerge where ttFamilyToPreMerge.number eq ttFamilyFrom.number:
                        delete ttFamilyToPreMerge.
                    end.
            end.  
            for first ttFamilyTo where ttFamilyTo.number eq number:
                nameDescription = ttFamilyFrom.FirstName + " " + ttFamilyFrom.LastName + " - merged into " + ttFamilyTo.FirstName + " " + ttFamilyTo.LastName.  
                run createPreMerge(ttFamilyFrom.personId, "merge", ttFamilyTo.personid, nameDescription).
            end.  
        end. 
        else 
        do:
            nameDescription = ttFamilyFrom.FirstName + " " + ttFamilyFrom.LastName + " - to be moved into household ".  
            run createPreMerge(ttFamilyFrom.personId, "", ?, nameDescription).  
        end.    
    end.
  
    if not can-find(first ttFamilyFromPreMerge) then 
        mergeOption = "".
    else mergeOption = "Do Not Transfer/Merge".
  
    for each ttTeamFrom where ttTeamFrom.mergeoptionteam ne mergeOption :
        if ttTeamFrom.mergeoptionteam begins "Merge" then 
        do:    
            run extractNumber(ttTeamFrom.mergeoptionteam,output number).
            if FromHHNumber eq ToHHNumber then 
            do:
                if number eq ttTeamFrom.number then next.
                else 
                    for first ttTeamToPreMerge where ttTeamToPreMerge.number eq ttTeamFrom.number:
                        delete ttTeamToPreMerge.
                    end.
            end.    
            for first ttTeamTo where ttTeamTo.number eq number:
                nameDescription = ttTeamTo.TeamName + " - merged into " + ttTeamTo.TeamName.  
                run createPreMerge(ttTeamFrom.teamid, "merge", ttTeamTo.teamid, nameDescription).
            end.  
        end. 
        else 
        do:
            nameDescription = ttTeamFrom.teamName + " - to be moved into household ".  
            run createPreMerge(ttTeamFrom.teamid, "", ?, nameDescription).  
        end.    
    end.
    run StoreInContext2.    
    SetData({&ScreenName},"FamilyMemberPreMerge").
end procedure.  /* PRE-MERGE END */

procedure create-log:
    def input parameter inpDetail1 as char no-undo.
    def input parameter inpDetail2 as char no-undo.
    def input parameter inpDetail3 as char no-undo.
    def input parameter inpDetail4 as char no-undo.
    def input parameter inpSource as char no-undo.
  
    def buffer BUFActivityLog for ActivityLog.
  
    do for BUFActivityLog transaction:
        create BUFActivityLog.
        assign 
            BUFActivityLog.SourceProgram = "HouseholdMerge" + inpSource                           
            BUFActivityLog.LogDate       = today
            BUFActivityLog.UserName      = caps(signon())
            BUFActivityLog.LogTime       = time
            BUFActivityLog.Detail1       = inpdetail1
            BUFActivityLog.Detail2       = inpdetail2
            BUFActivityLog.Detail3       = inpDetail3
            BUFActivityLog.Detail4       = inpDetail4.
    end. 

end procedure.  /* CREATE-LOG END */
  
procedure update-mem-schol:
    define input parameter personid as int64 no-undo.
    define input parameter amt as dec no-undo.
    define buffer buf-Member for Member.

    do for buf-Member transaction:     
        find buf-Member exclusive-lock where buf-Member.id = personid no-error no-wait.      
        if available buf-Member then assign buf-Member.ScholarshipAmount = buf-Member.ScholarshipAmount - amt.
    end.

end procedure. /* UPDATE-MEM-SCHOL END */  
 
procedure ProcessMerge:
  
    define variable ix                 as integer   no-undo.
    define variable good-hist          as logical   no-undo.
    define variable householdComments  as character no-undo.
    define variable householdTicklers  as character no-undo.
    define variable housholdFeatures   as character no-undo.
    define variable householdPhone     as character no-undo.
    define variable householdPhoneExt  as character no-undo.
    define variable householdPhonetype as character no-undo.
    define variable householdEmail     as character no-undo.
    define variable hhid               as int64     no-undo.
    define variable cc-link            as integer   no-undo.
    define variable autopay-opt        as character no-undo.
    define variable from-extid         as character no-undo init "".
    define variable newId              as int64     no-undo.
    define variable number             as integer   no-undo.
    define variable newLink            as integer   no-undo.
   
    define buffer bufPhoneNumber            for PhoneNumber.
    define buffer bufsaemailaddress     for EmailContact.    
    define buffer buf1WebUserName       for WebUserName.
    define buffer buf2WebUserName       for WebUserName.      
    define buffer bufMember           for Member.
    define buffer bufLSTeam             for LSTeam.  
    define buffer bufContactEmergency for ContactEmergency.
    define buffer bufAccountAddress for AccountAddress.
    define buffer bufBinaryFile         for BinaryFile.
    define buffer bufRelationship             for Relationship. 
    define buffer bufLSSchedule         for LSSchedule.
    
    assign 
        photo-check = if findProfile("Photo") = false then no else yes.
  
  
    run create-log ("From Household: " + string(FromHHNumber) +
        "  To Household: " + string(ToHHNumber) + "  Option: " + if MergeOption = "transfer"
        then "Transfer" else if MergeOption = "fullmerge" then "Full Merge"
        else "Partial Merge",
        "",
        "",
        "",
        "").

  
    find first bufFromAccount no-lock where bufFromAccount.EntityNumber = FromHHNumber no-error.      
    FromHHID = if available bufFromAccount then bufFromAccount.id else 0.
    find first bufToAccount no-lock where bufToAccount.EntityNumber = TOHHNumber no-error. 
    ToHHID = if available bufToAccount then bufToAccount.id else 0.
                                   
    create ChargeHistory.
    assign
        ChargeHistory.ParentRecord     = ToHHID
        ChargeHistory.parenttable  = "Account"
        ChargeHistory.LogDate      = today
        ChargeHistory.LogTime      = time
        ChargeHistory.Notes        = "From Household: " + string(FromHHNumber) + "  To Household: " + string(ToHHNumber) +
                         (if MergeOption = "transfer" then " (Transfer)" 
                          else if MergeOption = "fullmerge" then " (Full Merge)"
                          else " (Partial Merge)")
        ChargeHistory.RecordStatus = "Note"
        ChargeHistory.UserName     = Signon().
 
    if MergeOption = "partialmerge" then 
    do: 
        create ChargeHistory.
        assign
            ChargeHistory.ParentRecord     = FromHHID
            ChargeHistory.parenttable  = "Account"
            ChargeHistory.LogDate      = today
            ChargeHistory.LogTime      = time
            ChargeHistory.Notes        = "From Household: " + string(FromHHNumber) + "  To Household: " + string(ToHHNumber) + " (Partial Merge)"
            ChargeHistory.RecordStatus = "Note"
            ChargeHistory.UserName     = Signon().    
    end. /* CREATE HISTORY FOR FROM HH ONLY IF PARTIAL MERGE */     
 
    if lookup(MergeOption,"fullmerge,transfer") gt 0 then 
    do:
        assign 
            emnum = 0.    
        if mergeOption ne "transfer" then 
        do:
            for each bufContactEmergency no-lock where bufContactEmergency.ParentRecord = ToHHID:
                assign 
                    emnum = if bufContactEmergency.Order gt emnum then bufContactEmergency.Order else emnum.
            end.
            assign 
                emnum = emnum + 1.
  
            for each ContactEmergency no-lock where ContactEmergency.ParentRecord = FromHHID by ContactEmergency.Order:
                run UpdateSAEmergencyContact (rowid(ContactEmergency)).
            end.  /*  FOR EACH END  */       
     
            for each EPayInfo no-lock where EPayInfo.ParentRecord = FromHHID:
                run UpdateEPayInfo (rowid(EPayInfo)).        
            end.  /*  FOR EACH END  */      
      
            for each CardTransactionLog no-lock where CardTransactionLog.ParentRecord  = FromHHID:
                run UpdateSACreditCardHistory (rowid(CardTransactionLog)).         
            end.  /*  FOR EACH END  */    
    
            for each BinaryFile no-lock where BinaryFile.Filename begins "\Household Documents\" + string(FromHHID) + "\":
                NewFileName = replace(BinaryFile.Filename, "\" + string(FromHHID) + "\", "\" + string(ToHHID) + "\").
                find first BufBlobFile no-lock where BufBlobFile.Filename = 
                    NewFileName no-error.

                if available BufBlobfile and 
                    (BufBlobFile.FileDate gt BinaryFile.FileDate or
                    (BufBlobFile.FileDate = BinaryFile.FileDate and BufBlobFile.FileTime ge BinaryFile.FileTime))
                    then run DeleteSABlobFile (BinaryFile.id).        
                else if available BufBlobfile then 
                    do:
                        run DeleteSABlobFile (bufBinaryFile.id).              
                        run UpdateSABlobFile (BinaryFile.id). 
                    end.
                    else run UpdateSABlobFile (BinaryFile.id).           

            end.  /*  FOR EACH END  */      
    
            for each File no-lock where File.ParentRecord = FromHHID:
                run UpdateSADocument (File.id).           
            end.  /*  FOR EACH END  */   
       
            for each bufLSSchedule no-lock where bufLSSchedule.AwayHouseholdNumber = FromHHNumber:
                run updateLeagueLSSchedule (bufLSSchedule.id, ToHHNumber, ?, "away", "").
            end.        
     
            for each bufLSSchedule no-lock where bufLSSchedule.HomeHouseholdNumber = FromHHNumber:
                run updateLeagueLSSchedule (bufLSSchedule.id, ToHHNumber, ?, "home", "").
            end.
    
        end. /* NOT TRANSFER END */   
     
        for each AccountBalanceLog no-lock where AccountBalanceLog.EntityNumber = FromHHNumber:
            run UpdateSAControlAccountHistory (rowid(AccountBalanceLog)).       
        end.  /*  FOR EACH END  */            
        for each MTCuslog no-lock where MTCuslog.CustomerNumber = FromHHNumber:
            run UpdateMTCuslog (rowid(MTCuslog)).       
        end.  /*  FOR EACH MTCuslog END  */  
        for each MTInvoice no-lock where MTInvoice.CustomerNumber = FromHHNumber:
            run UpdateMTInvoice (rowid(MTInvoice)).       
        end.  /*  FOR EACH MTInvoice END  */  
     
        for each PaymentLog no-lock where 
            PaymentLog.EntityNumber = FromHHNumber and
            PaymentLog.RecordType = "Rewards":
            run UpdateSAPaymentHistory (rowid(PaymentLog)).         
        end.  /*  FOR EACH END  */
  
        for each DPTicket no-lock where DPTicket.EntityNumber = FromHHNumber:
            run UpdateDPTicket (rowid(DPTicket)).       
        end.  /*  FOR EACH END  */      

        for each VoucherDetail no-lock where VoucherDetail.EntityNumber = FromHHNumber:
            run UpdateSAGiftCertificateDetail (rowid(VoucherDetail)).       
        end.  /*  FOR EACH END  */      
  
        for each GRTournament no-lock where GRTournament.EntityNumber = FromHHNumber:
            run UpdateGRTournament (rowid(GRTournament)).       
        end.  /*  FOR EACH END  */     
  
        find first AccountAddress no-lock where AccountAddress.EntityNumber = ToHHNumber no-error.
        if available AccountAddress then 
        do:
            find first bufAccountAddress no-lock where bufAccountAddress.EntityNumber = FromHHNumber no-error.
            if available bufAccountAddress then run DeleteSAHouseholdAddress (rowid(bufAccountAddress)).        
        end.  /* TO HH IS AVAILABLE SO DELETE FROM HH */
        else 
        do:
            find first bufAccountAddress no-lock where bufAccountAddress.EntityNumber = FromHHNumber no-error.
            if available bufAccountAddress then run UpdateSAHouseholdAddress (rowid(bufAccountAddress)).  
        end.  /* TO HH IS NOT AVAILABLE SO ADJUST FROM HH */
  
        for each Reversal no-lock where Reversal.EntityNumber = FromHHNumber:
            if Reversal.MemberLinkID = 0 then run UpdateSARefund (rowid(Reversal)).   
        end.  /*  FOR EACH END  */

        for each BillingStatement no-lock where BillingStatement.EntityNumber = FromHHNumber:
            run UpdateSAStatementHistory (rowid(BillingStatement)).          
        end.  /*  FOR EACH END  */  
  
        for each WebAddressChange no-lock where WebAddressChange.EntityNumber = FromHHNumber:
            run UpdateWebAddressChange (rowid(WebAddressChange)).          
        end.  /*  FOR EACH END  */       
    
        /** RENTALS THAT ARE NOT LINKED TO A FAMILY MEMBER DO NOT HAVE FM LINKS IN IBILLS **/
        /** IBHISTOR AND IBMASTER ARE ADJUSTED IN BOTH HH AND FM LOOPS                    **/
        for each InvoiceLineItem no-lock where 
            InvoiceLineItem.EntityNumber = FromHHNumber and
            InvoiceLineItem.MemberLinkID = 0:
            run UpdateSABillingDetail (rowid(InvoiceLineItem)). 
        end.  /*  FOR EACH END  */
  
        for each ChargeHistory no-lock where ChargeHistory.PaymentHousehold = FromHHNumber:
            run UpdateSAFeeHistory (rowid(ChargeHistory)). 
        end.  /*  FOR EACH END  */    
  
        for each UserSession no-lock where UserSession.EntityNumber = FromHHNumber:
            run UpdateSASessionInfo (rowid(UserSession)). 
        end.  /*  FOR EACH END  */      
  
        for each LedgerEntry no-lock where LedgerEntry.EntityNumber = FromHHNumber:
            if MergeOption ne "Transfer" and LedgerEntry.PatronLinkID ne 0 then next.
            run UpdateSAGLDistribution (rowid(LedgerEntry)). 
        end.  /*  FOR EACH END  */   
  
        for each PaymentTransaction no-lock where PaymentTransaction.PaymentHousehold = FromHHNumber:
            run UpdateSAReceiptPayment (rowid(PaymentTransaction)). 
        end.  /*  FOR EACH END  */   
  
        for each PaymentReceipt no-lock where PaymentReceipt.EntityNumber = FromHHNumber:  
            run UpdateSAReceipt (rowid(PaymentReceipt)). 
        end.  /*  FOR EACH END  */     
  
        for each WebWishList no-lock where 
            WebWishList.ParentRecord = FromHHID and
            WebWishList.MemberLinkID = 0:
            run UpdateWebWishList (rowid(WebWishList)). 
        end.  /*  FOR EACH END  */ 
    
        for each Agreement no-lock where Agreement.EntityNumber = FromHHNumber:
            run UpdateSAContract (rowid(Agreement)).
        end. /* FOR EACH END */
    end.  /*  CONVERT H/H ONLY TABLES IF DOING FULL MERGE OR TRANSFER END  */
    else 
    do: 
        find first bufToAccount no-lock where bufToAccount.EntityNumber = TOHHNumber no-error.  
        ToHHID = if available bufToAccount then  bufToAccount.id else 0.
    end.   
    /****************************************************************************/
    /*  Convert all of the tables that have a family member link                */
    /****************************************************************************/
    for each ttFamilyFrom where ttFamilyFrom.mergeoptionfamily ne "Do Not Transfer/Merge":   
        run getNewLinkForFamily(output newLink).
        if FromHHNumber eq ToHHNumber and newLink eq ttFamilyFrom.number then next. 
        run updateDetails(ttFamilyFrom.personId, ttFamilyFrom.mergeoptionfamily, "family", output newId).
 
        run FMAdjustments (ttFamilyFrom.personid, newId, MergeOption, yes).              
        find first Member no-lock where Member.ID = ttFamilyFrom.personid no-error.  
        for first Relationship no-lock where Relationship.ChildTableID = ttFamilyFrom.personid and
            Relationship.ChildTable = "Member" and
            Relationship.ParentTableID = FromHHID and
            Relationship.ParentTable = "Account" and           
            Relationship.Order = ttFamilyFrom.number:
        end.
    
        if not available Member or not available Relationship then next.
    
        /* If just transferring a person with a web account into another household, reset their web permissions */
        find first WebUserName no-lock where WebUserName.ParentRecord = Member.ID no-error.
        if available WebUserName and ttFamilyFrom.mergeoptionfamily = "Transfer Member into the To Household" then run updateWebUserNamePermissions(rowid(Relationship)).
    
        for first bufRelationship no-lock where
            bufRelationship.ParentTableID = ToHHID and
            bufRelationship.ParentTable = "Account" and
            bufRelationship.ChildTable = "Member" and   
            bufRelationship.Order = newLink:
            find first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID no-error.
            if available bufMember then 
            do:
                if bufMember.id <> Member.id then 
                do:
                    run WebUserNameAdjustments (Member.ID, bufMember.ID, Relationship.ID, bufRelationship.ID, MergeOption).
                    run FMAdjustments (Member.id, bufMember.id, MergeOption, no).   
                    run UpdatebufMember (rowid(bufMember)). 
                    run RemoveMember (Member.id, bufMember.id, Relationship.id).
                end.
                else run othersalinks(Member.id, bufMember.id, Relationship.id).
            end.
            else run UpdateRelationship2 (bufRelationship.id, Member.id, newLink).  
            run DeleteRelationship (Relationship.id).         
        end.
        if not available bufRelationship then 
        do:
            if Relationship.Primary then   
                run UpdateRelationship (Relationship.id, newlink, "").
            else
                run UpdateRelationship (Relationship.id, newlink, Relationship.Relationship).      
        end.
        for each AccountBenefits no-lock where 
            AccountBenefits.HouseholdID = FromHHID and
            AccountBenefits.QualifyingPersonID eq ttFamilyFrom.personID:
            run UpdateAccountBenefits (rowid(AccountBenefits),input newId). 
        end.  /*  FOR EACH END  */ 
        if mergeoption eq "partialmerge" and ttFamilyFrom.isPrimary then
            run makeNextAvailablePersonPrimary.
    end.
  
    if not can-find(first ttFamilyFromPreMerge) then
        for each ttTeamFrom where ttTeamFrom.mergeoptionteam eq "Do Not Transfer/Merge":
            ttTeamFrom.mergeoptionteam = "Transfer Team into the To Household".
        end.      
        
    for each ttTeamFrom where ttTeamFrom.mergeoptionteam ne "Do Not Transfer/Merge":
        run getNewLinkForTeam(output newLink).   
        if FromHHNumber eq ToHHNumber and newLink eq ttTeamFrom.number then next. 
        run updateDetails(ttTeamFrom.teamid, ttTeamFrom.mergeoptionteam, "team", output newId).   
        find first LSTeam no-lock where LSTeam.ID = ttTeamFrom.teamid no-error.  
          
        for first Relationship no-lock where Relationship.ChildTableID = ttTeamFrom.teamid and
            Relationship.ChildTable = "LSTeam" and
            Relationship.ParentTableID = FromHHID and
            Relationship.ParentTable = "Account" and           
            Relationship.Order = ttTeamFrom.number:
        end.
     
        if not available LSTeam or not available Relationship then
            next.
        for first bufRelationship no-lock where
            bufRelationship.ParentTableID = ToHHID and
            bufRelationship.ParentTable = "Account" and
            bufRelationship.ChildTable = "LSTeam" and   
            bufRelationship.Order = newLink:
 
            find first bufLSTeam no-lock where bufLSTeam.ID = bufRelationship.ChildTableID no-error.      
            if available bufLSTeam then 
            do: 
                if bufLSTeam.id <> LSTeam.ID then
                    run RemoveLSTeam (LSTeam.ID, bufLSTeam.id, Relationship.ID).
                else
                    run othersalinks(LSTeam.id, bufLSTeam.id, Relationship.ID).
            end.
            else
                run UpdateRelationship2 (bufRelationship.ID, LSTeam.ID, NewLink).  
            run DeleteRelationship (Relationship.ID).
        end.
        if not available bufRelationship then
            run UpdateRelationship (Relationship.id, newlink, Relationship.Relationship).
   
        for each bufLSSchedule no-lock where bufLSSchedule.AwayTeamLinkID = ttTeamFrom.teamid:
            run updateLeagueLSSchedule(bufLSSchedule.ID, ToHHNumber, newId, "away", "teamLinkID").
            run updateLSTeamStanding(ttTeamFrom.teamid, newId).
        end.
        for each bufLSSchedule no-lock where bufLSSchedule.HomeTeamLinkID = ttTeamFrom.teamid:
            run updateLeagueLSSchedule(bufLSSchedule.ID, ToHHNumber, newId, "home", "teamLinkID").
            run updateLSTeamStanding(ttTeamFrom.teamid, newId).
        end.
    
    end.
  
    if lookup(MergeOption,"fullmerge,transfer") gt 0 then 
    do: /**Do this after FM Piece to catch any still linked to old house ***/
        for each TransactionDetail no-lock where
            TransactionDetail.EntityNumber = FromHHNumber:
            run UpdateSADetail (rowid(TransactionDetail)).
        end.  /*  FOR EACH END  */ 
    end.  
    /****************************************************************************/
    /*  Update the FROM household for all types of conversions                  */
    /****************************************************************************/
    FromHHNumberupdt:
    do:
  
        find first bufFromAccount exclusive-lock where bufFromAccount.EntityNumber = FromHHNumber no-error no-wait.
        FromHHID = if availabl bufFromAccount then bufFromAccount.id else 0.
        if not available bufFromAccount then leave FromHHNumberupdt.
       
        if MergeOption = "fullmerge" then assign
                cc-link                         = bufFromAccount.EPayLink
                autopay-opt                     = bufFromAccount.AutoPayBalance
                bufFromAccount.RewardPoints = 0.
  
        for each PaymentLog no-lock where 
            PaymentLog.EntityNumber = bufFromAccount.EntityNumber and
            PaymentLog.RecordType = "Rewards":
            assign 
                bufFromAccount.RewardPoints = bufFromAccount.RewardPoints + PaymentLog.Amount.
        end.  /* FOR EACH END  */ 
      
        if MergeOption = "fullmerge" then assign
                householdComments  = bufFromAccount.comments
                householdTicklers  = bufFromAccount.TicklerText
                housholdFeatures   = bufFromAccount.Features
                householdEmail     = bufFromAccount.PrimaryEmailAddress
                householdPhone     = bufFromAccount.PrimaryPhoneNumber 
                householdPhoneExt  = bufFromAccount.PrimaryPhoneExtension 
                householdPhoneType = bufFromAccount.PrimaryPhoneType 
                hhid               = FromHHID.
  
        if MergeOption = "transfer" /*and ConflictCount = 0*/ then assign
                bufFromAccount.EntityNumber = ToHHNumber.   
        else if MergeOption = "fullmerge" /*and ConflictCount = 0*/ and
                FromHHNumber ne ToHHNumber then delete bufFromAccount.
    
    end.  /*  FromHHNumberUPDT END  */    
  
    /****************************************************************************/
    /*  Update the TO household for MERGE type conversions                      */
    /****************************************************************************/
    if lookup(MergeOption,"fullmerge,partialmerge") gt 0 then 
    do:
  
        ToHHNumberupdt:
        do:
  
            find first bufToAccount exclusive-lock where bufToAccount.EntityNumber = ToHHNumber no-error no-wait.
            ToHHID = if available bufToAccount then  bufToAccount.id else 0.
            if MergeOption = "fullmerge" then assign 
                    bufToAccount.AutoPayBalance = if bufToAccount.EPayLink = 0 then autopay-opt else bufToAccount.AutoPayBalance 
                    bufToAccount.EPayLink       = if bufToAccount.EPayLink = 0 then cc-link else bufToAccount.EPayLink.
             
            bufToAccount.RewardPoints = 0.
  
            for each PaymentLog no-lock where 
                PaymentLog.EntityNumber = bufToAccount.EntityNumber and
                PaymentLog.RecordType = "Rewards":
                assign 
                    bufToAccount.RewardPoints = bufToAccount.RewardPoints + PaymentLog.Amount.
            end.  /*  FOR EACH END  */ 
  
            if MergeOption = "fullmerge" then 
            do:
                if lookup(householdComments,bufToAccount.Comments) = 0 then assign
                        bufToAccount.Comments = bufToAccount.Comments + (if householdComments ne "" then "  " else "") + householdComments.
  
                if lookup(householdTicklers,bufToAccount.TicklerText) = 0 then assign
                        bufToAccount.TicklerText = bufToAccount.TicklerText + (if householdTicklers ne "" then "  " else "") + householdTicklers.
        
                if bufToAccount.PrimaryPhoneNumber = "" then assign
                        bufToAccount.PrimaryPhoneNumber    = householdPhone
                        bufToAccount.PrimaryPhoneExtension = householdPhoneExt
                        bufToAccount.PrimaryPhonetype      = householdPhonetype.
                for each PhoneNumber no-lock where PhoneNumber.ParentRecord = hhid
                    and PhoneNumber.ParentTable = "Account":
                    for first BUFPhone no-lock where BUFPhone.ParentRecord = ToHHID and 
                        BufPhone.ParentTable = "Account" and 
                        BufPhone.phonenumber = PhoneNumber.PhoneNumber:
                        run purgesaphone (PhoneNumber.id).
                    end.  
                    if not available BUFPhone then
                        run updatesaphone (PhoneNumber.id, ToHHID, if PhoneNumber.PhoneNumber = bufToAccount.PrimaryPhoneNumber then yes else no).
                end.
        
                if bufToAccount.PrimaryEmailAddress = "" then bufToAccount.PrimaryEmailAddress = householdEmail.
                for each EmailContact no-lock where EmailContact.ParentRecord = hhid
                    and EmailContact.ParentTable = "Account":
                    for first BUFEmailAddress no-lock where BUFEmailAddress.ParentRecord = ToHHID and 
                        BufEmailAddress.ParentTable = "Account" and 
                        BufEmailAddress.EmailAddress = EmailContact.EmailAddress:
                        run purgeEmailContact (EmailContact.id).
                    end.  
                    if not available BUFEmailAddress then 
                    do: 
                        run updateEmailContact (EmailContact.id, ToHHID, if EmailContact.EmailAddress = 
                            bufToAccount.PrimaryEmailAddress then yes else no).
                    end.  
                end.

                if housholdFeatures ne "" then 
                do ix = 1 to num-entries(housholdFeatures):
                    if lookup(entry(ix,housholdFeatures),bufToAccount.Features) = 0 then assign
                            bufToAccount.Features = bufToAccount.Features + (if bufToAccount.Features ne "" then "," else "") +
            entry(ix,housholdFeatures).
                end.
            end.  /* FULL MERGE END */
  
        end.  /*  ToHHNumberUPDT END  */    
    end.  /*  UPDATE TO HOUSEHOLD IF MERGE END  */

    /*adjust the salinks for partialmerge*/
    if mergeoption eq "partialmerge" then 
    do:
        run adjustSaLinks(FromHHNumber).
        run adjustSaLinks(ToHHNumber).
    end.
  
    if FromHHNumber ne ToHHNumber then run UpdateSaFeeHistoryStartingBalanceRecords.
  
end procedure. /* PROCESSMERGE END */


procedure findconflict:
    def input parameter TransactionDetailID as int64 no-undo.
    def input parameter newpatron as int64 no-undo.
  
    def buffer ExistSadetail    for TransactionDetail.
    def buffer ConflictSadetail for TransactionDetail.
    find first ExistSadetail no-lock where ExistSadetail.id = TransactionDetailID no-error.
    if not available ExistSadetail then return.
   
    if existsadetail.RecordType = "By Day" then 
    do: 
        for first ConflictSadetail no-lock where 
            ConflictSadetail.EntityNumber = ToHHNumber and 
            ConflictSadetail.PatronLinkID = newpatron and        
            ConflictSadetail.FileLinkid = ExistSadetail.filelinkid and
            ConflictTRANSACTIONDETAIL.BeginDateTime = ExistSadetail.BeginDateTime and 
            ConflictSadetail.CartStatus = "Complete"  and    
            ConflictSadetail.RecordStatus ne "Cancelled": 
            ConflictCount    = ConflictCount + 1.
            run create-log ("From Household: " + string(FromHHNumber) +
                "  To Household: " + string(ToHHNumber) + "  Option: " + if MergeOption = "transfer"
                then "Transfer" else if MergeOption = "fullmerge" then "Full Merge"
                else "Partial Merge",
                "Dupe enrollment for: " + String(newpatron) + 
                ", Activity: " + ExistSadetail.filelinkcode1 + "_" + ExistSadetail.filelinkcode2,
                "",
                "",
                "Conflicts").
        end.
    end.
    else 
        for first ConflictSadetail no-lock where 
            ConflictSadetail.EntityNumber = ToHHNumber and 
            ConflictSadetail.PatronLinkID = newpatron and        
            ConflictSadetail.FileLinkid = ExistSadetail.filelinkid and  
            ConflictSadetail.CartStatus = "Complete"  and    
            ConflictSadetail.RecordStatus ne "Cancelled":
    
            ConflictCount    = ConflictCount + 1.
            run create-log ("From Household: " + string(FromHHNumber) +
                "  To Household: " + string(ToHHNumber) + "  Option: " + if MergeOption = "transfer"
                then "Transfer" else if MergeOption = "fullmerge" then "Full Merge"
                else "Partial Merge",
                "Dupe enrollment for: " + String(newpatron) + 
                (if ExistSadetail.Module = "AR" then ", Activity: " + ExistSadetail.filelinkcode1 + "_" + ExistSadetail.filelinkcode2
                else ", League: " + ExistSadetail.filelinkcode1),
                "",
                "",
                "Conflicts").
        end.
      
end procedure.

procedure FMAdjustments:
    def input parameter InpOldId as int64 no-undo.
    def input parameter inpNewId as int64 no-undo.
    def input parameter inpRunoption as char no-undo.
    def input parameter HHImportant as log no-undo. 
  
    def var dup-found as log no-undo.
    def buffer bufImmunizationRecord     for ImmunizationRecord.
    def buffer bufEntityLink for EntityLink. 
    def buffer bufBinaryFile       for BinaryFile. 
    
    for each Employee no-lock where Employee.MemberLinkID = InpOldId:
        run UpdateSAStaff (rowid(Employee), inpNewId).  
    end.  /*  FOR EACH END  */
  
    if inpRunoption ne "transfer" and inpoldid <> inpnewid then 
    do:
        
        ImmunizationRecord-loop:
        for each ImmunizationRecord no-lock where ImmunizationRecord.MemberLinkID = inpoldid:

            dup-found = no.
            dup-loop:
            for each bufImmunizationRecord no-lock where bufImmunizationRecord.MemberLinkID = inpnewid and bufImmunizationRecord.RecordCode = ImmunizationRecord.RecordCode:
                if bufImmunizationRecord.ShotDate = ImmunizationRecord.ShotDate and bufImmunizationRecord.DueDate = ImmunizationRecord.DueDate then dup-found = yes.
                if dup-found then leave dup-loop.
            end.

            if not dup-found then run UpdateSAShotDetail (rowid(ImmunizationRecord),inpnewid).  
            else run DeleteSAShotDetail (rowid(ImmunizationRecord)). 
        end.  /*  ImmunizationRecord-LOOP END  */
    
        for each PaymentTransaction no-lock where PaymentTransaction.PaymentMemberID = inpoldid:
            run UpdateSAReceiptPayment2 (rowid(PaymentTransaction),inpnewid).          
        end.  /*  FOR EACH END  */  
        for each HealthInfo no-lock where HealthInfo.MemberLinkID = inpoldid:
            run UpdateSAMedicalDetail (rowid(HealthInfo),inpnewid).            
        end.  /*  FOR EACH END  */  
        for each CYProviderReferral no-lock where CYProviderReferral.MemberLinkID = inpoldid:
            run UpdateCYProviderReferral (rowid(CYProviderReferral),inpnewid).         
        end.  /*  FOR EACH END  */   

        for each BinaryFile no-lock where BinaryFile.Filename begins "\Family Member Documents\" + string(inpoldid) + "\": 
            NewFileName = replace(BinaryFile.Filename, "\" + string(inpoldid) + "\", "\" + string(inpnewid) + "\").
            find first BufBlobFile no-lock where BufBlobFile.Filename = 
                NewFileName no-error.

            if available BufBlobfile and 
                (BufBlobFile.FileDate gt BinaryFile.FileDate or
                (BufBlobFile.FileDate = BinaryFile.FileDate and BufBlobFile.FileTime ge BinaryFile.FileTime))       
                then run DeleteSABlobFile (BinaryFile.id).        
            else if available BufBlobfile then 
                do:
                    run DeleteSABlobFile (bufBinaryFile.id).              
                    run UpdateSABlobFile2 (BinaryFile.id,inpoldid,inpnewid). 
                end.
                else run UpdateSABlobFile2 (BinaryFile.id,inpoldid,inpnewid).         
        end.  /*  FOR EACH END  */    

        for each File no-lock where File.ParentRecord = inpoldid:
            run UpdateSADocument2 (File.id,inpnewid).         
        end.  /*  FOR EACH END  */

    end. /***inpRunoption ne "transfer"***/
  
    if not HHImportant then 
    do:
        for each TransactionDetail no-lock where    
            TransactionDetail.PatronLinkID = InpOldId:
            run UpdateSADetail2 (rowid(TransactionDetail),inpnewid).  
      
            for each InvoiceLineItem no-lock where 
                InvoiceLineItem.DetailLinkID  = TransactionDetail.id:
                run UpdateSABillingDetail2 (rowid(InvoiceLineItem),inpnewid).          
            end.  /*  FOR EACH END  */          
            for each LedgerEntry no-lock where LedgerEntry.detaillinkID = TransactionDetail.id:
                run UpdateSAGLDistribution2 (LedgerEntry.id,inpNewId). 
            end.  /*  FOR EACH END  */  
            if TransactionDetail.Module = "PST" and TransactionDetail.SerialNumber gt "" then 
            do:
                for each PSSerialTicket no-lock where PSSerialTicket.SerialNumber = TransactionDetail.SerialNumber
                    and PSSerialTicket.TicketCode = TransactionDetail.FileLinkCode1: 
                    if PSSerialTicket.EntityNumber = FRomHHnumber or 
                        PSSerialTicket.MemberLinkID = inpoldid then  run UpdatePSSerialTicket (rowid(PSSerialTicket),inpoldid,inpnewid ).        
                end.  /*  FOR EACH END  */
        
            end.    
        end.  /*  Archived-LOOP END  */
    end.  
   
    for each CYProviderEnrolleeSchedule no-lock where  
        CYProviderEnrolleeSchedule.MemberLinkID = inpoldid:
        run UpdateCYProviderEnrolleeSchedule (rowid(CYProviderEnrolleeSchedule),inpnewid).          
    end.  /*  FOR EACH END  */   
  
    for each CYWaitlist no-lock where  
        CYWaitlist.MemberLinkID = inpoldid:
        run UpdateCYWaitlist2 (rowid(CYWaitlist),inpnewid).          
    end.  /*  FOR EACH END  */
  
    for each WaiverLog no-lock where 
        WaiverLog.ParentRecord = inpoldid:
        run UpdateSAWaiverHistory2 (rowid(WaiverLog),inpnewid).        
    end.  /*  FOR EACH END  */
    for each PaymentLog no-lock where  
        PaymentLog.MemberLinkID = inpoldid:
        run UpdateSAPaymentHistory3 (rowid(PaymentLog),inpnewid).            
    end.  /*  FOR EACH END  */ 
    for each Reversal no-lock where  
        Reversal.MemberLinkID = inpoldid:
        run UpdateSARefund2 (rowid(Reversal),inpnewid).          
    end.  /*  FOR EACH END  */
    entitylink-loop:
    for each EntityLink no-lock where  
        EntityLink.MemberLinkID = inpoldid:         

        for first bufEntityLink no-lock where bufEntityLink.EntityNumber = ToHHNumber and
            bufEntityLink.MemberLinkID = inpnewid and
            bufEntityLink.ExternalID = EntityLink.ExternalID:
            run DeleteSACrossReference (rowid(EntityLink)).       
        end.
      
        if not available bufEntityLink then run UpdateSACrossReference (rowid(EntityLink),inpnewid).          
    end.  /*  FOR EACH END  */  
  
end procedure.

procedure updateDetails:
    /*------------------------------------------------------------------------------
     Purpose:
     Notes:
    ------------------------------------------------------------------------------*/
    define input parameter personOrTeamId as int64 no-undo.
    define input parameter mergeoptionFamilyOrTeam as char no-undo.
    define input parameter teamOrFamily as char no-undo.
    define output parameter newId as int64 no-undo.

    define variable number as integer no-undo.
    if teamOrFamily eq "family" then   
        newId =  ttFamilyFrom.personid.
    else newId = ttTeamFrom.teamid.
  
    if mergeoptionFamilyOrTeam begins "Merge" then 
    do:    
        run extractNumber(mergeoptionFamilyOrTeam, output number).
        if teamOrFamily eq "family" then   
            for first ttFamilyTo where ttFamilyTo.number eq number:
                newId = ttFamilyTo.personId. 
            end. 
        else
            for first ttTeamTo where ttTeamTo.number eq number:
                newId = ttTeamTo.teamid. 
            end.       
    end.    
    
    for each PaymentLog no-lock where
        PaymentLog.MemberLinkID = personOrTeamId and
        PaymentLog.RecordType = "Scholarship":
        run UpdateSAPaymentHistory3 (rowid(PaymentLog),newId).         

    end.  /*  FOR EACH END  */                        
   
    for each TransactionDetail no-lock where TransactionDetail.PatronLinkID = personOrTeamId:   
        /**Can't use HH number filter here - need to convert all linked to this person ***/
        if TransactionDetail.Module = "AR" and
            TransactionDetail.CartStatus = "Complete" 
            and not sadetail.archived 
            and newId <> personOrTeamId
            and TransactionDetail.RecordStatus ne "Cancelled" then 
        do:
        
            run findconflict (TransactionDetail.id, newId).  
        end.
      
        run UpdateSADetail2 (rowid(TransactionDetail),newId).  
      
        for each InvoiceLineItem no-lock where 
            InvoiceLineItem.DetailLinkID  = TransactionDetail.id:
            run UpdateSABillingDetail2 (rowid(InvoiceLineItem),newId).          
        end.  /*  FOR EACH END  */  
        for each LedgerEntry no-lock where LedgerEntry.detaillinkID = TransactionDetail.id:
            run UpdateSAGLDistribution2 (LedgerEntry.id,newId). 
        end.  /*  FOR EACH END  */  
        if TransactionDetail.Module = "PST" and TransactionDetail.SerialNumber gt "" then 
        do:
            for each PSSerialTicket no-lock where PSSerialTicket.SerialNumber = TransactionDetail.SerialNumber
                and PSSerialTicket.TicketCode = TransactionDetail.FileLinkCode1: 
                if PSSerialTicket.EntityNumber = fromhhnumber or 
                    PSSerialTicket.MemberLinkID = personOrTeamId then  
                    run UpdatePSSerialTicket (rowid(PSSerialTicket),personOrTeamId,newId).        
            end.  /*  FOR EACH END  */
        
        end.         
    end.  /*  Archived-LOOP END  */

end procedure.

procedure updateEmergencyContact:
  
    def input parameter row1 as rowid.
  
    def buffer buf-ContactEmergency for ContactEmergency.
  
    do for buf-ContactEmergency transaction:     
        find buf-ContactEmergency exclusive-lock where rowid(buf-ContactEmergency) = row1 no-error no-wait.
        if available buf-ContactEmergency then 
        do:
            assign 
                buf-ContactEmergency.ParentRecord = ToHHID.
            assign
                buf-ContactEmergency.Order = emnum + 1
                emnum                        = emnum + 1.     
        end.
    end.

end procedure. 

procedure updateLeagueRelationship:
    def input parameter inpid as int64 no-undo.
    def input parameter newlinkid as int64 no-undo.
    def buffer buf-Relationship for Relationship.
    do for buf-Relationship transaction:
        find buf-Relationship exclusive-lock where buf-Relationship.id = inpid no-error no-wait.
        if available buf-Relationship then assign buf-Relationship.parenttableid = newlinkid.
    end.
end procedure.

procedure updateLSTeamStanding:
    
    define input parameter ipTeamId    as integer no-undo.
    define input parameter ipNewTeamId as integer no-undo.
  
    define buffer buf-LSTeamStanding for LSTeamStanding.
  
    do for buf-LSTeamStanding transaction:
        find buf-LSTeamStanding exclusive-lock where buf-LSTeamStanding.LSTeamLinkID = ipTeamId no-error no-wait.
        if available buf-LSTeamStanding then assign buf-LSTeamStanding.LSTeamLinkID = ipNewTeamId.
    end.
  
end procedure.

procedure updateLeagueLSSchedule:
    define input parameter inpid         as int64 no-undo.
    define input parameter newHHnumber   as int.
    define input parameter newTeamLinkID as int.
    define input parameter inpoption     as char.
    define input parameter fieldOption   as char.
  
    def buffer buf-LSSchedule for LSSchedule.
    do for buf-LSSchedule transaction:
        find buf-LSSchedule exclusive-lock where buf-LSSchedule.id = inpid no-error no-wait.
        if available buf-LSSchedule and inpoption = "away" then 
        do:
            buf-LSSchedule.AwayHouseholdNumber = newHHnumber.
            if fieldOption = "teamLinkID" then buf-LSSchedule.AwayTeamLinkID = newTeamLinkID.
        end.
        else if available buf-LSSchedule then 
            do:
                buf-LSSchedule.HomeHouseholdNumber = newHHnumber.
                if fieldOption = "teamLinkID" then buf-LSSchedule.HomeTeamLinkID = newTeamLinkID.
            end.
    end.
end procedure.

procedure UpdateEPayInfo:
  
    def input parameter row1 as rowid.
  
    def buffer buf-EPayInfo for EPayInfo.
  
    do for buf-EPayInfo transaction:     
        find buf-EPayInfo exclusive-lock where rowid(buf-EPayInfo) = row1 no-error no-wait.
        if available buf-EPayInfo then assign buf-EPayInfo.ParentRecord = ToHHID.
    end.

end procedure. 

procedure updateCardTransactionLog:
  
    def input parameter row1 as rowid.
  
    def buffer buf-CardTransactionLog for CardTransactionLog.
  
    do for buf-CardTransactionLog transaction:     
        find buf-CardTransactionLog exclusive-lock where rowid(buf-CardTransactionLog) = row1 no-error no-wait.
        if available buf-CardTransactionLog then assign buf-CardTransactionLog.ParentRecord = ToHHID.
    end.

end procedure.

procedure updateDocument:
  
    def input parameter inp1 as int64 no-undo.
  
    def buffer buf-File for File.
  
    do for buf-File transaction:     
        find first buf-File exclusive-lock where buf-File.id = inp1 no-error no-wait.
        if available buf-File then assign
                buf-File.ParentRecord = ToHHID
                buf-File.Filename = replace(buf-File.Filename, "\" + string(FromHHID) + "\", "\" + string(ToHHID) + "\").
    end.

end procedure. 

procedure updateBinaryFile:

    def input parameter inp1 as int64 no-undo.

    def buffer buf-BinaryFile for BinaryFile.
    def buffer buf-File for File.
  
    do for buf-BinaryFile transaction:
        find first buf-BinaryFile exclusive-lock where buf-BinaryFile.id = inp1 no-error no-wait.
        if available buf-BinaryFile then 
        do:
            find first buf-File exclusive-lock where buf-File.FileName = buf-BinaryFile.FileName no-error no-wait.      
            if available buf-File then assign
                    buf-File.Filename = NewFileName
                    buf-File.ParentRecord = ToHHID.    

            assign
                buf-BinaryFile.Filename   = NewFileName
                buf-BinaryFile.FolderName = replace(buf-BinaryFile.FolderName,  "\" + string(FromHHID) + "\", "\" + string(ToHHID) + "\").
        end.
    end.

end procedure.

procedure deleteBinaryFile:

    def input parameter inp1 as int64 no-undo.

    def buffer buf-BinaryFile for BinaryFile.
    def buffer buf-File for File.
  
    do for buf-BinaryFile, buf-File transaction:
        find first buf-BinaryFile exclusive-lock where buf-BinaryFile.id = inp1 no-error no-wait.
        if available buf-BinaryFile then 
        do:
            find first buf-File exclusive-lock use-index filename 
                where buf-File.FileName = buf-BinaryFile.FileName no-error no-wait.     
            if available buf-File then
                delete buf-File.

            delete buf-BinaryFile.
        end.
    end.

end procedure.

procedure updateMailingAddress:
  
    def input parameter row1 as rowid.
  
    def buffer buf-AccountAddress for AccountAddress.
  
    do for buf-AccountAddress transaction:     
        find buf-AccountAddress exclusive-lock where rowid(buf-AccountAddress) = row1 no-error no-wait.
        if available buf-AccountAddress then assign buf-AccountAddress.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAControlAccountHistory:
  
    def input parameter row1 as rowid.
  
    def buffer buf-AccountBalanceLog for AccountBalanceLog.
  
    do for buf-AccountBalanceLog transaction:     
        find buf-AccountBalanceLog exclusive-lock where rowid(buf-AccountBalanceLog) = row1 no-error no-wait.
        if available buf-AccountBalanceLog then assign buf-AccountBalanceLog.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAPaymentHistory:
  
    def input parameter row1 as rowid.
  
    def buffer buf-PaymentLog for PaymentLog.
  
    do for buf-PaymentLog transaction:     
        find buf-PaymentLog exclusive-lock where rowid(buf-PaymentLog) = row1 no-error no-wait.
        if available buf-PaymentLog then assign buf-PaymentLog.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateDPTicket:
  
    def input parameter row1 as rowid.
  
    def buffer buf-DPTicket for DPTicket.
  
    do for buf-DPTicket transaction:     
        find buf-DPTicket exclusive-lock where rowid(buf-DPTicket) = row1 no-error no-wait.
        if available buf-DPTicket then assign buf-DPTicket.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSADetail:
  
    def input parameter row1 as rowid.
  
    def buffer buf-TransactionDetail for TransactionDetail.
  
    do for buf-TransactionDetail transaction:     
        find buf-TransactionDetail exclusive-lock where rowid(buf-TransactionDetail) = row1 no-error no-wait.
        if available buf-TransactionDetail then assign buf-TransactionDetail.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAGiftCertificateDetail:
  
    def input parameter row1 as rowid.
  
    def buffer buf-VoucherDetail for VoucherDetail.
  
    do for buf-VoucherDetail transaction:     
        find buf-VoucherDetail exclusive-lock where rowid(buf-VoucherDetail) = row1 no-error no-wait.
        if available buf-VoucherDetail then assign buf-VoucherDetail.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateGRTournament:
  
    def input parameter row1 as rowid.
  
    def buffer buf-GRTournament for GRTournament.
  
    do for buf-GRTournament transaction:     
        find buf-GRTournament exclusive-lock where rowid(buf-GRTournament) = row1 no-error no-wait.
        if available buf-GRTournament then assign buf-GRTournament.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSARefund:
  
    def input parameter row1 as rowid.
  
    def buffer buf-Reversal for Reversal.
  
    do for buf-Reversal transaction:     
        find buf-Reversal exclusive-lock where rowid(buf-Reversal) = row1 no-error no-wait.
        if available buf-Reversal then assign buf-Reversal.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAStatementHistory:
  
    def input parameter row1 as rowid.
  
    def buffer buf-BillingStatement for BillingStatement.
  
    do for buf-BillingStatement transaction:     
        find buf-BillingStatement exclusive-lock where rowid(buf-BillingStatement) = row1 no-error no-wait.
        if available buf-BillingStatement then assign buf-BillingStatement.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateWebAddressChange:
  
    def input parameter row1 as rowid.
  
    def buffer buf-WebAddressChange for WebAddressChange.
  
    do for buf-WebAddressChange transaction:     
        find buf-WebAddressChange exclusive-lock where rowid(buf-WebAddressChange) = row1 no-error no-wait.
        if available buf-WebAddressChange then assign buf-WebAddressChange.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSABillingDetail:
  
    def input parameter row1 as rowid.
  
    def buffer buf-InvoiceLineItem for InvoiceLineItem.
  
    do for buf-InvoiceLineItem transaction:     
        find buf-InvoiceLineItem exclusive-lock where rowid(buf-InvoiceLineItem) = row1 no-error no-wait.
        if available buf-InvoiceLineItem then assign buf-InvoiceLineItem.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAFeeHistory:
  
    def input parameter row1 as rowid.
  
    def buffer buf-ChargeHistory for ChargeHistory.
  
    do for buf-ChargeHistory transaction:     
        find buf-ChargeHistory exclusive-lock where rowid(buf-ChargeHistory) = row1 no-error no-wait.
        if available buf-ChargeHistory then assign buf-ChargeHistory.PaymentHousehold = ToHHNumber.
    end.

end procedure. 

procedure UpdateSASessionInfo:
  
    def input parameter row1 as rowid.
  
    def buffer buf-UserSession for UserSession.
  
    do for buf-UserSession transaction:     
        find buf-UserSession exclusive-lock where rowid(buf-UserSession) = row1 no-error no-wait.
        if available buf-UserSession then assign buf-UserSession.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAGLDistribution2:
    def input parameter inpid as int64 no-undo.
    def input parameter NEWLinkID as int64 no-undo.
    def buffer buf-LedgerEntry for LedgerEntry.
    do for buf-LedgerEntry transaction:
        find buf-LedgerEntry exclusive-lock where buf-LedgerEntry.id = inpid no-error no-wait.
        if available buf-LedgerEntry then assign
                buf-LedgerEntry.EntityNumber = ToHHNumber 
                buf-LedgerEntry.patronlinkid    = NEWLinkID.
    end.
end procedure.

procedure UpdateSAGLDistribution:
  
    def input parameter row1 as rowid.
  
    def buffer buf-LedgerEntry for LedgerEntry.
  
    do for buf-LedgerEntry transaction:     
        find buf-LedgerEntry exclusive-lock where rowid(buf-LedgerEntry) = row1 no-error no-wait.
        if available buf-LedgerEntry then assign buf-LedgerEntry.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAReceiptPayment:
  
    def input parameter row1 as rowid.
  
    def buffer buf-PaymentTransaction for PaymentTransaction.
  
    do for buf-PaymentTransaction transaction:     
        find buf-PaymentTransaction exclusive-lock where rowid(buf-PaymentTransaction) = row1 no-error no-wait.
        if available buf-PaymentTransaction then assign buf-PaymentTransaction.PaymentHousehold = ToHHNumber.
    end.

end procedure. 

procedure UpdateSAReceipt:
  
    def input parameter row1 as rowid.
  
    def buffer buf-PaymentReceipt for PaymentReceipt.
  
    do for buf-PaymentReceipt transaction:     
        find buf-PaymentReceipt exclusive-lock where rowid(buf-PaymentReceipt) = row1 no-error no-wait.
        if available buf-PaymentReceipt then assign buf-PaymentReceipt.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateWebWishList:
  
    def input parameter row1 as rowid.
  
    def buffer buf-WebWishList for WebWishList.
  
    do for buf-WebWishList transaction:     
        find buf-WebWishList exclusive-lock where rowid(buf-WebWishList) = row1 no-error no-wait.
        if available buf-WebWishList then assign buf-WebWishList.EntityNumber = ToHHNumber.
    end.

end procedure. 

procedure UpdateAccountBenefits:
  
    def input parameter row1 as rowid.
    def input parameter newId as int64.
  
    def buffer buf-SaHouseholdBenefits for SaHouseholdBenefits.
  
    do for buf-SaHouseholdBenefits transaction:     
        find buf-SaHouseholdBenefits exclusive-lock where rowid(buf-SaHouseholdBenefits) = row1 no-error no-wait.
        if available buf-SaHouseholdBenefits then 
            assign buf-SaHouseholdBenefits.HouseholdID        = ToHHID
                buf-SaHouseholdBenefits.QualifyingPersonID = newId.
    end.

end procedure. 

procedure UpdateSADetail2:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo.
  
    def buffer buf-Member for Member.
    def buffer buf-TransactionDetail for TransactionDetail.
    def buffer buf-LSTeam   for LSTeam.
  
    do for buf-TransactionDetail transaction:     
        find buf-TransactionDetail exclusive-lock where rowid(buf-TransactionDetail) = row1 no-error no-wait.
        if available buf-TransactionDetail then 
        do:
            if buf-TransactionDetail.EntityNumber = FromHHnumber then 
            do:
                assign 
                    buf-TransactionDetail.EntityNumber = ToHHnumber. 
 
                for each Charge no-lock where           
                    Charge.ParentRecord = buf-TransactionDetail.ID and
                    Charge.ParentTable = "TransactionDetail":     
                    for each ChargeHistory no-lock where 
                        ChargeHistory.ParentRecord = Charge.ID and          
                        ChargeHistory.PaymentHousehold = FromHHNumber:
                        run UpdateSAFeeHistory (rowid(ChargeHistory)). 
                    end.  /*  FOR EACH END  */     
                end.  /*  FOR EACH END  */   
               
                for each ChargeHistory no-lock where 
                    ChargeHistory.ParentRecord = buf-TransactionDetail.ID and
                    ChargeHistory.ParentTable = "TransactionDetail" and          
                    ChargeHistory.PaymentHousehold = FromHHNumber:
                    run UpdateSAFeeHistory (rowid(ChargeHistory)). 
                end.  /*  FOR EACH END  */         
            end.
      
            assign 
                buf-TransactionDetail.PatronLinkID = NEWLinkID.
      
            if buf-TransactionDetail.PatronTypeLinkTable = "LSTeam" then 
            do:
                find buf-LSTeam no-lock where buf-LSTeam.ID = buf-TransactionDetail.PatronLinkID no-error.
                if available buf-LSTeam then assign
                        buf-TransactionDetail.FirstName = buf-LSTeam.TeamName
                        buf-TransactionDetail.LastName  = buf-LSTeam.TeamName.
            end.
            else 
            do:
                find buf-Member no-lock where buf-Member.ID = buf-TransactionDetail.PatronLinkID no-error.
                if available buf-Member then assign
                        buf-TransactionDetail.FirstName = buf-Member.FirstName
                        buf-TransactionDetail.LastName  = buf-Member.LastName.
            end.
        end.        
    
    end.

end procedure.

procedure UpdateSAStaff:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo.
  
    def buffer buf-Employee    for Employee.
    def buffer BufAccount for Account.
  
    do for buf-Employee transaction:     
        find buf-Employee exclusive-lock where rowid(buf-Employee) = row1 no-error no-wait.
        if available buf-Employee then 
        do:
            assign 
                buf-Employee.MemberLinkID = NEWLinkID.

            if ChangeStaffInfo then 
            do:
                find BufAccount no-lock where BufAccount.EntityNumber = ToHHNumber no-error.
                if available BufAccount then assign
                        buf-Employee.Address1              = BufAccount.PrimaryAddress1
                        buf-Employee.Address2              = BufAccount.PrimaryAddress2
                        buf-Employee.City                  = BufAccount.PrimaryCity
                        buf-Employee.State                 = BufAccount.PrimaryState
                        buf-Employee.ZipCode               = BufAccount.PrimaryZipcode
                        buf-Employee.PrimaryPhoneNumber    = BufAccount.PrimaryPhoneNumber
                        buf-Employee.PrimaryPhoneExtension = BufAccount.PrimaryPhoneExtension
                        buf-Employee.PrimaryPhoneType      = BufAccount.PrimaryPhoneType
                        buf-Employee.PrimaryEmailAddress   = if buf-Employee.PrimaryEmailAddress = "" then BufAccount.PrimaryEmailAddress else buf-Employee.PrimaryEmailAddress.
            end.
        end.
    end.

end procedure. 

procedure UpdateSAReceiptPayment2:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo.
    def buffer buf-PaymentTransaction for PaymentTransaction.
  
    do for buf-PaymentTransaction transaction:     
        find buf-PaymentTransaction exclusive-lock where rowid(buf-PaymentTransaction) = row1 no-error no-wait.
        if available buf-PaymentTransaction then assign buf-PaymentTransaction.PaymentMemberID = NEWLinkID.
    end.

end procedure. 

procedure UpdateSAMedicalDetail:
  
    def input parameter row1 as rowid.  
    def input parameter NEWLinkID as int64 no-undo.
  
    def buffer buf-HealthInfo for HealthInfo.
  
    do for buf-HealthInfo transaction:     
        find buf-HealthInfo exclusive-lock where rowid(buf-HealthInfo) = row1 no-error no-wait.
        if available buf-HealthInfo then assign buf-HealthInfo.MemberLinkID = NEWLinkID.
    end.

end procedure. 

procedure UpdateCYProviderReferral:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo.
    def buffer buf-CYProviderReferral for CYProviderReferral.
  
    do for buf-CYProviderReferral transaction:     
        find buf-CYProviderReferral exclusive-lock where rowid(buf-CYProviderReferral) = row1 no-error no-wait.
        if available buf-CYProviderReferral then assign buf-CYProviderReferral.MemberLinkID = NEWLinkID.
    end.

end procedure. 

procedure UpdateSADocument2:
  
    def input parameter inp1 as int64 no-undo.
    def input parameter NEWLinkID as int64 no-undo.
   
    def buffer buf-File for File.
  
    do for buf-File transaction:     
        find first buf-File exclusive-lock where buf-File.id = inp1 no-error no-wait.
        if available buf-File then assign
                buf-File.Filename = replace(buf-File.Filename, "\" + string(buf-File.ParentRecord) + "\", "\" + string(NEWLinkID) + "\")    
                buf-File.ParentRecord = NEWLinkID.
    end.

end procedure.

procedure UpdateSABlobFile2:
  
    def input parameter inp1 as int64 no-undo.
    def input parameter OLDLinkID as int64 no-undo.
    def input parameter NEWLinkID as int64 no-undo.
  
    def buffer buf-BinaryFile for BinaryFile.
    def buffer buf-File for File.
    
    do for buf-BinaryFile, buf-File transaction:     
        find first buf-BinaryFile exclusive-lock where buf-BinaryFile.id = inp1 no-error no-wait.
        if available buf-BinaryFile then 
        do:
            find first buf-File exclusive-lock where buf-File.FileName = buf-BinaryFile.FileName no-error no-wait.      
            if available buf-File then assign
                    buf-File.Filename = NewFileName
                    buf-File.ParentRecord = NEWLinkID.         

            assign 
                buf-BinaryFile.Filename   = NewFileName
                buf-BinaryFile.FolderName = replace(buf-BinaryFile.FolderName, "\" + string(OLDLinkID) + "\","\" + string(NEWLinkID) + "\").
        end.
    end.

end procedure. 

procedure UpdateCYProviderEnrolleeSchedule:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
  
    def buffer buf-CYProviderEnrolleeSchedule for CYProviderEnrolleeSchedule.
  
    do for buf-CYProviderEnrolleeSchedule transaction:     
        find buf-CYProviderEnrolleeSchedule exclusive-lock where rowid(buf-CYProviderEnrolleeSchedule) = row1 no-error no-wait.
        if available buf-CYProviderEnrolleeSchedule then 
        do: 
            if buf-CYProviderEnrolleeSchedule.EntityNumber = FromHHnumber then buf-CYProviderEnrolleeSchedule.EntityNumber = ToHHnumber.
            assign 
                buf-CYProviderEnrolleeSchedule.MemberLinkID = NEWLinkID.
        end.
    end.

end procedure. 

procedure UpdateCYWaitlist2:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
  
    def buffer buf-CYWaitlist for CYWaitlist.
  
    do for buf-CYWaitlist transaction:     
        find buf-CYWaitlist exclusive-lock where rowid(buf-CYWaitlist) = row1 no-error no-wait.
        if available buf-CYWaitlist then 
        do: 
            if buf-CYWaitlist.EntityNumber = FromHHnumber then buf-CYWaitlist.EntityNumber = ToHHnumber.
            assign 
                buf-CYWaitlist.MemberLinkID = NEWLinkID.
        end.
    end.

end procedure. 

procedure UpdateGRTournamentPlayer:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo.
    def input parameter NewhouseholdLink as int no-undo.
  
    def buffer buf-GRTournament for GRTournamentPlayer.
  
    do for buf-GRTournament transaction:     
        find buf-GRTournament exclusive-lock where rowid(buf-GRTournament) = row1 no-error no-wait.
        if available buf-GRTournament then assign
                buf-GRTournament.EntityNumber = NewhouseholdLink
                buf-GRTournament.MemberLinkID    = NEWLinkID.
    end.

end procedure. 
procedure UpdateSABillingDetail2:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
    def buffer buf-InvoiceLineItem for InvoiceLineItem.
  
    do for buf-InvoiceLineItem transaction:     
        find buf-InvoiceLineItem exclusive-lock where rowid(buf-InvoiceLineItem) = row1 no-error no-wait.
        if available buf-InvoiceLineItem then 
        do:  
            if buf-InvoiceLineItem.EntityNumber = FromHHnumber then buf-InvoiceLineItem.EntityNumber = ToHHnumber.
            assign 
                buf-InvoiceLineItem.MemberLinkID = NEWLinkID.
        end.
    end.

end procedure. 

procedure UpdatePSSerialTicket:
  
    def input parameter row1 as rowid.
    def input parameter oldLinkID as int64 no-undo. 
    def input parameter NEWLinkID as int64 no-undo. 
    def buffer buf-PSSerialTicket for PSSerialTicket.
  
    do for buf-PSSerialTicket transaction:     
        find buf-PSSerialTicket exclusive-lock where rowid(buf-PSSerialTicket) = row1 no-error no-wait.
        if available buf-PSSerialTicket then 
        do:  
            if buf-PSSerialTicket.EntityNumber = FromHHnumber then buf-PSSerialTicket.EntityNumber = ToHHnumber.
      
            if buf-PSSerialTicket.MemberLinkID = oldLinkID then buf-PSSerialTicket.MemberLinkID = NEWLinkID.
        end.  
    end.

end procedure. 

procedure UpdateSAWaiverHistory2:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
  
    def buffer buf-WaiverLog for WaiverLog.
  
    do for buf-WaiverLog transaction:     
        find buf-WaiverLog exclusive-lock where rowid(buf-WaiverLog) = row1 no-error no-wait.
        if available buf-WaiverLog then 
        do:  
            if buf-WaiverLog.EntityNumber = FromHHnumber then buf-WaiverLog.EntityNumber = ToHHnumber.
            buf-WaiverLog.ParentRecord = NEWLinkID.
        end.  
    end.

end procedure. 

procedure UpdateSAPaymentHistory3:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
  
    def buffer buf-PaymentLog for PaymentLog.
  
    do for buf-PaymentLog transaction:     
        find buf-PaymentLog exclusive-lock where rowid(buf-PaymentLog) = row1 no-error no-wait.
        if available buf-PaymentLog then 
        do:
            if buf-PaymentLog.EntityNumber = FromHHnumber then buf-PaymentLog.EntityNumber = ToHHnumber. 
       
            buf-PaymentLog.MemberLinkID = NEWLinkID.
        end.  
    end.

end procedure. 

procedure UpdateSARefund2:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
  
    def buffer buf-Reversal for Reversal.
  
    do for buf-Reversal transaction:     
        find buf-Reversal exclusive-lock where rowid(buf-Reversal) = row1 no-error no-wait.
        if available buf-Reversal then 
        do:
            if buf-Reversal.EntityNumber = FromHHnumber then buf-Reversal.EntityNumber = ToHHnumber. 
            assign
                buf-Reversal.MemberLinkID = NEWLinkID.
        end.
    end.

end procedure. 

procedure DeleteSAHouseholdAddress:
  
    def input parameter row1 as rowid.
  
    def buffer buf-AccountAddress for AccountAddress.
  
    do for buf-AccountAddress transaction:     
        find buf-AccountAddress exclusive-lock where rowid(buf-AccountAddress) = row1 no-error no-wait.
        if available buf-AccountAddress then delete buf-AccountAddress.
    end.

end procedure. 

procedure UpdateSAShotDetail:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo.
    def buffer buf-ImmunizationRecord for ImmunizationRecord.
  
    do for buf-ImmunizationRecord transaction:     
        find buf-ImmunizationRecord exclusive-lock where rowid(buf-ImmunizationRecord) = row1 no-error no-wait.
        if available buf-ImmunizationRecord then assign buf-ImmunizationRecord.MemberLinkID = NEWLinkID.
    end.

end procedure. 

procedure DeleteSAShotDetail:
  
    def input parameter row1 as rowid.
  
    def buffer buf-ImmunizationRecord for ImmunizationRecord.
  
    do for buf-ImmunizationRecord transaction:     
        find buf-ImmunizationRecord exclusive-lock where rowid(buf-ImmunizationRecord) = row1 no-error no-wait.
        if available buf-ImmunizationRecord then delete buf-ImmunizationRecord.
    end.

end procedure.

procedure UpdateSACrossReference:
  
    def input parameter row1 as rowid.
    def input parameter NEWLinkID as int64 no-undo. 
  
    def buffer buf-EntityLink for EntityLink.
  
    do for buf-EntityLink transaction:     
        find buf-EntityLink exclusive-lock where rowid(buf-EntityLink) = row1 no-error no-wait.
        if available buf-EntityLink then 
        do:
            if buf-EntityLink.EntityNumber = FromHHnumber then buf-EntityLink.EntityNumber = ToHHnumber. 
            assign 
                buf-EntityLink.MemberLinkID = NEWLinkID.
        end.
    end.

end procedure. 

procedure DeleteSACrossReference:
  
    def input parameter row1 as rowid.
  
    def buffer buf-EntityLink for EntityLink.
  
    do for buf-EntityLink transaction:     
        find buf-EntityLink exclusive-lock where rowid(buf-EntityLink) = row1 no-error no-wait.
        if available buf-EntityLink then delete buf-EntityLink.
    end.

end procedure. 

procedure UpdateRelationship2:
  
    def input parameter inpid1 as int64 no-undo.
    def input parameter inpid2 as int64 no-undo.
    def input parameter linkOrder as int no-undo.
    def buffer buf-Relationship for Relationship.
  
    do for buf-Relationship transaction:     
        find buf-Relationship exclusive-lock where buf-Relationship.id = inpid1 no-error no-wait.
        if available buf-Relationship then assign 
                buf-Relationship.ParentTableID = ToHHID
                buf-Relationship.childtableid  = inpid2
                buf-Relationship.Order         = linkOrder. 
    end.

end procedure. 

procedure UpdateRelationship3:
  
    def input parameter inpID as int64 no-undo. 
    def input parameter inpTOID as int64 no-undo. 
    def buffer buf-Relationship for Relationship.
  
    do for buf-Relationship transaction:     
        find buf-Relationship exclusive-lock where buf-Relationship.id =  inpID no-error no-wait.
        if available buf-Relationship then 
        do: 
            assign
                buf-Relationship.childtableID = inpTOID.  
            if buf-Relationship.ParentTableID = FromHHID then assign
                    buf-Relationship.Primary       = no /***Can NOT have two primary members in same HH ***/
                    buf-Relationship.ParentTableID = ToHHID.
        end.
    end.

end procedure. 
procedure UpdateRelationship:
  
    def input parameter inpID as int64 no-undo. 
    define input parameter linkOrder as int no-undo.
    define input parameter relationship as char no-undo.
  
    def buffer buf-Relationship for Relationship.
  
    do for buf-Relationship transaction:     
        find buf-Relationship exclusive-lock where buf-Relationship.id =  inpID no-error no-wait.
        if available buf-Relationship then assign
                buf-Relationship.Primary       = no /***Can NOT have two primary members in same HH ***/
                buf-Relationship.ParentTableID = ToHHID
                buf-Relationship.Order         = linkOrder
                buf-Relationship.Relationship  = relationship. 
 
    end.
end procedure. 

procedure DeleteRelationship:
    def input parameter inpid as int64 no-undo.
    def buffer buf-Relationship for Relationship.
  
    do for buf-Relationship transaction:
        find buf-Relationship exclusive-lock where buf-Relationship.id = inpid no-error no-wait.
        if available buf-Relationship then delete buf-Relationship.
    end.
end procedure.

procedure othersalinks:
  
    def input parameter InpRemoveId as int64 no-undo.
    def input parameter InpToId as int64 no-undo.
    def input parameter InpLinkSkipId as int64 no-undo.
  
    def buffer buf-Relationship for Relationship.
  
    for each buf-Relationship no-lock where buf-Relationship.ChildTableID = InpRemoveId:
        if buf-Relationship.id <> InpLinkSkipId then 
        do:
            run updatesalink3 (buf-Relationship.id,InpToId). 
        end.
    end.

end procedure. 

procedure RemoveMember:
  
    def input parameter InpRemoveId as int64 no-undo.
    def input parameter InpToId as int64 no-undo.
    def input parameter InpLinkSkipId as int64 no-undo.
   
    def buffer buf-Member    for Member.
    def buffer bufNew-Member for Member.
  
    find first bufNew-Member no-lock where bufNew-Member.id = InpToID no-error.
    run othersalinks(InpRemoveId,InpToId,InpLinkSkipId).
   
    if available bufNew-Member then 
    do for buf-Member transaction:     
        find buf-Member exclusive-lock where buf-Member.id = InpRemoveId no-error no-wait.
    
        if available buf-Member then 
        do: 
            run create-log ("From Household: " + string(FromHHNumber) +
                "  To Household: " + string(ToHHNumber) + 
                "  Option: " + if MergeOption = "transfer"
                then "Transfer" else if MergeOption = "fullmerge" then "Full Merge"
                else "Partial Merge",
                "Person Name = "  + trueval(buf-Member.firstname) + " " + trueval(buf-Member.lastname) ,
                "ID Value = " + trueval(string(buf-Member.id)),
                "Person Combined With = "  + trueval(bufNew-Member.firstname) + " " + trueval(bufNew-Member.lastname) + 
                ", ID Value = " + trueval(string(bufNew-Member.id)),
                "DeletedMember").
            delete buf-Member.
        end.
    end.

end procedure. 

procedure RemoveLSTeam:
  
    def input parameter InpRemoveId as int64 no-undo.
    def input parameter InpToId as int64 no-undo.
    def input parameter InpLinkSkipId as int64 no-undo.
   
    def buffer buf-LSTeam    for LSTeam.
    def buffer bufNew-LSTeam for LSTeam.
  
    find first bufNew-LSTeam no-lock where bufNew-LSTeam.id = InpToID no-error.
    run othersalinks(InpRemoveId,InpToId,InpLinkSkipId).
   
    if available bufNew-LSTeam then 
    do for buf-LSTeam transaction:     
        find buf-LSTeam exclusive-lock where buf-LSTeam.id = InpRemoveId no-error no-wait.
    
        if available buf-LSTeam then 
        do: 
            run create-log ("From Household: " + string(FromHHNumber) +
                "  To Household: " + string(ToHHNumber) + 
                "  Option: " + if MergeOption = "transfer"
                then "Transfer" else if MergeOption = "fullmerge" then "Full Merge"
                else "Partial Merge",
                "Team Name = "  + buf-LSTeam.TeamName,"ID Value = " + string(buf-LSTeam.id),
                "Team Combined With = "  + bufNew-LSTeam.TeamName + ", ID Value = " + string(bufNew-LSTeam.id),
                "DeletedLSTeam").
            delete buf-LSTeam.
        end.
    end.

end procedure. 

procedure UpdatebufMember:
  
    def input parameter row1 as rowid.
  
    def var NewID      as int64 no-undo.
    def var primePhone as char.
    def var primeemail as char.
  
    def buffer buf-Member       for Member.
    def buffer buf-PhoneNumber        for PhoneNumber.
    def buffer buf-EmailContact for EmailContact.
  
    assign 
        NewID = 0.
    do for buf-Member transaction:     
        find buf-Member exclusive-lock where rowid(buf-Member) = row1 no-error no-wait.
        if available buf-Member then 
        do:
            assign
                NewID                          = buf-Member.id
                buf-Member.ScholarshipAmount = (if buf-Member.ScholarshipAmount = ? then 0 else buf-Member.ScholarshipAmount) +
          (if Member.ScholarshipAmount = ? then 0 else Member.ScholarshipAmount)
                buf-Member.CreditBookAmount  = (if buf-Member.CreditBookAmount = ? then 0 else buf-Member.CreditBookAmount) + 
          (if Member.CreditBookAmount = ? then 0 else Member.CreditBookAmount)
                buf-Member.AllowCreditBook   = if buf-Member.CreditBookAmount gt 0 then yes else no.
            if buf-Member.primaryphonenumber = "" then assign
                    buf-Member.primaryphoneextension = Member.PrimaryPhoneExtension 
                    buf-Member.primaryphonetype      = Member.PrimaryPhoneType 
                    buf-Member.primaryphonenumber    = Member.primaryphonenumber.
            primePhone = buf-Member.primaryphonenumber.
            if buf-Member.primaryemailaddress = "" then buf-Member.primaryemailaddress = Member.primaryemailaddress.
            primeemail = buf-Member.primaryemailaddress. 
            if photo-check then 
            do:
                find first BinaryFile no-lock where BinaryFile.Filename = "\Photos\" + string(buf-Member.PhotoIDNumber) + ".jpg" no-error.         
  
                if not available BinaryFile then assign buf-Member.PhotoIDNumber = Member.PhotoIDNumber.
            end.  /*** CHECK FOR PHOTO ON TO MEMBER THAT ALREADY EXISTS ***/     
        end.    
    end.
    if newid gt 0 then 
    do:
        for each PhoneNumber no-lock where PhoneNumber.ParentRecord = Member.id
            and PhoneNumber.ParentTable = "Member":
            for first buf-PhoneNumber no-lock where buf-PhoneNumber.ParentRecord = newid and 
                buf-PhoneNumber.ParentTable = "Member" and 
                buf-PhoneNumber.phonenumber = PhoneNumber.PhoneNumber:
                run purgesaphone (PhoneNumber.id).        
            end.
            if not available buf-PhoneNumber then
                run updatesaphone (PhoneNumber.id, NewID, if PhoneNumber.PhoneNumber = primePhone then yes else no).
        end.
        for each EmailContact no-lock where EmailContact.ParentRecord = Member.id
            and EmailContact.ParentTable = "Member":
            for first buf-EmailContact no-lock where buf-EmailContact.ParentRecord = newid and 
                buf-EmailContact.ParentTable = "Member" and 
                buf-EmailContact.EmailAddress = EmailContact.EmailAddress:
                run purgeEmailContact (EmailContact.id).
            end.
            if not available buf-EmailContact then 
                run updateEmailContact (EmailContact.id, NewID, if EmailContact.EmailAddress = primePhone then yes else no).
        end.
    
    end.
end procedure.

procedure updateEmailContact:
    def input parameter inpid as int64 no-undo.
    def input parameter newinpid as int64 no-undo.
    def input parameter prime as log.
    def buffer buf-EmailContact for EmailContact .
  
    do for buf-EmailContact transaction:
        find buf-EmailContact exclusive-lock where buf-EmailContact.id = inpid no-error no-wait.
        if available buf-EmailContact then assign
                buf-EmailContact.ParentRecord            = newinpid
                buf-EmailContact.primaryEmailAddress = prime.
    end.
end procedure.

procedure updateSAPrimaryEmailAddress:
    define input parameter  inpid as int64 no-undo.  
    define input parameter newEmailAdress as char no-undo.
    define input parameter newSalinkPersonId as int64 no-undo.
    def buffer buf-EmailContact for EmailContact.
  
    do for buf-EmailContact transaction:
        find buf-EmailContact exclusive-lock where buf-EmailContact.id = inpid no-error no-wait.
        if available buf-EmailContact then assign
                buf-EmailContact.MemberLinkID = newSalinkPersonId
                buf-EmailContact.EmailAddress   = newEmailAdress.
    end.
end procedure.

procedure purgeEmailContact:
    def input parameter inpid as int64 no-undo.
    def buffer buf-EmailContact for EmailContact.
  
    do for buf-EmailContact transaction:
        find buf-EmailContact exclusive-lock where buf-EmailContact.id = inpid no-error no-wait.
        if available buf-EmailContact then delete buf-EmailContact.
    end.
end procedure.

procedure updatesaphone:
    def input parameter inpid as int64 no-undo.
    def input parameter newinpid as int64 no-undo.
    def input parameter prime as log.
    def buffer buf-PhoneNumber for PhoneNumber.
  
    do for buf-PhoneNumber transaction:
        find buf-PhoneNumber exclusive-lock where buf-PhoneNumber.id = inpid no-error no-wait.
        if available buf-PhoneNumber then assign
                buf-PhoneNumber.ParentRecord           = newinpid
                buf-PhoneNumber.primaryphonenumber = prime.
    end.
end procedure.

procedure updatesaphoneprimary:
    define input parameter inpid as int64 no-undo.  
    define input parameter newPhone as char no-undo.
    define input parameter newSalinkPersonId as int64 no-undo.
    define input parameter phonetype as char no-undo.
    define input parameter extension as char no-undo.
    def buffer buf-PhoneNumber for PhoneNumber.
  
    do for buf-PhoneNumber transaction:
        find buf-PhoneNumber exclusive-lock where buf-PhoneNumber.id = inpid no-error no-wait.
        if available buf-PhoneNumber then assign
                buf-PhoneNumber.MemberLinkID = newSalinkPersonId
                buf-PhoneNumber.PhoneNumber    = newPhone
                buf-PhoneNumber.PhoneType      = phonetype
                buf-PhoneNumber.Extension      = extension.
    end.
end procedure.

procedure purgesaphone:
    def input parameter inpid as int64 no-undo.
    def buffer buf-PhoneNumber for PhoneNumber.
  
    do for buf-PhoneNumber transaction:
        find buf-PhoneNumber exclusive-lock where buf-PhoneNumber.id = inpid no-error no-wait.
        if available buf-PhoneNumber then delete buf-PhoneNumber.
    end.
end procedure.

procedure UpdateMTCuslog: 
    def input parameter InpRowid as rowid no-undo.
    def buffer BufMTCuslog for MTCuslog. 
  
    do for BufMTCuslog transaction: 
        find first BufMTCuslog exclusive-lock where rowid(BufMTCuslog) = inprowid no-error no-wait.
        if available BufMTCuslog then 
        do: 
            BufMTCuslog.CustomerNumber = ToHHnumber.
        end.
    end. 
end procedure.

procedure UpdateMTInvoice: 
    def input parameter InpRowid as rowid no-undo.
    def buffer BufMTInvoice for MTInvoice. 
  
    do for BufMTInvoice transaction: 
        find first BufMTInvoice exclusive-lock where rowid(BufMTInvoice) = inprowid no-error no-wait.
        if available BufMTInvoice then 
        do: 
            BufMTInvoice.CustomerNumber = ToHHnumber.
        end.
    end. 
end procedure.

procedure UpdateSaFeeHistoryStartingBalanceRecords: 

    if mergeoption ne "fullmerge" then 
    do:
        for first ChargeHistory no-lock where 
            ChargeHistory.RecordStatus eq "Starting Balance" and
            ChargeHistory.ParentRecord eq FromHHID and 
            ChargeHistory.ParentTable eq "Account":
            run deleteChargeHistory (rowid(ChargeHistory)).  
        end.    
        run CreateSAFeeHistory (FromHHID, FromHHNumber).
    end.

    for first ChargeHistory no-lock where 
        ChargeHistory.RecordStatus eq "Starting Balance" and
        ChargeHistory.ParentRecord eq ToHHID and 
        ChargeHistory.ParentTable eq "Account":
        run deleteChargeHistory (rowid(ChargeHistory)).  
    end.  
            
    run CreateSAFeeHistory (ToHHID, ToHHNumber).    
         
end procedure.

procedure DeleteSAFeeHistory:
  
    def input parameter row1 as rowid.
  
    def buffer bufChargeHistory for ChargeHistory.
  
    do for bufChargeHistory transaction:     
        find bufChargeHistory exclusive-lock where rowid(bufChargeHistory) = row1 no-error no-wait.
        if available bufChargeHistory then delete bufChargeHistory.
    end.

end procedure. 

procedure CreateSAFeeHistory:
    def input parameter inpid as int64 no-undo.
    def input parameter inpHH as int no-undo.
  
    def var HHDRbal as dec no-undo. 
  
    def buffer bufChargeHistory for ChargeHistory.
  
    run business/CalcHouseholdBalance.p (inpHH, "", 0, yes, "OverallBalance", no, output HHDRbal).
  
    do for bufChargeHistory transaction:   
        create bufChargeHistory.
        assign
            bufChargeHistory.AccrualAmount       = 0
            bufChargeHistory.BillDate            = ?                  
            bufChargeHistory.CashDrawer          = 0               
            bufChargeHistory.DiscountAmount      = 0             
            bufChargeHistory.FeeAmount           = if HHDRbal gt 0 then HHDRbal else 0                  
            bufChargeHistory.FeePaid             = if HHDRbal lt 0 then abs(HHDRbal) else 0                  
            bufChargeHistory.LogDate             = today                     
            bufChargeHistory.LogTime             = time
            bufChargeHistory.MiscInformation     = ""                  
            bufChargeHistory.NewFeePaid          = 0                  
            bufChargeHistory.NewPayCodes         = ""                  
            bufChargeHistory.NewPayHouseholdList = ""         
            bufChargeHistory.NewTaxPaid          = 0                 
            bufChargeHistory.Notes               = "Running Balance Start Record"                        
            bufChargeHistory.OrderNumber         = 1                 
            bufChargeHistory.ParentRecord            = inpid                 
            bufChargeHistory.ParentTable         = "Account"                 
            bufChargeHistory.PayCode             = ""                  
            bufChargeHistory.PaymentHousehold    = inphh             
            bufChargeHistory.Quantity            = 1                     
            bufChargeHistory.ReceiptNumber       = 0                
            bufChargeHistory.RecordStatus        = "Starting Balance"                
            bufChargeHistory.SpecialLinkID       = 0              
            bufChargeHistory.SpecialLinkTable    = ""           
            bufChargeHistory.TaxAmount           = 0              
            bufChargeHistory.TaxPaid             = 0           
            bufChargeHistory.TimeCount           = 1                 
            bufChargeHistory.UserName            = signon()                  
            bufChargeHistory.WordIndex           = "".          
    end.
end procedure.

procedure UpdateSAContract:
    def input parameter row1 as rowid.
  
    def buffer buf-Agreement for Agreement.
  
    do for buf-Agreement transaction:     
        find buf-Agreement exclusive-lock where rowid(buf-Agreement) = row1 no-error no-wait.
        if available buf-Agreement then assign Agreement.EntityNumber = ToHHNumber.
    end.
end procedure.

procedure WebUserNameAdjustments:
    define input parameter i_fromPersonID as int64 no-undo.
    define input parameter i_toPersonID as int64 no-undo.
    define input parameter i_fromRelationshipID as int64 no-undo.
    define input parameter i_toSalinkID as int64 no-undo.
    define input parameter i_mergeOption as char no-undo.
  
    define buffer bufFromWebUserName for WebUserName.
    define buffer bufToWebUserName   for WebUserName.
    define buffer bufToRelationship        for Relationship.
  
    find first bufFromWebUserName no-lock where bufFromWebUserName.ParentRecord = i_fromPersonID no-error.
    find first bufToWebUserName no-lock where bufToWebUserName.ParentRecord = i_toPersonID no-error.
  
    if available bufFromWebUsername and i_mergeoption ne "Do Not Transfer/Merge" then 
    do:
        if available bufToWebUserName then 
        do:
            /* If "To" household also has a webusername, keep most recent one, or if both are unused, keep the "To" WebUserName */
            if bufFromWebUserName.LastLoginDateTime ne ? and (bufFromWebUserName.LastLoginDateTime gt bufToWebUserName.LastLoginDateTime) then 
            do:
                run DeleteWebUserName(rowid(bufToWebUserName)).
                run UpdateWebUserNameParentID(rowid(bufFromWebUserName), i_toPersonID). /* Update the "from" webusername record with the "to" person's ID */
            end.
            else
                run DeleteWebUserName(rowid(bufFromWebUsername)).
        end.
        else 
        do:
            /* if "To" person doesn't have a webusername, keep the "from" webusername, just update the WebUserName record */
            run UpdateWebUserNameParentID(rowid(bufFromWebUsername), i_toPersonID).
            do for bufToRelationship transaction:
                /* If from person has webusername but to doesn't, take away "account management" of to person if they aren't primary,
                   and activate the account since the Relationship record will be different */
                find first bufToRelationship exclusive-lock where bufToRelationship.ID = i_toSalinkID no-wait no-error.
                if available bufTORelationship then 
                do:
                    if bufTOSalink.Relationship = "Primary Guardian" then bufTOSalink.WebPermissions = "Account Management".
                    else bufTOSalink.WebPermissions = "".
                    bufTOSalink.WebRecordStatus = "Active".
                end.
            end.
        end.
    end.
/* If the "To" person has a WebUserName but the "From" doesn't, nothing needs to be done */
end procedure.

procedure DeleteWebUserName:
    define input parameter i_rowid as rowid no-undo.
    define buffer bufWebUserName for WebUserName.
  
    do for bufWebUserName transaction:
        find first bufWebUserName exclusive-lock where rowid(bufWebUserName) = i_rowid no-error no-wait.
        if available bufWebUserName then delete bufWebUserName.
    end.
end.

procedure UpdateWebUserNamePermissions:
    define input parameter i_rowid as rowid no-undo.
    define buffer bufRelationship for Relationship.
  
    do for bufRelationship transaction:
        find first bufRelationship exclusive-lock where rowid(bufRelationship) = i_rowid no-error no-wait.
        if available bufRelationship then bufRelationship.WebPermissions = "".
    end.
end.

procedure UpdateWebUserNameParentID:
    define input parameter i_rowid as rowid no-undo.
    define input parameter i_parentID as int64 no-undo.
    define buffer bufWebUserName for WebUserName.
  
    do for bufWebUserName transaction:
        find first bufWebUserName exclusive-lock where rowid(bufWebUserName) = i_rowid no-error no-wait.
        if available bufWebUserName then bufWebUserName.ParentRecord = i_parentID.
    end.
end.