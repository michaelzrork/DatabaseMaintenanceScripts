/*------------------------------------------------------------------------
    File        : fixFileLinkID.p
    Purpose     : Fix FileLinkID fields after Service Item Code Conversion with merge

    Syntax      : 

    Description : Finds all records with the old FileLinkIDs of the various converted
                  service item codes and updates them to their respective new FileLinkIDs
                  as well as updates their respecitive Descriptions

    Author(s)   : michaelzr
    Created     : 10/26/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
define variable ix as integer no-undo.
define variable recCount as integer no-undo.
define variable newFileLinkID as integer no-undo.
define variable newDescription as character no-undo.
define variable serviceItemCodeList as character no-undo.
define variable conversionDate as date no-undo.
ix = 0.
recCount = 0.
newFileLinkID = 0.
newDescription = "".
serviceItemCodeList = "".
conversionDate = 11/6/2023.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/


// CREATE SERVICE ITEM CODE LIST
for each ActivityLog where ActivityLog.LogDate = conversionDate and ActivityLog.SourceProgram = "CodeConversion" and ActivityLog.Detail4 = "Merge Record: Yes":
    if lookup(substring(ActivityLog.Detail3,18),serviceItemCodeList) = 0 then serviceItemCodeList = list(substring(ActivityLog.Detail3,18),serviceItemCodeList).
end.

// SERVICE ITEM LOOP
do ix = 1 to num-entries(serviceItemCodeList):
    newFileLinkID = 0.
    newDescription = "".
    for first PSServiceItem no-lock where PSServiceItem.ServiceItem = entry(ix,serviceItemCodeList).
        assign
            newFileLinkID = PSServiceItem.ID
            newDescription = PSServiceItem.ShortDescription + " (" + PSServiceItem.serviceitem + ")".    
        // UPDATE FILELINKID AND DESCRIPTION
        for each TransactionDetail no-lock where TransactionDetail.Module = "PSS" and TransactionDetail.FileLinkCode1 = entry(ix,serviceItemCodeList) and TransactionDetail.FileLinkID <> newFileLinkID:
            run updateSADetailRecord(TransactionDetail.ID).
        end. // UPDATE FILELINKID AND DESCRIPTION
    end. // FOR FIRST
end. // SERVICE ITEM LOOP

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/
 
 procedure updateSADetailRecord:
     define input parameter inpid as int64 no-undo.
     define buffer bufTransactionDetail for TransactionDetail.
     find first bufTransactionDetail exclusive-lock where bufTransactionDetail.ID = inpid no-error no-wait.
     if available bufTransactionDetail then assign
        recCount = recCount + 1
        bufTransactionDetail.FileLinkID = newFileLinkID
        bufTransactionDetail.Description = newDescription.
 end procedure.
 
 procedure ActivityLog:
     define buffer bufActivityLog for ActivityLog.
     do for bufActivityLog transaction:
         create bufActivityLog.
         assign
            bufActivityLog.SourceProgram = "fixFileLinkID"
            bufActivityLog.LogDate       = today
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.LogTime       = time
            bufActivityLog.Detail1       = "Fixed TransactionDetail FileLinkID and Description after service item code conversion merge"
            bufActivityLog.Detail2       = "Records updated: " + string(recCount)
            bufActivityLog.Detail3       = if serviceItemCodeList <> "" then string(serviceItemCodeList) else "No ServiceItemCodes".
    end. // TRANSACTION
 end procedure.