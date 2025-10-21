/*------------------------------------------------------------------------
    File        : performanceCheck.p
    Purpose     : 

    Syntax      : 

    Description : Meant to find how long a query takes

    Author(s)   : michaelzrork
    Created     : 2/13/25
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs          as integer   no-undo.
define variable startTime        as integer   no-undo.
define variable endTime          as integer   no-undo.
define variable trialDescription as character no-undo.
define variable trialRun         as integer   no-undo.
define variable tmpTrialRun      as character no-undo.
define variable trialNum         as integer   no-undo.
define variable trialName         as character no-undo.
define variable ix               as integer   no-undo.
define variable isNumber         as logical   no-undo.

assign
    numRecs          = 0
    startTime        = 0
    endTime          = 0
    trialNum         = 0
    trialDescription = "" // LEAVE BLANK AND UPDATE IN EACH TRIAL HEADER
    tmpTrialRun      = ""
    trialRun         = 1
    ix               = 1
    isNumber         = true    
    trialName         = "Trial Name". // CHANGE TO TRIAL NAME
    
define temp-table ttChangeRecord no-undo
    field id         as int64 
    field xTable     as character
    field oldPaycode as character 
    field newPaycode as character
    index xTable xTable
    index id     id.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for last ActivityLog no-lock where ActivityLog.SourceProgram = "performanceCheck.r" and ActivityLog.Detail1 begins trialName by ID:
    tmpTrialRun = substring(ActivityLog.Detail1,index(ActivityLog.Detail1,"_") - 2,2).
    do ix = 1 to 2 while isNumber = yes:
        isNumber = if lookup(substring(tmpTrialRun,ix,1),"0,1,2,3,4,5,6,7,8,9") > 0 then yes else no.
    end.
    trialRun = if isNumber then integer(tmpTrialRun) else 1.
end.

// **********************************************************************
trialDescription = "TRIAL DESCRIPTION".
// **********************************************************************

empty temp-table ttChangeRecord no-error.

assign 
    startTime = mtime
    numRecs   = 0
    trialNum  = trialNum + 1.
    
// TRIAL CODE

assign 
    endTime = mtime.

run ActivityLog(trialName + " Trial " + (if trialRun < 10 then "0" else "") + string(trialRun) + "_" + (if trialNum < 10 then "0" else "") + string(trialNum) + " - " + trialDescription).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    define input parameter logDetail as character no-undo.
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "performanceCheck.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail
            bufActivityLog.Detail2       = "Time Elapsed: " + string(endTime - startTime)
            bufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.