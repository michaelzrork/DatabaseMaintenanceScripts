/*------------------------------------------------------------------------
    File        : endSessions.p
    Purpose     : 

    Syntax      : 

    Description : 

    Author(s)   : michaelzr
    Created     : 12/14/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

using Business.Library.Model.BO.WebInviteBO.WebInviteBO from propath.

{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i}
{Includes/TransactionDetailCartStatusList.i}
{Includes/InterfaceData.i}

define variable sessionList          as longchar  no-undo.
define variable ixLog                as integer   no-undo.
define variable numRecs              as integer   no-undo.
define variable numKiosk             as integer   no-undo.
define variable numAC                as integer   no-undo.
define variable numWebInvite         as integer   no-undo.
define variable numMissingServerDate as integer   no-undo.

define variable LogFile              as character no-undo.

define variable LastActiveDateTime   as datetime  no-undo.
define variable RecTracGuest         as integer   no-undo.
define variable MRecTracGuest        as integer   no-undo.
define variable WebTracGuest         as integer   no-undo.
define variable CurrentDateTime      as datetime  no-undo.
define variable dtUtcDate            as date      no-undo.
define variable iUtcTime             as integer   no-undo.
define variable MRecTracCart         as integer   no-undo.
define variable RecTracCart          as integer   no-undo.
define variable WebTracCart          as integer   no-undo.
define variable RecTracInactive      as integer   no-undo.
define variable MRecTracInactive     as integer   no-undo.
define variable WebTracInactive      as integer   no-undo.
define variable logfileDate          as date      no-undo.
define variable logfileTime          as integer   no-undo. 

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.

if findProfile("Static Parameters") = false then 
do:
    run ActivityLog("Program Aborted: There is no Static Parameters profile linked.","").
    return.
end.

assign
    numRecs              = 0
    numKiosk             = 0
    numAC                = 0
    numWebInvite         = 0
    numMissingServerDate = 0
    
    inpfile-num          = 1
    ixLog                = 0
    logfileDate          = today
    logfileTime          = time
    
    LogFile              = SessionTemp() + "SessionCleaner.txt"
    
    dtUtcDate            = date(datetime-tz( now, 0))
    iUtcTime             = truncate(mtime( datetime-tz( now, 0)) / 1000, 0)
    CurrentDateTime      = datetime(dtUtcDate, iUtcTime * 1000)
    
    RecTracGuest         = int(ProfileChar("Static Parameters", "RecTracGuest"))
    MRecTracGuest        = int(ProfileChar("Static Parameters", "MobileRecTracGuest"))
    WebTracGuest         = int(ProfileChar("Static Parameters", "WebTracGuest"))
    RecTracCart          = int(ProfileChar("Static Parameters", "RecTracCart"))
    MRecTracCart         = int(ProfileChar("Static Parameters", "MobileRecTracCart"))
    WebTracCart          = int(ProfileChar("Static Parameters", "WebTracCart"))
    RecTracInactive      = int(ProfileChar("Static Parameters", "RecTracInactive"))
    MRecTracInactive     = int(ProfileChar("Static Parameters", "MobileRecTracInactive"))
    WebTracInactive      = int(ProfileChar("Static Parameters", "WebTracInactive")).
    
define temp-table ttACSessions no-undo
    field ID          as int64
    field WorkStation as character
    field xRowid      as rowid
    index ID          ID
    index WorkStation WorkStation.
  
define temp-table ttKioskSessions no-undo
    field ID          as int64
    field WorkStation as character
    field UserName    as character
    field xRowid      as rowid
    index ID          ID
    index WorkStation WorkStation.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// LOG STATIC PARAMETERS FIELD VALUES
run ActivityLog ("Profile Field Values",
    "CurrentDateTime: " +
    string(CurrentDateTime) +
    ";RecTracGuest: " + 
    string(RecTracGuest) + 
    "; MRecTracGuest: " + 
    string(mRecTracGuest) + 
    "; WebTracGuest: " +
    string(WebTracGuest) +
    "; RecTracCart: " +
    string(RecTracCart) +
    "; MRecTracCart: " +
    string(MRecTracCart) +
    "; WebTracCart: " +
    string(WebTracCart) +
    "; RecTracInactive: " +
    string(RecTracInactive) +
    "; MRecTracInactive: " +
    string(MRecTracInactive) +
    "; WebTracInactive: " +
    string(WebTracInactive) +
    "; Logfile Location: " +
    logfile).

// CREATE LOG FILE FIELDS
run put-stream ("Note,UserSession.ID,UserSession.SessionID,UserSession.InterfaceType,UserSession.UserName,UserSession.EntityNumber,UserSession.ServerLoginDate,UserSession.ServerLoginTime,UserSession.ServerLastActiveDate,UserSession.ServerLastActiveTime,UserSession.LogoutDate,UserSession.LogoutTime,").

session-loop:  
for each UserSession no-lock where UserSession.LogoutDate = ? while numRecs le 250000 by UserSession.ID:
                
    /* IF SERVER LAST ACTIVE DATE IS NULL, SKIP THE RECORD */
    if UserSession.ServerLastActiveDate = ? then
    do:
        assign
            numMissingServerDate = numMissingServerDate + 1.

        run put-stream ("~"" +
            /*Note*/
            "Session Not Closed - Missing ServerLastActiveDate"
            + "~",~"" +
            /*UserSession.ID*/
            getString(string(UserSession.ID))
            + "~",~"" +
            /*UserSession.SessionID*/
            getString(string(UserSession.SessionID))
            + "~",~"" +
            /*UserSession.InterfaceType*/
            getString(string(UserSession.InterfaceType))
            + "~",~"" +
            /*UserSession.UserName*/
            getString(string(UserSession.UserName))
            + "~",~"" +
            /*UserSession.EntityNumber*/
            getString(string(UserSession.EntityNumber))
            + "~",~"" +
            /*UserSession.ServerLoginDate*/
            getString(string(UserSession.ServerLoginDate))
            + "~",~"" +
            /*UserSession.ServerLoginTime*/
            getString(string(UserSession.ServerLoginTime / 86400))
            + "~",~"" +
            /*UserSession.ServerLastActiveDate*/
            getString(string(UserSession.ServerLastActiveDate))
            + "~",~"" +
            /*UserSession.ServerLastActiveTime*/
            getString(string(UserSession.ServerLastActiveTime / 86400))
            + "~",~"" +
            /*UserSession.LogoutDate*/
            getString(string(UserSession.LogoutDate))
            + "~",~"" +
            /*UserSession.LogoutTime"*/
            getString(string(UserSession.LogoutTime / 86400))
            + "~",").

        next session-loop.
    end.

    /* Check to see if the session record has "timed out" - if it has, clean history records and "close" session record */
    assign 
        LastActiveDateTime = datetime(UserSession.ServerLastActiveDate, UserSession.ServerLastActiveTime * 1000).

    /* CHECK KIOSK SESSIONS */
    if index(UserSession.MiscInformation,"SessionType" + chr(31) + "Kiosk") gt 0 then
    do:
        run CheckKioskSession.
        next session-loop.
    end.

    /* DO NOT KILL ACCESS CONTROL SESSIONS */
    if UserSession.AccessControlSession eq yes then
    do:
        run CheckACSession.
        next session-loop.
    end. /* END ACCESS CONTROL SESSION CHECKS */

    /* USE A DIFFERENT CHECK FOR WEBTRAC INVITES */
    if UserSession.InterfaceType = "WebPortal-Invite" then
    do:
        run CheckWebInvite.
        next session-loop.
    end.

    else if UserSession.ServerLoginDate = ? and
            (LastActiveDateTime + ((if UserSession.InterfaceType = "RecPortal" then RecTracGuest
        else if UserSession.InterfaceType = "Mobile RecPortal" then MRecTracGuest
        else WebTracGuest) * 60000)) lt CurrentDateTime then
        do:
            assign
                numRecs = numRecs + 1.
            run sessioninfo-end (rowid(UserSession)).
        end.

        else
        do:
            for first TransactionDetail no-lock where
                TransactionDetail.SessionID = UserSession.SessionID and
                lookup(TransactionDetail.CartStatus,{&SaDetailInCartList}) ne 0:
            end.
            if available TransactionDetail and
                (LastActiveDateTime + ((if UserSession.InterfaceType = "RecPortal" then RecTracCart
            else if UserSession.InterfaceType = "Mobile RecPortal" then MRecTracCart
            else WebTracCart) * 60000)) lt CurrentDateTime then
            do:
                assign
                    numRecs = numRecs + 1.
                run sessioninfo-end (rowid(UserSession)).
            end.
            else if UserSession.ServerLoginDate ne ? and ((LastActiveDateTime + ((if UserSession.InterfaceType = "RecPortal" then RecTracInactive
                else if UserSession.InterfaceType = "Mobile RecPortal" then MRecTracInactive
                else WebTracInactive) * 60000)) lt CurrentDateTime ) then
                do:
                    assign
                        numRecs = numRecs + 1.
                    run sessioninfo-end (rowid(UserSession)).
                end.
        end.
end. /* END SESSION-LOOP */

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "endSessionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "endSessionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

run ActivityLog("End Sessions Complete; Check Document Center for Logfile of sessions ended",
    "Number of Sessions Ended: " + string(numRecs + numAC + numWebInvite + numKiosk) +  
    "; Breakdown of Sessions - " +
    "RecPortal/WebPortal Sessions Closed: " + string(numRecs) +
    "; Access Control Closed: " + string(numAC) + 
    "; WebInvite Closed: " + string(numWebInvite) + 
    "; Kiosk Closed: " + string(numKiosk) +
    "; Missing Server Last Active Date: " + string(numMissingServerDate)
    ).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHECK WEB INVITE
procedure CheckWebInvite:
    define variable oWebInvite as WebInviteBO no-undo.
  
    oWebInvite = WebInviteBO:getBySessionId(UserSession.SessionID).
    if not valid-object(oWebInvite) or oWebInvite:isValid() then return.
    
    assign 
        numWebInvite = numWebInvite + 1.
        
    run put-stream ("~"" +
        /*Note*/
        "WebPortal Invite Session Closed"
        + "~",~"" +
        /*UserSession.ID*/
        getString(string(UserSession.ID))
        + "~",~"" +
        /*UserSession.SessionID*/
        getString(string(UserSession.SessionID))
        + "~",~"" +
        /*UserSession.InterfaceType*/
        getString(string(UserSession.InterfaceType))
        + "~",~"" +
        /*UserSession.UserName*/
        getString(string(UserSession.UserName))
        + "~",~"" +
        /*UserSession.EntityNumber*/
        getString(string(UserSession.EntityNumber))
        + "~",~"" +
        /*UserSession.ServerLoginDate*/
        getString(string(UserSession.ServerLoginDate))
        + "~",~"" +
        /*UserSession.ServerLoginTime*/
        getString(string(UserSession.ServerLoginTime / 86400))
        + "~",~"" +
        /*UserSession.ServerLastActiveDate*/
        getString(string(UserSession.ServerLastActiveDate))
        + "~",~"" +
        /*UserSession.ServerLastActiveTime*/
        getString(string(UserSession.ServerLastActiveTime / 86400))
        + "~",~"" +
        /*UserSession.LogoutDate*/
        getString(string(UserSession.LogoutDate))
        + "~",~"" +
        /*UserSession.LogoutTime"*/
        getString(string(UserSession.LogoutTime / 86400)) 
        + "~",").
        
    oWebInvite:invalidate().  
end procedure.

// CHECK ACCESS CONTROL SESSION
/* CODE FROM ANOTHER VERSION - POSSIBLY .33 */
/*procedure CheckACSession:                                                           */
/*    define variable ACWorkstation as character no-undo.                             */
/*                                                                                    */
/*    ACWorkstation = UserSession.WorkStationName.                                  */
/*                                                                                    */
/*    /* BACKUP FOR OLDER SESSIONS WITHOUT WORKSTATION ON SESSION */                  */
/*    if isEmpty(ACWorkstation) then                                                  */
/*    do:                                                                             */
/*        run ReadContextData in Business.Library.Super:SuperHandle(                  */
/*            input UserSession.SessionID,                                          */
/*            input "",                                                               */
/*            input "ALL",                                                            */
/*            input no,                                                               */
/*            output table ttContextData).                                            */
/*                                                                                    */
/*        CONTEXT-LOOP:                                                               */
/*        for first ttContextData where                                               */
/*            ttContextData.FieldName = "Workstation":                                */
/*            ACWorkstation = ttContextData.FieldValue.                               */
/*            leave CONTEXT-LOOP.                                                     */
/*        end.                                                                        */
/*    end.                                                                            */
/*                                                                                    */
/*    find first ttACSessions where ttACSessions.WorkStation = ACWorkstation no-error.*/
/*    if available ttACSessions then                                                  */
/*    do:                                                                             */
/*        if ttACSessions.ID gt UserSession.ID then                                 */
/*        do:                                                                         */
/*            run sessioninfo-end (rowid(UserSession), "Empty Cart").               */
/*            assign                                                                  */
/*                numAC = numAC + 1.                                                  */
/*            return.                                                                 */
/*        end.                                                                        */
/*                                                                                    */
/*        run sessioninfo-end (ttACSessions.xRowid,"Empty Cart").                     */
/*        assign                                                                      */
/*            ttACSessions.ID     = UserSession.ID                                  */
/*            ttACSessions.xRowid = rowid(UserSession)                              */
/*            numAC               = numAC + 1.                                        */
/*        return.                                                                     */
/*    end.                                                                            */
/*                                                                                    */
/*    create ttACSessions.                                                            */
/*    assign                                                                          */
/*        ttACSessions.ID          = UserSession.ID                                 */
/*        ttACSessions.xRowid      = rowid(UserSession)                             */
/*        ttACSessions.WorkStation = ACWorkstation.                                   */
/*end procedure.                                                                      */

/* CODE FROM .34.01 */
procedure CheckACSession:
    define variable ACWorkstation as character no-undo.
  
    ACWorkstation = UserSession.WorkStationName.
  
    /* BACKUP FOR OLDER SESSIONS WITHOUT WORKSTATION ON SESSION */
    if isEmpty(ACWorkstation) then 
    do:
        run ReadContextData(
            input UserSession.SessionID,
            input "",
            input "ALL",
            input no,
            output table ttContextData).
      
        CONTEXT-LOOP:
        for first ttContextData where
            ttContextData.FieldName = "Workstation":
            ACWorkstation = ttContextData.FieldValue.
            leave CONTEXT-LOOP.
        end.
    end.    
  
    find first ttACSessions where ttACSessions.WorkStation = ACWorkstation no-error.
    if available ttACSessions then 
    do:
        if ttACSessions.ID gt UserSession.ID then 
        do:
            assign 
                numAC = numAC + 1.
            run sessioninfo-end (rowid(UserSession)).
            return.
        end.
    
        run sessioninfo-end (ttACSessions.xRowid).
        assign
            ttACSessions.ID     = UserSession.ID
            ttACSessions.xRowid = rowid(UserSession)
            numAC               = numAC + 1.
        return.
    end.

    create ttACSessions.
    assign
        ttACSessions.ID          = UserSession.ID
        ttACSessions.xRowid      = rowid(UserSession)
        ttACSessions.WorkStation = ACWorkstation.
end procedure.

// CHECK KIOSK SESSION
procedure CheckKioskSession:
    define variable KioskWorkStation as character no-undo.
    define variable SessionUserName  as character no-undo.
  
    assign
        KioskWorkStation = trueval(UserSession.WorkStationName)
        SessionUserName  = UserSession.UserName.
  
    for first ttKioskSessions where (KioskWorkStation ne "" and ttKioskSessions.WorkStation = KioskWorkStation) or
        ttKioskSessions.UserName = SessionUserName:
        if ttKioskSessions.ID gt UserSession.ID then 
        do:
            run sessioninfo-end (rowid(UserSession)).
            assign 
                numKiosk = numKiosk + 1.
            return.
        end.
    
        run sessioninfo-end (ttKioskSessions.xRowid).
        assign
            ttKioskSessions.ID     = UserSession.ID
            ttKioskSessions.xRowid = rowid(UserSession)
            numKiosk               = numKiosk + 1.
        return.
    end.

    create ttKioskSessions.
    assign
        ttKioskSessions.ID          = UserSession.ID
        ttKioskSessions.xRowid      = rowid(UserSession)
        ttKioskSessions.WorkStation = KioskWorkStation
        ttKioskSessions.UserName    = SessionUserName.
end procedure.

// SESSION INFO END
procedure sessioninfo-end:

    define input parameter ws-rowid as rowid no-undo.
    
    do transaction:
  
        find UserSession no-lock where rowid(UserSession) = ws-rowid no-error.
      
        if available UserSession and UserSession.ServerLogoutDate = ? then 
        do:        
            create SessionAudit.
            assign
                SessionAudit.SessionID     = UserSession.SessionID
                SessionAudit.SubSessionID  = "1"
                SessionAudit.Routine       = "SessionCleaner"
                SessionAudit.Action        = "SessionCleaner"
                SessionAudit.PostingDate   = today
                SessionAudit.PostingTime   = time
                SessionAudit.SubAction     = "SessionCleaner"
                SessionAudit.UserAgent     = if SessionClientType(false) = "WEBSPEED" then GetUserAgent() else ""
                SessionAudit.UserName      = UserSession.UserName
                SessionAudit.QueryString   = "X"
                SessionAudit.IPAddress     = if SessionClientType(false) = "WEBSPEED" then GetRealIP() else ""
                SessionAudit.InterfaceType = UserSession.InterfaceType.
        end.
      
        else find UserSession no-lock where rowid(UserSession) = ws-rowid no-error.
      
        if not available UserSession then message "UserSession unavailable - Rowid = " + string(ws-rowid).
        
        run put-stream ("~"" +
            /*Note*/
            "Session Closed"
            + "~",~"" +
            /*UserSession.ID*/
            getString(string(UserSession.ID))
            + "~",~"" +
            /*UserSession.SessionID*/
            getString(string(UserSession.SessionID))
            + "~",~"" +
            /*UserSession.InterfaceType*/
            getString(string(UserSession.InterfaceType))
            + "~",~"" +
            /*UserSession.UserName*/
            getString(string(UserSession.UserName))
            + "~",~"" +
            /*UserSession.EntityNumber*/
            getString(string(UserSession.EntityNumber))
            + "~",~"" +
            /*UserSession.ServerLoginDate*/
            getString(string(UserSession.ServerLoginDate))
            + "~",~"" +
            /*UserSession.ServerLoginTime*/
            getString(string(UserSession.ServerLoginTime / 86400))
            + "~",~"" +
            /*UserSession.ServerLastActiveDate*/
            getString(string(UserSession.ServerLastActiveDate))
            + "~",~"" +
            /*UserSession.ServerLastActiveTime*/
            getString(string(UserSession.ServerLastActiveTime / 86400))
            + "~",~"" +
            /*UserSession.LogoutDate*/
            getString(string(UserSession.LogoutDate))
            + "~",~"" +
            /*UserSession.LogoutTime"*/
            getString(string(UserSession.LogoutTime / 86400)) 
            + "~",").

        run SessionEnd(UserSession.SessionID).
        
    end.
end procedure. /* SESSIONINFO-END END */

// SessionEnd.p AS A PROCEDURE
procedure sessionEnd:

    def input parameter sessionid as char no-undo.

    def var receiptNumbers as char no-undo init "".

    /* Get Any TransactionDetail records tied to session stil in cart... 
       - Run BEFORE SpecialSessionEnd.p because the RecordStatus/CartStatus will be REMOVED after*/
    receipt-loop:
    for each TransactionDetail no-lock where TransactionDetail.SessionID = SessionID and 
        lookup(TransactionDetail.CartStatus,{&SaDetailInCartList}) ne 0:
        if num-entries(receiptNumbers) gt 10 then 
        do: 
            receiptNumbers = receiptNumbers + " +++". 
            leave receipt-loop.
        end.
        receiptNumbers = UniqueList(string(TransactionDetail.CurrentReceipt), receiptNumbers, ",").
    end.
    /* ***************************  Main Block  *************************** */

    run Business/EndSession.p  /* External session management */ (sessionid, yes).

    find first UserSession exclusive-lock where UserSession.SessionID = sessionid no-error no-wait.
    if available UserSession then assign
            UserSession.LogOutDate       = today
            UserSession.LogOutTime       = time
            UserSession.ServerLogoutDate = date(datetime-tz( now, 0))
            UserSession.ServerLogoutTime = truncate(mtime( datetime-tz( now, 0)) / 1000, 0) .

    if receiptNumbers gt "" then 
    do: 
        /* Add this to the audit log ONLY if receipts are involved.*/
        create ActivityLog.
        assign
            ActivityLog.SourceProgram = "SessionEnd"
            ActivityLog.LogDate       = today
            ActivityLog.UserName      = signon()
            ActivityLog.LogTime       = time
            ActivityLog.Detail1       = "Session ID: " + sessionID
            ActivityLog.Detail2       = "Receipt Numbers With Items Removed From Cart: " + receiptNumbers
            ActivityLog.Detail3       = "Instantiating Procedure: " + this-procedure:instantiating-procedure:name. 
    end.    
  
    for each SessionContext no-lock where SessionContext.SessionID = sessionid:
        run deleteSAContext (rowid(SessionContext)).
    end.
end procedure.

// DELETE SACONTEXT
procedure deleteSAContext: 
    def input parameter InpRowid as rowid no-undo.
    def buffer BufContext for SessionContext. 
    do for BufContext transaction: 
        find first BufContext exclusive-lock where rowid(BufContext) = inprowid no-error no-wait.
        if available BufContext then  delete BufContext.
    end. 
end procedure.


// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "endSessionsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(1000)" skip.
    counter = counter + 1.
    if counter gt 40000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY TRANSACTIONDETAIL RECORDS WERE CHANGED
procedure ActivityLog:
    define input parameter logDescription as character no-undo.
    define input parameter logDetail as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "endSessions.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = logDescription
            BufActivityLog.Detail2       = logDetail.
    end.
end procedure.
