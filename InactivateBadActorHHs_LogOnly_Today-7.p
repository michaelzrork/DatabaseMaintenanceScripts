/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "InactivateBadActorHHs_LogOnly_Today-" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME, DO NOT INCLUDE THE .p OR .r */
&global-define ProgramDescription "Inactivate households created by a bad actor testing stolen credit cards"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
/*----------------------------------------------------------------------
   Author(s):   michaelzr
   Created  :   5/29/25
   Notes    :   - Finds new households created since the check date, which is Today minus the value in the filename (or Today - 7 if it doesn't find a value)
                  This is done by finding the QuickFixProcessor audit log entry and looking for the number after "Today-" in the filename
                - Uses the WebPortal interface parameters to determine the Usernames to check
                - Adds a logfile entry for every Settled transaction for inactivated households so they can be refunded if necessary
                - Inactivates any account using an email address that is known as used by the bad actor
                - Inactivates any account with an email address that includes @example, as these would not be valid email addresses anyway
                - Skips any account with payments in house, as the bad actor wouldn't have access to run cards this way
                - Inactivates any account whose name includes gibberish known to be used by the bad actor (eg. - name begins "asd")
                - Skips households with Account Coordinates, as this means they have legitimate addresses
                - Inactivates any account with a birthday that matches 12/31/69, which is the main one used, or any birthday used in the @example households
                - Skips households with no credit card activity (settled or declined)                
                - Skips households where the card holder name matches a first or last name of any family member
                - Inactivates any account with a declined transaction where the card holder name doesn't match the first or last name of any family member
                - Skips households with no declined transactions (only settled)
 ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

block-level on error undo, throw.

using Business.Library.Results from propath.
using Business.Library.SuperFunctions from propath.

{Includes/InterfaceData.i}
{Includes/ttProfile.i}
{Includes/ttScreen.i}
{Includes/FetchParam.i}
{Includes/ScreenDef.i}
{Includes/PDFSuper.i} 
{Includes/ttLanguageCodes.i}
{Includes/WebAvailability.i}
{src/web/method/cgidefs.i} 
{Includes/InterfaceConfig.i}

{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i}

function ParseList character (inputValue as char) forward.
function RoundUp returns decimal(dValue as decimal,precision as integer) forward.
function AddCommas returns character (dValue as decimal) forward.
function isNumeric returns log (cText as character) forward.

define stream   ex-port.
define variable inpfile-num      as integer   no-undo init 1.
define variable inpfile-loc      as character no-undo init "".
define variable counter          as integer   no-undo init 0.
define variable ixLog            as integer   no-undo init 1. 
define variable logfileDate      as date      no-undo.
define variable logfileTime      as integer   no-undo.
define variable LogOnly          as logical   no-undo init false.
define variable ActivityLogID       as int64     no-undo init 0. 
define variable ClientCode           as character no-undo init "".
define variable cLastID          as character no-undo init "".
define variable LastTable        as character no-undo init "".
define variable ix               as integer   no-undo init 0.
define variable numRecs          as integer   no-undo init 0.
define variable AccountStatus    as character no-undo init "".
define variable CheckDate        as date      no-undo. 
define variable cDaysCheck       as character no-undo.
define variable iNumDays         as integer   no-undo init 7.
define variable numFMs           as integer   no-undo init 0.
define variable numCCHist        as integer   no-undo init 0.
define variable numHHSkipped     as integer   no-undo init 0.
define variable WebTracUserNames as character no-undo init "".
define variable StartPosition    as integer   no-undo init 0.
define variable stopPosition     as integer   no-undo init 0.


/* SET THE CHECKDATE TO TODAY MINUS THE NUMBER OF DAYS IN THE FILENAME OF THE QUICK FIX */
find last ActivityLog no-lock where ActivityLog.SourceProgram = "QuickFixProcessor" and ActivityLog.Detail1 matches "*InactivateBadActorHHs*" and ActivityLog.Detail1 matches "*Today-*" use-index ID no-error no-wait.
if available ActivityLog then 
do:
    assign 
        StartPosition = index(ActivityLog.Detail1,"Today-") + 6.
        
    do ix = 1 to length(substring(ActivityLog.Detail1,StartPosition)) while stopPosition = 0:
        if not isNumeric(substring(ActivityLog.Detail1,StartPosition + ix,1)) then stopPosition = StartPosition + ix.
    end.
        
    assign
        cDaysCheck = substring(ActivityLog.Detail1,StartPosition,stopPosition - startPosition).
    if isNumeric(cDaysCheck) then assign iNumDays = int(cDaysCheck).
    else assign iNumDays = 7.
