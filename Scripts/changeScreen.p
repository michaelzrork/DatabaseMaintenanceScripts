/*------------------------------------------------------------------------
    File        : programName.p
    Purpose     : 

    Syntax      : 

    Description : xDescription

    Author(s)   : michaelzrork
    Created     : 
    Notes       : How to use this template:
                    - Start with a save as! (I've forgotten this step and needed to recreate this template many times!)
                    - Do a find/replace all for programName and xDescription to update all locations these are mentioned; these will print in the audit log 
                    - Don't forget to add a creation date and update the Author!
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs as integer   no-undo.
define variable oldCode as character no-undo.
define variable newCode as character no-undo.

assign
    oldCode = "RSAdmin2"
    newCode = "RSAdmin"
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each FormDefinition no-lock where FormDefinition.Design = oldCode:
    run changeScreen(FormDefinition.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHANGE SCREEN
procedure changeScreen:
    define input parameter inpID as int64 no-undo.
    define buffer bufFormDefinition for FormDefinition.
    do for bufFormDefinition transaction:
        find first bufFormDefinition exclusive-lock where bufFormDefinition.ID = inpID no-error no-wait.
        if available bufFormDefinition then assign bufFormDefinition.Design = newCode.
        numRecs = numRecs + 1.
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "programName.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "xDescription"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.