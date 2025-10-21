/*************************************************************************TEST
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "changeWebUserNameToPrimary" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Change WebUserName from child to primary guardian"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------

   Author(s)   : michaelzr
   Created     : 3/12/25
   Notes       : Code pulled and modified from bulkSendWebInvite.p

 ----------------------------------------------------------------------*/
 
/*************************************************************************
                                DEFINITIONS
*************************************************************************/

block-level on error undo, throw.

using Business.Library.Model.BO.HouseholdBO.HouseholdBO from propath.
using Business.Library.Model.BO.PersonBO.PersonBO from propath.
using Business.Library.Model.BO.WebInviteBO.WebInvitesBO from propath.
using Business.Library.Model.BO.LinkBO.LinkBO from propath.
using Business.Library.Model.DAO.Core.DAO from propath.
using Business.Library.Validator.EmailAddressFormatValidator from propath.
using Business.Library.Results from propath.

{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i}

define stream   ex-port.
define variable inpfile-num         as integer      no-undo.
define variable inpfile-loc         as character    no-undo.
define variable counter             as integer      no-undo.
define variable ixLog               as integer      no-undo. 
define variable logfileDate         as date         no-undo.
define variable logfileTime         as integer      no-undo.
define variable numUserNamesChanged as integer      no-undo. 
define variable numPermissions      as integer      no-undo.
define variable accountStatus       as character    no-undo.
define variable childAccountStatus  as character    no-undo.
define variable skipHouseholds      as character    no-undo.
define variable permissionsUpdated  as logical      no-undo.
define variable WebUserUpdated      as logical      no-undo.
define variable ix                  as integer      no-undo.
define variable LogOnly             as logical      no-undo init false.

define variable oHouseholdBO        as HouseholdBO  no-undo.
define variable oPersonBO           as PersonBO     no-undo.
define variable oLinkBO             as LinkBO       no-undo.
define variable oWebInvitesBO       as WebInvitesBO no-undo.

define variable oChildPersonBO      as PersonBO     no-undo.
define variable oChildLinkBO        as LinkBO       no-undo.
define variable oChildWebInvitesBO  as WebInvitesBO no-undo.

assign
    LogOnly             = if {&ProgramName} matches "*LogOnly*" then true else false
    inpfile-num         = 1
    logfileDate         = today
    logfileTime         = time 
    numUserNamesChanged = 0
    numPermissions      = 0
    permissionsUpdated  = no
    skipHouseholds      = "999999999".


/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* FIND ALL INTERNAL AND MODEL HOUSEHOLDS */
profilefield-loop:
for each CustomField no-lock where CustomField.FieldName = "InternalHousehold" or CustomField.FieldName begins "ModelHousehold":
    if getString(CustomField.FieldValue) = "" then next profilefield-loop.
    do ix = 1 to num-entries(getString(CustomField.FieldValue)):
        skipHouseholds = uniquelist(entry(ix,getString(CustomField.FieldValue)),skipHouseholds,",").
    end. 
end.

/* CREATE LOG FILE FIELD HEADERS */
/*run put-stream (                   */
/*    "Household Number," +          */
/*    "Primary Guardian Person ID," +*/
/*    "First Name," +                */
/*    "Last Name," +                 */
/*    "Primary Guardian," +          */
/*    "Email Address," +             */
/*    "Email Verified," +            */
/*    "Email Opted In," +            */
/*    "WebTrac Username," +          */
/*    "Has Web Account," +           */
/*    "Has Web Access," +            */
/*    "Has Web Invites," +           */
/*    "Account Status," +            */
/*    "Permissions," +               */
/*    "Permissions Added?," +        */
/*    "Family Member Person ID," +   */
/*    "First Name," +                */
/*    "Last Name," +                 */
/*    "Primary Guardian," +          */
/*    "Email Address," +             */
/*    "Email Verified," +            */
/*    "Email Opted In," +            */
/*    "WebTrac Username," +          */
/*    "Has Web Account," +           */
/*    "Has Web Access," +            */
/*    "Has Web Invites," +           */
/*    "Account Status," +            */
/*    "Permissions,").               */

run put-stream("WebUserName.ID," +
               "Original WebUserName.ParentRecord," +
               "New WebUserName.ParentRecord," +
               "Child Relationship.ID," +
               "Original Child Relationship.WebLastLoginDateTime," +
               "New Child Relationship.WebLastLoginDateTime," +
               "Parent Relationship.ID," +
               "Original Parent Relationship.WebLastLoginDateTime," +
               "New Parent Relationship.WebLastLoginDateTime,").
    
