/*------------------------------------------------------------------------
    File        : syncFamilyMemberStatusToHHStatus.p
    Purpose     : Match Family Member status to the status of the Household

    Syntax      : 

    Description : This will check the status of all family members linked to a household
                  and then check to see if they are also linked to additional households
                  before changing the status. If the HH is Active, it will change all FM
                  to Active; but if the HH is Inactive it will check to see if there
                  are any Active linked HH before changing the status to Inactive. If
                  it finds an Active HH it will skip the FM and leave it Active.

    Author(s)   : michaelzrork
    Created     : late 2022
    Notes       : 4/19/23 - Added Inactive HH status check before sending to additionalHHcheck
                    This ensures only HH set to Inactive get the extra check, so any HH set to
                    Active syncs all FM regardless of additional HHs
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

def var personID             as int64 no-undo.
def var householdID          as int64 no-undo.
def var secondaryHouseholdID as int64 no-undo.
def var hhStatus             as char  no-undo.
def var hhCheck              as char  no-undo.
def var numRecords           as int   no-undo.
numRecords = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

household-loop:
for each Account no-lock:
    hhStatus = Account.RecordStatus.
    householdID = Account.ID.
    familymember-loop:
    for each Relationship no-lock where Relationship.ParentTableID = householdID and Relationship.Childtable = "Member":
        personID = Relationship.ChildTableID.
        for first Member no-lock where Member.id = personID and Member.RecordStatus <> hhStatus:
            hhCheck = "continue".
            if hhStatus = "Inactive" then run additionalHHCheck(Member.id).
            if hhCheck = "skip" then next familymember-loop.
            run matchFMStatus (Member.id).
        end. /* FOR FIRST */
    end. /* FAMILYMEMBER-LOOP */
end. /* END HOUSEHOLD LOOP */
    
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* CHECKS FOR ADDITIONAL HH SET TO ACTIVE STATUS */
procedure additionalHHCheck:
    def input parameter inpid as int64 no-undo.
    def buffer bufRelationship for Relationship.
    for each bufRelationship no-lock where bufRelationship.ChildTableID = inpid and bufRelationship.ChildTable = "Member" and bufRelationship.ParentTable = "Account" and bufRelationship.ParentTableID <> householdID and hhCheck = "continue":
        secondaryHouseholdID = bufRelationship.ParentTableID.
        if can-find(first Account where Account.ID = secondaryHouseholdID and Account.RecordStatus <> hhStatus) then hhCheck = "skip".
    end. /* END FOR EACH */
end procedure.

/* SETS FM STATUS TO STATUS OF HH */
procedure matchFMStatus:
    def input parameter inpid as int64.
    def buffer bufMember for Member.
    do for bufMember transaction:
        find bufMember exclusive-lock where bufMember.id = inpid no-error no-wait.
        if available bufMember then assign
            numRecords = numRecords + 1
            bufMember.RecordStatus = hhStatus.
    end. /* DO FOR */
end procedure.
    
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "syncFamilyMemberStatusToHHStatus"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Set FM status to match HH status"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end. /* DO FOR */
end procedure.