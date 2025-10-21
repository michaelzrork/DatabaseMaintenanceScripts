/*************************************************************************
                        PROGRAM NAME AND DESCRIPTION
*************************************************************************/

&global-define ProgramName "addMissingBillingTemplateID" /* PRINTS IN AUDIT LOG AND USED FOR LOGFILE NAME */
&global-define ProgramDescription "Adds missing BillingTemplateID in InvoiceLineItem"  /* PRINTS IN AUDIT LOG WHEN INCLUDED AS INPUT PARAMETER */
    
 /*----------------------------------------------------------------------
    Author(s)   : 
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define stream   ex-port.
define variable inpfile-num           as integer   no-undo.
define variable inpfile-loc           as character no-undo.
define variable counter               as integer   no-undo.
define variable ixLog                 as integer   no-undo. 
define variable logfileDate           as date      no-undo.
define variable logfileTime           as integer   no-undo.

define variable numRecs               as integer   no-undo. 
define variable billingTemplateIDList as character no-undo.
define variable hhName                as character no-undo.
define variable personName            as character no-undo.
define variable detailDescription     as character no-undo.
define variable BillingOption         as character no-undo.
define variable transactionDate       as date      no-undo.

assign
    inpfile-num           = 1
    logfileDate           = today
    logfileTime           = time
    
    numRecs               = 0
    billingTemplateIDList = ""
    hhName                = ""
    personName            = ""
    detailDescription     = ""
    billingOption         = ""
    transactionDate       = ?.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

/* CREATE LOG FILE FIELD HEADERS */
/* I LIKE TO INCLUDE AN EXTRA COMMA AT THE END OF THE CSV ROWS BECAUSE THE LAST FIELD HAS EXTRA WHITE SPACE - IT'S JUST A LITTLE CLEANER */
run put-stream (
    "ID,TransactionDate,HouseholdNumber,Household Name,Person Name,DetailLinkID,Description,InstallmentBillingOption,BillingDetailID,").
    
for each BillingPlan no-lock:
    billingTemplateIDList = uniqueList(string(BillingPlan.ID),billingTemplateIDList,",").
end.

for each InvoiceLineItem no-lock where InvoiceLineItem.BillingTemplateID = 0 or lookup(string(InvoiceLineItem.BillingTemplateID),billingTemplateIDList) = 0:
    assign 
        hhName            = ""
        personName        = ""
        detailDescription = ""
        billingOption     = ""
        transactionDate   = ?.
    for first Charge no-lock where Charge.ParentRecord = InvoiceLineItem.DetailLinkID and Charge.FeeType = "Installment Bill Fee" and Charge.InstallmentBillingOption <> "":
        assign 
            billingOption = Charge.InstallmentBillingOption.
        find first Account no-lock where Account.EntityNumber = InvoiceLineItem.EntityNumber no-error.
        if available Account then
            assign
                hhName = trim(getString(Account.FirstName) + " " + getString(Account.LastName)).
        find first TransactionDetail no-lock where TransactionDetail.ID = InvoiceLineItem.DetailLinkID no-error.
        if available TransactionDetail then 
            assign 
                detailDescription = getString(TransactionDetail.Description)
                personName        = trim(getString(TransactionDetail.FirstName) + " " + getString(TransactionDetail.LastName))
                transactionDate   = TransactionDetail.TransactionDate.
        find first BillingPlan no-lock where BillingPlan.InstallmentBillingCode = Charge.InstallmentBillingOption no-error.
        if available BillingPlan then 
        do:
            run fixBillingTemplateID(InvoiceLineItem.ID,BillingPlan.ID).
        end.
    end.
end.
  
/* CREATE LOG FILE */
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

/* CREATE AUDIT LOG RECORD */
run ActivityLog({&ProgramDescription},"Check Document Center for " + {&ProgramName} + "Log for a log of Records Changed","Number of Records Updated: " + string(numRecs),"").

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/
    
/* FIX BILLING TEMPLATE ID */
procedure fixBillingTemplateID:
    define input parameter billingDetailID as int64 no-undo.
    define input parameter templateID as int64 no-undo.
    define buffer bufInvoiceLineItem for InvoiceLineItem.
    define buffer bufAccount     for Account.
    define buffer bufTransactionDetail        for TransactionDetail.
    do for bufInvoiceLineItem transaction:
        find first bufInvoiceLineItem exclusive-lock where bufInvoiceLineItem.ID = billingDetailID no-error.
        if available bufInvoiceLineItem then
        do:
            assign
                bufInvoiceLineItem.BillingTemplateID = templateID
                numRecs                              = numRecs + 1.
            
            run put-stream ("~"" +
                /*ID*/
                getString(string(bufInvoiceLineItem.ID))
                + "~",~"" +
                /*TransactionDate*/
                (if transactionDate = ? then "" else string(transactionDate))
                + "~",~"" +
                /*HouseholdNumber*/
                getString(string(bufInvoiceLineItem.EntityNumber))
                + "~",~"" +
                /*Household Name*/
                getString(hhName)
                + "~",~"" +
                /*Person Name*/
                getString(personName)
                + "~",~"" +
                /*DetailLinkID*/
                getString(string(bufInvoiceLineItem.DetailLinkID))
                + "~",~"" +
                /*Description*/
                getString(detailDescription)
                + "~",~"" +
                /*InstallmentBillingOption*/
                getString(BillingOption)
                + "~",~"" +
                /*BillingDetailID*/
                getString(string(templateID))
                + "~",").
                
        end.
    end.
end procedure.

/* CREATE LOG FILE */
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + {&ProgramName} + "Log" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(800)" skip.
    counter = counter + 1.
    if counter gt 40000 then 
    do: 
        inpfile-num = inpfile-num + 1. 
        counter = 0.
    end.
    output stream ex-port close.
end procedure.

/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    define input parameter logDetail1 as character no-undo.
    define input parameter logDetail2 as character no-undo.
    define input parameter logDetail3 as character no-undo.
    define input parameter logDetail4 as character no-undo.
    define buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = {&ProgramName} + ".r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = logDetail1
            bufActivityLog.Detail2       = logDetail2
            bufActivityLog.Detail3       = logDetail3
            bufActivityLog.Detail4       = logDetail4.
    end.
end procedure.