/*------------------------------------------------------------------------
    File        : findMissingSABlobFileRecords.p
    Purpose     : 

    Syntax      : 

    Description : Finds File Records with missing BinaryFile records

    Author(s)   : michaelzr
    Created     : 10/24/2024
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
define variable numRecs    as integer   no-undo.
define variable accountNum      as integer   no-undo.
define variable recordName as character no-undo.
define variable noFileNum  as integer   no-undo.
assign
    noFileNum = 0
    numRecs   = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Account Number,Record Name,File ID,File Link Date,File Description,File FileName,").

// SADOCUMENT LOOP
document-loop:
for each File no-lock:
    find first BinaryFile no-lock where BinaryFile.FileName = File.FileName no-error no-wait.
    if not available BinaryFile then 
    do:
        case File.ParentTable:
            when "Account" then 
                do:
                    find first Account no-lock where Account.ID = File.ParentRecord no-error no-wait.
                    if not available Account then next document-loop. 
                    assign
                        accountNum      = Account.EntityNumber
                        recordName = trim((if Account.FirstName = "" then "" else Account.FirstName + " ") + Account.LastName).
                    if recordName = "" then recordName = Account.OrganizationName.
                end. 
            when "Member" then 
                do:
                    find first Member no-lock where Member.ID = File.ParentRecord no-error no-wait.
                    if not available Member then next document-loop.
                    find first Relationship no-lock where Relationship.ChildTableID = Member.ID and Relationship.ParentTable = "Account" no-error no-wait.
                    if not available Relationship then next document-loop.
                    find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
                    if not available Account then next document-loop.
                    assign 
                        accountNum      = Account.EntityNumber
                        recordName = trim((if Member.Firstname = "" then "" else Member.FirstName + " ") + Member.LastName).
                    if recordName = "" then recordName = trim((if Account.FirstName = "" then "" else Account.FirstName + " ") + Account.LastName).
                    if recordName = "" then recordName = Account.OrganizationName.
                end.
            otherwise 
            assign 
                accountNum      = 0
                recordName = "Not HH/FM Document; File.ParentTable = " + File.ParentTable. 
        end.
            
        if File.Filename = "" then noFileNum = noFileNum + 1. 
        else numRecs = numRecs + 1. 
        run put-stream("~"" + string(accountNum) + "~",~"" + recordName + "~",~"" + string(File.ID) + "~",~"" + string(File.LinkDate) + "~",~"" + File.Description + "~",~"" + File.FileName + "~",").
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findMissingSABlobFileRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findMissingSABlobFileRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findMissingSABlobFileRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findMissingSABlobFileRecords.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Finds File Records with missing BinaryFile records"
            BufActivityLog.Detail2       = "Check Document Center for findMissingSABlobFileRecordsLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of File records with Missing BinaryFile record: " + string(numRecs)
            BufActivityLog.Detail4       = "Number of File records with no uploaded file: " + string(noFileNum).
    end.
end procedure.