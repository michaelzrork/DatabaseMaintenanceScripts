/*------------------------------------------------------------------------
    File        : setActiveFamilyMemberToInactive_HHCheck.p
    Purpose     : Set Family Members to Inactive when Household is Inactive

    Syntax      : 

    Description : This will find all households that are inactive, and then
                  check the family member status. If it's Active, it will check
                  the for other households the family member is in, and if 
                  all other households are also inactive, it will set the FM
                  to inactive as well

    Author(s)   : MichaelZR
    Created     : 12/19/2022
    Notes       : 12/30/2022 - Updated by Dave Ball to buffer in the procedure
                  10/12/2023 - Cleaned up the formatting and comments (no code changes)
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

def var personID             as int64 no-undo.
def var householdID          as int64 no-undo.
def var secondaryHouseholdID as int64 no-undo.
def var hhCheck              as char  no-undo.
def var numRecords           as int   no-undo.
numRecords = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// RUNS THROUGH ALL INACTIVE HHs AND CHECKS FOR ACTIVE FMs
household-loop:
for each Account no-lock where Account.RecordStatus = "Inactive":
    householdID = Account.ID.
    familymember-loop:
    for each Relationship no-lock where Relationship.ParentTableID = householdID and Relationship.Childtable = "Member":
        personID = Relationship.ChildTableID.
        for first Member no-lock where Member.id = personID and Member.RecordStatus = "Active":
            hhCheck = "continue".
            run additionalHHCheck(Member.id).
            if hhCheck = "skip" then next familymember-loop.
            run setFMInactive (Member.id).
        end. /* FOR FIRST */
    end. /* FAMILYMEMBER-LOOP */
end. /* END HOUSEHOLD LOOP */
    
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// CHECKS IF FM IS LINKED TO ADDITIONAL ACTIVE HHs
procedure additionalHHCheck:
    def input parameter inpid as int64 no-undo.
    def buffer bufRelationship for Relationship.
    for each bufRelationship no-lock where bufRelationship.ChildTableID = inpid and bufRelationship.ChildTable = "Member" and bufRelationship.ParentTable = "Account" and bufRelationship.ParentTableID <> householdID and hhCheck = "continue":
        secondaryHouseholdID = bufRelationship.ParentTableID.
        if can-find(first Account where Account.ID = secondaryHouseholdID and Account.RecordStatus = "Active") then hhCheck = "skip".
    end. /* END FOR EACH */
end procedure.


// SETS FM TO INACTIVE
procedure setFMInactive:
    def input parameter inpid as int64.
    def buffer bufMember for Member.
    do for bufMember transaction:
        find bufMember exclusive-lock where bufMember.id = inpid no-error no-wait.
        if available bufMember then assign
                numRecords               = numRecords + 1
                bufMember.RecordStatus = "Inactive".
    end. /* DO FOR */
end procedure.
    
// CREATES AUDIT LOG ENTRY
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "setActiveFamilyMemberToInactive_HHCheck"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Set any Active Family Member of an Inactive Household to Inactive"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end. /* DO FOR */
end procedure.