param([switch]$DryRun)
# C29 (patch 83): the owner's own try. Opens the built browser (out\Default) on a FRESH copy of the smoke profile --
# never the daily browser's profile -- with three extra pinned pages ("Extra 1", "Extra 2", "Extra 3") added at the end of
# Home, the sidebar 280 wide (all five workspace chips drawn) and the toolbar's own New Tab button off. A log is written for
# Claude to read afterwards. It prints the preconditions it checked, what to do, and what a pass looks like.
# -DryRun: makes and checks the copy, prints the same, starts nothing.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c29.ps1
$ws   = "<local-path>\Helium-workspace"
$bin  = "$ws\helium-windows\build\src\out\Default"
$exe  = "$bin\chrome.exe"
$prof = "$ws\testprofile-c29-owner"
$log  = "$ws\c29-owner-run.log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
foreach ($s in @("pins: dragging ", "selected row(s)", "pins: selection cleared")) {
    & python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -ne 0) { Write-Host "This build has no C29 yet (no '$s' in out\Default\chrome.dll): tell Claude."; exit 1 }
}
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $log -EA SilentlyContinue
& python -I -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); d['workspaces']['default'] += [{'type':'item','id':'x%d'%i,'title':'Extra %d'%i,'url':'https://example.com/?extra=%d'%i} for i in (1,2,3)]; open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins"
$ok1 = $LASTEXITCODE -eq 0
& python -I "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null
if (-not $ok1 -or $LASTEXITCODE -ne 0) { Write-Host "Could not seed the copy of the profile: tell Claude."; exit 1 }
# The three things the feature rests on, read back from the copy (a classic layout or Workspaces off draws no pinned section).
Write-Host "Preconditions, read from the copy:" -ForegroundColor Cyan
& python "$PSScriptRoot\set-workspaces-pref.py" $prof --show
if ($LASTEXITCODE -ne 0) { Write-Host "The copy cannot answer: tell Claude."; exit 1 }
$rows = & python -I -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); print(', '.join(r['title'] or r['id'] for r in d['workspaces']['default']))" "$prof\Default\Workspace Pins"
Write-Host "Home's pinned rows in the copy: $rows"
if ($DryRun) { Write-Host "(dry run: nothing started)"; exit 0 }
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
@"

The test browser is opening (a copy of the smoke profile; your daily browser is not touched). It opens on HOME. In Home the
pinned pages are: Example A, "Smoke folder" (open: Wikipedia and a GitHub page), "Closed folder" (Hidden), Example D,
Extra 1, Extra 2, Extra 3. The five workspaces sit at the bottom of the sidebar: Home, Work, Canary, Private, Unpin.
"Filled" = a soft coloured box behind the pinned page. Do the steps in order; step 9 is the only one that deletes.

 1. Ctrl+click Example A, then Ctrl+click Example D.
    PASS: both are filled; neither page opens (no new tab, no x on them). Ctrl+click Example D again: its fill goes, A's stays.
 2. Ctrl+click Extra 1, then Shift+click Extra 3.
    PASS: Extra 1, 2 and 3 are filled; Example A is NOT any more (Shift alone replaces). Press Esc: nothing is filled.
 3. Ctrl+click "Smoke folder", then Shift+click "Closed folder".
    PASS: the folder, Wikipedia, the GitHub page and "Closed folder" are all filled (the rows between them). Esc.
 4. Ctrl+click Extra 1 and Extra 2, then right-click Extra 2.
    PASS: the menu offers Unpin, Move to workspace and Delete -- no Rename, no New folder. Choose Move to workspace > Work.
    Both leave Home. Click the Work chip: Extra 1 then Extra 2 are at the END of Work's pinned pages. Click Home again.
 5. Ctrl+click Example A and Example D. Drag Example A onto the MIDDLE of "Closed folder" and let go.
    PASS: both go into the folder; open it: Example A, Example D, then Hidden (first inside, in that order).
 6. Ctrl+click Wikipedia. Then drag Extra 3 (it is NOT filled) up to the top edge of Example A -- a thin line shows where it
    will land -- and let go.
    PASS: only Extra 3 moves, to just above Example A; Wikipedia's fill goes.
 7. Ctrl+click Wikipedia and the GitHub page, drag Wikipedia down onto the Today tab(s) below the line and let go.
    PASS: both become Today tabs, Wikipedia above GitHub, and their pinned pages leave the folder. They are not loaded
    (no spinner) until you click one.
 8. Ctrl+click Example A and Example D (inside the open "Closed folder"), drag Example A onto the "Canary" chip
    at the bottom; the chip lights while you hold it. Let go.
    PASS: both leave Home. Click the Canary chip: Example A then Example D are at the end of its pinned pages.
 9. In Home, Ctrl+click "Smoke folder" and "Closed folder" (two top-level rows -- a page inside a selected folder counts as
    part of that folder), right-click one > Delete.
    PASS: a box asks "Delete the 2 selected rows?". Cancel: nothing is deleted. Do it again > Delete: both go. (Their pages
    go to the Archive, Shift+Alt+H, for 60 days.)

Then close the test browser and tell Claude which steps passed (or what you saw). The log is $log.
"@
