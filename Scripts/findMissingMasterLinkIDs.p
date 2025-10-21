/*------------------------------------------------------------------------
    File        : findMissingMasterLinkIDs.p
    Purpose     : 

    Syntax      : 

    Description : Find any MasterLinkIDs that did not get updated in TransactionDetail

    Author(s)   : michaelzrork
    Created     : 11/18/2024
    Notes       : Confirming all MasterLinkIDs point to an available GRTeeTime
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs     as integer   no-undo.
define variable teeTimeList as character no-undo.

assign
    numRecs     = 0
    teeTimeList = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each TransactionDetail no-lock where TransactionDetail.Module = "GR" and TransactionDetail.MasterLinkID <> 0:
    find first GRTeeTime no-lock where GRTeeTime.ID = TransactionDetail.MasterLinkID no-error no-wait.
    if not available GRTeeTime and lookup(string(TransactionDetail.MasterLinkID),teeTimeList) = 0 then assign
            numRecs     = numRecs + 1
            teeTimeList = teeTimeList + (if teeTimeList = "" then "" else ",") + string(TransactionDetail.MasterLinkID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "findMissingMasterLinkIDs.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Find any MasterLinkIDs that did not get updated in TransactionDetail"
            bufActivityLog.Detail2       = "Number of Records Found: " + string(numRecs)
            bufActivityLog.Detail3       = "MasterLinkIDs with missing GRTeeTime record: " + teeTimeList.
    end.
end procedure.