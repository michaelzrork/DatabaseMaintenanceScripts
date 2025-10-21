/*------------------------------------------------------------------------
    File        : findNoFeeRecords.p
    Purpose     : Find any CHARGEHistory record with a record status of "No Fee", then find any Charge record
                  linked to the same receipt with a status of Charge that does not have a linked ChargeHistory
                  record also with a status of Charge. If there is no ChargeHistory record available, log the fee.

    Syntax      : 

    Description : Find No Fee Records with Charge Fees

    Author(s)   : michaelzr
    Created     : 7/23/24
    Notes       : - THIS IS ATTEMPTING TO RESEARCH A BUG WHERE ITEMS ARE ADDED TO CART FOR $0 THAT SHOULD HAVE A FEE AMOUNT
                  - IN MOST CASES, THE CHARGE IS ADDED WITH A RECORDSTATUS OF CHARGE, BUT NO CHARGEHISTORY RECORD WITH A RECORDSTATUS OF CHARGE WAS CREATED
                    INSTEAD, A RECORD IS CREATED THAT IS LINKED TO THE RECEIPT, BUT NOT THE FEE, WITH A RECORD STATUS OF "NO FEE"
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
define variable numRecsWithoutHistory as integer   no-undo.
define variable numRecsWithHistory    as integer   no-undo.
define variable hasFeeHistory         as logical   no-undo.
define variable accountNum                 as integer   no-undo.
define variable noFeeID               as int64     no-undo.
define variable noFeeReceiptNumber    as integer   no-undo.
define variable noFeeLogDate          as character no-undo.
define variable noFeeUserName         as character no-undo.
define variable chargeFeeFeeGroupCode as character no-undo.
define variable chargeFeeDueOption    as character no-undo.

assign
    numRecsWithHistory    = 0
    numRecsWithoutHistory = 0
    hasFeeHistory         = false
    accountNum                 = 0
    noFeeID               = 0
    noFeeReceiptNumber    = 0
    noFeeLogDate          = ""
    noFeeUserName         = ""
    chargeFeeFeeGroupCode = ""
    chargeFeeDueOption    = "".
    
define buffer bufChargeHistory for ChargeHistory.
define buffer bufCharge        for Charge.

/*CREATE TEMP TABLE TO TRACK THE RECEIPT NUMBERS THAT HAVE BEEN LOGGED IN THE RECEIPT PAYMENT LOOP*/
/*THEN SKIP THOSE RECEIPTS WHEN RUNNING THROUGH THE FEE HISTORY LOOP                              */

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("Account Number,'No Fee' ChargeHistory.ID,ChargeHistory.LogDate,ChargeHistory.ReceiptNumber,ChargeHistory.Username,TransactionDetail.ID,TransactionDetail.Description,Charge.ID,Charge.Description,Charge.FeeType,Charge.TransactionType,Charge.FeeGroupCode,Charge.MinimumPaymentOption,Charge.DueOption,Charge.Amount,ChargeHistory.ID,ChargeHistory.RecordStatus,Note,").

// RECEIPT PAYMENT LOOP
receiptpayment-loop:
for each PaymentTransaction no-lock where PaymentTransaction.ParentTable = "ChargeHistory":
    // FIND RECEIPT PAYMENT RECORDS WITH NO FEE HISTORY RECORD FOR THE LINKED PARENT ID
    find first ChargeHistory no-lock where ChargeHistory.ID = PaymentTransaction.ParentRecord no-error no-wait.
    if available ChargeHistory then next receiptpayment-loop.
    if not available ChargeHistory then find first bufChargeHistory no-lock where bufChargeHistory.RecordStatus = "No Fee" no-error no-wait.
    if available bufChargeHistory then run findUnchargedFees(bufChargeHistory.ID). 
    /* NEED TO GRAB ALL THE VARIOUS VARIABLES FOR THE LOG FILE BEFORE RUNNING THE PUT STREAM - ANOTHER PROCEDURE? */   
    if not available bufChargeHistory run put-stream(/*ENTER LOG FIELDS*/). // "Account Number,'No Fee' ChargeHistory.ID,ChargeHistory.LogDate,ChargeHistory.ReceiptNumber,ChargeHistory.Username,TransactionDetail.ID,TransactionDetail.Description,Charge.ID,Charge.Description,Charge.FeeType,Charge.TransactionType,Charge.FeeGroupCode,Charge.MinimumPaymentOption,Charge.DueOption,Charge.Amount,ChargeHistory.ID,ChargeHistory.RecordStatus,Note,"
