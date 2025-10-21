/*------------------------------------------------------------------------
    File        : syncHHPhoneToPrimaryGuardian.p
    Purpose     : 

    Syntax      : 

    Description : Sync Household phone number to the Primary Guardian record

    Author(s)   : michaelzr
    Created     : 4/19/2024
    Notes       : RecTrac has never synced phone numbers, so this is not necessarily a bug. It is being looked into with PM-147506
          
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

// AUDIT LOG STUFF

define variable personPhoneRecs  as integer no-undo.
define variable phoneRecs        as integer no-undo.
define variable newPhoneRecs     as integer no-undo.
define variable deletedPhoneRecs as integer no-undo.
assign
    personPhoneRecs  = 0
    phoneRecs        = 0
    newPhoneRecs     = 0
    deletedPhoneRecs = 0.
    
// EVERYTHING ELSE

define variable hhID        as int64     no-undo.
define variable personID    as int64     no-undo.
define variable hhPhoneNum  as character no-undo.
define variable hhPhoneType as character no-undo.
define variable hhPhoneExt  as character no-undo.

assign 
    hhID        = 0
    personID    = 0
    hhPhoneNum  = ""
    hhPhoneType = ""
    hhPhoneExt  = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Record ID,Table,Member ID,First Name,Last Name,Original Phone Number,Original Phone Type,Original Phone Ext,New Phone Number,New Phone Type,New Phone Ext,").

// SYNC SAPERSON PHONE NUMBER WITH SAHOUSEHOLD IF OUT OF SYNC
for each Relationship no-lock where Relationship.ChildTable = "Member" and Relationship.ParentTable = "Account" and Relationship.Primary = true:
    assign 
        hhID        = 0
        personID    = 0
        hhPhoneNum  = ""
        hhPhoneType = ""
        hhPhoneExt  = "".
    find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
    if available Account then find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
    if available Member and (Member.PrimaryPhoneNumber <> Account.PrimaryPhoneNumber or (Member.PrimaryPhoneNumber = Account.PrimaryPhoneNumber and Account.PrimaryPhoneNumber <> "" and (Member.PrimaryPhoneType <> Account.PrimaryPhoneType or Member.PrimaryPhoneExtension <> Account.PrimaryPhoneExtension))) then 
    do:
        assign
            hhID        = Account.ID
            personID    = Member.ID
            hhPhoneNum  = getString(Account.PrimaryPhoneNumber)
            hhPhoneType = if hhPhoneNum = "" then "" else getString(Account.PrimaryPhoneType)
            hhPhoneExt  = if hhPhoneNum = "" then "" else getString(Account.PrimaryPhoneExtension).
        run syncPhoneNum(Member.ID).
    end. 
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "syncHHPhoneToPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "syncHHPhoneToPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SYNC SAHOUSEHOLD PHONE TO SAPERSON PHONE
procedure syncPhoneNum:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    define buffer bufPhoneNumber  for PhoneNumber.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then 
        do:
            run put-stream (string(bufMember.ID) + "," + "Member" + "," + string(inpID) + ",~"" + getString(bufMember.FirstName) + "~",~"" + getString(bufMember.LastName)
                + "~",~"" + (if getString(bufMember.PrimaryPhoneNumber) = "" then "No Phone Number" else getString(bufMember.PrimaryPhoneNumber))
                + "~",~"" + (if getString(bufMember.PrimaryPhoneType) = "" then "No Phone Type" else getString(bufMember.PrimaryPhoneType))
                + "~",~"" + (if getString(bufMember.PrimaryPhoneExtension) = "" then "No Phone Ext" else getString(bufMember.PrimaryPhoneExtension))
                + "~",~"" + (if bufMember.PrimaryPhoneNumber = hhPhoneNum then "No Change" else (if hhPhoneNum = "" then "Removed" else hhPhoneNum))
                + "~",~"" + (if bufMember.PrimaryPhoneType = hhPhoneType then "No Change" else (if hhPhoneType = "" then "Removed" else hhPhoneType))
                + "~",~"" + (if bufMember.PrimaryPhoneExtension = hhPhoneExt then "No Change" else (if hhPhoneExt = "" then "Removed" else hhPhoneExt))
                + "~",").
            assign 
                personPhoneRecs                   = personPhoneRecs + 1
                bufMember.PrimaryPhoneNumber    = hhPhoneNum
                bufMember.PrimaryPhoneType      = hhPhoneType
                bufMember.PrimaryPhoneExtension = hhPhoneExt.
        
            // UPDATE SAPHONE RECORD
            for first bufPhoneNumber exclusive-lock where bufPhoneNumber.ParentTable = "Member" and bufPhoneNumber.PrimaryPhoneNumber = true and bufPhoneNumber.ParentRecord = inpID:
                if hhPhoneNum = "" then 
                do:
                    run put-stream (string(bufPhoneNumber.ID) + "," + "PhoneNumber" + "," + string(inpID) + ",~"" + getString(bufMember.FirstName) + "~",~"" + getString(bufMember.LastName)
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneNumber) = "" then "No Phone Number" else getString(bufPhoneNumber.PhoneNumber))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneType) = "" then "No Phone Type" else getString(bufPhoneNumber.PhoneType))
                        + "~",~"" + (if getString(bufPhoneNumber.Extension) = "" then "No Phone Ext" else getString(bufPhoneNumber.Extension))
                        + "~",~"" + "PhoneNumber Record Deleted"
                        + "~",~"" + ""
                        + "~",~"" + ""
                        + "~",").
                    assign
                        deletedPhoneRecs = deletedPhoneRecs + 1.
                    delete bufPhoneNumber.
                end.
                else 
                do:
                    run put-stream (string(bufPhoneNumber.ID) + "," + "PhoneNumber" + "," + string(inpID) + ",~"" + getString(bufMember.FirstName) + "~",~"" + getString(bufMember.LastName)
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneNumber) = "" then "No Phone Number" else getString(bufPhoneNumber.PhoneNumber))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneType) = "" then "No Phone Type" else getString(bufPhoneNumber.PhoneType))
                        + "~",~"" + (if getString(bufPhoneNumber.Extension) = "" then "No Phone Ext" else getString(bufPhoneNumber.Extension))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneNumber) = hhPhoneNum then "No Change" else (if hhPhoneNum = "" then "Removed" else hhPhoneNum))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneType) = hhPhoneType then "No Change" else (if hhPhoneType = "" then "Removed" else hhPhoneType))
                        + "~",~"" + (if getString(bufPhoneNumber.Extension) = hhPhoneExt then "No Change" else (if hhPhoneExt = "" then "Removed" else hhPhoneExt))
                        + "~",").
                    assign
                        phoneRecs              = phoneRecs + 1
                        bufPhoneNumber.PhoneNumber = hhPhoneNum
                        bufPhoneNumber.PhoneType   = hhPhoneType
                        bufPhoneNumber.Extension   = hhPhoneExt.
                end.
            end.
            if not available bufPhoneNumber and hhPhoneNum <> "" then run createSAPhone(bufMember.ID,"Member",getString(bufMember.FirstName),getString(bufMember.LastName)).
        end.
    end.
end.

// CREATE MISSING SAPHONE RECORDS
procedure createSAPhone:
    define input parameter i64ParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.
    define input parameter cFirstName as character no-undo.
    define input parameter cLastName as character no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:  
        create bufPhoneNumber.
        assign
            newPhoneRecs                  = newPhoneRecs + 1
            bufPhoneNumber.ID                 = next-value(UniqueNumber)
            bufPhoneNumber.ParentRecord           = i64ParentID
            bufPhoneNumber.ParentTable        = cParentTable
            bufPhoneNumber.PrimaryPhoneNumber = true
            bufPhoneNumber.MemberLinkID     = personID
            bufPhoneNumber.PhoneNumber        = hhPhoneNum
            bufPhoneNumber.PhoneType          = hhPhoneType
            bufPhoneNumber.Extension          = hhPhoneExt.
        // CREATE LOG ENTRY
        run put-stream (string(bufPhoneNumber.ID) + "," + "PhoneNumber" + "," + string(bufPhoneNumber.MemberLinkID) + ",~"" + cFirstName + "~",~"" + cLastName
            + "~",~"" + "New PhoneNumber Record Created"
            + "~",~"" + ""
            + "~",~"" + ""
            + "~",~"" + (if hhPhoneNum = "" then "No Phone Number" else hhPhoneNum)
            + "~",~"" + (if hhPhoneType = "" then "No Phone Type" else hhPhoneType)
            + "~",~"" + (if hhPhoneExt = "" then "No Phone Ext" else hhPhoneExt)
            + "~",").
    end.
end procedure.
              
// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "syncHHPhoneToPrimaryGuardianLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "syncHHPhoneToPrimaryGuardian.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sync Household Phone Number to the Primary Guardian record"
            BufActivityLog.Detail2       = "Check Document Center for syncHHPhoneToPrimaryGuardianLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Member Records Adjusted: " + string(personPhoneRecs)
            BufActivityLog.Detail4       = "Number of PhoneNumber Records Adjusted: " + string(phoneRecs) 
            BufActivityLog.Detail5       = "Number of PhoneNumber Records Created: " + string(newPhoneRecs)
            BufActivityLog.Detail6       = "Number of PhoneNumber Records Deleted: " + string(deletedPhoneRecs).
    end.
end procedure.