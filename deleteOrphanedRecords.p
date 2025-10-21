/*------------------------------------------------------------------------
    File        : deleteOrphanedRecords.p
    Purpose     : 

    Syntax      : 

    Description : Deletes orphaned Account, Relationship, and Member records.

    Author(s)   : michaelzr
    Created     : 09/30/2024
    Notes       : 
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
define variable numSALinksDeleted        as integer   no-undo.
define variable fixedSALinkCount         as integer   no-undo.
define variable numFMDeleted             as integer   no-undo.
define variable numHHDeleted             as integer   no-undo.

assign
    numSALinksDeleted   = 0
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

// CREATE LOG FILE FIELDS
run put-stream ("Table,Record ID,Record Details,").

// Account LOOP
household-loop:
for each Account no-lock:
    find first Relationship no-lock where Relationship.ParentTableID = Account.ID no-error no-wait.
    if not available Relationship then
    do:
        find first TransactionDetail no-lock where TransactionDetail.EntityNumber = Account.EntityNumber no-error no-wait.
        if not available TransactionDetail then run deleteSAHousehold(Account.ID).
    end.
end.

// Member LOOP
person-loop:
for each Member no-lock:
    find first Relationship no-lock where Relationship.ChildTableID = Member.ID no-error no-wait.
    if not available Relationship then 
    do:
        find first TransactionDetail no-lock where TransactionDetail.PatronLinkID = Member.ID no-error no-wait.
        if not available TransactionDetail then run deleteSAPerson(Member.ID).
    end.
end.

// SALINK LOOP
salink-loop:
for each Relationship no-lock where Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
    find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
    if available Account then next salink-loop.
    find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
    if available Member then next salink-loop.
    if not available Account and not available Member then run deleteSALink(Relationship.ID).
end.
  
    // CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deleteOrphanedRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deleteOrphanedRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

    // CREATE AUDIT LOG RECORD
run ActivityLog ("Deleted Orphaned Account, Member, and Relationship records").


/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// DELETE SALINK
procedure deleteSALink:
    define input parameter inpid as int64 no-undo.
    define buffer bufRelationship for Relationship.
    do for bufRelationship transaction:
        find bufRelationship exclusive-lock where bufRelationship.ID = inpid no-error no-wait.
        if available bufRelationship then 
        do:
            numSALinksDeleted = numSALinksDeleted + 1.
            run put-stream ("Relationship" + "," + string(bufRelationship.ID) + "," + "~"Parent Table: " + bufRelationship.ParentTable + ", Parent Table ID: " + string(bufRelationship.ParentTableID) + ", Child Table: " + bufRelationship.ChildTable + ", Child Table ID: " + string(bufRelationship.ChildTableID) + "~",").
            delete bufRelationship.
        end.
    end.
end procedure.

// DELETE SAPERSON
procedure deleteSAPerson:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then 
        do:
            run put-stream ("Member" + "," + string(bufMember.ID) + "," + "~"Person First Name: " + bufMember.FirstName + ", Person Last Name: " + bufMember.LastName + "~"" + ",").
            numFMDeleted = numFMDeleted + 1.
            delete bufMember.
        end.
    end.
end.

// DELETE ORPHAN HOUSEHOLD
procedure deleteSAHousehold:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            run put-stream ("Account" + "," + string(bufAccount.ID) + "," + "~"Household First Name: " + bufAccount.FirstName + ", Household Last Name: " + bufAccount.LastName + "~"" + ",").
            numHHDeleted = numHHDeleted + 1.
            delete bufAccount.
        end. 
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deleteOrphanedRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "deleteOrphanedRecords.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = logDetail
            BufActivityLog.Detail2       = "Check Document Center for deleteOrphanedRecordsLog for log file of records changed"
            bufActivityLog.Detail3       = " Member records deleted: " + string(numFMDeleted).
    end.
end procedure.