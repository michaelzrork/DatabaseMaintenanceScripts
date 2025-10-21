/*------------------------------------------------------------------------
    File        : deleteBadSADistributionRecords.p
    Purpose     : 

    Syntax      : 

    Description : Delete Bad LedgerEntry Records

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
define variable numRecs as integer no-undo.
assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("ID,ReceiptNumber,PostingDate,GLCode,PayCode,TransactionReference1,HouseholdNumber,UserName").

// MAIN PROGRAM GOES HERE
for each LedgerEntry no-lock where LedgerEntry.ReceiptNumber ge 500000 and LedgerEntry.ID le 3000000:
    run deleteSAGLDistribution(LedgerEntry.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deletedSAGLDistributionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deletedSAGLDistributionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// PROCEDURE X WITH LOGFILE CREATION
procedure deleteSAGLDistribution:
    define input parameter inpID as int64 no-undo.
    define buffer bufLedgerEntry for LedgerEntry.
    do for bufLedgerEntry transaction:
        find first bufLedgerEntry exclusive-lock where bufLedgerEntry.ID = inpid no-error no-wait.
        if available bufLedgerEntry then 
        do:     
            assign
                numRecs = numRecs + 1.
            // CREATE LOG ENTRY "ID,ReceiptNumber,PostingDate,GLCode,PayCode,TransactionReference1,HouseholdNumber,UserName"
            run put-stream (string(bufLedgerEntry.ID) + "," + string(bufLedgerEntry.ReceiptNumber) + "," + string(bufLedgerEntry.PostingDate) + "," + string(bufLedgerEntry.AccountCode) + "," + bufLedgerEntry.PayCode + "," + bufLedgerEntry.TransactionReference1 + "," + string(bufLedgerEntry.EntityNumber) + "," + bufLedgerEntry.UserName).
            delete bufLedgerEntry.
        end.
    end.
end. 

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deletedSAGLDistributionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "deleteBadSADistributionRecords.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Delete Bad LedgerEntry Records"
            BufActivityLog.Detail1       = "Check Document Center for " + "deletedSAGLDistributionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_*.csv" + " for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.