/*------------------------------------------------------------------------
    File        : fixGolfStatus.p
    Purpose     : 

    Syntax      : 

    Description : Fix stuck tee time pattern reservations

    Author(s)   : michaelzrork
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recNum as integer no-undo.

assign
    recNum = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each TransactionDetail no-lock where module = "GR" and (cartstatus = "New" or recordstatus = "New"):
    run fixStatus(TransactionDetail.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIX TRANSACTIONDETAIL STATUS
procedure fixStatus:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpid no-wait no-error.
        if available bufTransactionDetail then assign
                recNum                   = recNum + 1
                bufTransactionDetail.RecordStatus = "Cancelled"
                bufTransactionDetail.CartStatus   = "Complete".
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "fixGolfStatus.p"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Fix stuck tee time pattern reservations"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(recNum).
    end.
end procedure.