end.

assign 
    CheckDate = today - iNumDays.

assign
    /* TO SET PROGRAM TO 'LOG ONLY' ADD 'LogOnly' ANYWHERE IN THE GLOBAL VARIABLE PROGRAM NAME eg. 'ProgramName_LogOnly' */
    LogOnly     = if {&ProgramName} matches "*LogOnly*" then true else false // USE THIS VARIABLE TO HALT CHANGES WHEN LOG ONLY eg. 'if not LogOnly then assign'
    logfileDate = today
    logfileTime = time.
    
find first CustomField no-lock where CustomField.FieldName = "ClientID" no-error no-wait.
if available CustomField then assign ClientCode = CustomField.FieldValue.

define temp-table ttHouseholds
    field ID          as int64
    field recordCount as integer 
    index ID ID.
    
define temp-table ttMemberName
    field ID        as int64
    field AccountID      as int64
    field FirstName as character 
    field LastName  as character
    field Birthday  as date
    index ID   ID 
    index AccountID AccountID.
    
define temp-table ttBirthdays
    field Birthday as date
    index Birthday Birthday.
    
create ttBirthdays.
assign 
    ttBirthdays.Birthday = 12/31/1969.
    
interface-loop:
for each IntegrationConfig no-lock where IntegrationConfig.InterfaceType matches "*WebPortal*":
    if getString(IntegrationConfig.UserName) = "" then next interface-loop. 
    assign 
        WebTracUserNames = uniqueList(WebTracUserNames,IntegrationConfig.UserName,",").
end.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
/* I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER */
run put-stream (
    "Log Notes," +
    "Account Number," +
    "Account ID," +
    "FM ID," +
    "CCHistory ID," +
    "Account Name," +
    "FM Name," +
    "Card Holder Name," +
    "Number of Family Members," +
    "HH Creation Date," +
    "HH Creation Time," +
    "HH Creation User," +
    "HH Last Active Date," +
    "HH Phone Number," +
    "FM Birthday," + 
    "HH Street," +
    "HH City," +
    "HH State," +
    "HH Zip Code," +
    "HH Email Address," +
    "FM Email Address," +
    "HH MiscInformation," +
    "HH WordIndex," +
    "CCHist Process Date," +
    "CCHist Posting Time," +
    "CCHist Record Status," +
    "CCHist Username," +
    "CCHist Amount," +
    "CCHist Receipt Num," +
    "CCHist Brand,").

/* CREATE INITIAL AUDIT LOG RECORD */
run ActivityLog(
    {&ProgramDescription} + " as of " + string(CheckDate),
    "Program in Progress",
    "Number of Households Inactivated So Far: " + addCommas(numRecs),
    "Number of Households Skipped So Far:" + addCommas(numHHSkipped),
    "").

