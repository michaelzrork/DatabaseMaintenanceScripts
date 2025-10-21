{Includes/Framework.i}
{Includes/BusinessLogic.i}

define variable numRecords as integer.
define variable idList     as character.

assign
    numRecords = 0
    idList     = "".

for each Member exclusive-lock where Member.ID = 0:
    assign 
        numRecords  = numRecords + 1
        Member.ID = next-value(uniquenumber)
        idList      = list(string(Member.ID),idList).
end. /* END ACCOUNT LOOP */
    
run ActivityLog.
    
procedure ActivityLog:
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "fixRecordID.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Fixed missing ID for Record"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords)
            bufActivityLog.Detail3       = "IDs Added: " + idList.
    end. /* DO FOR */
end procedure.