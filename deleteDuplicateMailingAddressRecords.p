/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "deleteDuplicateSAAddressRecords" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Delete Duplicate Address Management Records"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s)   : michaelzr
   Created     : 5/15/25
   Notes       : Loops through all MailingAddress Records and looks for duplicates, deleting them
                 Then, for each duplicate it deletes, it updates the AccountAddress table with the new Record code
                 The first Record it finds when looking for duplicates is used as the one to keep, but since this is
                 the oldest Record it may have an out of date RecordCode, so after the first MailingAddress loop it loops again,
                 this time fixing the Record code to match the import formatting of Number Street Apartment, City, State Zip Code
                 Except I also strip the ", " from the beginning of the code that the address import adds when there is no Number or Street
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

function ParseList character (inputValue as char) forward.
function RoundUp returns decimal(dValue as decimal,precision as integer) forward.
function AddCommas returns character (dValue as decimal) forward.

define stream   ex-port.
define variable inpfile-num      as integer   no-undo init 1.
define variable inpfile-loc      as character no-undo init "".
define variable counter          as integer   no-undo init 0.
define variable ixLog            as integer   no-undo init 1. 
define variable logfileDate      as date      no-undo.
define variable logfileTime      as integer   no-undo.
define variable LogOnly          as logical   no-undo init false.
define variable ActivityLogID       as int64     no-undo init 0.
define variable fixedAddressCode as character no-undo init "".
define variable numRecs          as integer   no-undo init 0.
define variable numHHAddressRecs as integer   no-undo init 0. 
define variable numFixedCodes    as integer   no-undo init 0.
define variable ClientCode           as character no-undo init "".
define variable cLastID          as character no-undo init "".
define variable lastTable        as character no-undo init "".
    
find first CustomField no-lock where CustomField.FieldName = "ClientID" no-error no-wait.
if available CustomField then assign ClientCode = CustomField.FieldValue.

assign
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false
    logfileDate = today
    logfileTime = time.
    
define temp-table ttAddress
    field ID          as int64
    field AddressCode as character 
    field Street      as character 
    field Number      as character  
    field Apartment   as character 
    field City        as character 
    field State       as character 
    field Zip         as character
    field NewCode     as character 
    index ID          ID
    index AddressCode AddressCode
    index Street      Street
    index Number      Number
    index Apartment   Apartment
    index City        City
    index State       State
    index Zip         Zip.

define temp-table ttDeleted
    field ID as int64
    index ID ID.
    
