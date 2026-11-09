# Runs the one feature-gate check that can be automated end to end: does an
# incognito window get a WorkspaceService at all?
#
# Why this is a script and not three sentences of instructions. Two traps make
# the by-hand version answer the wrong question, and both look like a pass:
#
#   1. A stale binary. out/Default/chrome.exe can easily be the previous chunk's
#      build, which answers the previous chunk's question. Guarded below.
#   2. LOCAL.md 11: tabs inserted while a window is being set up are NOT observed,
#      because WorkspaceService does not exist yet. So the FIRST tab of the
#      incognito window logs nothing whether the gate works or not. The real test
#      is a SECOND tab forwarded into the already-open incognito window, which a
#      working service would log and a missing one cannot.
#
# The positive control matters as much as the test: LOCAL.md 8 -- if logging is
# off, "no line" means nothing at all. So we first prove a normal tab DOES log.
#
#   .\local\check-gate.ps1

$exe   = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$patch = "<local-path>\Helium-workspace\helium\patches\local\workspaces\04-gate.patch"
$prof  = "<local-path>\Helium-workspace\gatecheck-profile"
$log   = "<local-path>\Helium-workspace\gatecheck.log"
$mark  = "[workspaces] tab inserted"

function Count-Marks { if (Test-Path $log) { @(Select-String -Path $log -SimpleMatch $mark -ErrorAction SilentlyContinue).Count } else { 0 } }

if (-not (Test-Path $exe))   { Write-Host "ABORT: no chrome.exe -- build first." -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $patch).LastWriteTime) {
    Write-Host "ABORT: chrome.exe is OLDER than 04-gate.patch." -ForegroundColor Red
    Write-Host "       exe:   $((Get-Item $exe).LastWriteTime)" -ForegroundColor Red
    Write-Host "       patch: $((Get-Item $patch).LastWriteTime)" -ForegroundColor Red
    Write-Host "       This binary predates the gate; any result would be E6b's answer." -ForegroundColor Red
    exit 1
}
if (Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '*Helium-workspace*' }) {
    Write-Host "ABORT: the fork is already running. Close it -- a forwarded launch would log into its window, not ours." -ForegroundColor Red
    exit 1
}

Remove-Item $log -ErrorAction SilentlyContinue
$common = @("--user-data-dir=$prof", "--no-first-run", "--no-default-browser-check")

Write-Host "starting the fork (fresh profile at $prof)..." -ForegroundColor Yellow
$proc = Start-Process $exe -PassThru -ArgumentList ($common + @("--enable-logging", "--log-file=$log", "--v=0", "about:blank"))

$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline -and -not (Test-Path $log)) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path $log)) { Write-Host "ABORT: no log file appeared -- logging flags did not take." -ForegroundColor Red; Stop-Process -Id $proc.Id -Force; exit 1 }
Start-Sleep -Seconds 5

$atStart = Count-Marks
Write-Host "  lines after startup: $atStart  (LOCAL.md 11: startup tabs are not observed, so 0 here is normal)"

# --- positive control: a normal tab MUST log, or the whole run proves nothing ---
& $exe @common "about:blank" | Out-Null
Start-Sleep -Seconds 4
$afterNormal = Count-Marks
Write-Host "  lines after a normal tab: $afterNormal"
if ($afterNormal -le $atStart) {
    Write-Host "INCONCLUSIVE: the positive control did not log. Logging is off or the service is not running at all;" -ForegroundColor Red
    Write-Host "              a silent incognito result below would mean nothing. Investigate before trusting anything." -ForegroundColor Red
    Stop-Process -Id $proc.Id -Force
    exit 1
}

# --- the test: first incognito window, then a SECOND tab into it (trap 2) ---
& $exe @common "--incognito" "about:blank" | Out-Null
Start-Sleep -Seconds 4
$afterIncognitoWindow = Count-Marks

& $exe @common "--incognito" "about:blank" | Out-Null
Start-Sleep -Seconds 4
$afterIncognitoTab = Count-Marks

Write-Host "  lines after the incognito WINDOW: $afterIncognitoWindow"
Write-Host "  lines after a second incognito TAB: $afterIncognitoTab   <-- the one that decides it"
Write-Host ""
if ($afterIncognitoTab -eq $afterNormal) {
    Write-Host "PASS: a normal tab is observed, incognito tabs are not." -ForegroundColor Green
    Write-Host "      No WorkspaceService is built for an off-the-record profile." -ForegroundColor Green
} else {
    Write-Host "FAIL: $($afterIncognitoTab - $afterNormal) incognito tab(s) were observed." -ForegroundColor Red
    Write-Host "      The service exists in incognito -- check IsRegularProfile() at browser_window_features.cc:634." -ForegroundColor Red
}

Write-Host ""
Write-Host "closing the fork instance this script started (PID $($proc.Id))." -ForegroundColor Yellow
Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Write-Host "log kept at $log"
