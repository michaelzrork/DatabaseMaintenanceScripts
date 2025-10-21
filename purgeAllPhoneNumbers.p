/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "purgeAllPhoneNumbers" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Purge all phone numbers from the database"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s)   : 
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

define variable numRecs     as integer   no-undo init 0.
define variable hhRecs      as integer   no-undo init 0.
define variable personName  as character no-undo init "".
define variable accountNum       as integer   no-undo init 0. 
define variable fmRecs      as integer   no-undo init 0.

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time.
    
/* FUNCTION RETURNS A COMMA SEPARATED LIST FROM CHR(30) SEPARATED LIST IN A SINGLE VALUE */
function parseList character (inputValue as char):
    if index(chr(31),inputValue) > 0 and index(chr(30),inputValue) > 0 then 
        return replace(replace(inputValue,chr(31),": "),chr(30),", ").
    else if index(chr(30),inputValue) > 0 and index(chr(31),inputValue) = 0 then
            return replace(inputValue,chr(30),", ").
        else if index(chr(30),inputValue) = 0 and index(chr(31),inputValue) > 0 then
                return replace(inputValue,chr(31),", ").
            else return inputValue.
end.

define temp-table ttSkip
    field xtable as char
    field id     as int64
    index id id.
    
empty temp-table ttSkip.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
/* I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER */
run put-stream (
    "ID," +
    "Table," +
    "Parent Table," +
    "Parent ID," +
    "Member ID," +
    "Account Num," +
    "Name," +
    "Phone Number," +
    "Phone Ext," +
    "Phone Type,").

for each Account no-lock where Account.CreationDate > 3/30/2025 or (Account.CreationDate = 3/30/2025 and Account.CreationTime > 57600) /*or Account.CreationUserName = "WWW"*/:
    
    /*ADD TO SKIP LIST*/
    find first ttSkip no-lock where ttSkip.id = Account.ID no-error.
    if not available ttSkip then 
    do:
        create ttSkip.
        assign 
            ttSkip.xtable = "Account"
            ttSkip.id     = Account.ID.
    end.
    
    if Account.PrimaryPhoneNumber <> "" then 
    do:
        for each PhoneNumber no-lock where PhoneNumber.ParentTable = "Account" and PhoneNumber.ParentRecord = Account.ID:
            find first ttSkip where ttSkip.ID = PhoneNumber.ID no-error.
            if not available ttSkip then 
            do:
                create ttSkip.
                assign 
                    ttSkip.xtable = "PhoneNumber"
                    ttSkip.id     = PhoneNumber.ID.
            end.
        end.
    end.
    
    /*FAMILY MEMBER LOOP TO ADD TO SKIP LIST*/
    for each Relationship no-lock where Relationship.ParentTableID = Account.ID and Relationship.ChildTable = "Member":
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error.
        if available Member then 
        do:
            find first ttSkip where ttSkip.id = Member.ID no-error.
            if not available ttSkip then
            do:
                create ttSkip.
                assign 
                    ttSkip.xtable = "Member"
                    ttSkip.ID     = Member.ID.
            end.
            
            if Member.PrimaryPhoneNumber <> "" then 
            do:
                for each PhoneNumber no-lock where PhoneNumber.ParentTable = "Member" and PhoneNumber.MemberLinkID = Member.ID:
                    find first ttSkip where ttSkip.ID = PhoneNumber.ID no-error.
                    if not available ttSkip then 
                    do:
                        create ttSkip.
                        assign 
                            ttSkip.xtable = "PhoneNumber"
                            ttSkip.id     = PhoneNumber.ID.
                    end.
                end.
            end.
        end.
    end.
end.

/*ActivityLog-loop:                                                                                                                                           */
/*for each ActivityLog no-lock where ActivityLog.SourceProgram = "Maintenance" and ActivityLog.Detail1 = "Account Update" and ActivityLog.UserName = "WWW":*/
/*    find first ttSkip where ttSkip.ID = ActivityLog.Detail2 no-error.                                                                                     */
/*    if not available ttSkip then                                                                                                                         */
/*    do:                                                                                                                                                  */
/*                                                                                                                                                         */
/*    end.                                                                                                                                                 */
/*end.                                                                                                                                                     */

phone-loop:
for each PhoneNumber no-lock:
    
    find first ttSkip where ttSkip.id = PhoneNumber.ID no-error.
    if available ttSkip then next phone-loop.
    
    find first Member no-lock where Member.ID = PhoneNumber.MemberLinkID no-error.
    if available Member then assign
            personName = trim(getString(Member.FirstName) + " " + getString(Member.LastName)).
    
    if PhoneNumber.ParentTable = "Account" then 
    do:
        find first Account no-lock where Account.ID = PhoneNumber.ParentRecord no-error.
        if available Account then assign 
                accountNum = Account.EntityNumber.
    end.
    
    run deletePhoneNumber(PhoneNumber.ID).
end.

