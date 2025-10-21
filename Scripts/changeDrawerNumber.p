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
define variable LedgerEntryNum        as integer no-undo.
define variable PaymentReceiptNum               as integer no-undo.
define variable PaymentTransactionNum        as integer no-undo.
define variable AccountBalanceLogNum as integer no-undo.
define variable ChargeHistoryNum            as integer no-undo.
define variable GiftCertificateDetailNum as integer no-undo.
define variable MiscIncomeNum            as integer no-undo.
define variable PaymentLogNum        as integer no-undo.
define variable DiscountLogNum         as integer no-undo.
define variable CardTransactionLogNum     as integer no-undo.
define variable ShiftCloseNum            as integer no-undo.

assign
    newDrawer                  = 0
    LedgerEntryNum        = 0
    PaymentReceiptNum               = 0
    PaymentTransactionNum        = 0
    AccountBalanceLogNum = 0
    ChargeHistoryNum            = 0
    GiftCertificateDetailNum = 0
    MiscIncomeNum            = 0
    PaymentLogNum        = 0
    DiscountLogNum         = 0
    CardTransactionLogNum     = 0
    ShiftCloseNum            = 0.

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
        if LedgerEntry.CashDrawer <> newDrawer then run fixLedgerEntryDrawer(LedgerEntry.ID).
    end.

    for each PaymentReceipt no-lock where PaymentReceipt.UserName = userMatch:
        if PaymentReceipt.DrawerNumber <> newDrawer then run fixPaymentReceiptDrawer(PaymentReceipt.ID).
    end.

    for each PaymentTransaction no-lock where PaymentTransaction.username = userMatch:
        if PaymentTransaction.CashDrawer <> newDrawer then run fixPaymentTransactionDrawer(PaymentTransaction.ID).
    end.

    for each AccountBalanceLog no-lock where AccountBalanceLog.username = userMatch:
        if AccountBalanceLog.CashDrawer <> newDrawer then run fixAccountBalanceLogDrawer(AccountBalanceLog.ID).
    end.

    for each ChargeHistory no-lock where ChargeHistory.username = userMatch:
        if ChargeHistory.CashDrawer <> newDrawer then run fixChargeHistoryDrawer(ChargeHistory.ID).
    end.

    for each VoucherDetail no-lock where VoucherDetail.username = userMatch:
        if VoucherDetail.CashDrawer <> newDrawer then run fixSAGiftCertificateDetailDrawer(VoucherDetail.ID).
    end.

    for each OtherRevenue no-lock where OtherRevenue.username = userMatch:
        if OtherRevenue.CashDrawer <> newDrawer then run fixSAMiscIncomeDrawer(OtherRevenue.ID).
    end.

    for each PaymentLog no-lock where PaymentLog.username = userMatch:
        if PaymentLog.DrawerNumber <> newDrawer then run fixPaymentLogDrawer(PaymentLog.ID).
    end.
    
    for each DiscountLog no-lock where DiscountLog.username = userMatch:
        if DiscountLog.CashDrawer <> newDrawer then run fixSACouponHistoryDrawer(DiscountLog.ID).
    end.

    for each CardTransactionLog no-lock where CardTransactionLog.username = userMatch:
        if CardTransactionLog.CashDrawer <> newDrawer then run fixCardTransactionLogDrawer(CardTransactionLog.ID).
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
                LedgerEntryNum            = LedgerEntryNum + 1
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
                PaymentReceiptNum              = PaymentReceiptNum + 1
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
                PaymentTransactionNum            = PaymentTransactionNum + 1
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
                AccountBalanceLogNum            = AccountBalanceLogNum + 1
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
                ChargeHistoryNum            = ChargeHistoryNum + 1
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
                GiftCertificateDetailNum            = GiftCertificateDetailNum + 1
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
                MiscIncomeNum            = MiscIncomeNum + 1
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
                DiscountLogNum            = DiscountLogNum + 1
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
                CardTransactionLogNum            = CardTransactionLogNum + 1
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
                PaymentLogNum              = PaymentLogNum + 1
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
                ShiftCloseNum = ShiftCloseNum + 1.
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
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(LedgerEntryNum + PaymentReceiptNum + PaymentTransactionNum + AccountBalanceLogNum + ChargeHistoryNum + GiftCertificateDetailNum + MiscIncomeNum + PaymentLogNum + DiscountLogNum + CardTransactionLogNum + ShiftCloseNum)
            BufActivityLog.Detail3       = "LedgerEntry: " + string(LedgerEntryNum) + ", PaymentReceipt: " + string(PaymentReceiptNum) + ", PaymentTransaction: " + string(PaymentTransactionNum) + ", AccountBalanceLog: " + string(AccountBalanceLogNum) + ", ChargeHistory: " + string(ChargeHistoryNum) + ", VoucherDetail: " + string(GiftCertificateDetailNum) + ", OtherRevenue: " + string(MiscIncomeNum) + ", PaymentLog: " + string(PaymentLogNum) + ", DiscountLog: " + string(DiscountLogNum) + ", CardTransactionLog: " + string(CardTransactionLogNum) + ", ShiftClose: " + string(ShiftCloseNum).
    end.
end procedure.