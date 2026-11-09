param([switch]$GradeOnly,
      [switch]$Rehearsal,             # the small sample file, the DCHECK build, a THROWAWAY profile
      [switch]$Reset,                 # put the clean copy back over testprofile before starting
      [string]$Sidebar = "",          # a smaller / copied StorableSidebar.json (sets HELIUM_ARC_SIDEBAR)
      [string]$OutDir = "Default",    # "Dcheck" runs the same steps over the DCHECK build
      [string]$Tag = "e14c")
# E14c: "Import from Arc" and THE SCALE GATE (LOCAL.md 40, design 5). The browser is opened TWICE:
# run 1 = the import, which fills the window whose rail was clicked (a new window was built, rehearsed
# and withdrawn on 2026-09-22: closed before the original, it left the session), run 2 = a cold
# restart that must bring everything back on its own. The pass line (design 5 says this script is the
# authority): restore loop <= 10 s, browser process <= 1536 MB private with the tabs asleep, renderers
# <= 20, exit <= 10 s of the window close, 0 crash markers, a re-run imports almost nothing. Import
# time and the session file size are recorded, not gated. Scrolling and the switch are your eyes.
#
#   check-e14c.ps1 -Rehearsal        27 fake tabs (arc-sidebar-sample.json), out\Dcheck, a throwaway profile
#   check-e14c.ps1 [-Reset]          the made-up big Arc file, out\Default, testprofile  = THE SCALE GATE
#   check-e14c.ps1 -GradeOnly        re-grade the saved logs and measurements
#
# The script measures the open browser by itself every few seconds (memory, process count) and
# notices the moment it exits, so there is nothing to press: do the steps, then close the windows.
# The rehearsal NEVER touches testprofile: an import records its time, and the real import would then
# find nothing in Arc newer than the rehearsal. Interactive: run it in an ordinary terminal.
$ws    = "<local-path>\Helium-workspace"
$prof  = "$ws\testprofile"
if ($Rehearsal) {
    $OutDir = "Dcheck"; $Tag = "e14c-rehearsal"; $prof = "$ws\testprofile-e14c-rehearsal"
    $Sidebar = "$ws\helium\local\arc-sidebar-sample.json"
} elseif ($Sidebar) { Write-Host "ABORT: -Sidebar on testprofile would record an import time and starve the real import. Use -Rehearsal." -ForegroundColor Red; exit 1 }
$exe   = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$keep  = "$ws\testprofile-pre-e14c"
$live  = "$ws\helium-windows\patches\local\workspaces\36-arc-import.patch"
$log1 = "$ws\$Tag-run1.log"; $log2 = "$ws\$Tag-run2.log"; $samples = "$ws\$Tag-gate.json"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
$LimitColdStartS = 10; $LimitBrowserMB = 1536; $LimitExitS = 10

