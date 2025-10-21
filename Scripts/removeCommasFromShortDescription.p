/*------------------------------------------------------------------------
    File        : removeCommasFromShortDescription.p
    Purpose     : 

    Syntax      : 

    Description : Remove Commas from Facility Short Descriptions

    Author(s)   : michaelzr
    Created     : 7/15/2024
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
run put-stream ("ID,Original Facility Description,New Facility Description,").

for each FRFacility no-lock where index(FRFacility.ShortDescription,",") > 0:
    run removeComma(FRFacility.ID).
end.

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "removeCommasFromShortDescriptionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "removeCommasFromShortDescriptionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// REMOVE COMMA FROM SHORT DESCRIPTION
procedure removeComma:
    define input parameter inpID as int64 no-undo.
    define buffer bufFRFacility for FRFacility.
    do for bufFRFacility transaction:
        find first bufFRFacility exclusive-lock where bufFRFacility.ID = inpID no-error no-wait.
        if available bufFRFacility then 
        do:
            run put-stream ("~"" + string(bufFRFacility.ID) + "~",~"" + bufFRFacility.ShortDescription + "~",~"" + replace(bufFRFacility.ShortDescription,",","") + "~",").
            assign 
                numRecs                        = numRecs + 1
                bufFRFacility.ShortDescription = replace(bufFRFacility.ShortDescription,",","").
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "removeCommasFromShortDescriptionLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(600)" skip.
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
            BufActivityLog.SourceProgram = "removeCommasFromShortDescription.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Remove Commas from Facility Short Descriptions"
            BufActivityLog.Detail2       = "Check Document Center for removeCommasFromShortDescriptionLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.