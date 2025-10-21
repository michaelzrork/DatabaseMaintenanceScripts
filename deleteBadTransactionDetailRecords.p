/*------------------------------------------------------------------------
    File        : deleteBadSADetailRecords.p
    Purpose     : 

    Syntax      : 

    Description : Delete Bad TransactionDetail Visit Records

    Author(s)   : michaelzrork
    Created     : 10/17/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs as integer no-undo.

assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each TransactionDetail no-lock where TransactionDetail.currentreceipt = 0 and TransactionDetail.module = "PMV" and TransactionDetail.username = "":
    run deleteRecord(TransactionDetail.ID). 
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteRecord:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-wait no-error.
        if available bufTransactionDetail then 
        do:
            assign 
                numRecs = numRecs + 1.
            delete bufTransactionDetail.
        end.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "deleteBadSADetailRecords.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Delete Bad TransactionDetail Visit Records"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.