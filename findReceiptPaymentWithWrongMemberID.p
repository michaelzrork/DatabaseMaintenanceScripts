/*------------------------------------------------------------------------
    File        : findReceiptPaymentWithWrongID.p
    Purpose     : 

    Syntax      : 

    Description : Find Receipt Payments with the wrong Member ID

    Author(s)   : michaelzr
    Created     : 8/2/24
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

// LOG FILE STUFF

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num as integer   no-undo.
define variable inpfile-loc as character no-undo.
define variable counter     as integer   no-undo.
define variable ixLog       as integer   no-undo. 
define variable logfileDate as date      no-undo.
define variable logfileTime as integer   no-undo. 

assign
    inpfile-num = 1
    logfileDate = today
    logfileTime = time.

// EVERYTHING ELSE
define variable numRecs              as integer   no-undo.
define variable hhList               as character no-undo.
define variable incorrectName        as character no-undo.
define variable correctName          as character no-undo.
define variable paycodeList          as character no-undo.
define variable paymentHistoryAmount as decimal   no-undo.
define variable paymentType          as character no-undo.

assign
    numRecs              = 0
    hhList               = ""
    incorrectName        = ""
    correctName          = ""
    paycodeList          = ""
    paymentType          = ""
    paymentHistoryAmount = 0.

define buffer bufPaymentTransaction for PaymentTransaction.    
define buffer bufMember         for Member.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// FIND SCHOLARSHIP AND GIFT CERTIFICATE PAY CODES
for each PaymentMethod no-lock where lookup(PaymentMethod.RecordType,"Scholarship,Gift Certificate") > 0:
    paycodeList = list(PaymentMethod.PayCode,paycodeList).
end.

// CREATE LOG FILE FIELD HEADERS
run put-stream ("PaymentTransaction ID,Date,Time,User,Receipt Number,Receipt Account Num,Correct Member ID,Correct Member Name,Incorrect Member Account Num List,Incorrect Member ID,Incorrect Member Name,Paycode,Paycode Record Type,Receipt Payment Amount,Payment History Amount,").

payment-loop:
for each PaymentTransaction no-lock where PaymentTransaction.PaymentMemberID <> 0:
    assign
        hhList               = ""
        incorrectName        = ""
        correctName          = ""
        paymentHistoryAmount = 0
        paymentType          = "".
    find first PaymentReceipt no-lock where PaymentReceipt.EntityNumber = PaymentTransaction.PaymentHousehold no-error no-wait.
    if available PaymentReceipt then 
    do:
        find first ChargeHistory no-lock where ChargeHistory.ID = PaymentTransaction.ParentRecord no-error no-wait.
        if available ChargeHistory then 
        do:
            find first Charge no-lock where Charge.ID = ChargeHistory.ParentRecord no-error no-wait.
            if available Charge then 
            do:
                find first TransactionDetail no-lock where TransactionDetail.ID = Charge.ParentRecord no-error no-wait.
                if available TransactionDetail then 
                do:
                    // IF THE PERSON ON THE TRANSACTIONDETAIL RECORD DOES NOT MATCH THE PERSON ON THE RECEIPT PAYMENT RECORD, KEEP GOING
                    if TransactionDetail.PatronLinkID <> PaymentTransaction.PaymentMemberID then 
                    do:
                        
                        // FIND PAYCODE RECORD TYPE
                        find first PaymentMethod no-lock where PaymentMethod.PayCode = PaymentTransaction.Paycode no-error no-wait.
                        if available PaymentMethod then assign paymentType = PaymentMethod.RecordType.
                            
                        if lookup(PaymentTransaction.Paycode,paycodeList) > 0 then 
                        do:                            
                            for first PaymentLog no-lock where PaymentLog.ReceiptNumber = PaymentTransaction.ReceiptNumber and PaymentLog.MemberLinkID <> TransactionDetail.PatronLinkID:
                                // GRAB AMOUNT USED OR REFUNDED, UPDATE THE MEMBERLINKID THEN FIND THE MEMBER RECORD AND ADJUST THE SCHOLARSHIPAMOUNT BY THAT AMOUNT
                                assign 
                                    paymentHistoryAmount = PaymentLog.Amount.
                            end.
                        end. 
                        
                        // FIND PERSON RECORD FOR INCORRECT PAYMENT MEMBER ID
                        find first Member no-lock where Member.ID = PaymentTransaction.PaymentMemberID no-error no-wait.
                        if available Member then 
                        do:
                            incorrectName = Member.FirstName + " " + Member.LastName.
                            // ADD EVERY ACCOUNT ASSOCIATED WITH THIS PERSON TO THE Account LIST
                            for each Relationship no-lock where Relationship.ChildTableID = Member.ID and Relationship.ParentTable = "Account" and Relationship.RecordType = "Account":
                                find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
                                hhList = list(string(Account.EntityNumber),hhList).
                            end.
                            // IF THE PERSON ON THE TRANSACTIONDETAIL RECORD IS IN ONE OF THE ACCOUNTS THE INCORRECT PERSON IS IN, SKIP THE RECORD
                            if lookup(string(PaymentTransaction.PaymentHousehold),hhList) ne 0 then next payment-loop.
                        end.
                        
                        // IF NOT AVAILABLE FIND FIRST TEAM THAT MATCHES THE ID
                        if not available Member then find first LSTeam no-lock where LSTeam.ID = PaymentTransaction.PaymentMemberID no-error no-wait.
                        if available LSTeam then 
                        do:
                            incorrectName = "TeamID: " + LSTeam.TeamID.
                            // ADD EVERY ACCOUNT ASSOCIATED WITH THIS TEAM TO THE Account LIST
                            for each Relationship no-lock where Relationship.ChildTableID = LSTeam.ID and Relationship.ParentTable = "Account" and Relationship.RecordType = "Team":
                                find first Account no-lock where Account.ID = Relationship.ParentTableID no-error no-wait.
                                hhList = list(string(Account.EntityNumber),hhList).
                            end.
                            // IF THE PERSON ON THE TRANSACTIONDETAIL RECORD IS IN ONE OF THE ACCOUNTS THE INCORRECT PERSON IS IN, SKIP THE RECORD
                            if lookup(string(PaymentTransaction.PaymentHousehold),hhList) ne 0 then next payment-loop.
                        end.
                        
                        // FIND THE PERSON RECORD FOR THE CORRECT PERSON
                        if TransactionDetail.PatronTypeLinkTable = "Member" then find first bufMember no-lock where bufMember.ID = TransactionDetail.PatronLinkID no-error no-wait.
                        if available bufMember then assign correctName = bufMember.FirstName + " " + bufMember.LastName.
                        
                        // IF NOT AVAILABLE FIND THE FIRST TEAM THAT MATCHES THE ID
                        if TransactionDetail.PatronTypeLinkTable = "LSTeam" then find first LSTeam no-lock where LSTeam.ID = TransactionDetail.PatronLinkID no-error no-wait.
                        if available LSTeam then assign correctName = "TeamID: " + LSTeam.TeamID.
                        
                        assign
                            numRecs = numRecs + 1.
                        // PaymentTransaction ID,Date,Time,User,Receipt Number,Receipt Account Num,Correct Member ID,Correct Member Name,Incorrect Member Account Num List,Incorrect Member ID,Incorrect Member Name,Paycode,Paycode Record Type,Receipt Payment Amount,Payment History Amount
                        run put-stream(string(PaymentTransaction.ID) + "," + (if PaymentTransaction.PostingDate = ? then "" else string(PaymentTransaction.PostingDate)) + "," + string(PaymentTransaction.PostingTime / 86400) + "," + PaymentTransaction.UserName + "," + string(PaymentTransaction.ReceiptNumber) + "," + string(PaymentTransaction.PaymentHousehold) + "," + string(TransactionDetail.PatronLinkID) + "," + (if correctName = "" then "Member Not Available" else "~"" + correctName + "~"") + "," + "~"" + replace(hhList,",",", ") + "~"" + "," + string(PaymentTransaction.PaymentMemberID) + "," + (if incorrectName = "" then "Member Not Available" else "~"" + incorrectName + "~"") + "," + PaymentTransaction.Paycode + "," + paymentType + "," + string(PaymentTransaction.Amount) + "," + (if paymentHistoryAmount = 0 then "n/a" else string(paymentHistoryAmount)) + ",").
                    end.
                end.
            end.
        end.
    end.
end.

  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findReceiptPaymentWithWrongIDLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findReceiptPaymentWithWrongIDLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/



// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findReceiptPaymentWithWrongIDLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 30000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "findReceiptPaymentWithWrongID.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find Receipt Payments with the wrong Member ID"
            BufActivityLog.Detail2       = "Check Document Center for findReceiptPaymentWithWrongIDLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.