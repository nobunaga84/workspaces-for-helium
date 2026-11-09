param([ValidateSet("Restart", "Import")][string]$Mode = "Restart",
      [switch]$NoExtensions,          # also try it with extensions disabled
      [switch]$ReportOnly,            # re-run the symbol decoding / reports on an existing .etl
      [switch]$Elevated,              # (internal) this is the administrator child
      [string]$Tag = "e14c-probe")
# E14c probe (LOCAL.md 40): WHERE do the seconds go? The first real import took 324 s for 3,873
# tabs and the cold restart 263 s for 3,875, the cost per tab GROWING from 5 ms to 130 ms as the
# strip filled -- some per-insert work walks the whole strip. Reading found candidates; only a
# profile can rank them.
#
# Records a sampled CPU profile (Windows ETW, 100 Hz, with stacks) of the DCHECK build -- the only
# build with function names -- then decodes the symbols against out\Dcheck\chrome.dll.pdb and writes:
#   <Tag>-profile.txt   samples per function, self time (xperf -a profile -detail)
#   <Tag>-stacks.txt    the butterfly (callers / callees) of the browser process
#   <Tag>-console.log   everything the elevated window printed
# -Mode Restart (default): a COPY of the imported testprofile restores its 3,875 tabs on its own;
#   NOTHING to click -- the script closes the browser when the restore loop has ended.
# -Mode Import: a copy of the CLEAN profile; you click "Import from Arc" once.
# ETW recording needs an administrator: the script asks for elevation (one UAC "Yes") and runs
# itself again in that window; the reports land in <local-path>\Helium-workspace either way.
$ws   = "<local-path>\Helium-workspace"
$src  = "$ws\helium-windows\build\src"
$exe  = "$src\out\Dcheck\chrome.exe"
$live = "$ws\helium-windows\patches\local\workspaces\36-arc-import.patch"
$xperf = "C:\Program Files (x86)\Windows Kits\10\Windows Performance Toolkit\xperf.exe"
if ($NoExtensions) { $Tag = "$Tag-noext" }
$Tag = "$Tag-$($Mode.ToLower())"
$prof = "$ws\testprofile-$Tag"
$from = if ($Mode -eq "Restart") { "$ws\testprofile" } else { "$ws\testprofile-pre-e14c" }
$etl  = "$ws\$Tag.etl"; $log = "$ws\$Tag-run.log"; $console = "$ws\$Tag-console.log"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--log-file=`"$log`"")
if ($Mode -eq "Import") { $flags += "--restore-last-session" }
if ($NoExtensions) { $flags += "--disable-extensions" }

# Process.HasExited answered "true" for a browser that was still restoring when the script was run from
# a nested non-interactive shell (LOCAL.md 40). The browser main process is found by its command
# line instead: chrome.exe on this profile, no --type= (renderers and helpers carry one).
function BrowserPid { $b = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' }); if ($b.Count) { $b[0].ProcessId } else { 0 } }
function Abort($m) { Write-Host "ABORT: $m" -ForegroundColor Red; if ($Elevated) { Read-Host "press Enter to close this window" | Out-Null }; exit 1 }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not (Test-Path $xperf)) { Abort "xperf.exe not found (Windows Performance Toolkit)" }

