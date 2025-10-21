/*------------------------------------------------------------------------
    File        : fixHouseholdPhoneNumber.p
    Purpose     : 

    Syntax      : 

    Description : Fix which phone number is linked to the Household based on primary guardian phone number

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
define variable numRecs             as integer   no-undo.
define variable numPrimaryUntoggled as integer   no-undo.
define variable numDeletedPhone     as integer   no-undo.
define variable numUpdatedPhone     as integer   no-undo.
define variable personPhone         as character no-undo.
define variable personType          as character no-undo.
define variable personExt           as character no-undo.
define variable hhPhone             as character no-undo.
define variable hhType              as character no-undo.
define variable hhExt               as character no-undo.
assign
    numRecs             = 0
    numUpdatedPhone     = 0
    numPrimaryUntoggled = 0
    numDeletedPhone     = 0
    personPhone         = ""
    personType          = ""
    personExt           = ""
    hhPhone             = ""
    hhType              = ""
    hhExt               = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
// run put-stream ("Household Number,Household ID,Household Name,Household Phone Number,Person Phone Number,").

for each Relationship no-lock where Relationship.Primary = true and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
    find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
    if available Member then find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
    if available Account and Account.PrimaryPhoneNumber <> Member.PrimaryPhoneNumber then 
    do:
        assign 
            personPhone = if Member.PrimaryPhoneNumber = ? then "" else Member.PrimaryPhoneNumber
            personType  = if Member.PrimaryPhoneType = ? then "" else Member.PrimaryPhoneType
            personExt   = if Member.PrimaryPhoneExtension = ? then "" else Member.PrimaryPhoneExtension
            hhPhone     = if Account.PrimaryPhoneNumber = ? then "" else Account.PrimaryPhoneNumber
            hhType      = if Account.PrimaryPhoneType = ? then "" else Account.PrimaryPhoneType
            hhExt       = if Account.PrimaryPhoneExtension = ? then "" else Account.PrimaryPhoneExtension.
        run fixHHPhone(Account.ID).
    end.
end.

  
// CREATE LOG FILE
/*do ixLog = 1 to inpfile-num:                                                                                                                                                                                              */
/*    if search(sessiontemp() + "fixHouseholdPhoneNumberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then                                             */
/*        SaveFileToDocuments(sessiontemp() + "fixHouseholdPhoneNumberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").*/
/*end.                                                                                                                                                                                                                      */

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// Sync Member Phone to Account
procedure fixHHPhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    define buffer bufPhoneNumber     for PhoneNumber.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then 
        do:
            assign
                bufAccount.PrimaryPhoneNumber    = personPhone
                bufAccount.PrimaryPhoneType      = personType
                bufAccount.PrimaryPhoneExtension = personExt
                numRecs                              = numRecs + 1.
                
            for first PhoneNumber no-lock where PhoneNumber.ParentRecord = bufAccount.ID and PhoneNumber.ParentTable = "Account" and PhoneNumber.PrimaryPhoneNumber = true and PhoneNumber.PhoneNumber = personPhone:
                for each bufPhoneNumber no-lock where bufPhoneNumber.ParentRecord = bufAccount.ID and bufPhoneNumber.ParentTable = "Account" and bufPhoneNumber.PrimaryPhoneNumber = true and bufPhoneNumber.ID <> PhoneNumber.ID:
                    if bufPhoneNumber.PhoneNumber = personPhone then run deletePhone(bufPhoneNumber.ID).
                    else run clearPrimaryToggle(bufPhoneNumber.ID).
                end.
            end.
            
            if not available PhoneNumber then 
            do: 
                for first PhoneNumber exclusive-lock where PhoneNumber.ParentRecord = bufAccount.ID and PhoneNumber.ParentTable = "Account" and PhoneNumber.PrimaryPhoneNumber = true and PhoneNumber.PhoneNumber <> personPhone:
                    assign 
                        PhoneNumber.PhoneNumber = personPhone
                        PhoneNumber.PhoneType   = personType
                        PhoneNumber.Extension   = personExt
                        numUpdatedPhone     = numUpdatedPhone + 1.
                    for each bufPhoneNumber no-lock where bufPhoneNumber.ID <> PhoneNumber.ID and bufPhoneNumber.ParentRecord = bufAccount.ID and bufPhoneNumber.ParentTable = "Account" and bufPhoneNumber.PrimaryPhoneNumber = true:
                        if bufPhoneNumber.PhoneNumber = PhoneNumber.PhoneNumber then run deletePhone(bufPhoneNumber.ID).
                        else run clearPrimaryToggle(bufPhoneNumber.ID).
                    end. 
                end.
            end.
        end.
    end.
end.

// DELETE PHONE
procedure deletePhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:
        find first bufPhoneNumber exclusive-lock where bufPhoneNumber.ID = inpID no-error no-wait.
        if available bufPhoneNumber then 
        do:
            delete bufPhoneNumber.
            assign 
                numDeletedPhone = numDeletedPhone + 1.
        end.
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
            BufActivityLog.Detail1       = "Fix which phone number is linked to the Household based on primary guardian phone number"
            BufActivityLog.Detail2       = "Number of Account Records updated: " + string(numRecs)
            BufActivityLog.Detail3       = "Number of PhoneNumber Records deleted: " + string(numDeletedPhone)
            BufActivityLog.Detail4       = "Number of PhoneNumber records set to secondary: " + string(numPrimaryUntoggled)
            bufActivityLog.Detail5       = "Number of PhoneNumber records updated: " + string(numUpdatedPhone).
    end.
end procedure.