/* HOUSEHOLD LOOP */   
hh-loop:
for each Account no-lock where Account.RecordStatus = "Active":
    
    /* SKIP GUEST AND ALL INTERNAL AND MODEL HOUSEHOLDS */
    if lookup(string(Account.EntityNumber),skipHouseholds) > 0 then next hh-loop.
   
    /* LOOP THROUGH ALL MEMBERS OF THE HOUSEHOLD */
    member-loop:
    for each Relationship no-lock where Relationship.ParentTable = "Account"
        and Relationship.ParentTableID = Account.ID
        and Relationship.ChildTable = "Member"
        and Relationship.Primary = true:
            
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error.
        if not available Member or Member.RecordStatus <> "Active" or isEmpty(Member.PrimaryEmailAddress) then next member-loop.

        assign
            oHouseholdBO       = HouseholdBO:GetByHouseholdID(Account.ID)       /* GRABS THE HOUSEHOLD OBJECT */
            oPersonBO          = PersonBO:GetByID(Member.ID)                      /* GRABS THE FAMILY MEMBER OBJECT */
            oLinkBO            = oPersonBO:GetLinkToRecord(oHouseholdBO:Household)  /* GRABS THE SALINK OBJECT */
            permissionsUpdated = no
            WebUserUpdated     = no.
        
        if not valid-object(oHouseholdBO) or not valid-object(oPersonBO) or not valid-object(oLinkBO) then next member-loop.
        
        /* GRAB THE WEBINVITE INFORMATION */
        oWebInvitesBO = new WebInvitesBO(oHouseholdBO:HouseholdNumber, oPersonBO:MemberNumber).
       
        /* IF THEY DO NOT HAVE ACCOUNT MANAGEMENT PERMISSIONS, SET THEM */
        if oPersonBO:IsPrimaryGuardianForHousehold(oHouseholdBO) and isEmpty(oLinkBO:link:Vals:WebPermissions) then 
        do:
            assign 
                numPermissions     = numPermissions + 1
                permissionsUpdated = yes.
                
            /* SET WEB PERMISSIONS TO ACCOUNT MANAGEMENT */
            if not LogOnly then oLinkBO:setWebPermissions("Account Management").
        end.
        
        /* DETERMINE THE ACCOUNT STATUS */
        assign 
            accountStatus = (if oPersonBO:IsWebLockedOut() then "Locked Out"
            else if (not oPersonBO:HasWebAccount() or not oLinkBO:HasWebAccess()) and oWebInvitesBO:hasInvites() then "Invite Pending"
            else if not oPersonBO:HasWebAccount() or not oLinkBO:HasWebAccess() then "No Access"
            else "User Active").
            
        /* IF NO WEBTRAC ACCESS, SEND INVITE */
        if accountStatus <> "User Active" then run checkForActiveUser(Account.ID,Member.ID).
    
