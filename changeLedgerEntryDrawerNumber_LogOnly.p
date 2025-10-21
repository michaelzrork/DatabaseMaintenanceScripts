/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "changeSAGLDistributionDrawerNumber_LogOnly" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Prefix LedgerEntry drawer numbers with ~'33~'"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */

/*------------------------------------------------------------------------
    File        : changeSAGLDistributionDrawerNumber.p
    Purpose     : Prefix all drawer numbers with "33" for transactions between June 1, 2024 - July 31, 2024.
                 Avoid modifying the same drawer number multiple times.
    Author(s)   : michaelzrork,Updated by: Darby Scott
    Created     : 2/7/25, 4/22/25
    Notes       : Updated to ensure drawer numbers are updated only if not already prefixed.
  ----------------------------------------------------------------------*/
  
/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num  as integer   no-undo init 1.
define variable inpfile-loc  as character no-undo.
define variable counter      as integer   no-undo.
define variable ixLog        as integer   no-undo. 
define variable logfileDate  as date      no-undo.
define variable logfileTime  as integer   no-undo.
define variable LogOnly      as logical   no-undo init false.
define variable receiptMatch as integer   no-undo init 0.
define variable numRecs      as integer   no-undo init 0. 
define variable newDrawer    as integer   no-undo init 0.

assign
    logfileDate = today
    logfileTime = time
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false.
    
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

/*************************************************************************
                            MAIN BLOCK
*************************************************************************/
run put-stream (
    "ID," +
    "Receipt Number," +
    "Posting Date," +
    "Original Drawer Number," +
    "New Drawer Number,").

receipt-loop:
for each LedgerEntry no-lock:
    
    /* SKIP THEIR TEST DRAWER */
    if LedgerEntry.CashDrawer = 9999 then next receipt-loop.
    
    /* SKIP DRAWERS ALREADY PREFIXED WITH 33 */
    if string(LedgerEntry.CashDrawer) begins "33" then next receipt-loop.
    
    /* SKIP RECORDS OUTSIDE OF DATE RANGE */
    if LedgerEntry.PostingDate < 6/1/2024 or LedgerEntry.PostingDate > 7/31/2024 then next receipt-loop.
    
    /* SET NEW DRAWER AND RECEIPT NUMBER */
    assign
        numRecs      = numRecs + 1
        newDrawer    = integer("33" + string(LedgerEntry.CashDrawer))
        receiptMatch = LedgerEntry.ReceiptNumber.
        
    run put-stream ("~"" +
        /*ID*/
        getString(string(LedgerEntry.ID))
        + "~",~"" +
        /*Receipt Number*/
        getString(string(receiptMatch))
        + "~",~"" +
        /*Posting Date*/
        getString(string(LedgerEntry.PostingDate))
        + "~",~"" +
        /*Original Drawer Number*/
        getString(string(LedgerEntry.CashDrawer))
        + "~",~"" +
        /*New Drawer Number*/
        getString(string(newDrawer))
        + "~",").
        
    /* SKIP CHANGING RECORDS IF WE JUST WANT A LOGFILE */
    if LogOnly then next receipt-loop.   
     
    /* UPDATE DRAWER */
    run fixSAGLDistributionDrawer(LedgerEntry.ID).
end.


/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "~\Reports~\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog(
    {&ProgramDescription}
    ,"Check Document Center for " + {&ProgramName} + "Log for a log of Records Changed"
    ,"Number of Records Found: " + AddCommas(numRecs)
    ,""
    ).
    
/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* Fix Functions */
procedure fixSAGLDistributionDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufLedgerEntry for LedgerEntry.
    do for bufLedgerEntry transaction:
        find first bufLedgerEntry exclusive-lock where bufLedgerEntry.ID = inpID no-error no-wait.
        if available bufLedgerEntry then assign
                bufLedgerEntry.CashDrawer = newDrawer.
    end.
end.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
    define input parameter logDetail1 as character no-undo.
    define input parameter logDetail2 as character no-undo.
    define input parameter logDetail3 as character no-undo.
    define input parameter logDetail4 as character no-undo.
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = {&ProgramName} + ".r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail1
            bufActivityLog.Detail2       = logDetail2
            bufActivityLog.Detail3       = logDetail3
            bufActivityLog.Detail4       = logDetail4.
    end.
end procedure.
