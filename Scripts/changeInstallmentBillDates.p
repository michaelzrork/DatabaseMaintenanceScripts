/*------------------------------------------------------------------------
    File        : changeInstallmentBillDates.p
    Purpose     : Update the dates on installment bills in bulk

    Syntax      : 

    Description : 

    Author(s)   : michaelzr
    Created     : 01/23/2024
    Notes       : - Originally wrote to target a specific Fee, but realized that my customer needed all
                    bills with the date of the 2nd to be adjusted, so I removed that check. It can be
                    added back in, or updated to check a list of fees for more targetted adjustments.
                  - 1/24/24 Notes from DaveB added to the end; use these to make the code more efficent before using it again!
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
define variable ix          as integer   no-undo. 

inpfile-num = 1.

define variable originalDay   as integer no-undo.
define variable newDay        as integer no-undo.
define variable numRecs       as integer no-undo.
define variable originalMonth as integer no-undo.
define variable originalYear  as integer no-undo.
// define variable feeID         as int64   no-undo.
assign
    originalDay = 2
    newDay      = 1
    numRecs     = 0.
    // feeID      = 852866.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELDS
run put-stream ("Table,RecordID,HH#,Receipt#,OriginalBillDate,NewBillDate").

// LOOP THROUGH CHARGEHISTORY FOR FUTURE BILLS SET TO THE 2ND
// ORIGINALY WRITTEN TO TARGET SPECIFIC FEES, BUT SINCE THIS CUSTOMER NEEDS ANY BILL WITH THE 2ND, I REMOVED THAT CHECK
// THE CHECK CAN BE REINSTATED AND UPDATED TO CHECK A LIST OF FEES IF NECESSARY 
for each ChargeHistory no-lock where lookup(ChargeHistory.RecordStatus,"Unbilled,Unbilled Adjusted,Suspended") > 0 /* and ChargeHistory.ParentRecord = feeID */ and int(substring(string(ChargeHistory.BillDate),4,2)) = originalDay:
    assign
        // GRAB THE ORIGINAL MONTH AND YEAR TO MAKE IT EASIER TO UPDATE LATER
        originalMonth = int(substring(string(ChargeHistory.BillDate),1,2))
        originalYear  = int(substring(string(ChargeHistory.BillDate),7)) + 2000.
    run changeDate(ChargeHistory.ID).
end.

// CREATE LOG FILE
do ix = 1 to inpfile-num:
    if search(sessiontemp() + "InstallmentBillDateChange" + string(ix) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "InstallmentBillDateChange" + string(ix) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHANGE INSTALLMENT BILLING DATE
procedure changeDate:
    define input parameter inpID as int64 no-undo.
    define buffer bufChargeHistory for ChargeHistory.
    do for bufChargeHistory transaction:
        find first bufChargeHistory exclusive-lock where bufChargeHistory.ID = inpID no-error no-wait.
        if available bufChargeHistory then 
            // CREATE LOG ENTRY "Table,RecordID,HH#,Receipt#,OriginalBillDate,NewBillDate"
            run put-stream ("ChargeHistory" + "," + string(bufChargeHistory.ID) + "," + string(bufChargeHistory.PaymentHousehold) + "," + string(bufChargeHistory.ReceiptNumber) + "," + string(bufChargeHistory.BillDate) + "," + string(date(originalMonth,newDay,originalYear))).
            assign
                numRecs                  = numRecs + 1
                bufChargeHistory.BillDate = date(originalMonth,newDay,originalYear).
    end.
end.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "InstallmentBillDateChange" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(400)" skip.
    counter = counter + 1.
    if counter gt 15000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.


// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY TRANSACTIONDETAIL RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "changeInstallmentBillDates.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Change Installment Bill Date from mm/" + (if originalDay < 10 then "0" else "") + string(originalDay) + "/yyyy to mm/" + (if newDay < 10 then "0" else "") + string(newDay) + "/yyyy"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecs)
            BufActivityLog.Detail3       = "Check Document Center for Log File of Records Changed".
    end.
end procedure.


/* NOTES FROM DAVEB

int(substring(string(ChargeHistory.BillDate),4,2)) = originalDay

should be 
day(ChargeHistory.BillDate) = originalDay
 
 
assign
        originalMonth = int(substring(string(ChargeHistory.BillDate),1,2))
        originalYear  = int(substring(string(ChargeHistory.BillDate),7)) + 2000.
 
should be 
assign
        originalMonth = month(ChargeHistory.BillDate)
        originalYear  = year(ChargeHistory.BillDate).
 
FWIW there is also a "weekday" function that will return #of the day of the week (ie, Sunday is 1 and Saturday is 7)
 
 
The other thing i would do just because ChargeHistory is SO MASSIVE is one of 2 things:
    
    Split the "SAfeeHistory" loop into three runs with an equality on RecordStatus. You could put it all in a procedure
    and call the procedure three different times with an input parameter of the recordstatus. 

    or, Get rid of the "Suspended" piece and change the loop to
        for each ChargeHistory no-lock where ChargeHistory.RecordStatus begins "Unbilled":
    if you do this, move the new "day" piece to a condition within the for each rather than part of the query (you want to
    use "begins" on its own to utilize it correctly.) I would just query their actual data to see if you actually need
    "Suspended" at all. If so, go with #1. 
 
The query as written may work locally on a small db and it might work for them (but potentially slowly) but doing this kind
of fix for any our bigger customers we have to consider efficiency.  We had this exact problem when trying to update email
records - the program was not finishing for certain customer because the code was written inefficiently. We had to kill it
for them and run a quickie that i worte that was more efficient.

*/