/*------------------------------------------------------------------------
    File        : findLinkedCriteria.p
    Purpose     : 

    Syntax      : 

    Description : Find items criteria are linked to

    Author(s)   : michaelzr
    Created     : 2/5/2025
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
define variable numRecs          as integer no-undo.
define variable hasActiveSection as logical no-undo.
define variable isActive         as logical no-undo.

assign
    numRecs          = 0
    hasActiveSection = no.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE LOG FILE FIELD HEADERS
run put-stream ("FilterCriteria.ID,Parent Table,Parent ID,Linked Record Table,Linked Record ID,Activity ID,Section ID,Activity_Section Combo,Short Description,Activity Type,Section Year,Criteria Year,Begin Date,Archived Status,Display on Web,").

for each FilterCriteria no-lock where FilterCriteria.RecordType = "Advanced":
    case FilterCriteria.Parenttable:
        when "Charge" then 
            do:
                for first Charge no-lock where Charge.ID = FilterCriteria.ParentRecord and Charge.RecordStatus = "Active":
                    case Charge.ParentTable:
                        when "ARActivity" then 
                            do:
                                for first ARActivity no-lock where ARActivity.ID = Charge.ParentRecord and ARActivity.RecordStatus = "Active":
                                    for each ARSection no-lock where ARSection.ActivityCode = ARActivity.ActivityCode and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                        run addtoLogfile(getString(Charge.ParentTable),getString(string(Charge.ParentRecord))).
                                    end.
                                end.    
                            end. // WHEN ARACTIVITY
                        when "ARSection" then 
                            do:
                                for first ARSection no-lock where ARSection.ID = Charge.ParentRecord and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                    for first ARActivity no-lock where ARActivity.ActivityCode = ARSection.ActivityCode:
                                        run addtoLogfile(getString(Charge.ParentTable),getString(string(Charge.ParentRecord))).
                                    end.
                                end.
                            end. // WHEN ARSection
                        when "Collection" then 
                            do:
                                for each Relationship no-lock where Relationship.ChildTableID = Charge.ParentRecord:
                                    case Relationship.ParentTable:
                                        when "ARActivity" then 
                                            do:
                                                for first ARActivity no-lock where ARActivity.ID = Relationship.ParentTableID and ARActivity.RecordStatus = "Active":
                                                    for each ARSection no-lock where ARSection.ActivityCode = ARActivity.ActivityCode and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                                        run addtoLogfile(getString(Charge.ParentTable),getString(string(Charge.ParentRecord))).
                                                    end.
                                                end.    
                                            end. // WHEN ARACTIVITY
                                        when "ARSection" then 
                                            do:
                                                for first ARSection no-lock where ARSection.ID = Charge.ParentRecord and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                                    for first ARActivity no-lock where ARActivity.ActivityCode = ARSection.ActivityCode:
                                                        run addtoLogfile(getString(Charge.ParentTable),getString(string(Charge.ParentRecord))).
                                                    end.
                                                end.
                                            end. // WHEN ARSection
                                    end case. // CASE RELATIONSHIP.ParentTable
                                end. 
                            end. // WHEN Collection
                        when "LookupCode" then 
                            do:
                                for first LookupCode no-lock where LookupCode.ID = Charge.ParentRecord:
                                    if LookupCode.RecordType = "Season" then 
                                    do:
                                        for each ARSection no-lock where ARSection.Season = LookupCode.RecordCode:
                                            if ARSection.RecordStatus = "Active" and ARSection.Archived = no and ARSection.DisplayOnWeb = "Yes" then 
                                            do:
                                                for first ARActivity no-lock where ARActivity.ActivityCode = ARSection.ActivityCode and ARActivity.RecordStatus = "Active":
                                                    run addtoLogfile(getString(Charge.ParentTable),getString(string(Charge.ParentRecord))).
                                                end.
                                            end.
                                        end.
                                    end.
                                end.
                            end. // WHEN SASYSTEMCODE    
                    end case. // CASE Charge.ParentTable
                end. // FOR FIRST Charge
            end. // WHEN Charge
        when "BusinessRule" or 
        when "" then  
            do:
                for first BusinessRule no-lock where BusinessRule.ID = FilterCriteria.ParentRecord and BusinessRule.RecordStatus = "Active":
                    case BusinessRule.ParentTable:
                        
                        when "LookupCode" then 
                            do:
                                for first LookupCode no-lock where LookupCode.ID = BusinessRule.ParentRecord:
                                    if LookupCode.RecordType = "Season" then 
                                    do:
                                        for each ARSection no-lock where ARSection.Season = LookupCode.RecordCode and ARSection.RecordStatus = "Active" and ARSection.Archived = no and ARSection.DisplayOnWeb = "Yes": 
                                            for first ARActivity no-lock where ARActivity.ActivityCode = ARSection.ActivityCode and ARActivity.RecordStatus = "Active":
                                                run addtoLogfile(getString(BusinessRule.ParentTable),getString(string(BusinessRule.ParentRecord))).
                                            end.
                                        end.
                                    end.
                                end.
                            end. // WHEN SASYSTEMCODE    
                            
                        when "ARActivity" then 
                            do:
                                for first ARActivity no-lock where ARActivity.ID = BusinessRule.ParentRecord and ARActivity.RecordStatus = "Active":
                                    for each ARSection no-lock where ARSection.ActivityCode = ARActivity.ActivityCode and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                        run addtoLogfile(getString(BusinessRule.ParentTable),getString(string(BusinessRule.ParentRecord))).
                                    end.
                                end.    
                            end. // WHEN ARACTIVITY
                            
                        when "ARSection" then 
                            do:
                                for first ARSection no-lock where ARSection.ID = BusinessRule.ParentRecord and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                    for first ARActivity no-lock where ARActivity.ActivityCode = ARSection.ActivityCode:
                                        run addtoLogfile(getString(BusinessRule.ParentTable),getString(string(BusinessRule.ParentRecord))).
                                    end.
                                end.
                            end. // WHEN ARSection
                            
                        when "Collection" then 
                            do:
                                for each Relationship no-lock where Relationship.ChildTableID = BusinessRule.ParentRecord:
                                    case Relationship.ParentTable:
                                        when "ARActivity" then 
                                            do:
                                                for first ARActivity no-lock where ARActivity.ID = Relationship.ParentTableID and ARActivity.RecordStatus = "Active":
                                                    for each ARSection no-lock where ARSection.ActivityCode = ARActivity.ActivityCode and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                                        run addtoLogfile(getString(BusinessRule.ParentTable),getString(string(BusinessRule.ParentRecord))).
                                                    end.
                                                end.    
                                            end. // WHEN ARACTIVITY
                                        when "ARSection" then 
                                            do:
                                                for first ARSection no-lock where ARSection.ID = BusinessRule.ParentRecord and ARSection.DisplayOnWeb = "Yes" and ARSection.Archived = no and ARSection.RecordStatus = "Active":
                                                    for first ARActivity no-lock where ARActivity.ActivityCode = ARSection.ActivityCode:
                                                        run addtoLogfile(getString(BusinessRule.ParentTable),getString(string(BusinessRule.ParentRecord))).
                                                    end.
                                                end.
                                            end. // WHEN ARSection
                                    end case. // CASE RELATIONSHIP.ParentTable
                                end. 
                            end. // WHEN Collection
                        
                    end case. // CASE BusinessRule.ParentTable
                end. // FOR FIRST BusinessRule
            end. // WHEN BusinessRule
    end case. // CASE FilterCriteria.ParentTable
end. // FOR EACH FilterCriteria           
        
  
// CREATE LOG FILE
do ixLog = 1 to inpfile-num:
    if search(sessiontemp() + "findLinkedCriteriaLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv") <> ? then 
        SaveFileToDocuments(sessiontemp() + "findLinkedCriteriaLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(ixLog) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

// CREATE AUDIT LOG RECORD
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// ADD TO LOGFILE
procedure addToLogfile:
    define input parameter linkedRecordTable as character no-undo.
    define input parameter linkedRecordID as character no-undo.
    
    run put-stream("~"" +
                                        
        /*FilterCriteria.ID*/
        getString(string(FilterCriteria.ID))
        + "~",~"" +
                                        
        /*Parent Table*/
        getString(FilterCriteria.ParentTable)
        + "~",~"" +
                                        
        /*Parent ID*/
        getString(string(FilterCriteria.ParentRecord))
        + "~",~"" +
                                                
        /*Linked Record Table*/
        linkedRecordTable // VARIABLE 
        + "~",~"" +
                                                
        /*Linked Record ID*/
        linkedRecordID // VARIABLE
        + "~",~"" +
                                                
        /*Activity ID*/
        getString(string(ARActivity.ID))
        + "~",~"" +
                                                
        /*Section ID*/
        getString(string(ARSection.ID))
        + "~",~"" +
                                                
        /*Activity_Section Combo*/
        getString(ARSection.ComboKey)
        + "~",~"" +
                                                
        /*Short Description*/
        getString(ARSection.ShortDescription)
        + "~",~"" +
        
        /*Activity Type*/
        getString(ARSection.TypeCode)
        + "~",~"" +
                                                
        /*Section Year*/
        getString(string(ARSection.Year))
        + "~",~"" +
                                                
        /*FilterCriteria Year*/
        getString(string(FilterCriteria.Value12))
        + "~",~"" +
                                                
        /*Begin Date*/
        getString(string(ARSection.BeginDate))
        + "~",~"" +
                                                
        /*Archived Status*/
        (if ARSection.Archived = yes then "Yes" else "No")
        + "~",~"" +
                                                
        /*Display on Web*/
        getString(ARSection.DisplayOnWeb)
        + "~",").
        
    assign 
        numRecs = numRecs + 1.
        
end procedure.

// CREATE LOG FILE
procedure put-stream:
    def input parameter inpfile-info as char no-undo.
    inpfile-loc = sessiontemp() + "findLinkedCriteriaLog" + "_" + replace(string(logfileDate),"/","-") + "_" + string(logfileTime) + "_" + string(inpfile-num) + ".csv".
    output stream ex-port to value(inpfile-loc) append.
    inpfile-info = inpfile-info + "".
  
    put stream ex-port inpfile-info format "X(1000)" skip.
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
            BufActivityLog.SourceProgram = "findLinkedCriteria.r"
            BufActivityLog.LogDate       = today
            BufActivityLog.LogTime       = time
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.Detail1       = "Find items criteria are linked to"
            BufActivityLog.Detail2       = "Check Document Center for findLinkedCriteriaLog for a log of Records Changed"
            BufActivityLog.Detail3       = "Number of Records Found: " + string(numRecs).
    end.
end procedure.