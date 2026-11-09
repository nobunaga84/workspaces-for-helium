param([string]$OutDir = "Default", [string]$Tag = "e14c2-time")
# No-click A/B: restart a throwaway copy of the imported testprofile on the given build, time the
# restore loop from the log, sample memory once everything is asleep, close the browser itself.
$ws = "<local-path>\Helium-workspace"; $prof = "$ws\testprofile-$Tag"; $log = "$ws\$Tag-run.log"
$exe = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: fork running"; exit 1 }
if (Test-Path $prof) { [IO.Directory]::Delete($prof, $true) }
robocopy "$ws\testprofile" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
"copied testprofile -> $prof (robocopy $LASTEXITCODE)"
if (Test-Path $log) { [IO.File]::Delete($log) }
function BrowserPid { $b = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' }); if ($b.Count) { $b[0].ProcessId } else { 0 } }
$t0 = Get-Date
Start-Process -FilePath $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--log-file=`"$log`"") | Out-Null
Start-Sleep 5
$n0 = -1; $stable = 0; $t = 0
while ((BrowserPid) -and $stable -lt 15 -and $t -lt 900) {
    Start-Sleep 3; $t += 3
    $n = if (Test-Path $log) { (Select-String -Path $log -Pattern 'tab inserted at index' | Measure-Object).Count } else { 0 }
    if ($n -ne $n0) { $n0 = $n; $stable = 0 } else { $stable += 3 }
}
"restore reached $n0 inserts; loop settled $t s after launch"
$s = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.ExecutablePath -like '*Helium-workspace*' })
$b = @($s | Where-Object { $_.CommandLine -notmatch '--type=' })
if ($b.Count) { $p = Get-Process -Id $b[0].ProcessId; "asleep: $($s.Count) processes, $(@($s | Where-Object { $_.CommandLine -match '--type=renderer' }).Count) renderers, browser $([int]($p.PrivateMemorySize64/1MB)) MB private" }
$bp = BrowserPid
if ($bp) { $tc = Get-Date; [void](Get-Process -Id $bp).CloseMainWindow(); $w = 0; while ((BrowserPid) -and $w -lt 300) { Start-Sleep 1; $w++ }; "closed gracefully: $(if (BrowserPid) { 'NO' } else { "yes, in $w s" })" }
if (BrowserPid) { Stop-Process -Id (BrowserPid) -Force; "force-stopped" }
# A force-stopped browser's renderers and GPU process take a moment to die; until they do,
# check-e14c.ps1 (and this script) refuse to start. Wait for them rather than race the owner.
$w = 0; while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') -and $w -lt 60) { Start-Sleep 1; $w++ }
if ($w) { "waited $w s for the fork's child processes to exit$(if ($w -ge 60) { ' -- STILL RUNNING' })" }
# the curve
$first = $null; $rows = @()
foreach ($line in Get-Content $log) {
    if ($line -match '\[\d+:\d+:\d{4}/(\d\d)(\d\d)(\d\d)\.(\d{3}):') {
        $ts = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000
        if ($null -eq $first) { $first = $ts }
        if ($line -match '\[workspaces\] tab inserted at index') { $rows += ($ts - $first) }
    }
}
if ($rows.Count) {
    "restart: {0} inserts, last at +{1:N1} s ({2:N0} ms/tab mean)" -f $rows.Count, $rows[-1], (1000 * $rows[-1] / $rows.Count)
    $prev = 0; for ($n = 500; $n -le $rows.Count; $n += 500) { "  tabs {0,4}-{1,4}: {2,6:N1} s ({3,4:N0} ms/tab)" -f ($n - 499), $n, ($rows[$n - 1] - $prev), (1000 * ($rows[$n - 1] - $prev) / 500); $prev = $rows[$n - 1] }
    # [int] ROUNDS in PowerShell (3864/500 = 7.7 -> 8), which labelled the last bucket "4001-3864".
    if ($rows.Count % 500) { "  tabs {0,4}-{1,4}: {2,6:N1} s ({3,4:N0} ms/tab)" -f ([math]::Floor($rows.Count / 500) * 500 + 1), $rows.Count, ($rows[-1] - $prev), (1000 * ($rows[-1] - $prev) / ($rows.Count % 500)) }
}
"crash markers: $((Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|dangling|NOTREACHED' | Measure-Object).Count)"
"compositor animation errors: $((Select-String -Path $log -Pattern 'CompositorAnimationObserver is active for too long' | Measure-Object).Count)"
exit 0  # robocopy's "copied OK" is 1 and would leak out as this script's exit code
