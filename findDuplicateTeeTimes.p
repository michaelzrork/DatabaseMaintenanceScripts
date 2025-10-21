/*------------------------------------------------------------------------
    File        : findDuplicateTeeTimes.p
    Purpose     : 

    Syntax      : 

    Description : Find duplicate Tee Times bewteen Course 1 and Course 2

    Author(s)   : michaelzr
    Created     : 10/29/2024
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
define variable numRecs           as integer no-undo.
define variable numRecsNoDupe     as integer no-undo.
define variable foundSADetail     as logical no-undo.
define variable numDeletedTeeTime as integer no-undo.
assign
    numRecs       = 0
    numRecsNoDupe = 0
    foundSADetail = false.
    
define buffer bufGRTeeTime for GRTeeTime.
define buffer bufTransactionDetail  for TransactionDetail.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Notes,GRTeeTime.ID,LogDate,GolfCourse,LinkCourse,TeeTimeDate,TeeTime,LinkedTime,TeeTimeType,StartingTee,RecordStatus,SlotsOpen,Dupe GRTeeTime.ID,LogDate,Dupe GolfCourse,Dupe LinkCourse,Dupe TeeTimeDate,Dupe TeeTime,Dupe LinkedTime,Dupe TeeTimeType,Dupe StartingTee,Dupe RecordStatus,Dupe SlotsOpen,").

for each GRTeeTime no-lock where GRTeeTime.GolfCourse = 2:
    for each bufGRTeeTime no-lock where bufGRTeeTime.GolfCourse = 1 and bufGRTeeTime.TeeTimeDate = GRTeeTime.TeeTimeDate and bufGRTeeTime.TeeTime = GRTeeTime.TeeTime and bufGRTeeTime.StartingTee = GRTeeTime.StartingTee and bufGRTeeTime.TeeTimeType = GRTeeTime.TeeTImeTYpe:
        assign 
            foundSADetail = false.
        for each TransactionDetail no-lock where TransactionDetail.MasterLinkID = bufGRTeeTime.ID:
            run put-stream("~"" + "Duplicate with TransactionDetail RecordStatus: " + getString(string(TransactionDetail.RecordStatus)) + "; Receipt Number: " + string(TransactionDetail.CurrentReceipt) + "~",~"" + trueval(string(GRTeeTime.ID)) + "~",~"" + getString(string(GRTeeTime.LogDate)) + "~",~"" + getString(string(GRTeeTime.GolfCourse)) + "~",~"" + getString(string(GRTeeTime.LinkCourse)) + "~",~"" + getString(string(GRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(GRTeeTime.TeeTime)) + "~",~"" + getString(string(GRTeeTime.LinkedTime)) + "~",~"" + getString(string(GRTeeTime.TeeTimeType)) + "~",~"" + getString(string(GRTeeTime.StartingTee)) + "~",~"" + getString(GRTeeTime.RecordStatus) + "~",~"" + getString(string(GRTeeTime.SlotsOpen)) + "~",~"" + getString(string(bufGRTeeTime.ID)) + "~",~"" + getString(string(bufGRTeeTime.LogDate)) + "~",~"" + getString(string(bufGRTeeTime.GolfCourse)) + "~",~"" + getString(string(bufGRTeeTime.LinkCourse)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(bufGRTeeTime.TeeTime)) + "~",~"" + getString(string(bufGRTeeTime.LinkedTime)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeType)) + "~",~"" + getString(string(bufGRTeeTime.StartingTee)) + "~",~"" + getString(string(bufGRTeeTime.RecordStatus)) + "~",~"" + getString(string(bufGRTeeTime.SlotsOpen)) + "~",").
            assign
                foundSADetail = true
                numRecs       = numRecs + 1.
        end.
        
        if foundSADetail = false then 
        do:
            run put-stream("~"" + "Duplicate with No TransactionDetail record; Tee Time Deleted" + "~",~"" + trueval(string(GRTeeTime.ID)) + "~",~"" + getString(string(GRTeeTime.LogDate)) + "~",~"" + getString(string(GRTeeTime.GolfCourse)) + "~",~"" + getString(string(GRTeeTime.LinkCourse)) + "~",~"" + getString(string(GRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(GRTeeTime.TeeTime)) + "~",~"" + getString(string(GRTeeTime.LinkedTime)) + "~",~"" + getString(string(GRTeeTime.TeeTimeType)) + "~",~"" + getString(string(GRTeeTime.StartingTee)) + "~",~"" + getString(GRTeeTime.RecordStatus) + "~",~"" + getString(string(GRTeeTime.SlotsOpen)) + "~",~"" + getString(string(bufGRTeeTime.ID)) + "~",~"" + getString(string(bufGRTeeTime.LogDate)) + "~",~"" + getString(string(bufGRTeeTime.GolfCourse)) + "~",~"" + getString(string(bufGRTeeTime.LinkCourse)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(bufGRTeeTime.TeeTime)) + "~",~"" + getString(string(bufGRTeeTime.LinkedTime)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeType)) + "~",~"" + getString(string(bufGRTeeTime.StartingTee)) + "~",~"" + getString(string(bufGRTeeTime.RecordStatus)) + "~",~"" + getString(string(bufGRTeeTime.SlotsOpen)) + "~",").
            numRecsNoDupe = numRecsNoDupe + 1.
            run deleteTeeTime(bufGRTeeTime.ID).
        end.
    end.
end. 
      
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findDuplicateTeeTimesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findDuplicateTeeTimesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE TEE TIME
procedure deleteTeeTime:
    define input parameter inpID as int64 no-undo.
    define buffer bufGRTeeTime2 for GRTeeTime.
    do for bufGRTeeTime2 transaction:
        find first bufGRTeeTime2 exclusive-lock where bufGRTeeTime2.ID = inpID no-error no-wait.
        if available bufGRTeeTime2 then 
        do:
            // run put-stream("~"" + "GRTeeTime Deleted for Course 1" + "~",~"" + trueval(string(GRTeeTime.ID)) + "~",~"" + getString(string(GRTeeTime.LogDate)) + "~",~"" + getString(string(GRTeeTime.GolfCourse)) + "~",~"" + getString(string(GRTeeTime.LinkCourse)) + "~",~"" + getString(string(GRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(GRTeeTime.TeeTime)) + "~",~"" + getString(string(GRTeeTime.LinkedTime)) + "~",~"" + getString(string(GRTeeTime.TeeTimeType)) + "~",~"" + getString(string(GRTeeTime.StartingTee)) + "~",~"" + getString(GRTeeTime.RecordStatus) + "~",~"" + getString(string(GRTeeTime.SlotsOpen)) + "~",~"" + getString(string(bufGRTeeTime.ID)) + "~",~"" + getString(string(bufGRTeeTime.LogDate)) + "~",~"" + getString(string(bufGRTeeTime.GolfCourse)) + "~",~"" + getString(string(bufGRTeeTime.LinkCourse)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(bufGRTeeTime.TeeTime)) + "~",~"" + getString(string(bufGRTeeTime.LinkedTime)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeType)) + "~",~"" + getString(string(bufGRTeeTime.StartingTee)) + "~",~"" + getString(string(bufGRTeeTime.RecordStatus)) + "~",~"" + getString(string(bufGRTeeTime.SlotsOpen)) + "~",").
            assign 
                numDeletedTeeTime = numDeletedTeeTime + 1.
            // delete bufGRTeeTime2.
        end.
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findDuplicateTeeTimesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
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
            BufActivityLog.SourceProgram = "findDuplicateTeeTimes.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find duplicate Tee Times bewteen Course 1 and Course 2"
            BufActivityLog.Detail2       = "Check Document Center for findDuplicateTeeTimesLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found with TransactionDetail Records: " + string(numRecs)
            BufActivityLog.Detail4       = "Number of Records Found with No TransactionDetail record: " + string(numRecsNoDupe)
            bufActivityLog.Detail5       = "Number of Deleted Tee Times for Course 1: " + string(numDeletedTeeTime).
    end.
end procedure.