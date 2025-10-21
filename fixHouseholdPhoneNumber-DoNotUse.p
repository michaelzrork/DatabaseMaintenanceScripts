/*------------------------------------------------------------------------
    File        : fixHouseholdPhoneNumber.p
    Purpose     : 

    Syntax      : 

    Description : Sync Account Phone Number from Primary Guardian Number

    Author(s)   : michaelzr
    Created     : 4/19/2024; modified from syncAccountPhoneToPrimaryGuardian.p on 10/30/2024
    Notes       : Syncing from Primary Guardian to Account due to an error in a account import
    
    THIS WORKED, TECHNICALLY, BUT DIDN'T DO WHAT I WANTED IT TO DO, SO I'M SCRAPPING IT AND STARTING OVER
          
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

define variable hhPhoneRecs      as integer no-undo.
define variable phoneRecs        as integer no-undo.
define variable newPhoneRecs     as integer no-undo.
define variable deletedPhoneRecs as integer no-undo.
assign
    hhPhoneRecs      = 0
    phoneRecs        = 0
    newPhoneRecs     = 0
    deletedPhoneRecs = 0.
    
// EVERYTHING ELSE

define variable accountID                  as int64     no-undo.
define variable personID              as int64     no-undo.
define variable fmPhoneNum            as character no-undo.
define variable fmPhoneType           as character no-undo.
define variable fmPhoneExt            as character no-undo.
define variable numUntoggledHHPrimary as integer   no-undo.

assign 
    accountID                  = 0
    personID              = 0
    fmPhoneNum            = ""
    fmPhoneType           = ""
    fmPhoneExt            = ""
    numUntoggledHHPrimary = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Record ID,Table,Member ID,First Name,Last Name,Original Phone Number,Original Phone Type,Original Phone Ext,New Phone Number,New Phone Type,New Phone Ext,").

// SYNC MEMBER EMAIL WITH ACCOUNT IF OUT OF SYNC
for each Relationship no-lock where Relationship.ChildTable = "Member" and Relationship.ParentTable = "Account" and Relationship.Primary = true:
    assign 
        accountID        = 0
        personID    = 0
        fmPhoneNum  = ""
        fmPhoneType = ""
        fmPhoneExt  = "".
    find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
    if available Account then find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
    if available Member and Member.PrimaryPhoneNumber <> "" and (Member.PrimaryPhoneNumber <> Account.PrimaryPhoneNumber or (Member.PrimaryPhoneNumber = Account.PrimaryPhoneNumber and (Member.PrimaryPhoneType <> Account.PrimaryPhoneType or Member.PrimaryPhoneExtension <> Account.PrimaryPhoneExtension))) then 
    do:
        assign
            accountID        = Account.ID
            personID    = Member.ID
            fmPhoneNum  = getString(Member.PrimaryPhoneNumber)
            fmPhoneType = if fmPhoneNum = "" then "" else getString(Member.PrimaryPhoneType)
            fmPhoneExt  = if fmPhoneNum = "" then "" else getString(Member.PrimaryPhoneExtension).
        run syncPhoneNum(Account.ID).
    end. 
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "fixHouseholdPhoneNumberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "fixHouseholdPhoneNumberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// SYNC ACCOUNT PHONE TO Account PHONE
procedure syncPhoneNum:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    define buffer bufPhoneNumber     for PhoneNumber.
    define buffer bufPhone2    for PhoneNumber.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            run put-stream ("~"" + 
                string(bufAccount.ID) + "~",~"" + 
                "Account" + "~",~"" + 
                string(personID) + "~",~"" + 
                getString(bufAccount.FirstName) + "~",~"" + 
                getString(bufAccount.LastName) + "~",~"" + 
                (if getString(bufAccount.PrimaryPhoneNumber) = "" then "No Phone Number" else getString(bufAccount.PrimaryPhoneNumber)) + "~",~"" + 
                (if getString(bufAccount.PrimaryPhoneType) = "" then "No Phone Type" else getString(bufAccount.PrimaryPhoneType)) + "~",~"" + 
                (if getString(bufAccount.PrimaryPhoneExtension) = "" then "No Phone Ext" else getString(bufAccount.PrimaryPhoneExtension)) + "~",~"" + 
                (if bufAccount.PrimaryPhoneNumber = fmPhoneNum then "No Change" else (if fmPhoneNum = "" then "Removed" else fmPhoneNum)) + "~",~"" + 
                (if bufAccount.PrimaryPhoneType = fmPhoneType then "No Change" else (if fmPhoneType = "" then "Removed" else fmPhoneType)) + "~",~"" + 
                (if bufAccount.PrimaryPhoneExtension = fmPhoneExt then "No Change" else (if fmPhoneExt = "" then "Removed" else fmPhoneExt)) + "~",").
            assign 
                hhPhoneRecs                          = hhPhoneRecs + 1
                bufAccount.PrimaryPhoneNumber    = fmPhoneNum
                bufAccount.PrimaryPhoneType      = fmPhoneType
                bufAccount.PrimaryPhoneExtension = fmPhoneExt.
        
            // UPDATE SAPHONE RECORD
            find first bufPhoneNumber no-lock where bufPhoneNumber.ParentTable = "Account" and bufPhoneNumber.PrimaryPhoneNumber = true and bufPhoneNumber.ParentRecord = inpID and bufPhoneNumber.PhoneNumber = fmPhoneNum no-error no-wait.
            if available bufPhoneNumber then 
            do:
                for each bufPhone2 exclusive-lock where bufPhoneNumber.ParentTable = "Account" and bufPhoneNumber.PrimaryPhoneNumber = true and bufPhoneNumber.ParentRecord = inpID and bufPhoneNumber.PhoneNumber <> fmPhoneNum:
                    assign 
                        bufPhone2.PrimaryPhoneNumber = false
                        numUntoggledHHPrimary          = numUntoggledHHPrimary + 1.
                    run put-stream (string(bufAccount.ID) + "," + "Account" + "," + string(inpID) + ",~"" + getString(bufAccount.FirstName) + "~",~"" + getString(bufAccount.LastName)
                        + "~",~"" + (if getString(bufAccount.PrimaryPhoneNumber) = "" then "No Phone Number" else getString(bufAccount.PrimaryPhoneNumber))
                        + "~",~"" + (if getString(bufAccount.PrimaryPhoneType) = "" then "No Phone Type" else getString(bufAccount.PrimaryPhoneType))
                        + "~",~"" + (if getString(bufAccount.PrimaryPhoneExtension) = "" then "No Phone Ext" else getString(bufAccount.PrimaryPhoneExtension))
                        + "~",~"" + (if bufAccount.PrimaryPhoneNumber = fmPhoneNum then "No Change" else (if fmPhoneNum = "" then "Removed" else fmPhoneNum))
                        + "~",~"" + (if bufAccount.PrimaryPhoneType = fmPhoneType then "No Change" else (if fmPhoneType = "" then "Removed" else fmPhoneType))
                        + "~",~"" + (if bufAccount.PrimaryPhoneExtension = fmPhoneExt then "No Change" else (if fmPhoneExt = "" then "Removed" else fmPhoneExt))
                        + "~",").
                end.
                return.
            end.
          
            for first bufPhoneNumber exclusive-lock where bufPhoneNumber.ParentTable = "Account" and bufPhoneNumber.PrimaryPhoneNumber = true and bufPhoneNumber.ParentRecord = inpID:
                if fmPhoneNum = "" then 
                do:
                    run put-stream (string(bufPhoneNumber.ID) + "," + "PhoneNumber" + "," + string(inpID) + ",~"" + getString(bufAccount.FirstName) + "~",~"" + getString(bufAccount.LastName)
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
                    run put-stream (string(bufPhoneNumber.ID) + "," + "PhoneNumber" + "," + string(inpID) + ",~"" + getString(bufAccount.FirstName) + "~",~"" + getString(bufAccount.LastName)
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneNumber) = "" then "No Phone Number" else getString(bufPhoneNumber.PhoneNumber))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneType) = "" then "No Phone Type" else getString(bufPhoneNumber.PhoneType))
                        + "~",~"" + (if getString(bufPhoneNumber.Extension) = "" then "No Phone Ext" else getString(bufPhoneNumber.Extension))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneNumber) = fmPhoneNum then "No Change" else (if fmPhoneNum = "" then "Removed" else fmPhoneNum))
                        + "~",~"" + (if getString(bufPhoneNumber.PhoneType) = fmPhoneType then "No Change" else (if fmPhoneType = "" then "Removed" else fmPhoneType))
                        + "~",~"" + (if getString(bufPhoneNumber.Extension) = fmPhoneExt then "No Change" else (if fmPhoneExt = "" then "Removed" else fmPhoneExt))
                        + "~",").
                    assign
                        phoneRecs              = phoneRecs + 1
                        bufPhoneNumber.PhoneNumber = fmPhoneNum
                        bufPhoneNumber.PhoneType   = fmPhoneType
                        bufPhoneNumber.Extension   = fmPhoneExt.
                end.
            end.
            if not available bufPhoneNumber and fmPhoneNum <> "" then run createSAPhone(bufAccount.ID,"Account",getString(bufAccount.FirstName),getString(bufAccount.LastName)).
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
            bufPhoneNumber.PhoneNumber        = fmPhoneNum
            bufPhoneNumber.PhoneType          = fmPhoneType
            bufPhoneNumber.Extension          = fmPhoneExt.
        // CREATE LOG ENTRY
        run put-stream (string(bufPhoneNumber.ID) + "," + "PhoneNumber" + "," + string(bufPhoneNumber.MemberLinkID) + ",~"" + cFirstName + "~",~"" + cLastName
            + "~",~"" + "New PhoneNumber Record Created"
            + "~",~"" + ""
            + "~",~"" + ""
            + "~",~"" + (if fmPhoneNum = "" then "No Phone Number" else fmPhoneNum)
            + "~",~"" + (if fmPhoneType = "" then "No Phone Type" else fmPhoneType)
            + "~",~"" + (if fmPhoneExt = "" then "No Phone Ext" else fmPhoneExt)
            + "~",").
    end.
end procedure.
              
// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "fixHouseholdPhoneNumberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "fixHouseholdPhoneNumber.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sync Account Phone Number from Primary Guardian Number"
            BufActivityLog.Detail2       = "Check Document Center for fixHouseholdPhoneNumberLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Account Records Adjusted: " + string(hhPhoneRecs)
            BufActivityLog.Detail4       = "Number of PhoneNumber Records Adjusted: " + string(phoneRecs) 
            BufActivityLog.Detail5       = "Number of PhoneNumber Records Created: " + string(newPhoneRecs)
            BufActivityLog.Detail6       = "Number of PhoneNumber Records Deleted: " + string(deletedPhoneRecs).
    end.
end procedure.