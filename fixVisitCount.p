/*------------------------------------------------------------------------
    File        : fixVisitCount.p
    Purpose     : 

    Syntax      : 

    Description : Fix Visit Counts

    Author(s)   : michaelzrork
    Created     : 
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

for each TransactionDetail no-lock where TransactionDetail.VisitCount ge 1000 and module = "PMV":
    run fixVisitCount(TransactionDetail.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure fixVisitCount:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then 
            assign 
                numRecs                = numRecs + 1
                bufTransactionDetail.VisitCount = 1.
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "fixVisitCount.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Fix Visit Counts"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.