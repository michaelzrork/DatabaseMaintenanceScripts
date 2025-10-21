/*------------------------------------------------------------------------
    File        : changeEmailAddressesToBlackList.p
    Purpose     : 

    Syntax      : 

    Description : Change example/test/refused email addresses currently in the system to a standard @noemail.com domain
                  using the family member~'s first and last name for the first half of the email address

    Author(s)   : michaelzr
    Created     : 3/1/24
    Notes       : The original version of this also fixed Gmail email addresses that had a typo, like xgmail.com or gmail with no .com
                  As of 4/16/24 I~'m pulling that code out to a separate quick fix called fixCommonEmailDomains.p and adding Yahoo, Hotmail, etc
                  4/22/24 - Added a check for fake first half of the email, like example@ or test@
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable emailDomainList as character no-undo.
define variable fullEmailList        as character no-undo.
define variable newDomain            as character no-undo.
define variable atPosition           as integer   no-undo.
define variable newEmailAddress      as character no-undo.
define variable specialCharacterList as character no-undo.
define variable familyMemberID       as int64     no-undo.
define variable isPrimary            as log       no-undo.
define variable hhOrg                as log       no-undo.
define variable ixSpecialCharList    as integer   no-undo.
define variable emailRecs            as integer   no-undo.
define variable deletedSecondaryRecs as integer   no-undo.
define variable newEmailRecs         as integer   no-undo.
define variable hhRecs               as integer   no-undo.
define variable fmRecs               as integer   no-undo.
define variable personFirstName      as character no-undo.
define variable personLastName       as character no-undo.
define variable originalEmail        as character no-undo.
define variable isPrimaryEmail       as log       no-undo.
define variable firstHalf            as character no-undo.
define variable firstHalfList        as character no-undo.

assign
    /* THIS CAN BE MODIFIED TO MATCH ANY OF THE HARDCODED BLACKLIST DOMAINS PROVIDED BY VERMONT SYSTEMS */
    /* THE FULL LIST CAN BE FOUND HERE: https://vermont-systems.helpjuice.com/recchat/recchat-email-updates-8172023?from_search=145031376#email-blacklist-5 */
    newDomain            = "@noemail.com"
    /* THIS IS THE CUSTOMER PROVIDED LIST OF DOMAINS THEY HAVE BEEN USING IN THEIR SYSTEM, PLUS A FEW I ADDED TO BE SURE WE GRABBED EVERYTHING THAT WASN~'T A VALID EMAIL ADDRESS */
    emailDomainList      = "@noemail.com,@example.com,@email.com,@example.org,@example.gov,@example.net,@example,@example.co,@exampl.com,@ex.com,@l.com,@l.l,@sample.com,@test.com,@none.com,@no.com,@example,@email,@example,@exampl,@ex,@l.com,@l.l,@sample,@test,@none,@no,@none,@k.com,@Noemial.com,@d.com,@Nomail.com,@s.com,@Examole.com,@Exaple.com,@Exampe.com,@Abc.com,@q.com,@examplle.com,@exaplme.com,@exapmle.com,@exmaple.com,@Exmpole.com,@Exmple.com,@expample.com"
    /* CUSTOMER HAD REQUESTED THESE EMAIL ADDRESSES ARE REMOVED, AS THEY WERE USED AS FAKE EMAIL ADDRESSES AT SOME POINT AND ARE NOT VALID GMAIL EMAIL ADDRESSES */
    fullEmailList        = "123@gmail.com,1234@gmail.com,ex@gmail.com"
    /* FIRST HALF LIST OF FAKE EMAILS */
    firstHalfList        = "example,test,noemail,none,no,ex,sample"
    /* SPECIAL CHARACTER LIST TO BE REMOVED FROM EMAIL ADDRESSES WHEN PULLING CUSTOMER NAMES AS THE USERNAME; THIS DOESN~'T REMOVE . OR , */
    specialCharacterList = " ,~',~!,~~,`,#,$,%,^,&,*,~(,~),_,-,=,+,~[,~],~\,~{,~},|,~:,~;,~",~<,~>,~?,~/"
    atPosition           = 0
    hhOrg                = false
    isPrimary            = false
    newEmailAddress      = ""
    ixSpecialCharList    = 0
    familyMemberID       = 0
    fmRecs               = 0
    hhRecs               = 0
    emailRecs            = 0
    deletedSecondaryRecs = 0
    newEmailrecs         = 0
    personFirstName      = ""
    personLastName       = ""
    originalEmail        = ""
    isPrimaryEmail       = true
    firstHalf            = "".
    
