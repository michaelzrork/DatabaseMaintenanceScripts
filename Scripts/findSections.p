/*------------------------------------------------------------------------
    File        : findSections.p
    Purpose     : 

    Syntax      : 

    Description : Find Sections for Failed ePACT Disconnects

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
define variable numRecs    as integer   no-undo.
define variable personList as character no-undo.
define variable ix         as integer   no-undo.
assign
    ix         = 1
    personList = "30211,38816,43472,48649,48890,50292,50293,51689,51690,52638,52639,54033,54548,56635,56647,61926"
    numRecs    = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Member ID,Household Number,Name,Description,Status,Receipt List,Transaction Date,TransactionDetail Begin Date,Section Begin Date,Section ID,ePACT Section,Section Status,Archived,").

person-loop:
do ix = 1 to num-entries(personList):
    find first Member no-lock where string(Member.ID) = entry(ix,personList) no-error no-wait.
/*    if not available Member then run put-stream(string(entry(ix,personList)) + "," + "No Member Record Found" + ",,,,,,,").*/
    if not available Member then next person-loop.
    detail-loop:
    for each TransactionDetail no-lock where TransactionDetail.PatronLinkID = Member.ID and TransactionDetail.Module = "AR" and lookup(TransactionDetail.RecordStatus,"Removed,Denied") = 0:
        find first ARSection no-lock where ARSection.ID = TransactionDetail.FileLinkID no-error no-wait.
/*        if not available ARSection then run put-stream(string(Member.ID) + "," + string(TransactionDetail.EntityNumber) + "," + TransactionDetail.FirstName + " " + TransactionDetail.LastName + "," + replace(TransactionDetail.Description,",","_") + "," + TransactionDetail.RecordStatus + "," + string(TransactionDetail.TransactionDate) + "," + "No ARSection Found" + "," + "N/A,").*/
        if not available ARSection then next detail-loop.
        run put-stream(string(Member.ID) + "," + string(TransactionDetail.EntityNumber) + "," + TransactionDetail.FirstName + " " + TransactionDetail.LastName + "," + replace(TransactionDetail.Description,",","_") + "," + TransactionDetail.RecordStatus + "," + replace(TransactionDetail.ReceiptList,","," | ") + "," + string(TransactionDetail.TransactionDate) + "," + string(TransactionDetail.BeginDate) + "," + string(ARSection.BeginDate) + "," + trim(string(ARSection.ID)) + "," + (if ARSection.EnableEpactSection = true then "ePACT" else "Not ePACT") + "," + ARSection.RecordStatus + "," + (if ARSection.Archived = true then "Archived" else "Unarchived") + ",").
    end.
/*    for first TransactionDetail no-lock where TransactionDetail.PatronLinkID = Member.ID and TransactionDetail.Module = "AR" and lookup(TransactionDetail.RecordStatus,"Removed,Denied") = 0:                                                                                                              */
/*    end.                                                                                                                                                                                                                                                                 */
/*    if not available TransactionDetail then                                                                                                                                                                                                                                       */
/*    do:                                                                                                                                                                                                                                                                  */
/*        find first Relationship no-lock where Relationship.ChildTableID = Member.ID no-error no-wait.                                                                                                                                                                              */
/*        if available Relationship then find first Account no-lock where Account.ID = Relationship.ParentTableID.                                                                                                                                                             */
/*        run put-stream(string(Member.ID) + "," + (if available Account then string(Account.EntityNumber) else "No Household Found") + "," + Member.FirstName + " " + Member.LastName + "," + "No Enrollments Found" + "," + "" + "," + "," + "," + ",").*/
/*    end.                                                                                                                                                                                                                                                                 */
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "failedSectionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "failedSectionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/ 

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "failedSectionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findSections.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Sections for Failed ePACT Disconnects"
            BufActivityLog.Detail2       = "Check Document Center for " + "failedSectionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_*.csv" + " for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.