/*------------------------------------------------------------------------
    File        : purgeSAAddressRecordsWithNoHouseholdLink.p
    Purpose     : 

    Syntax      : 

    Description : Purge all MailingAddress Records without a Household Link

    Author(s)   : michaelzr
    Created     : 12/18/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recCount as integer no-undo.
recCount = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

address-loop:
for each MailingAddress no-lock:
    if can-find(first AccountAddress no-lock where AccountAddress.RecordCode = MailingAddress.RecordCode) then next address-loop.
    run purgeSAAddress(MailingAddress.ID).
end.
    
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure purgeMailingAddress:
    define input parameter inpid as int64.
    define buffer bufMailingAddress for MailingAddress.
    do for bufMailingAddress transaction:
        find first bufMailingAddress exclusive-lock where bufMailingAddress.ID = inpid no-error no-wait.
        if available bufMailingAddress then 
        do:
            recCount = recCount + 1.
            delete bufMailingAddress.
        end.
    end.
end procedure.

procedure purgeMailingAddress:
    define input parameter inpid as int64.
    define buffer bufAccountAddress for AccountAddress.
    do for bufAccountAddress transaction:
        find first bufAccountAddress exclusive-lock where bufAccountAddress.ID = inpid no-error no-wait.
        if available bufAccountAddress then 
        do:
            recCount = recCount + 1.
            delete bufAccountAddress.
        end.
    end.
end procedure.

procedure ActivityLog:
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "purgeSAAddressRecordsWithNoHouseholdLink.r"
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Purge all MailingAddress Records without a Household Link"
            bufActivityLog.Detail2       = "Number of records deleted: " + string(recCount).
    end.
end procedure.