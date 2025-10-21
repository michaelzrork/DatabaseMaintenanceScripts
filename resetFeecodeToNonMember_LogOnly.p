/*------------------------------------------------------------------------
    File        : resetFeecodeToNonMember.p
    Purpose     : 

    Syntax      : 

    Description : Reset Feecode to Non-Member for Households with Renter Feature

    Author(s)   : michaelzrork
    Created     : 12/16/2024
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

define variable nonMemberFeecode     as character no-undo.
define variable memberFeecode        as character no-undo.
define variable hhStatusQuestion     as integer   no-undo.
define variable hhStatusAnswer       as character no-undo.
define variable lastReviewedQuestion as integer   no-undo.
define variable lastReviewedDate     as date      no-undo.
define variable checkLastReviewed    as date      no-undo.
define variable numRecs              as integer   no-undo.
define variable numHHFeaturesUpdated as integer   no-undo.
define variable newFeatures          as character no-undo.
define variable oldFeatures          as character no-undo.
define variable accountName               as character no-undo.
define variable oldFeecodeList       as character no-undo.
define variable addToLog             as logical   no-undo.
define variable numAnswersFixed      as integer   no-undo.
define variable newAnswer            as character no-undo.
define variable newFeecodeList       as character no-undo.

assign
    numRecs              = 0
    nonMemberFeecode     = "Non-Member"
    memberFeecode        = "RA Member"
    checkLastReviewed    = 09/01/2024 /* DATE USED TO CHECK FOR RECENT VERIFICATION */
    hhStatusQuestion     = 178522 /* Account STATUS QUESTION ID */
    lastReviewedQuestion = 3203615 /* LAST REVIEWED DATE QUESTION ID */
    numHHFeaturesUpdated = 0
    newFeatures          = ""
    oldFeatures          = ""
    accountName               = ""
    lastReviewedDate     = ?
    oldFeecodeList       = ""
    addToLog             = false
    numAnswersFixed      = 0
    newAnswer            = ""
    newFeecodeList       = "".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/
// CREATE LOG FILE FIELD HEADERS
run put-stream ("Account ID,Account Num,Account Name,Original Account Status Answer,New Account Status Answer,Last Reviewed Date,Original Features,New Features,Original Feecodes,New Feecodes,").
  
