/*------------------------------------------------------------------------
    File        : findRecordsWithDynamicTable.p
    Purpose     : 

    Syntax      : 

    Description : Wrote this to test making changes to records using a dynamic table and field

    Author(s)   : michaelzrork
    Created     : 
    Notes       : - This was generated with the help of ChatGPT, with modifications to get it to work
                  - It's designed  to work in Scratchpad and message with an alert box with the parent table data for the first SearchCache record found 
  ----------------------------------------------------------------------*/

define variable hBuffer      as handle    no-undo.
define variable hQuery       as handle    no-undo.
define variable hField       as handle    no-undo.
define variable bufferField  as character no-undo.
define variable cParentTable as character no-undo.
define variable cParentID    as int64 no-undo.
define variable cFieldValue  as character no-undo.
define variable cSQL         as character no-undo.

find first SearchCache no-lock no-error no-wait.

if available SearchCache then 
do:

    /* Assign the parent table and parent ID from SearchCache */
    assign 
        cParentTable = SearchCache.ParentTable
        cParentID    = SearchCache.ParentRecord. /* Assuming ParentID is a character */

    /* Create a dynamic buffer for the Parent Table */
    create buffer hBuffer for table cParentTable.

    /* Create a dynamic query */
    create query hQuery.

    /* Set the buffer to the dynamic query */
    hQuery:set-buffers(hBuffer).

    /* Construct dynamic query string to find the first record where ID matches */
    cSQL = substitute("for each &1 no-lock where &1.ID = &2", cParentTable, cParentID).

    /* Prepare and open the query */
    hQuery:query-prepare(cSQL).
    hQuery:query-open().
    hQuery:get-first().

    /* Check if the record was found */
    if hQuery:query-off-end then 
    do:
        message "Record not found" view-as alert-box.
    end.
    else 
    do:
        if cParentTable = "GRTeeTime" then cFieldValue = "Tee Time".
        else 
        do:
            /* Check if the field 'ShortDescription' exists */
            hField = hBuffer:buffer-field("ShortDescription") no-error.
    
            if valid-handle(hField) then 
            do:
                /* Store the value of ShortDescription */
                cFieldValue = hField:buffer-value.
                bufferField = "ShortDescription".
            end.
            else 
            do:
                /* Check if the field 'ShortDescription' exists */
                hField = hBuffer:buffer-field("Description") no-error.
    
                if valid-handle(hField) then 
                do:
                    /* Store the value of ShortDescription */
                    cFieldValue = hField:buffer-value.
                    bufferField = "Description".
                end.
                else 
                do:
                    /* If ShortDescription is not available, try ComboKey */
                    hField = hBuffer:buffer-field("ComboKey") no-error.
                    if valid-handle(hField) then 
                    do:
                        cFieldValue = hField:buffer-value.
                        bufferField = "ComboKey".
                    end.
                    do:
                        /* If ShortDescription is not available, try ComboKey */
                        hField = hBuffer:buffer-field("ComboKey") no-error.
                        if valid-handle(hField) then 
                        do:
                            cFieldValue = hField:buffer-value.
                            bufferField = "ComboKey".
                        end.
            
                        else 
                        do:
                            message "Neither ShortDescription nor ComboKey fields found."
                                view-as alert-box.
                        end.
                    end.
                end.
            end.
        end.
    
        /* Use or display the value as needed */
        message cParentTable + "." + bufferField + " = " + cFieldValue view-as alert-box.
    end.

/* Clean up the dynamic objects */
hQuery:query-close().
delete object hQuery.
delete object hBuffer.

end.
else message "No SearchCache Record Available" view-as alert-box.