account-loop:
for each Account no-lock where Account.PrimaryPhoneNumber <> "":
    find first ttSkip where ttSkip.ID = Account.ID no-error.
    if available ttSkip then next account-loop.
    assign 
        personName = trim(getString(Account.FirstName + " " + getString(Account.LastName)))
        accountNum      = Account.EntityNumber.
    run stripHHPhone(Account.ID).
end.

person-loop:
for each Member no-lock where Member.PrimaryPhoneNumber <> "":
    find first ttSkip where ttSkip.ID = Member.ID no-error.
    if available ttSkip then next person-loop.
    assign 
        personName = trim(getString(Member.FirstName + " " + getString(Member.LastName))).
    run stripFMPhone(Member.ID).
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Check Document Center for " + {&ProgramName} + "Log for a log of Records Changed","Number of Phone Records Deleted: " + string(numRecs) + "; Number of Account Numbers Removed: " + string(hhRecs) + "; " + "Number of Member Numbers Removed: " + string(fmRecs),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteSAPhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:
        find first bufPhoneNumber exclusive-lock where bufPhoneNumber.ID = inpID no-error.
        if available bufPhoneNumber then 
        do:
            assign
                numRecs = numRecs + 1.
            run put-stream ("~"" +
                /*ID*/
                getString(string(bufPhoneNumber.ID))
                + "~",~"" +
                /*Table*/
                "PhoneNumber"
                + "~",~"" +
                /*Parent Table*/
                getString(bufPhoneNumber.ParentTable)
                + "~",~"" +
                /*Parent ID*/
                getString(string(bufPhoneNumber.ParentRecord))
                + "~",~"" +
                /*Member ID*/
                getString(string(bufPhoneNumber.MemberLinkID))
                + "~",~"" +
                /*Account Num*/
                (if accountNum <> 0 then getString(string(accountNum)) else "N/A")
                + "~",~"" +
                /*Name*/
                getString(personName)
                + "~",~"" +
                /*Phone Number*/
                getString(bufPhoneNumber.PhoneNumber)
                + "~",~"" +
                /*Phone Ext*/
                getString(bufPhoneNumber.Extension)
                + "~",~"" +
                /*Phone Type*/
                getString(bufPhoneNumber.PhoneType)
                + "~",~"" +
                /*Primary*/
                (if bufPhoneNumber.PrimaryPhoneNumber then "True" else "False")
                + "~",").
            delete PhoneNumber.
        end.
    end.
end.

procedure stripHHPhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find first bufAccount exclusive-lock where bufAccount.ID = inpID no-error.
        if available bufAccount then 
        do:
            run put-stream ("~"" +
                /*ID*/
                getString(string(bufAccount.ID))
                + "~",~"" +
                /*Table*/
                "Account"
                + "~",~"" +
                /*Parent Table*/
                "N/A"
                + "~",~"" +
                /*Parent ID*/
                "N/A"
                + "~",~"" +
                /*Member ID*/
                "N/A"
                + "~",~"" +
                /*Account Num*/
                (if accountNum <> 0 then getString(string(accountNum)) else "N/A")
                + "~",~"" +
                /*Name*/
                getString(personName)
                + "~",~"" +
                /*Phone Number*/
                getString(bufAccount.PrimaryPhoneNumber)
                + "~",~"" +
                /*Phone Ext*/
                getString(bufAccount.PrimaryPhoneExtension)
                + "~",~"" +
                /*Phone Type*/
                getString(bufAccount.PrimaryPhoneType)
                + "~",~"" +
                /*Primary*/
                "True"
                + "~",").
            assign 
                hhRecs                               = hhRecs + 1
                bufAccount.PrimaryPhoneNumber    = ""
                bufAccount.PrimaryPhoneExtension = ""
                bufAccount.PrimaryPhoneType      = "".
        end.
    end.
end procedure.

procedure stripFMPhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error.
        if available bufMember then 
        do:
            run put-stream ("~"" +
                /*ID*/
                getString(string(bufMember.ID))
                + "~",~"" +
                /*Table*/
                "Member"
                + "~",~"" +
                /*Parent Table*/
                "N/A"
                + "~",~"" +
                /*Parent ID*/
                "N/A"
                + "~",~"" +
                /*Member ID*/
                "N/A"
                + "~",~"" +
                /*Account Num*/
                (if accountNum <> 0 then getString(string(accountNum)) else "N/A")
                + "~",~"" +
                /*Name*/
                getString(personName)
                + "~",~"" +
                /*Phone Number*/
                getString(bufMember.PrimaryPhoneNumber)
                + "~",~"" +
                /*Phone Ext*/
                getString(bufMember.PrimaryPhoneExtension)
                + "~",~"" +
                /*Phone Type*/
                getString(bufMember.PrimaryPhoneType)
                + "~",~"" +
                /*Primary*/
                "True"
                + "~",").
            assign 
                fmRecs                            = fmRecs + 1
                bufMember.PrimaryPhoneNumber    = ""
                bufMember.PrimaryPhoneExtension = ""
                bufMember.PrimaryPhoneType      = "".
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