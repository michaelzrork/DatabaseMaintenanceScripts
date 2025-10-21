/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "programName" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME, DO NOT INCLUDE THE .p OR .r */
&global-define ProgramDescription "Program Description"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
 /*----------------------------------------------------------------------
    Author(s):   
    Created  :  
    Notes    :  
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
define variable inpfile-num as integer   no-undo init 1.
define variable inpfile-loc as character no-undo init "".
define variable counter     as integer   no-undo init 0.
define variable ixLog       as integer   no-undo init 1. 
define variable logfileDate as date      no-undo.
define variable logfileTime as integer   no-undo.
define variable LogOnly     as logical   no-undo init false.
define variable ActivityLogID  as int64     no-undo init 0. 
define variable ClientCode      as character no-undo init "".
define variable cLastID     as character no-undo init "".
define variable LastTable   as character no-undo init "".
define variable numRecs     as integer   no-undo init 0.

assign
    /* TO SET PROGRAM TO 'LOG ONLY' ADD 'LogOnly' ANYWHERE IN THE GLOBAL VARIABLE PROGRAM NAME eg. 'ProgramName_LogOnly' */
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false // USE THIS VARIABLE TO HALT CHANGES WHEN LOG ONLY eg. 'if not LogOnly then assign'
    logfileDate = today
    logfileTime = time.
    
find first CustomField no-lock where CustomField.FieldName = "ClientID" no-error no-wait.
if available CustomField then assign ClientCode = CustomField.FieldValue.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
/* I FIXED THE LAST RECORD EXTRA SPACE ISSUE BY CHANGING THE FORMAT (X800) TO UNFORMATTED, SO EXTRA COMMAS ARE NO LONGER NECESSARY */
run put-stream (
    "Put," +
    "Field," +
    "Headers," +
    "Here").

/* CREATE INITIAL AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},
    "Program in Progress",
    "Number of Records Found So Far: " + addCommas(numRecs),
    "",
    "").

/* MAIN CODE BLOCK */


/* UPDATE AUDIT LOG WITH LAST RECORD ID AND TABLE */
/* USE THIS WITHIN YOUR MAIN LOOP OR PROCEDURES */
assign 
    cLastID   = getString(string(0)) // REPLACE 0 WITH TABLENAME.ID 
    LastTable = "<TABLE NAME>". // REPLACE <TABLE NAME> WITH THE TABLE NAME
run UpdateActivityLog({&ProgramDescription},
    "Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),
    "Number of Records Found So Far: " + addCommas(numRecs),
    "",
    "").

/* UPDATE AUDIT LOG TO SAY THE LOGFILE IS BEING CREATED */
run UpdateActivityLog({&ProgramDescription},
    "Program in Progress; Logfile is being created...",
    "Number of Records Found: " + addCommas(numRecs),
    "",
    "").  
    
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "~\Reports~\", "", no, yes, yes, "Report").  
end.

/* UPDATE AUDIT LOG ENTRY WITH FINAL COUNTS */
run UpdateActivityLog({&ProgramDescription},
    "Program is Complete; Check Document Center for a log of Records Changed",
    "Number of Records Found: " + addCommas(numRecs),
    "",
    "").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* USE THIS WITHIN YOUR MAIN BLOCK OR PROCEDURE TO ADD THE LOGFILE RECORDS */
run put-stream ("~"" +
    /*REPLACE THIS TEXT WITH FIRST HEADER, THEN COPY THE FOLLOWING CODE BETWEEN HEADERS STARTING HERE-->*/
    "" // REPLACE THIS LINE WITH YOUR DATA
    + "~",~"" +
    /*<--THROUGH HERE, THEN REPLACE THIS TEXT WITH THE SECOND HEADER, AND PASTE COPIED CODE HERE FOR EACH ADDITIONAL HEADER-->*/
    ""
    + "~"").

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port unformatted inpfile-info skip.
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
        if ActivityLogID = 0 and bufActivityLog.Detail2 = "Program in Progress" then 
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
    define variable absValue     as decimal   no-undo. // ABSOLUTE VALUE
    define variable iValue       as integer   no-undo. // INTEGER VALUE
    define variable cValue       as character no-undo. // CHARACTER VALUE
    define variable ix           as integer   no-undo. 
    define variable decimalValue as character no-undo. // DECIMAL VALUE
    define variable decLoc       as integer   no-undo. // DECIMAL LOCATION
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