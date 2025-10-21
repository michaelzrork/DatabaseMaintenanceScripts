/*------------------------------------------------------------------------
    File        : syncHHEmailtoPrimaryGuardian.p
    Purpose     : 

    Syntax      : 

    Description : Sync Household emails to the Primary Guardian record

    Author(s)   : michaelzr
    Created     : 4/19/2024
    Notes       : 8/12/2024 - Changed to opt in; also confirmed that because triggers are not disabled the WebUserName.EmailAddress is getting updated
                            - Could disable triggers and update the WebUserName.EmailAddress field manually if we wanted to
                            - Also confirmed that the EmailContact record for the Household is getting updated by the trigger, despite not being updated in the quickie
                            - Changes in Household email record are to sync things like Verified and Optin status 
                            - Adjusted logs so that records without email address now read "No Email Address"
                            - If used as a post update step, we probably don't need the logfile stuff, but keeping it here in case it's useful
                  8/30/2024 - The logic on this program is that since the bug that got emails out of sync was from the HH side when deleting the email or changing it to a
                              non-valid email address that it would make sense to select the HH email as the email address to use for syncing; because if they deleted the
                              email from HH and it didn't delete from FM, then we'd want to delete the email from FM, and if they edited the email in HH, then we'd want FM
                              to match (even if it's a typo and bad email address, but that's a different conversation)
                            - This quickie does not disable triggers, but instead sets the updated emails to verified automatically; this could be updated to sync the
                              verification status of the HH email address instead, which should be a fairly easy change to add other fields that need to get updated,
                              disable triggers, and sync the existing HH email address data
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

// AUDIT LOG STUFF

define variable personRecs       as integer no-undo.
define variable emailRecsUpdated as integer no-undo.
define variable newEmailRecs     as integer no-undo.
define variable deletedEmailRecs as integer no-undo.
assign
    personRecs       = 0
    emailRecsUpdated = 0
    newEmailRecs     = 0
    deletedEmailRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Record ID,Table,SAPeson.ID,First Name,Last Name,Original Member Email Address,New Email from Account,").

// SYNC SAPERSON EMAIL WITH SAHOUSEHOLD IF OUT OF SYNC
for each Relationship no-lock where Relationship.ChildTable = "Member" and Relationship.ParentTable = "Account" and Relationship.Primary = true:
    find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
    if available Account then find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
    if available Member and Member.PrimaryEmailAddress <> Account.PrimaryEmailAddress then run syncHouseholdEmail(Account.ID,Account.PrimaryEmailAddress,Member.ID). 
end.

  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "syncHHEmailtoPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "syncHHEmailtoPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SYNC SAHOUSEHOLD EMAIL TO SAPERSON EMAIL
procedure syncHouseholdEmail:
    define input parameter hhID as int64 no-undo.
    define input parameter householdEmail as character no-undo.
    define input parameter fmID as int64 no-undo.
    define variable dtNow as datetime no-undo.
    define buffer bufMember       for Member.
    define buffer bufEmailContact for EmailContact.
    do for bufMember transaction:
        // SET SAPERSON EMAIL ADDRESS
        find first bufMember exclusive-lock where bufMember.ID = fmID no-error no-wait.
        if available bufMember then 
        do:
            run put-stream (string(bufMember.ID) + "," + "Member" + "," + string(fmID) + "," + replace(bufMember.FirstName,",","") + "," + replace(bufMember.LastName,",","") + "," + (if bufMember.PrimaryEmailAddress = "" or bufMember.PrimaryEmailAddress = ? then "No Member Email Address" else bufMember.PrimaryEmailAddress) + "," + (if householdEmail = "" or householdEmail = ? then "No Account Email Address" else householdEmail) + ",").
            assign 
                personRecs                      = personRecs + 1
                bufMember.PrimaryEmailAddress = householdEmail.
        
            // UPDATE SAEMAILADDRESS RECORD
            for first bufEmailContact exclusive-lock where bufEmailContact.ParentTable = "Member" and bufEmailContact.PrimaryEmailAddress = true and bufEmailContact.ParentRecord = fmID:
                if householdEmail = "" then 
                do:
                    run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(fmID) + "," + replace(bufMember.FirstName,",","") + "," + replace(bufMember.LastName,",","") + "," + bufEmailContact.EmailAddress + "," + "Removed" + ",").
                    assign 
                        deletedEmailRecs = deletedEmailRecs + 1.
                    delete bufEmailContact.
                end.
                else 
                do:
                    run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(fmID) + "," + replace(bufMember.FirstName,",","") + "," + replace(bufMember.LastName,",","") + "," + bufEmailContact.EmailAddress + "," + householdEmail + ",").
                    assign
                        emailRecsUpdated                       = emailRecsUpdated + 1
                        dtNow                                  = now
                        bufEmailContact.EmailAddress         = householdEmail
                        bufEmailContact.Verified             = yes
                        bufEmailContact.LastVerifiedDateTime = dtNow
                        bufEmailContact.OptIn                = yes
                        bufEmailContact.VerificationSentDate = dtNow.
                end.
            end.
            if not available bufEmailContact and householdEmail <> "" then run createSAEmailAddress(bufMember.ID,"Member",householdEmail,fmID,bufMember.FirstName,bufMember.LastName).
        end.
    end.
end.

// CREATE MISSING SAEMAILADDRESS RECORDS
procedure createSAEmailaddress:
    define input parameter i64ParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.
    define input parameter cEmailAddress as character no-undo.
    define input parameter i64PersonLinkID as int64 no-undo.
    define input parameter cFirstName as character no-undo.
    define input parameter cLastName as character no-undo.
    define variable dtNow as datetime no-undo.
    define buffer bufEmailContact for EmailContact.
    do for bufEmailContact transaction:  
        newEmailRecs = newEmailRecs + 1.
        create bufEmailContact.
        assign
            dtNow                                  = now
            bufEmailContact.ID                   = next-value(UniqueNumber)
            bufEmailContact.ParentRecord             = i64ParentID
            bufEmailContact.ParentTable          = cParentTable
            bufEmailContact.PrimaryEmailAddress  = true
            bufEmailContact.MemberLinkID       = i64PersonLinkID
            bufEmailContact.EmailAddress         = cEmailAddress
            bufEmailContact.Verified             = yes
            bufEmailContact.LastVerifiedDateTime = dtNow
            bufEmailContact.OptIn                = yes
            bufEmailContact.VerificationSentDate = dtNow.
        // CREATE LOG ENTRY
        run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(i64PersonLinkID) + "," + replace(cFirstName,",","") + "," + replace(cLastName,",","") + "," + "New Record" + "," + cEmailAddress + ",").
    end.
end procedure.
              
// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "syncHHEmailtoPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "syncHHEmailtoPrimaryGuardian.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sync Household emails to the Primary Guardian record"
            BufActivityLog.Detail2       = "Check Document Center for syncHHEmailtoPrimaryGuardianLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Member Records Adjusted: " + string(personRecs)
            BufActivityLog.Detail4       = "Number of EmailContact Records Adjusted: " + string(emailRecsUpdated)
            BufActivityLog.Detail5       = "Number of EmailContact Records Added: " + string(newEmailRecs)
            BufActivityLog.Detail6       = "Number of EmailContact Records Deleted: " + string(deletedEmailRecs).
    end.
end procedure.