# The fork's processes: the browser (no --type) and its renderers. $PathLike/$Name are parameters so
# the function can be RUN against any Chromium-family app when the fork is not up (LOCAL.md 36).
function Sample([string]$PathLike = "*Helium-workspace*", [string]$Name = "chrome.exe") {
    $all = @(Get-CimInstance Win32_Process -Filter "Name='$Name'" | Where-Object { $_.ExecutablePath -like $PathLike })
    $browser = @($all | Where-Object { $_.CommandLine -notmatch '--type=' })
    $private = -1
    if ($browser.Count) { $bp = Get-Process -Id $browser[0].ProcessId -EA SilentlyContinue; if ($bp) { $private = [int]($bp.PrivateMemorySize64 / 1MB) } }
    [pscustomobject]@{
        at = (Get-Date).ToString("o")
        processes = $all.Count
        renderers = @($all | Where-Object { $_.CommandLine -match '--type=renderer' }).Count
        browserMB = if ($browser.Count) { [int](($browser | Measure-Object WorkingSetSize -Sum).Sum / 1MB) } else { -1 }
        browserPrivateMB = $private
        totalMB = [int](($all | Measure-Object WorkingSetSize -Sum).Sum / 1MB)
    }
}
# Process.HasExited lied for a browser started from a nested shell (LOCAL.md 40): the browser is
# found by its command line -- chrome.exe on this profile, no --type= (helpers carry one).
function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
# One run of the browser: print the steps, open it, measure it every 3 s until it exits.
# $AutoCloseAfterS > 0: the script closes the browser itself after that many quiet seconds.
function RunLeg([string]$title, [string]$log, [string[]]$extra, [string]$steps, [int]$AutoCloseAfterS = 0) {
    Write-Host ""
    Write-Host "==================== $title ====================" -ForegroundColor Cyan
    Write-Host $steps -ForegroundColor Yellow
    if (-not $AutoCloseAfterS) {
        Write-Host @"
   HOW THIS RUN GOES:
     A. the browser opens now: do the numbered steps in it
     B. when you are done, close the browser window (its X, top right). Do not close tabs first.
   Nothing to press here: this window measures the browser by itself (one dot = one measurement).
"@ -ForegroundColor Cyan
    }
    $t0 = Get-Date
    Start-Process -FilePath $exe -ArgumentList @($flags; $extra; "--log-file=`"$log`"") | Out-Null
    Start-Sleep 5
    $taken = New-Object System.Collections.Generic.List[object]
    $last = [datetime]::MinValue; $quiet = 0; $lastLogSize = -1
    while ((BrowserPids).Count -gt 0) {
        Start-Sleep -Milliseconds 250
        if (((Get-Date) - $last).TotalSeconds -ge 3) {
            $s = Sample
            if ($s.browserPrivateMB -gt 0) { $taken.Add($s); Write-Host -NoNewline "." -ForegroundColor DarkGray }
            $last = Get-Date
            if ($AutoCloseAfterS) {
                $size = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
                if ($size -eq $lastLogSize) { $quiet += 3 } else { $quiet = 0; $lastLogSize = $size }
                if ($quiet -ge $AutoCloseAfterS) { foreach ($id in BrowserPids) { $bp = Get-Process -Id $id -EA SilentlyContinue; if ($bp) { [void]$bp.CloseMainWindow() } }; $AutoCloseAfterS = 0 }
            }
        }
    }
    $exited = Get-Date
    Write-Host ""
    $peak = if ($taken.Count) { ($taken | Measure-Object browserPrivateMB -Maximum).Maximum } else { 0 }
    Write-Host ("  closed after {0:N0} s; {1} measurements, browser peak {2} MB private" -f ($exited - $t0).TotalSeconds, $taken.Count, $peak) -ForegroundColor Green
    [pscustomobject]@{ launched = $t0.ToString("o"); exited = $exited.ToString("o"); samples = $taken.ToArray() }
}

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if (-not (Test-Path $live)) { Write-Host "ABORT: no 36-arc-import.patch" -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.exe is older than patch 36 (stale binary)" -ForegroundColor Red; exit 1 }
    if ($Rehearsal) {
        # A throwaway profile, rebuilt every time from the cleanest testprofile there is.
        $from = if (Test-Path $keep) { $keep } else { "$ws\testprofile" }
        if ((Test-Path $prof) -and $prof.EndsWith("-e14c-rehearsal")) { Remove-Item -Recurse -Force $prof }
        Write-Host "rehearsal profile: copying $from -> $prof ..." -ForegroundColor Green
        robocopy $from $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
    } elseif ($Reset) {
        if (-not (Test-Path $keep)) { Write-Host "ABORT: -Reset needs the clean copy at $keep" -ForegroundColor Red; exit 1 }
        Write-Host "putting the clean copy back: $keep -> $prof ..." -ForegroundColor Green
        Remove-Item -Recurse -Force $prof
        robocopy $keep $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
    }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }

    # The import puts thousands of tabs into testprofile. Keep the profile as it was, ONCE: a second
    # run must never overwrite the clean copy with an imported one.
    if ($Rehearsal) { }
    elseif (Test-Path $keep) { Write-Host "clean copy already kept at $keep (not overwritten)" -ForegroundColor Green }
    else {
        Write-Host "keeping a clean copy of testprofile at $keep ..." -ForegroundColor Green
        robocopy $prof $keep /E /NFL /NDL /NJH /NP /R:1 /W:1 | Select-Object -Last 8 | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
    }
    if (-not $Sidebar) { $Sidebar = "$ws\arc-made-up\StorableSidebar.json" }  # Arc's shape, made up (LOCAL.md 133)
    if ($Sidebar) { if (-not (Test-Path $Sidebar)) { Write-Host "ABORT: no such file: $Sidebar" -ForegroundColor Red; exit 1 }; $env:HELIUM_ARC_SIDEBAR = $Sidebar }
    Remove-Item $log1, $log2, $samples -EA SilentlyContinue

    if ($Rehearsal) {
        Write-Host @"

THIS IS THE REHEARSAL: 27 fake tabs from a sample file (no Arc data), the DCHECK build, a throwaway
profile. Nothing you do here touches testprofile or Arc. Its job: crash the DCHECK build now, on 27
tabs, rather than later on 3,865. The browser opens twice.
"@ -ForegroundColor Magenta
        $steps1 = @"
 1. [any workspace]  click the + at the END of the rail (after the last workspace) -> "Import from Arc".
            EXPECT: the tabs fill this window while a status line at its bottom-left counts
            ("Importing from Arc: N of 27 tabs"). Then a bubble: "Imported 27 tabs from Arc",
            "2 folders became tab groups. 2 tabs were skipped ...", and a line saying
            "On startup" is now "Continue where you left off".   Click OK.
 2. EXPECT: you are still in the workspace you were in; no new tab opened. Two pinned tabs appeared
            at the top (Arc's favorites). The rail has two new workspaces: "Arc Sample One" (rocket
            icon) and "Arc Sample Two".
 3. click "Arc Sample One" in the rail. EXPECT: about 21 tabs, all greyed (asleep); two COLLAPSED
            groups named "Alpha" and "Alpha > Beta"; two split views (a tab drawn as a pair).
 4. click the "Alpha" header to expand it, then click ONE tab inside. EXPECT: only that tab loads.
 5. click + again. EXPECT: "Import from Arc" is there; DO NOT click it yet. Press Esc.
 6. wait about 10 seconds (a measurement with everything asleep), then close the browser window.
"@
        $steps2 = @"
 7. [wait]  the window restores BY ITSELF (no restore flag was given this time).
            EXPECT: "Arc Sample One" and "Arc Sample Two" are still in the rail; click each: the tabs
            are back, still asleep, groups still collapsed and named, the splits still split.
 8. click + -> "Import from Arc" AGAIN. EXPECT: a bubble "Imported 0 tabs from Arc". Click OK.
 9. wait about 10 seconds, then close the browser window.
"@
    } else {
        Write-Host @"

THIS IS THE REAL IMPORT AND THE SCALE GATE: the made-up Arc file of Arc's real size, the normal build,
testprofile (a clean copy is kept first). Arc may stay open. The browser opens twice.
"@ -ForegroundColor Magenta
        $steps1 = @"
 1. [any workspace]  click the + at the END of the rail -> "Import from Arc".
            EXPECT: the tabs fill this window while the status line at its bottom-left counts
            ("Importing from Arc: N of M tabs"). Watch whether the window still answers (scroll the
            strip, hover a tab). Then a bubble: "Imported N tabs from Arc", a line about folders and
            skipped tabs, one about folders left out, and one saying "On startup" is set. Click OK.
 2. EXPECT: you are still in the workspace you were in, and no new tab opened by itself. Two pinned
            tabs (Arc's favorites) at the top. The rail shows Arc's spaces as new workspaces.
 3. click the biggest imported workspace. EXPECT: its tabs appear, anchored ones asleep, folders as
            COLLAPSED groups named like "A > B". Scroll the strip up and down: smooth or choppy?
 4. expand one group (click its header), click ONE tab in it. EXPECT: only that tab loads.
 5. click + again. EXPECT: "Import from Arc" is there and clickable; DO NOT click it yet. Press Esc.
 6. wait about 10 seconds (a measurement with everything asleep), then close the browser window.
"@
        $steps2 = @"
 7. count in your head from the moment a window appears until you can click a tab. Note the seconds.
 8. click through the rail's workspaces. EXPECT: all imported tabs are back, still asleep, groups
            still collapsed and named, the split views still split.
 9. click + -> "Import from Arc" AGAIN. EXPECT: a bubble "Imported 0 tabs" (or only the few tabs
            Arc gained since) -- a re-run must not duplicate anything. Click OK.
10. wait about 10 seconds, then close the browser window.
"@
    }
    $leg1 = RunLeg "RUN 1 of 2: THE IMPORT" $log1 @("--restore-last-session") $steps1
    [pscustomobject]@{ leg1 = $leg1 } | ConvertTo-Json -Depth 5 | Set-Content $samples -Encoding utf8
    Start-Sleep 3
    if (-not (Test-Path $log1) -or (Get-Item $log1).Length -eq 0) { Write-Host "FAIL: run-1 log missing or EMPTY" -ForegroundColor Red; exit 1 }

    # No --restore-last-session on purpose: the import must have set "Continue where you left off".
    $leg2 = RunLeg "RUN 2 of 2: THE RESTART" $log2 @() $steps2
    [pscustomobject]@{ leg1 = $leg1; leg2 = $leg2 } | ConvertTo-Json -Depth 5 | Set-Content $samples -Encoding utf8
    Write-Host "`nBoth runs done. Grading from the logs:" -ForegroundColor Cyan
}

# ---- grading -------------------------------------------------------------------------------
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
function Note($text) { Write-Host "      $text" }
# Seconds of the day from a Chromium log line "[pid:tid:MMDD/HHMMSS.mmm:...". -1 when there is none.
function Stamp([string]$line) {
    if ($line -match '\[\d+:\d+:\d{4}/(\d{2})(\d{2})(\d{2})\.(\d{3}):') { return [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000.0 }
    return -1
}
# ConvertFrom-Json hands back a string on Windows PowerShell and may hand back a DateTime on newer ones.
function DayS($v) { $d = if ($v -is [datetime]) { $v } else { [datetime]::Parse("$v") }; return $d.TimeOfDay.TotalSeconds }
function WsLines($path) { if (-not (Test-Path $path) -or (Get-Item $path).Length -eq 0) { return $null }; return ,@(Get-Content $path | Where-Object { $_ -match '\[workspaces\]' }) }
# The restore burst: from the first log line to the last insert before the first gap of 2 s.
function RestoreLoop($path) {
    $lines = Get-Content $path
    $first = -1; foreach ($l in $lines) { $first = Stamp $l; if ($first -ge 0) { break } }
    $ins = @($lines | Where-Object { $_ -match '\[workspaces\] tab inserted at index' })
    $end = if ($ins.Count) { Stamp $ins[0] } else { $first }
    $n = 0
    foreach ($l in $ins) { $s = Stamp $l; if ($s - $end -gt 2) { break }; $end = $s; $n++ }
    [pscustomobject]@{ seconds = ($end - $first); restored = $n; end = $end }
}

$w1 = WsLines $log1; $w2 = WsLines $log2
if ($null -eq $w1) { Write-Host "FAIL: $log1 missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
$g = if (Test-Path $samples) { Get-Content $samples -Raw | ConvertFrom-Json } else { $null }

# The import is bounded by its own two log lines, never by a line count (LOCAL.md 30).
$iStart = -1; $iDone = -1; $doneAt = -1
for ($n = 0; $n -lt $w1.Count; $n++) { if ($iStart -lt 0 -and $w1[$n] -match 'arc import: start: (\d+) tab') { $iStart = $n; $planned = [int]$Matches[1] }; if ($iStart -ge 0 -and $iDone -lt 0 -and $w1[$n] -match 'arc import: done: (\d+) tab\(s\), (\d+) group\(s\), (\d+) split\(s\), (\d+) workspace\(s\), (\d+) skipped, startup ([a-z ]+), (\d+) ms(, aborted)?') { $iDone = $n; $done = $Matches; $doneAt = Stamp $w1[$n] } }
Verdict "run 1: the import started and finished (step 1 was done in RUN 1)" (($iStart -ge 0) -and ($iDone -gt $iStart))
if ($iDone -gt $iStart -and $iStart -ge 0) {
    $inside = @($w1[($iStart + 1)..($iDone - 1)])
    $tabs = [int]$done[1]; $importS = [int]$done[7] / 1000
    Note ("imported {0} of {1} planned tabs, {2} groups, {3} splits, {4} workspaces, {5} skipped, startup {6}, {7:N1} s{8}" -f $tabs, $planned, $done[2], $done[3], $done[4], $done[5], $done[6], $importS, $done[8])
    Verdict "the import was not aborted" (-not $done[8])
    Verdict "every planned tab was created" ($tabs -eq $planned -and $tabs -gt 0)
    Verdict "one 'tab inserted' line per imported tab, all inside the import" (@($inside | Where-Object { $_ -match 'tab inserted at index' }).Count -eq $tabs)
    $relayouts = @($inside | Where-Object { $_ -match 'relayout requested' }).Count
    Verdict "tags arrived BEFORE the insert: at most a handful of relayouts for $tabs tabs (saw $relayouts; the pinned favorites cost one each)" ($relayouts -le 5)
    Verdict "the import never switched workspace or spawned a tab" (@($inside | Where-Object { $_ -match "active workspace ->|created workspace '[^']*'$" }).Count -eq 0)
    Verdict "progress lines were written while it ran" (@($inside | Where-Object { $_ -match 'arc import: \d+ of \d+ tab' }).Count -ge 1)
    Verdict "startup was set to continue (or already was)" ($done[6] -match 'continue|unchanged')
    Note ("import time {0:N1} s (recorded, not gated)" -f $importS)
}
$restoreEnd = -1
if ($null -eq $w2) { Write-Host "FAIL: $log2 missing or EMPTY" -ForegroundColor Red; $script:failed++ } else {
    $r = RestoreLoop $log2; $restoreEnd = $r.end
    Note ("restart: {0} tabs restored, restore loop ended {1:N1} s after the first log line" -f $r.restored, $r.seconds)
    if ($iDone -ge 0) { Verdict "restart restored at least every imported tab (no restore flag was passed)" ($r.restored -ge [int]$done[1]) }
    Verdict ("cold start: restore loop finished within {0} s ({1:N1} s)" -f $LimitColdStartS, $r.seconds) ($r.seconds -ge 0 -and $r.seconds -le $LimitColdStartS)
    $again = @($w2 | Where-Object { $_ -match 'arc import: done: (\d+) tab' })
    if ($again.Count) { $null = $again[0] -match 'arc import: done: (\d+) tab'; Verdict "last step: the re-run imported almost nothing (saw $($Matches[1]); Arc may have gained a few)" ([int]$Matches[1] -le 25) }
    else { Verdict "last step: the re-run happened (Import from Arc clicked again in RUN 2)" $false }
}
if ($g) {
    foreach ($leg in @(@{ n = "run 1"; v = $g.leg1; log = $log1; after = $doneAt }, @{ n = "run 2"; v = $g.leg2; log = $log2; after = $restoreEnd })) {
        if (-not $leg.v) { Write-Host "FAIL  $($leg.n): no measurement (the script did not get that far)" -ForegroundColor Red; $script:failed++; continue }
        # The window close is the last removal the log records; the exit is when the process was gone.
        $close = @(Get-Content $leg.log | Where-Object { $_ -match '\[workspaces\] removed \d+ tab' }) | Select-Object -Last 1
        $closeS = if ($close) { Stamp $close } else { DayS $leg.v.exited }
        # Only measurements taken after the import / restore settled and before the close began count.
        $usable = @($leg.v.samples | Where-Object { $t = DayS $_.at; $t -ge $leg.after + 1 -and $t -le $closeS - 1 })
        $all = @($leg.v.samples).Count
        Verdict "$($leg.n): measured after the import/restore and before the close ($($usable.Count) of $all measurements)" ($usable.Count -ge 1)
        if ($usable.Count) {
            $s = $usable[-1]; $peak = ($usable | Measure-Object browserPrivateMB -Maximum).Maximum
            Note ("{0}: last measurement {1} processes, {2} renderers, browser {3} MB private (peak {4} MB)" -f $leg.n, $s.processes, $s.renderers, $s.browserPrivateMB, $peak)
            Verdict "$($leg.n): browser process under $LimitBrowserMB MB with the tabs asleep" ($s.browserPrivateMB -gt 0 -and $s.browserPrivateMB -le $LimitBrowserMB)
            Verdict "$($leg.n): sleeping tabs have no renderer (renderers <= 20)" ($s.renderers -ge 0 -and $s.renderers -le 20)
        }
        $exitS = if ($close) { (DayS $leg.v.exited) - $closeS } else { -1 }
        Verdict ("$($leg.n): exit took {0:N1} s from the window close (limit $LimitExitS)" -f $exitS) ($exitS -ge 0 -and $exitS -le $LimitExitS)
    }
} else { Write-Host "FAIL: no measurements file ($samples) -- the script was stopped before its end" -ForegroundColor Red; $script:failed++ }
$sess = Get-ChildItem "$prof\Default\Sessions" -EA SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 2
if ($sess) { Note ("session files: " + (($sess | ForEach-Object { "{0} {1:N0} KB" -f $_.Name.Split('_')[0], ($_.Length / 1KB) }) -join ", ") + " (recorded, not gated)") }
$markers = (Get-Content $log1, $log2 -EA SilentlyContinue | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the logs" ($markers -eq 0)
Write-Host "`nOwner-observed: same workspace after the import; the window answering while it filled; groups collapsed and named; only the clicked tab loads; scrolling smooth; your own cold-start count."
if (-not $Rehearsal) { Write-Host "To go back to the profile as it was: run this with -Reset, or close the fork, delete $prof and rename $keep to testprofile." }
Write-Host "Logs: $log1, $log2. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
