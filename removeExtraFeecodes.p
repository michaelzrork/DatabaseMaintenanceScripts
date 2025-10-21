/*------------------------------------------------------------------------
    File        : removeExtraFeecodes.p
    Purpose     : 

    Syntax      : 

    Description : Remove Extra Feecodes

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

define variable feecodeList  as character no-undo.
define variable ix           as integer   no-undo.
define variable iy           as integer   no-undo.
define variable feecodeCount as integer   no-undo.

assign 
    ix           = 0
    iy           = 0
    feecodeList  = ""
    feecodeCount = 0.

for each LookupCode no-lock where LookupCode.RecordType = "Fee":
    feecodeList = list(LookupCode.RecordCode,feecodeList).
end.

run put-stream ("Household ID,Household Number,Original Feecode List,New Feecode List").

/* FIND ANY HOUSEHOLD THAT HAS MORE THAN ONE FEECODE - THIS WON'T BE HOUSEHOLDS WITH MULTIPLES OF THE SAME FEECODE, BUT IF THEY ONLY HAVE ONE FEECODE WE DON'T CARE */
/* BASICALY, NUM-ENTRIES ONLY COUNTS THE TOTAL NUMBER OF ITEMS, AND THERE ISN'T A WAY TO COUNT HOW MANY OF ONE SPECIFIC ITEM THAT I COULD FIND OR FIGURE OUT */
for each Account no-lock where num-entries(Account.CodeValue) > 1:
    do ix = 1 to num-entries(feecodeList):
        assign 
            feecodeCount = 0.
        do iy = 1 to num-entries(Account.CodeValue) while feecodeCount < 2:
            if entry(iy,Account.CodeValue) = entry(ix,feecodeList) then assign feecodeCount = feecodeCount + 1.
        end.
        if feecodeCount > 1 then run removeExtraFeecode(Account.ID,entry(ix,feecodeList)).
    end.
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "removeExtraFeecodesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "removeExtraFeecodesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIX FEECODE LIST
procedure removeExtraFeecode:
    define input parameter inpID as int64 no-undo.
    define input parameter feecodeToRemove as character no-undo.
    define variable originalFeecodeList as character no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufSAhousehold.ID = inpID no-error no-wait.
        assign
            /* SET THE ORIGINAL FEECODE LIST FOR THE LOGFILE */
            originalFeecodeList    = bufAccount.CodeValue
            /* FIRST WE REMOVE IT FROM THE LIST */  
            bufAccount.CodeValue = removeList(feecodeToRemove,bufAccount.CodeValue)
            /* THEN WE ADD IT BACK IN */
            bufAccount.CodeValue = list(feecodeToRemove,bufAccount.CodeValue).
        /* LOG THE CHANGES */
        run put-stream ("~"" +
            /*Household ID*/
            getString(string(bufAccount.ID))
            + "~",~"" +
            /*Household Number*/
            getString(string(bufAccount.EntityNumber))
            + "~",~"" +
            /*Original Feecode List*/
            getString(originalFeecodeList)
            + "~",~"" +
            /*New Feecode List*/
            getString(bufAccount.CodeValue)
            + "~",").
        assign 
            numRecs = numRecs + 1.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "removeExtraFeecodesLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "removeExtraFeecodes.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Remove Extra Feecodes"
            BufActivityLog.Detail2       = "Check Document Center for removeExtraFeecodesLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.