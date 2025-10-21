/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "addEmailVerificationAndOptInStatus" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Adds lost Email Address Verification and Opt In status as seen in DEMO"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 3/17/25
   Notes       : This may be useless, as they've likely come up with an alternative solution at this point and the data may be drastically out of date
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo. 
define variable logfileDate as date      no-undo.
define variable logfileTime as integer   no-undo.

define variable exactCount  as integer   no-undo. 
define variable searchCount as integer   no-undo.
define variable recCount    as integer   no-undo.

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time
    
    exactCount  = 0
    searchCount = 0
    recCount    = 0.
    
    // FILE IMPORT STUFF

{Includes/ProcessingConfig.i}
{Includes/TransactionDetailStatusList.i}
{Includes/TTVals.i}
{Includes/Screendef.i "reference-only"}  
{Includes/AvailableCredit.i}
{Includes/AvailableScholarship.i} 
{Includes/ModuleList.i} 
{Includes/TTProfile.i}

define variable importFileName as character no-undo.
define variable importfile     as char      no-undo.  
define variable tmpcode1       as char      no-undo. 

def stream exp.

def temp-table ttImport no-undo 
    field ParentID             as int64
    field ParentTable          as character 
    field EmailAddress         as character 
    field PrimaryEmailAddress  as logical
    field MemberLinkID       as int64
    field ID                   as int64
    field LastVerifiedDateTime as datetime
    field Verified             as logical
    field OptIn                as logical
    field OptInIP              as character
    field OptInDateTime        as datetime
    field VerificationSentDate as date
    index ID             ID
    index parentID       parentID
    index MemberLinkID MemberLinkID.
    
assign 
    importFileName = "optInRecords.txt"
    tmpcode1       = "\Import\" + importFileName.
    
disable triggers for load of EmailContact.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// GRAB INPUT FILE FROM DOCUMENT CENTER IMPORT
CreateFile (tmpcode1, false, sessionTemp(), true, false) no-error. 

// SET IMPORTFILE VALUE WITH SESSION AND IMPORT FILE NAME
assign
    Importfile = sessionTemp() + importFileName.

// CHECK FOR IMPORT FILE
if search(Importfile) = ? then 
do:
    // IF NOT FOUND, CREATE ERROR RECORD AND END
    run ActivityLog("Program aborted: " + Importfile + " not found!").
    return.
end.   
 
// SET IMPORT FILE
input stream exp from value(importfile) no-echo.

// RESET COUNTER FOR IMPORT LOOP
assign 
    counter = 0.

// CREATE TEMP TABLE FROM INPUT FILE VALUES
import-loop:
repeat transaction:
    create ttImport.
    import stream exp delimiter "," ttImport  no-error.
    counter = counter + 1.
end.

// CLOSE INPUT STREAM
input stream exp close.  

// LOG NUMBER OF RECORDS IMPORTED FROM IMPORT FILE
run ActivityLog("Importfile = " + Importfile,"Import Records imported = " + string(counter),"","").

// RESET COUNTER FOR LOGFILE
assign 
    counter = 0.
  
// SET CHANGES HEADER
run put-stream("ID," +
    "Import ID," +
    "Parent Table," +
    "Parent ID," +
    "Email Address," +
    "Person ID," +
    "Original Verified," +
    "Verified," +
    "Original OptIn," +
    "OptIn,").

// LOOPS THROUGH ALL IMPORTED RECORDS
ttImport-loop:
for each ttImport:
    if ttImport.ParentTable = "" then delete ttImport.
    if ttImport.ParentTable = "ParentTable" then next ttImport-loop.
    find first EmailContact no-lock where EmailContact.ID = ttImport.ID no-error.
    if available EmailContact then 
    do:
        assign 
            exactCount = exactCount + 1.
        if not EmailContact.Verified or not EmailContact.OptIn then run updateEmailAddress(EmailContact.ID,yes,yes).
    end.
    if not available EmailContact then
        for first EmailContact no-lock where EmailContact.ParentRecord = ttImport.ParentRecord and EmailContact.ParentTable = ttImport.ParentTable and EmailContact.MemberLinkID = ttImport.MemberLinkID and EmailContact.EmailAddress = ttImport.EmailAddress:
            assign 
                searchCount = searchCount + 1.
            if not EmailContact.OptIn or not EmailContact.Verified then 
            do:
                if ttImport.PrimaryEmailAddress and not EmailContact.PrimaryEmailAddress and not EmailContact.Verified then run updateEmailAddress(SAemailAddress.ID,yes,EmailContact.OptIn).
                else run updateEmailAddress(EmailContact.ID,yes,yes).
            end.
        end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// DELETES THE UPLOADED TXT FILE AFTER UPDATING RECORDS
DeleteBlob(tmpcode1).

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Check Document Center for " + {&ProgramName} + "Log for a log of Records Changed","Number of Records Found: " + string(recCount),"Exact match: " + string(exactCount) + ", Search Match: " + string(searchCount)).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* Update Email Address */
procedure updateEmailAddress:
    define input parameter inpID as int64.
    define input parameter lVerified as logical.
    define input parameter lOptedIn as logical. 
    define buffer bufEmailContact for EmailContact.
    define variable dNow as datetime.
    assign 
        dNow = datetime(today,mtime).
    do for bufEmailContact transaction:
        find first bufEmailContact exclusive-lock where bufEmailContact.ID = inpID no-error.
        if available bufEmailContact then 
        do:
            run put-stream ("~"" +
                /*ID*/
                getString(string(bufEmailContact.ID))
                + "~",~"" +
                /*Import ID*/
                getString(string(ttImport.ID))
                + "~",~"" +
                /*Parent Table*/
                getString(bufEmailContact.ParentTable)
                + "~",~"" +
                /*Parent ID*/
                getString(string(bufEmailContact.ParentRecord))
                + "~",~"" +
                /*Email Address*/
                getString(bufEmailContact.EmailAddress)
                + "~",~"" +
                /*Person ID*/
                getString(string(bufEmailContact.MemberLinkID))
                + "~",~"" +
                /*Original Verified*/
                (if bufEmailContact.Verified = true then "Yes" else "No")
                + "~",~"" +
                /*Verified*/
                (if lVerified = true then "Yes" else "No")
                + "~",~"" +
                /*Original OptIn*/
                (if bufEmailContact.OptIn then "Yes" else "No")
                + "~",~"" +
                /*OptIn*/
                (if lOptedIn = true then "Yes" else "No")
                + "~",").
            assign 
                bufEmailContact.LastVerifiedDateTime = if bufEmailContact.LastVerifiedDateTime = ? then dNow else bufEmailContact.LastVerifiedDateTime
                bufEmailContact.Verified             = lVerified
                bufEmailContact.OptIn                = lOptedIn
                bufEmailContact.OptInDateTime        = dNow
                recCount                               = recCount + 1.
        end.
    end.
end procedure.


/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
    counter = counter + 1.
    if counter gt 40000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    define input parameter logDetail1 as character no-undo.
    define input parameter logDetail2 as character no-undo.
    define input parameter logDetail3 as character no-undo.
    define input parameter logDetail4 as character no-undo.
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = {&ProgramName} + ".r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail1
            bufActivityLog.Detail2       = logDetail2
            bufActivityLog.Detail3       = logDetail3
            bufActivityLog.Detail4       = logDetail4.
    end.
end procedure.