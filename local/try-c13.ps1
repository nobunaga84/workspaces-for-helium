param([switch]$Zen)
# C13 + C22 a-c (patch 61): the owner's own try of the new keys. Opens the built browser (out\Default) on a FRESH copy
# of the smoke profile (Home, Work, Canary, Private, Unpin) -- never the daily browser's profile -- with a log
# for Claude to read afterwards, and prints what to press and what a pass looks like. -Zen: zen mode, sidebar
# unpinned, as the daily browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c13.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-c13-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\c13-owner-run.log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
if ($Zen) { & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
@"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched).
Press each, in the test browser:
 1. Shift+Alt+2  -> Work is shown.          Shift+Alt+1 -> Home.
 2. Shift+Alt+0  -> back to Work.           Shift+Alt+0 again -> back to Home.
 3. Shift+Alt+3  -> Canary.         Shift+Alt+6 -> nothing (there are 5 workspaces).
 4. In Work, open any web page (a Today tab). Shift+Alt+D -> it becomes a pinned page at the END of Work's pinned
    pages, still open. Shift+Alt+D again -> it is a Today tab again, at the TOP of the list.
 5. Open two or three more web pages, pin one with Shift+Alt+D. Shift+Alt+K -> every Today tab closes; the pinned
    page you pinned stays open. Ctrl+Shift+T brings a closed one back.
 6. Shift+Alt+H -> the Archive opens in the MIDDLE of the page (not by the bar); the tabs from step 5 are in it.
    Escape closes it.
 7. Settings > System > Keyboard shortcuts: "Workspace 1".."Workspace 9", "Back to the last workspace",
    "Pin or unpin this page", "Clear Today", "Open the Archive" are listed with their keys.
Then close the test browser and tell Claude which steps passed. The log is $log.
"@