/* FIND ACCOUNTS CREATED SINCE CHECK DATE */
hh-loop:
for each Account no-lock where Account.CreationDate ge CheckDate and lookup(Account.CreationUserName,WebTracUserNames) > 0 and Account.RecordStatus = "Active":
    
    /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
    assign 
        cLastID   = getString(string(Account.ID)) // REPLACE 0 WITH TABLENAME.ID 
        LastTable = "Account". // REPLACE <TABLE NAME> WITH THE TABLE NAME
    run UpdateActivityLog(
        {&ProgramDescription} + " as of " + string(CheckDate) + " as of " + string(CheckDate),
        "Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),
        "Number of Households Inactivated So Far: " + addCommas(numRecs),
        "Number of Households Skipped So Far:" + addCommas(numHHSkipped),
        "").
    
    /* RESET Member COUNT */
    assign
        numFMs = 0
        ix     = 0.
    
    /* COUNT HOW MANY FAMILY MEMBERS THERE ARE IN THE ACCOUNT TO ADD TO LOGFILE */
    fm-loop:
    for each Relationship no-lock where Relationship.ParentTable = "Account"
        and Relationship.ParentTableID = Account.ID
        and Relationship.ChildTable = "Member":
        
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error no-wait.
        if available Member then 
        do:
            numFMs = numFMs + 1.
            for first ttMemberName no-lock where ttMemberName.ID = Relationship.ChildTableID and ttMemberName.AccountID = Relationship.ParentTableID:
                next fm-loop.
            end.
            create ttMemberName.
            assign 
                ttMemberName.ID        = Relationship.ChildTableID
                ttMemberName.AccountID      = Relationship.ParentTableID
                ttMemberName.FirstName = Member.FirstName
                ttMemberName.LastName  = Member.LastName
                ttMemberName.Birthday  = Member.Birthday.
        end.
    end.
            
    /* LOOP THROUGH ALL MEMBERS OF THE ACCOUNT TO FIND THE PRIMARY GUARDIAN */
    primary-loop:
    for each Relationship no-lock where Relationship.ParentTable = "Account"
        and Relationship.ParentTableID = Account.ID
        and Relationship.ChildTable = "Member"
        and Relationship.Primary = true:
            
        /* IF NOT ACTIVE, SKIP FAMILY MEMBER */
        find first Member no-lock where Member.ID = Relationship.ChildTableID no-error.
        if not available Member or Member.RecordStatus <> "Active" then next primary-loop.
        
        /* INACTIVATE ANY ACCOUNT WITH AN EMAIL ADDRESS WITH @example OR A KNOWN EMAIL ADDRESS USED BY THE BAD ACTOR */
        /* NOTE: WE DO THIS BEFORE WE CHECK FOR INTERNAL TRANSACTIONS TO SPEED UP THE PROGRAM, AS WE KNOW THESE ARE INVALID ACCOUNTS */
        if Account.PrimaryEmailAddress matches "*@example*" or Account.PrimaryEmailAddress = "marcelopinedaloia9222@gmail.com" or Account.PrimaryEmailAddress = "emmayue159@gmail.com" then 
        do:
            /* LOG ALL BIRTHDAYS USED IN THESE KNOWN BAD ACTOR ACCOUNTS TO BE USED LATER */
            if Member.Birthday <> ? then 
            do:
                find first ttBirthdays no-lock where ttBirthdays.Birthday = Member.Birthday no-error no-wait.
                if not available ttBirthdays then 
                do:
                    create ttBirthdays.
                    assign 
                        ttBirthdays.Birthday = Member.Birthday.
                end.
            end.
            /* INACTIVATE THE ACCOUNT */
            run InactivateHousehold(Account.ID,Member.ID,0,"HH Inactivated - @example or marcelopinedaloia9222@gmail.com as Email Address; Potential Bad Actor").
            /* LOG ANY SETTLED CREDIT CARD TRANSACTION FOR THE INACTIVATED ACCOUNT IN CASE THEY NEED TO BE REFUNDED */
            run checkForSettled(Account.ID).
            /* IF INACTIVATED, MOVE ON TO THE NEXT ACCOUNT */
            next hh-loop.
        end.
    
        /* SKIP ANY ACCOUNT THAT HAS AN INTERNAL CREDIT CARD TRANSACTION (I.E. NOT A WEBTRAC USERNAME), AS THE BAD ACTOR WOULD NOT HAVE ACCESS TO THOSE USERNAMES */
        /* NOTE: THIS IS THE LAST CHECK THAT WILL NOT HAVE ANY FALSE POSITIVES OR NEGATIVES */
        for first CardTransactionLog no-lock where CardTransactionLog.ParentRecord = Account.ID and lookup(CardTransactionLog.UserName,WebTracUserNames) = 0:
            run LogHousehold(Account.ID,Member.ID,CardTransactionLog.ID,"HH Skipped - Internal Credit Card Purchase Found; Potential Legitimate Account").
            next hh-loop.
        end.
        
        /* INACTIVATE ANY ACCOUNT USING GIBBERISH IN THE FIRST OR LAST NAME */
        /* NOTE: THIS COULD POTENTIALLY INACTIVATE A VALID ACCOUNT, BUT I CAN'T THINK OF ANY NAME THAT MIGHT START WITH THESE RANDOM LETTERS UNLESS IT'S AN ACRONYM */
        /* AND IF A ACCOUNT THAT ISN'T CREATED BY THE BAD ACTOR USES GIBBERISH AS THEIR NAME THEY MIGHT AS WELL BE INACTIVATED ANYWAY */
        if Account.FirstName begins "asd" or Account.LastName begins "asd"
            or Account.FirstName begins "asg" or Account.LastName begins "asg" 
            or Account.FirstName begins "asf" or Account.LastName begins "asf"
            or Account.FirstName begins "sdf" or Account.LastName begins "sdf"
            or Account.FirstName begins "fdg" or Account.LastName begins "fdg" then 
        do:
            /* LOG ALL BIRTHDAYS USED IN THESE KNOWN BAD ACTOR ACCOUNTS TO BE USED LATER */
            if Member.Birthday <> ? then 
            do:
                find first ttBirthdays no-lock where ttBirthdays.Birthday = Member.Birthday no-error no-wait.
                if not available ttBirthdays then 
                do:
                    create ttBirthdays.
                    assign 
                        ttBirthdays.Birthday = Member.Birthday.
                end.
            end.
            /* INACTIVATE THE ACCOUNT */
            run InactivateHousehold(Account.ID,Member.ID,0,"HH Inactivated - Name begins with 'asd' or other gibberish; Potential Bad Actor").
            /* LOG ANY SETTLED CREDIT CARD TRANSACTION FOR THE INACTIVATED ACCOUNT IN CASE THEY NEED TO BE REFUNDED */
            run checkForSettled(Account.ID).
            /* IF INACTIVATED, MOVE ON TO THE NEXT ACCOUNT */
            next hh-loop.
        end.

        /* SKIP ANY ACCOUNT WITH ACCOUNT COORDINATES, AS THIS WOULD MEAN THAT THE ADDRESS IS VALID AND THE BAD ACTOR HAS (SO FAR) BEEN USING INVALID ADDRESSES */
        /* NOTE: THIS COULD POTENTIALLY SKIP ACCOUNTS CREATED BY THE BAD ACTOR IF THEY START TO USE LEGITIMATE ADDRESSES, BUT THE HOPE IS THAT THE ABOVE CHECKS CATCH THEM FIRST */        
        if index(Account.MiscInformation,"HouseholdCoordinates") > 0 then 
        do:
            run LogHousehold(Account.ID,0,0,"HH Skipped - Account Coordinates Found; Potential Legitimate Account").
            next hh-loop.
        end.
        
        /* INACTIVATE ACCOUNTS USING A BIRTHDAY KNOWN TO BE USED BY THE BAD ACTOR */
        /* NOTE: THIS COULD POTENTIALLY INACTIVATE VALID ACCOUNTS IF THE PERSON ACTUALLY HAS A BIRTHDAY THAT MATCHES THE LIST OF USED BIRTHDAYS */
        if Member.Birthday <> ? then 
        do:
            find first ttBirthdays no-lock where ttBirthdays.Birthday = Member.Birthday no-error no-wait.
            if available ttBirthdays then 
            do:
                run InactivateHousehold(Account.ID,Member.ID,0,"HH Inactivated - Birthday Match with Known Bad HHs; Potential Bad Actor").
                run checkForSettled(Account.ID).
                next hh-loop.
            end.
        end.

        /* SKIP ACCOUNTS WITH NO CREDIT CARD ACTIVITY */
        /* NOTE: THIS COULD POTENTIALLY SKIP VALID ACCOUNTS IF THE BAD ACTOR DIDN'T USE THE ACCOUNT TO TEST CARDS */
        /* THE HOPE IS THAT THE ABOVE CHECKS FIND ALL OF THE BAD ACTOR ACCOUNTS EVEN IF THEY AREN'T BEING USED BEFORE WE GET HERE */
        if not can-find (first CardTransactionLog no-lock where CardTransactionLog.ParentRecord = Account.ID no-wait) then 
        do:
            run LogHousehold(Account.ID,Member.ID,0,"HH Skipped - No Credit Card Transactions Found; Potential Legitimate Account").
            next hh-loop.
        end.
        
        /* FIND THE FIRST DECLINED CREDIT CARD TRANSACTION AND CHECK FOR A NAME MATCH */
        /* THE THINKING HERE IS THAT THE BAD ACTOR IS TESTING MULTIPLE CARDS AGAINST EACH ACCOUNT THEY CREATE */
        /* SO, EVEN IF THEY FIND A VALID CREDIT CARD, THE ACCOUNT WILL HAVE MULTIPLE DECLINES */
        /* BY THE TIME WE GET HERE ALL INVALID ACCOUNTS HAVE HOPEFULLY BEEN CAUGHT AND INACTIVATED, SO ANY ACCOUNT GOING THROUGH THIS LOOP ARE LIKELY VALID */
        cc-loop:
        for first CardTransactionLog no-lock where CardTransactionLog.ParentRecord = Account.ID and lookup(CardTransactionLog.UserName,WebTracUserNames) > 0 and CardTransactionLog.RecordStatus = "Declined":
    
            /* CHECK FOR A NAME MATCH ON THE CARD HOLDER NAME TO ANY FAMILY MEMBER WITHIN THE ACCOUNT */ 
            for each ttMemberName no-lock where ttMemberName.AccountID = Account.ID:
                
                /* SKIP THE ACCOUNT IF A FIRST OR LAST NAME MATCH IS FOUND ON ANY MEMBER OF THE FAMILY TO THE CARD HOLDER NAME */
                /* NOTE: THIS COULD POTENTIALLY SKIP BAD ACTOR ACCOUNTS IF THE STOLEN CARD DATA HAPPENS TO SHARE A FIRST OR LAST NAME WITH THE FAKE ACCOUNT */
                /* AS OF NOW THE BAD ACTOR HAS NOT BEEN LINING UP THE ACCOUNT NAME WITH THE CARD NAME, BUT THEY COULD START TO DO THAT IN THE FUTURE */
                /* IF THEY DO, HOPEFULLY THE ABOVE CHECKS WOULD CATCH IT BEFORE IT MAKES IT THIS FAR */
                if index(CardTransactionLog.CreditCardholder,ttMemberName.FirstName) > 0 or
                        index(CardTransactionLog.CreditCardholder,ttMemberName.LastName) > 0 then 
                do:
                    run LogHousehold(Account.ID,Member.ID,CardTransactionLog.ID,"HH Skipped - Card Holder Name Matches Account or Member Name; Potential Legitimate Account").
                    next hh-loop.
                end.
            end.
               
            /* IF THERE IS A DECLINED TRANSACTION WITH NO NAME MATCH THEN INACTIVATE THE ACCOUNT */
            /* NOTE: THIS HAS THE POTENTIAL TO INACTIVATE LEGITIMATE ACCOUNTS THAT HAPPENED TO MAKE IT PAST THE OTHER CHECKS */
            run InactivateHousehold(Account.ID,Member.ID,CardTransactionLog.ID,"HH Inactivated - Declined Transactions Found; Potential Bad Actor").
            run checkForSettled(Account.ID).
            next hh-loop.
        end.
        
        /* IF WE MAKE IT THIS FAR THEY ONLY HAVE SETTLED CC TRANSACTIONS, SO LET'S LOG THEM AS SKIPPED */
        find first CardTransactionLog no-lock where CardTransactionLog.ParentRecord = Account.ID and CardTransactionLog.RecordStatus = "Settled" no-error no-wait.
        if available CardTransactionLog then run LogHousehold(Account.ID,Member.ID,CardTransactionLog.ID,"HH Skipped - No Declined Credit Card Transactions Found; Potential Legitimate Account").
        if not available CardTransactionLog then run LogHousehold(Account.ID,Member.ID,0,"HH Skipped - No Declined Credit Card Transactions Found; Potential Legitimate Account").
    end.
