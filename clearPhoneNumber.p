/*------------------------------------------------------------------------
    File        : clearSAPhone.p
    Purpose     : 

    Syntax      : 

    Description : Clear PhoneNumber Primary Records

    Author(s)   : michaelzrork
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable numRecs as integer no-undo.

assign
    numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each PhoneNumber no-lock where PhoneNumber.PrimaryPhoneNumber = yes and PhoneNumber.ParentTable = "Member":
    run deleteSAPhone(PhoneNumber.ID).
end.

for each Member no-lock where Member.PrimaryPhoneNumber <> "":
    run removePhone(Member.ID).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure deleteSAPhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufPhoneNumber for PhoneNumber.
    do for bufPhoneNumber transaction:
        find first bufPhoneNumber exclusive-lock where bufPhoneNumber.ID = inpID no-error no-wait.
        if available bufPhoneNumber then 
        do:
            numRecs = numRecs + 1.
            delete bufPhoneNumber.
        end.
    end.
end.

procedure removePhone:
    define input parameter inpID as int64 no-undo.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find first bufMember exclusive-lock where bufMember.ID = inpID no-error no-wait.
        if available bufMember then
            assign 
                bufMember.PrimaryPhoneNumber    = ""
                bufMember.PrimaryPhoneType      = ""
                bufMember.PrimaryPhoneExtension = "".
    end.
end.
            

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "clearSAPhone.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Clear PhoneNumber Primary Records"
            bufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.