/* LOG FILE STUFF */
{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo.

assign
    ixLog       = 0
    inpfile-num = 1.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* DISABLES AUTOMATIC VERIFICATION EMAIL PROMPTS WHEN UPDATING THE EMAIL ADDRESSES */
disable triggers for load of EmailContact.

/* CREATE LOG FILE FIELDS */
run put-stream ("Record ID,Table,Member.ID,First Name,Last Name,Original Email,New Email,Primary Email").

/* GOES THROUGH EVERY PERSON IN THE DATABASE, REGARDLESS OF EMAIL ADDRESS STATUS */
Member-loop:
for each Member no-lock:
    /* SET FAMILY MEMBER ID AND CLEAR VARIABLES */
    assign
        isPrimary       = false
        hhOrg           = false
        isPrimaryEmail  = true
        originalEmail   = Member.PrimaryEmailAddress
        personFirstName = replace(Member.FirstName,",","")
        personLastName  = replace(Member.LastName,",","")
        firstHalf       = ""
        familyMemberID  = Member.ID.
    /* CHECK IF PERSON IS A PRIMARY MEMBER IN ANY HOUSEHOLD */
    for first Relationship no-lock where Relationship.ChildTableID = Member.ID and Relationship.ChildTable = "Member" and Relationship.ParentTable = "Account" and Relationship.Primary = true:
        assign 
            isPrimary = true.
    end.
    /* IF EMAIL IS BLANK AND NOT A PRIMARY, NEXT LOOP; WE ONLY WANT TO ADD THE @NOEMAIL.COM DOMAIN TO BLANK EMAIL ADDRESSES IF THEY ARE A PRIMARY */
    if Member.PrimaryEmailAddress = "" and isPrimary = false then next Member-loop.
    /* FIND @ POSITION IN EMAIL */
    if Member.PrimaryEmailAddress <> "" then 
    do:
        assign
            atPosition = index(Member.PrimaryEmailAddress,"@")
            firstHalf  = substring(Member.PrimaryEmailAddress,1,atPosition - 1).
    end.
    /* CHECK TO SEE IF EMAIL ADDRESS IS BLANK OR IF THE DOMAIN IS ON THE EMAIL DOMAIN LIST */
    if Member.PrimaryEmailAddress = "" or (Member.PrimaryEmailAddress <> "" and (lookup(substring(Member.PrimaryEmailAddress,atPosition),emailDomainList) > 0 or lookup(Member.PrimaryEmailAddress,fullEmailList) > 0 or lookup(firstHalf,firstHalfList) > 0)) then
    do:
        /* IF FAMILY MEMBER HAS NO FIRST AND LAST NAME OR ORGANIZATION NAME, LOOK FOR A HOUSEHOLD ORGANIZATION NAME; WE ARE NOT CHECKING THE MEMBER.ORGANIZATION NAME, AS THIS IS OFTEN USED FOR SILVER SNEAKERS */
        if Member.FirstName = "" and Member.LastName = "" then run orgCheck(Member.ID).
        /* CREATE NEW EMAIL ADDRESS USING FIRSTNAME.LASTNAME OR FAMILY MEMBER ORGANIZATION  */
        if hhOrg = false then newEmailAddress = lc(
                /* IF THE PERSON HAS NO NAME, AND IS NOT A PRIMARY GUARDIAN WITH AN ORGANIZATION NAME, USE THE PERSON ID FOR THE FIRST HALF */
                if Member.FirstName = "" and Member.LastName = "" then string(familyMemberID)
                /* IF THE PERSON ONLY HAS A LAST NAME, USE THAT */
                else if Member.Firstname = "" then Member.LastName
                /* IF THE PERSON ONLY HAS A FIRST NAME, USE THAT */
                else if Member.LastName = "" then Member.FirstName
                /* IF THE PERSON HAS FIRST AND LAST NAME, USE THE FULL NAME */
                else Member.FirstName + "." + Member.LastName) + newDomain.
        /* STRIP ANY COMMAS FROM NEW EMAIL ADDRESS (THE REPLACE FUNCTION DIDN'T REMOVE COMMAS WHEN PULLED FROM THE SPECIAL CHARACTER LIST, SO WE REMOVE THEM BEFORE USING THE LIST) */
        newEmailAddress = replace(newEmailAddress,",","").
        /* STRIP ANY SPECIAL CHARACTERS IN THE RESULTING EMAIL ADDRESS */
        do ixSpecialCharList = 1 to num-entries(specialCharacterList):
            newEmailAddress = replace(newEmailAddress,entry(ixSpecialCharList,specialCharacterList),"").
        end.
        /* CHANGE MEMBER EMAIL ADDRESS */
        if originalEmail <> newEmailAddress then run changePersonEmailAddress(Member.ID).
        /* IF PERSON IS A PRIMARY, UPDATE HOUSEHOLD */
        if isPrimary = true then 
        do:
            for each Relationship no-lock where Relationship.ChildTableID = Member.ID and Relationship.ChildTable = "Member" and Relationship.ParentTable = "Account" and Relationship.Primary = true:
                if originalEmail <> newEmailAddress then run changeHouseholdEmailAddress(Relationship.ParentTableID).
            end.    
        end.
    end.
        
    /* CHECK FOR AND UPDATE ANY SECONDARY EMAIL ADDRESSES */
    for each EmailContact where EmailContact.PrimaryEmailAddress = false and EmailContact.MemberLinkID = Member.ID:
        assign
            isPrimaryEmail  = false
            newEmailAddress = "".
        if EmailContact.EmailAddress <> "" then assign
                atPosition = index(EmailContact.EmailAddress,"@")
                firstHalf  = substring(EmailContact.EmailAddress,1,atPosition - 1).
        if (EmailContact.EmailAddress <> "" and (lookup(substring(EmailContact.EmailAddress,atPosition),emailDomainList) > 0 or lookup(EmailContact.EmailAddress,fullEmailList) > 0 or lookup(firstHalf,firstHalfList) > 0)) or EmailContact.EmailAddress = "" then run deleteSecondaryEmail(EmailContact.ID).
    end.
end. 

/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "changeEmailToBlackListLog" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "changeEmailToBlackListLog" + string(ixLog) + ".csv", "~\Reports~\", "", no, yes, yes, "Report").  
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* RUNS ONLY IF THE PERSON RECORD HAS NO FIRST NAME, LAST NAME, OR ORGANIZATION NAME, THEN SETS THE */
/* NEW EMAIL ADDRESS WITH THE HOUSEHOLD ORGANIZATION NAME OR THE PERSON ID IF AN ORG IS NOT AVAILABLE */
procedure orgCheck:
    define input parameter inpID as int64 no-undo.
    define buffer bufRelationship      for Relationship.
    define buffer bufAccount for Account.
    for each bufRelationship no-lock where bufRelationship.ChildTableID = inpID and bufRelationship.ChildTable = "Member" and bufRelationship.ParentTable = "Account" and bufRelationship.Primary = true:
        if hhOrg = true then return.
        /* IF CAN FIND PRIMARY WITH ORGANIZATION NAME, USE ORGANIZATION NAME */
        for first bufAccount no-lock where bufAccount.ID = bufRelationship.ParentTableID and bufAccount.OrganizationName <> "":
            assign
                hhOrg           = true
                newEmailAddress = lc(bufAccount.OrganizationName) + newDomain.
        end.
    end.
end.

/* UPDATE THE FAMILY MEMBER EMAIL ADDRESS */
procedure changePersonEmailAddress:
    define input parameter inpID as int64 no-undo.
    define variable dtNow as datetime no-undo.
    define buffer bufMember       for Member.
    define buffer bufEmailContact for EmailContact.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        /* SET MEMBER EMAIL ADDRESS */
        if available bufMember then 
        do:
            run put-stream (string(bufMember.ID) + "," + "Member" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
            fmRecs = fmRecs + 1.
            bufMember.PrimaryEmailAddress = newEmailAddress.
       
        /* UPDATE EMAILCONTACT RECORD */
            for first bufEmailContact exclusive-lock where bufEmailContact.ParentTable = "Member" and bufEmailContact.PrimaryEmailAddress = true and bufEmailContact.MemberLinkID = bufMember.ID: 
                do:
                    run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
                    assign
                        emailRecs                              = emailRecs + 1
                        dtNow                                  = now
                        bufEmailContact.EmailAddress         = newEmailAddress
                        bufEmailContact.Verified             = true
                        bufEmailContact.VerificationSentDate = dtNow
                        bufEmailContact.LastVerifiedDateTime = dtNow
                        bufEmailContact.OptIn                = false.
                end.
            end.
            if not available bufEmailContact then run createEmailContact(bufMember.ID,"Member",newEmailAddress,familyMemberID).
        end.
    end.
end.

/* UPDATE HOUSEHOLD EMAIL ADDRESS */
procedure changeHouseholdEmailAddress:
    define input parameter inpID as int64 no-undo.
    define variable dtNow as datetime no-undo.
    define buffer bufAccount    for Account.
    define buffer bufEmailContact for EmailContact.
    do for bufAccount transaction:
        /* SET ACCOUNT EMAIL ADDRESS */
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            run put-stream (string(bufAccount.ID) + "," + "Account" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
            hhRecs = hhRecs + 1.
            bufAccount.PrimaryEmailAddress = newEmailAddress.
       
        /* UPDATE EMAILCONTACT RECORD */
            for first bufEmailContact exclusive-lock where bufEmailContact.ParentTable = "Account" and bufEmailContact.PrimaryEmailAddress = true and bufEmailContact.ParentRecord = inpID:
                run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + originalEmail + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).         
                assign
                    dtNow                                  = now
                    emailRecs                              = emailRecs + 1
                    bufEmailContact.EmailAddress         = newEmailAddress
                    bufEmailContact.Verified             = true
                    bufEmailContact.VerificationSentDate = dtNow
                    bufEmailContact.LastVerifiedDateTime = dtNow
                    bufEmailContact.OptIn                = false.
            end.
            if not available bufEmailContact then run createEmailContact(bufAccount.ID,"Account",newEmailAddress,familyMemberID).
        end. 
    end.
end.

/* UPDATE SECONDARY EMAIL ADDRESS RECORDS */
procedure deleteSecondaryEmail:
    define input parameter inpID as int64 no-undo.
    define buffer bufEmailContact for EmailContact.
    do for bufEmailContact transaction:
        find first bufEmailContact exclusive-lock where bufEmailContact.ID = inpID no-error no-wait.
        if available bufEmailContact then 
        do:
            run put-stream (string(bufEmailContact.ID) + "," + "EmailContact (Secondary)" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + bufEmailContact.EmailAddress + "," + "Deleted Secondary" + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
            deletedSecondaryRecs = deletedSecondaryRecs + 1.
            delete bufEmailContact.
        end.
    end.
end.

/* CREATE MISSING EMAILCONTACT RECORDS */
procedure createEmailContact:
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
         /* CREATE LOG ENTRY  */
        run put-stream (string(bufEmailContact.ID) + "," + "EmailContact" + "," + string(familyMemberID) + "," + personFirstName + "," + personLastName + "," + "New Record" + "," + newEmailAddress + "," + (if isPrimaryEmail = true then "Primary" else "Secondary")).
    end.
end procedure.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "changeEmailtoBlacklistLog" + string(inpfile-num) + ".csv".
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

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "changeEmailAddressesToBlackList.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Replaced emails that matched original black list and updated them to firstname.lastname@noemail.com"
            bufActivityLog.Detail2       = "Check Document Center for changeEmailtoBlackListLog to see log file"
            BufActivityLog.Detail3       = "Member Records Updated: " + string(fmRecs)
            bufActivityLog.Detail4       = "Account Records Updated: " + string(hhRecs)
            bufActivityLog.Detail5       = "EmailContact Records Updated: " + string(emailRecs)
            bufActivityLog.Detail6       = "EmailContact Records Created: " + string(newEmailRecs) 
            bufActivityLog.Detail7       = "Secondary Email Records Deleted: " + string(deletedSecondaryRecs).
    end.
end procedure.