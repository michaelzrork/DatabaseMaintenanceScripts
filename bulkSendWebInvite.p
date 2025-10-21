/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "bulkSendWebInvite" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Bulk send Web Invites to all users without WebTrac logins"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------

   Author(s)   : michaelzr
   Created     : 3/12/25
   Notes       : Code pulled and modified from WebAccountManagement.p

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
define variable inpfile-num        as integer      no-undo.
define variable inpfile-loc        as character    no-undo.
define variable counter            as integer      no-undo.
define variable ixLog              as integer      no-undo. 
define variable logfileDate        as date         no-undo.
define variable logfileTime        as integer      no-undo.
define variable numEmailsSent      as integer      no-undo. 
define variable numPermissions     as integer      no-undo.
define variable accountStatus      as character    no-undo.
define variable skipHouseholds     as character    no-undo.
define variable permissionsUpdated as logical      no-undo.
define variable inviteSent         as logical      no-undo.
define variable ix                 as integer      no-undo.

define variable oHouseholdBO       as HouseholdBO  no-undo.
define variable oPersonBO          as PersonBO     no-undo.
define variable oLinkBO            as LinkBO       no-undo.
define variable oWebInvitesBO      as WebInvitesBO no-undo.

assign
    inpfile-num        = 1
    logfileDate        = today
    logfileTime        = time 
    numEmailsSent      = 0
    numPermissions     = 0
    inviteSent         = no
    permissionsUpdated = no
    skipHouseholds     = "999999999".


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
run put-stream (
    "Household Number," +
    "HH Creation Date," +
    "HH Last Active Date," +
    "Person ID," +
    "First Name," +
    "Last Name," +
    "Primary Guardian," +
    "Email Address," +
    "Email Verified," +
    "Email Opted In," +
    "WebTrac Username," +
    "Has Web Account," +
    "Has Web Access," +
    "Has Web Invites," +
    "Account Status," +
    "Permissions," +
    "Permissions Added?," +
    "Invite Sent?,").
    
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
            oLinkBO            = oPersonBO:GetLinkToRecord(oHouseholdBO:Household)  /* GRABS THE RELATIONSHIP OBJECT */
            permissionsUpdated = no
            inviteSent         = no.
        
        if not valid-object(oHouseholdBO) or not valid-object(oPersonBO) or not valid-object(oLinkBO) then next member-loop.
        
        /* SKIP ANY FAMILY MEMBERS WITHOUT A VALID AND VERIFIED EMAIL ADDRESS */
        if not oPersonBO:PrimaryEmailAddressVerified() or not EmailAddressFormatValidator:valid(oPersonBO:Person:Vals:PrimaryEmailAddress) then next member-loop.
        
        /* GRAB THE WEBINVITE INFORMATION */
        oWebInvitesBO = new WebInvitesBO(oHouseholdBO:HouseholdNumber, oPersonBO:MemberNumber).
       
        /* IF THEY DO NOT HAVE ACCOUNT MANAGEMENT PERMISSIONS, SET THEM */
        if oPersonBO:IsPrimaryGuardianForHousehold(oHouseholdBO) and isEmpty(oLinkBO:link:Vals:WebPermissions) then 
        do:
            assign 
                numPermissions     = numPermissions + 1
                permissionsUpdated = yes.
                
            /* SET WEB PERMISSIONS TO ACCOUNT MANAGEMENT */
            oLinkBO:setWebPermissions("Account Management").
        end.
        
        /* DETERMINE THE ACCOUNT STATUS */
        assign 
            accountStatus = (if oPersonBO:IsWebLockedOut() then "Locked Out"
            else if (not oPersonBO:HasWebAccount() or not oLinkBO:HasWebAccess()) and oWebInvitesBO:hasInvites() then "Invite Pending"
            else if not oPersonBO:HasWebAccount() or not oLinkBO:HasWebAccess() then "No Access"
            else "User Active").
            
        /* IF NO WEBTRAC ACCESS, SEND INVITE */
        if accountStatus = "No Access" then run sendWebInvite(oHouseholdBO,oLinkBO,oPersonBO).
    
        /* LOG CHANGES */
        if permissionsUpdated or inviteSent then run put-stream("~"" +
                /*Household Number*/
                string(oHouseholdBO:HouseholdNumber)
                + "~",~"" +
                /*HH Creation Date*/
                getString(string(Account.CreationDate))
                + "~",~"" +
                /*HH Last Active Date*/
                getString(string(Account.LastActiveDate))
                + "~",~"" +
                /*Person ID*/
                string(oPersonBO:MemberNumber)
                + "~",~"" +
                /*First Name*/
                getString(oPersonBO:FirstName)
                + "~",~"" +
                /*Last Name*/
                getString(oPersonBO:LastName)
                + "~",~"" +
                /*Primary Guardian*/
                (if oPersonBO:IsPrimaryGuardianForHousehold(oHouseholdBO) then "Yes" else "No")
                + "~",~"" +
                /*Email Address*/
                oPersonBO:Person:Vals:PrimaryEmailAddress
                + "~",~"" +
                /*Email Verified*/
                (if oPersonBO:PrimaryEmailAddressVerified() then "Yes" else "No")
                + "~",~"" +
                /*Email Opted In*/
                (if oPersonBO:GetPrimaryEmailOptedIn() then "Yes" else "No")
                + "~",~"" +
                /*WebTrac Username*/
                (if oPersonBO:WebUserName:UserName = "" then "None" else oPersonBO:WebUserName:UserName)
                + "~",~"" +
                /*Has Web Account*/
                (if oPersonBO:HasWebAccount() then "Yes" else "No")
                + "~",~"" +
                /*Has Web Access*/
                (if oLinkBO:HasWebAccess() then "Yes" else "No")
                + "~",~"" +
                /*Has Web Invites*/
                (if oWebInvitesBO:hasInvites() then "Yes" else "No")
                + "~",~"" +
                /*Account Status*/
                (if oPersonBO:IsWebLockedOut() then "Locked Out"
                else if (not oPersonBO:HasWebAccount() or not oLinkBO:HasWebAccess()) and oWebInvitesBO:hasInvites() then "Invite Pending"
                else if not oPersonBO:HasWebAccount() or not oLinkBO:HasWebAccess() then "No Access"
                else "User Active")
                + "~",~"" +
                /*Permissions*/
                (if oLinkBO:link:Vals:WebPermissions = "" then "None" else oLinkBO:link:Vals:WebPermissions)
                + "~",~"" +
                /*Permissions Added?*/
                (if permissionsUpdated then "Account Management Permissions Added" else "")
                + "~",~"" +
                /*Invite Sent?*/
                (if inviteSent then "WebTrac Invite Email Sent" else "")
                + "~",").
    end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Check Document Center for " + {&ProgramName} + "Log for a log of Web Invites Sent","Web Invites Sent: " + string(numEmailsSent),"Account Management Permissions Added: " + string(numPermissions),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* SEND WEB INVITE EMAIL */
procedure sendWebInvite:
    define input parameter oHouseholdBO as HouseholdBO no-undo.
    define input parameter oLinkBO      as LinkBO      no-undo.
    define input parameter oPersonBO    as PersonBO    no-undo.
    define variable oResults as Results no-undo.
    
    /* SEND THE WEBTRAC INVITE EMAIL */
    oResults = oPersonBO:SendInviteEmailForHousehold(oHouseholdBO, oPersonBO:Person:Vals:PrimaryEmailAddress).
    if not oResults:Success then return.
       
    assign 
        numEmailsSent = numEmailsSent + 1
        inviteSent    = yes.    
        
end procedure.
    
/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".

    put stream ex-port inpfile-info format "X(800)" skip.
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