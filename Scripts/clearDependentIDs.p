/*------------------------------------------------------------------------
    File        : clearDependentIDs.p
    Purpose     : 

    Syntax      : 

    Description : Clear Dependent IDs for missing TransactionDetail records

    Author(s)   : michaelzr
    Created     : 1/6/2025
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
define variable numRecs  as integer   no-undo.
define variable ruleList as character no-undo.
define variable feeList  as character no-undo.
define variable ix       as integer   no-undo.

assign
    numRecs  = 0
    ruleList = ""
    feeList  = "".

define buffer bufTransactionDetail for TransactionDetail.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("TransactionDetail ID,List Type,Original DependentIDs List,Removed ID,New DependentIDs List,").

for each TransactionDetail no-lock where TransactionDetail.DependentIDs <> "":
    assign
        ruleList = ""
        feeList  = ""
        RuleList = trueval(NameVal("RuleDependentIds", TransactionDetail.DependentIds, "=", chr(30)))
        FeeList  = trueval(NameVal("FeeDependentIds", TransactionDetail.DependentIds, "=", chr(30))).
    
    if ruleList <> "" then 
    do: 
        do ix = 1 to num-entries(RuleList):
            find first bufTransactionDetail no-lock where bufTransactionDetail.ID = int64(entry(ix,RuleList)) no-error no-wait.
            if not available bufTransactionDetail and not locked bufTransactionDetail then run removeDependentID(TransactionDetail.ID,"Rules",entry(ix,RuleList)).
            // if available bufTransactionDetail and bufTransactionDetail.RecordStatus = "Removed" then run removeDependentID(TransactionDetail.ID,"Rules",entry(ix,RuleList)).
        end.
    end.
    if feeList <> "" then 
    do: 
        do ix = 1 to num-entries(FeeList):
            find first bufTransactionDetail no-lock where bufTransactionDetail.ID = int64(entry(ix,FeeList)) no-error no-wait.
            if not available bufTransactionDetail and not locked bufTransactionDetail then run removeDependentID(TransactionDetail.ID,"Fees",entry(ix,FeeList)).
            // if available bufTransactionDetail and bufTransactionDetail.RecordStatus = "Removed" then run removeDependentID(TransactionDetail.ID,"Fees",entry(ix,FeeList)).
        end.
    end.
end.  
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "clearDependentIDsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "clearDependentIDsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// DELETE DEPENDENT ID
procedure removeDependentID:
    define input parameter inpID as int64 no-undo.
    define input parameter listType as character no-undo.
    define input parameter deleteID as character no-undo.
    define variable originalList    as character no-undo.
    define variable dependentIDList as character no-undo.
    define buffer bufDetail2 for TransactionDetail.
    do for bufDetail2 transaction:
        find first bufDetail2 exclusive-lock where bufDetail2.ID = inpID no-error no-wait.
        if available bufDetail2 then 
        do:
            // SET ORIGINAL LIST VARIABLE FOR LOG
            assign 
                dependentIDList = ""
                originalList    = bufDetail2.DependentIDs
                numRecs         = numRecs + 1.
                
            case listType:
                when "Fees" then 
                    do:
                        /** GRAB EXISITING List **/
                        dependentIDList = trueval(NameVal("FeeDependentIds", bufDetail2.DependentIds, "=", chr(30))).
                        /** REMOVE EXISITING LIST **/
                        bufDetail2.DependentIDs       = RemoveList2("FeeDependentIds=" + dependentIDList,bufDetail2.DependentIDs,chr(30)).
                        // REMOVE THE MISSING bufDetail2 ID FROM THE EXISTING LIST
                        dependentIDList = removeList(deleteID,dependentIDList).
                        /** ASSIGN LIST **/
                        if dependentIDList <> "" then assign
                                bufDetail2.DependentIDs = list2("FeeDependentIds=" + dependentIDList,bufDetail2.DependentIDs,chr(30)).
                    end.
            
                when "Rules" then 
                    do:
                        /** GRAB EXISITING List **/
                        dependentIDList = trueval(NameVal("RuleDependentIds", bufDetail2.DependentIds, "=", chr(30))).
                        /** REMOVE EXISITING LIST **/
                        bufDetail2.DependentIDs       = RemoveList2("RuleDependentIds=" + dependentIDList,bufDetail2.DependentIDs,chr(30)).
                        // REMOVE THE MISSING bufDetail2 ID FROM THE EXISTING LIST
                        dependentIDList = removeList(deleteID,dependentIDList).
                        /** ASSIGN LIST **/
                        if dependentIDList <> "" then assign
                                bufDetail2.DependentIDs = list2("RuleDependentIds=" + dependentIDList,bufDetail2.DependentIDs,chr(30)).
                    end.
            end case.
            
            run put-stream("~"" +
                // TransactionDetail ID
                getString(string(inpID)) + "~",~"" +
                // List Type
                listType + "~",~"" +
                // Original DependentIDs List
                getString(originalList) + "~",~"" +
                // Removed ID
                string(deleteID) + "~",~"" +
                // New DependentIDs List
                getString(bufDetail2.DependentIDs)
                + "~",").
        end.
    end.
end procedure. 


// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "clearDependentIDsLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(30000)" skip.
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
            BufActivityLog.SourceProgram = "clearDependentIDs.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Clear Dependent IDs for missing TransactionDetail records"
            BufActivityLog.Detail2       = "Check Document Center for clearDependentIDsLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Missing IDs deleted: " + string(numRecs).
    end.
end procedure.