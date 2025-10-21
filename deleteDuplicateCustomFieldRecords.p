/*------------------------------------------------------------------------
    File        : deleteDuplicateSAProfileFieldRecords.p
    Purpose     : 

    Syntax      : 

    Description : Delete Duplicate CustomField Records

    Author(s)   : michaelzr
    Created     : 11/5/24
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
define variable numRecs           as integer no-undo.
define variable numDeletedDetails as integer no-undo.
assign
    numRecs           = 0
    numDeletedDetails = 0.
    
define temp-table ttProfileField no-undo
    field profileFieldID as int64
    index profileFieldID profileFieldID.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Retained ID,Deleted ID,ProfileID,FieldName,FieldValue").

profile-loop:
for each CustomField no-lock by CustomField.ID descending:
    find first ttProfileField no-lock where ttProfileField.profileFieldID = CustomField.ID no-error no-wait.
    if available ttProfileField then next profile-loop.
    run findDuplicateProfileField(CustomField.ID,CustomField.ProfileID,CustomField.FieldName).
end.

for each EntityProfile no-lock:
    find first CustomField no-lock where CustomField.ProfileID = EntityProfile.ID no-error no-wait.
    if available CustomField then run deleteProfileDetails(EntityProfile.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deleteDuplicateSAProfileFieldRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deleteDuplicateSAProfileFieldRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIND DUPLICATE PROFILE FIELD
procedure findDuplicateProfileField:
    define input parameter originalID as int64 no-undo.
    define input parameter xProfileID as int64 no-undo.
    define input parameter xFieldName as character no-undo.
    define buffer bufCustomField for CustomField.
    do for bufCustomField transaction:
        for each bufCustomField no-lock where bufCustomField.ProfileID = xProfileID and bufCustomField.FieldName = xFieldName and bufCustomField.ID <> originalID:
            find first ttProfileField no-lock where ttProfileField.profileFieldID = bufCustomField.ID no-error no-wait.
            if not available ttProfileField then create ttProfileField.
            assign 
                ttProfileField.profileFieldID = bufCustomField.ID.
            run deleteSAProfileField(bufCustomField.ID,originalID).
        end.
    end.
end procedure.

// DELETE SAPROFILEFIELD
procedure deleteCustomField:
    define input parameter inpID as int64 no-undo.
    define input parameter originalID as int64 no-undo.
    define buffer bufCustomField for CustomField.
    do for bufCustomField transaction:
        find first bufCustomField exclusive-lock where bufCustomField.ID = inpID no-error no-wait.
        if available bufCustomField then 
        do:
            run put-stream("~"" + string(originalID) + "~",~"" + string(bufCustomField.ID) + "~",~"" + getString(string(bufCustomField.ProfileID)) + "~",~"" + getString(bufCustomField.FieldName) + "~",~"" + getString(bufCustomField.FieldValue) + "~",").
            numRecs = numRecs + 1.
            delete bufCustomField.
        end.
    end.
end procedure.

// DELETE PROFILE DETAILS VALUE
procedure deleteProfileDetails:
    define input parameter inpID as int64 no-undo.
    define buffer bufEntityProfile for EntityProfile.
    do for bufEntityProfile transaction:
        find first bufEntityProfile exclusive-lock where bufEntityProfile.ID = inpID no-error no-wait.
        if available bufEntityProfile then 
            assign
                numDeletedDetails           = numDeletedDetails + 1
                bufEntityProfile.ProfileDetails = "".
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deleteDuplicateSAProfileFieldRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "deleteDuplicateSAProfileFieldRecords.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Delete Duplicate CustomField Records"
            BufActivityLog.Detail2       = "Check Document Center for deleteDuplicateSAProfileFieldRecordsLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Duplicate ProfileField records deleted: " + string(numRecs)
            bufActivityLog.Detail4       = "Number of ProfileDetails deleted: " + string(numDeletedDetails).
    end.
end procedure.