empty temp-table ttDeleted no-error.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE INITIAL AUDIT LOG STATUS ENTRY */
run ActivityLog({&ProgramDescription},"Program in Progress","Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).

/* CREATE LOG FILE FIELD HEADERS */
/* I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER */
run put-stream (
    "Table," +
    "ID," +
    "RecordCode," +
    "Changes," +
    "Duplicate of Record Code," +
    "New Code,").

/* INITIAL ADDRESS LOOP TO FIND DUPLICATES */
address-loop:
for each MailingAddress no-lock:
    
    run trimFields(MailingAddress.ID).
    
    for first ttAddress no-lock where ttAddress.ID <> MailingAddress.ID and ttAddress.State = MailingAddress.State and ttAddress.Zip = MailingAddress.ZipCode and ttAddress.City = MailingAddress.City and ttAddress.Street = MailingAddress.Street and ttAddress.Number = MailingAddress.Number and ttAddress.Apartment = MailingAddress.Apartment:   
        for each AccountAddress no-lock where AccountAddress.RecordCode = MailingAddress.RecordCode:
            if AccountAddress.RecordCode <> ttAddress.NewCode then
                run updateHouseholdAddress(AccountAddress.ID,ttAddress.NewCode).
        end.
        
        run deleteAddress(MailingAddress.ID,ttAddress.NewCode,ttAddress.AddressCode).  
    end.
    if not available ttAddress then 
    do:
        create ttAddress.
        assign 
            ttAddress.ID          = MailingAddress.ID
            ttAddress.Street      = MailingAddress.Street
            ttAddress.Number      = MailingAddress.Number
            ttAddress.Apartment   = MailingAddress.Apartment
            ttAddress.City        = MailingAddress.City
            ttAddress.State       = MailingAddress.State
            ttAddress.Zip         = MailingAddress.ZipCode
            ttAddress.AddressCode = MailingAddress.RecordCode
            ttAddress.NewCode     = trim(trim(
                                    trim(getString(MailingAddress.Number)
                                    + " " 
                                    + getString(MailingAddress.Street))
                                    + (if MailingAddress.Apartment <> "" then " " + getString(MailingAddress.Apartment) else "")
                                    + (if getString(MailingAddress.City) = "" then "" else ", " 
                                    + getString(MailingAddress.City)) 
                                    + ", "
                                    + getString(MailingAddress.State)
                                    + " " 
                                    + getString(MailingAddress.ZipCode)
                                    ),", ").
    end.
end.

/* AFTER DELETING DUPLICATES WE THEN FIX ANY REMAINING ADDRESS CODES */
fixcode-loop:
for each MailingAddress no-lock:
    
    find first ttAddress no-lock where ttAddress.ID = MailingAddress.ID no-error no-wait.
    if available ttAddress then 
    do:
        if MailingAddress.RecordCode <> ttAddress.NewCode then 
        do:
            for each AccountAddress no-lock where AccountAddress.RecordCode = MailingAddress.RecordCode:
                run updateHouseholdAddress(AccountAddress.ID,ttAddress.NewCode).
            end.
            run fixAddressCode(MailingAddress.ID,ttAddress.NewCode).
        end.
    end.
    
    else 
    do:
        find first ttDeleted no-lock where ttDeleted.ID = MailingAddress.ID.
        if available ttDeleted then next fixcode-loop.
        
        assign 
            fixedAddressCode = trim(trim(
                                    trim(getString(MailingAddress.Number)
                                    + " " 
                                    + getString(MailingAddress.Street))
                                    + (if MailingAddress.Apartment <> "" then " " + getString(MailingAddress.Apartment) else "")
                                    + (if getString(MailingAddress.City) = "" then "" else ", " 
                                    + getString(MailingAddress.City)) 
                                    + ", "
                                    + getString(MailingAddress.State)
                                    + " " 
                                    + getString(MailingAddress.ZipCode)
                                    ),", ").
                                    
        if MailingAddress.RecordCode <> fixedAddressCode then 
        do: 
            for each AccountAddress no-lock where AccountAddress.RecordCode = MailingAddress.RecordCode:
                run updateHouseholdAddress(AccountAddress.ID,fixedAddressCode).
            end.
            run fixAddressCode(MailingAddress.ID,fixedAddressCode).
        end.
    end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* UPDATE AUDIT LOG STATUS Record */
run UpdateActivityLog({&ProgramDescription},"Program is Complete; Check Document Center for a log of Records Changed","Number of MailingAddress Records Deleted: " + addCommas(numRecs),"Number of MailingAddress Records Updated: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated: " + addCommas(numHHAddressRecs)).

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* TRIM FIELDS */
procedure trimFields:
    define input parameter inpID as int64 no-undo.
    define buffer bufMailingAddress for MailingAddress.
    do for bufMailingAddress transaction:
        find first bufMailingAddress exclusive-lock where bufMailingAddress.ID = inpID no-error no-wait.
        if available bufMailingAddress then assign
                bufMailingAddress.Street    = left-trim(trim(trim(trim(trim(trim(replace(bufMailingAddress.Street,"~"","~'"),"'"),"-"),"/")),"."),"0")
                bufMailingAddress.Number    = left-trim(trim(trim(trim(trim(trim(replace(bufMailingAddress.Number,"~"","~'"),"'"),"-"),"/")),"."),"0")
                bufMailingAddress.Apartment = left-trim(trim(trim(trim(trim(trim(replace(bufMailingAddress.Apartment,"~"","~'"),"'"),"-"),"/")),"."),"0")
                bufMailingAddress.City      = left-trim(trim(trim(trim(trim(trim(replace(bufMailingAddress.City,"~"","~'"),"'"),"-"),"/")),"."),"0")
                bufMailingAddress.State     = left-trim(trim(trim(trim(trim(trim(replace(bufMailingAddress.State,"~"","~'"),"'"),"-"),"/")),"."),"0")
                bufMailingAddress.ZipCode   = trim(trim(trim(trim(trim(replace(bufMailingAddress.ZipCode,"~"","~'"),"'"),"-"),"/")),".").
    end.
end procedure.
        
/* FIX ADDRESS CODE */
procedure fixAddressCode:
    define input parameter inpID as int64 no-undo.
    define input parameter newCode as character no-undo.
    define buffer BufAddress for MailingAddress.
    do for BufAddress transaction:
        if LogOnly then 
        do:
            find first BufAddress no-lock where BufAddress.ID = inpID no-error no-wait.
            assign 
                cLastID   = getString(string(bufMailingAddress.ID))
                LastTable = "MailingAddress".
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).
            if locked BufAddress then
            do:
                run ActivityLog("MailingAddress Record Code Not Updated","Locked Record ID: " + string(BufAddress.ID),"Original Record Code: " + BufAddress.RecordCode,"New Record Code: " + newCode,"").
                return.
            end.
            else if available BufAddress then
                do:
                    run put-stream ("~"" +
                        /*Table*/
                        "Updated MailingAddress Record Code"
                        + "~",~"" +
                        /*ID*/
                        getString(string(BufAddress.ID))
                        + "~",~"" +
                        /*RecordCode*/
                        "Original Record Code: " + replace(getString(BufAddress.RecordCode),"~"","~"~"")
                        + "~",~"" +
                        /*Changes*/
                        "New Record Code: " + replace(getString(newCode),"~"","~"~"")
                        + "~",~"" +
                        /*Duplicate of Record Code*/
                        ""
                        + "~",~"" +
                        /*New Record Code*/
                        ""
                        + "~",").
                    assign 
                        numFixedCodes = numFixedCodes + 1.
                end. 
        end.
        else 
        do:
            find first BufAddress exclusive-lock where BufAddress.ID = inpID no-error no-wait.
            assign 
                cLastID   = getString(string(bufMailingAddress.ID))
                LastTable = "MailingAddress".
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).
            if locked BufAddress then
            do:
                run ActivityLog("MailingAddress Record Code Not Updated","Locked Record ID: " + string(BufAddress.ID),"Original Record Code: " + BufAddress.RecordCode,"New Record Code: " + newCode,"").
                return.
            end.
            else if available BufAddress then
                do:
                    run put-stream ("~"" +
                        /*Table*/
                        "Updated MailingAddress Record Code"
                        + "~",~"" +
                        /*ID*/
                        getString(string(BufAddress.ID))
                        + "~",~"" +
                        /*RecordCode*/
                        "Original Record Code: " + replace(getString(BufAddress.RecordCode),"~"","~"~"")
                        + "~",~"" +
                        /*Changes*/
                        "New Record Code: " + replace(getString(newCode),"~"","~"~"")
                        + "~",~"" +
                        /*Duplicate of Record Code*/
                        ""
                        + "~",~"" +
                        /*New Record Code*/
                        ""
                        + "~",").
                    assign 
                        numFixedCodes           = numFixedCodes + 1
                        BufAddress.RecordCode = newCode
                        BufAddress.Apartment  = replace(trim(BufAddress.Apartment),"~"","~'")
                        BufAddress.City       = replace(trim(BufAddress.City),"~"","~'")
                        BufAddress.Number     = replace(trim(BufAddress.Number),"~"","~'")
                        BufAddress.State      = replace(trim(BufAddress.State),"~"","~'")
                        BufAddress.Street     = replace(trim(BufAddress.Street),"~"","~'")
                        BufAddress.ZipCode    = replace(trim(BufAddress.ZipCode),"~"","~'").
                end. 
        end.
    end.
end procedure.

/* DELETE SAADDRESS */
procedure deleteAddress:
    define input parameter inpID as int64 no-undo.
    define input parameter ttNewCode as character no-undo.
    define input parameter ttCode as character no-undo.
    define buffer BufAddress for MailingAddress.
    do for BufAddress transaction:
        if logOnly then 
        do:
            find first BufAddress no-lock where BufAddress.ID = inpID no-error no-wait.
            assign 
                cLastID   = getString(string(bufMailingAddress.ID))
                LastTable = "MailingAddress".
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).
            if locked BufAddress then 
            do:
                run ActivityLog("MailingAddress Record Not Deleted","Locked Record ID: " + string(BufAddress.ID),"Record Code: " + BufAddress.RecordCode,"","").
                return.
            end.
            if available BufAddress then 
            do:
                find first ttDeleted no-lock where ttDeleted.ID = BufAddress.ID no-error no-wait.
                if not available ttDeleted then 
                do:
                    create ttDeleted.
                    assign 
                        ttDeleted.ID = BufAddress.ID.
                end.
                run put-stream ("~"" +
                    /*Table*/
                    "Deleted MailingAddress Record"
                    + "~",~"" +
                    /*ID*/
                    getString(string(BufAddress.ID))
                    + "~",~"" +
                    /*RecordCode*/
                    "Deleted Record Code: " + replace(getString(BufAddress.RecordCode),"~"","~"~"")
                    + "~",~"" +
                    /*Changes*/
                    "Deleted Record Details: " + replace(trim(trim(getString(BufAddress.Number) + " " + getString(BufAddress.Street) + " " + (if BufAddress.Apartment <> "" then " " + getString(BufAddress.Apartment) else "") + ", " + getString(BufAddress.City) + ", " + getString(BufAddress.State) + " " + getString(BufAddress.ZipCode),", ")," "),"~"","~"~"")
                    + "~",~"" +
                    /*Duplicate of Record Code*/
                    "Duplicate of Original Record Code: " + replace(getString(ttCode),"~"","~"~"")
                    + "~",~"" +
                    /*New Record Code*/
                    "New Record Code: " + replace(getString(ttNewCode),"~"","~"~"")
                    + "~",").
                assign 
                    numRecs = numRecs + 1.
                
            end.
        end.
        else 
        do:
            find first BufAddress exclusive-lock where BufAddress.ID = inpID no-error no-wait.
            assign 
                cLastID   = getString(string(bufMailingAddress.ID))
                LastTable = "MailingAddress".
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).
            if locked BufAddress then 
            do:
                run ActivityLog("MailingAddress Record Not Deleted","Locked Record ID: " + string(BufAddress.ID),"Record Code: " + BufAddress.RecordCode,"","").
                return.
            end.
            if available BufAddress then 
            do:
                run put-stream ("~"" +
                    /*Table*/
                    "Deleted MailingAddress Record"
                    + "~",~"" +
                    /*ID*/
                    getString(string(BufAddress.ID))
                    + "~",~"" +
                    /*RecordCode*/
                    "Deleted Record Code: " + replace(getString(BufAddress.RecordCode),"~"","~"~"")
                    + "~",~"" +
                    /*Changes*/
                    "Deleted Record Details: " + replace(trim(trim(getString(BufAddress.Number) + " " + getString(BufAddress.Street) + " " + (if BufAddress.Apartment <> "" then " " + getString(BufAddress.Apartment) else "") + ", " + getString(BufAddress.City) + ", " + getString(BufAddress.State) + " " + getString(BufAddress.ZipCode),", ")," "),"~"","~"~"")
                    + "~",~"" +
                    /*Duplicate of Record Code*/
                    "Duplicate of Original Record Code: " + replace(getString(ttCode),"~"","~"~"")
                    + "~",~"" +
                    /*New Record Code*/
                    "New Record Code: " + replace(getString(ttNewCode),"~"","~"~"")
                    + "~",").
                assign 
                    numRecs = numRecs + 1.
                delete BufAddress.
            end.
        end.
    end.
end procedure.

/* UPDATE ACCOUNT ADDRESS */
procedure updateHouseholdAddress:
    define input parameter inpID as int64 no-undo.
    define input parameter newCode as character no-undo.
    define buffer BufHouseholdAddress for AccountAddress.
    do for BufHouseholdAddress transaction:
        if logOnly then 
        do:
            find first BufHouseholdAddress no-lock where BufHouseholdAddress.ID = inpID no-error no-wait.
            assign 
                cLastID   = getString(string(bufAccountAddress.ID))
                LastTable = "AccountAddress".
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).
            if locked BufHouseholdAddress then 
            do:
                run ActivityLog("AccountAddress Record Not Updated","Locked Record ID: " + string(BufHouseholdAddress.ID),"Original Code: " + BufHouseholdAddress.RecordCode,"New Record Code: " + newCode,"").
                return.
            end.
            if available BufHouseholdAddress then 
            do:
                /*                run put-stream ("~"" +                                                                       */
                /*                    /*Table*/                                                                                */
                /*                    "Updated AccountAddress Record Code"                                                 */
                /*                    + "~",~"" +                                                                              */
                /*                    /*ID*/                                                                                   */
                /*                    getString(string(BufHouseholdAddress.ID))                                                */
                /*                    + "~",~"" +                                                                              */
                /*                    /*RecordCode*/                                                                           */
                /*                    "Original Record Code: " + replace(getString(BufHouseholdAddress.RecordCode),"~"","~"~"")*/
                /*                    + "~",~"" +                                                                              */
                /*                    /*Changes*/                                                                              */
                /*                    "New Record Code: " + replace(newCode,"~"","~"~"")                                       */
                /*                    + "~",~"" +                                                                              */
                /*                    /*Duplicate of Record Code*/                                                             */
                /*                    ""                                                                                       */
                /*                    + "~",~"" +                                                                              */
                /*                    /*New Record Code*/                                                                      */
                /*                    ""                                                                                       */
                /*                    + "~",").                                                                                */
                assign
                    numHHAddressRecs = numHHAddressRecs + 1.
            end.
        end.
        else 
        do:
            find first BufHouseholdAddress exclusive-lock where BufHouseholdAddress.ID = inpID no-error no-wait.
            assign 
                cLastID   = getString(string(bufAccountAddress.ID))
                LastTable = "AccountAddress".
            run UpdateActivityLog({&ProgramDescription},"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of MailingAddress Records Deleted So Far: " + addCommas(numRecs),"Number of MailingAddress Records Updated So Far: " + addCommas(numFixedCodes),"Number of AccountAddress Records Updated So Far: " + addCommas(numHHAddressRecs)).
            if locked BufHouseholdAddress then 
            do:
                run ActivityLog("AccountAddress Record Not Updated","Locked Record ID: " + string(BufHouseholdAddress.ID),"Original Code: " + BufHouseholdAddress.RecordCode,"New Record Code: " + newCode,"").
                return.
            end.
            if available BufHouseholdAddress then 
            do:
                /*                run put-stream ("~"" +                                                                       */
                /*                    /*Table*/                                                                                */
                /*                    "AccountAddress"                                                                     */
                /*                    + "~",~"" +                                                                              */
                /*                    /*ID*/                                                                                   */
                /*                    getString(string(BufHouseholdAddress.ID))                                                */
                /*                    + "~",~"" +                                                                              */
                /*                    /*RecordCode*/                                                                           */
                /*                    "Original Record Code: " + replace(getString(BufHouseholdAddress.RecordCode),"~"","~"~"")*/
                /*                    + "~",~"" +                                                                              */
                /*                    /*Changes*/                                                                              */
                /*                    "New Record Code: " + replace(newCode,"~"","~"~"")                                       */
                /*                    + "~",~"" +                                                                              */
                /*                    /*Duplicate of Record Code*/                                                             */
                /*                    ""                                                                                       */
                /*                    + "~",~"" +                                                                              */
                /*                    /*New Record Code*/                                                                      */
                /*                    ""                                                                                       */
                /*                    + "~",").                                                                                */
                assign
                    numHHAddressRecs                 = numHHAddressRecs + 1
                    BufHouseholdAddress.RecordCode = newCode.
            end.
        end.
    end.
end procedure.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
    counter = counter + 1.
    if counter gt 100000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

/* CREATE AUDIT LOG ENTRY */
procedure ActivityLog:
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    define input parameter LogDetail5 as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = {&ProgramName} + ".r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = LogDetail1
            BufActivityLog.Detail2       = LogDetail2
            BufActivityLog.Detail3       = LogDetail3
            BufActivityLog.Detail4       = LogDetail4
            BufActivityLog.Detail5       = LogDetail5.
        /* IF THIS IS THE FIRST AUDIT LOG ENTRY, UPDATE THE ID FIELD */
        if ActivityLogID = 0 then assign
                ActivityLogID = BufActivityLog.ID.
    end.
end procedure.

/* UPDATE AUDIT LOG STATUS ENTRY */
procedure UpdateActivityLog:
    define input parameter LogDetail1 as character no-undo.
    define input parameter LogDetail2 as character no-undo.
    define input parameter LogDetail3 as character no-undo.
    define input parameter LogDetail4 as character no-undo.
    define input parameter LogDetail5 as character no-undo.
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        if ActivityLogID = 0 then return.
        find first BufActivityLog exclusive-lock where BufActivityLog.ID = ActivityLogID no-error no-wait.
        if available BufActivityLog then 
            assign
                BufActivityLog.LogDate = today
                BufActivityLog.LogTime = time
                BufActivityLog.Detail1 = LogDetail1
                BufActivityLog.Detail2 = LogDetail2
                BufActivityLog.Detail3 = LogDetail3
                BufActivityLog.Detail4 = LogDetail4
                BufActivityLog.Detail5 = LogDetail5.
    end.
end procedure.

/*************************************************************************
                            INTERNAL FUNCTIONS
*************************************************************************/

/* FUNCTION RETURNS A COMMA SEPARATED LIST FROM CHR(30) SEPARATED LIST IN A SINGLE VALUE */
function ParseList character (inputValue as char):
    if index(inputValue,chr(31)) > 0 and index(inputValue,chr(30)) > 0 then 
        return replace(replace(inputValue,chr(31),": "),chr(30),", ").
    else if index(inputValue,chr(30)) > 0 and index(inputValue,chr(31)) = 0 then
            return replace(inputValue,chr(30),": ").
        else if index(inputValue,chr(30)) = 0 and index(inputValue,chr(31)) > 0 then
                return replace(inputValue,chr(31),": ").
            else return inputValue.
end.

/* FUNCTION RETURNS A DECIMAL ROUNDED UP TO THE PRECISION VALUE */
function RoundUp returns decimal(dValue as decimal,precision as integer):
    define variable newValue  as decimal   no-undo.
    define variable decLoc    as integer   no-undo.
    define variable tempValue as character no-undo.
    define var      tempInt   as integer   no-undo.
    
    /* IF THE TRUNCATED VALUE MATCHES THE INPUT VALUE, NO ROUNDING IS NECESSARY; RETURN THE ORIGINAL VALUE */
    if dValue - truncate(dValue,precision) = 0 then
        return dValue.
            
    /* IF THE ORIGINAL VALUE MINUS THE TRUNCATED VALUE LEAVES A REMAINDER THEN ROUND UP */
    else 
    do:
        assign
            /* FINDS THE LOCATION OF THE DECIMAL SO IT CAN BE ADDED BACK IN LATER */
            decLoc    = index(string(truncate(dValue,precision)),".")
            /* TRUNCATES TO THE PRECISION POINT, DROPS THE DECIMAL, CONVERTS TO AN INT, THEN IF NEGATIVE SUBTRACTS ONE, IF POSITIVE ADDS ONE */
            tempValue = string(integer(replace(string(truncate(dValue,precision)),".","")) + if dValue < 0 then -1 else 1).
        /* ADDS THE DECIMAL BACK IN AT THE ORIGINAL LOCATION */
        assign 
            substring(tempValue,(if decLoc = 0 then length(tempValue) + 1 else decLoc),0) = ".".
        /* RETURNS THE RESULTING VALUE AS A DECIMAL */ 
        return decimal(tempValue).
    end.
end.

/* FUNCTION RETURNS A NUMBER AS A CHARACTER WITH ADDED COMMAS */
function AddCommas returns character (dValue as decimal):
    define variable absValue     as decimal   no-undo.
    define variable iValue       as integer   no-undo.
    define variable cValue       as character no-undo.
    define variable ix           as integer   no-undo.
    define variable decimalValue as character no-undo.
    define variable decLoc       as integer   no-undo.
    assign
        absValue     = abs(dValue)
        decLoc       = index(string(absValue),".")
        decimalValue = substring(string(absValue),(if decLoc = 0 then length(string(absValue)) + 1 else decLoc))
        iValue       = truncate(absValue,0)
        cValue       = string(iValue).
    do ix = 1 to roundUp(length(string(iValue)) / 3,0) - 1:
        assign 
            substring(cValue,length(string(iValue)) - ((ix * 3) - 1),0) = ",".
    end.
    return (if dValue < 0 then "-" else "") + cValue + decimalValue.
end.