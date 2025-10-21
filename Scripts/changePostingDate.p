/*------------------------------------------------------------------------
    File        : changePostingDate.p
    Purpose     : CHANGE POSTING DATE ON IB RUN WHERE THE POSTING DATE MISMATCHES
                  THE DATE THE IB WAS ACTUALLY RUN

    Syntax      : 

    Description : CHANGES THE POSTING DATE FOR LedgerEntry TABLE RECORDS

    Author(s)   : MICHAELZRORK
    Created     : OCT 2022
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

define variable NumRecords as integer no-undo.
define variable userName as character no-undo.
define variable cashDrawer as integer no-undo.
define variable oldPostingDate as date no-undo.
define variable newPostingDate as date no-undo.

userName = "kschmidt".
cashDrawer = 888.
oldPostingDate = 10/01/2022.
newPostingDate = 10/03/2022.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

for each LedgerEntry no-lock where LedgerEntry.PostingDate = oldPostingDate and LedgerEntry.CashDrawer = cashDrawer and LedgerEntry.UserName = userName:
    run changedate (LedgerEntry.id).
end.  


run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure changedate:
  def input parameter inpid as int64.
  def buffer bufLedgerEntry for LedgerEntry.
  do for bufLedgerEntry transaction:
    find bufLedgerEntry exclusive-lock where bufLedgerEntry.id = inpid no-error no-wait.
    if available bufLedgerEntry then assign
      NumRecords = NumRecords + 1
      bufLedgerEntry.PostingDate = newPostingDate.
  end.
end procedure.


procedure ActivityLog:
  def buffer BufActivityLog for ActivityLog.
   
  do for BufActivityLog transaction:
  
    create BufActivityLog.
    assign
      BufActivityLog.SourceProgram = "ChangePostingDate"
      BufActivityLog.LogDate       = today
      BufActivityLog.UserName      = "SYSTEM"
      BufActivityLog.LogTime       = time
      BufActivityLog.Detail1       = "Change LedgerEntry.PostingDate from " + string(oldPostingDate) + " to " + string(newPostingDate)
      BufActivityLog.Detail2       = "Number of Records Adjusted = " + string(NumRecords).
  end.
  
end procedure.