/*------------------------------------------------------------------------
    File        : removeHolidays.p
    Purpose     : 

    Syntax      : 

    Description : Remove Holidays added with the wrong date

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

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Record ID,Meeting Date,ActivityLinkID,Activity/Section Code,Section Description,").

for each ARSchedule no-lock where ARSchedule.meetingdate ge 11/17/2024 and ARSchedule.meetingdate le 11/23/2024 and ARSchedule.holiday = true:
    find first ARSection no-lock where ARSection.ID = ARSchedule.ActivityLinkID no-error no-wait.
    if available ARSection then run deleteARSchedule(ARSchedule.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "removeHolidaysLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "removeHolidaysLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE AR SCHEDULE
procedure deleteARSchedule:
    define input parameter inpID as int64.
    define buffer bufARSchedule for ARSchedule.
    do for bufARSchedule transaction:
        find first bufARSchedule exclusive-lock where bufARSchedule.ID = inpid no-error no-wait.
        if available bufARSchedule then 
        do:
            numRecs = numRecs + 1.
            run put-stream ("~"" + string(bufARSchedule.ID) + "~",~"" + string(bufARSchedule.MeetingDate) + "~",~"" + string(bufARSchedule.ActivityLinkID) + "~",~"" + ARSection.ComboKey + "~",~"" + ARSection.ShortDescription + "~",").
            delete bufARSchedule.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "removeHolidaysLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "removeHolidays.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Remove Holidays added with the wrong date"
            BufActivityLog.Detail2       = "Check Document Center for removeHolidaysLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.