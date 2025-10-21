/*------------------------------------------------------------------------
    File        : findMissingSALinkAndSAPersonRecords.p
    Purpose     : 

    Syntax      : 

    Description : Find missing Relationship and Member records

    Author(s)   : michaelzr
    Created     : 
    Notes       : 
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

// EVERYTHING ELSE
define variable numRecs    as integer no-undo.
define variable hasPrimary as logical no-undo.
define variable hasSALink  as logical no-undo.
assign
    hasSALink  = false
    hasPrimary = false
    numRecs    = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Status,HH ID,HH Num,HH Name,HH Creation Date,HH Creation User,Missing Person ID,").

// HOUSEHOLD LOOP
household-loop:
for each Account no-lock:

    assign 
        hasPrimary = false
        hasSALink  = false.
        
    for each Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
        assign 
            hasSALink = true.
        if Relationship.Primary = true then assign hasPrimary = true.
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
        if not available Member then run put-stream ("Missing Member" + "," + string(Account.ID) + "," + string(Account.EntityNumber) + "," + replace(Account.FirstName + " " + Account.LastName,",","") + "," + string(Account.CreationDate) + "," + Account.CreationUserName + "," + string(Relationship.ChildTableID) + ",").
    end.
    
    if hasSALink = false then run put-stream ("Missing Any HH Relationship" + "," + string(Account.ID) + "," + string(Account.EntityNumber) + "," + replace(Account.FirstName + " " + Account.LastName,",","") + "," + string(Account.CreationDate) + "," + Account.CreationUserName + ",,"). 
    if hasSALink = true and hasPrimary = false then run put-stream ("Missing Primary HH Relationship" + "," + string(Account.ID) + "," + string(Account.EntityNumber) + "," + replace(Account.FirstName + " " + Account.LastName,",","") + "," + string(Account.CreationDate) + "," + Account.CreationUserName + ",,"). 

end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingSALinkAndSAPersonRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingSALinkAndSAPersonRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingSALinkAndSAPersonRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingSALinkAndSAPersonRecords.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find missing Relationship and Member records"
            BufActivityLog.Detail2       = "Check Document Center for findMissingSALinkAndSAPersonRecordsLog for a log of Records Found".
    end.
end procedure.