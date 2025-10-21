/*------------------------------------------------------------------------
    File        : updatePrimaryGuardianRelationshipCode.p
    Purpose     : 

    Syntax      : 

    Description : Creates a log file of all households without a primary guardian relationship code

    Author(s)   : michaelzr
    Created     : 12/29/2023
    Notes       : 09/16/2024 - Updated to delete orphaned Relationship records
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define variable hhID                     as int64     no-undo.
define variable hhNum                    as integer   no-undo.
define variable originalRelationshipCode as character no-undo.
define variable primaryGuardianCode      as character no-undo.
define variable hhFirstName              as character no-undo.
define variable hhLastName               as character no-undo.
define variable personID                 as int64     no-undo.
define variable personFirstName          as character no-undo.
define variable personLastName           as character no-undo.
define variable canFindFM                as log       no-undo.
define variable canFindHH                as log       no-undo.
define variable deletedSALinkCount       as integer   no-undo.
define variable fixedSALinkCount         as integer   no-undo.
define variable numFMDeleted             as integer   no-undo.
define variable numHHDeleted             as integer   no-undo.

assign
    deletedSALinkCount  = 0
    fixedSALinkCount    = 0
    numFMDeleted        = 0
    numHHDeleted        = 0
    primaryGuardianCode = TrueVal(ProfileChar("Static Parameters","PrimeGuardSponsorCode")).

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

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

if primaryGuardianCode = "" or primaryGuardianCode = ? then 
do:
    run ActivityLog ("Primary Guardian Code not set in Static Parameters; program aborted").
    return.
end.    

// CREATE LOG FILE FIELDS
run put-stream ("Record Notes,Record ID,Household Number,Original Relationship Code,New Relationship Code,Household ID,Household First Name,Household Last Name,Person ID,Person First Name,Person Last Name").

// SALINK LOOP
for each Relationship no-lock where primary = true and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member" and Relationship.Relationship <> primaryGuardianCode:
    assign 
        hhID                     = Relationship.ParentTableID
        personID                 = Relationship.ChildTableID
        originalRelationshipCode = if Relationship.Relationship = "" then "No Relationship Code" else getString(Relationship.Relationship)
        hhNum                    = 0
        hhFirstName              = ""
        hhLastName               = ""
        personFirstName          = ""
        personLastName           = "".
    
    // FIND SAPERSON RECORD
    find first Member no-lock where Member.ID = Relationship.ChildTableID no-wait no-error.
    if available Member then 
    do:
        assign
            canFindFM       = true
            personFirstName = if Member.FirstName = "" then "No First Name" else getString(Member.FirstName)
            personLastName  = if Member.LastName = "" then "No Last Name" else getString(Member.LastName).
    end.
    if not available Member then 
    do:
        assign
            canFindFM       = false
            personID        = 0
            personFirstName = "No Member Record Available"
            personLastName  = "".
    end.

    // FIND SAHOUSEHOLD RECORD
    find first Account no-lock where Account.ID = Relationship.ParentTableID no-wait no-error.
    if available Account then 
    do:
        assign
            canFindHH   = true
            hhNum       = Account.EntityNumber
            hhFirstName = if Account.FirstName = "" then "No First Name" else getString(Account.FirstName)
            hhLastName  = if Account.LastName = "" then "No Last Name" else getString(Account.LastName).
        if hhFirstName = "No First Name" and hhLastName = "No Last Name" and Account.OrganizationName <> "" then assign
                hhFirstName = getString(Account.OrganizationName)
                hhLastName  = "".
    end.
    if not available Account then
    do:
        assign
            canFindHH   = false
            hhID        = 0
            hhNum       = 0
            hhFirstName = "No Account Record Available"
            hhLastName  = "".
    end.

    // NOT SURE IF I WANT TO BOTHER WITH CLEARING OUT ORPHANED SALINK RECORDS JUST YET... THIS SHOULD WORK FINE WITHOUT THIS STUFF    

    // IF WE CAN'T FIND THE FM BUT WE CAN FIND A HH, LET'S FIND ADDITIONAL FAMILY MEMBERS AND MARK ONE OF THEM AS THE PRIMARY GUARDIAN, OTHERWISE LET'S DELETE THE HOUSEHOLD
    if not canFindFM and canFindHH then run findAdditionalFM(Relationship.ParentTableID,Relationship.ChildTableID).
        
    // IF THEY ARE NOT IN ANOTHER HH, THEN LET'S CHECK IF THERE IS PURCHASE HISTORY; IF NO HISTORY, DELETE THE SALINK AND THE FM; IF THERE IS PURCHASE HISTORY LET'S JUST LOG IT FOR NOW
    if canFindFM and not canFindHH then run findAdditionalHH(Relationship.ParentTableID,Relationship.ChildTableID).
    
    // IF WE CAN'T FIND THE FM AND WE CAN'T FIND THE HH, THEN LET'S DELETE THIS ORPHANED SALINK RECORD
    if not canFindFM and not canFindHH then run deleteSALink(Relationship.ID,"No Member or Account Records Available").
    
    // IF WE CAN FIND THE FM AND WE CAN FIND A HH, UPDATE THE RELATIONSHIP CODE
    if canFindFM and canFindHH then run fixRelationshipCode(Relationship.ID).
    
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "updatePrimaryGuardianRelationshipCodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "updatePrimaryGuardianRelationshipCodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog ("Updated Relationship Code for all Primary Guardians to '" + primaryGuardianCode + "'").
    

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// FIND ADDITIONAL FAMILY MEMBERS ON THE SAME HOUSEHOLD 
procedure findAdditionalFM:
    define input parameter parentID as int64 no-undo.
    define input parameter childID as int64 no-undo.
    define buffer bufRelationship   for Relationship.
    define buffer bufMember for Member.
    
    // FIND ANY OTHER FM ON THE HH WITH THE PRIMARY TOGGLE, IF AVAILABLE, DELETE THE SALINK RECORD WITH THE MISSING SAPERSON RECORD
    // THE OTHER SALINK RECORD WITH THE PRIMARY TOGGLE WILL NATURALLY BE FED THROUGH THE LOOP AND BE UPDATED OR DELETED
    for first bufRelationship no-lock where bufRelationship.ParentTableID = parentID and bufRelationship.ChildTableID <> childID and bufRelationship.ParentTable = "Account" and bufRelationship.ChildTable = "Member" and bufRelationship.Primary = true by bufRelationship.Order:
        run deleteSALink (Relationship.ID,"No Member Record; Addtional FM Linked to HH has Primary Toggle Enabled - Confirm they are linked correctly").
        return.
    end.
    
    // IF NO OTHER FM HAS THE PRIMARY TOGGLE, FIND ANY OTHER FM ON THE HH WITHOUT A PRIMARY TOGGLE
    // DELETE THE SALINK RECORD WITH THE MISSING SAPERSON RECORD AND NOTATE IN THE LOG THAT THERE IS A FM MEMBER AVAILABLE TO MANUALLY BE LINKED AS THE PRIMARY MEMBER
    for each bufRelationship no-lock where bufRelationship.ParentTableID = parentID and bufRelationship.ChildTableID <> childID and bufRelationship.ParentTable = "Account" and bufRelationship.ChildTable = "Member" and bufRelationship.Primary = false by bufRelationship.Order:
        find first bufMember no-lock where bufMember.ID = bufRelationship.ChildTableID no-error no-wait.
        if available bufMember then 
        do:
            run deleteSALink (Relationship.ID,"No Member Record; Additional FM available to manually be linked as Primary on HH").
            return.
        end.
    end.
    
    // IF NO ADDITIONAL FM ON THE HH HAS AN SAPERSON RECORD, DELETE THE SALINK, NOTE THAT THERE IS AN ORPHANED HH RECORD    
    run deleteSALink(Relationship.ID,"No Member Record; No Additional FM on HH - Potentially Orphaned HH Record").
    // IF THE NOW ORPHANED HH HAS NO PURCHASE HISTORY, DELETE THE HH
    find first TransactionDetail no-lock where TransactionDetail.EntityNumber = hhNum no-error no-wait. // SHOULD PROBABLY MAKE THIS A FOR FIRST AND ADD RECORDSTATUS <> "REMOVED"
    if not available TransactionDetail then run deleteSAHousehold(Relationship.ParentTableID).
end procedure. // findAdditionalFM


// FIND ADDITIONAL HOUSEHOLD FOR SAPERSON RECORD
procedure findAdditionalHH:
    define input parameter parentID as int64 no-undo.
    define input parameter childID as int64 no-undo.
    define buffer bufRelationship for Relationship.
    do for bufRelationship transaction:
        // FIND A LINK RECORD FOR THE FM LINKED TO ANOTHER HH, IF AVAILABLE, DELETE THE SALINK FOR THE MISSING HH
        for first bufRelationship no-lock where bufRelationship.ChildTableID = childID and bufRelationship.ParentTableID <> parentID and bufRelationship.ParentTable = "Account" and bufRelationship.ChildTable = "Member" by bufRelationship.Order:
            run deleteSALink(Relationship.ID,"No Account Record, Member Record Linked to additional HH").
            return.
        end.
        // IF THE FM IS NOT LINKED TO A SECOND HH, THEN DELETE THE SALINK AND THE SAPERSON RECORDS (SO LONG AS THERE IS NO PURCHASE HISTORY)
        if not available bufRelationship then 
        do:
            run deleteSALink(Relationship.ID,"No Account Record, Member not linked to additional HH - Potentially Orphaned FM Record").
            find first TransactionDetail no-lock where TransactionDetail.PatronLinkID = childID no-error no-wait. // SHOULD PROBABLY MAKE THIS A FOR FIRST AND ADD RECORDSTATUS <> "REMOVED"
            if not available TransactionDetail then run deleteSAPerson(childID).
        end.
    end.
end procedure. // findAdditionalHH


// DELETE SALINK
procedure deleteSALink:
    define input parameter inpid as int64 no-undo.
    define input parameter deleteNote as character no-undo.
    define buffer bufRelationship for Relationship.
    do for bufRelationship transaction:
        find bufRelationship exclusive-lock where bufRelationship.ID = inpid no-error no-wait.
        if available bufRelationship then 
        do:
            deletedSALinkCount = deletedSALinkCount + 1.
            run put-stream ("~"" + "Relationship Record Deleted; " + deleteNote + "~"," + string(bufRelationship.ID) + "," + string(hhNum) + "," + originalRelationshipCode + "," + "N/A" + "," + string(hhID) + "," + "~"" + hhFirstName + "~"" + "," + "~"" + hhLastName + "~"" + "," + string(personID) + "," + "~"" + personFirstName + "~"" + "," + "~"" + personLastName + "~"" + ",").
            delete bufRelationship.
        end.
    end.
end procedure.


// DELETE ORPHAN HOUSEHOLD
procedure deleteSAHousehold:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            run put-stream ("~"" + "Account Recorded Deleted; Orphaned Record with no purchase history" + "~"," + string(bufAccount.ID) + "," + string(hhNum) + "," + "N/A" + "," + "N/A" + "," + string(hhID) + "," + "~"" + hhFirstName + "~"" + "," + "~"" + hhLastName + "~"" + "," + string(personID) + "," + "~"" + personFirstName + "~"" + "," + "~"" + personLastName + "~"" + ",").
            delete bufAccount.
            numHHDeleted = numHHDeleted + 1.
        end. 
    end.
end.


// DELETE SAPERSON
procedure deleteSAPerson:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then 
        do:
            run put-stream ("~"" + "Member Recorded Deleted; Orphaned Record with no purchase history" + "~"," + string(bufMember.ID) + "," + string(hhNum) + "," + "N/A" + "," + "N/A" + "," + string(hhID) + "," + "~"" + hhFirstName + "~"" + "," + "~"" + hhLastName + "~"" + "," + string(personID) + "," + "~"" + personFirstName + "~"" + "," + "~"" + personLastName + "~"" + ",").
            delete bufMember.
            numFMDeleted = numFMDeleted + 1.
        end.
    end.
end.


// FIX RELATIONSHIP CODE
procedure fixRelationshipCode:
    define input parameter inpid as int64 no-undo.
    define buffer bufRelationship for Relationship.
    do for bufRelationship transaction:
        find bufRelationship exclusive-lock where bufRelationship.ID = inpid no-error no-wait.
        if available bufRelationship then 
        do:
            run put-stream ("~"" + "Primary Guardian Relationship Code Updated" + "~"," + string(bufRelationship.ID) + "," + string(hhNum) + "," + originalRelationshipCode + "," + primaryGuardianCode + "," + string(hhID) + "," + "~"" + hhFirstName + "~"" + "," + "~"" + hhLastName + "~"" + "," + string(personID) + "," + "~"" + personFirstName + "~"" + "," + "~"" + personLastName + "~"" + ",").
            assign
                fixedSALinkCount       = fixedSALinkCount + 1
                bufRelationship.Relationship = primaryGuardianCode.
        end.
    end.
end procedure.


// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "updatePrimaryGuardianRelationshipCodeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
    define buffer BufActivityLog for ActivityLog.
    define input parameter logDetail as character no-undo.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "updatePrimaryGuardianRelationshipCode.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = logDetail
            BufActivityLog.Detail2       = "Check Document Center for updatePrimaryGuardianRelationshipCodeLog for log file of records changed"
            bufActivityLog.Detail3       = "Relationship records updated to Primary Guardian Relationship Code: " + string(fixedSALinkCount) + "; Relationship records deleted: " + string(deletedSALinkCount) + "; Member records deleted: " + string(numFMDeleted) + "; Account records deleted: " + string(numHHDeleted).
    end.
end procedure.