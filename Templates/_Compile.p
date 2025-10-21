/************************************************************

       COMPILE PROGRAM THAT WILL UPDATE THE RESULTING
       FILENAME WITH THE PROGRESS AND RECTRAC VERSIONS

- To use this program, replace the cProgramName with the name of your .p
- Update the cFileLocation and cCompileLocation for your file system
- Copy all text and paste it in a scratchpad (make sure to change your AVM to RecTrac_3.1)
- Run from the scratchpad to avoid the need to run a full build of RecTrac
- If your .p doesn't syntax check, this will throw an error with the issue and halt
- This can be run for 11.7 or 12.8 and will append your filename accordingly based on where you run it from

************************************************************/

define variable cProgramName     as character no-undo.
define variable cVersions        as character no-undo.
define variable cOriginalDotR    as character no-undo.
define variable cNewDotR         as character no-undo.
define variable cFileLocation    as character no-undo.
define variable cCompileLocation as character no-undo.
define variable ProgressVersion  as character no-undo.
define variable iFirstDot        as integer   no-undo.
define variable iSecondDot       as integer   no-undo.
define variable RecTracVersion   as character no-undo.
define variable isDarbyFix       as logical   no-undo.
define variable isDaveFix        as logical   no-undo.
define variable isRecTracProgram as logical   no-undo.
define variable MichaelLocation  as character no-undo.
define variable DarbyLocation    as character no-undo.
define variable DaveLocation     as character no-undo.

find first VSIVersion no-lock where VSIVersion.ProductName = "RecTracVersion" no-error no-wait.
if available VSIVersion then assign RecTracVersion = VSIVersion.ProductVersion.

assign
    isDarbyFix       = false
    isDaveFix        = false
    isRecTracProgram = false
    cProgramName     = "purgeSAAddressRecordsWithNoHouseholdLink.p" /* INCLUDE THE EXTENTION (.P, .CLS, .I, ETC) */
    cCompileLocation = "C:~\Users~\michaelzr~\OneDrive - Vermont Systems~\Documents~\Quick Fixes~\Compiled~\"
    ProgressVersion  = string(proversion(1)).
        
/* Find the position of the first and second dots */
iFirstDot = index(ProgressVersion, ".", 1).
iSecondDot = index(ProgressVersion, ".", iFirstDot + 1). /* Search for the second dot after the first one */

/* Extract the substring between the first and second dots (this will give you the major.minor) */
ProgressVersion = replace(substring(ProgressVersion, 1, iSecondDot - 1),".","").
    
iFirstDot = index(RecTracVersion,".", 1).
iSecondDot = index(RecTracVersion,".",iFirstDot + 1).
    
RecTracVersion = replace(substring(RecTracVersion,iSecondDot,index(RecTracVersion,".",iSecondDot + 1)),".","").

cVersions = "_" + ProgressVersion + "_" + RecTracVersion.

if isDarbyFix then assign cFileLocation = "C:~\Users~\michaelzr~\OneDrive - Vermont Systems\Quickies~\Darby's Quick Fixes and In-Progress~\".
else if isDaveFix then assign cFileLocation = "C:~\Users~\michaelzr~\OneDrive - Vermont Systems~\Quickies~\Dave B Quick Fixes~\".
    else if isRecTracProgram then assign cFileLocation = (if ProgressVersion = "117" then "C:~\Workspace~\RecTrac_3.1~\RecTrac~\" else "C:~\Workspace_125~\RecTrac_3.1~\RecTrac~\").
        else assign cFileLocation = "C:~\Users~\michaelzr~\OneDrive - Vermont Systems~\Documents~\Quick Fixes~\Michael's Quickies~\".

if index(cProgramName,"~\") > 0 then 
    os-create-dir value(cCompileLocation + substring(cProgramName,1,r-index(cProgramName,"~\"))).

/* Compile the program and save into the cCompileLocation */
compile VALUE(cFileLocation + cProgramName) save into VALUE(cCompileLocation + (if index(cProgramName,"~\") > 0 then substring(cProgramName,1,r-index(cProgramName,"~\")) else "")) no-error.
if compiler:error then 
do:
    message "Compilation error for program file: " skip
        cFileLocation + cProgramName skip 
        "at line:" compiler:error-row skip(1)
        "Error Message:" skip
        error-status:get-message(1)  /* Get the most recent error message */
        view-as alert-box.
    return.
end.

/* Construct the original and new filenames in the cCompileLocation */
assign
    cOriginalDotR = cCompileLocation + substring(cProgramName,1,r-index(cProgramName,".") - 1) + ".r"
    cNewDotR      = cCompileLocation + substring(cProgramName,1,r-index(cProgramName,".") - 1) + cVersions + ".r".

os-delete value(cNewDotR) no-error no-wait.

/* Rename the compiled file in the cCompileLocation */
os-rename VALUE(cOriginalDotR) VALUE(cNewDotR).

message "Finished Compiling program file:" skip 
    substring(cProgramName,r-index(cProgramName,"~\") + 1) ">>>" substring(cNewDotR,r-index(cNewDotR,"~\") + 1) skip(1)
    "From file location:" skip
    cFileLocation + (if index(cProgramName,"~\") > 0 then substring(cProgramName,1,r-index(cProgramName,"~\")) else "") skip(1)
    "Saved to:" skip
    cCompileLocation + (if index(cProgramName,"~\") > 0 then substring(cProgramName,1,r-index(cProgramName,"~\")) else "") view-as alert-box.