// ACCOUNT LOOPS
for each Account no-lock:    
    assign
        hhStatusAnswer   = ""
        newFeatures      = ""
        newAnswer        = ""
        newFeecodeList   = Account.CodeValue
        lastReviewedDate = ?
        oldFeeCodeList   = Account.CodeValue
        oldFeatures      = Account.Features
        addToLog         = false
        accountName           = trim(getString(Account.FirstName) + " " + getString(Account.LastName)).                     
    if accountName = "" then assign accountName = (if getString(Account.OrganizationName) = "" then "No Account Name" else getString(Account.OrganizationName)).
    
    // FIND Account STATUS ANSWER AND USE THAT TO SET NEW FEATURES
    for first QuestionResponse no-lock where QuestionResponse.DetailLinkID = Account.ID and QuestionResponse.QuestionLinkId = hhStatusQuestion:
        hhStatusAnswer = getString(QuestionResponse.Answer).
        find first LookupCode no-lock where LookupCode.RecordType = "Account Feature" and LookupCode.RecordCode = QuestionResponse.Answer no-error no-wait.
        if available LookupCode then assign newFeatures = LookupCode.RecordCode. 
        if not available LookupCode then 
        do:
            find first LookupCode no-lock where LookupCode.RecordType = "Account Feature" and LookupCode.Description = QuestionResponse.Answer no-error no-wait.
            if available LookupCode then 
            do:
                assign 
                    newFeatures = LookupCode.RecordCode
                    newAnswer   = LookupCode.RecordCode.
                run fixAnswer(QuestionResponse.ID).
            end.
            if not available LookupCode then 
            do:
                assign 
                    newFeatures = "Unknown"
                    newAnswer   = "Unknown".
                run fixAnswer(QuestionResponse.ID).
            end.
        end.
    end.
    
    // IF Account STATUS ANSWER NOT AVAILABLE, SET NEW FEATURES TO UNKNOWN
    if not available QuestionResponse then assign newFeatures = "Unknown".

    // IF CURRENT FEATURES DO NOT MATCH THE NEW FEATURES, UPDATE THE Account FEATURES
    if oldFeatures <> newFeatures then run syncFeatures(Account.ID).
    
    // FIND THE LAST REVIEWED DATE
    for first QuestionResponse no-lock where QuestionResponse.DetailLinkID = Account.ID and QuestionResponse.QuestionLinkID = lastReviewedQuestion: 
        lastReviewedDate = date(QuestionResponse.Answer).
    end.
    
    // CHECK THE FEECODE AGAINST THE NEW FEATURES AND UPDATE MEMBER OR NON-MEMBER FEECODES ACCORDINGLY
    case newFeatures:
        // SET BUSINESSES, ORGANIZATIONS, AND OWNERS TO MEMBER IF NOT SET OR THEY HAVE BOTH, OTHERWISE LEAVE AS IS 
        when "BusinessOrganization" or 
        when "Owner" then 
            if lookup(MemberFeecode,Account.CodeValue) > 0 and lookup(nonMemberFeecode,Account.CodeValue) > 0 then run changeFeeCode(Account.ID,memberFeecode,nonMemberFeecode).
            else if lookup(MemberFeecode,Account.CodeValue) = 0 and lookup(nonMemberFeecode,Account.CodeValue) = 0 then run changeFeeCode(Account.ID,memberFeecode,nonMemberFeecode).
        // SET FORMER OWNER AND UNKNOWN TO NON-MEMBER
        when "Former Owner" or 
        when "Unknown" then
            if lookup(nonMemberFeecode,Account.CodeValue) = 0 or lookup(MemberFeecode,Account.CodeValue) > 0 then run changeFeeCode(Account.ID,nonMemberFeecode,MemberFeecode).    
        // SET RENTER TO NON-MEMBER UNLESS THERE IS A RECENT REVIEWED DATE, IF THERE IS A RECENT REVIEW DATE THEN SET TO NON-MEMBER IF THEY HAVE NEITHER OR MEMBER IF THEY HAVE BOTH
        when "Renter" then 
            if lastReviewedDate = ? or lastReviewedDate < checkLastReviewed then 
            do:
                if lookup(nonMemberFeecode,Account.CodeValue) = 0 or lookup(memberFeecode,Account.CodeValue) > 0 then run changeFeeCode(Account.ID,nonMemberFeecode,MemberFeecode).
            end.
            else if lastReviewedDate ge checkLastReviewed then 
                do: 
                    if lookup(MemberFeecode,Account.CodeValue) = 0 and lookup(nonMemberFeecode,Account.CodeValue) = 0 then run changeFeeCode(Account.ID,nonMemberFeecode,MemberFeecode).
                    else if lookup(MemberFeecode,Account.CodeValue) > 0 and lookup(nonMemberFeecode,Account.CodeValue) > 0 then run changeFeeCode(Account.ID,MemberFeecode,nonMemberFeecode).
                end.
    end case.
    
    // IF ANY CHANGES WERE MADE, ADD TO THE LOGFILE
    if addToLog = true then run put-stream("~"" + 
            getString(string(Account.ID)) + "~",~"" + 
            getString(string(Account.EntityNumber)) + "~",~"" + 
            getString(accountName) + "~",~"" + 
            getString(hhStatusAnswer) + "~",~"" + 
            (if getString(newAnswer) = "" then "No Change" else getString(newAnswer)) + "~",~"" + 
            getString(string(lastReviewedDate)) + "~",~"" + 
            getString(oldFeatures) + "~",~"" + 
            (if getString(oldFeatures) = getString(newFeatures) then "No Change" else getString(newFeatures)) + "~",~"" + 
            getString(oldFeecodeList) + "~",~"" + 
            (if getString(oldFeecodeList) = getString(newFeecodeList) then "No Change" else getString(newFeecodeList))
            + "~",").
end.

// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "resetFeecodeToNonMemberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "resetFeecodeToNonMemberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.


run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIX ANSWER
procedure fixAnswer:
    define input parameter inpID as int64 no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    do for bufQuestionResponse transaction:
        find first bufQuestionResponse exclusive-lock where bufQuestionResponse.ID = inpID no-error no-wait.
        if available bufQuestionResponse then assign
                // bufQuestionResponse.Answer = newAnswer
                numAnswersFixed = numAnswersFixed + 1
                addToLog        = true.
    end.
end procedure.


// SYNCS Account FEATURES WITH THE Account STATUS QUESTION ANSWER
procedure syncFeatures:
    define input parameter inpid as int64 no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then 
        do:
            assign
                numHHFeaturesUpdated = numHHFeaturesUpdated + 1
                // bufAccount.Features = newFeatures
                addToLog             = true.
        end.
    end.
end procedure. /* SYNC FEATURES */


// REPLACES OLD FEECODE WITH NEW FEECODE
procedure changeFeeCode:
    define input parameter inpid as int64 no-undo.
    define input parameter addFeecode as character no-undo.
    define input parameter removeFeecode as character no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.id = inpid no-error no-wait.
        if available bufAccount then 
        do:
            assign
                numRecs        = numRecs + 1
                addToLog       = true
                newFeecodeList = bufAccount.CodeValue.
            if lookup(removeFeecode,newFeecodeList) > 0 then newFeecodeList = removeList(removeFeecode,newFeecodeList).
            if lookup(addFeecode,newFeecodeList) = 0 then newFeecodeList = list(addFeecode,newFeecodeList).
            // assign 
                // bufAccount.CodeValue = newFeecodeList.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "resetFeecodeToNonMemberLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
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
            BufActivityLog.SourceProgram = "resetFeecodeToNonMember.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Reset Feecode to Non-Member for Households with Renter Feature"
            BufActivityLog.Detail2       = "Check Document Center for resetFeecodeToNonMemberLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Account Features to Update: " + string(numHHFeaturesUpdated)
            bufActivityLog.Detail4       = "Number of Account Feecodes to Update: " + string(numRecs)
            bufActivityLog.Detail5       = "Number of Account Answers to Update: " + string(numAnswersFixed).
    end.
end procedure.