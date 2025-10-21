/*------------------------------------------------------------------------
    File        : syncPhoneType.p
    Purpose     : 

    Syntax      : 

    Description : Sync Phone Type from Account and Member to PhoneNumber

    Author(s)   : michaelzr
    Created     : 10/29/2024
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
define variable numRecs             as integer no-undo.
define variable numHHPhoneTypeAdded as integer no-undo.
define variable numFMPhoneTypeAdded as integer no-undo.
define variable numPrimaryUntoggled as integer no-undo.
assign
    numRecs             = 0
    numHHPhoneTypeAdded = 0
    numFMPhoneTypeAdded = 0
    numPrimaryUntoggled = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("PhoneNumber.ID,Parent Table,Parent ID,MemberLinkID,Parent Table Phone Number,PhoneNumber PhoneNumber,Parent Table/New Phone Type,PhoneNumber/Original Phone Type,").

for each Account no-lock where Account.PrimaryPhoneNumber <> "":
    // SET A PHONE TYPE OF 'CELL' FOR ANY HOUSEHOLD PHONE NUMBER WITHOUT A TYPE
    if Account.PrimaryPhoneType = "" then run setHHPhoneType(Account.ID,"Cell").
    // FIND ALL PRIMARY PHONE RECORDS FOR THE HOUSEHOLD AND COMPARE THE PHONE TYPE
    for each PhoneNumber no-lock where PhoneNumber.ParentRecord = Account.ID and PhoneNumber.ParentTable = "Account" and PhoneNumber.PrimaryPhoneNumber = true and PhoneNumber.PhoneNumber = Account.PrimaryPhoneNumber and PhoneNumber.PhoneType <> Account.PrimaryPhoneType:
        run fixPhoneType(PhoneNumber.ID,Account.PrimaryPhoneType,Account.PrimaryPhoneNumber).
    end.
end.

for each Member no-lock where Member.PrimaryPhoneNumber <> "":
    // SET A PHONE TYPE OF 'CELL' FOR ANY PERSON PHONE NUMBER WITHOUT A TYPE
    if Member.PrimaryPhoneType = "" then run setFMPhoneType(Member.ID,"Cell").
    // FIND ALL PRIMARY PHONE RECORDS FOR THE PERSON AND COMPARE THE PHONE TYPE
    for each PhoneNumber no-lock where PhoneNumber.ParentRecord = Member.ID and PhoneNumber.ParentTable = "Member" and PhoneNumber.PrimaryPhoneNumber = true and PhoneNumber.PhoneNumber = Member.PrimaryPhoneNumber and PhoneNumber.PhoneType <> Member.PrimaryPhoneType:
        run fixPhoneType(PhoneNumber.ID,Member.PrimaryPhoneType,Member.PrimaryPhoneNumber).
    end.
end.

for each PhoneNumber no-lock where PhoneNumber.PrimaryPhoneNumber = false and PhoneNumber.PhoneType = "" and lookup(PhoneNumber.ParentTable,"Account,Member") > 0:
    run fixPhoneType(PhoneNumber.ID,"Cell","N/A").
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "syncPhoneTypeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "syncPhoneTypeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SET HH PHONE TYPE
procedure setHHPhoneType:
    define input parameter inpID as int64 no-undo.
    define input parameter newPhoneType as character no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then assign
                bufAccount.PrimaryPhoneType = newPhoneType
                numHHPhoneTypeAdded             = numHHPhoneTypeAdded + 1.
    end.
end.

// SET FM PHONE TYPE
procedure setFMPhoneType:
    define input parameter inpID as int64 no-undo.
    define input parameter newPhoneType as character no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then assign
                bufMember.PrimaryPhoneType = newPhoneType
                numFMPhoneTypeAdded          = numFMPhoneTypeAdded + 1.
    end.
end.

// CLEAR PRIMARY TOGGLE
procedure clearPrimaryToggle:
    define input parameter inpID as int64 no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:
        find first bufPhoneNumber exclusive-lock where bufPhoneNumber.ID = inpID no-error no-wait.
        if available bufPhoneNumber then assign 
                bufPhoneNumber.PrimaryPhoneNumber = false
                numPrimaryUntoggled           = numPrimaryUntoggled + 1.
    end.
end.
        

// FIX PHONE TYPE
procedure fixPhoneType:
    define input parameter inpID as int64 no-undo.
    define input parameter parentTablePhoneType as character no-undo.
    define input parameter parentTablePhoneNumber as character no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:
        find first bufPhoneNumber exclusive-lock where bufPhoneNumber.ID = inpid no-error no-wait.
        if available bufPhoneNumber then 
        do:
            run put-stream("~"" + 
                getString(string(bufPhoneNumber.ID)) + "~",~"" + 
                getString(bufPhoneNumber.ParentTable) + "~",~"" +
                getString(string(bufPhoneNumber.ParentRecord)) + "~",~"" +
                getString(string(bufPhoneNumber.MemberLinkID)) + "~",~"" + 
                getString(string(parentTablePhoneNumber)) + "~",~"" + 
                getString(string(bufPhoneNumber.PhoneNumber)) + "~",~"" +
                getString(parentTablePhoneType) + "~",~"" + 
                (if getString(bufPhoneNumber.PhoneType) = "" then "No Phone Type" else getString(bufPhoneNumber.PhoneType)) + "~",").
            assign
                bufPhoneNumber.PhoneType = parentTablePhoneType
                numRecs              = numRecs + 1.                
        end.
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "syncPhoneTypeLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "syncPhoneType.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sync Phone Type from Account and Member to PhoneNumber"
            BufActivityLog.Detail2       = "Check Document Center for syncPhoneTypeLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of PhoneNumber Records updated: " + string(numRecs)
            BufActivityLog.Detail4       = "Number of Account Records updated: " + string(numHHPhoneTypeAdded)
            BufActivityLog.Detail5       = "Number of Member Records updated: " + string(numFMPhoneTypeAdded)
            bufsaActivityLog.detail6       = "Number of PhoneNumber Primary records set to secondary: " + string(numPrimaryUntoggled).
    end.
end procedure.