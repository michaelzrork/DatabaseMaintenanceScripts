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

define variable numAnswers   as integer no-undo.
define variable numQuestions as integer no-undo.
define variable questionID   as int64   no-undo.
assign
    numAnswers   = 0
    numQuestions = 0
    questionID   = 497496.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each QuestionResponse no-lock where QuestionResponse.QuestionLinkID = questionID:
    run deleteAnswer(QuestionResponse.ID).
end.

for each QuestionDefinition no-lock where QuestionDefinition.CloneID = questionID or QuestionDefinition.ID = questionID:
    run deleteQuestion(QuestionDefinition.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteAnswer:
    define input parameter inpID as int64 no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    do for bufQuestionResponse transaction:
        find first bufQuestionResponse exclusive-lock where bufQuestionResponse.ID = inpID no-error no-wait.
        if available bufQuestionResponse then 
        do:
            numAnswers = numAnswers + 1.
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
            numQuestions = numQuestions + 1.
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
            BufActivityLog.SourceProgram = "deleteSAAnswers.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Delete Question Answers and Questions"
            BufActivityLog.Detail2       = "Number of Answers Deleted: " + string(numAnswers)
            BufActivityLog.Detail3       = "Number of Questions Deleted: " + string(numQuestions).
    end.
end procedure.