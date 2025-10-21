/*------------------------------------------------------------------------
    File        : syncFamilyMemberStatusToHHStatus.p
    Purpose     : Match Family Member status to the status of the Account

    Syntax      : 

    Description : This will check the status of all family members linked to a account
                  and then check to see if they are also linked to additional households
                  before changing the status. If the Account is Active, it will change all FM
                  to Active; but if the Account is Inactive it will check to see if there
                  are any Active linked Account before changing the status to Inactive. If
                  it finds an Active Account it will skip the Member and leave it Active.

    Author(s)   : michaelzrork
    Created     : late 2022
    Notes       : 4/19/23 - Added Inactive Account status check before sending to additionalHHcheck
                    This ensures only Account set to Inactive get the extra check, so any Account set to
                    Active syncs all Member regardless of additional HHs
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

def var personID             as int64 no-undo.
def var householdID          as int64 no-undo.
def var secondaryHouseholdID as int64 no-undo.
def var accountStatus             as char  no-undo.
def var accountCheck              as char  no-undo.
def var numRecords           as int   no-undo.
numRecords = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

account-loop:
for each Account no-lock:
    accountStatus = Account.RecordStatus.
    householdID = Account.ID.
    member-loop:
    for each Relationship no-lock where Relationship.ParentTableID = householdID and Relationship.Childtable = "Member":
        personID = Relationship.ChildTableID.
        for first Member no-lock where Member.id = personID and Member.RecordStatus <> accountStatus:
            accountCheck = "continue".
            if accountStatus = "Inactive" then run additionalHHCheck(Member.id).
            if accountCheck = "skip" then next member-loop.
            run matchFMStatus (Member.id).
        end. /* FOR FIRST */
    end. /* FAMILYMEMBER-LOOP */
end. /* END ACCOUNT LOOP */
    
run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* CHECKS FOR ADDITIONAL Account SET TO ACTIVE STATUS */
procedure additionalHHCheck:
    def input parameter inpid as int64 no-undo.
    def buffer bufRelationship for Relationship.
    for each bufRelationship no-lock where bufRelationship.ChildTableID = inpid and bufRelationship.ChildTable = "Member" and bufRelationship.ParentTable = "Account" and bufRelationship.ParentTableID <> householdID and accountCheck = "continue":
        secondaryHouseholdID = bufRelationship.ParentTableID.
        if can-find(first Account where Account.ID = secondaryHouseholdID and Account.RecordStatus <> accountStatus) then accountCheck = "skip".
    end. /* END FOR EACH */
end procedure.

/* SETS Member STATUS TO STATUS OF Account */
procedure matchFMStatus:
    def input parameter inpid as int64.
    def buffer bufMember for Member.
    do for bufMember transaction:
        find bufMember exclusive-lock where bufMember.id = inpid no-error no-wait.
        if available bufMember then assign
            numRecords = numRecords + 1
            bufMember.RecordStatus = accountStatus.
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
            BufActivityLog.Detail1       = "Set Member status to match Account status"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end. /* DO FOR */
end procedure.