/*        /* LOG CHANGES */                                                                                             */
/*        if permissionsUpdated or WebUserUpdated then run put-stream("~"" +                                            */
/*                /*Household Number*/                                                                                  */
/*                string(oHouseholdBO:HouseholdNumber)                                                                  */
/*                + "~",~"" +                                                                                           */
/*                /*Primary Guardian Person ID*/                                                                        */
/*                string(oPersonBO:MemberNumber)                                                                        */
/*                + "~",~"" +                                                                                           */
/*                /*First Name*/                                                                                        */
/*                getString(oPersonBO:FirstName)                                                                          */
/*                + "~",~"" +                                                                                           */
/*                /*Last Name*/                                                                                         */
/*                getString(oPersonBO:LastName)                                                                           */
/*                + "~",~"" +                                                                                           */
/*                /*Primary Guardian*/                                                                                  */
/*                (if oPersonBO:IsPrimaryGuardianForHousehold(oHouseholdBO) then "Yes" else "No")                       */
/*                + "~",~"" +                                                                                           */
/*                /*Email Address*/                                                                                     */
/*                oPersonBO:Person:Vals:PrimaryEmailAddress                                                             */
/*                + "~",~"" +                                                                                           */
/*                /*Email Verified*/                                                                                    */
/*                (if oPersonBO:PrimaryEmailAddressVerified() then "Yes" else "No")                                     */
/*                + "~",~"" +                                                                                           */
/*                /*Email Opted In*/                                                                                    */
/*                (if oPersonBO:GetPrimaryEmailOptedIn() then "Yes" else "No")                                          */
/*                + "~",~"" +                                                                                           */
/*                /*WebTrac Username*/                                                                                  */
/*                (if oPersonBO:WebUserName:UserName = "" then "None" else oPersonBO:WebUserName:UserName)              */
/*                + "~",~"" +                                                                                           */
/*                /*Has Web Account*/                                                                                   */
/*                (if oPersonBO:HasWebAccount() then "Yes" else "No")                                                   */
/*                + "~",~"" +                                                                                           */
/*                /*Has Web Access*/                                                                                    */
/*                (if oLinkBO:HasWebAccess() then "Yes" else "No")                                                      */
/*                + "~",~"" +                                                                                           */
/*                /*Has Web Invites*/                                                                                   */
/*                (if oWebInvitesBO:hasInvites() then "Yes" else "No")                                                  */
/*                + "~",~"" +                                                                                           */
/*                /*Account Status*/                                                                                    */
/*                accountStatus                                                                                         */
/*                + "~",~"" +                                                                                           */
/*                /*Permissions*/                                                                                       */
/*                (if oLinkBO:link:Vals:WebPermissions = "" then "None" else oLinkBO:link:Vals:WebPermissions)          */
/*                + "~",~"" +                                                                                           */
/*                /*Permissions Added?*/                                                                                */
/*                (if permissionsUpdated then "Yes" else "")                                                            */
/*                + "~",~"" +                                                                                           */
/*                /*Family Member Person ID*/                                                                           */
/*                string(oChildPersonBO:MemberNumber)                                                                   */
/*                + "~",~"" +                                                                                           */
/*                /*First Name*/                                                                                        */
/*                getString(oChildPersonBO:FirstName)                                                                     */
/*                + "~",~"" +                                                                                           */
/*                /*Last Name*/                                                                                         */
/*                getString(oChildPersonBO:LastName)                                                                      */
/*                + "~",~"" +                                                                                           */
/*                /*Primary Guardian*/                                                                                  */
/*                (if oChildPersonBO:IsPrimaryGuardianForHousehold(oHouseholdBO) then "Yes" else "No")                  */
/*                + "~",~"" +                                                                                           */
/*                /*Email Address*/                                                                                     */
/*                oChildPersonBO:Person:Vals:PrimaryEmailAddress                                                        */
/*                + "~",~"" +                                                                                           */
/*                /*Email Verified*/                                                                                    */
/*                (if oChildPersonBO:PrimaryEmailAddressVerified() then "Yes" else "No")                                */
/*                + "~",~"" +                                                                                           */
/*                /*Email Opted In*/                                                                                    */
/*                (if oChildPersonBO:GetPrimaryEmailOptedIn() then "Yes" else "No")                                     */
/*                + "~",~"" +                                                                                           */
/*                /*WebTrac Username*/                                                                                  */
/*                (if oChildPersonBO:WebUserName:UserName = "" then "None" else oChildPersonBO:WebUserName:UserName)    */
/*                + "~",~"" +                                                                                           */
/*                /*Has Web Account*/                                                                                   */
/*                (if oChildPersonBO:HasWebAccount() then "Yes" else "No")                                              */
/*                + "~",~"" +                                                                                           */
/*                /*Has Web Access*/                                                                                    */
/*                (if oChildLinkBO:HasWebAccess() then "Yes" else "No")                                                 */
/*                + "~",~"" +                                                                                           */
/*                /*Has Web Invites*/                                                                                   */
/*                (if oChildWebInvitesBO:hasInvites() then "Yes" else "No")                                             */
/*                + "~",~"" +                                                                                           */
/*                /*Account Status*/                                                                                    */
/*                ChildAccountStatus                                                                                    */
/*                + "~",~"" +                                                                                           */
/*                /*Permissions*/                                                                                       */
/*                (if oChildLinkBO:link:Vals:WebPermissions = "" then "None" else oChildLinkBO:link:Vals:WebPermissions)*/
/*                + "~",").                                                                                             */
    end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Check Document Center for " + {&ProgramName} + "Log for a log of Records Updated","Number of WebUserName Records Updated: " + string(numUserNamesChanged),"Account Management Permissions Added: " + string(numPermissions),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* CHECK FOR ACTIVE USER */
