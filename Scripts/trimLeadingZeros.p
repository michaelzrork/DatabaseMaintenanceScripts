/*------------------------------------------------------------------------
    File        : trimLeadingZeros.p
    Purpose     : Remove the leading 0's from Cross Reference files

    Syntax      : 

    Description : 

    Author(s)   : michaelzrork
    Created     : 05/10/2023
    Notes       : This will trim all leading 0s
  ----------------------------------------------------------------------*/
  
/*************************************************************************
                                DEFINITIONS
*************************************************************************/

/* Define variable to keep count of records that have their ExternalID trimmed */
define variable recCount as integer no-undo.
recCount = 0. // Initialize the variable to 0

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* Loop through each record in EntityLink that has a leading 0 in ExternalID */
for each EntityLink no-lock where substring(EntityLink.ExternalID, 1, 1) = "0":
    run trimLeadingZero(EntityLink.ID). // Call the trimLeadingZero procedure to trim the leading 0 from the record's ExternalID
end.

/* Call the ActivityLog procedure to log how many records were adjusted */
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* This procedure trims the leading 0 from the ExternalID of a single record */
procedure trimLeadingZero:
    define input parameter inpid as int64 no-undo. // Define an input parameter for the record ID
    define buffer bufEntityLink for EntityLink. // Define a buffer for the EntityLink table
    find bufEntityLink exclusive-lock where bufEntityLink.ID = inpid no-error no-wait. // Find the record with the given ID
        if available bufEntityLink then assign // Check if the record was found
            recCount = recCount + 1 // Increment the count of records adjusted
            bufEntityLink.ExternalID = left-trim(bufEntityLink.ExternalID, "0").
end procedure.

/* This procedure logs how many records were adjusted */
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog. // Define buffer for ActivityLog
    do for BufActivityLog transaction: // Start a transaction
        create BufActivityLog. // Create a new record in ActivityLog
        assign // Assign values to the fields
            BufActivityLog.SourceProgram = "trimLeadingZeros"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Trim the leading zeros from the ExternalID in EntityLink"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(recCount).
    end.
end procedure.
