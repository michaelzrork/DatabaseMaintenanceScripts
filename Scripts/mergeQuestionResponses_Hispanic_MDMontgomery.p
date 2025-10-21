/*------------------------------------------------------------------------
    File        : mergeSAAnswers.p
    Purpose     : 

    Syntax      : 

    Description : Merege duplicate questions into a single question and delete duplicate answers

    Author(s)   : michaelzrork
    Created     : 05/01/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numDupAnswersDeleted  as integer no-undo.
define variable numNoHHAnswersDeleted as integer no-undo.
define variable numAnswersUpdated     as integer no-undo.
define variable numQuestionsDeleted   as integer no-undo.
define variable dupQuestionID         as int64   no-undo.
define variable newQuestionID         as int64   no-undo.
define variable origQuestionLinkID    as int64   no-undo.
define variable isDuplicate           as log     no-undo.

assign
    numDupAnswersDeleted  = 0
    numNoHHAnswersDeleted = 0
    numAnswersUpdated     = 0
    numQuestionsDeleted   = 0
    isDuplicate           = false
    origQuestionLinkID    = 21197320 // CLONE ID
    dupQuestionID         = 4338312
    newQuestionID         = 24154506.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each QuestionResponse no-lock where QuestionResponse.QuestionLinkID = origQuestionLinkID and index(QuestionResponse.WordIndex,string(dupQuestionID)) > 0:
    assign 
        isDuplicate = false.
    run checkForDuplicateAnswer(QuestionResponse.DetailLinkID,QuestionResponse.ID).
    if not isDuplicate then run updateAnswer(QuestionResponse.ID).
end.

find first QuestionDefinition no-lock where QuestionDefinition.ID = dupQuestionID no-error no-wait.
if available QuestionDefinition then run deleteQuestion(QuestionDefinition.ID).

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure checkForDuplicateAnswer:
    define input parameter hhID as int64 no-undo.
    define input parameter origAnswerID as int64 no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    for first bufQuestionResponse no-lock where bufQuestionResponse.DetailLinkID = hhID and bufQuestionResponse.QuestionLinkID = origQuestionLinkID and index(bufQuestionResponse.WordIndex,string(newQuestionID)) > 0:
        assign 
            isDuplicate = true.
        run deleteAnswer(origAnswerID,"Duplicate").
    end.   
end procedure.

procedure updateAnswer:
    define input parameter inpID as int64 no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    do for bufQuestionResponse transaction:
        find first bufQuestionResponse exclusive-lock where bufQuestionResponse.ID = inpID no-error no-wait.
        if available bufQuestionResponse then 
        do:
            // CHECK FOR HOUSEHOLD
            // find first Account no-lock where Account.ID = bufQuestionResponse.DetailLinkID no-wait no-error.
            //if not available Account then run deleteAnswer(bufQuestionResponse.ID,"No Household").
            // else
            assign
                numAnswersUpdated     = numAnswersUpdated + 1
                bufQuestionResponse.WordIndex = replace(bufQuestionResponse.WordIndex,string(dupQuestionID),string(newQuestionID)).
        end.
    end.
end procedure.

procedure deleteAnswer:
    define input parameter inpID as int64 no-undo.
    define input parameter reason as character no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    do for bufQuestionResponse transaction:
        find first bufQuestionResponse exclusive-lock where bufQuestionResponse.ID = inpID no-error no-wait.
        if available bufQuestionResponse then 
        do:
            if reason = "Duplicate" then numDupAnswersDeleted = numDupAnswersDeleted + 1.
            else if reason = "No Household" then numNoHHAnswersDeleted = numNoHHAnswersDeleted + 1.
            delete bufQuestionResponse.
        end.
    end.
end procedure.

procedure deleteQuestion:
    define input parameter inpID as int64 no-undo.
    define buffer bufQuestionDefinition for QuestionDefinition.
    do for bufQuestionDefinition transaction:
        find first bufQuestionDefinition exclusive-lock where bufQuestionDefinition.ID = inpID no-error no-wait.
        if available bufQuestionDefinition then 
        do:
            numQuestionsDeleted = numQuestionsDeleted + 1.
            delete bufQuestionDefinition.
        end.
    end.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "mergeSAAnswers.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Merge and Delete Duplicate Question Answers for Question ID " + string(origQuestionLinkID) + " (Merged " + string(dupQuestionID) + " into " + string(newQuestionID) + ")"
            BufActivityLog.Detail2       = "Number of Duplicate Answers Deleted: " + string(numDupAnswersDeleted)
            BufActivityLog.Detail3       = "Number of No Household Answers Deleted: " + string(numNoHHAnswersDeleted)
            BufActivityLog.Detail4       = "Number of Answers Merged: " + string(numAnswersUpdated)
            BufActivityLog.Detail5       = "Number of Questions Deleted: " + string(numQuestionsDeleted).
    end.
end procedure.