if (-not $ReportOnly -and -not $admin) {
    # Ask Windows for an administrator window and run this same script there.
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"", "-Mode", $Mode, "-Elevated", "-Tag", "`"$($Tag -replace "-$($Mode.ToLower())$", '' -replace '-noext$', '')`"")
    if ($NoExtensions) { $args += "-NoExtensions" }
    Write-Host "ETW recording needs an administrator: click YES on the prompt that appears. The work then runs in a new window; its output is also saved to $console" -ForegroundColor Yellow
    $child = Start-Process powershell -Verb RunAs -ArgumentList $args -PassThru
    $child.WaitForExit()
    Write-Host "elevated run finished (exit $($child.ExitCode)). Console log: $console"
    exit $child.ExitCode
}

if (-not $ReportOnly) {
    Start-Transcript -Path $console -Force | Out-Null
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Abort "a fork browser is already running (forwarded-launch trap)" }
    if (-not (Test-Path $live)) { Abort "no 36-arc-import.patch" }
    # A warning, not the usual abort: patch 36 was refreshed AFTER this binary was built (the log-line
    # walk fix), and profiling the binary that produced the 324 s is the point of this script.
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "note: Dcheck chrome.exe is older than patch 36 -- profiling the build the gate ran" -ForegroundColor Yellow }
    if (-not (Test-Path $from)) { Abort "no source profile at $from" }
    if (Test-Path $prof) { Remove-Item -Recurse -Force $prof }
    Write-Host "throwaway profile: copying $from -> $prof ..." -ForegroundColor Green
    robocopy $from $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { Abort "the copy failed (robocopy $LASTEXITCODE)" }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Abort "preconditions not met" }
    Remove-Item $etl, $log -EA SilentlyContinue

    # 100 Hz (the unit is 100 ns), stacks on every sample, straight to a file.
    & $xperf -SetProfInt 100000 | Out-Null
    & $xperf -on PROC_THREAD+LOADER+PROFILE -stackwalk Profile -BufferSize 1024 -MinBuffers 64 -MaxBuffers 512 -f "$ws\$Tag-kernel.etl"
    if ($LASTEXITCODE -ne 0) { Abort "xperf could not start recording (exit $LASTEXITCODE). Is another kernel trace running? 'xperf -stop' then retry." }
    Write-Host "recording ..." -ForegroundColor Green
    if ($Mode -eq "Import") {
        Write-Host @"

 1. [any workspace]  click the + at the END of the rail -> "Import from Arc". Then WAIT.
    The window freezes while it imports (several minutes on this build). This window reports
    the moment the import finishes -- the recording stops by itself then.
"@ -ForegroundColor Yellow
    } else {
        Write-Host "The browser restores its 3,875 tabs by itself (several minutes, window frozen). NOTHING to click; do not close it." -ForegroundColor Yellow
    }
    $env:HELIUM_ARC_SIDEBAR = "$ws\arc-made-up\StorableSidebar.json"  # Arc's shape, made up (LOCAL.md 133)
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 5
    $script:browserPid = BrowserPid
    if (-not $script:browserPid) { & $xperf -d $etl | Out-Null; Abort "the browser did not start" }
    $done = $false; $inserts = 0; $lastGrowth = Get-Date
    while ((BrowserPid) -and -not $done) {
        Start-Sleep 3
        if (-not (Test-Path $log)) { continue }
        if ($Mode -eq "Import") {
            if (Select-String -Path $log -Pattern 'arc import: done' -Quiet) { $done = $true }
        } else {
            # The restore loop has ended when no tab has been inserted for 15 s after at least one was.
            $n = (Select-String -Path $log -Pattern 'tab inserted at index' | Measure-Object).Count
            if ($n -gt $inserts) { $inserts = $n; $lastGrowth = Get-Date; Write-Host -NoNewline "`r  restored so far: $n   " }
            elseif ($inserts -gt 0 -and ((Get-Date) - $lastGrowth).TotalSeconds -ge 15) { $done = $true }
        }
    }
    & $xperf -d $etl | Out-Null
    Write-Host ""
    if ($done) { Write-Host "$Mode finished -- recording stopped." -ForegroundColor Green } else { Write-Host "the browser exited early; recording stopped anyway." -ForegroundColor Red }
    $bp = BrowserPid
    if ($bp) { $proc = Get-Process -Id $bp -EA SilentlyContinue; if ($proc) { [void]$proc.CloseMainWindow() }; Write-Host "closing the browser ..."; $w = 0; while ((BrowserPid) -and $w -lt 180) { Start-Sleep 1; $w++ } }
    if (BrowserPid) { Stop-Process -Id (BrowserPid) -Force }
    Remove-Item "$ws\$Tag-kernel.etl" -EA SilentlyContinue
}

# ---- what the log says: the per-500 curve ---------------------------------------------------
if (Test-Path $log) {
    $t0 = $null; $rows = @()
    foreach ($line in Get-Content $log) {
        if ($line -match '\[\d+:\d+:\d{4}/(\d\d)(\d\d)(\d\d)\.(\d{3}):') {
            $t = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000
            if ($null -eq $t0) { $t0 = $t }
            if ($line -match '\[workspaces\] arc import: start') { $t0 = $t }
            elseif ($line -match '\[workspaces\] tab inserted at index') { $rows += ($t - $t0) }
        }
    }
    if ($rows.Count) {
        Write-Host ("`n{0}: {1} inserts in {2:N1} s ({3:N0} ms/tab mean)" -f $Mode, $rows.Count, $rows[-1], 1000 * $rows[-1] / $rows.Count)
        $prev = 0; for ($n = 500; $n -le $rows.Count; $n += 500) { Write-Host ("  tabs {0,4}-{1,4}: {2,6:N1} s ({3,4:N0} ms/tab)" -f ($n - 499), $n, ($rows[$n - 1] - $prev), 1000 * ($rows[$n - 1] - $prev) / 500); $prev = $rows[$n - 1] }
    }
}

# ---- symbol decoding + reports ------------------------------------------------------------------
if (-not (Test-Path $etl)) { Abort "no trace at $etl" }
$env:_NT_SYMBOL_PATH = "$src\out\Dcheck"
$env:_NT_SYMCACHE_PATH = "$ws\symcache"
if (-not (Test-Path $env:_NT_SYMCACHE_PATH)) { New-Item -ItemType Directory $env:_NT_SYMCACHE_PATH | Out-Null }
Write-Host "`ndecoding symbols (the first time builds a cache from a 2.3 GB PDB -- this can take many minutes) ..." -ForegroundColor Green
& $xperf -i $etl -o "$ws\$Tag-profile.txt" -symbols -a profile -detail
Write-Host "profile report: $ws\$Tag-profile.txt (exit $LASTEXITCODE)"
$who = if ($script:browserPid) { @("-pid", $script:browserPid) } else { @("-process", "chrome.exe") }
& $xperf -i $etl -o "$ws\$Tag-stacks.txt" -symbols -a stack -butterfly 30 @who
Write-Host "stack report:   $ws\$Tag-stacks.txt (exit $LASTEXITCODE)"
Write-Host "`nDone. The analysis is mine; just say the probe finished." -ForegroundColor Cyan
if ($Elevated) { Stop-Transcript | Out-Null; Read-Host "press Enter to close this window" | Out-Null }
