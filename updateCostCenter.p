/*------------------------------------------------------------------------
    File        : updateCostCenter.p
    Purpose     : 

    Syntax      : 

    Description : Update Cost Center for GL Distribution and Control Account History

    Author(s)   : michaelzr
    Created     : 12/9/2024
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
define variable numRecs       as integer   no-undo.
define variable numRecs2      as integer   no-undo.
define variable checkGL       as int       no-undo.
define variable checkDate     as date      no-undo.
define variable newCostCenter as character no-undo.

assign
    numRecs       = 0
    numRecs2      = 0
    checkGL       = 263
    checkDate     = 10/17/2024
    newCostCenter = "1PG2400".
/*    checkGL       = 1                    */
/*    checkDate     = 10/17/2021           */
/*    newCostCenter = "superNewCostCenter".*/


/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ID,Table,Date,Receipt Number,GL Code,Original Cost Center,New Cost Center,").

for each LedgerEntry no-lock where LedgerEntry.AccountCode = checkGL and LedgerEntry.PostingDate > checkDate and LedgerEntry.CostCenter <> newCostCenter:
    run updateGLCostCenter(LedgerEntry.ID).
end.

for each AccountBalanceLog no-lock where AccountBalanceLog.DebitCredit = "Credit" and AccountBalanceLog.FullyUsed = no and AccountBalanceLog.CostCenter <> newCostCenter:
    run updateControlAccountCostCenter(AccountBalanceLog.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "updateCostCenterLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "updateCostCenterLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// UPDATE GL DISTRIBUTION COST CENTER
procedure updateGLCostCenter:
    define input parameter inpID as int64 no-undo.
    define buffer bufLedgerEntry for LedgerEntry.
    do for bufLedgerEntry transaction:
        find first bufLedgerEntry exclusive-lock where bufLedgerEntry.ID = inpID no-error no-wait.
        if available bufLedgerEntry then 
        do:
            run put-stream(string(bufLedgerEntry.ID) + ",~"" + "LedgerEntry" + "~",~"" + getString(string(bufLedgerEntry.PostingDate)) + "~",~"" + string(bufLedgerEntry.ReceiptNumber) + "~",~"" + getString(string(bufLedgerEntry.AccountCode)) + "~",~"" + getString(bufLedgerEntry.CostCenter) + "~",~"" + newCostCenter + "~",").
            assign
                bufLedgerEntry.CostCenter = newCostCenter
                numRecs                        = numRecs + 1.
        end.
    end.
end procedure.
                
// UPDATE CONTROL ACCOUNT COST CENTER
procedure updateControlAccountCostCenter:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccountBalanceLog for AccountBalanceLog.
    do for bufAccountBalanceLog transaction:
        find first bufAccountBalanceLog exclusive-lock where bufAccountBalanceLog.ID = inpID no-error no-wait.
        if available bufAccountBalanceLog then 
        do:
            run put-stream(string(bufAccountBalanceLog.ID) + ",~"" + "AccountBalanceLog" + "~",~"" + getString(string(bufAccountBalanceLog.PostingDate)) + "~",~"" + string(bufAccountBalanceLog.ReceiptNumber) + "~",~"" + getString(string(bufAccountBalanceLog.AccountCode)) + "~",~"" + getString(bufAccountBalanceLog.CostCenter) + "~",~"" + newCostCenter + "~",").
            assign
                bufAccountBalanceLog.CostCenter = newCostCenter
                numRecs2                              = numRecs2 + 1.
        end.
    end.
end procedure.


// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "updateCostCenterLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "updateCostCenter.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Update Cost Center for GL Distribution and Control Account History"
            BufActivityLog.Detail2       = "Check Document Center for updateCostCenterLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of GLDistribution Records Updated: " + string(numRecs) + "; Number of AccountBalanceLog Records Updated: " + string(numRecs2).
    end.
end procedure.