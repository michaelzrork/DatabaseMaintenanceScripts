/*------------------------------------------------------------------------
    File        : fixGolfCourseConversion.p
    Purpose     : 

    Syntax      : 

    Description : Fix the FileLinkCode4 on golf course TransactionDetail records

    Author(s)   : michaelzrork
    Created     : 11/18/2024
    Notes       : Ran the codeConvertGolfCourse quick fix and realized I had mistakenly not updated FileLinkCode4. This resolves that.
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

for each TransactionDetail no-lock where TransactionDetail.Module = "PSS" and TransactionDetail.FileLinkCode4 = "2":
    run fixRecord(TransactionDetail.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure fixRecord:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then assign
                bufTransactionDetail.FileLinkCode4 = "1"
                numRecs                   = numRecs + 1.
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "fixGolfCourseConversion.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Fix the FileLinkCode4 on golf course TransactionDetail records"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.