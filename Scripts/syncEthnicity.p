/*------------------------------------------------------------------------
    File        : syncEthnicity.p
    Purpose     : 

    Syntax      : 

    Description : Sync Ethnicity Field with Question Answer

    Author(s)   : 
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i} 

define variable numRecs         as integer   no-undo.
define variable questionID      as int64     no-undo.
define variable ethnicityAnswer as character no-undo.
define variable deleted9Zdec    as integer   no-undo.
assign
    numRecs      = 0
    deleted9Zdec = 0
    questionid   = 11118104.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each Member no-lock where Member.Ethnicity = "" or Member.Ethnicity = "9-Zdec":
    if Member.Ethnicity = "9-Zdec" then run delete9Zdec(Member.ID). 
    ethnicityAnswer = "".
    // FIND THE FAMILY MEMBER ANSWER TO THE QUESTION
    for first QuestionResponse no-lock where QuestionResponse.DetailLinkID = Member.ID and QuestionResponse.QuestionLinkID = questionID:
        ethnicityAnswer = if QuestionResponse.Answer begins "Afri" then "AFRAM"
        else if QuestionResponse.Answer begins "Ameri" then "AMIND"
        else if SAANswer.Answer begins "Asian" then "ASIAN"
        else if QuestionResponse.Answer begins "East" then "AFRE"
        else if QuestionResponse.Answer begins "Hisp" then "LATINX"
        else if QuestionResponse.Answer begins "Nativ" then "ISLAND"
        else if QuestionResponse.Answer begins "West" then "AFRW"
        else if QuestionResponse.Answer begins "White" then "WHITE"
        else if QuestionResponse.Answer begins "Other" then "OTHER"
        else "NOANS". 
        run updateEthnicity(Member.ID).
    end.
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure updateEthnicity:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then 
        do:
            assign
                numRecs               = numRecs + 1
                bufMember.Ethnicity = ethnicityAnswer.
        end.
    end.
end.

procedure delete9Zdec:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then 
        do:
            assign
                deleted9Zdec          = deleted9Zdec + 1
                bufMember.Ethnicity = "".
        end.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "syncEthnicity.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sync Ethnicity Field with Question Answer"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs)
            BufActivityLog.Detail3       = "Number of 9-Zdec records removed: " + string(deleted9Zdec).
    end.
end procedure.