end.

/* UPDATE AUDIT LOG TO SAY THE LOGFILE IS BEING CREATED */
run UpdateActivityLog({&ProgramDescription},
    "Program in Progress; Logfile is being created...",
    "Number of Households Inactivated: " + addCommas(numRecs),
    "Number of Households Skipped:" + addCommas(numHHSkipped),
    ""). 
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + string(iNumDays) + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + string(iNumDays) + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* UPDATE AUDIT LOG ENTRY WITH FINAL COUNTS */
run UpdateActivityLog(
    {&ProgramDescription} + " as of " + string(CheckDate),
    "Program is Complete; Check Document Center for a log of Records Changed",
    "Number of Households Inactivated: " + addCommas(numRecs),
    "Number of Households Skipped:" + addCommas(numHHSkipped),
    "").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/
procedure checkForSettled:
    define input parameter inpID as int64 no-undo.
    define buffer bufCardTransactionLog for CardTransactionLog.
    do for bufCardTransactionLog transaction:
        for each bufCardTransactionLog no-lock where bufCardTransactionLog.ParentRecord = inpID and bufCardTransactionLog.RecordStatus = "Settled":
            run LogHousehold(Account.ID,0,BufCreditCardHistory.ID,"Settled CC History Record for Inactivated Account; Potential Refund Required").
        end.
    end.
