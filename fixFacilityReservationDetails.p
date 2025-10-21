/*------------------------------------------------------------------------
    File        : fixFacilityReservationDetails.p
    Purpose     : 

    Syntax      : 

    Description : Fix incorrect FileLinkCode6 and Description values for Facility reservations

    Author(s)   : michaelzr
    Created     : 11/18/2024
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
define variable numRecs              as integer   no-undo.
define variable currentFileLinkCode6 as character no-undo.
define variable correctFileLinkCode6 as character no-undo.
define variable fixedDescription     as character no-undo.
define variable badDescription       as character no-undo.
define variable numDescriptions      as integer   no-undo.

assign
    numRecs              = 0
    numDescriptions      = 0
    currentFileLinkCode6 = ""
    correctFileLinkCode6 = ""
    badDescription       = ""
    fixedDescription     = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ID,FileLinkCode1,FileLinkCode2,FileLinkCode3,Updated Value,Original Value,New Value,").

// LOOP THROUGH ALL FACILITY RESERVATIONS
for each TransactionDetail no-lock where TransactionDetail.Module = "FR":
    // FIND THE FACILITY BASED ON THE FILELINKID
    find first FRFacility no-lock where FRFacility.ID = TransactionDetail.FileLinkID no-error no-wait.
    if available FRFacility then 
    do:
        // FIND THE FACILITY LOCATION FROM THE FACILITY 
        find first FRLocation no-lock where FRLocation.FacilityLocation = FRFacility.FacilityLocation no-error no-wait.
        
        // SET THE VALUES
        assign
            currentFileLinkCode6 = TransactionDetail.FileLinkCode6
            correctFileLinkCode6 = FRFacility.ComboKey
            badDescription       = replace(correctFileLinkCode6,"_",":") + ";" // THIS SETS THE COMBOKEY TO HOW IT IS INCORRECTLY SET IN THE TRANSACTIONDETAIL_DESCRIPTION 
            fixedDescription     = "".
    
        // IF THE CURRENT COMBOKEY IS DIFFERENT FROM THE FACILITY COMBO KEY, FIX IT
        if currentFileLinkCode6 <> correctFileLinkCode6 then run fixCode6(TransactionDetail.ID).
    
        // IF THE TRANSACTIONDETAIL DESCRIPTION HAS THE BAD COMBOKEY VALUE, LET'S UPDATE IT
        if index(TransactionDetail.Description,badDescription) > 0 then 
        do:
            assign 
                // REPLACES THE BAD COMBOKEY WITH THE PROPER SHORT DESCRIPTION
                fixedDescription = replace(TransactionDetail.Description,badDescription,FRFacility.ShortDescription + " on").
            if available FRLocation then 
            do:
                // IF THE DESCRIPTIONS ARE ALSO MISSING THE "AT LOCATION", WE NEED TO ADD THAT AS WELL
                if index(fixedDescription," at " + FRLocation.ShortDescription) = 0 then assign
                        fixedDescription = fixedDescription + " at " + FRLocation.ShortDescription.
            end.
            run fixDescription(TransactionDetail.ID).
        end.
    end. 
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "fixFacilityReservationDetailsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "fixFacilityReservationDetailsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIX FILELINKCODE6
procedure fixCode6:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then 
        do:
            run put-stream ("~"" + string(bufTransactionDetail.ID) + "~",~"" + getString(bufTransactionDetail.FileLinkCode1) + "~",~"" + getString(bufTransactionDetail.FileLinkCode2) + "~",~"" + getString(bufTransactionDetail.FileLinkCode3) + "~",~"" + "FileLinkCode6" + "~",~"" + currentFileLinkCode6 + "~",~"" + correctFileLinkCode6 + "~",").
            assign 
                bufTransactionDetail.FileLinkCode6 = correctFileLinkCode6
                numRecs                   = numRecs + 1.
        end.
    end.
end procedure.

// FIX DESCRIPTION
procedure fixDescription:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then 
        do:
            run put-stream ("~"" + string(bufTransactionDetail.ID) + "~",~"" + getString(bufTransactionDetail.FileLinkCode1) + "~",~"" + getString(bufTransactionDetail.FileLinkCode2) + "~",~"" + getString(bufTransactionDetail.FileLinkCode3) + "~",~"" + "Description" + "~",~"" + bufTransactionDetail.Description + "~",~"" + fixedDescription + "~",").
            assign 
                bufTransactionDetail.Description = fixedDescription
                numDescriptions         = numDescriptions + 1.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "fixFacilityReservationDetailsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "fixFacilityReservationDetails.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Fix incorrect FileLinkCode6 and Description values for Facility reservations"
            BufActivityLog.Detail2       = "Check Document Center for fixFacilityReservationDetailsLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of FileLinkCode6 values updated: " + string(numRecs)
            bufActivityLog.Detail4       = "Number of Descriptions updated: " + string(numDescriptions).
    end.
end procedure.