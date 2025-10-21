/*------------------------------------------------------------------------
    File        : convertPhoneExtToHHFeature.p
    Purpose     : TO TAKE THE VALUE IN THE PHONE EXT FIELD AND CONVERT IT TO A Account FEATURE

    Syntax      :

    Description : THIS PROGRAM WAS WRITTEN FOR A VERY SPECIFIC USE CASE WHERE THE CUSTOMER
                  HAD BEEN KEEPING TRACK OF THE HOA FEES IN THE PHONE EXT FIELD AND WE WANTED
                  TO CONVERT THAT VALUE TO A Account FEATURE SO WE COULD SET UP FEES WITH Account FEATURE
                  CRITERIA THAT WOULD LOOK AT THE FEATURE TO DETERMINE THE FEE, BUT WE NEEDED
                  TO CONVERT THE EXT TO THE FEATURE TO DO THIS

    Author(s)   : MICHAELZRORK
    Created     : EARLY 2023
    Notes       :
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

def var priceCode    as char no-undo.
def var newHHFeature as char no-undo.
def var numRecords   as int  no-undo.
priceCode = "".
newHHFeature = "".
numRecords = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

account-loop: /* CHECK FOR Account FEATURE THAT MATCHES PHONE EXT AND ADD TO ACCOUNT IF NOT THERE */
for each Account no-lock where Account.PrimaryPhoneExtension <> "":
    priceCode = Account.PrimaryPhoneExtension.
    for first LookupCode no-lock where LookupCode.RecordType = "Account Feature" and index(LookupCode.Description,priceCode) > 0:
        newHHFeature = LookupCode.RecordCode.
        if lookup(newHHFeature,Account.Features) = 0 then run addPriceCodeHHFeature(Account.ID).
    end. /* FOR FIRST */
end. /* ACCOUNT-LOOP */    

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

/* ADD RELATED Account FEATURE */
procedure addPriceCodeHHFeature:
    def input parameter inpid as int64.
    def var countVar as int no-undo.
    def buffer bufAccount for Account.
    do for bufAccount transaction:
        find bufAccount exclusive-lock where bufAccount.ID = inpid no-error no-wait.
        if available bufAccount then assign
            numRecords = numRecords + 1
            bufAccount.Features = bufAccount.Features + (if bufAccount.Features gt "" then "," else "") + newHHFeature.
    end. /* DO FOR bufAccount */
end procedure.
           
           
/* CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED */
procedure ActivityLog:
    def buffer BufActivityLog for ActivityLog.
    do for BufActivityLog transaction:
        create BufActivityLog.
        assign
            BufActivityLog.SourceProgram = "convertPhoneExtToHHFeature"
            BufActivityLog.LogDate       = today
            BufActivityLog.UserName      = "SYSTEM"
            BufActivityLog.LogTime       = time
            BufActivityLog.Detail1       = "Convert Phone Extension (Price Code) to Account Feature"
            BufActivityLog.Detail2       = "Number of Records Adjusted: " + string(numRecords).
    end.
  
end procedure.