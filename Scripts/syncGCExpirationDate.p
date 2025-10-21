/*------------------------------------------------------------------------
    File        : syncGCExpirationDate.p
    Purpose     : 

    Syntax      : 

    Description : Sync Gift Certificate Expiration Dates to the Current Expiration Date on the Service Item

    Author(s)   : michaelzr
    Created     : 2/12/25
    Notes       : Will find all Gift Certificates that have not yet been redeemed and sync their expiration dates with the 
                    current expiration date of the PSServiceItem they are linked to. If the PSServiceItem is missing, the 
                    new expiration date will be stripped or set to the date on the missingDate variable.
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
define variable numRecs     as integer no-undo.
define variable missingDate as date    no-undo.

assign
    numRecs     = 0
    missingDate = ?.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("ID,Gift Certificate Code,Gift Certificate Number,Household,Amount Issued,Amount Used,Issue Date,Original Expiration Date,New Expiration Date,").

for each VoucherDetail no-lock where VoucherDetail.Redeemed = no:
    find first PSServiceItem no-lock where PSServiceItem.ServiceItem = VoucherDetail.ServiceItem no-error no-wait.
    if available PSServiceItem and VoucherDetail.ExpirationDate <> PSServiceItem.ExpirationDate then run syncExpirationDate(VoucherDetail.ID,PSServiceItem.ExpirationDate).
    if not available PSServiceItem then run syncExpirationDate(VoucherDetail.ID,missingDate).
end.
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "syncGCExpirationDateLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "syncGCExpirationDateLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHANGE EXPIRATION DATE
procedure syncExpirationDate:
    define input parameter inpID as int64 no-undo.
    define input parameter newExpirationDate as date no-undo.
    define buffer bufVoucherDetail for VoucherDetail.
    do for bufVoucherDetail transaction:
        find first bufVoucherDetail exclusive-lock where bufVoucherDetail.ID = inpID no-error no-wait.
        if available bufVoucherDetail then 
        do:
            run put-stream("~"" +
                /*ID*/
                getString(string(bufVoucherDetail.ID))
                + "~",~"" +
                /*Gift Certificate Code*/
                getString(bufVoucherDetail.ServiceItem)
                + "~",~"" +
                /*Gift Certificate Number*/
                getString(string(bufVoucherDetail.Number))
                + "~",~"" +
                /*Household*/
                getString(string(bufVoucherDetail.EntityNumber))
                + "~",~"" +
                /*Amount Issued*/
                getString(string(bufVoucherDetail.Amount))
                + "~",~"" +
                /*Amount Used*/
                getString(string(bufVoucherDetail.AmountUsed))
                + "~",~"" +
                /*Issue Date*/
                getString(string(bufVoucherDetail.IssueDate))
                + "~",~"" +
                /*Original Expiration Date*/
                getString(string(bufVoucherDetail.ExpirationDate))
                + "~",~"" +
                /*New Expiration Date*/
                getString(string(newExpirationDate))
                + "~",").
            assign
                numRecs                                   = numRecs + 1
                bufVoucherDetail.ExpirationDate = newExpirationDate.
        end.
    end.
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "syncGCExpirationDateLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
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
            BufActivityLog.SourceProgram = "syncGCExpirationDate.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Sync Gift Certificate Expiration Dates to the Current Expiration Date on the Service Item"
            BufActivityLog.Detail2       = "Check Document Center for syncGCExpirationDateLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.