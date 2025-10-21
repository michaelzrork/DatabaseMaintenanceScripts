/*------------------------------------------------------------------------
    File        : stripUnwantedCharactersFromXref.p
    Purpose     : Remove unwanted charcters from Cross Reference files

    Syntax      : 

    Description : This will strip all %, Z, and ? from existing Xref files

    Author(s)   : michaelzrork
    Created     : 07/17/2023
    Notes       : This was modified from my trimAllLeadingZeros.p
  ----------------------------------------------------------------------*/
  
/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
define variable recCount as integer no-undo.
recCount = 0. // Initialize the variable to 0

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// Loop through each record in EntityLink to find the records we're looking for
for each EntityLink no-lock:
    if index(EntityLink.ExternalID,"452016") <> 0 and (index(EntityLink.ExternalID,"%") <> 0 or index(EntityLink.ExternalID,"?") <> 0 or index(EntityLink.ExternalID,"Z") <> 0) then
        run stripSpecialCharacters(EntityLink.ID).
end.

// Call the ActivityLog procedure to log how many records were adjusted 
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// This procedure strips the %, Z, and ? from the EntityLink code 
procedure stripSpecialCharacters:
    define input parameter inpid as int64 no-undo. // Define an input parameter for the record ID
    define buffer bufEntityLink for EntityLink. // Define a buffer for the EntityLink table
    find bufEntityLink exclusive-lock where bufEntityLink.ID = inpid no-error no-wait. // Find the record with the given ID
        if available bufEntityLink then assign // Check if the record was found
            recCount = recCount + 1 // Increment the count of records adjusted
            bufEntityLink.ExternalID = StripUnwantedCharacters(bufCrossreference.ExternalID,"0123456789","").
end procedure.

// This procedure logs how many records were adjusted 
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog. // Define buffer for ActivityLog
    do for BufActivityLog transaction: // Start a transaction
        create BufActivityLog. // Create a new record in ActivityLog
        assign // Assign values to the fields
            BufActivityLog.SourceProgram = "stripUnwantedCharactersFromXref"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Strips anything but numbers from Cross Reference records"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(recCount).
    end.
end procedure.
