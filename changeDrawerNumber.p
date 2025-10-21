/*------------------------------------------------------------------------
    File        : ChangeDrawerNumber.p
    Purpose     : 

    Syntax      : 

    Description : Change drawer number for WWW and ZZZ transactions

    Author(s)   : michaelzrork
    Created     : 03/20/2024
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable newDrawer                  as integer no-undo.
define variable SAGLDistributionNum        as integer no-undo.
define variable SAReceiptNum               as integer no-undo.
define variable SAReceiptPaymentNum        as integer no-undo.
define variable SAControlAccountHistoryNum as integer no-undo.
define variable SAFeeHistoryNum            as integer no-undo.
define variable SAGiftCertificateDetailNum as integer no-undo.
define variable SAMiscIncomeNum            as integer no-undo.
define variable SAPaymentHistoryNum        as integer no-undo.
define variable SACouponHistoryNum         as integer no-undo.
define variable SACreditCardHistoryNum     as integer no-undo.
define variable SAEndOfShiftNum            as integer no-undo.

assign
    newDrawer                  = 0
    SAGLDistributionNum        = 0
    SAReceiptNum               = 0
    SAReceiptPaymentNum        = 0
    SAControlAccountHistoryNum = 0
    SAFeeHistoryNum            = 0
    SAGiftCertificateDetailNum = 0
    SAMiscIncomeNum            = 0
    SAPaymentHistoryNum        = 0
    SACouponHistoryNum         = 0
    SACreditCardHistoryNum     = 0
    SAEndOfShiftNum            = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

run initialProcess("WWW",9999999).
run initialProcess("SYSTEM",9999998).

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// RUN EACH TABLE WITH THE PROVIDED USERNAME AND DRAWER
procedure initialProcess:
    define input parameter userMatch as character no-undo.
    define input parameter userDrawer as integer no-undo.
    
    assign
        newDrawer = userDrawer.
    
    for each LedgerEntry no-lock where LedgerEntry.UserName = userMatch:
        if LedgerEntry.CashDrawer <> newDrawer then run fixSAGLDistributionDrawer(LedgerEntry.ID).
    end.

    for each PaymentReceipt no-lock where PaymentReceipt.UserName = userMatch:
        if PaymentReceipt.DrawerNumber <> newDrawer then run fixSAReceiptDrawer(PaymentReceipt.ID).
    end.

    for each PaymentTransaction no-lock where PaymentTransaction.username = userMatch:
        if PaymentTransaction.CashDrawer <> newDrawer then run fixSAReceiptPaymentDrawer(PaymentTransaction.ID).
    end.

    for each AccountBalanceLog no-lock where AccountBalanceLog.username = userMatch:
        if AccountBalanceLog.CashDrawer <> newDrawer then run fixSAControlAccountHistoryDrawer(AccountBalanceLog.ID).
    end.

    for each ChargeHistory no-lock where ChargeHistory.username = userMatch:
        if ChargeHistory.CashDrawer <> newDrawer then run fixSAFeeHistoryDrawer(ChargeHistory.ID).
    end.

    for each VoucherDetail no-lock where VoucherDetail.username = userMatch:
        if VoucherDetail.CashDrawer <> newDrawer then run fixSAGiftCertificateDetailDrawer(VoucherDetail.ID).
    end.

    for each OtherRevenue no-lock where OtherRevenue.username = userMatch:
        if OtherRevenue.CashDrawer <> newDrawer then run fixSAMiscIncomeDrawer(OtherRevenue.ID).
    end.

    for each PaymentLog no-lock where PaymentLog.username = userMatch:
        if PaymentLog.DrawerNumber <> newDrawer then run fixSAPaymentHistoryDrawer(PaymentLog.ID).
    end.
    
    for each DiscountLog no-lock where DiscountLog.username = userMatch:
        if DiscountLog.CashDrawer <> newDrawer then run fixSACouponHistoryDrawer(DiscountLog.ID).
    end.

    for each CardTransactionLog no-lock where CardTransactionLog.username = userMatch:
        if CardTransactionLog.CashDrawer <> newDrawer then run fixSACreditCardHistoryDrawer(CardTransactionLog.ID).
    end.    
    
    for each ShiftClose no-lock where ShiftClose.username = userMatch:
        if ShiftClose.DrawerNumber <> newDrawer then run fixSAEndOfShiftDrawer(ShiftClose.ID,"DrawerNumber").
        if ShiftClose.OldDrawerNumber <> newDrawer then run fixSAEndOfShiftDrawer(ShiftClose.ID,"OldDrawerNumber").
    end.    

end procedure.


// FIX LedgerEntry DRAWER NUMBER
procedure fixSAGLDistributionDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufLedgerEntry for LedgerEntry. 
    do for bufLedgerEntry transaction:
        find first bufLedgerEntry exclusive-lock where bufLedgerEntry.ID = inpID no-error no-wait.
        if available bufLedgerEntry then assign
                SAGLDistributionNum            = SAGLDistributionNum + 1
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
                SAReceiptPaymentNum            = SAReceiptPaymentNum + 1
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
                SAControlAccountHistoryNum            = SAControlAccountHistoryNum + 1
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
                SAFeeHistoryNum            = SAFeeHistoryNum + 1
                bufChargeHistory.CashDrawer = newDrawer.
    end.
end.

// FIX VoucherDetail DRAWER NUMBER
procedure fixSAGiftCertificateDetailDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufVoucherDetail for VoucherDetail.
    do for bufVoucherDetail transaction:
        find first bufVoucherDetail exclusive-lock where bufVoucherDetail.ID = inpID no-error no-wait.
        if available bufVoucherDetail then assign
                SAGiftCertificateDetailNum            = SAGiftCertificateDetailNum + 1
                bufVoucherDetail.CashDrawer = newDrawer.
    end.
end.

// FIX OtherRevenue DRAWER NUMBER
procedure fixSAMiscIncomeDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufOtherRevenue for OtherRevenue.
    do for bufOtherRevenue transaction:
        find first bufOtherRevenue exclusive-lock where bufOtherRevenue.ID = inpID no-error no-wait.
        if available bufOtherRevenue then assign
                SAMiscIncomeNum            = SAMiscIncomeNum + 1
                bufOtherRevenue.CashDrawer = newDrawer.
    end.
end.

// FIX DiscountLog DRAWER NUMBER
procedure fixSACouponHistoryDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufDiscountLog for DiscountLog.
    do for bufDiscountLog transaction:
        find first bufDiscountLog exclusive-lock where bufDiscountLog.ID = inpID no-error no-wait.
        if available bufDiscountLog then assign
                SACouponHistoryNum            = SACouponHistoryNum + 1
                bufDiscountLog.CashDrawer = newDrawer.
    end.
end.

// FIX CardTransactionLog DRAWER NUMBER
procedure fixSACreditCardHistoryDrawer:
    define input parameter inpID as int64 no-undo.
    define buffer bufCardTransactionLog for CardTransactionLog.
    do for bufCardTransactionLog transaction:
        find first bufCardTransactionLog exclusive-lock where bufCardTransactionLog.ID = inpID no-error no-wait.
        if available bufCardTransactionLog then assign
                SACreditCardHistoryNum            = SACreditCardHistoryNum + 1
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
                SAPaymentHistoryNum              = SAPaymentHistoryNum + 1
                bufPaymentLog.DrawerNumber = newDrawer.
    end.
end.

// FIX ShiftClose DRAWER NUMBER
procedure fixSAEndOfShiftDrawer:
    define input parameter inpID as int64 no-undo.
    define input parameter drawerField as character no-undo.
    define buffer bufShiftClose for ShiftClose.
    do for bufShiftClose transaction:
        find first bufShiftClose exclusive-lock where bufShiftClose.ID = inpID no-error no-wait.
        if available bufShiftClose then 
        do: 
            assign
                SAEndOfShiftNum = SAEndOfShiftNum + 1.
            if drawerField = "DrawerNumber" then assign bufShiftClose.DrawerNumber = newDrawer.
            else if drawerField = "OldDrawerNumber" then assign bufShiftClose.OldDrawerNumber = newDrawer.
        end.
    end.
end.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "ChangeDrawerNumber.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Change drawer number for WWW and ZZZ transactions"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(SAGLDistributionNum + SAReceiptNum + SAReceiptPaymentNum + SAControlAccountHistoryNum + SAFeeHistoryNum + SAGiftCertificateDetailNum + SAMiscIncomeNum + SAPaymentHistoryNum + SACouponHistoryNum + SACreditCardHistoryNum + SAEndOfShiftNum)
            BufActivityLog.Detail3       = "LedgerEntry: " + string(SAGLDistributionNum) + ", PaymentReceipt: " + string(SAReceiptNum) + ", PaymentTransaction: " + string(SAReceiptPaymentNum) + ", AccountBalanceLog: " + string(SAControlAccountHistoryNum) + ", ChargeHistory: " + string(SAFeeHistoryNum) + ", VoucherDetail: " + string(SAGiftCertificateDetailNum) + ", OtherRevenue: " + string(SAMiscIncomeNum) + ", PaymentLog: " + string(SAPaymentHistoryNum) + ", DiscountLog: " + string(SACouponHistoryNum) + ", CardTransactionLog: " + string(SACreditCardHistoryNum) + ", ShiftClose: " + string(SAEndOfShiftNum).
    end.
end procedure.