/* Adds a specific missing ID for when you know what the ID of the record was, but it was accidentally deleted */

define variable numRecords as integer.
numRecords = 0.

for first Member exclusive-lock where Member.ID = 0:
    assign 
        numRecords = numRecords + 1.
    delete Member.
end. /* END HOUSEHOLD LOOP */
    
run ActivityLog.
    
procedure ActivityLog:
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "deleteBadRecord.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Fixed missing ID for TransactionDetail record ID 383669374"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end. /* DO FOR */
end procedure.