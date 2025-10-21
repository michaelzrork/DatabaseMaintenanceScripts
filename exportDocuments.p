/*------------------------------------------------------------------------
    File        : exportDocuments.p
    Purpose     : 

    Syntax      : 

    Description : Export Documents to Server

    Author(s)   : michaelzrork
    Created     : 
    Notes       : 
  ----------------------------------------------------------------------*/

/*************************************************************************
                                DEFINITIONS
*************************************************************************/

{Includes/Framework.i}
{Includes/BusinessLogic.i}
{Includes/ProcessingConfig.i} 
{Includes/InterfaceData.i}

define variable recNum         as integer   no-undo.
define variable FileExt        as character no-undo.
define variable FilePath       as character no-undo.
define variable URLName        as character no-undo.
define variable fileToDownload as character no-undo.

assign
    FileExt  = ""
    FilePath = ""
    recNum   = 0.
    // fileToDownload       = "\Reports\Rental Detail Status Change 20241008-57604.pdf".
    // fileToDownload       = "\Reports\ZZZ\10-11-2024\RecConnect Labels  1-07-30 pm.pdf".

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

os-create-dir value(sessionTemp() + "DocumentExport\").

for each BinaryFile no-lock where BinaryFile.FileName = "\Household Documents\10630251\CallowayQuinea102823SSRC-PRR.pdf":
    run CleanFileName(entry(num-entries(BinaryFile.filename,"\"),sablobfile.filename,"\"), output URLName).
    assign
        FileExt  = GetFileExtension(BinaryFile.FileName)
        FilePath = sessionTemp() + "DocumentExport\" + URLName
        recNum   = recNum + 1.
    copy-lob from BinaryFile.BlobFile to file (FilePath).
end.

run ActivityLog.

/*************************************************************************
                            INTERNAL PROCEDURES
*************************************************************************/

procedure CleanFileName:
    def input param cFileName as char no-undo.
    def output param cFixedName as char no-undo.
  
    def var FileExt  as char no-undo.
    def var charlist as char no-undo init "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_".
    def var ix       as int  no-undo.

    if isEmpty(cFileName) then return.
  
    assign
        FileExt   = GetFileExtension(cFileName)
        cFileName = replace(replace(replace(replace(cFileName," ","_"),chr(10),""),chr(13),""),"#","")
        cFileName = if not isEmpty(FileExt) then replace(cFileName,"." + FileExt,"") else cFileName.
  
    do ix = 1 to length(cFileName):
        if index(charlist, substring(cFileName,ix,1)) gt 0 then 
            cFixedName = cFixedName + substring(cFileName,ix,1).
    end.
  
    if not isEmpty(FileExt) then 
        cFixedName = cFixedName + "." + FileExt.
end procedure.

// CREATE AUDIT LOG ENTRY DISPLAYING HOW MANY RECORDS WERE CHANGED
procedure ActivityLog:
    def buffer bufActivityLog for ActivityLog.
    do for bufActivityLog transaction:
        create bufActivityLog.
        assign
            bufActivityLog.SourceProgram = "exportDocuments.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Export Documents to Server"
            bufActivityLog.Detail2       = "Exported records can be found on the server at: " + sessionTemp() + "DocumentExport\"
            bufActivityLog.Detail3       = "Documents Exported: " + string(recNum).
    end.
end procedure.