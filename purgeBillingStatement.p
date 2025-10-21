/*------------------------------------------------------------------------
    File        : purgeSAStatementHistory.p
    Purpose     : 

    Syntax      : 

    Description : Purge all BillingStatement records

    Author(s)   : michaelzr
    Created     : 12/10/24
    Notes       : This will purge all records in BillingStatement to resolve an issue with running childcare statements
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

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ID,Account Number,Due Date,Invoice Number,Receipt Number,Record Status,BinaryFileLinkID,MiscInformation,WordIndex,").

// PURGE STATEMENT HISTORY
for each BillingStatement no-lock:
    run deleteRecord(BillingStatement.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "purgeSAStatementHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "purgeSAStatementHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteRecord:
    define input parameter inpID as int64 no-undo.
    define buffer bufBillingStatement for BillingStatement.
    do for bufBillingStatement transaction:
        find first bufBillingStatement exclusive-lock where bufBillingStatement.ID = inpID no-error no-wait.
        if available bufBillingStatement then 
        do:
            run put-stream ("~"" + 
                getString(string(bufBillingStatement.ID)) + "~",~"" + 
                getString(string(bufBillingStatement.EntityNumber)) + "~",~"" + 
                getString(string(bufBillingStatement.DueDate)) + "~",~"" + 
                getString(string(bufBillingStatement.InvoiceNumber)) + "~",~"" + 
                getString(string(bufBillingStatement.ReceiptNumber)) + "~",~"" + 
                getString(bufBillingStatement.RecordStatus) + "~",~"" + 
                getString(string(bufBillingStatement.BinaryFileLinkID)) + "~",~"" + 
                getString(string(bufBillingStatement.MiscInformation)) + "~",~"" + 
                getString(string(bufBillingStatement.WordIndex))
                + "~",").
            delete bufBillingStatement.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "purgeSAStatementHistoryLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "purgeSAStatementHistory.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Purge all BillingStatement records"
            BufActivityLog.Detail2       = "Check Document Center for purgeSAStatementHistoryLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.