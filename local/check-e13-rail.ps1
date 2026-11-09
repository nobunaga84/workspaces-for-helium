# historical (pre-E17): E17a moved Archive to the bar's own button; the "+" menu is New tab / New workspace / Tab search / Import from Arc
param([string]$Log = "<local-path>\Helium-workspace\e13-rail-run.log", [switch]$GradeOnly)
# E13 patches 29 + 30 (LOCAL.md 34): the rail as the owner designed it --  < [workspaces] > +
# -- and (30) renaming a tab you are not on brings it to the front with its rename box.
# The workspace buttons slide (mouse wheel, arrows) instead of overflowing the strip, "+" opens
# New tab / New workspace / Tab search, and Helium's own new tab button is hidden while the rail
# is shown. Layout is owner-observed; the actions behind it are log-graded, each window bounded
# by an event the browser logged (LOCAL.md 30). -GradeOnly re-grades an existing log.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\29-rail-scroll.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no $live" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
foreach ($f in 'workspace_rail_view\.cc','workspace_rail_view\.h','vertical_tab_strip_bottom_container\.cc','generated_resources\.grd') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f -- an edit was not quilt-added (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
$live30 = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\30-rename-background-tab.patch"
if (-not (Test-Path $live30) -or (Get-Item $exe).LastWriteTime -lt (Get-Item $live30).LastWriteTime) { Write-Host "ABORT: no 30, or chrome.exe older than it (stale binary)" -ForegroundColor Red; exit 1 }
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
$count = @((Get-Content "$prof\Default\Preferences" -Raw | ConvertFrom-Json).helium.workspaces.list.items).Count
if ($count -lt 5) { Write-Host "ABORT: $count workspaces; the overflow needs at least 5 to show at the narrowest strip" -ForegroundColor Red; exit 1 }

if (-not $GradeOnly) {
Remove-Item $Log -EA SilentlyContinue
Write-Host @"

E13 RAIL -- $count workspaces. Every step says which workspace you are IN.

  1. [Home]  drag the tab strip's right edge LEFT as far as it goes (narrowest).
             EXPECT: the bottom row reads   <  [workspace buttons]  >  +
             Nothing is cut off at the left. There is NO separate "New tab" button.
  2. [Home]  point at the workspace buttons and roll the mouse wheel.
             EXPECT: the buttons slide sideways. The arrows go grey at each end.
  3. [Home]  click  >  until it is grey, then  <  until it is grey.
             EXPECT: one button per click; the last workspace, then Home, fully shown.
  4. [Home]  click  + .  EXPECT a menu: New tab / New workspace / Tab search.
             Click "New tab".  EXPECT: a new tab opens here, in Home.
  5. [Home]  +  -> "Tab search".  EXPECT: the tab search panel opens. Press Esc.
  6. [Home]  +  -> "New workspace", type  TEST , OK.
             EXPECT: you are now IN the new workspace: a button "T" at the end of the
             rail, lit up and slid into view, and a fresh tab.
      [TEST] right-click T -> "Delete workspace".
             EXPECT: T is gone, and you land in the workspace before it.
 6b. [any]   click HOME in the rail. Ctrl+T  https://example.org , then Ctrl+T
             https://www.iana.org  (so Example Domain is a tab you are NOT on).
      [Home] right-click Example Domain -> "Rename tab...".
             EXPECT: that tab comes to the front AND the rename box appears at once
             (patch 30). Type  DELTA , OK.
  7. [Home]  press Shift+Alt+Right  4 times, slowly.
             EXPECT: the lit-up button moves one along each time and ALWAYS stays in
             view -- the rail slides to follow it.
  8. [any]   collapse the tab strip (its collapse button at the top), look, expand it.
             EXPECT while collapsed: a column of workspace buttons, + at the bottom,
             no arrows, no separate New tab button.
  9. [any]   +  -> New tab, go to  helium://settings/appearance , turn Workspaces OFF.
             EXPECT: the rail disappears and Helium's own "New tab" button is back.
             Turn Workspaces ON again.  EXPECT: the rail is back, the New tab button
             hidden again. (The settings tab may vanish into another workspace -- fine.)
 10. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
}
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""

# Every window below is bounded by a logged event, never by a line count (LOCAL.md 30), and each
# step grades the line its own action writes: the startup can insert tabs of its own (Chromium
# reopens pinned tabs), so "an insert happened" proves nothing about the + menu (E13 review).
$from = { param($pattern, $start) @($start..([Math]::Max($w.Count - 1, 0)) | Where-Object { $_ -lt $w.Count -and $w[$_] -match $pattern } | Select-Object -First 1) }
$between = { param($a, $b) if ($b - $a -gt 1) { @($w[($a + 1)..($b - 1)]) } else { @() } }
$newTab  = & $from "rail \+ menu: new tab" 0
$search  = & $from "rail \+ menu: tab search" 0
$newWs   = & $from "rail \+ menu: new workspace" 0
$created = & $from "created workspace '([0-9a-f-]+)'" 0
$front   = & $from "rename dialog at index \d+, brought to front" 0
$delta   = & $from "custom title at index \d+ -> 'DELTA'" 0
$off     = & $from "enabled pref -> false" 0
$on      = if ($off.Count) { & $from "enabled pref -> true" ($off[0] + 1) } else { @() }

$ok4 = $false
if ($newTab.Count -and $search.Count) { $ok4 = @((& $between $newTab[0] $search[0]) | Where-Object { $_ -match "tab inserted at index" }).Count -ge 1 }
Verdict "step 4: '+ > New tab' logged, and a tab was inserted before the next + item" $ok4
$ok5 = $false
if ($search.Count -and $newWs.Count) { $ok5 = @((& $between $search[0] $newWs[0]) | Where-Object { $_ -match "tab search: listed" }).Count -ge 1 }
Verdict "step 5: '+ > Tab search' logged, and the panel listed tabs before the next + item" $ok5

$ok6 = $false; $deleted = @()
if ($newWs.Count -and $created.Count -and $created[0] -gt $newWs[0]) {
    $g = [regex]::Match($w[$created[0]], "created workspace '([0-9a-f-]+)'").Groups[1].Value
    $deleted = & $from "deleting workspace '$g'" $created[0]
    $ok6 = $deleted.Count -gt 0
}
Verdict "step 6: '+ > New workspace' logged, one was created, and it was deleted" $ok6
Verdict "step 6b: a background tab was brought to front for its rename, then renamed DELTA (patch 30)" (($front.Count -gt 0) -and ($delta.Count -gt 0) -and ($front[0] -lt $delta[0]))

$ok7 = $false
if ($delta.Count -and $off.Count) {
    $switches = @((& $between $delta[0] $off[0]) | Where-Object { $_ -match "active workspace -> '" }).Count
    Write-Host "step 7: $switches switch(es) between the DELTA rename and the toggle"
    $ok7 = $switches -ge 4
}
Verdict "step 7: Shift+Alt+Right switched at least 4 times" $ok7
Verdict "step 9: Workspaces toggled off, then on again" (($off.Count -gt 0) -and ($on.Count -gt 0))

$crash = @(Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED').Count
Verdict "no Check failed / FATAL / NOTREACHED in the log ($crash)" ($crash -eq 0)
Write-Host "`nSteps 1, 2, 3, 6 (T slid into view), 6b (the box at once), 7 (the rail following), 8 and 9 (the button swap) are yours to grade by eye." -ForegroundColor Yellow
