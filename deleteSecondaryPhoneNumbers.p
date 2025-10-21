/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "deleteSecondaryPhoneNumbers" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Delete all secondary phone numbers"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
 /*----------------------------------------------------------------------
    Author(s)   : michaelzr
    Created     : 4/3/25
    Notes       : - Customer did a household import that somehow caused the phone numbers to be added as a secondary number
                  - My guess is that they did an import with the incorrect phone numbers or a different value in the phone field, and the system
                    added them as secondary when they didn't match the existing primary 
                  - Looks like they actually had the correct phone numbers already in the system as the primary, and when they imported the wrong 
                    phone numbers it moved all of the primary numbers to the secondary, adding the wrong numbers as the primary 
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

define variable numRecs     as integer   no-undo. 

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time
    
    numRecs     = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each PhoneNumber no-lock where PhoneNumber.PrimaryPhoneNumber = false:
    run deletePhone(PhoneNumber.ID).
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Number of Records Found: " + string(numRecs),"","").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* DELETE SECONDARY PHONE */
procedure deletePhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:
        find first bufPhoneNumber exclusive-lock where bufPhoneNumber.ID = inpID no-error.
        if available bufPhoneNumber then 
        do:
            assign 
                numRecs = numRecs + 1.
            delete bufPhoneNumber.
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