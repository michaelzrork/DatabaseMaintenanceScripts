/*------------------------------------------------------------------------
    File        : updateFullyPaid.p
    Purpose     : 

    Syntax      : 

    Description : Update FullyPaid value from False to True

    Author(s)   : michaelzrork
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recNum as integer no-undo.
define variable hhNum  as integer no-undo.

assign
    hhNum  = 10834
    recNum = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each TransactionDetail no-lock where TransactionDetail.EntityNumber = hhNum and TransactionDetail.FullyPaid = false:
    run updateFullyPaid(TransactionDetail.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure updateFullyPaid:
    define buffer bufTransactionDetail for TransactionDetail.
    define input parameter inpID as int64 no-undo.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then assign
                recNum                = recNum + 1
                bufTransactionDetail.FullyPaid = true.
    end.
end procedure.
        

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "updateFullyPaid.p"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Update FullyPaid value from False to True"
            bufActivityLog.Detail2       = "Number of TransactionDetail Records Adjusted for Household " + string(hhNum) + ": " + string(recNum).
    end.
end procedure.