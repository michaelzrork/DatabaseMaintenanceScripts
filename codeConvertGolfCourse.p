/*------------------------------------------------------------------------
    File        : codeConvertGolfCourse.p
    Purpose     : 

    Syntax      : 

    Description : Convert Golf Course 2 to Course 1

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
define variable numDeletedCourse2  as integer no-undo.
define variable numDeletedCourse1  as integer no-undo.
define variable numDeletedTeeTime  as integer no-undo.
define variable numDupesNotDeleted as integer no-undo.
define variable numRecs            as integer no-undo.
define variable numDetail          as integer no-undo.
define variable oldCourseID        as int64   no-undo.
define variable newCourseID        as int64   no-undo.
define variable numMasterLink      as integer no-undo.
assign
    numDeletedCourse2  = 0
    numDeletedCourse1  = 0
    numDupesNotDeleted = 0
    numDeletedTeeTime  = 0
    numRecs            = 0
    numDetail          = 0
    oldCourseID        = 21679903
    newCourseID        = 13642921
    numMasterLink      = 0.
    
define buffer bufGRTeeTime for GRTeeTime.
define buffer bufTransactionDetail  for TransactionDetail.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Notes,GRTeeTime.ID,LogDate,GolfCourse,LinkCourse,TeeTimeDate,TeeTime,LinkedTime,TeeTimeType,StartingTee,RecordStatus,SlotsOpen,Dupe GRTeeTime.ID,LogDate,Dupe GolfCourse,Dupe LinkCourse,Dupe TeeTimeDate,Dupe TeeTime,Dupe LinkedTime,Dupe TeeTimeType,Dupe StartingTee,Dupe RecordStatus,Dupe SlotsOpen,").

// TEE TIME LOOP
teetime-loop:
for each GRTeeTime no-lock where GRTeeTime.GolfCourse = 2:
    // FIND DUPLICATE TEE TIMES FOR COURSE 1
    for first bufGRTeeTime no-lock where bufGRTeeTime.GolfCourse = 1 and bufGRTeeTime.TeeTimeDate = GRTeeTime.TeeTimeDate and bufGRTeeTime.TeeTime = GRTeeTime.TeeTime and bufGRTeeTime.StartingTee = GRTeeTime.StartingTee and bufGRTeeTime.TeeTimeType = GRTeeTime.TeeTImeType:
        // IF THERE IS A DUPLICATE COURSE 1 TEE TIME, FIND SADETAIL RECORDS FOR COURSE 1 TEE TIME
        for first TransactionDetail no-lock where TransactionDetail.MasterLinkID = bufGRTeeTime.ID and lookup(TransactionDetail.RecordStatus,"Removed,Cancelled") = 0:
            // IF THERE IS AN SADETAIL RECORD FOR COURSE 1 TEE TIME, FIND SADETAIL RECORDS FOR COURSE 2 TEE TIME
            for first bufTransactionDetail no-lock where bufTransactionDetail.MasterLinkID = GRTeeTime.ID and lookup(bufTransactionDetail.RecordStatus,"Removed,Cancelled") = 0:
                // IF BOTH COURSES HAVE SADETAIL RECORDS, LOG AND CHECK NEXT TEE TIME
                run put-stream("~"" + "Duplicate with TransactionDetail Record; Both courses have TransactionDetail records" + "~",~"" + trueval(string(GRTeeTime.ID)) + "~",~"" + getString(string(GRTeeTime.LogDate)) + "~",~"" + getString(string(GRTeeTime.GolfCourse)) + "~",~"" + getString(string(GRTeeTime.LinkCourse)) + "~",~"" + getString(string(GRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(GRTeeTime.TeeTime)) + "~",~"" + getString(string(GRTeeTime.LinkedTime)) + "~",~"" + getString(string(GRTeeTime.TeeTimeType)) + "~",~"" + getString(string(GRTeeTime.StartingTee)) + "~",~"" + getString(GRTeeTime.RecordStatus) + "~",~"" + getString(string(GRTeeTime.SlotsOpen)) + "~",~"" + getString(string(bufGRTeeTime.ID)) + "~",~"" + getString(string(bufGRTeeTime.LogDate)) + "~",~"" + getString(string(bufGRTeeTime.GolfCourse)) + "~",~"" + getString(string(bufGRTeeTime.LinkCourse)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(bufGRTeeTime.TeeTime)) + "~",~"" + getString(string(bufGRTeeTime.LinkedTime)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeType)) + "~",~"" + getString(string(bufGRTeeTime.StartingTee)) + "~",~"" + getString(string(bufGRTeeTime.RecordStatus)) + "~",~"" + getString(string(bufGRTeeTime.SlotsOpen)) + "~",").
                assign 
                    numDupesNotDeleted = numDupesNotDeleted + 1.
            end.
            // IF ONLY COURSE 1 HAS SADETAIL RECORDS, DELETE TEE TIME FOR COURSE 2 THEN MOVE TO THE NEXT TEE TIME
            if not available bufTransactionDetail then 
            do:
                run put-stream("~"" + "Duplicate with TransactionDetail Record; Course 2 Tee Time Deleted" + "~",~"" + trueval(string(GRTeeTime.ID)) + "~",~"" + getString(string(GRTeeTime.LogDate)) + "~",~"" + getString(string(GRTeeTime.GolfCourse)) + "~",~"" + getString(string(GRTeeTime.LinkCourse)) + "~",~"" + getString(string(GRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(GRTeeTime.TeeTime)) + "~",~"" + getString(string(GRTeeTime.LinkedTime)) + "~",~"" + getString(string(GRTeeTime.TeeTimeType)) + "~",~"" + getString(string(GRTeeTime.StartingTee)) + "~",~"" + getString(GRTeeTime.RecordStatus) + "~",~"" + getString(string(GRTeeTime.SlotsOpen)) + "~",~"" + getString(string(bufGRTeeTime.ID)) + "~",~"" + getString(string(bufGRTeeTime.LogDate)) + "~",~"" + getString(string(bufGRTeeTime.GolfCourse)) + "~",~"" + getString(string(bufGRTeeTime.LinkCourse)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(bufGRTeeTime.TeeTime)) + "~",~"" + getString(string(bufGRTeeTime.LinkedTime)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeType)) + "~",~"" + getString(string(bufGRTeeTime.StartingTee)) + "~",~"" + getString(string(bufGRTeeTime.RecordStatus)) + "~",~"" + getString(string(bufGRTeeTime.SlotsOpen)) + "~",").
                assign
                    numDeletedCourse2 = numDeletedCourse2 + 1.
                run deleteTeeTime(GRTeeTime.ID,bufGRTeeTime.ID).
                next teetime-loop.
            end.
        end.
        // IF COURSE 1 HAS NO SADETAIL RECORDS, DELETE THE COURSE 1 TEE TIME AND CHANGE COURSE 2 TO COURSE 1
        if not available TransactionDetail then 
        do:
            run put-stream("~"" + "Duplicate with No TransactionDetail record; Course 1 Tee Time Deleted" + "~",~"" + trueval(string(GRTeeTime.ID)) + "~",~"" + getString(string(GRTeeTime.LogDate)) + "~",~"" + getString(string(GRTeeTime.GolfCourse)) + "~",~"" + getString(string(GRTeeTime.LinkCourse)) + "~",~"" + getString(string(GRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(GRTeeTime.TeeTime)) + "~",~"" + getString(string(GRTeeTime.LinkedTime)) + "~",~"" + getString(string(GRTeeTime.TeeTimeType)) + "~",~"" + getString(string(GRTeeTime.StartingTee)) + "~",~"" + getString(GRTeeTime.RecordStatus) + "~",~"" + getString(string(GRTeeTime.SlotsOpen)) + "~",~"" + getString(string(bufGRTeeTime.ID)) + "~",~"" + getString(string(bufGRTeeTime.LogDate)) + "~",~"" + getString(string(bufGRTeeTime.GolfCourse)) + "~",~"" + getString(string(bufGRTeeTime.LinkCourse)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeDate)) + "~",~"" + getString(string(bufGRTeeTime.TeeTime)) + "~",~"" + getString(string(bufGRTeeTime.LinkedTime)) + "~",~"" + getString(string(bufGRTeeTime.TeeTimeType)) + "~",~"" + getString(string(bufGRTeeTime.StartingTee)) + "~",~"" + getString(string(bufGRTeeTime.RecordStatus)) + "~",~"" + getString(string(bufGRTeeTime.SlotsOpen)) + "~",").
            assign 
                numDeletedCourse1 = numDeletedCourse1 + 1.
            run changeCourse(GRTeeTime.ID).
            run deleteTeeTime(bufGRTeeTime.ID,GRTeeTime.ID).
            next teetime-loop.
        end.
    end.
    // IF THERE ARE NO DUPLICATE TEE TIMES, CHANGE COURSE 2 TO COURSE 1
    if not available bufGRTeeTime then 
    do:
        run changeCourse(GRTeeTime.ID).
    end.
end.

for each TransactionDetail no-lock where TransactionDetail.FileLinkID = oldCourseID:
    find first GRTeeTime no-lock where GRTeeTime.ID = TransactionDetail.MasterLinkID no-error no-wait.
    if not available GRTeeTime then run put-stream("~"" + "GRTeeTime record not found for TransactionDetail record" + "~",~"" + "TransactionDetail.ID = " + string(TransactionDetail.ID) + "~",~"" + "TransactionDetail.MasterlinkID = " + string(TransactionDetail.MasterLinkID) + "~",~"" + "TransactionDetail.Description = " + TransactionDetail.Description + "~",~"" + "TransactionDetail.BeginDate = " + getString(string(TransactionDetail.BeginDate)) + "~",~"" + "TransactionDetail.BeginTime = " + getString(string(TransactionDetail.BeginTime)) + "~",~"" + "TransactionDetail.RecordStatus = " + TransactionDetail.RecordStatus + "~",~"" + "TransactionDetail.CartStatus = " + TransactionDetail.CartStatus + "~","). 
    run changeDetail(TransactionDetail.ID).
end.
      
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "codeConvertGolfCourseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "codeConvertGolfCourseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHANGE COURSE 2 TEE TIMES TO COURSE 1
procedure changeCourse:
    define input parameter inpID as int64 no-undo.
    define buffer bufGRTeeTime3 for GRTeeTime.
    do for bufGRTeeTime3 transaction:
        find first bufGRTeeTime3 exclusive-lock where bufGRTeeTime3.ID = inpID no-error no-wait.
        if available bufGRTeeTime3 then
            assign
                bufGRTeeTime3.GolfCourse = 1
                bufGRTeeTime3.LinkCourse = 1
                numRecs                  = numRecs + 1.
    end.
end.

// CHANGE THE SADETAIL RECORD DETAILS
procedure changeDetail:
    define input parameter inpID as int64 no-undo.
    define buffer bufDetail1 for TransactionDetail.
    do for bufDetail1 transaction:
        find first bufDetail1 exclusive-lock where bufDetail1.ID = inpID no-error no-wait.
        if available bufDetail1 then 
        do:
            assign 
                bufDetail1.FileLinkID    = newCourseID
                bufDetail1.FileLinkCode1 = "1"
                bufDetail1.FileLinkCode4 = "1"
                numDetail                  = numDetail + 1.
        end.
    end.
end.

// DELETE TEE TIME
procedure deleteTeeTime:
    define input parameter inpID as int64 no-undo.
    define input parameter newTeeTime as int64 no-undo.
    define buffer bufGRTeeTime2 for GRTeeTime.
    define buffer bufDetail2  for TransactionDetail.
    do for bufGRTeeTime2 transaction:
        find first bufGRTeeTime2 exclusive-lock where bufGRTeeTime2.ID = inpID no-error no-wait.
        if available bufGRTeeTime2 then 
        do:
            for each bufDetail2 exclusive-lock where bufDetail2.MasterLinkID = inpID:
                assign 
                    bufDetail2.MasterLinkID = newTeeTime
                    numMasterLink             = numMasterLink + 1.
            end.
            assign 
                numDeletedTeeTime = numDeletedTeeTime + 1.
            delete bufGRTeeTime2.
        end.
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "codeConvertGolfCourseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "codeConvertGolfCourse.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Convert Golf Course 2 to Course 1"
            BufActivityLog.Detail2       = "Check Document Center for codeConvertGolfCourseLog for a log of Records Changed"
            bufActivityLog.Detail3       = "Number of Tee Times changed to Course 1: " + string(numRecs)
            BufActivityLog.Detail4       = "Number of Course 2 Tee Times Deleted: " + string(numDeletedCourse2)
            BufActivityLog.Detail5       = "Number of Course 1 Tee Times Deleted: " + string(numDeletedCourse1)
            bufActivityLog.Detail6       = "Number of Duplicate Tee Times not deleted: " + string(numDupesNotDeleted)
            bufActivityLog.Detail7       = "Number of TransactionDetail Records updated to Course 1: " + string(numDetail)
            bufActivityLog.Detail8       = "Number of TransactionDetail records MasterLinkID updated: " + string(numMasterLink).
    end.
end procedure.