/*------------------------------------------------------------------------
    File        : copyUserEmailToXref.p
    Purpose     : Copy staff emails to Xref

    Syntax      : 

    Description : Copies the staff emails in User Management to the Xref field in SSO settings.

    Author(s)   : michaelzr
    Created     : 01/26/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs as integer no-undo.
numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each Permission no-lock where Permission.EmailAddress <> "" and Permission.XRefValue = "":
    run copyEmailtoXref(Permission.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure copyEmailtoXref:
    define input parameter inpID as int64 no-undo.
    define buffer bufPermission for Permission.
    do for bufPermission transaction:
        find first bufPermission exclusive-lock where bufPermission.ID = inpID no-wait no-error.
        if available bufPermission then 
            assign
                numRecs                     = numRecs + 1
                bufPermission.XRefValue = bufPermission.EmailAddress.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "copyUserEmailToXref.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Copy Staff Emails to Xref"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.