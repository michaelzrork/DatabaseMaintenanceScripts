/*------------------------------------------------------------------------
    File        : fixCommonEmailDomainTypos.p
    Purpose     : 

    Syntax      : 

    Description : Fix common misspellings of common email domains, such as Gmail, Hotmail, and Yahoo

    Author(s)   : michaelzr
    Created     : 4/16/24
    Notes       : Cloned from changeEmailAddressesToBlackList.p
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

// LOG FILE STUFF
{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num       as integer   no-undo.
define variable inpfile-loc       as character no-undo.
define variable counter           as integer   no-undo.
define variable ixLog             as integer   no-undo. 

define variable newDomain         as character no-undo.
define variable atPosition        as integer   no-undo.
define variable newEmailAddress   as character no-undo.
define variable familyMemberID    as int64     no-undo.
define variable ix                as integer   no-undo.
define variable emailRecs         as integer   no-undo.
define variable secondaryRecs     as integer   no-undo.
define variable newEmailRecs      as integer   no-undo.
define variable hhRecs            as integer   no-undo.
define variable syncedHHEmails    as integer   no-undo.
define variable syncedEmails      as integer   no-undo.
define variable fmRecs            as integer   no-undo.
define variable domainCheck       as log       no-undo.
define variable gmailDomainList   as character no-undo.
define variable yahooDomainList   as character no-undo.
define variable hotmailDomainList as character no-undo.
define variable iCloudDomainList  as character no-undo.
define variable orgDomainList     as character no-undo.
define variable newOrgDomain      as character no-undo.
define variable firstHalf         as character no-undo.
define variable isPrimaryEmail    as log       no-undo.
define variable personFirstName   as character no-undo.
define variable personLastName    as character no-undo.
define variable originalEmail     as character no-undo.
define variable validDomainList   as character no-undo.


assign
    newDomain         = ""
    validDomainList   = "@bsugmail.net,@gmail.com,@yahoo.com,@hotmail.com,@icloud.com,@lawrenceks.org,@hotmail.co.kr,@hotmail.co.uk,@hotmail.fr,@us.gmail,@yahoo.ca,@myyahoo.com,@hotmail.de,@yahoo.co.in,@yahoo.co.jp,@yahoo.co.uk,@yahoo.com.au,@yahoo.com.br,@yahoo.com.hk,@yahoo.com.mx,@yahoo.de,@yahoo.es,@yahoo.fr,@yahoo.in"
    gmailDomainList   = "gmail,@gmai.com,@gamil,@gmal,@gmial,@gail.com,@gmil,@gmnail,@gmaikl,@gmaiol,@gmali,@gmiail"
    yahooDomainList   = "yahoo,@yhaoo"
    iCloudDomainList  = "icloud,@icoud,@icould" 
    hotmailDomainList = "hotmail,@homail,@hotmial"
    orgDomainList     = "@lawrence.org"
    newOrgDomain      = "@lawrenceks.org"
    atPosition        = 0
    newEmailAddress   = ""
    ix                = 0
    ixLog             = 0
    inpfile-num       = 1
    familyMemberID    = 0
    fmRecs            = 0
    hhRecs            = 0
    syncedHHEmails    = 0
    syncedEmails      = 0
    emailRecs         = 0
    newEmailRecs      = 0
    secondaryRecs     = 0
    domainCheck       = false
    isPrimaryEmail    = true
    firstHalf         = ""
    personFirstName   = ""
    personLastName    = ""
    originalEmail     = "".
    

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// DISABLES AUTOMATIC VERIFICATION EMAIL PROMPTS WHEN UPDATING THE EMAIL ADDRESSES
disable triggers for load of EmailContact.

// CREATE LOG FILE FIELDS
run put-stream ("Record ID,Table,SAPeson.ID,First Name,Last Name,Original Email,New Email,Primary Email").

// FIND ANY PERSON WITH AN EMAIL ADDRESS
Member-loop:
for each Member no-lock where Member.PrimaryEmailAddress <> "":
    // SET FAMILY MEMBER ID AND CLEAR VARIABLES
    assign
        originalEmail   = Member.PrimaryEmailAddress
        familyMemberID  = Member.ID
        isPrimaryEmail  = true
        personFirstName = replace(Member.FirstName,",","")
        personLastName  = replace(Member.LastName,",","")
        newDomain       = ""
        firstHalf       = ""
        domainCheck     = false. 
    
    // FIND @ POSITION IN EMAIL
    if Member.PrimaryEmailAddress <> "" then atPosition = index(Member.PrimaryEmailAddress,"@").
    
    // FIND COMMON DOMAINS WITH TYPOS
    run checkDomain(substring(Member.PrimaryEmailAddress,atPosition)).
    
    // IF ON DOMAIN LISTS FIX PRIMARY EMAIL ADDRESS
    if domainCheck = true then 
    do:
        assign
            firstHalf       = substring(Member.PrimaryEmailAddress,1,atPosition - 1)
            newEmailAddress = firsthalf + newDomain.
        // CHANGE SAPERSON EMAIL ADDRESS
        run changePersonEmailAddress(familyMemberID).
        // IF PERSON IS A PRIMARY, UPDATE HOUSEHOLD
        for each Relationship no-lock where Relationship.ChildTableID = familyMemberID and Relationship.ChildTable = "Member" and Relationship.ParentTable = "Account" and Relationship.Primary = true:
            run changeHouseholdEmailAddress(Relationship.ParentTableID).
        end.   
    end.
        
    // CHECK FOR AND FIX ANY SECONDARY EMAIL ADDRESSES
    for each EmailContact where EmailContact.PrimaryEmailAddress = false and EmailContact.MemberLinkID = familyMemberID and EmailContact.EmailAddress <> "":
        assign
            isPrimaryEmail  = false
            newEmailAddress = ""
            firstHalf       = ""
            atPosition      = index(EmailContact.EmailAddress,"@")
            newDomain       = ""
            domainCheck     = false.
            
        // CHECK TO SEE IF SECONDARY EMAIL IS ON DOMAIN LISTS
        run checkDomain(substring(EmailContact.EmailAddress,atPosition)).
        
        // IF SECONDARY EMAIL IS ON DOMAIN LISTS, FIX EMAIL ADDRESS
        if domainCheck = true then 
        do:
            assign
                firstHalf       = substring(EmailContact.EmailAddress,1,atPosition - 1)
                newEmailAddress = firsthalf + newDomain.
            run changeSecondaryEmailAddress(EmailContact.ID).
        end.
    end.
end. 

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "fixCommonEmailDomainTyposLog" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "fixCommonEmailDomainTyposLog" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHECK DOMAIN FOR TYPOS AND SET NEW DOMAIN
procedure checkDomain:
    define input parameter emailDomain as character no-undo.
    do ix = 1 to num-entries(gmailDomainList) while domainCheck = false:
        if index(emailDomain,entry(ix,gmailDomainList)) > 0 and lookup(emailDomain,validDomainList) = 0 then
            assign
                domainCheck = true
                newDomain   = "@gmail.com".
    end.
    do ix = 1 to num-entries(yahooDomainList) while domainCheck = false:
        if index(emailDomain,entry(ix,yahooDomainList)) > 0 and lookup(emailDomain,validDomainList) = 0 then
            assign
                domainCheck = true
                newDomain   = "@yahoo.com".
    end.
    do ix = 1 to num-entries(hotmailDomainList) while domainCheck = false:
        if index(emailDomain,entry(ix,hotmailDomainList)) > 0 and lookup(emailDomain,validDomainList) = 0 then
            assign
                domainCheck = true
                newDomain   = "@hotmail.com".
    end.
    do ix = 1 to num-entries(icloudDomainList) while domainCheck = false:
        if index(emailDomain,entry(ix,icloudDomainList)) > 0 and lookup(emailDomain,validDomainList) = 0 then
            assign
                domainCheck = true
                newDomain   = "@icloud.com".
    end.
    do ix = 1 to num-entries(orgDomainList) while domainCheck = false:
        if index(emailDomain,entry(ix,orgDomainList)) > 0 and emailDomain <> newOrgDomain then
            assign
                domainCheck = true
                newDomain   = newOrgDomain.
    end.
end.

// UPDATE THE FAMILY MEMBER EMAIL ADDRESS
procedure changePersonEmailAddress:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember       for Member.
    define buffer bufEmailContact for EmailContact.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        // SET SAPERSON EMAIL ADDRESS
        if available bufMember then 
        do:
            // CREATE LOG ENTRY
            run put-stream (string(bufMember.ID) + "," + "Member" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
            assign 
                fmRecs                          = fmRecs + 1
                bufMember.PrimaryEmailAddress = newEmailAddress.
        
        // UPDATE SAEMAILADDRESS RECORD
            for first bufEmailContact exclusive-lock where bufEmailContact.ParentTable = "Member" and bufEmailContact.PrimaryEmailAddress = true and bufEmailContact.MemberLinkID = bufMember.ID:
                // CREATE LOG ENTRY
                run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
                assign
                    emailRecs                      = emailRecs + 1
                    bufEmailContact.EmailAddress = newEmailAddress.
            end.
            if not available bufEmailContact then run createSAEmailAddress(bufMember.ID,"Member",newEmailAddress,familyMemberID).
        end.
    end.
end.

// UPDATE HOUSEHOLD EMAIL ADDRESS
procedure changeHouseholdEmailAddress:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount    for SAhousehold.
    define buffer bufEmailContact for EmailContact.
    do for bufAccount transaction:
        // SET SAHOUSEHOLD EMAIL ADDRESS
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            // CREATE LOG ENTRY "Match,Fields,To,Headers"
            run put-stream (string(bufAccount.ID) + "," + "Account" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
            assign 
                hhRecs                             = hhRecs + 1
                bufAccount.PrimaryEmailAddress = newEmailAddress.
        
        // UPDATE SAEMAILADDRESS RECORD
            for first bufEmailContact exclusive-lock where bufEmailContact.ParentTable = "Account" and bufEmailContact.PrimaryEmailAddress = true and bufEmailContact.ParentRecord = inpID:
                // CREATE LOG ENTRY "Match,Fields,To,Headers"
                run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
                assign
                    emailRecs                      = emailRecs + 1
                    bufEmailContact.EmailAddress = newEmailAddress.
            end.
            if not available bufEmailContact then run createSAEmailAddress(bufAccount.ID,"Account",newEmailAddress,familyMemberID).
        end.
    end.
end.

// UPDATE SECONDARY EMAIL ADDRESS RECORDS
procedure changeSecondaryEmailAddress:
    define input parameter inpID as int64 no-undo.
    define buffer bufEmailContact for EmailContact.
    do for bufEmailContact transaction:
        find first bufEmailContact exclusive-lock where bufEmailContact.ID = inpID no-error no-wait.
        if available bufEmailContact then 
        do:
            // CREATE LOG ENTRY "Match,Fields,To,Headers"
            run put-stream (string(bufEmailContact.ID) + "," + "EmailContact (Secondary)" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + bufEmailContact.EmailAddress + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
            assign
                secondaryRecs                  = secondaryRecs + 1
                bufEmailContact.EmailAddress = newEmailAddress.
        end.
    end.
end.

// CREATE MISSING SAEMAILADDRESS RECORDS
procedure createSAEmailaddress:
    define input parameter i64ParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.
    define input parameter cEmailAddress as character no-undo.
    define input parameter i64PersonLinkID as int64 no-undo.
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
            bufEmailContact.OptIn                = no
            bufEmailContact.VerificationSentDate = dtNow.
        // CREATE LOG ENTRY "Match,Fields,To,Headers"
        run put-stream (string(bufEmailContact.ID) + "," + "EmailContact (New Record)" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "fixCommonEmailDomainTyposLog" + string(inpfile-num) + ".csv".
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
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "fixCommonEmailDomainTypos.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Fix typos in common email address domains"
            BufActivityLog.Detail2       = "Member Domains Fixed: " + string(fmRecs)
            bufActivityLog.Detail3       = "Account Domains Fixed: " + string(hhRecs)
            bufActivityLog.Detail4       = "Primary EmailContact Domains Fixed: " + string(emailRecs)
            bufActivityLog.Detail5       = "EmailContact Records Created: " + string(newEmailRecs)
            bufActivityLog.Detail6       = "Secondary EmailContact Domains Fixed: " + string(secondaryRecs).
    end.
end procedure.