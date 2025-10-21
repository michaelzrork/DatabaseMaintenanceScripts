/*------------------------------------------------------------------------
    File        : printStatusUpdate.p
    Purpose     : Update status of receipts that did not properly print from bulk print

    Syntax      : 

    Description : 

    Author(s)   : michaelzr
    Created     : 11/21/2024
    Notes       :
  ----------------------------------------------------------------------*/
{Includes/Framework.i}
{Includes/BusinessLogic.i}

define variable updatePrintStatus as character no-undo.
define variable newStatus         as character no-undo.
define variable numRecords        as integer   no-undo.
define variable billDate          as character no-undo.

assign
    numRecords = 0
    newStatus  = ""
    billDate   = "01/15/2025".

for each PaymentReceipt no-lock where PaymentReceipt.WordIndex contains "Installment Billing Bill Date: " + billDate + " (Printed)" and PaymentReceipt.WordIndex contains "Declined CC":
    newStatus = replace(PaymentReceipt.WordIndex,billDate + " (Printed)",billDate + " (Ready to Print)").
    run updatePrintStatus(PaymentReceipt.id).
end.
    
run ActivityLog.   
    
procedure updatePrintStatus:
    def input parameter inpid as int64.
    def buffer bufPaymentReceipt for PaymentReceipt.
    
    do for bufPaymentReceipt transaction:
        find bufPaymentReceipt exclusive-lock where bufPaymentReceipt.id = inpid no-error no-wait.
        
        if available bufPaymentReceipt then 
        do:
            bufPaymentReceipt.WordIndex = newStatus.
            numRecords = numRecords + 1.
        end.
    end. /* DO FOR */
end procedure.

procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "updatePrintStatus_" + replace(billDate,"/","-") + ".r"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Update Print Status for Declined CC Installment Bill receipts with bill date: " + billDate
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end. /* DO FOR */
end procedure.