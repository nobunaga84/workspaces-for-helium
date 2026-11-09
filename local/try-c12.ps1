param([switch]$Zen)
# C12 + C30 + C24 + C26 (patch 62): the owner's own try. Opens the built browser (out\Default) on a FRESH copy of the
# smoke profile -- never the daily browser's profile -- with a log for Claude to read afterwards, and prints what to
# do and what a pass looks like. -Zen: zen mode, sidebar unpinned, as the daily browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c12.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-c12-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\c12-owner-run.log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
if ($Zen) { & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
@"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched). Press Shift+Alt+2
first: everything below happens in Work. Its pinned pages: Example A, "Smoke folder" (open), "Closed folder", Example D.
 1. C12 -- open "Closed folder", click its page "Hidden", close the folder again. PASS: "Hidden" still shows,
    indented under the closed folder (you are on it). Click any Today tab: it goes. Right-click it while it shows:
    the menu has "Close page" and no "New folder".
 2. C26 -- click "Example A" (its page opens). PASS: its x shows only while the mouse is over its row; the row's
    title and its back arrow (if any) never move. Right-click it: "Close page" is in the menu and closes it.
 3. C30 -- right-click "Example D" > Delete, then Shift+Alt+H. PASS: "Example D" is in the Archive; clicking it
    reopens it as a Today tab. Right-click "Smoke folder" > Delete folder: the box says its pages go to the
    Archive; after Delete folder, both its pages are in the Archive.
 4. C24 -- Shift+Alt+S (a new, empty workspace), open any web page there, drag its tab up onto the workspace's
    name at the top of the section. PASS: a blue line shows under the name while dragging; let go and the page
    is that workspace's first pinned page.
Then close the test browser and tell Claude which steps passed. The log is $log.
"@