procedure CheckForActiveUser:
    define input parameter HouseholdID as int64 no-undo.
    define input parameter PersonID as int64 no-undo.
    
    define buffer bufRelationship      for Relationship.
    define buffer bufAccount for Account.
    define buffer bufMember    for Member.
    
    find first bufAccount no-lock where bufAccount.ID = HouseholdID no-error.
    if available bufAccount then 
    do: 
        bufMember-loop:
        for each bufRelationship no-lock where bufRelationship.ParentTable = "Account"
            and BufRelationship.ParentTableID = BufAccount.ID
            and BufRelationship.ChildTable = "Member"
            and BufRelationship.Primary = false
            and bufRelationship.ChildTableID <> PersonID:
            
            find first BufMember no-lock where BufMember.ID = BufRelationship.ChildTableID no-error.
            if not available BufMember or BufMember.RecordStatus <> "Active" then next bufMember-loop.

            assign
                oChildPersonBO = PersonBO:GetByID(BufMember.ID)                         /* GRABS THE CHILD FAMILY MEMBER OBJECT */
                oChildLinkBO   = oChildPersonBO:GetLinkToRecord(oHouseholdBO:Household).  /* GRABS THE CHILD Relationship OBJECT */
        
            if not valid-object(oChildPersonBO) or not valid-object(oChildLinkBO) then next bufMember-loop.
        
            /* GRAB THE WEBINVITE INFORMATION */
            oChildWebInvitesBO = new WebInvitesBO(oHouseholdBO:HouseholdNumber, oChildPersonBO:MemberNumber).
        
            /* DETERMINE THE ACCOUNT STATUS */
            assign 
                ChildAccountStatus = (if oChildPersonBO:IsWebLockedOut() then "Locked Out"
                                else if (not oChildPersonBO:HasWebAccount() or not oChildLinkBO:HasWebAccess()) and oChildWebInvitesBO:hasInvites() then "Invite Pending"
                                else if not oChildPersonBO:HasWebAccount() or not oChildLinkBO:HasWebAccess() then "No Access"
                                else "User Active").
            
            /* IF NO WEBTRAC ACCESS, SEND INVITE */
            if ChildAccountStatus = "User Active" then 
            do:
                run changeWebUser(HouseholdID,bufMember.ID,PersonID).
                return.
            end.
        end.
    end.
end procedure.

/* CHANGE WEB USER */
procedure changeWebUser:
    define input parameter hhID as int64 no-undo.
    define input parameter childPersonID as int64 no-undo.
    define input parameter parentPersonID as int64 no-undo.
    define variable lastWebLogin    as datetime no-undo.
    define variable parentLastLogin as datetime no-undo.
    define buffer bufWebUserName  for WebUserName.
    define buffer bufMember     for Member.
    define buffer bufChildSALink  for Relationship.
    define buffer bufParentSALink for Relationship.
    
    do for bufWebUserName transaction:
        for first bufWebUserName exclusive-lock where bufWebUserName.ParentTable = "Member" and bufWebUserName.ParentRecord = childPersonID:
            assign 
                WebUserUpdated      = true
                numUserNamesChanged = numUserNamesChanged + 1.
            if not LogOnly then assign
                    bufWebUserName.ParentRecord = parentPersonID.
            for first bufChildSALink exclusive-lock where bufChildSALink.ChildTableID = childPersonID and bufChildSALink.ParentTableID = hhID:
                assign 
                    lastWebLogin = bufChildSALink.WebLastLoginDateTime.
                if not LogOnly then assign
                        bufChildSALink.WebLastLoginDateTime = ?.
                for first bufParentSALink exclusive-lock where bufParentSALink.ChildTableID = parentPersonID and bufParentSALink.ParentTableID = hhID:
                    assign 
                        parentLastLogin = bufParentSALink.WebLastLoginDateTime.
                    if not LogOnly then assign 
                            bufParentSALink.WebLastLoginDateTime = lastWebLogin.
                end.
            end.
            run put-stream("~"" +
                /*WebUserName.ID*/
                getString(string(bufWebUserName.ID))
                + "~",~"" +
                /*Original WebUserName.ParentRecord*/
                getString(string(childPersonID))
                + "~",~"" +
                /*New WebUserName.ParentRecord*/
                getString(string(parentPersonID))
                + "~",~"" +
                /*Child Relationship.ID*/
                getString(string(bufChildSALink.ID))
                + "~",~"" +
                /*Original Child Relationship.WebLastLoginDateTime*/
                getString(string(lastWebLogin))
                + "~",~"" +
                /*New Child Relationship.WebLastLoginDateTime*/
                getString(string(?))
                + "~",~"" +
                /*Parent Relationship.ID*/
                getString(string(bufParentSALink.ID))
                + "~",~"" +
                /*Original Parent Relationship.WebLastLoginDateTime*/
                getString(string(parentLastLogin))
                + "~",~"" +
                /*New Parent Relationship.WebLastLoginDateTime*/
                getString(string(lastWebLogin))
                + "~",").
        end.
    end.
end procedure.
    
/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".

    put stream ex-port inpfile-info format "X(1200)" skip.
    counter = counter + 1.
    if counter gt 40000 then
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
    define input parameter logDetail5 as character no-undo.
    
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
            bufActivityLog.Detail4       = logDetail4
            bufActivityLog.Detail5       = logDetail5.
    end.
end procedure.