/*------------------------------------------------------------------------
    File        : fixLottoSpinEnrollments.p
    Purpose     : Fix TransactionDetail records with cartstatus of Update

    Syntax      : 

    Description : 

    Author(s)   : michaelzr
    Created     : 12/20/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/BusinessLogic.i}

define variable numRecs as integer no-undo.
numRecs = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each TransactionDetail no-lock where (recordstatus = "Enrolled" or recordstatus = "Waitlist") and PTFRPreviousStatus matches "*StatusChangeTracking=Lottery:*:01/09/2024*" and cartstatus = "Update":
    run fixCartStatus(TransactionDetail.ID).
end.

define buffer bufProgramSchedule for ProgramSchedule.
do for BufScheduledProgram transaction:
    create BufScheduledProgram.
    assign
        BufScheduledProgram.ScheduleName        = "Enrollment Recalculation" + chr(9) + guid(generate-uuid)
        BufScheduledProgram.InterfaceType       = InterfaceType()
        BufScheduledProgram.ScheduleInformation = ""
        BufScheduledProgram.RunParameters1      = "EnrollmentRecalculation_Module" + chr(31) + "AR" + 
            chr(30) + "EnrollmentRecalculation_ARBeginCombokey" +  chr(31) +  
            chr(30) + "EnrollmentRecalculation_AREndCombokey" +  chr(31)  
        BufScheduledProgram.RunParameters2      = ""
        BufScheduledProgram.RunParameters3      = ""
        BufScheduledProgram.ProgramToRun        = "business/EnrollmentRecalculation.p" 
        BufScheduledProgram.ProgramToRunType    = "Processing"
        BufScheduledProgram.recordstatus        = "Active"
        BufScheduledProgram.RunAs               = "SYSTEM"
        BufScheduledProgram.RunNow              = yes
        BufScheduledProgram.runonce             = yes. 
end.  /*** THIS IS A SCHEDULE RECORD THAT IS RUN ONCE AS SOON AS THE SCHEDULER KICKS OFF AGAIN ***/

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// FIX CART STATUS
procedure fixCartStatus:
    define input parameter inpID as int64 no-undo.
    define buffer bufTransactionDetail for TransactionDetail.
    do for bufTransactionDetail transaction:
        find bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpID no-error no-wait.
        if available bufTransactionDetail then
            assign
                numRecs                = numRecs + 1
                bufTransactionDetail.CartStatus = "Complete".
    end.
end.


// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY SADETAIL RECORDS WERE CHANGED
procedure ActivityLog:
    define buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "fixLottoSpinEnrollments.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Update any lottery spin records with cartstatus of Update to Complete"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs).
    end.
end procedure.