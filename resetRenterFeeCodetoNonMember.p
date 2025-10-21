/****************************************************************************************
                                                                                      
    DESCRIPTION:                                                                    
    Changes the FeeCode to Non-Member if the HH Feature is set to Renter and
    the Last Reviewed Date is before the begining of the year             
                                                                                      
    DATE CREATED: 03/14/2023                                                         
    LAST UPDATED: 03/15/2023                                                                  
                                                                                      
    NOTES:
    - Not currently set up to sync FM Fee Codes                                                                                          
                                                                                      
****************************************************************************************/

/**************************************
             VARIABLES
**************************************/

define variable newFeeCode as character no-undo.
define variable feecodetoReplace as character no-undo.
define variable hhFeatureReset as character no-undo.
define variable hhStatusQuestion as integer no-undo.
define variable hhStatusAnswer as character no-undo.
define variable lastReviewedQuestion as integer no-undo.
define variable lastReviewedDate as date no-undo.
define variable checkLastReviewed as date no-undo.
define variable numRecords as integer no-undo.
define variable numHHFeaturesUpdated as integer no-undo.


/**************************************
          INITIALIZATIONS
**************************************/

newFeeCode = "Non-Member".
feecodetoReplace = "RA Member". 
hhFeatureReset = "Renter". /* HH FEATURE USED TO RESET FEE CODE */
checkLastReviewed = 01/01/2024. /* DATE USED TO CHECK FOR RECENT VERIFICATION */
hhStatusQuestion = 178522. /* HH STATUS QUESTION ID */
lastReviewedQuestion = 3203615. /* LAST REVIEWED DATE QUESTION ID */
numRecords = 0.
numHHFeaturesUpdated = 0.


/**************************************
              PROGRAM
**************************************/

for each Account no-lock:
    
    /* RESET HH STATUS ANSWER BETWEEN EACH HH */
    hhStatusAnswer = "".
    
    /* FIND HH ANSWER TO HH STATUS QUESTION */
    for first QuestionResponse no-lock where QuestionResponse.DetailLinkID = Account.ID and QuestionResponse.QuestionLinkId = hhStatusQuestion:
        hhStatusAnswer = QuestionResponse.Answer.
    end. /* FIND HH ANSWER */
    
    /* MATCH HH FEATURES TO HH STATUS QUESTION */
    if hhStatusAnswer <> Account.Features then do:
        run syncFeatures(Account.ID).
    end. /* MATCH HH FEATURE */
    
    /* FIND LAST REVIEWED DATE */
    for first QuestionResponse no-lock where QuestionResponse.DetailLinkID = Account.ID and QuestionResponse.QuestionLinkID = lastReviewedQuestion: 
        lastReviewedDate = date(QuestionResponse.Answer).
    end. /* FIND LAST REVIEWED DATE */
    
    /* FIND RENTERS WITHOUT RECENT VERIFICATION AND REMOVE MEMBER FEE CODE */
    if hhStatusAnswer = hhFeatureReset and lastReviewedDate < checkLastReviewed and (lookup(newFeeCode,Account.CodeValue) = 0 or lookup(feecodetoReplace,Account.CodeValue) > 0) then do:
        run changeFeeCode(Account.ID).
    end. /* REMOVE MEMBER FEE CODE */

end.
 
run ActivityLog.


/**************************************
             PROCEDURES
**************************************/

procedure syncFeatures: /* SYNCS HH FEATURES WITH THE HH STATUS QUESTION ANSWER */
    define input parameter inpid as int64.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then assign
            numHHFeaturesUpdated = numHHFeaturesUpdated + 1
            bufAccount.Features = hhStatusAnswer.   
    end.
end procedure. /* SYNC FEATURES */

procedure changeFeeCode: /* REPLACES OLD FEECODE WITH NEW FEECODE */
    define input parameter inpid as int64.
    define variable countVar    as int       no-undo.
    define variable oldFeeCodes as character no-undo.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.id = inpid no-error no-wait.
        if available bufAccount then assign
                numRecords              = numRecords + 1
                oldFeeCodes             = bufAccount.CodeValue
                bufAccount.CodeValue  = newFeeCode.
        /* IF THE FEECODE FROM THE LIST IS NOT THE ONE WE'RE REPLACING AND NOT THE NEW ONE WE JUST ADDED, ADD IT TO THE LIST */
        count-loop:
        do countVar = 1 to num-entries(oldFeeCodes):
            if entry(countVar,oldFeeCodes) = feecodetoReplace or entry(countVar,OldFeeCodes) = newFeeCode then next count-loop.
            assign 
                bufAccount.CodeValue = bufAccount.CodeValue + "," + entry(countVar,oldFeeCodes).
        end.
    end.
end procedure. /* CHANGE FEE CODE */
              

procedure ActivityLog: /* CREATES AUDIT LOG ENTRY OF NUM RECORDS CHANGED */
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "resetRenterFeeCodetoNonMember"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Reset Renters to Non-Members"
            BufActivityLog.Detail2       = "Num HH Features Synced to HH Status: " + string(numHHFeaturesUpdated) + "; Num Renter HH Reset to NonMem: " + string(numRecords).
    end.
  
end procedure.
     