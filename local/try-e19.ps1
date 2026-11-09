param([switch]$Zen, [switch]$Keep)
# E19 (patch 65): the owner's own try of pinned splits. Opens the built browser (out\Default) on a FRESH copy of the
# smoke profile -- never the daily browser's profile -- with the made-up Arc file's 3 pinned splits seeded into Work the way
# the old import left them, as 6 loose pinned pages (e19-seed-splits.py, LOCAL.md 133), and a log for
# Claude to read afterwards. -Zen: zen mode, sidebar unpinned, as the daily browser runs. -Keep: the same copy again,
# not a fresh one (the restart step).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-e19.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-e19-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\e19-owner-run$(if ($Keep) { '-restart' }).log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (-not $Keep) {
  if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
  $null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
  Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
  & python "$PSScriptRoot\e19-seed-splits.py" $prof
  if ($LASTEXITCODE -ne 0) { Write-Host "Seeding the splits failed: tell Claude."; exit 1 }
  if ($Zen) { & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
} elseif (-not (Test-Path -LiteralPath $prof)) { Write-Host "No copy to keep: run without -Keep first."; exit 1 }
$env:HELIUM_ARC_SIDEBAR = "$ws\arc-made-up\StorableSidebar.json"  # the repair reads Arc's file: the made-up one (LOCAL.md 133)
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
if ($Keep) {
@"
The same test copy is opening again. Press Shift+Alt+2. PASS: every pinned split is still ONE row with two pages
(the renamed page keeps its name). Then close the test browser and tell Claude. The log is $log.
"@
  exit 0
}
@"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched). Press Shift+Alt+2
first: everything below happens in Work. A "pinned split" is ONE row of the pinned section that shows two pages
side by side -- an icon and a title on the left, another icon and title on the right.
 1. The repair -- look under Example D. PASS: 3 pinned splits, not 6 separate pinned pages. Two of them are the
    image pages of your "P" workspace.
 2. Open -- click the RIGHT page of the first pinned split. PASS: both pages open side by side (a split view), the
    right one in front; the row is highlighted.
 3. Close one page -- move the mouse over the row's LEFT page. PASS: an x shows at the left page's right end only;
    over the right page it moves there. Click the left page's x. PASS: the left page closes, the right one stays
    on screen alone, the row stays.
 4. Click the row's left page. PASS: it opens beside the right page again, one split view, the left page in front.
 5. Close both -- right-click the row > Close. PASS: both pages close; the row stays, not highlighted.
 6. Rename one page -- right-click the RIGHT page of the second pinned split > Rename, type Right one, Enter.
    PASS: only that page's title changes.
 7. Pin a Today split -- open two web pages as Today tabs (any two sites). With one in front, right-click the other
    Today tab > New split view with current tab. Drag that split (its Today row) up onto the pinned section.
    PASS: a blue line shows while dragging; let go and it is ONE new pinned split, and neither page is a Today tab.
 8. Unpin by key -- click a page of that new pinned split, press Shift+Alt+D. PASS: both pages go to the top of
    Today as one split view; the pinned split is gone from the section.
 9. Delete -- right-click the third pinned split > Delete, then Shift+Alt+H. PASS: its two pages are in the
    Archive, two entries.
10. Restart -- close the test browser, then run this script again with -Keep (step text printed then).
Then tell Claude which steps passed. The log is $log.
"@
