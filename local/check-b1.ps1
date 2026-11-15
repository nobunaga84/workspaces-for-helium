param([string]$OutDir = "Default")
# B1 (ideas.md B1, LOCAL.md 147): the sidebar width after an upgrade. Hands-free, nothing to click. A Chromium 156
# session file has no width record; a window session restore brings back from it never read the pref and wrote its
# built-in 200 over the owner's width (OnBrowserCreated -> UpdatePrefService). Each row runs on a fresh throwaway copy
# of testprofile-e15b-smoke (made-up data; testprofile and the daily browser are never touched), whose session's width
# record is changed with session-width.py BEFORE the launch, the pref set to 474, then one start with
# --restore-last-session, a close with the window's X, and the pref read back:
#   A   the session's width record removed (a 156 session)  -> the pref still 474 (red before the fix: 200)
#   A2  A's profile started again (the session the fix wrote) -> 474, and that session holds 474
#   B   the session's record says 333 (the window's own width) -> 333: the session's width wins over the pref
#   all logs: 0 crash markers
# Each start must log one new session restore with a window (Chromium's own sessions.event_log in Preferences, type 1
# kRestore) or the row aborts: a new window would take the pref through Helium's own branch and pass without 113.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-b1.ps1 [-OutDir Dcheck]
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$smoke = "$ws\testprofile-e15b-smoke"
$src   = "$ws\helium-windows\build\src"
$bin   = "$src\out\$OutDir"
$exe   = "$bin\chrome.exe"
$tag   = "b1-$($OutDir.ToLower())"
$markers = 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr'
$script:failed = 0
function Fail([string]$why) { Write-Host "ABORT: $why" -ForegroundColor Red; exit 1 }
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
function Pids([string]$prof, [switch]$All) {
    @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and ($All -or $_.CommandLine -notmatch '--type=') } | ForEach-Object { $_.ProcessId })
}
function Prefs([string]$prof, [string[]]$a) { & python -I "$here\prefs.py" "$prof\Default\Preferences" @a }
function PrefWidth([string]$prof) { "$(Prefs $prof @('vertical_tabs.uncollapsed_width'))".Trim() }
# Chromium's own record (session_service_log.h): kRestore (type 1) entries after time `since` that brought back a
# window, read cleanly. By time, not by count: the log keeps the last 20 entries (kMaxEventCount), so once full a
# run adds entries and drops as many old ones (11-14: 19 entries in the base).
function EventLog([string]$prof) { @("$(Prefs $prof @('sessions.event_log'))" | ConvertFrom-Json) }
function LastEventTime([string]$prof) { [int64](@(EventLog $prof | ForEach-Object { [int64]$_.time }) + 0 | Measure-Object -Maximum).Maximum }
function RestoresSince([string]$prof, [int64]$since) {
    @(EventLog $prof | Where-Object { [int64]$_.time -gt $since -and $_.type -eq 1 -and $_.window_count -ge 1 -and -not $_.errored_reading }).Count
}
function SessionFile([string]$prof) { Get-ChildItem -LiteralPath "$prof\Default\Sessions" -Filter "Session_*" -File | Sort-Object LastWriteTime | Select-Object -Last 1 }
function Width([string]$prof) { "$(& python -I "$here\session-width.py" (SessionFile $prof).FullName)".Trim() }
function NewCopy([string]$row) {
    $prof = "$ws\testprofile-$tag-$row"
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if ($LASTEXITCODE -ge 8 -or -not (Test-Path "$prof\Default\Preferences")) { Fail "the copy of $smoke failed (robocopy $LASTEXITCODE)" }
    if (@(Get-ChildItem -LiteralPath "$prof\Default\Sessions" -Filter "Session_*" -File).Count -ne 1) { Fail "$row`: the copy should hold exactly one Session_ file" }
    $null = Prefs $prof @("vertical_tabs.uncollapsed_width=474", "vertical_tabs.collapsed_state=false")
    $prof
}
# One start with the last session, the window drawn, closed with its X (WM_CLOSE, the session written), all gone.
function Run([string]$prof, [string]$row) {
    $log = "$ws\$tag-$row-run.log"
    if (Test-Path $log) { Remove-Item $log -Force }
    $since = LastEventTime $prof
    $argv = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--log-file=`"$log`"", "--no-first-run", "--no-default-browser-check", "--restore-last-session")
    Start-Process -FilePath $exe -ArgumentList $argv -RedirectStandardOutput "$ws\$tag-$row-out.txt" -RedirectStandardError "$ws\$tag-$row-err.txt" | Out-Null
    $t = Get-Date
    while (-not ((Test-Path $log) -and (Select-String -Path $log -Pattern "pins: drew \d+ row\(s\) of '" -Quiet))) {
        if (((Get-Date) - $t).TotalSeconds -gt 60) { foreach ($id in Pids $prof -All) { Stop-Process -Id $id -EA SilentlyContinue }; Fail "$row`: the window was not drawn in 60 s" }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep 3
    foreach ($id in Pids $prof) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    # The browser process writes Preferences and the session before it ends; its helpers can outlive it under load
    # (a renderer, 11-13 during a full build): 30 s for them, then the copy's leftovers are ended.
    while ((Pids $prof).Count) {
        if (((Get-Date) - $t).TotalSeconds -gt 60) { foreach ($id in Pids $prof -All) { Stop-Process -Id $id -EA SilentlyContinue }; Fail "$row`: the browser did not close in 60 s (the copy's processes ended)" }
        Start-Sleep -Milliseconds 500
    }
    $t = Get-Date
    while ((Pids $prof -All).Count -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }
    foreach ($id in Pids $prof -All) { Stop-Process -Id $id -EA SilentlyContinue }
    $new = RestoresSince $prof $since
    if ($new -ne 1) { Fail "$row`: $new new session restore(s) with a window in sessions.event_log (1 expected) -- the row would not test a restored window" }
    @(Select-String -LiteralPath $log -CaseSensitive -Pattern $markers).Count
}

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Fail "a fork browser is already running -- close it first" }
if (-not (Test-Path "$bin\chrome.dll")) { Fail "no $bin\chrome.dll" }
$bwf = "$src\chrome\browser\ui\browser_window\internal\browser_window_features.cc"
if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt (Get-Item $bwf).LastWriteTime) { Fail "$OutDir chrome.dll is older than browser_window_features.cc (stale binary: build first)" }
# 113 has no log text, so the binary cannot be asked; the source it was built from (newer chrome.dll, above) can.
if (-not (Select-String -LiteralPath $bwf -SimpleMatch "Helium Workspaces (B1)" -Quiet)) { Fail "browser_window_features.cc has no B1 fallback: patch 113 is not applied in this tree" }
& python "$here\set-workspaces-pref.py" $smoke --show | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { Fail "$smoke`: preconditions not met (vertical layout, a non-default workspace, enabled)" }
Write-Host "      binary: $OutDir, chrome.dll $((Get-Item "$bin\chrome.dll").LastWriteTime.ToString('s'))"

$a = NewCopy "a"
$null = & python -I "$here\session-width.py" (SessionFile $a).FullName --strip
Verdict "A  before: the session holds no width ($(Width $a)), the pref $(PrefWidth $a)" ((Width $a) -eq "{}")
$m = Run $a "a"
$w = PrefWidth $a
Verdict "A  a window restored from a session with no width: the pref after the close $w (474; the bug wrote 200)" ($w -eq "474")
$m2 = Run $a "a2"
$w2 = PrefWidth $a
$s2 = Width $a
Verdict "A2 started again: the pref $w2, the session written at the close $s2 (474 both)" ($w2 -eq "474" -and $s2 -match '^\{"\d+": "474"\}$')

$b = NewCopy "b"
$null = & python -I "$here\session-width.py" (SessionFile $b).FullName --set 333
$m3 = Run $b "b"
$w3 = PrefWidth $b
Verdict "B  a window restored with its own width 333 (the pref 474): the pref after the close $w3 (333: the window's own width wins)" ($w3 -eq "333")

Verdict "0 crash markers: A $m, A2 $m2, B $m3" ($m -eq 0 -and $m2 -eq 0 -and $m3 -eq 0)
Write-Host "Logs: $ws\$tag-<a|a2|b>-run.log" -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