end procedure.

procedure LogHousehold:
    define input parameter accountID as int64 no-undo.
    define input parameter fmID as int64 no-undo.
    define input parameter ccID as int64 no-undo.
    define input parameter LogNotes as character no-undo. 
    define buffer bufAccount         for Account.
    define buffer bufMember            for Member.
    define buffer bufCardTransactionLog for CardTransactionLog.
    do for bufAccount transaction:
        find first BufAccount no-lock where BufAccount.ID = accountID no-error no-wait.
        if fmID <> 0 then find first bufMember no-lock where bufMember.ID = fmID no-error no-wait.
        if ccID <> 0 then find first bufCardTransactionLog no-lock where bufCardTransactionLog.ID = ccID no-error no-wait.
        if available BufAccount then 
        do:
            assign 
                numHHSkipped = numHHSkipped + 1.
                
            run put-stream ("~"" +
                /*Log Notes*/
                LogNotes
                + "~",~"" +
                /*Account Number*/
                getString(string(bufAccount.EntityNumber))
                + "~",~"" +
                /*Account ID*/
                getString(string(bufAccount.ID))
                + "~",~"" +
                /*FM ID*/
                (if fmID = 0 then "" else string(bufMember.ID))
                + "~",~"" +
                /*CCHistory ID*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ID)))
                + "~",~"" +
                /*Account Name*/
                trim(getString(bufAccount.FirstName) + " " + getString(bufAccount.LastName))
                + "~",~"" +
                /*FM Name*/
                (if fmID = 0 then "" else trim(getString(bufMember.FirstName) + " " + getString(bufMember.LastName)))
                + "~",~"" +
                /*Card Holder Name*/
                (if ccID = 0  then "" else getString(bufCardTransactionLog.CreditCardholder))
                + "~",~"" +
                /*Number of Family Members*/
                addCommas(numFMs)
                + "~",~"" +
                /*HH Creation Date*/
                getString(string(bufAccount.CreationDate))
                + "~",~"" +
                /*HH Creation Time*/
                getString(string(bufAccount.CreationTime))
                + "~",~"" +
                /*HH Creation User*/
                getString(bufAccount.CreationUserName)
                + "~",~"" +
                /*HH Last Active Date*/
                getString(string(bufAccount.LastActiveDate))
                + "~",~"" +
                /*HH Phone Number*/
                getString(bufAccount.PrimaryPhoneNumber)
                + "~",~"" +
                /*FM Birthday*/
                (if fmID = 0 then "" else getString(string(bufMember.Birthday)))
                + "~",~"" +
                /*HH Street*/
                getString(bufAccount.PrimaryAddress1)
                + "~",~"" +
                /*HH City*/
                getString(bufAccount.PrimaryCity)
                + "~",~"" +
                /*HH State*/
                getString(bufAccount.PrimaryState)
                + "~",~"" +
                /*HH Zip Code*/
                getString(bufAccount.PrimaryZipCode)
                + "~",~"" +
                /*HH Email Address*/
                getString(bufAccount.PrimaryEmailAddress)
                + "~",~"" +
                /*FM Email Address*/
                (if fmID = 0 then "" else getString(bufMember.PrimaryEmailAddress))
                + "~",~"" +
                /*HH MiscInformation*/
                parseList(getString(bufAccount.MiscInformation))
                + "~",~"" +
                /*HH WordIndex*/
                parseList(getString(bufAccount.WordIndex))
                + "~",~"" +
                /*CCHist Process Date*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ProcessDate)))
                + "~",~"" +
                /*CCHist Posting Time*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.PostingTime)))
                + "~",~"" +
                /*CCHist Record Status*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.RecordStatus)))
                + "~",~"" +
                /*CCHist Username*/
                (if ccID = 0 then "" else getString(bufCardTransactionLog.UserName))
                + "~",~"" +
                /*CCHist Amount*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.Amount)))
                + "~",~"" +
                /*CCHist Receipt Num*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ProcessDate)))
                + "~",~"" +
                /*CCHist Brand*/
                (if ccID = 0 then "" else getString(string(bufCardTransactionLog.CreditCardBrand)))
                + "~",").
        end.
    end.
end procedure.
        
procedure InactivateHousehold:
    define input parameter accountID as int64 no-undo.
    define input parameter fmID as int64 no-undo.
    define input parameter ccID as int64 no-undo.
    define input parameter LogNotes as character no-undo. 
    define buffer bufAccount         for Account.
    define buffer bufMember            for Member.
    define buffer bufCardTransactionLog for CardTransactionLog.
    do for bufAccount transaction:
        if fmID <> 0 then find first bufMember no-lock where bufMember.ID = fmID no-error no-wait.
        if ccID <> 0 then find first bufCardTransactionLog no-lock where bufCardTransactionLog.ID = ccID no-error no-wait.
        if LogOnly then 
        do:
            find first bufAccount no-lock where bufAccount.ID = accountID no-error.
            if available bufAccount then 
            do:
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(bufAccount.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "Account". // REPLACE <TABLE NAME> WITH THE TABLE NAME
                run UpdateActivityLog({&ProgramDescription} + " as of " + string(CheckDate),"Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),"Number of Households Inactivated So Far: " + addCommas(numRecs),"Number of Households Skipped So Far:" + addCommas(numHHSkipped),"").
            
                assign
                    numRecs = numRecs + 1.
            
                run put-stream ("~"" +
                    /*Log Notes*/
                    LogNotes
                    + "~",~"" +
                    /*Account Number*/
                    getString(string(bufAccount.EntityNumber))
                    + "~",~"" +
                    /*Account ID*/
                    getString(string(bufAccount.ID))
                    + "~",~"" +
                    /*FM ID*/
                    (if fmID = 0 then "" else string(bufMember.ID))
                    + "~",~"" +
                    /*CCHistory ID*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ID)))
                    + "~",~"" +
                    /*Account Name*/
                    trim(getString(bufAccount.FirstName) + " " + getString(bufAccount.LastName))
                    + "~",~"" +
                    /*FM Name*/
                    (if fmID = 0 then "" else trim(getString(bufMember.FirstName) + " " + getString(bufMember.LastName)))
                    + "~",~"" +
                    /*Card Holder Name*/
                    (if ccID = 0  then "" else getString(bufCardTransactionLog.CreditCardholder))
                    + "~",~"" +
                    /*Number of Family Members*/
                    addCommas(numFMs)
                    + "~",~"" +
                    /*HH Creation Date*/
                    getString(string(bufAccount.CreationDate))
                    + "~",~"" +
                    /*HH Creation Time*/
                    getString(string(bufAccount.CreationTime))
                    + "~",~"" +
                    /*HH Creation User*/
                    getString(bufAccount.CreationUserName)
                    + "~",~"" +
                    /*HH Last Active Date*/
                    getString(string(bufAccount.LastActiveDate))
                    + "~",~"" +
                    /*HH Phone Number*/
                    getString(bufAccount.PrimaryPhoneNumber)
                    + "~",~"" +
                    /*FM Birthday*/
                    (if fmID = 0 then "" else getString(string(bufMember.Birthday)))
                    + "~",~"" +
                    /*HH Street*/
                    getString(bufAccount.PrimaryAddress1)
                    + "~",~"" +
                    /*HH City*/
                    getString(bufAccount.PrimaryCity)
                    + "~",~"" +
                    /*HH State*/
                    getString(bufAccount.PrimaryState)
                    + "~",~"" +
                    /*HH Zip Code*/
                    getString(bufAccount.PrimaryZipCode)
                    + "~",~"" +
                    /*HH Email Address*/
                    getString(bufAccount.PrimaryEmailAddress)
                    + "~",~"" +
                    /*FM Email Address*/
                    (if fmID = 0 then "" else getString(bufMember.PrimaryEmailAddress))
                    + "~",~"" +
                    /*HH MiscInformation*/
                    parseList(getString(bufAccount.MiscInformation))
                    + "~",~"" +
                    /*HH WordIndex*/
                    parseList(getString(bufAccount.WordIndex))
                    + "~",~"" +
                    /*CCHist Process Date*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ProcessDate)))
                    + "~",~"" +
                    /*CCHist Posting Time*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.PostingTime)))
                    + "~",~"" +
                    /*CCHist Record Status*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.RecordStatus)))
                    + "~",~"" +
                    /*CCHist Username*/
                    (if ccID = 0 then "" else getString(bufCardTransactionLog.UserName))
                    + "~",~"" +
                    /*CCHist Amount*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.Amount)))
                    + "~",~"" +
                    /*CCHist Receipt Num*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ProcessDate)))
                    + "~",~"" +
                    /*CCHist Brand*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.CreditCardBrand)))
                    + "~",").
            end.
        end.
        else 
        do:
            find first bufAccount exclusive-lock where bufAccount.ID = accountID no-error.
            if available bufAccount then 
            do:
                /* UPDATE AUDIT LOG WITH LAST TABLE/ID AND CURRENT RECORD COUNTS */ 
                assign 
                    cLastID   = getString(string(bufAccount.ID)) // REPLACE 0 WITH TABLENAME.ID 
                    LastTable = "Account". // REPLACE <TABLE NAME> WITH THE TABLE NAME
                run UpdateActivityLog(
                    {&ProgramDescription} + " as of " + string(CheckDate),
                    "Program in Progress; Last Record ID - " + getString(lastTable) + ": " + getString(cLastID),
                    "Number of Households Inactivated So Far: " + addCommas(numRecs),
                    "Number of Households Skipped So Far:" + addCommas(numHHSkipped),
                    "").
            
                assign
                    numRecs                     = numRecs + 1
                    bufAccount.RecordStatus = "Inactive".
            
                run put-stream ("~"" +
                    /*Log Notes*/
                    LogNotes
                    + "~",~"" +
                    /*Account Number*/
                    getString(string(bufAccount.EntityNumber))
                    + "~",~"" +
                    /*Account ID*/
                    getString(string(bufAccount.ID))
                    + "~",~"" +
                    /*FM ID*/
                    (if fmID = 0 then "" else string(bufMember.ID))
                    + "~",~"" +
                    /*CCHistory ID*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ID)))
                    + "~",~"" +
                    /*Account Name*/
                    trim(getString(bufAccount.FirstName) + " " + getString(bufAccount.LastName))
                    + "~",~"" +
                    /*FM Name*/
                    (if fmID = 0 then "" else trim(getString(bufMember.FirstName) + " " + getString(bufMember.LastName)))
                    + "~",~"" +
                    /*Card Holder Name*/
                    (if ccID = 0  then "" else getString(bufCardTransactionLog.CreditCardholder))
                    + "~",~"" +
                    /*Number of Family Members*/
                    addCommas(numFMs)
                    + "~",~"" +
                    /*HH Creation Date*/
                    getString(string(bufAccount.CreationDate))
                    + "~",~"" +
                    /*HH Creation Time*/
                    getString(string(bufAccount.CreationTime))
                    + "~",~"" +
                    /*HH Creation User*/
                    getString(bufAccount.CreationUserName)
                    + "~",~"" +
                    /*HH Last Active Date*/
                    getString(string(bufAccount.LastActiveDate))
                    + "~",~"" +
                    /*HH Phone Number*/
                    getString(bufAccount.PrimaryPhoneNumber)
                    + "~",~"" +
                    /*FM Birthday*/
                    (if fmID = 0 then "" else getString(string(bufMember.Birthday)))
                    + "~",~"" +
                    /*HH Street*/
                    getString(bufAccount.PrimaryAddress1)
                    + "~",~"" +
                    /*HH City*/
                    getString(bufAccount.PrimaryCity)
                    + "~",~"" +
                    /*HH State*/
                    getString(bufAccount.PrimaryState)
                    + "~",~"" +
                    /*HH Zip Code*/
                    getString(bufAccount.PrimaryZipCode)
                    + "~",~"" +
                    /*HH Email Address*/
                    getString(bufAccount.PrimaryEmailAddress)
                    + "~",~"" +
                    /*FM Email Address*/
                    (if fmID = 0 then "" else getString(bufMember.PrimaryEmailAddress))
                    + "~",~"" +
                    /*HH MiscInformation*/
                    parseList(getString(bufAccount.MiscInformation))
                    + "~",~"" +
                    /*HH WordIndex*/
                    parseList(getString(bufAccount.WordIndex))
                    + "~",~"" +
                    /*CCHist Process Date*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ProcessDate)))
                    + "~",~"" +
                    /*CCHist Posting Time*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.PostingTime)))
                    + "~",~"" +
                    /*CCHist Record Status*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.RecordStatus)))
                    + "~",~"" +
                    /*CCHist Username*/
                    (if ccID = 0 then "" else getString(bufCardTransactionLog.UserName))
                    + "~",~"" +
                    /*CCHist Amount*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.Amount)))
                    + "~",~"" +
                    /*CCHist Receipt Num*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.ProcessDate)))
                    + "~",~"" +
                    /*CCHist Brand*/
                    (if ccID = 0 then "" else getString(string(bufCardTransactionLog.CreditCardBrand)))
                    + "~",").
            end.
        end.
    end.
end procedure.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + string(iNumDays) + "_Log" + "_" + ClientCode + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
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
            BufActivityLog.SourceProgram = {&ProgramName} + string(iNumDays) + ".r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = LogDetail1
            BufActivityLog.Detail2       = LogDetail2
            BufActivityLog.Detail3       = LogDetail3
            BufActivityLog.Detail4       = LogDetail4
            BufActivityLog.Detail5       = LogDetail5.
        /* IF THIS IS THE FIRST AUDIT LOG ENTRY, UPDATE THE ID FIELD */
        if ActivityLogID = 0 and bufActivityLog.Detail2 = "Program in Progress" then 
            assign
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

/* STUPID SUPER.I NOT INCLUDING ISNUMERIC! */
function isNumeric returns log (cText as character):
    return SuperFunctions:IsNumeric(cText).  
end function.

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
    define variable absValue     as decimal   no-undo. // ABSOLUTE VALUE
    define variable iValue       as integer   no-undo. // INTEGER VALUE
    define variable cValue       as character no-undo. // CHARACTER VALUE
    define variable ix           as integer   no-undo. 
    define variable decimalValue as character no-undo. // DECIMAL VALUE
    define variable decLoc       as integer   no-undo. // DECIMAL LOCATION
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