end.

// FEE HISTORY LOOP
feehist-loop:
// LOOP THROUGH ALL FEE HISTORY RECORDS WITH A STATUS OF NO FEE
for each ChargeHistory no-lock where ChargeHistory.RecordStatus = "No Fee" and ChargeHistory.UserName = "WWW":
    /* CHECK THE TEMP TABLE FOR THE RECEIPT FROM THE RECEIPT PAYMENT LOOP BEFORE PROCEDING */
    assign
        noFeeID            = ChargeHistory.ID
        noFeeReceiptNumber = if ChargeHistory.ReceiptNumber = ? then 0 else ChargeHistory.ReceiptNumber
        noFeeLogDate       = if ChargeHistory.LogDate = ? then "No Log Date" else string(ChargeHistory.LogDate)
        noFeeUserName      = if ChargeHistory.Username = ? then "" else getString(ChargeHistory.Username).
        
    run findUnchargedFees(ChargeHistory.ID).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findNoFeeRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findNoFeeRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* THIS IS A BIT MESSED UP WITH THE TABLE QUERIES - FIX THE TABLE BUFFER DEFINITIONS AND THE BUFFER TABLES THROUGHOUT THE CODE */

procedure findUnchargedFees:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    find first bufChargeHistory no-lock where bufChargeHistory.ID = inpID no-error no-wait.
    if available bufChargeHistory then 
    do: 
        // FIND THE TRANSACTIONDETAIL RECORD FOR THE FEEHISTORY RECORD
        for first TransactionDetail no-lock where TransactionDetail.ID = ChargeHistory.ParentRecord:
            assign
                accountNum = if TransactionDetail.EntityNumber = ? then 0 else TransactionDetail.EntityNumber.
        
            // IF THE FEE HISTORY RECORD IS LINKED TO A PASS VISIT RECORD, MOVE TO THE NEXT FEE HISTORY RECORD
            if TransactionDetail.Module = "PMV" then return.
        
            fee-loop:
            // FIND ALL CHARGE RECORDS WITH A STATUS OF CHARGE FOR THE SAME ITEM AS THE NO FEE RECORD
            for each Charge no-lock where Charge.ParentRecord = ChargeHistory.ParentRecord and Charge.RecordStatus = "Charge" and Charge.ReceiptNumber = ChargeHistory.ReceiptNumber and lookup(Charge.FeeType,"Installment Bill Fee,Standard Fee") > 0 and Charge.Amount > 0:
            
                assign
                    hasFeeHistory         = false
                    chargeFeeFeeGroupCode = if Charge.FeeGroupCode = "" then "No Fee Group" else getString(Charge.FeeGroupCode)
                    chargeFeeDueOption    = if Charge.DueOption = "" then "No Due Option" else getString(Charge.DueOption).
                
                // IF THERE IS FEE HISTORY WITH A CHARGE, PAID, BILLED, OR UNBILLED STATUS MOVE TO THE NEXT CHARGE RECORD
                for first bufChargeHistory no-lock where bufChargeHistory.ParentRecord = Charge.ID and lookup(bufChargeHistory.RecordStatus,"Charge,Paid,Billed,Unbilled") > 0:
                    next fee-loop.
                end.
            
                // IF NO CHARGE TYPE CHARGEHISTORY RECORD IS FOUND, LOOK FOR ANOTHER FEE WITH THE SAME PARENTID AND CLONEID ON THE SAME RECEIPT 
                for each bufCharge no-lock where bufCharge.ID <> Charge.ID and bufCharge.ParentRecord = Charge.ParentRecord and bufCharge.CloneID = Charge.CloneID and bufCharge.ReceiptNumber = Charge.ReceiptNumber:
                    for first bufChargeHistory no-lock where bufChargeHistory.ParentRecord = Charge.ID and lookup(bufChargeHistory.RecordStatus,"Charge,Paid,Billed,Unbilled") > 0:
                        next fee-loop.
                    end.
                end.
            
                // CHECK FOR DUPLICATE FEES SUGGESTING THIS FEE SHOULD BE A RESET FEE
                for first bufCharge no-lock where bufCharge.ID <> Charge.ID and bufCharge.ParentRecord = Charge.ParentRecord and bufCharge.CloneID = Charge.CloneID and lookup(bufCharge.RecordStatus,"Charge,NoCharge,Reset") > 0 and bufCharge.ReceiptNumber > Charge.ReceiptNumber and bufCharge.LogDate ge Charge.LogDate by bufCharge.ID:
                    next fee-loop.
                end.
            
                // IF NO CHARGE TYPE FEE HISTORY IS FOUND, AND THERE IS NOT A DUPLICATE FEE WITH CHARGE TYPE HISTORY, FIND ANY FEE HISTORY RECORD FOR THE CHARGE FEE AND LOG IT
                for each bufChargeHistory no-lock where bufChargeHistory.ParentRecord = Charge.ID and bufChargeHistory.ReceiptNumber = ChargeHistory.ReceiptNumber:
                    assign 
                        hasFeeHistory      = true
                        numRecsWithHistory = numRecsWithHistory + 1.
                    run put-stream (string(accountNum) + "," + string(noFeeID) + "," + noFeeLogDate + "," + string(noFeeReceiptNumber) + ",~"" + noFeeUsername + "~"," + string(TransactionDetail.ID) + ",~"" + getString(TransactionDetail.Description) + "~"," + string(Charge.ID) + ",~"" + getString(Charge.Description) + "~"," + getString(Charge.FeeType) + ",~"" + getString(Charge.TransactionType) + "~",~"" + chargeFeeFeeGroupCode + "~"," + getString(Charge.MinimumPaymentOption) + "," + chargeFeeDueOption + "," + string(Charge.Amount) + "," + string(bufChargeHistory.ID) + "," + bufChargeHistory.RecordStatus + "," + "Non Standard Fee History Record Status,").
                end.
            
                // IF FEE HISTORY HAS BEEN FOUND  AND LOGGED, MOVED TO NEXT FEE
                if hasFeeHistory = true then next fee-loop.
            
                // IF NO CHARGEHISTORY RECORDS ARE FOUND, AND NO DUPLICATE FEE RECORDS ARE FOUND, LOG THE FEE RECORD AS AN UNCHARGED FEE
                assign 
                    numRecsWithoutHistory = numRecsWithoutHistory + 1.
                run put-stream (string(accountNum) + "," + string(noFeeID) + "," + noFeeLogDate + "," + string(noFeeReceiptNumber) + ",~"" + noFeeUsername + "~"," + string(TransactionDetail.ID) + ",~"" + getString(TransactionDetail.Description) + "~"," + string(Charge.ID) + ",~"" + getString(Charge.Description) + "~"," + getString(Charge.FeeType) + ",~"" + getString(Charge.TransactionType) + "~",~"" + chargeFeeFeeGroupCode + "~"," + getString(Charge.MinimumPaymentOption) + "," + chargeFeeDueOption + "," + string(Charge.Amount) + "," + "0" + "," + "No ChargeHistory Record" + "," + "Charge Charge Found with no ChargeHistory,").
            end.
        end.
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findNoFeeRecordsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(600)" skip.
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
            BufActivityLog.SourceProgram = "findNoFeeRecords.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find No Fee Records with Charge Fees"
            BufActivityLog.Detail2       = "Check Document Center for findNoFeeRecordsLog for a log of Records Found"
            BufActivityLog.Detail3       = "Number of Charge Fees Found Without Fee History: " + string(numRecsWithoutHistory)
            BufActivityLog.Detail4       = "Number of Charge Fees Found With Alternate Fee History: " + string(numRecsWithHistory).
    end.
end procedure.