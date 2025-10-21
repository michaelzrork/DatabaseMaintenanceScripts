
/*------------------------------------------------------------------------
    File        : fixTeeTimes.p
    Purpose     : 

    Syntax      :

    Description : Fixes Tee Times with bad TeeTime data 

    Author(s)   : michaelzr
    Created     : 5/21/2024
    Notes       : - Loops through all Tee Time with a TeeTime that exceeds 86400 (midnight) then subtracts 86400 seconds so it aligns with the proper time
                  - Also deletes any TeeTime with a null value, as those are broken records (this also removes the SearchCache record) 
                  - 10/31/2024 updated to subtract 86400 from the linkedtime as well, as they weren't getting blocked off once the teetime was fixed
                  - Worth noting that this fix is only necessary if trying to clear tee times that exceeded 11:59pm, as the system won't clear anything beyond 86399
                    and should not be necessary if the tee times are otherwise fine, as bookings seem to work; with the possible exception of the wonky teetimes 
                    breaking syncing with services such as GolfNow
  ----------------------------------------------------------------------*/

/* ***************************  Definitions  ************************** */

block-level on error undo, throw.

{Includes/Framework.i} 
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i} 
{Includes/TransactionDetailStatusList.i}

define variable BeginTime as int     no-undo.
define variable ix        as integer no-undo.
define variable iy        as integer no-undo.
define variable iz        as integer no-undo.

/* ***************************  Main Block  *************************** */

assign
    BeginTime = 0
    ix        = 0
    iy        = 0
    iz        = 0.
  
for each GRTeeTime no-lock where GRTeeTime.TeeTime = ?:
    run deleteTeeTime(GRTeeTime.ID).
end.
  
for each GRTeeTime no-lock where GRTeeTime.TeeTime = BeginTime:
    run fixTeeTime(GRTeeTime.ID).
end.

/*for each GRTeeTime no-lock where GRTeeTime.LinkedTime ge BeginTime:*/
/*    run fixLinkedTime(GRTeeTime.ID).                               */
/*end.                                                               */

create ActivityLog.
assign 
    ActivityLog.SourceProgram = "fixTeeTimes.r"
    ActivityLog.LogDate       = today
    ActivityLog.UserName      = signon()
    ActivityLog.LogTime       = time
    ActivityLog.Detail1       = "Fixes Tee Times with bad TeeTime data"
    ActivityLog.Detail2       = "Number of Tee Times fixed: " + string(ix)
    ActivityLog.Detail3       = "Number of Linked Times fixed: " + string(iz)
    ActivityLog.detail4       = "Number of Tee Times deleted: " + string(iy).

/* ***************************  Procedures  *************************** */

procedure fixTeeTime:
    define input parameter inpID as int64.
    define buffer bufGRTeeTime for GRTeeTime.
    
    do for bufGRTeeTime transaction:
        find first bufGRTeeTime exclusive-lock where bufGRTeeTime.ID = inpID.
        if available bufGRTeeTime then 
        do:
            assign  
                ix                   = ix + 1
                bufGRTeeTime.TeeTime = bufGRTeeTime.TeeTime + 86400.     
        end.
    end.
end procedure.    

procedure fixLinkedTime:
    define input parameter inpID as int64.
    define buffer bufGRTeeTime for GRTeeTime.
    
    do for bufGRTeeTime transaction:
        find first bufGRTeeTime exclusive-lock where bufGRTeeTime.ID = inpID.
        if available bufGRTeeTime then 
        do:
            assign  
                ix                      = iz + 1
                bufGRTeeTime.LinkedTime = bufGRTeeTime.LinkedTime - 86400.     
        end.
    end.
end procedure.  

procedure deleteTeeTime:
    define input parameter inpID as int64.
    define buffer bufGRTeeTime     for GRTeeTime.
    define buffer bufSearchCache for SearchCache.
    do for bufGRTeeTime transaction:
        find first bufGRTeeTime where bufGRTeeTime.ID = inpID.
        if available bufGRTeeTime then 
        do:
            if can-find(first TransactionDetail where sadetail.masterlinkid = GRTeeTime.ID and
                lookup(TransactionDetail.recordstatus,{&SaDetailDenied} + "," + {&SaDetailRemoved} + "," + 
                {&SaDetailCancel} + "," + {&SaDetailChange}) = 0) then return.
              
            find first SearchCache exclusive-lock where SearchCache.ParentRecord = GRTeeTime.ID no-error no-wait.
            if available SearchCache then delete sasearchindex.
              
            iy = iy + 1.
            delete grteetime.
        end.
    end.
end.