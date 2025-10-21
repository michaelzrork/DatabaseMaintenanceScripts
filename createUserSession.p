/*------------------------------------------------------------------------
    File        : createSASessionInfoRecord.p
    Purpose     : 

    Syntax      : 

    Description : Create missing UserSession record

    Author(s)   : michaelzrork
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable recNum         as integer   no-undo.
define variable missingSession as character no-undo.

assign
    // ACTUAL SESSION
    missingSession = "6d940ab766f104cdfce752872cadfa65a889c7921f5eb423fdfbd70d3ac05cfe7245aaf42e19a5f50bac6ae08687d898248f6d4b461e43a3a29dc4b50b3c672c"
    recNum         = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

find first UserSession no-lock where UserSession.SessionID = missingSession no-error no-wait.
if not available UserSession then run createSession.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure createSession:
    define variable xDate as date no-undo.
    define variable xTime as int  no-undo.
    define buffer bufUserSession for UserSession.
    assign 
        xDate = today
        xTime = time.
    do for bufUserSession transaction:
        create bufUserSession.
        assign
            bufUserSession.UserName = "VSHEE"
            bufUserSession.WorkStationName = "PR-5035"
            bufUserSession.SessionID = missingSession
            bufUserSession.InterfaceType = "RecPortal"
            bufUserSession.InterfaceParameter = "RecTrac_1"
            bufUserSession.LoginDate = xDate
            bufUserSession.LoginTime = xTime
            bufUserSession.LogoutDate = ?
            bufUserSession.LogoutTime = 0
            bufUserSession.LastActiveDate = xDate
            bufUserSession.LastActiveTime = xTime
            bufUserSession.ServerLoginDate = xDate
            bufUserSession.ServerLoginTime = xTime
            bufUserSession.ServerLogoutDate = ?
            bufUserSession.ServerLogoutTime = 0
            bufUserSession.ServerLastActiveDate = xDate
            bufUserSession.ServerLastActiveTime = xTime
            bufUserSession.ID = 88942887.
    end.
end.


// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "createSASessionInfoRecord.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Create missing UserSession record"
            bufActivityLog.Detail2       = "Number of Records Created: " + string(recNum).
    end.
end procedure.