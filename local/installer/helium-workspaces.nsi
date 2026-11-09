; Helium Workspaces -- a per-user installer BESIDE official Helium (roadmap Phase 2, LOCAL.md 56).
; Never run makensis on this by hand: local/package-installer.py passes the defines:
;   VERSION      e.g. 1.21.157.00 (1.<Helium minor>.<Chromium major>.<fix on that base, 00 first>, the owner's scheme;
;                0.<Helium minor>.<Chromium major>.<patch count> before the first public one)
;   FILES_NSH    the generated File list (FILES.cfg's files from out/Default)
;   HERE         this folder (disclaimer.txt, initial_preferences)
;   ICON_FILE    the .ico
;   SIZE_KB      for Apps & features, and the free-space check
;   BUILT_FOR    "Helium 0.20.2.1 / Chromium 156.0.8078.73", read off chrome.dll (the licence page shows it)
;   OUTPUT_FILE  the setup .exe
; Everything it writes is its own: a folder, a profile folder, a shortcut and HKCU keys named
; HeliumWorkspaces. Since patch 95 the browser's own default folder is ${PROFILE} too (LOCAL.md 124);
; the --user-data-dir on every command below stays: a build from before 95 still needs it.

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WordFunc.nsh"
!include "Sections.nsh"

!define NAME       "Workspaces for Helium"
; The name before 1.X.X.00 (the owner, 2026-11-05): the program and data folders keep it, so an upgrade
; moves nothing and the taskbar pin keeps working; its shortcut and Default-apps entry are removed.
!define OLD_NAME   "Helium Workspaces"
!define KEY        "HeliumWorkspaces"
!define PROGID     "HeliumWorkspacesHTML"
!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${KEY}"
!define CLIENT_KEY "Software\Clients\StartMenuInternet\${KEY}"
; Fixed, never chosen: both the installer and the uninstaller delete this folder whole.
!define DIR        "$LOCALAPPDATA\Programs\${OLD_NAME}"
!define DATA       "$LOCALAPPDATA\${OLD_NAME}"
!define PROFILE    "${DATA}\User Data"
!define OPEN       '"$INSTDIR\chrome.exe" --user-data-dir="${PROFILE}"'

Name "${NAME} ${VERSION}"
OutFile "${OUTPUT_FILE}"
Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma
InstallDir "${DIR}"
ShowInstDetails show
ShowUninstDetails show

!define MUI_ICON "${ICON_FILE}"
!define MUI_UNICON "${ICON_FILE}"
!define MUI_ABORTWARNING
!define MUI_LICENSEPAGE_TEXT_TOP "Built on ${BUILT_FOR}."
!insertmacro MUI_PAGE_LICENSE "${HERE}\disclaimer.txt"
!insertmacro MUI_PAGE_INSTFILES
; "Run now", ticked (the owner's F6a, LOCAL.md 132): the Start menu shortcut, opened by Explorer -- so a setup
; someone ran as administrator never starts the browser elevated. A silent install shows no finish page.
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_FUNCTION RunNow
!define MUI_FINISHPAGE_RUN_TEXT "Open ${NAME} now"
!define MUI_FINISHPAGE_TEXT "Open it from the Start menu: ${NAME}.$\r$\n$\r$\nTo pin it to the taskbar: right-click it in the Start menu > Pin to taskbar (the safe way even if Show details lists $\"Taskbar id NOT set$\").$\r$\n$\r$\nTo make it your default browser: Windows Settings > Apps > Default apps > ${NAME}."
!insertmacro MUI_PAGE_FINISH

!define MUI_COMPONENTSPAGE_NODESC
!define MUI_COMPONENTSPAGE_TEXT_TOP "Your tabs, workspaces and sign-ins are kept unless you tick the second box."
!insertmacro MUI_UNPAGE_COMPONENTS
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; Refuse while this browser runs: Windows does not open a loaded chrome.dll for writing. A virus scan of
; a just-installed chrome.dll holds it too, for a moment (1.6 s here): try for 5 s before calling it open.
!macro RefuseWhileRunning
  ${If} ${FileExists} "${DIR}\chrome.dll"
    StrCpy $1 0
    ${Do}
      ClearErrors
      FileOpen $0 "${DIR}\chrome.dll" a
      ${IfNot} ${Errors}
        FileClose $0
        ${Break}
      ${EndIf}
      IntOp $1 $1 + 1
      ${If} $1 >= 20
        MessageBox MB_ICONSTOP "${NAME} is open. Close it (its menu > More tools > Exit), then run this again." /SD IDOK
        SetErrorLevel 2
        Quit
      ${EndIf}
      Sleep 250
    ${Loop}
  ${EndIf}
!macroend

Function RunNow
  Exec '"$WINDIR\explorer.exe" "$SMPROGRAMS\${NAME}.lnk"'
FunctionEnd

Function .onInit
  StrCpy $INSTDIR "${DIR}"  ; a /D= on the command line must not move the folder deleted whole below
  ; An older setup over a newer install asks first (LOCAL.md 124). No, and a silent run, quit with 3
  ; (2 = the browser is open, 4 = too little space, below).
  ReadRegStr $0 HKCU "${UNINST_KEY}" "DisplayVersion"
  ${If} $0 != ""
    ${VersionCompare} $0 "${VERSION}" $1  ; 1 = the installed one is newer
    ${If} $1 == 1
      MessageBox MB_YESNO|MB_ICONEXCLAMATION|MB_DEFBUTTON2 "${NAME} $0 is installed, and this setup is the older ${VERSION}. An older version may not read everything a newer one saved: back up first.$\r$\n$\r$\nInstall the older version anyway?" /SD IDNO IDYES older_ok
      SetErrorLevel 3
      Quit
      older_ok:
    ${EndIf}
  ${EndIf}
  !insertmacro RefuseWhileRunning
  ; Room first (LOCAL.md 127): twice the program's size, a margin, less the old version's folder, which is deleted
  ; before the new files are written. In MB, as LogicLib compares 32-bit numbers. A drive it cannot read is not
  ; refused; no old folder counts 0.
  ${GetSize} "$INSTDIR" "/S=0K /G=1" $3 $4 $5
  ${GetRoot} "$INSTDIR" $0
  ClearErrors
  ${DriveSpace} "$0\" "/D=F /S=M" $1
  IntOp $2 ${SIZE_KB} * 2
  IntOp $2 $2 - $3
  IntOp $2 $2 / 1024
  ${IfNot} ${Errors}
  ${AndIf} $1 < $2
    MessageBox MB_ICONSTOP "${NAME} needs $2 MB free on $0, which has $1 MB. Free some space, then run this again." /SD IDOK
    SetErrorLevel 4
    Quit
  ${EndIf}
FunctionEnd

Section
  !insertmacro RefuseWhileRunning  ; again: the browser may have been opened while the licence page was shown
  RMDir /r "$INSTDIR"  ; an older version's files
  SetOutPath "$INSTDIR"
  ; Before the files: a copy that stops halfway (a full disk, a virus scanner) can still be uninstalled.
  WriteUninstaller "$INSTDIR\uninstall.exe"
  !include "${FILES_NSH}"
  SetOutPath "$INSTDIR"
  ; Chromium reads it on a NEW profile's first run only: vertical layout (the rail needs it) and
  ; "Continue where you left off", written signed. A copied profile ignores it.
  File "${HERE}\initial_preferences"
  CreateShortCut "$SMPROGRAMS\${NAME}.lnk" "$INSTDIR\chrome.exe" '--user-data-dir="${PROFILE}"' "$INSTDIR\chrome.exe" 0
  Delete "$SMPROGRAMS\${OLD_NAME}.lnk"  ; an older version's
  ; The window's taskbar id on the shortcut: "Pin to taskbar" on the running window then pins this
  ; shortcut, --user-data-dir included, not the bare chrome.exe (official Helium's profile, 2026-10-12).
  ; A failure costs only that; the install goes on. A PowerShell silent for 60 s is ended ("timeout").
  InitPluginsDir
  File "/oname=$PLUGINSDIR\set-taskbar-id.ps1" "${HERE}\set-taskbar-id.ps1"
  nsExec::ExecToLog /TIMEOUT=60000 '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$PLUGINSDIR\set-taskbar-id.ps1" -Lnk "$SMPROGRAMS\${NAME}.lnk" -UserDataDir "${PROFILE}"'
  Pop $0
  ${If} $0 != 0
    DetailPrint "Taskbar id NOT set ($0): pin ${NAME} from the Start menu, never from its running window."
  ${EndIf}

  WriteRegStr   HKCU "${UNINST_KEY}" "DisplayName" "${NAME}"
  WriteRegStr   HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr   HKCU "${UNINST_KEY}" "Publisher" "unofficial, self-built"
  WriteRegStr   HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\chrome.exe,0"
  WriteRegStr   HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr   HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr   HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" ${SIZE_KB}

  ; A browser Windows can pick in Settings > Apps > Default apps. Nothing changes until the user
  ; picks it. --single-argument: what Windows hands over is one URL or file, never more switches.
  WriteRegStr HKCU "Software\Classes\${PROGID}" "" "${NAME} Document"
  WriteRegStr HKCU "Software\Classes\${PROGID}" "URL Protocol" ""
  WriteRegStr HKCU "Software\Classes\${PROGID}\DefaultIcon" "" "$INSTDIR\chrome.exe,0"
  ; The name Open with and Default apps show: without it Windows takes chrome.exe's own, "Helium",
  ; the same as official Helium's (the owner's check, 2026-09-30).
  WriteRegStr HKCU "Software\Classes\${PROGID}\Application" "ApplicationName" "${NAME}"
  WriteRegStr HKCU "Software\Classes\${PROGID}\shell\open\command" "" '${OPEN} --single-argument %1'
  WriteRegStr HKCU "${CLIENT_KEY}" "" "${NAME}"
  WriteRegStr HKCU "${CLIENT_KEY}\DefaultIcon" "" "$INSTDIR\chrome.exe,0"
  WriteRegStr HKCU "${CLIENT_KEY}\shell\open\command" "" '${OPEN}'
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities" "ApplicationName" "${NAME}"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities" "ApplicationDescription" "Arc-style workspaces for Helium"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities" "ApplicationIcon" "$INSTDIR\chrome.exe,0"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities\StartMenu" "StartMenuInternet" "${KEY}"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities\URLAssociations" "http" "${PROGID}"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities\URLAssociations" "https" "${PROGID}"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities\FileAssociations" ".htm" "${PROGID}"
  WriteRegStr HKCU "${CLIENT_KEY}\Capabilities\FileAssociations" ".html" "${PROGID}"
  DeleteRegValue HKCU "Software\RegisteredApplications" "${OLD_NAME}"  ; an older version's
  WriteRegStr HKCU "Software\RegisteredApplications" "${NAME}" "${CLIENT_KEY}\Capabilities"
  WriteRegStr HKCU "Software\Classes\.htm\OpenWithProgids" "${PROGID}" ""
  WriteRegStr HKCU "Software\Classes\.html\OpenWithProgids" "${PROGID}" ""
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'  ; SHCNE_ASSOCCHANGED
SectionEnd

Section "un.${NAME} (the program)"
  SectionIn RO
  !insertmacro RefuseWhileRunning  ; again: the browser may have been opened while the first page was shown
  Delete "$SMPROGRAMS\${NAME}.lnk"
  Delete "$SMPROGRAMS\${OLD_NAME}.lnk"
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "${CLIENT_KEY}"
  DeleteRegKey HKCU "Software\Classes\${PROGID}"
  DeleteRegValue HKCU "Software\RegisteredApplications" "${NAME}"
  DeleteRegValue HKCU "Software\RegisteredApplications" "${OLD_NAME}"
  DeleteRegValue HKCU "Software\Classes\.htm\OpenWithProgids" "${PROGID}"
  DeleteRegValue HKCU "Software\Classes\.html\OpenWithProgids" "${PROGID}"
  System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
  RMDir /r "$INSTDIR"
SectionEnd

Section /o "un.Also delete my ${NAME} data (tabs, workspaces, history, sign-ins)" UnData
  ; Chrome holds the lockfile open while any browser uses the profile, so it will not delete.
  Delete "${PROFILE}\lockfile"
  ${If} ${FileExists} "${PROFILE}\lockfile"
    MessageBox MB_ICONEXCLAMATION "Your data was KEPT: a browser is still using ${PROFILE}." /SD IDOK
  ${Else}
    RMDir /r "${DATA}"
    ; Another program (Explorer, a backup or sync tool, a virus scan) may hold a file: say what is left.
    ${If} ${FileExists} "${DATA}\*.*"
      MessageBox MB_ICONEXCLAMATION "Some of your data could not be deleted, as another program was using it. Delete the rest yourself: ${DATA}" /SD IDOK
    ${EndIf}
  ${EndIf}
SectionEnd

Function un.onInit
  ; The uninstaller deletes $INSTDIR whole: a copy of it run from anywhere else does nothing.
  ${If} $INSTDIR != "${DIR}"
    MessageBox MB_ICONSTOP "This uninstaller only removes ${DIR}." /SD IDOK
    SetErrorLevel 2
    Quit
  ${EndIf}
  !insertmacro RefuseWhileRunning
  ; /DELETEDATA ticks the second box from the command line: a silent uninstall has no screen to tick it on.
  ${un.GetParameters} $1
  ClearErrors
  ${un.GetOptions} $1 "/DELETEDATA" $2
  ${IfNot} ${Errors}
    SectionSetFlags ${UnData} ${SF_SELECTED}
  ${EndIf}
FunctionEnd
