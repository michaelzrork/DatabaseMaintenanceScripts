/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "FixChargePendingFees" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Fix for Charge Pending Fees Records time Count and Quantity"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 3/28/25
   Notes       : - There have been many attempts to write a quick fix to resolve this issue, but I think this is the cleanest and easiest way to do it
                 - Unlike previous attempts, the goal of this one is to just delete any Pending fee without a due option, regardless of if it's still in the Active/Pending
                   record status, or if it's been updated to Charge/Charge
                 - This will use the ParentID Charge.DueOption to confirm if it was legitimately supposed to be a Pending fee, if not, the ChargeHistory and Charge get deleted
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

function ParseList character (inputValue as char) forward.
function RoundUp returns decimal(dValue as decimal,precision as integer) forward.
function AddCommas returns character (dValue as decimal) forward.

define stream   ex-port.
define variable InpFile-Num as integer   no-undo init 1.
define variable InpFile-Loc as character no-undo init "".
define variable Counter     as integer   no-undo init 0.
define variable ixLog       as integer   no-undo init 1. 
define variable LogfileDate as date      no-undo.
define variable LogfileTime as integer   no-undo.
define variable ActivityLogID  as int64     no-undo init 0.
define variable LogOnly     as logical   no-undo init false.
define variable numRecs     as integer   no-undo init 0.
define variable ClientCode      as character no-undo init "".

// FILE IMPORT STUFF

{Includes/ProcessingConfig.i}
{Includes/TransactionDetailStatusList.i}
{Includes/TTVals.i}
{Includes/Screendef.i "reference-only"}  
{Includes/AvailableCredit.i}
{Includes/AvailableScholarship.i} 
{Includes/ModuleList.i} 
{Includes/TTProfile.i}

define variable importFileName as character no-undo.
define variable importfile     as char      no-undo.  
define variable tmpcode1       as char      no-undo. 

def stream exp.

def temp-table ttImport no-undo 
    field xID          as character 
    field cDescription as character 
    field dTimeCount   as character    
    field dQuantity    as character   
    index xID xID. 
    
assign 
    importFileName = "ChargeRecords.txt"
    tmpcode1       = "\Import\" + importFileName.

assign
    LogfileDate = today
    LogfileTime = time
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false.
    
define temp-table ttCharge
    field ID as int64
    index ID ID.
    
define temp-table ttDetail
    field ID as int64
    index ID ID.
    
define buffer bufFeeHist for ChargeHistory.

find first CustomField no-lock where CustomField.FieldName = "ClientID" no-error no-wait.
if available CustomField then assign ClientCode = getString(CustomField.FieldValue).

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

run ActivityLog({&ProgramDescription},"Program in Progress","Number of ChargeHistory Records Updated So Far: " + string(numRecs),"","").

// GRAB INPUT FILE FROM DOCUMENT CENTER IMPORT
CreateFile (tmpcode1, false, sessionTemp(), true, false) no-error. 

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Starting Process " + string(counter) + ",,,,").

assign
    Importfile = sessionTemp() + importFileName.

run put-stream (" 1 Importfile = " + Importfile + ",,,,").

