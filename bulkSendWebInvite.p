/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "bulkSendWebInvite" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Bulk send Web Invites to all users without WebTrac logins"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------

   Author(s)   : michaelzr
   Created     : 3/12/25
   Notes       : Some of the code here, specifically the object models, was originally pulled
                 and heavily modified from WebAccountManagement.p, which was written by Vermont Systems Staff.
                 The overall logic for sending WebTrac invite emails was written written by Michael Rork with
                 guidance on using the objects from Chris Ebbs.
 ----------------------------------------------------------------------*/
 
/*************************************************************************
                                DEFINITIONS
*************************************************************************/

block-level on error undo, throw.

using Business.Library.Model.BO.AccountBO.AccountBO from propath.
using Business.Library.Model.BO.MemberBO.MemberBO from propath.
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
define variable skipAccounts     as character    no-undo.
define variable permissionsUpdated as logical      no-undo.
define variable inviteSent         as logical      no-undo.
define variable ix                 as integer      no-undo.

define variable oAccountBO       as AccountBO  no-undo.
define variable oMemberBO          as MemberBO     no-undo.
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
    skipAccounts     = "999999999".


/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* FIND ALL INTERNAL AND MODEL ACCOUNTS */
profilefield-loop:
for each CustomField no-lock where CustomField.FieldName = "InternalAccount" or CustomField.FieldName begins "ModelAccount":
    if getString(CustomField.FieldValue) = "" then next profilefield-loop.
    do ix = 1 to num-entries(getString(CustomField.FieldValue)):
        skipAccounts = uniquelist(entry(ix,getString(CustomField.FieldValue)),skipAccounts,",").
    end. 
end.

/* CREATE LOG FILE FIELD HEADERS */
run put-stream (
    "Account Number," +
    "HH Creation Date," +
    "HH Last Active Date," +
    "Member ID," +
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
    
/* Account LOOP */   
account-loop:
for each Account no-lock where Account.RecordStatus = "Active":
    
    /* SKIP GUEST AND ALL INTERNAL AND MODEL ACCOUNTS */
    if lookup(string(Account.EntityNumber),skipAccounts) > 0 then next account-loop.
   
    /* LOOP THROUGH ALL MEMBERS OF THE ACCOUNT */
    member-loop:
    for each Relationship no-lock where Relationship.ParentTable = "Account"
        and Relationship.ParentTableID = Account.ID
        and Relationship.ChildTable = "Member"
        and Relationship.Primary = true:
            
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error.
        if not available Member or Member.RecordStatus <> "Active" or isEmpty(Member.PrimaryEmailAddress) then next member-loop.

        assign
            oAccountBO       = AccountBO:GetByAccountID(Account.ID)       /* GRABS THE ACCOUNT OBJECT */
            oMemberBO          = MemberBO:GetByID(Member.ID)                      /* GRABS THE FAMILY MEMBER OBJECT */
            oLinkBO            = oMemberBO:GetLinkToRecord(oAccountBO:Account)  /* GRABS THE RELATIONSHIP OBJECT */
            permissionsUpdated = no
            inviteSent         = no.
        
        if not valid-object(oAccountBO) or not valid-object(oMemberBO) or not valid-object(oLinkBO) then next member-loop.
        
        /* SKIP ANY FAMILY MEMBERS WITHOUT A VALID AND VERIFIED EMAIL ADDRESS */
        if not oMemberBO:PrimaryEmailAddressVerified() or not EmailAddressFormatValidator:valid(oMemberBO:Member:Vals:PrimaryEmailAddress) then next member-loop.
        
        /* GRAB THE WEBINVITE INFORMATION */
        oWebInvitesBO = new WebInvitesBO(oAccountBO:AccountNumber, oMemberBO:MemberNumber).
       
        /* IF THEY DO NOT HAVE ACCOUNT MANAGEMENT PERMISSIONS, SET THEM */
        if oMemberBO:IsPrimaryGuardianForAccount(oAccountBO) and isEmpty(oLinkBO:link:Vals:WebPermissions) then 
        do:
            assign 
                numPermissions     = numPermissions + 1
                permissionsUpdated = yes.
                
            /* SET WEB PERMISSIONS TO ACCOUNT MANAGEMENT */
            oLinkBO:setWebPermissions("Account Management").
        end.
        
        /* DETERMINE THE ACCOUNT STATUS */
        assign 
            accountStatus = (if oMemberBO:IsWebLockedOut() then "Locked Out"
            else if (not oMemberBO:HasWebAccount() or not oLinkBO:HasWebAccess()) and oWebInvitesBO:hasInvites() then "Invite Pending"
            else if not oMemberBO:HasWebAccount() or not oLinkBO:HasWebAccess() then "No Access"
            else "User Active").
            
        /* IF NO WEBTRAC ACCESS, SEND INVITE */
        if accountStatus = "No Access" then run sendWebInvite(oAccountBO,oLinkBO,oMemberBO).
    
        /* LOG CHANGES */
        if permissionsUpdated or inviteSent then run put-stream("~"" +
                /*Account Number*/
                string(oAccountBO:AccountNumber)
                + "~",~"" +
                /*HH Creation Date*/
                getString(string(Account.CreationDate))
                + "~",~"" +
                /*HH Last Active Date*/
                getString(string(Account.LastActiveDate))
                + "~",~"" +
                /*Member ID*/
                string(oMemberBO:MemberNumber)
                + "~",~"" +
                /*First Name*/
                getString(oMemberBO:FirstName)
                + "~",~"" +
                /*Last Name*/
                getString(oMemberBO:LastName)
                + "~",~"" +
                /*Primary Guardian*/
                (if oMemberBO:IsPrimaryGuardianForAccount(oAccountBO) then "Yes" else "No")
                + "~",~"" +
                /*Email Address*/
                oMemberBO:Member:Vals:PrimaryEmailAddress
                + "~",~"" +
                /*Email Verified*/
                (if oMemberBO:PrimaryEmailAddressVerified() then "Yes" else "No")
                + "~",~"" +
                /*Email Opted In*/
                (if oMemberBO:GetPrimaryEmailOptedIn() then "Yes" else "No")
                + "~",~"" +
                /*WebTrac Username*/
                (if oMemberBO:WebUserName:UserName = "" then "None" else oMemberBO:WebUserName:UserName)
                + "~",~"" +
                /*Has Web Account*/
                (if oMemberBO:HasWebAccount() then "Yes" else "No")
                + "~",~"" +
                /*Has Web Access*/
                (if oLinkBO:HasWebAccess() then "Yes" else "No")
                + "~",~"" +
                /*Has Web Invites*/
                (if oWebInvitesBO:hasInvites() then "Yes" else "No")
                + "~",~"" +
                /*Account Status*/
                (if oMemberBO:IsWebLockedOut() then "Locked Out"
                else if (not oMemberBO:HasWebAccount() or not oLinkBO:HasWebAccess()) and oWebInvitesBO:hasInvites() then "Invite Pending"
                else if not oMemberBO:HasWebAccount() or not oLinkBO:HasWebAccess() then "No Access"
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
    define input parameter oAccountBO as AccountBO no-undo.
    define input parameter oLinkBO      as LinkBO      no-undo.
    define input parameter oMemberBO    as MemberBO    no-undo.
    define variable oResults as Results no-undo.
    
    /* SEND THE WEBTRAC INVITE EMAIL */
    oResults = oMemberBO:SendInviteEmailForAccount(oAccountBO, oMemberBO:Member:Vals:PrimaryEmailAddress).
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