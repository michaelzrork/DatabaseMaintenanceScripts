/*------------------------------------------------------------------------
    File        : exportPhotos.p
    Purpose     : 

    Syntax      : 

    Description : Export Member Photos to Server

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

define variable recNum               as integer   no-undo.
define variable FileExt              as character no-undo.
define variable FilePath             as character no-undo.
define variable URLName              as character no-undo.
define variable personName           as character no-undo.
define variable specialCharacterList as character no-undo.
define variable ixSpecialCharList    as integer   no-undo.

assign
    FileExt              = ""
    FilePath             = ""
    personName           = ""
    specialCharacterList = " ,',~!,~~,`,#,$,%,^,&,*,~(,~),_,-,=,+,~[,~],~\,~{,~},|,~:,~;,~",~<,~>,~?,~/"
    ixSpecialCharList    = 0
    recNum               = 0.

/*************************************************************************
                                MAIN BLOCK
*************************************************************************/

os-create-dir value(sessionTemp() + "PhotoExport\").

for each Member no-lock where Member.PhotoIDNumber <> 0:
    personName = replace(Member.FirstName + Member.LastName,",","").
    // STRIP ANY SPECIAL CHARACTERS IN THE RESULTING EMAIL ADDRESS
    do ixSpecialCharList = 1 to num-entries(specialCharacterList):
        personName = replace(personName,entry(ixSpecialCharList,specialCharacterList),"").
    end.
    // ORIGINAL METHOD
    // USING THIS WILL ALLOW YOU TO CHANGE THE FILE NAME ON EXPORT TO INCLUDE THE SAPERSON ID AND/OR NAME
    for first BinaryFile no-lock where BinaryFile.RecordType = "photos" and BinaryFile.FileName = "\photos\" + string(Member.PhotoIDNumber) + ".jpg":
        run CleanFileName(entry(num-entries(BinaryFile.filename,"\"),sablobfile.filename,"\"), output URLName).
        assign
            FileExt  = GetFileExtension(BinaryFile.FileName)
            FilePath = sessionTemp() + "PhotoExport\" /*+ string(Member.ID) + "_" +*/ + personName + "_" + URLName.
        copy-lob from BinaryFile.BlobFile to file (FilePath).
    end.
    // OFFICIAL METHOD       
/*    for first BinaryFile no-lock where BinaryFile.RecordType = "photos" and BinaryFile.FileName = "\photos\" + string(Member.PhotoIDNumber) + ".jpg":*/
/*        CreateFile(BinaryFile.FileName,false,sessionTemp() + "MemberPhotoExport\",true,no) no-error.                                                   */
/*    end.                                                                                                                                               */
     
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
            bufActivityLog.SourceProgram = "exportPhotos.r"
            bufActivityLog.LogDate       = today
            bufActivityLog.LogTime       = time
            bufActivityLog.UserName      = "SYSTEM"
            bufActivityLog.Detail1       = "Export Member Photos to Server"
            bufActivityLog.Detail2       = "Exported records can be found on the server at: " + sessionTemp() + "PhotoExport\".
    end.
end procedure.