// CHECK FOR IMPORT FILE
if search(Importfile) = ? then 
do:
    // IF NOT FOUND, CREATE ERROR RECORD AND END
    run ActivityLog("; Program aborted: " + Importfile + " not found!").
    run put-stream (" 1 Importfile Problem" + Importfile + " not found!,,,,").
    SaveFileToDocuments(inpfile-loc, "\Reports\", "", no, yes, yes, "Report").  
    return.
end.   
 
// SET IMPORT FILE
input stream exp from value(importfile) no-echo.

// RESET COUNTER FOR IMPORT LOOP
assign 
    counter = 0.

// CREATE TEMP TABLE FROM INPUT FILE VALUES
import-loop:
repeat transaction:
    create ttImport.
    import stream exp delimiter "," ttImport  no-error.
    counter = counter + 1.
end.

// CLOSE INPUT STREAM
input stream exp close.  

// LOG NUMBER OF RECORDS IMPORTED FROM IMPORT FILE
run put-stream ("ttImport Records imported =  " + string(counter) + ",,,,").

// RESET COUNTER FOR LOGFILE
assign 
    counter = 0.
  
// SET CHANGES HEADER
run put-stream(",,,,").
run put-stream("Table,ID,Original Time Count,Updated Time Count,Original Quantity,Updated Quantity,").
  
run put-stream (
    "ID," +
    "Old Time Count," +
    "New Time Count," +
    "Old Quantity," +
    "New Quantity,").
  
// REVERT CHANGES
ttImport-loop:
for each ttImport:
    if ttImport.xID = "" then delete ttImport.
    if ttImport.xID = "Table" then next ttImport-loop.
    run fixFeeHistory(int64(ttImport.xID),substring(ttImport.dTimeCount,index(ttImport.dTimeCount,"New: ") + 5),substring(ttImport.dQuantity,index(ttImport.dQuantity,"New: ") + 5)).
    run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record Updated: " + string(ttImport.xID),"Number of ChargeHistory Records Updated So Far: " + string(numRecs),"","").
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run UpdateActivityLog({&ProgramDescription},"Program Complete","Number of ChargeHistory Records Updated: " + string(numRecs),"","").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/
 
/*FIX FEE HISTORY */
procedure fixFeeHistory:
    define input parameter xID as int64 no-undo.
    define input parameter dTimeCount as decimal no-undo.
    define input parameter dQuantity as decimal no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = xID no-error no-wait.
        if available bufChargeHistory then
            run put-stream("~"" +
                /*ID*/
                getString(string(bufChargeHistory.ID))
                + "~",~"" +
                /*Old Time Count*/
                getString(string(bufChargeHistory.TimeCount))
                + "~",~"" +
                /*New Time Count*/
                getString(string(dTimeCount))
                + "~",~"" +
                /*Old Quantity*/
                getString(string(bufChargeHistory.Quantity))
                + "~",~"" +
                /*New Quantity*/
                getString(string(dQuantity))
                + "~",").
            assign
                numRecs                   = numRecs + 1
                bufChargeHistory.TimeCount = dTimeCount
                bufChargeHistory.Quantity  = dQuantity.
    end.
end procedure.
    
             
/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
    counter = counter + 1.
    if counter gt 100000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    define input parameter LogDetail5 as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = {&ProgramName} + ".r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = LogDetail1
            BufActivityLog.Detail2       = LogDetail2
            BufActivityLog.Detail3       = LogDetail3
            BufActivityLog.Detail4       = LogDetail4
            BufActivityLog.Detail5       = LogDetail5.
        /* IF THIS IS THE FIRST AUDIT LOG ENTRY, UPDATE THE ID FIELD */
        if ActivityLogID = 0 then 
            assign
                ActivityLogID = BufActivityLog.ID.
    end.
end procedure.

/* UPDATE AUDIT LOG STATUS ENTRY */
procedure UpdateActivityLog:
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    define input parameter LogDetail5 as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        if ActivityLogID = 0 then return.
        find first BufActivityLog exclusive-lock where BufActivityLog.ID = ActivityLogID no-error no-wait.
        if available BufActivityLog then 
            assign
                BufActivityLog.LogDate = today
                BufActivityLog.LogTime = time
                BufActivityLog.Detail1 = LogDetail1
                BufActivityLog.Detail2 = LogDetail2
                BufActivityLog.Detail3 = LogDetail3
                BufActivityLog.Detail4 = LogDetail4
                BufActivityLog.Detail5 = LogDetail5.
    end.
end procedure.

/*************************************************************************
                            INTERNAL FUNCTIONS
*************************************************************************/

/* FUNCTION RETURNS A COMMA SEPARATED LIST FROM CHR(30) SEPARATED LIST IN A SINGLE VALUE */
function ParseList character (inputValue as char):
    if index(inputValue,chr(31)) > 0 and index(inputValue,chr(30)) > 0 then 
        return replace(replace(inputValue,chr(31),": "),chr(30),", ").
    else if index(inputValue,chr(30)) > 0 and index(inputValue,chr(31)) = 0 then
            return replace(inputValue,chr(30),": ").
        else if index(inputValue,chr(30)) = 0 and index(inputValue,chr(31)) > 0 then
                return replace(inputValue,chr(31),": ").
            else return inputValue.
end.

/* FUNCTION RETURNS A DECIMAL ROUNDED UP TO THE PRECISION VALUE */
function RoundUp returns decimal(dValue as decimal,precision as integer):
    define variable newValue  as decimal   no-undo.
    define variable decLoc    as integer   no-undo.
    define variable tempValue as character no-undo.
    define var      tempInt   as integer   no-undo.
    
    /* IF THE TRUNCATED VALUE MATCHES THE INPUT VALUE, NO ROUNDING IS NECESSARY; RETURN THE ORIGINAL VALUE */
    if dValue - truncate(dValue,precision) = 0 then
        return dValue.
            
    /* IF THE ORIGINAL VALUE MINUS THE TRUNCATED VALUE LEAVES A REMAINDER THEN ROUND UP */
    else 
    do:
        assign
            /* FINDS THE LOCATION OF THE DECIMAL SO IT CAN BE ADDED BACK IN LATER */
            decLoc    = index(string(truncate(dValue,precision)),".")
            /* TRUNCATES TO THE PRECISION POINT, DROPS THE DECIMAL, CONVERTS TO AN INT, THEN IF NEGATIVE SUBTRACTS ONE, IF POSITIVE ADDS ONE */
            tempValue = string(integer(replace(string(truncate(dValue,precision)),".","")) + if dValue < 0 then -1 else 1).
        /* ADDS THE DECIMAL BACK IN AT THE ORIGINAL LOCATION */
        assign 
            substring(tempValue,(if decLoc = 0 then length(tempValue) + 1 else decLoc),0) = ".".
        /* RETURNS THE RESULTING VALUE AS A DECIMAL */ 
        return decimal(tempValue).
    end.
end.

/* FUNCTION RETURNS A NUMBER AS A CHARACTER WITH ADDED COMMAS */
function AddCommas returns character (dValue as decimal):
    define variable absValue     as decimal   no-undo.
    define variable iValue       as integer   no-undo.
    define variable cValue       as character no-undo.
    define variable ix           as integer   no-undo.
    define variable decimalValue as character no-undo.
    define variable decLoc       as integer   no-undo.
    assign
        absValue     = abs(dValue)
        decLoc       = index(string(absValue),".")
        decimalValue = substring(string(absValue),(if decLoc = 0 then length(string(absValue)) + 1 else decLoc))
        iValue       = truncate(absValue,0)
        cValue       = string(iValue).
    do ix = 1 to roundUp(length(string(iValue)) / 3,0) - 1:
        assign 
            substring(cValue,length(string(iValue)) - ((ix * 3) - 1),0) = ",".
    end.
    return (if dValue < 0 then "-" else "") + cValue + decimalValue.
end.