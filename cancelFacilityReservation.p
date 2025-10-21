/*------------------------------------------------------------------------
    File        : cancelFacilityReservations.p
    Purpose     : 

    Syntax      : 

    Description : Cancel Activity Section Facility Reservations

    Author(s)   : michaelzrork
    Created     : 8/5/24
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}

define variable frResNum     as integer   no-undo.
define variable arsectionID  as int64     no-undo.
define variable detailIDList as character no-undo.
define variable ix           as integer   no-undo.

assign
    frResNum     = 222889
    arsectionID  = 246715309
    detailIDList = "246715518,246715520,246715536,246715537,246715538,246715556,246715557,246715558,246715572,246715573,246715574,246715592,246715593,246715594,246715610,246715611,246715614,246715636,246715637,246715638,246715652,246715653,246715654".
/*    frResNum    = 146    */
/*    arsectionID = 925355.*/
/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

RESERVATION-LOOP:
do ix = 1 to num-entries(detailIDlist):
    run _PurgeTransactionDetail(entry(ix,detailIDList)).
end.
    
/*    for each TransactionDetail no-lock where                    */
/*        TransactionDetail.ReservationNumber = frResNum and      */
/*        TransactionDetail.Module = "FR" and                     */
/*        TransactionDetail.ReservationType <> "Facility Tree" and*/
/*        TransactionDetail.CartStatus = "Complete":              */
/*                                                       */
/*        run _PurgeTransactionDetail(TransactionDetail.ID).               */
/*    end.                                               */

run _UpdateReservationNumber(arsectionID, 0).

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure _UpdateReservationNumber:
    def input param inpID as int64 no-undo.
    def input param ResNum as int no-undo.
    define buffer bufARSection for ARSection.
    
    do for bufARSection transaction:
        find first bufARSection exclusive-lock where bufARSection.ID = inpID no-wait no-error.
        if available bufARSection then bufARSection.ReservationNumber = ResNum.
    end.
end procedure.  /* END _UPDATERESERVATIONNUMBER */

procedure _PurgeTransactionDetail:
    def input param TransactionDetailID as int64 no-undo.
    
  
    def var ix           as int  no-undo.
    def var DependentIDs as char no-undo.

    def buffer buf-TransactionDetail for TransactionDetail.
    do for buf-TransactionDetail transaction:


        find first buf-TransactionDetail exclusive-lock where buf-TransactionDetail.ID = TransactionDetailID no-error no-wait.
        if not available buf-TransactionDetail or locked buf-TransactionDetail then return.


/*        if buf-TransactionDetail.DependentIDs ne "" then                                                      */
/*        do:                                                                                          */
/*            DependentIDs = TrueVal(NameVal("FacilityTree", buf-TransactionDetail.DependentIDs, "=", chr(30))).*/
/*            do ix = 1 to num-entries(DependentIDs):                                                  */
/*                run _PurgeTransactionDetail(int64(entry(ix,DependentIDs))) no-error.                          */
/*            end.                                                                                     */
/*        end.                                                                                         */

        run PurgeTransactionDetail(buf-TransactionDetail.ID).

        delete buf-TransactionDetail.
    end.  
end procedure.  /* END _PurgeTransactionDetail */

procedure PurgeTransactionDetail:
    def input parameter inpid as int64 no-undo.
  
    run purgeSAAnswer(inpid).
    for each Charge no-lock where Charge.ParentRecord = inpid:
        for each SAFEEHISTORY no-lock where SAFEEHISTORY.ParentRecord = SAFEE.ID:
            run deleteSAFeeHistory (ChargeHistory.id).
        end.
        for each FilterCriteria no-lock where FilterCriteria.ParentRecord = Charge.ID:
            run Business/DeleteSACriteria.p (FilterCriteria.id).
        end.
        run deleteSAFee (Charge.id).
    end.
    for each ScheduleConflict no-lock where ScheduleConflict.TransactionDetailID = inpid:
        run deleteSAConflict (ScheduleConflict.id).
    end.
    for each InvoiceLineItem no-lock where InvoiceLineItem.DetailLinkID = inpid:
        run deleteSABillingDetail(InvoiceLineItem.ID).
    end.
    
end procedure.

procedure purgeSAAnswer:
    def input parameter inpid as int64 no-undo. 
    for each QuestionResponse no-lock where QuestionResponse.DetailLinkID = inpid: 
        run deleteAnswer (QuestionResponse.id).   
    end.    
end procedure.

procedure deleteAnswer:
    define input parameter inpid as int64 no-undo.
    define buffer bufQuestionResponse for QuestionResponse.
    do for bufQuestionResponse transaction:
        find first bufQuestionResponse exclusive-lock where bufQuestionResponse.ID = inpid no-error no-wait.
        if available bufQuestionResponse then delete bufQuestionResponse.
    end.
end. 

procedure deleteSAFeeHistory:
    def input parameter inpid as int64 no-undo.
    def buffer buf1 for ChargeHistory.
    do for buf1 transaction:
        find first buf1 exclusive-lock where buf1.id = inpid no-error no-wait.
        if available buf1 then delete buf1.
    end.
end procedure.

procedure DeleteSAFee:
    def input parameter inpid as int64 no-undo.
    def buffer buf1 for safee .
    do for buf1 transaction:
        find first buf1 exclusive-lock where buf1.id = inpid no-error no-wait.
        if available buf1 then delete buf1.
    end.
end procedure.

procedure deleteSAConflict:
    def input parameter inpid as int64 no-undo.
    def buffer buf1 for ScheduleConflict.
    do for buf1 transaction:
        find first buf1 exclusive-lock where buf1.id = inpid no-error no-wait.
        if available buf1 then delete buf1.
    end.
end procedure.

procedure deleteSABillingDetail:
    def input parameter inpid as int64 no-undo.
    def buffer buf1 for InvoiceLineItem.
    do for buf1 transaction:
        find first buf1 exclusive-lock where buf1.id = inpid no-error no-wait.
        if available buf1 then delete buf1.
    end.
end procedure.


// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "cancelFacilityReservations.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Cancel Activity Section Facility Reservations".
    end.
end procedure.