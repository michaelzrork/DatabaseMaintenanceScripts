define variable xDescription as character no-undo.
define variable programName as character no-undo.

assign 
    programName  = "trimSAAddressCommaAndSpace" // Prints in Audit Log and used for logfile name
    xDescription = "Remove the leading ~", ~" from Address Management record codes". // Prints in Audit Log when included as input parameter  

/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 
   Notes       : 
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
define variable numLinked   as integer   no-undo.

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time
    
    numRecs     = 0
    numLinked   = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/*/* CREATE LOG FILE FIELD HEADERS */                                                                                                                                                                              */
/*run put-stream (                                                                                                                                                                                                 */
/*    "Put," +                                                                                                                                                                                                     */
/*    "Field," +                                                                                                                                                                                                   */
/*    "Headers," +                                                                                                                                                                                                 */
/*    "Here,"). // I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER                                                           */
/*                                                                                                                                                                                                                 */
/*/* USE THIS WITHIN YOUR MAIN BLOCK OR PROCEDURE TO ADD THE LOGFILE RECORDS */                                                                                                                                    */
/*run put-stream ("~"" +                                                                                                                                                                                           */
/*    /*Logfile*/                                                                                                                                                                                                  */
/*    ""                                                                                                                                                                                                           */
/*    + "~",~"" +                                                                                                                                                                                                  */
/*    /*Fields*/                                                                                                                                                                                                   */
/*    ""                                                                                                                                                                                                           */
/*    + "~",~"" +                                                                                                                                                                                                  */
/*    /*Go*/                                                                                                                                                                                                       */
/*    ""                                                                                                                                                                                                           */
/*    + "~",~"" +                                                                                                                                                                                                  */
/*    /*Here*/                                                                                                                                                                                                     */
/*    ""                                                                                                                                                                                                           */
/*    + "~",").                                                                                                                                                                                                    */
/*                                                                                                                                                                                                                 */
/*/* CREATE LOG FILE */                                                                                                                                                                                            */
/*do ixLog = 1 to inpfile-num:                                                                                                                                                                                     */
/*    if search(sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then                                             */
/*        SaveFileToDocuments(sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").*/
/*end.                                                                                                                                                                                                             */

for each MailingAddress exclusive-lock where MailingAddress.RecordCode begins ", ":
    assign
        numRecs              = numRecs + 1
        MailingAddress.RecordCode = trim(MailingAddress.RecordCode,", ").
    
end.

for each AccountAddress exclusive-lock where AccountAddress.RecordCode begins ", ":
    assign 
        numLinked                     = numLinked + 1
        AccountAddress.RecordCode = trim(AccountAddress.RecordCode,", ").
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog(xDescription,"Number of Address Records Adjusted: " + string(numRecs),"Number of Linked Account Records Adjusted: " + string(numLinked),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + programName + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            bufActivityLog.SourceProgram = programName + ".r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail1
            bufActivityLog.Detail2       = logDetail2
            bufActivityLog.Detail3       = logDetail3
            bufActivityLog.Detail4       = logDetail4.
    end.
end procedure.