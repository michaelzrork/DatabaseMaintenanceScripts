/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "clearSASearchIndexTable" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Clear all Facility records from the SearchCache table"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
 /*----------------------------------------------------------------------
    Author(s)   : michaelzr
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/
{Includes/Framework.i}
{Includes/BusinessLogic.i}

function ParseList character (inputValue as char) forward.
function RoundUp returns decimal(dValue as decimal,precision as integer) forward.
function AddCommas returns character (dValue as decimal) forward.

define variable ActivityLogID as int64   no-undo.
define variable numRecs    as integer no-undo.

assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/
/* CREATE INITIAL AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Program is in Progress","Number of Records Found So Far: " + addCommas(numRecs),"","","").

for each SearchCache no-lock where SearchCache.ParentTable = "FRFacility":
    run deleteSASearchIndex(SearchCache.ID).
    run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + "SearchCache: " + string(SearchCache.ID),"Number of Records Found So Far: " + addCommas(numRecs),"","","").
end.

/* UPDATE AUDIT LOG ENTRY WITH FINAL COUNTS */
run UpdateActivityLog({&ProgramDescription},"Program is Complete","Number of Records Deleted: " + addCommas(numRecs),"","").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE RAW3AC RECORD
procedure deleteSASearchIndex:
    define input parameter inpID as int64 no-undo.
    define buffer bufSearchCache for SearchCache.
    do for bufSearchCache transaction:
        find first bufSearchCache exclusive-lock where bufSearchCache.id = inpID no-error no-wait.
        if available bufSearchCache then 
        do:
            numRecs = numRecs + 1.
            delete bufSearchCache.
        end.
    end.
end.

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