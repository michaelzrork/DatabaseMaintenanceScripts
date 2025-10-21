/*------------------------------------------------------------------------
    File        : setCustomHHUpdateScreensToTaxable.p
    Purpose     : 

    Syntax      : 

    Description : Sets all custom Household Update screens to Taxable

    Author(s)   : michaelzr
    Created     : 11/06/2024
    Notes       : The code to add the toggle for the taxable on the custom screens did not work properly. 
                  The new records in FieldConfig were added, but didn't work. There's something else happening somewhere that I haven't figured out yet.
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
define variable numRecs       as integer no-undo.
define variable numHHupdated  as integer no-undo.
define variable xCreationDate as date    no-undo.
define variable numNewRecs    as integer no-undo.
assign
    numRecs       = 0
    numHHupdated  = 0
    xCreationDate = 11/06/2024
    numNewRecs    = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// FIND ALL CUSTOM HOUSEHOLD UPDATE SCREEN DESIGN FIELDS WITH A VALUE OF NO
for each FormDefinition no-lock where FormDefinition.ScreenName = "SAHouseholdUpdate" and FormDefinition.FieldName = "SAHousehold_Taxable":
    for first FieldConfig no-lock where FieldConfig.ParentRecord = FormDefinition.ID and FieldConfig.FieldName = "SAHousehold_Taxable" and FieldConfig.ParamName = "FieldValue":
        if FieldConfig.ParamValue = "No" then run updateTaxable(FieldConfig.ID).
    end.
    if not available FieldConfig then run createTaxable(FormDefinition.ID).
end.

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ID,HouseholdNumber,HouseholdName,CreationDate,Taxable,").

for each Account no-lock where Account.CreationDate ge xCreationDate and Account.Taxable = false:
    run updateHouseholdTaxable(Account.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "setCustomHHUpdateScreensToTaxableLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "setCustomHHUpdateScreensToTaxableLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// UPDATE CUSTOM SCREEN TAXABLE TOGGLE TO YES
procedure updateTaxable:
    define input parameter inpID as int64 no-undo.
    define buffer bufFieldConfig for FieldConfig.
    do for bufFieldConfig transaction:
        find first bufFieldConfig exclusive-lock where bufFieldConfig.ID = inpID no-error no-wait.
        if available bufFieldConfig then assign
                bufFieldConfig.ParamValue = "Yes"
                numRecs                    = numRecs + 1.
    end.
end procedure.

// CREATE SAFIELDPARAM RECORDS FOR SAHOUSEHOLD_TAXABLE FIELDVALUE
procedure createTaxable:
    define input parameter xParentID as int64 no-undo.
    define buffer bufFieldConfig for FieldConfig.
    do for bufFieldConfig transaction:
        create bufFieldConfig.
        assign
            bufFieldConfig.FieldName  = "SAHousehold_Taxable"
            bufFieldConfig.ParamName  = "FieldValue"
            bufFieldConfig.ParamValue = "Yes"
            bufFieldConfig.Interface  = "RecTrac"
            bufFieldConfig.RecordType = "Custom"
            bufFieldConfig.ParentRecord   = xParentID
            bufFieldConfig.Version    = "3.1.05.00"
            numNewRecs                 = numNewRecs + 1.
        create bufFieldConfig.
        assign
            bufFieldConfig.FieldName  = "SAHousehold_Taxable"
            bufFieldConfig.ParamName  = "FilterValue"
            bufFieldConfig.ParamValue = "No"
            bufFieldConfig.Interface  = "RecTrac"
            bufFieldConfig.RecordType = "Custom"
            bufFieldConfig.ParentRecord   = xParentID
            bufFieldConfig.Version    = "3.1.05.00".
    end.
end procedure.

// UPDATE HOUSEHOLDS CREATED SINCE .35 UPDATE
procedure updateHouseholdTaxable:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction: 
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            assign 
                bufAccount.Taxable = true
                numHHupdated           = numHHupdated + 1.
            run put-stream ("~"" + string(bufAccount.ID) + "~",~"" + string(bufAccount.EntityNumber) + "~",~"" + trim(getString(bufAccount.FirstName) + (if getString(bufSAhousehold.FirstName) = "" then "" else " ") + getString(bufAccount.LastName)) + "~",~"" + getString(string(bufAccount.CreationDate)) + "~",~"" + (if bufAccount.Taxable = true then "Yes" else "No") + "~",").
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "setCustomHHUpdateScreensToTaxableLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "setCustomHHUpdateScreensToTaxable.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sets all custom Household Update screens to Taxable"
            BufActivityLog.Detail2       = "Check Document Center for setCustomHHUpdateScreensToTaxableLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Custom Screen Designs Updated: " + string(numNewRecs + numRecs)
            bufActivityLog.Detail4       = "Number of Household created after " + string(xCreationDate) + " set to Taxable: " + string(numHHupdated).
    end.
end procedure.