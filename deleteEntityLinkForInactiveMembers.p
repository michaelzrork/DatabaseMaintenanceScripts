/*------------------------------------------------------------------------
    File        : deleteEntityLinkForInactiveMembers.p
    Purpose     : 

    Syntax      : 

    Description : Delete Xref for Inactive HHs and FMs

    Author(s)   : michaelzr
    Created     : 
    Notes       : This quick fix will loop through all EntityLink records and then check the linked member's Member and Account record status
                  If either the Account or the Person record is inactive, it deletes the EntityLink record
                  A log is created and found in Document Center of all Xref that are deleted.
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
define variable recCount     as integer   no-undo.
define variable memberName   as character no-undo.
define variable accountName       as character no-undo.
define variable accountStatus     as character no-undo.
define variable personStatus as character no-undo.
assign
    recCount     = 0
    memberName   = ""
    accountName       = ""
    accountStatus     = ""
    personStatus = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ID,XRef,Member ID,Account Num,Member Name,Member Record Status,Account Name,Account Record Status,").

xref-loop:
for each EntityLink no-lock:
    assign 
        memberName   = ""
        accountName       = ""
        personStatus = ""
        accountStatus     = "".
    find first Member no-lock where Member.ID = EntityLink.MemberLinkID no-error no-wait.
    if available Member then assign
            memberName   = getString(Member.FirstName) + " " + getString(Member.LastName)
            personStatus = Member.RecordStatus.
    for first Account no-lock where Account.EntityNumber = EntityLink.EntityNumber:
        assign 
            accountName   = getString(Account.FirstName) + " " + getString(Account.LastName)
            accountStatus = Account.RecordStatus.
        if accountName = "" and Account.OrganizationName <> "" then assign accountName = getString(Account.OrganizationName).
    end.
    if Member.RecordStatus = "Inactive" or Account.RecordStatus = "Inactive" then run deleteEntityLink(EntityLink.ID).
end.

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deleteEntityLinkForInactiveMembersLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deleteEntityLinkForInactiveMembersLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE CROSS REFERENCE
procedure deleteEntityLink:
    define input parameter inpid as int64.
    define buffer bufEntityLink for EntityLink.
    do for bufEntityLink transaction:
        find first bufEntityLink exclusive-lock where bufEntityLink.ID = inpid no-error no-wait.
        if available bufEntityLink then 
        do:
            recCount = recCount + 1.
            run put-stream (string(bufEntityLink.ID) + "," + string(bufEntityLink.ExternalID) + "," + string(bufEntityLink.MemberLinkID) + "," + string(bufEntityLink.EntityNumber) + ",~"" + memberName + "~"," + personStatus + ",~"" + accountName + "~"," + accountStatus + ",").
            delete bufEntityLink.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deleteEntityLinkForInactiveMembersLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "deleteEntityLinkForInactiveMembers.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Delete Xref for Inactive HHs and FMs"
            BufActivityLog.Detail2       = "Check Document Center for deleteEntityLinkForInactiveMembersLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(recCount).
    end.
end procedure.