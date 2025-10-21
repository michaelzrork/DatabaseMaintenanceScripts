{Includes/Framework.i}
{Includes/BusinessLogic.i}

define variable newLastActiveDate     as date      no-undo.
define variable numRecs               as integer   no-undo.
define variable skipHouseholds        as character no-undo.
define variable ix                    as integer   no-undo.
define variable defaultLastActiveDate as date      no-undo.

assign 
    numRecs               = 0
    skipHouseholds        = "999999999"
    defaultLastActiveDate = 02/01/2021.
    
/* FIND ALL INTERNAL AND MODEL HOUSEHOLDS */
profilefield-loop:
for each CustomField no-lock where CustomField.FieldName = "InternalHousehold" or CustomField.FieldName begins "ModelHousehold":
    if getString(CustomField.FieldValue) = "" then next profilefield-loop.
    do ix = 1 to num-entries(getString(CustomField.FieldValue)):
        skipHouseholds = uniquelist(entry(ix,getString(CustomField.FieldValue)),skipHouseholds,",").
    end. 
end.

/* MAIN HOUSEHOLD LOOP */
household-loop:
for each Account no-lock 
    where Account.LastActiveDate = ?:
        
    /* IF THE HOUSEHOLD IS THE GUEST HOUSEHOLD OR AN INTERNAL OR MODEL HOUSEHOLD, SKIP */
    if lookup(string(Account.EntityNumber),skipHouseholds) > 0 then next household-loop.

    /* RESET NEW LAST ACTIVE DATE VARIABLE BETWEEN HOUSEHOLDS */
    assign 
        newLastActiveDate = ?.
        
    /* INITIALIZE LAST ACTIVE DATE AS HOUSEHOLD CREATION DATE */
    if Account.CreationDate <> ? then
        assign 
            newLastActiveDate = Account.CreationDate.

    /* FIND LATEST TRANSACTION DATE AND SET LAST ACTIVE DATE TO THAT */
    for each TransactionDetail no-lock 
        where TransactionDetail.EntityNumber = Account.EntityNumber 
        and TransactionDetail.CartStatus = "Complete":
        
        if TransactionDetail.TransactionDate <> ? 
            and (newLastActiveDate = ? or TransactionDetail.TransactionDate > newLastActiveDate) then 
            assign newLastActiveDate = TransactionDetail.TransactionDate.
    end.
    
    /* CHECK HOUSEHOLD UPDATES FOR A MORE RECENT DATE */
    for each ActivityLog no-lock where (ActivityLog.Detail1 = "Account Update" or ActivityLog.Detail1 = "Account Add") and ActivityLog.Detail2 = string(Account.ID):
        if newLastActiveDate = ? or ActivityLog.LogDate > newLastActiveDate then assign newLastActiveDate = ActivityLog.LogDate.
    end.
    
    if newLastActiveDate = ? then assign newLastActiveDate = defaultLastActiveDate.

    if newLastActiveDate <> ? then run updateLastActiveDate(Account.ID). 
        
end.

run ActivityLog.

/* UPDATE LAST ACTIVE DATE */
procedure updateLastActiveDate:
    define input parameter inpID as int64 no-undo.
    define buffer bufSAhousehold for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error no-wait.
        if available bufAccount then assign
                bufAccount.LastActiveDate = newLastActiveDate
                numRecs                       = numRecs + 1.
    end.
end procedure.
    
/* CREATE AUDIT LOG ENTRY */
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "UpdateLastActiveDate.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Last Active Dates Added"
            BufActivityLog.Detail2       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.