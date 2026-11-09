param([string]$Log = "<local-path>\Helium-workspace\smoke-run.log", [string]$ProfileDir = "<local-path>\Helium-workspace\testprofile")
# Smoke test after a rebase (written for R2, LOCAL.md 27): launches out\Default against testprofile with logging,
# prints the owner's steps, waits for the browser to close, then grades the log (-Log, default smoke-run.log).
# Guards: browser already running (forwarded launch), stale binary, empty log.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
# -ProfileDir: since E14, testprofile restores its ~445-tab session at every start, so step 2's "Work is
# empty" cannot hold there; R5 ran this on a fresh copy of testprofile-e15b-smoke (LOCAL.md 59).
$prof = $ProfileDir
$log  = $Log
$pdir = "<local-path>\Helium-workspace\helium\patches\local\workspaces"

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running - close it (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$newest = (Get-ChildItem "$pdir\*.patch" | Sort-Object LastWriteTime | Select-Object -Last 1)
if ((Get-Item $exe).LastWriteTime -lt $newest.LastWriteTime) { Write-Host "ABORT: chrome.exe older than $($newest.Name)" -ForegroundColor Red; exit 1 }
$ver = (Get-Item "$exe".Replace('chrome.exe','chrome.dll')).VersionInfo.ProductVersion
$want = (Get-Content <local-path>\Helium-workspace\helium\chromium_version.txt -TotalCount 1).Trim()   # the version the rebase pinned
if ($ver -ne $want) { Write-Host "ABORT: chrome.dll is $ver, not $want" -ForegroundColor Red; exit 1 }
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
# Step 6 moves a tab into the third workspace, which must have no tab: since C4 a moved tab goes to the TOP of the
# other workspace's Today, and only with none there does it stay in place -- the interleaved strip step 6's verdict needs.
$empty = @((Get-Content "$prof\Default\Preferences" -Raw | ConvertFrom-Json).helium.workspaces.list.items | Where-Object { $_.guid -ne 'default' })[1].title
if (-not $empty) { Write-Host "ABORT: step 6 needs a third workspace with no tab (a fresh copy of testprofile-e15b-smoke has Canary)" -ForegroundColor Red; exit 1 }
Remove-Item $log -EA SilentlyContinue

Write-Host @"

Binary: $ver. Steps (every step says which workspace you are IN):
 0. [Home]  if small PINNED tabs sit at the top of the strip, right-click each -> Remove from Favorites (they show in
            every workspace, so Work would not be empty and step 2 would spawn nothing).
 1. [Home]  rail on the left shows Home and Work?   (owner-observed)
 2. [Home]  open 2 MORE tabs (the launch tab makes 3). Click WORK in the rail -> one tab should appear at once.
 3. [Work]  open 2 more tabs (Work now has 3). Press Ctrl+Tab three times: it must cycle
            only Work's tabs and the rail must stay on Work.
 4. [Work]  press Ctrl+9: last tab of Work, rail stays on Work.
 5. [Work]  right-click a Work tab -> Close other tabs. Work keeps 1 tab.
            Click HOME in the rail -> Home's 3 tabs must still be there.
 6. [Home]  right-click the MIDDLE Home tab -> Move tab to workspace -> $empty (it has no tab). A moved
            tab goes to the TOP of the other workspace's tabs, and with none there it stays where it was,
            so the list is now interleaved. (Not Work: its tab would pull the moved one above it -- C4.
            Opening a tab does not interleave either: since E15c.1 a new tab goes to the TOP of its
            workspace -- R5, LOCAL.md 59.)
            Open chrome://settings -> Appearance -> switch Workspaces OFF, then ON again.
 7. Close the browser window. This script then grades the log.

"@ -ForegroundColor Yellow

Start-Process -FilePath $exe -ArgumentList @("--user-data-dir=$prof","--enable-logging","--log-file=$log","--v=0","--no-first-run","--no-default-browser-check") -Wait
Start-Sleep 2
if (-not (Test-Path $log) -or (Get-Item $log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY - nothing ran (5.8.1 trap)" -ForegroundColor Red; exit 1 }
$w = Get-Content $log | Where-Object { $_ -match '\[workspaces\]' }
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
# step 2: spawn triple in one second
$spawn = $false
foreach ($l in ($w | Where-Object { $_ -match "active workspace -> " })) {
  # MMDD/HHMMSS only: the rest of the log prefix (milliseconds, file:line) differs line to line.
  $sec = [regex]::Match($l, '\d{4}/\d{6}').Value
  $same = $w | Where-Object { $_.Contains($sec) }
  if (($same -match "tag '' -> ") -and ($same -match 'tab inserted at index')) { $spawn = $true }
}
# A fresh start still reopens the last session's PINNED tabs (LOCAL.md 34), and a pinned tab is on
# screen in every workspace -- so Work is not empty and correctly spawns nothing (R4, LOCAL.md 36).
# More than one tab inserted in the launch second means this run cannot answer step 2: VOID, not FAIL.
$launchSec = [regex]::Match(($w | Select-Object -First 1), '\d{4}/\d{6}').Value
$launchTabs = @($w | Where-Object { $_.Contains($launchSec) -and $_ -match 'tab inserted at index' }).Count
if (-not $spawn -and $launchTabs -gt 1) {
  Write-Host "VOID  step 2: $launchTabs tabs opened at launch - pinned tabs from the last session made Work non-empty. Unpin them and rerun." -ForegroundColor Yellow
} else {
  Verdict "step 2: switching to empty Work spawned a tab (triple in one second)" $spawn
}
# step 6: toggle off reconciles with >=1 move; toggle on never reconciles
Verdict "step 6: toggle OFF -> reconcile with >=1 move" (($w -join "`n") -match "enabled pref -> false[\s\S]*reconcile: \d+ unit\(s\), [1-9]")
$onIdx = [array]::IndexOf($w, ($w | Where-Object { $_ -match 'enabled pref -> true' } | Select-Object -Last 1))
Verdict "step 6: toggle ON -> no reconcile after it" (($onIdx -ge 0) -and -not (($w | Select-Object -Skip ($onIdx+1)) -match 'reconcile:'))
Write-Host "`nSteps 3-5 (Ctrl+Tab, Ctrl+9, Close other tabs) are owner-observed; the log check for them is:"
Write-Host "  no 'active workspace ->' line between the step-2 spawn and the step-5 click on Home, and"
Write-Host "  the step-5 'active workspace ->' line NOT followed by 'tab inserted' in the same second."
Write-Host "  Read the timestamps above and confirm."
