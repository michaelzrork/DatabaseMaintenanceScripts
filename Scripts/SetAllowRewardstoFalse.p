/*------------------------------------------------------------------------
    File        : SetAllowRewardstoFalse.p
    Purpose     : Set all households to not allow rewards

    Syntax      : 

    Description : Customer would like to set all Households to not allow rewards
                    so that they can enable household rewards based on their own criteria

    Author(s)   : MichaelZR
    Created     : 10/9/2023
    Notes       : 5/29/2024 - Updated to be a universal fix; can now be run in any database without a date
                            - If it has not been run before, it will use 1/1/1985 for the household creation date
                            - If it has been run before, it will find the last date it was run and use that as the household creation date 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recordCount as integer no-undo.
define variable startDate as date no-undo.
assign 
    recordCount = 0
    startDate   = ?.

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

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

ActivityLog-loop:
for each ActivityLog no-lock where ActivityLog.SourceProgram = "SetAllowRewardstoFalse.p" by ActivityLog.LogDate descending:
    assign 
        startDate = ActivityLog.LogDate.
    leave ActivityLog-loop.
end.

if startDate = ? then startDate = 01/01/1985.

// CREATE LOG FILE FIELDS
run put-stream ("Household Number,Original Rewards Status,Household Creation Date").

for each Account no-lock where Account.AllowRewards = true and Account.CreationDate ge startDate:
    run setRewardstoFalse(Account.ID).
end.

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "SetAllowRewardstoFalseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "SetAllowRewardstoFalseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SET ALL RECORDS TO ALLOW REWARDS: FALSE
procedure setRewardstoFalse:
    define input parameter inpid as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then 
        do:
            // CREATE LOG ENTRY "Match,Fields,To,Headers"
            run put-stream (string(bufAccount.EntityNumber) + "," + string(bufAccount.AllowRewards) + "," + string(bufAccount.CreationDate)).
            assign
                recordCount                 = recordCount + 1
                bufAccount.AllowRewards = false.
        end.
    end. // DO FOR
end procedure.
 
 // CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "SetAllowRewardstoFalseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "SetAllowRewardstoFalse.p"
            BufActivityLog.LogDate       = today            
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Check Document Center for " + "SetAllowRewardstoFalseLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_*.csv" + " for a log of Records Changed"
            BufActivityLog.Detail2       = "Number of Households Updated using HH creation date of " + string(startDate) + ": " + string(recordCount).
    end.
  
end procedure.