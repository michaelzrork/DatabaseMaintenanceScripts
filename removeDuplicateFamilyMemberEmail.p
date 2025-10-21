/*------------------------------------------------------------------------
    File        : removeDuplicateFamilyMemberEmail.p
    Purpose     : Remove duplicate email addresses from family member records

    Syntax      : 

    Description : This is intended to resolve an issue where users cannot have their forgotten password email sent

    Author(s)   : michaelzr
    Created     : 11/20/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num         as integer      no-undo.
define variable inpfile-loc         as character    no-undo.
define variable counter             as integer      no-undo.
define variable ix                  as integer      no-undo. 

inpfile-num = 1.

// EVERYTHING ELSE

define variable householdEmail      as character    no-undo.
define variable primaryCheck        as logical      no-undo.
define variable numEmailsCleared    as integer      no-undo.
define variable numEmailsDeleted    as integer      no-undo.

householdEmail   = "".
numEmailsCleared = 0.
numEmailsDeleted = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Member.ID,Member.PrimaryEmailAddress,EmailContact.ID,EmailContact.EmailAddress").

// LOOP THROUGH HOUSEHOLDS
householdLoop:
for each Account no-lock:
    
    // SET HOUSEHOLD EMAIL FOR EASY REFERENCE
    householdEmail = Account.PrimaryEmailAddress.
    
    // IF THE HOUSEHOLD EMAIL IS BLANK, SKIP RECORD
    if householdEmail = "" or householdEmail = ? then next householdLoop.
    
    // FIND ALL FAMILY MEMBERS IN THE HOUSEHOLD THAT ARE NOT SET AS PRIMARY
    RelationshipLoop:
    for each Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.ChildTable = "Member" and Relationship.Primary = false and Relationship.RecordType = "Household":
        
        // CHECK TO SEE IF FAMILY MEMBER IS PRIMARY IN ANOTHER HOUSEHOLD
        primaryCheck = false.
        run checkForPrimary(Relationship.ChildTableID).
        if primaryCheck = true then next RelationshipLoop.
        
        // FILTER FAMILY MEMBERS TO JUST THE ONES THAT HAVE THE SAME EMAIL ADDRESS AS THE PRIMARY
        find first Member no-lock where Member.ID = Relationship.ChildTableID and Member.PrimaryEmailAddress = householdEmail no-error no-wait.
        if available Member then do:
            
            // REMOVE THE DUPLICATE EMAIL FROM THE FAMILY MEMBER
            run removeDupelicateMemberEmail(Member.ID).
            
            // FIND ALL OF THE EMAILCONTACT RECORDS LINKED TO THAT FAMILY MEMBER
            for each EmailContact no-lock where EmailContact.ParentRecord = Member.ID and EmailContact.EmailAddress = householdEmail and EmailContact.ParentTable = "Member":
                
                // DELETE THE EMAILCONTACT RECORDS
                run deleteEmailContactRecord(EmailContact.ID).
                
            end. // FOR EACH EMAILCONTACT
        end. // IF AVAILABLE MEMBER
    end. // FOR EACH RELATIONSHIP
end. // FOR EACH ACCOUNT

do ix = 1 to inpfile-num:
  if search(sessiontemp() + "EmailRecordsUpdated" + string(ix) + ".csv") <> ? then 
  SaveFileToDocuments(sessiontemp() + "EmailRecordsUpdated" + string(ix) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHECK IF PRIMARY IN ANOTHER HOUSEHOLD
procedure checkForPrimary:
    define input parameter inpid as int64 no-undo.
    define buffer bufRelationship for Relationship.
    if can-find(first bufRelationship no-lock where bufRelationship.ChildTableID = inpid and bufRelationship.Primary = true and Relationship.RecordType = "Household") then primaryCheck = true.
end procedure.

// REMOVE THE DUPLICATE EMAIL ADDRESS
procedure removeDuplicateMemberEmail:
    define input parameter inpid as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:

        // FIND THE RECORD OF THE PERSON IN THE LOOP
        find first bufMember exclusive-lock where bufMember.ID = inpid no-error no-wait.
        if available bufMember then do:
            
            // CREATE LOG ENTRY
            run put-stream (string(bufMember.ID) + "," + string(bufMember.PrimaryEmailAddress) + "," + ",").

            // ADD TO NUMBER OF EMAILS CLEARED COUNT
            numEmailsCleared = numEmailsCleared + 1.
            
            // BLANK OUT THE EMAIL ADDRESS
            bufMember.PrimaryEmailAddress = "".
        end.
    end.
end. 

// DELETE THE EMAIL ADDRESS RECORD
procedure deleteEmailContact:
    define input parameter inpid as int64 no-undo.
    define buffer bufEmailContact for EmailContact.
    do for bufEmailContact transaction:
        // FIND THE EMAIL ADDRESS RECORD THAT MATCHES THE PERSON IN THE LOOP
        find first bufEmailContact exclusive-lock where bufEmailContact.ID = inpid no-error no-wait.
        if available bufEmailContact then do:
            run put-stream (string(bufEmailContact.ParentRecord) + "," + "," + string(bufEmailContact.ID) + "," + string(bufEmailContact.EmailAddress)).
            // ADD TO NUMBER OF EMAILS DELETED COUNT 
            numEmailsDeleted = numEmailsDeleted + 1.
            // DELETE THE EMAILCONTACT TABLE RECORD
            delete bufEmailContact.
        end.
    end.
end.

// CREATE LOG FILE
procedure put-stream:
  def input parameter inpfile-info as char no-undo.
  inpfile-loc = sessiontemp() + "EmailRecordsUpdated" + string(inpfile-num) + ".csv".
  output stream ex-port to value(inpfile-loc) append.
  inpfile-info = inpfile-info + "".
  
  put stream ex-port inpfile-info format "X(400)" skip.
  counter = counter + 1.
  if counter gt 15000 then do: 
    inpfile-num = inpfile-num + 1. 
    counter = 0.
  end.
  output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "removeDuplicateFamilyMemberEmail"
            bufActivityLog.LogDate       = today
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Remove email addresses for family members that match the household primary guardian"
            bufActivityLog.Detail2       = "Number of Member emails removed: " + string(numEmailsCleared)
            bufActivityLog.Detail3       = "Number of EmailContact records removed: " + string(numEmailsDeleted).
    end.
end procedure.