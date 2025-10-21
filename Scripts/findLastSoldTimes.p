/*------------------------------------------------------------------------
    File        : findLastSoldTimes.p
    Purpose     : 

    Syntax      : 

    Description : Finds the time of the last ticket sold for each ticket block

    Author(s)   : michaelzr
    Created     : 
    Notes       : Need to find each ticket that begins with "Hex" and then find the time
                  of the last ticket sold for each of their time blocks and add it to a log
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
run put-stream ("Ticket Code,Ticket Short Description,Ticket Block ID,Ticket Block Description,Last Sold Ticket Receipt Number,Last Sold Ticket Transaction Date,Last Sold Ticket Transaction Time,").

// MAIN CODE LOOP  
for each PSTicketMain no-lock where PSTicketMain.TicketCode begins "Hex" and PSTicketMain.RecordStatus = "Active":
    for each PSTicketBlock no-lock where PSTicketBlock.TicketLinkID = PSTicketMain.ID:
        find last TransactionDetail no-lock where TransactionDetail.FileLinkCode2 = string(PSTicketBlock.ID) and TransactionDetail.RecordStatus = "Sold" and TransactionDetail.TransactionDate = 10/16/2024 no-error no-wait.
        if available TransactionDetail then 
        do:
            numRecs = numRecs + 1.
            run put-stream("~"" + PSTicketMain.TicketCode + "~",~"" + PSTicketMain.ShortDescription + "~",~"" + string(PSTicketBlock.ID) + "~",~"" + PSTicketBlock.Description + "~",~"" + string(TransactionDetail.CurrentReceipt) + "~",~"" + string(TransactionDetail.TransactionDate) + "~",~"" + string(TransactionDetail.TransactionTime / 86400) + "~",").
        end.
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findLastSoldTimesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findLastSoldTimesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findLastSoldTimesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "findLastSoldTimes.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Finds the time of the last ticket sold for each ticket block"
            BufActivityLog.Detail2       = "Check Document Center for findLastSoldTimesLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.