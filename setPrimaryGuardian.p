/*------------------------------------------------------------------------
    File        : setPrimaryGuardian.p
    Purpose     : 

    Syntax      : 

    Description : Set Primary Guardian toggle on Relationship records for Households without one set

    Author(s)   : michaelzr
    Created     : 10/25/2024
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
define variable numRecs        as integer   no-undo.
define variable numMissing     as integer   no-undo.
define variable numNoNameMatch as integer   no-undo.
define variable householdName  as character no-undo.
define variable personName     as character no-undo.
assign
    numRecs        = 0
    numMissing     = 0
    numNoNameMatch = 0
    householdName  = ""
    personName     = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Notes,Household ID,Household Number,Household Name,Family Member ID,Family Member Name,Relationship ID,Relationship Order").

household-loop:
for each Account no-lock:
    assign
        personName    = "" 
        householdName = ""
        householdName = trim((if Account.FirstName = "" then "" else Account.FirstName + " ") + Account.LastName).
    if householdName = "" then householdName = "No Household Name; Organization Name: " + Account.OrganizationName.
        
    for first Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.Primary = true and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
        next household-loop.
    end.
    
    if not available Relationship then 
    do:
        for each Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member" by Relationship.Order:
            find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
            if available Member and Member.FirstName = Account.FirstName and Member.LastName = Account.LastName then 
            do:
                personName = trim((if Member.Firstname = "" then "" else Member.FirstName + " ") + Member.LastName).
                if personName = "" then "No Person Name".
                
                run setPrimaryGuardian(Relationship.ID).
                next household-loop.
            end.
            // IF WE CAN'T FIND THE SAPERSON RECORD, LET'S LOG IT AS AN ORPHANED RECORD IN CASE WE NEED TO LOOK INTO SOMETHING FURTHER
            if not available Member then 
            do:
                assign 
                    personName = "No Member record available".
                run put-stream ("~"" + "No Member record available for Relationship record" + "~",~"" + string(Account.ID) + "~",~"" + string(Account.EntityNumber) + "~",~"" + householdName + "~",~"" + string(Member.ID) + "~",~"" + personName + "~",~"" + string(Relationship.ID) + "~",~"" + string(Relationship.Order) + "~",").
                assign 
                    numMissing = numMissing + 1.
            end.
        end.
        // IF WE GET HERE THERE WAS NO FAMILY MEMBER NAME MATCH AND WE SHOULD LOG IT AS NO UPDATED PRIMARY GUARDIAN
        if personName = "" then "No Person Name Match".
        run put-stream ("~"" + "Household has no family members with a name match; update the Primary Guardian manually with Household Management" + "~",~"" + string(Account.ID) + "~",~"" + string(Account.EntityNumber) + "~",~"" + householdName + "~",~"" + string(Member.ID) + "~",~"" + personName + "~",~"" + string(Relationship.ID) + "~",~"" + string(Relationship.Order) + "~",").
        numNoNameMatch = numNoNameMatch + 1.
    end.
end. 
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "setPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "setPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SET PRIMARY GUARDIAN TOGGLE
procedure setPrimaryGuardian:
    define input parameter inpID as int64 no-undo.
    define buffer bufRelationship for Relationship.
    do for bufRelationship transaction:
        find first bufRelationship exclusive-lock where bufRelationship.ID = inpID no-error no-wait.
        if available bufRelationship then 
        do:
            assign
                bufRelationship.Primary = true
                numRecs           = numRecs + 1.
                // Household Name,Family Member ID,Family Member Name,Relationship ID,Relationship Order
            run put-stream ("~"" + "Updated to the Primary Guardian" + "~",~"" + string(Account.ID) + "~",~"" + string(Account.EntityNumber) + "~",~"" + householdName + "~",~"" + string(Member.ID) + "~",~"" + personName + "~",~"" + string(Relationship.ID) + "~",~"" + string(Relationship.Order) + "~",").
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "setPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "setPrimaryGuardian.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Set Primary Guardian toggle on Relationship records for Households without one set"
            BufActivityLog.Detail2       = "Check Document Center for setPrimaryGuardianLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Households with Primary Guardian toggle added: " + string(numRecs)
            bufActivityLog.Detail4       = "Number of Households with no Family Member name match: " + string(numNoNameMatch)
            bufActivityLog.Detail5       = "Number of Relationship records with missing Member records: " + string(numMissing).
        .
    end.
end procedure.