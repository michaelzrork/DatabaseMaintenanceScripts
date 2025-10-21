/*------------------------------------------------------------------------
    File        : createPrimaryGuardianLogFile.p
    Purpose     : 

    Syntax      : 

    Description : Creates a log file of all households without a primary guardian relationship code

    Author(s)   : michaelzr
    Created     : 12/29/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable hhID as int64 no-undo.
define variable hhNum                as integer   no-undo.
define variable originalRelationship as character no-undo.
define variable newRelationship      as character no-undo.
define variable hhFirstName          as character no-undo.
define variable hhLastName           as character no-undo.
define variable personID             as int64     no-undo.
define variable personFirstName      as character no-undo.
define variable personLastName       as character no-undo.

assign 
    newRelationship = "Primary".

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo. 

inpfile-num = 1.

// AUDIT LOG STUFF
define variable numRecs as integer no-undo.
numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Relationship ID,Household Number,Original Relationship Code,New Relationship Code,Household ID,Household First Name,Household Last Name,Person ID,Person First Name,Person Last Name").

// MAIN PROGRAM GOES HERE
for each Relationship no-lock where primary = true and relationship <> "Primary" and Relationship.ParentTable = "Account":
    assign 
        hhID                 = Relationship.ParentTableID
        personID             = Relationship.ChildTableID
        originalRelationship = Relationship.Relationship
        hhNum                = 0
        hhFirstName          = ""
        hhLastName           = ""
        personFirstName      = ""
        personLastName       = "".
    find first Account no-lock where Account.ID = Relationship.ParentTableID no-wait no-error.
    if available Account then 
        assign
            hhNum       = Account.EntityNumber
            hhFirstName = Account.FirstName
            hhLastName  = Account.LastName.
    else assign
            hhNum       = 0
            hhFirstName = "No Account Record Available"
            hhLastName  = "No Account Record Available".
    find first Member no-lock where Member.ID = Relationship.ChildTableID no-wait no-error.
    if available Member then
        assign
            personFirstName = Member.FirstName
            personLastName  = Member.LastName.
    else assign
            personFirstName = "No Member Record Available"
            personLastName  = "No Member Record Available".
    run put-stream (string(Relationship.ID) + "," + string(hhNum) + "," + originalRelationship + "," + newRelationship + "," + string(hhID) + "," + hhFirstName + "," + hhLastName + "," + string(personID) + "," + (if hhFirstName = personFirstName then "Name matches HH" else (if personFirstName = "" then "No Member First Name" else personFirstName)) + "," + (if hhLastName = personLastName then "Name matches HH" else (if personLastName = "" then "No Member Last Name" else personLastName))).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "primaryGuardianLog" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "primaryGuardianLog" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "primaryGuardianLog" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "createPrimaryGuardianLogFile.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Creates a log file of all households without a primary guardian relationship code"
            BufActivityLog.Detail2       = "Check Document Center for primaryGuardianLog for log file".
    end.
end procedure.