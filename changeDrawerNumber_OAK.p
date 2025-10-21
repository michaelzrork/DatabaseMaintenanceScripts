/*------------------------------------------------------------------------
    File        : ChangeDrawerNumber.p
    Purpose     : 

    Syntax      : 

    Description : Change Web Refunds to Drawer 201 and Parks 2 Retail to drawer 301

    Author(s)   : michaelzrork
    Created     : 2/7/25
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable newDrawer    as integer no-undo.
define variable SAReceiptNum as integer no-undo.

assign
    newDrawer    = 0
    SAReceiptNum = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each CardTransactionLog no-lock where CardTransactionLog.CashDrawer ge 400 and CardTransactionLog.CashDrawer <> 9999:
    assign 
        newDrawer = 0.
    case CardTransactionLog.DeviceCodeLink:
        when "Oakland County Parks 1 Web" then
            do:
                assign 
                    newDrawer = 201.
                run updateDrawers(CardTransactionLog.ReceiptNumber).
            end.
        when "Oakland County Parks 2 Retail" then 
            do:
                assign 
                    newDrawer = 401.
                run updateDrawers(CardTransactionLog.ReceiptNumber).
            end.
    end case.
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// RUN EACH TABLE WITH THE PROVIDED ReceiptNumber AND DRAWER
procedure updateDrawers:
    define input parameter receiptMatch as integer no-undo.
    
    for first PaymentReceipt no-lock where PaymentReceipt.ReceiptNumber = receiptMatch:
        if PaymentReceipt.DrawerNumber <> newDrawer then 
        do:
            create ActivityLog.
            assign
                SAActivityLog.UserName      = "SYSTEM"
                SAActivityLog.LogDate       = today
                ActivityLog.Logtime       = time  
                SAActivityLog.SourceProgram = "ChangeDrawerNumber.r"
                ActivityLog.Detail1       = "Receipt Number: " + string(receiptMatch)
                ActivityLog.Detail2       = "Drawer Change: " + string(PaymentReceipt.DrawerNumber) + " ==> " + string(newDrawer).
            run fixSAReceiptDrawer(PaymentReceipt.ID).
        end.
    end.
    
    if not available PaymentReceipt then 
    do:
        if locked PaymentReceipt then 
        do:
            create ActivityLog.
            assign
                SAActivityLog.UserName      = "SYSTEM"
                SAActivityLog.LogDate       = today
                ActivityLog.Logtime       = time  
                SAActivityLog.SourceProgram = "ChangeDrawerNumber.r"
                ActivityLog.Detail1       = "Receipt number " + string(receiptMatch) + " is in use. Receipt skipped.".
        end.
                 
        else 
        do:
            create ActivityLog.
            assign
                SAActivityLog.UserName      = "SYSTEM"
                SAActivityLog.LogDate       = today
                ActivityLog.Logtime       = time  
                SAActivityLog.SourceProgram = "ChangeDrawerNumber.r"
                ActivityLog.Detail1       = "Receipt number " + string(receiptMatch) + " could not be found. Receipt skipped.".
        end.
            
        return.
    end.
    
    for each LedgerEntry no-lock where LedgerEntry.ReceiptNumber = receiptMatch:
        if LedgerEntry.CashDrawer <> newDrawer then run fixSAGLDistributionDrawer(LedgerEntry.ID).
    end.

    for each PaymentTransaction no-lock where PaymentTransaction.ReceiptNumber = receiptMatch:
        if PaymentTransaction.CashDrawer <> newDrawer then run fixSAReceiptPaymentDrawer(PaymentTransaction.ID).
    end.

    for each AccountBalanceLog no-lock where AccountBalanceLog.ReceiptNumber = receiptMatch:
        if AccountBalanceLog.CashDrawer <> newDrawer then run fixSAControlAccountHistoryDrawer(AccountBalanceLog.ID).
    end.

    for each ChargeHistory no-lock where ChargeHistory.ReceiptNumber = receiptMatch:
        if ChargeHistory.CashDrawer <> newDrawer then run fixSAFeeHistoryDrawer(ChargeHistory.ID).
    end.

    for each PaymentLog no-lock where PaymentLog.ReceiptNumber = receiptMatch:
        if PaymentLog.DrawerNumber <> newDrawer then run fixSAPaymentHistoryDrawer(PaymentLog.ID).
    end.
    
    for each CardTransactionLog no-lock where CardTransactionLog.ReceiptNumber = receiptMatch:
        if CardTransactionLog.CashDrawer <> newDrawer then run fixSACreditCardHistoryDrawer(CardTransactionLog.ID).
    end.    

end procedure.


// FIX LedgerEntry DRAWER NUMBER
procedure fixSAGLDistributionDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufLedgerEntry for LedgerEntry. 
    do for bufLedgerEntry transaction:
        find first bufLedgerEntry exclusive-lock where bufLedgerEntry.ID = inpID no-error no-wait.
        if available bufLedgerEntry then assign
                bufLedgerEntry.CashDrawer = newDrawer.
    end.
end.

// FIX PaymentReceipt DRAWER NUMBER
procedure fixSAReceiptDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufPaymentReceipt for PaymentReceipt. 
    do for bufPaymentReceipt transaction:
        find first bufPaymentReceipt exclusive-lock where bufPaymentReceipt.ID = inpID no-error no-wait.
        if available bufPaymentReceipt then assign
                SAReceiptNum              = SAReceiptNum + 1
                bufPaymentReceipt.DrawerNumber = newDrawer.
    end.
end.

// FIX PaymentTransaction DRAWER NUMBER
procedure fixSAReceiptPaymentDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufPaymentTransaction for PaymentTransaction.
    do for bufPaymentTransaction transaction:
        find first bufPaymentTransaction exclusive-lock where bufPaymentTransaction.ID = inpID no-error no-wait.
        if available bufPaymentTransaction then assign
                bufPaymentTransaction.CashDrawer = newDrawer.
    end.
end.

// FIX AccountBalanceLog DRAWER NUMBER
procedure fixSAControlAccountHistoryDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufAccountBalanceLog for AccountBalanceLog.
    do for bufAccountBalanceLog transaction:
        find first bufAccountBalanceLog exclusive-lock where bufAccountBalanceLog.ID = inpID no-error no-wait.
        if available bufAccountBalanceLog then assign
                bufAccountBalanceLog.CashDrawer = newDrawer.
    end.
end.

// FIX ChargeHistory DRAWER NUMBER
procedure fixSAFeeHistoryDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then assign
                bufChargeHistory.CashDrawer = newDrawer.
    end.
end.


// FIX CardTransactionLog DRAWER NUMBER
procedure fixSACreditCardHistoryDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufCardTransactionLog for CardTransactionLog.
    do for bufCardTransactionLog transaction:
        find first bufCardTransactionLog exclusive-lock where bufCardTransactionLog.ID = inpID no-error no-wait.
        if available bufCardTransactionLog then assign
                bufCardTransactionLog.CashDrawer = newDrawer.
    end.
end.

// FIX PaymentLog DRAWER NUMBER
procedure fixSAPaymentHistoryDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufPaymentLog for PaymentLog.
    do for bufPaymentLog transaction:
        find first bufPaymentLog exclusive-lock where bufPaymentLog.ID = inpID no-error no-wait.
        if available bufPaymentLog then assign
                bufPaymentLog.DrawerNumber = newDrawer.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "ChangeDrawerNumber.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Change drawer number program complete"
            BufActivityLog.Detail2       = "Number of Receipts updated: " + string(SAReceiptNum).
    end.
end procedure.