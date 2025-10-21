/*------------------------------------------------------------------------
    File        : fixPrimaryGuardianRelationshipCode.p
    Purpose     : Fix records with mismatched relationship codes

    Syntax      : 

    Description : Finds all Relationship records where the Primary toggle is checked,
                  but the record doesn't have the Primary Guardian relationship code
                  and fixes that

    Author(s)   : michaelzr
    Created     : 8/29/2023
    Notes       : 9/21/2023 Updated by Dave Ball
                  - changed to delete the orphaned Relationship records instead of remove Primary toggle
                  - changed to go through all Relationship records to remove any orphaned links regardless of Primary toggle
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}

define variable primaryGuardianCode as character no-undo.
define variable isPrimary as logical no-undo. 
define variable numRec as integer no-undo.
define variable removedPrimary as integer no-undo.
def stream ex-port.
def var inpfile-loc as char no-undo. 
def var counter as int no-undo.
def var inpfile-num as int no-undo. 
def var ix as int no-undo. 
assign 
    inpfile-num = 1 
    numRec = 0
    removedPrimary = 0
    primaryGuardianCode = TrueVal(ProfileChar("Static Parameters","PrimeGuardSponsorCode")).

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

run put-stream ("Relationship.ID,Account.ID,Member.ID").

for each Relationship no-lock where Relationship.Primary = true and Relationship.ParentTable = "Account" and Relationship.ChildTable = "Member":
  //Find valid Member Link
  for first Member no-lock where Member.ID = Relationship.ChildTableID: 
    if Relationship.Relationship ne primaryGuardianCode then run fixRelationshipCode(Relationship.ID).
  end.
  if not available Member then run DeleteRelationship(Relationship.ID). //If No Member Found remove record entirely, it is a dead link
end.

do ix = 1 to inpfile-num:
  if search(sessiontemp() + "PrimariesRemoved" + string(ix) + ".csv") <> ? then 
  SaveFileToDocuments(sessiontemp() + "PrimariesRemoved" + string(ix) + ".csv", "\Reports\", "", no, yes, yes, "Report").  
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure fixRelationshipCode:
    define input parameter inpid as int64.
    define buffer BufRelationship for Relationship.
    do for BufRelationship transaction:
        find BufRelationship exclusive-lock where BufRelationship.ID = inpid no-error no-wait.
            if available BufRelationship then assign
                numRec = numRec + 1
                BufRelationship.Relationship = primaryGuardianCode.
    end. // do for
end procedure. // fixRelationshipCode

procedure DeleteRelationship:
    define input parameter inpid as int64.
    define buffer BufRelationship for Relationship.
    do for BufRelationship transaction:
        find BufRelationship exclusive-lock where BufRelationship.ID = inpid no-error no-wait.
            if available BufRelationship then do:
                removedPrimary = removedPrimary + 1.
                run put-stream (string(BufRelationship.ID) + "," + string(BufRelationship.ParentTableID) + "," + string(BufRelationship.ChildTableID)).
                delete BufRelationship.
            end.
    end. // do for
end procedure. // DeleteRelationship

procedure put-stream:
  def input parameter inpfile-info as char no-undo.
  inpfile-loc = sessiontemp() + "PrimariesRemoved" + string(inpfile-num) + ".csv".
  output stream ex-port to value(inpfile-loc) append.
  inpfile-info = inpfile-info + "".
  
  put stream ex-port inpfile-info format "X(400)" skip.
  counter = counter + 1.
  if counter gt 15000 then do: 
    inpfile-num = inpfile-num + 1. 
    counter = 0.
  end.
  output stream ex-port close.
end procedure. // put-stream

procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "fixPrimaryGuardianRelationshipCode.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Sets Relationship Code to Primary Guardian for all Relationship records with the Primary toggle"
            BufActivityLog.Detail2       = "Number of Primary Records Updated: " + string(numRec).
            BufActivityLog.Detail3       = "Number of Orphaned Primary Records Updated: " + string(removedPrimary).
    end.
end procedure. // ActivityLog