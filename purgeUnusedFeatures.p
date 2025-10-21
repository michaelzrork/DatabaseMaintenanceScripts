/*------------------------------------------------------------------------
    File        : purgeUnusedFeatures.p
    Purpose     : Purge feature codes from Account and Member that are no longer in the system 

    Syntax      : 

    Description : This program will create a list of all current Account and Member Features, then remove any Feature 
                    still linked in the Account or Member tables that are no longer in the system

    Author(s)   : michaelzr
    Created     : 7/5/2023
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/
{Includes/Framework.i}
define variable hhFeatureList as character no-undo.
define variable fmFeatureList as character no-undo.
define variable numRecords as integer no-undo.
define variable oldFeatures as character no-undo.
define variable newFeatures as character no-undo.
define variable countVar as int no-undo.
hhFeatureList = "".
fmFeatureList = "".
numRecords = 0.
oldFeatures = "".
newFeatures = "".
countVar = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

// CREATE ACCOUNT FEATURE LIST
for each LookupCode no-lock where LookupCode.RecordType = "Account Feature":
    hhFeatureList = list(LookupCode.RecordCode,hhFeatureList).
end.
    
// CREATE FAMILY MEMBER FEATURE LIST
for each LookupCode no-lock where LookupCode.RecordType = "Family Member Feature":
    fmFeatureList = list(LookupCode.RecordCode,fmFeatureList).
end.

// COMPARE Account FEATURES TO hhFeatureList
account-loop:
    for each Account no-lock where Account.Features <> "":
        oldFeatures = Account.Features.
        newFeatures = "".
            count-loop: // CREATES LIST OF NEW FEATURES, DISCARDING ANY FEATURES NO LONGER IN THE SYSTEM
                do countVar = 1 to num-entries(oldFeatures):
                    if lookup(entry(countVar,oldFeatures),hhFeatureList) = 0 then next count-loop.
                    newFeatures = list(entry(countVar,oldFeatures),newFeatures).
                end.
        if newFeatures <> oldFeatures then run purgeHHFeatures(Account.ID).
    end.
    
// COMPARE Member FEATURES TO fmFeatureList
member-loop:
    for each Member no-lock where Member.Features <> "":
        oldFeatures = Member.Features.
        newFeatures = "".
            count-loop: // CREATES LIST OF NEW FEATURES, DISCARDING ANY FEATURES NO LONGER IN THE SYSTEM
                do countVar = 1 to num-entries(oldFeatures):
                    if lookup(entry(countVar,oldFeatures),fmFeatureList) = 0 then next count-loop.
                    newFeatures = list(entry(countVar,oldFeatures),newFeatures).
                end.
        if newFeatures <> oldFeatures then run purgeFMFeatures(Member.ID).
    end.
    
 run ActivityLog.
    
/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

// WRITES newFeatures LIST TO THE Account FEATURES
procedure purgeHHFeatures:
    define input parameter inpid as int64.
    define buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.id = inpid no-error no-wait.
        if available bufAccount then assign
            numRecords = numRecords + 1
            bufAccount.Features = newFeatures.
    end.
end procedure.

// WRITES newFeatures LIST TO THE Member FEATURES
procedure purgeFMFeatures:
    define input parameter inpid as int64.
    define buffer bufMember for Member.
    do for bufMember transaction:
        find bufMember exclusive-lock where bufMember.id = inpid no-error no-wait.
        if available bufMember then assign
            numRecords = numRecords + 1
            bufMember.Features = newFeatures.
    end.
end procedure.

// CREATES AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "purgeUnusedFeatures.p"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Purge all Features from Account and Member that are no longer in the system"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end.
  
end procedure.