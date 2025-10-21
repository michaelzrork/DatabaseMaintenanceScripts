/*------------------------------------------------------------------------
    File        : deleteSAAnswers.p
    Purpose     : Delete unused Question answers

    Syntax      : 

    Description : 

    Author(s)   : 
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numAnswersDeleted   as integer no-undo.
define variable numAnswersSkipped   as integer no-undo.
define variable numQuestionsDeleted as integer no-undo.
define variable dupQuestionID       as int64   no-undo.
define variable newQuestionID       as int64   no-undo.
define variable origQuestionLinkID  as int64   no-undo.
define variable isDuplicate         as log     no-undo.

assign
    numAnswersDeleted   = 0
    numAnswersSkipped   = 0
    numQuestionsDeleted = 0
    isDuplicate         = false
    origQuestionLinkID  = 21195871
    dupQuestionID       = 4338317
    newQuestionID       = 24154043.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each QuestionResponse no-lock where QuestionResponse.QuestionLinkID = origQuestionLinkID:
    run findAndDeleteDuplicate(QuestionResponse.DetailLinkID,QuestionResponse.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure findAndDeleteDuplicate:
    define input parameter hhID as int64 no-undo.
    define input parameter origAnswerID as int64 no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    for first bufQuestionResponse exclusive-lock where bufQuestionResponse.DetailLinkID = hhID and bufQuestionResponse.QuestionLinkID = origQuestionLinkID and bufQuestionResponse.ID <> origAnswerID:
        numAnswersDeleted = numAnswersDeleted + 1.
        delete bufQuestionResponse.
    end.
    if not available bufQuestionResponse then assign numAnswersSkipped = numAnswersSkipped + 1.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "deleteSAAnswers.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Delete Duplicate Questions for Question ID " + string(origQuestionLinkID)
            BufActivityLog.Detail2       = "Number of Answers Deleted: " + string(numAnswersDeleted)
            BufActivityLog.Detail3       = "Number of Answers Skipped: " + string(numAnswersSkipped).
    end.
end procedure.