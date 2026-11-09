param([switch]$Zen)
# C2 + C1 (patches 63, 64): the owner's own try of Ctrl+Tab and the quick search box. Opens the built browser
# (out\Default) on a FRESH copy of the smoke profile -- never the daily browser's profile -- with "Cycle through tabs
# in most recently used order" ON (helium.browser.mru_tab_cycling, as on the daily browser) and a log for Claude to
# read afterwards, and prints what to do and what a pass looks like. -Zen: zen mode, sidebar unpinned, as the daily
# browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c2.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-c2-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\c2-owner-run.log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$set = @("helium.browser.mru_tab_cycling=true")
if ($Zen) { $set += "helium.browser.zen_mode=true", "helium.browser.zen_mode_sidebar_pinned=false" }
& python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" @set | Out-Null
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
@"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched). Ctrl+Tab goes in
most recently used order, as on your daily browser. A PINNED PAGE is an entry above the thin line; a TODAY TAB is an
ordinary tab below it. Press Shift+Alt+2 first: everything starts in Work.
 1. Open two web pages (Today tabs). Click the pinned page "Example A" (its page opens), then click a Today tab.
    Press Ctrl+Tab once. PASS: Example A's page shows and its pinned page is highlighted. Ctrl+Tab again: back to
    that Today tab.
 2. Hold Ctrl and press Tab, then W, then Tab, then let go of Ctrl. PASS: the first Tab showed the page you were on
    before; W closed it and another page showed; the second Tab moved on to the page you used before that one;
    nothing froze or crashed.
 3. Shift+Alt+3 (Canary): open a web page there and pin it with Shift+Alt+D; open one more web page there
    and leave it as a Today tab. Shift+Alt+2 (back to Work).
 4. Click the pinned page "Example A" (step 2 closed its page; it opens again), then click a Today tab, then
    Shift+Alt+F. PASS: a box opens in the MIDDLE of the page, the cursor in its "Find tabs and pages" field. Before you
    type, it lists Work's recent tabs under "Recent tabs": Example A's page is there (it is open), the page in front
    is not, and a pinned page whose page is closed (Example D) is not.
 5. Type a few letters of the page you pinned in Canary. PASS: it is listed under "Pinned pages", with
    its page's icon at the left and a coloured dot and "Canary" at the right. Press Enter: the window
    switches to Canary and that page shows. Then press Ctrl+W (the page closes; its pinned page stays),
    Shift+Alt+2, Shift+Alt+F, type the same letters, Enter. PASS: the window switches to Canary and the
    page opens again.
 6. Shift+Alt+2, Shift+Alt+F, type a few letters of the Today tab you left in Canary. PASS: it is under
    "Open tabs"; Enter switches to Canary and shows it.
 7. Shift+Alt+F, type "closed folder". PASS: "Hidden" (the page inside "Closed folder") is under "Pinned pages".
    Up / Down move the highlight and stop at the ends. Escape: the box closes.
 8. Close a Today tab with Ctrl+W, then Shift+Alt+F and type a few letters of its name. PASS: it is under
    "Archived"; Enter brings it back as a Today tab. Shift+Alt+F and the same letters again: now it is under
    "Open tabs" and no longer under "Archived".
 9. Shift+Alt+F twice. PASS: the second press closes the box.
Then close the test browser and tell Claude which steps passed. The log is $log.
"@
