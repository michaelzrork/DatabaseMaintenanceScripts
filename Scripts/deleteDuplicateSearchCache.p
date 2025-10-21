/*------------------------------------------------------------------------
    File        : deleteDuplicateSASearchIndex.p
    Purpose     : 

    Syntax      : 

    Description : Delete Duplicate SearchCache Records

    Author(s)   : michaelzr
    Created     : 7/22/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo. 
define variable logfileDate as date      no-undo.
define variable logfileTime as integer   no-undo. 

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time.

// EVERYTHING ELSE
define variable numRecs            as integer   no-undo.
define variable itemDescription    as character no-undo.
define variable lastCreatedDate    as datetime  no-undo.
define variable bufLastCreatedDate as datetime  no-undo.
assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Parent ID," +
            "Parent Table," +
            "Deleted Record ID," +
            "Deleted Last Created Date," +
            "Duplicate Record ID," +
            "Duplicate Last Created Date," +
            "Deleted WordIndex," +
            "Duplicate WordIndex,").


for each SearchCache no-lock:
    assign
        itemDescription = ""
        lastCreatedDate = datetime(NameVal("LastCreated",SearchCache.MiscInformation,chr(31),chr(30))).
    run findDuplicateRecord(SearchCache.ID,SearchCache.ParentRecord,SearchCache.ParentTable).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "deleteDuplicateSASearchIndexLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "deleteDuplicateSASearchIndexLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE DUPLICATE SASEARCHINDEX RECORD
procedure findDuplicateRecord:
    define input parameter inpID as int64 no-undo.
    define input parameter cParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.
    define buffer bufSearchCache for SearchCache.
    do for bufSearchCache transaction:
        for first bufSearchCache no-lock where bufSearchCache.ID <> inpID and bufSearchCache.ParentRecord = cParentID:
            /*run findDescription(cParentID,cParentTable).*/
            assign
                bufLastCreatedDate = datetime(NameVal("LastCreated",SearchCache.MiscInformation,chr(31),chr(30))).
            if bufLastCreatedDate ge lastCreatedDate then run deleteDuplicateRecord(SearchCache.ID,lastCreatedDate,bufSearchCache.ID,bufLastCreatedDate,bufSearchCache.WordIndex).
            else run deleteDuplicateRecord(bufSearchCache.ID,bufLastCreatedDate,SearchCache.ID,lastCreatedDate,SearchCache.WordIndex). 
        end.
    end.
end procedure.

// DELETE DUPLICATE SASEARCHINDEX RECORD
procedure deleteDuplicateRecord:
    define input parameter inpID as int64 no-undo.
    define input parameter deletedLastCreatedDate as datetime no-undo.
    define input parameter dupeID as int64 no-undo.
    define input parameter dupeLastCreatedDate as datetime no-undo.
    define input parameter dupeWordIndex as character no-undo.
    define buffer bufSearchCache for SearchCache.
    do for bufSearchCache transaction:
        find first bufSearchCache exclusive-lock where bufSearchCache.ID = inpID no-error no-wait.
        if available bufSearchCache then 
        do:
            // "Parent ID,Parent Table,Item Description,Deleted Record ID,Deleted Last Created Date,Duplicate Record ID,Duplicate Last Created Date,Deleted WordIndex,Duplicate WordIndex,"
            run put-stream ("~"" + 
                string(bufSearchCache.ParentRecord)
                + "~",~"" +
                getString(bufSearchCache.ParentTable)
                + "~",~"" + 
                getString(string(bufSearchCache.ID))
                + "~",~"" + 
                getString(string(deletedLastCreatedDate)) 
                + "~",~"" + 
                getString(string(dupeID)) 
                + "~",~"" + 
                getString(string(dupeLastCreatedDate)) 
                + "~",~"" + 
                getString(bufSearchCache.WordIndex) 
                + "~",~"" + 
                getString(dupeWordIndex) 
                + "~",").
            assign 
                numRecs = numRecs + 1.
            delete bufSearchCache.
        end.
    end.
end.

// FIND PARENT ID DESCRIPTION
procedure findDescription:
    define input parameter cParentID as int64 no-undo.
    define input parameter cParentTable as character no-undo.
    define buffer bufSearchCache for SearchCache.
    define variable hBuffer     as handle    no-undo.
    define variable hQuery      as handle    no-undo.
    define variable hField      as handle    no-undo.
    define variable hField2     as handle    no-undo.
    define variable cFieldValue as character no-undo.
    define variable cQuery      as character no-undo.
    
    /* Create a dynamic buffer for the Parent Table */
    create buffer hBuffer for table cParentTable.
    /* Create a dynamic query */
    create query hQuery.
    /* Set the buffer to the dynamic query */
    hQuery:set-buffers(hBuffer).
    /* Construct dynamic query string to find the first record where ID matches */
    cQuery = substitute("for each &1 no-lock where &1.ID = &2", cParentTable, cParentID).
    
    /* Prepare and open the query */
    hQuery:query-prepare(cQuery).
    hQuery:query-open().
    hQuery:get-first().
    
    /* Check if the record was found */
    if hQuery:query-off-end then 
    do:
        message "Record not found." view-as alert-box.
    end.
    else 
    do:
        if cParentTable = "GRTeeTime" then 
        do:
            hField = hBuffer:buffer-field("TeeTimeDate") no-error.
            hField2 = hBuffer:buffer-field("GolfCourse") no-error.
            if valid-handle(hField) and valid-handle(hField2) then 
            do:
                /* Store the value of ShortDescription */
                itemDescription = "Tee Time for Golf Course " + string(hField2) + " on " + string(hfield).
            end.
        end.
        else 
        do:
            /* Check if the field 'ShortDescription' exists */
            hField = hBuffer:buffer-field("ShortDescription") no-error.
            if valid-handle(hField) then 
            do:
                /* Store the value of ShortDescription */
                itemDescription = hField:buffer-value.
            end.
            else 
            do:
                /* Check if the field 'ShortDescription' exists */
                hField = hBuffer:buffer-field("Description") no-error.
                if valid-handle(hField) then 
                do:
                    /* Store the value of ShortDescription */
                    itemDescription = hField:buffer-value.
                end.
                else 
                do:
                    /* If ShortDescription is not available, try ComboKey */
                    hField = hBuffer:buffer-field("ComboKey") no-error.
                    if valid-handle(hField) then 
                    do:
                        itemDescription = hField:buffer-value.
                    end.
                    do:
                        /* If ShortDescription is not available, try ComboKey */
                        hField = hBuffer:buffer-field("ComboKey") no-error.
                        if valid-handle(hField) then 
                        do:
                            itemDescription = hField:buffer-value.
                        end.    
                        else 
                        do:
                            itemDescription = "No Item Description Found".
                        end.
                    end.
                end.
            end.
        end.
    end.   
    /* Clean up the dynamic objects */
    hQuery:query-close().
    delete object hQuery.
    delete object hBuffer.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "deleteDuplicateSASearchIndexLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(3000)" skip.
    counter = counter + 1.
    if counter gt 30000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "deleteDuplicateSASearchIndex.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Delete Duplicate SearchCache Records"
            BufActivityLog.Detail2       = "Check Document Center for deleteDuplicateSASearchIndexLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.