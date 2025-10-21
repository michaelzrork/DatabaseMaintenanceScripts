/*------------------------------------------------------------------------
    File        : fixLocationCode.p
    Purpose     : replaces ItemLocationCode and TransactionLocationCodes 
                  with a new FaciltyCode

    Syntax      : 

    Description : Fixes an issue caused by a bug with Code Conversion, where
                  all visits after the code conversion were recorded with
                  an invalid Facility Code for their ItemLocationCode and 
                  their TransactionLocationCode

    Author(s)   : MichaelZR
    Created     : 10/6/2023
    Notes       : 11/15/2023 - Updated to run through a list of changed codes
                             - Also added FileLinkCode2 and FileLinkCode4
                  11/29/2023 - fixed it so it only goes through each TransactionDetail record once,
                               then checks each field against the code list. This should help
                               it run faster.
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
define variable ix          as integer   no-undo. 

inpfile-num = 1.

define variable oldLocationCodeList as character no-undo.
define variable newLocationCodeList as character no-undo.
define variable numRecs             as integer   no-undo.
define variable loopCount           as integer   no-undo.
define variable ActivityLogOldCode     as character no-undo.
define variable ActivityLogNewCode     as character no-undo.
define variable codeCount           as int       no-undo.
define variable oldLocationCode     as character no-undo.
define variable newLocationCode     as character no-undo.

oldLocationCodeList = "".
newLocationCodeList = "".
ActivityLogOldCode     = "".
ActivityLogNewCode     = "".
numRecs             = 0.
codeCount           = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/


// CREATE LOG FILE FIELDS
run put-stream ("TransactionDetail.ID,TransactionDetail.ItemLocationCode,TransactionDetail.TransactionLocationCode,TransactionDetail.FileLinkCode2,TransactionDetail.FileLinkCode4").

// CREATE LIST OF CODES FROM ActivityLog
for each ActivityLog where ActivityLog.SourceProgram = "CodeConversion" and ActivityLog.Detail1 = "Process Option: FacilityLocation" by ActivityLog.ID:
    // FIND CODES IN OLD AUDIT LOG ENTRY FORMAT
    if index(ActivityLog.Detail2,"  New: ") > 0 then assign
            ActivityLogOldCode = substring(ActivityLog.Detail2,6,index(ActivityLog.Detail2,"  New: ") - 6)
            ActivityLogNewCode = substring(ActivityLog.Detail2,index(ActivityLog.Detail2,"  New: ") + 7).
    // FIND CODES IN NEW AUDIT LOG ENTRY FORMAT
    else assign
            ActivityLogOldCode = substring(ActivityLog.Detail2,18)
            ActivityLogNewCode = substring(ActivityLog.Detail3,18).
    // ADD CODES TO LISTS
    assign
        oldLocationCodeList = list(ActivityLogOldCode,oldLocationCodeList)
        newLocationCodeList = list(ActivityLogNewCode,newLocationCodeList).
    // IF OLD CODE WAS CONVERTED PREVIOUSLY, REPLACE THE OLD CODE IN THE NEW LIST WITH THE NEWEST CODE
    if lookup(ActivityLogOldCode,newLocationCodeList) > 0 then newLocationCodeList = replace(newLocationCodeList,ActivityLogOldCode,ActivityLogNewCode).
end.

// FIND ALL RECORDS THAT CONTAIN A LOCATION CODE FROM OLD LIST
for each TransactionDetail where lookup(TransactionDetail.ItemLocationCode,oldLocationCodeList) > 0 or lookup(TransactionDetail.TransactionLocationCode,oldLocationCodeList) > 0
    or lookup(TransactionDetail.FileLinkCode2,oldLocationCodeList) > 0
    or ((TransactionDetail.Module = "PT" or TransactionDetail.Module = "ARV" or TransactionDetail.Module = "LSV") and lookup(TransactionDetail.FileLinkCode4,oldLocationCodeList) > 0):
    run fixLocationCode(TransactionDetail.ID).   
end.

// CREATE LOG FILE
do ix = 1 to inpfile-num:
    if search(sessiontemp() + "SADetailRecordsUpdated" + string(ix) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "SADetailRecordsUpdated" + string(ix) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// UPDATE VARIOUS LOCATION CODES TO NEW LOCATION CODE
procedure fixLocationCode:
    define input parameter inpid as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpid no-error no-wait.
        if available bufTransactionDetail then 
        do:
            // JUST ONE COUNT PER SADETAIL RECOD
            numRecs = numRecs + 1.
            // LOG ORIGINAL VALUES
            run put-stream (string(BufTransactionDetail.ID) + "," + string(bufTransactionDetail.ItemLocationCode) + "," + string(bufTransactionDetail.TransactionLocationCode) + "," + string(bufTransactionDetail.FileLinkCode2) + "," + string(bufTransactionDetail.FileLinkCode4)).
            // LOOP THROUGH LOCATION CODES AND UPDATE SADETAIL RECORD FIELDS
            codeLoop:
            do codeCount = 1 to num-entries(oldLocationCodeList):
                // CREATE A TEMP OLD CODE AND NEW CODE TO CHECK FIELDS AGAINST
                oldLocationCode = entry(codeCount,oldLocationCodeList).
                newLocationCode = entry(codeCount,newLocationCodeList).
                // SKIP RECORDS THAT WERE LATER CHANGED BACK TO THEIR ORIGINAL VALUES
                if oldLocationCode = newLocationCode then next codeLoop.
                // ITEM LOCATION CODE FIELD
                if bufTransactionDetail.ItemLocationCode = oldLocationcode then bufTransactionDetail.ItemLocationCode = newLocationCode.
                // TRANSACTION LOCATION CODE FIELD
                if bufTransactionDetail.TransactionLocationCode = oldLocationCode then bufTransactionDetail.TransactionLocationCode = newLocationCode.
                // FILE LINK CODE 2 FIELD
                if bufTransactionDetail.FileLinkCode2 = oldLocationCode then bufTransactionDetail.FileLinkCode2 = newLocationCode.
                // FILE LINK CODE 4 FIELD
                if bufTransactionDetail.FileLinkCode4 = oldLocationCode then bufTransactionDetail.FileLinkCode4 = newLocationCode.
            end. // CODELOOP
        end. // DO
    end. // TRANSACTION
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "SADetailRecordsUpdated" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 15000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY SADETAIL RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "fixLocationCode.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Replace old facility location code in TransactionDetail records"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs)
            BufActivityLog.Detail3       = "Old Location Code List: " + string(oldLocationCodeList)
            BufActivityLog.Detail4       = "New Location Code List: " + string(newLocationCodeList).
    end.
end procedure.
            
        
        
    