param([switch]$GradeOnly,
      [switch]$Rehearsal,             # the small sample file, the DCHECK build, a THROWAWAY profile
      [switch]$Reset,                 # put the clean pre-import copy back over testprofile before starting
      [string]$OutDir = "Default",    # "Dcheck" runs the same steps over the DCHECK build
      [string]$Tag = "e15b")
# E15b: Arc's pinned folders as ROWS of each workspace's pinned section, and THE SCALE GATE (LOCAL.md 45,
# design 5 "E15 spec"). Built from check-e14c.ps1: the same two runs -- run 1 = the import, run 2 = a cold
# restart that must bring everything back on its own -- and the same measurements. What changed: pinned
# tabs are no longer created as tabs, so the gate also grades the pins file (written by the import,
# loaded again at the restart), the section drawing it, and how long the biggest open folder took to draw.
# The pass line (design 5): restore loop <= 10 s, exit <= 10 s, the biggest folder drawn in <= 1 s,
# browser <= 1536 MB private, renderers <= 20, 0 crash markers, a re-run imports almost nothing.
#
#   check-e15b.ps1 -Rehearsal        the sample file (8 tabs + 19 pinned rows), out\Dcheck, a throwaway profile
#   check-e15b.ps1 -Reset            the made-up big Arc file, out\Default, testprofile reset to before ANY import
#   check-e15b.ps1 -GradeOnly        re-grade the saved logs and measurements
#
# The script measures the open browser by itself every few seconds and notices the moment it exits:
# do the steps, then close the windows. Interactive: run it in an ordinary terminal.
$ws    = "<local-path>\Helium-workspace"
$prof  = "$ws\testprofile"
$Sidebar = ""
if ($Rehearsal) {
    $OutDir = "Dcheck"; $Tag = "e15b-rehearsal"; $prof = "$ws\testprofile-e15b-rehearsal"
    $Sidebar = "$ws\helium\local\arc-sidebar-sample.json"
}
$bin   = "$ws\helium-windows\build\src\out\$OutDir"
$exe   = "$bin\chrome.exe"
$keep  = "$ws\testprofile-pre-e14c"
$live  = "$ws\helium-windows\patches\local\workspaces\40-pinned-section.patch"
$log1 = "$ws\$Tag-run1.log"; $log2 = "$ws\$Tag-run2.log"; $samples = "$ws\$Tag-gate.json"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
$LimitColdStartS = 10; $LimitBrowserMB = 1536; $LimitExitS = 10; $LimitDrawMs = 1000

function Sample([string]$PathLike = "*Helium-workspace*", [string]$Name = "chrome.exe") {
    $all = @(Get-CimInstance Win32_Process -Filter "Name='$Name'" | Where-Object { $_.ExecutablePath -like $PathLike })
    $browser = @($all | Where-Object { $_.CommandLine -notmatch '--type=' })
    $private = -1
    if ($browser.Count) { $bp = Get-Process -Id $browser[0].ProcessId -EA SilentlyContinue; if ($bp) { $private = [int]($bp.PrivateMemorySize64 / 1MB) } }
    [pscustomobject]@{
        at = (Get-Date).ToString("o")
        processes = $all.Count
        renderers = @($all | Where-Object { $_.CommandLine -match '--type=renderer' }).Count
        browserPrivateMB = $private
    }
}
# Process.HasExited lied for a browser started from a nested shell (LOCAL.md 40): found by command line.
function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function RunLeg([string]$title, [string]$log, [string[]]$extra, [string]$steps) {
    Write-Host ""
    Write-Host "==================== $title ====================" -ForegroundColor Cyan
    Write-Host $steps -ForegroundColor Yellow
    Write-Host @"
   HOW THIS RUN GOES:
     A. the browser opens now: do the numbered steps in it
     B. when you are done, close the browser window (its X, top right). Do not close tabs first.
   Nothing to press here: this window measures the browser by itself (one dot = one measurement).
"@ -ForegroundColor Cyan
    $t0 = Get-Date
    Start-Process -FilePath $exe -ArgumentList @($flags; $extra; "--log-file=`"$log`"") | Out-Null
    Start-Sleep 5
    $taken = New-Object System.Collections.Generic.List[object]
    $last = [datetime]::MinValue
    while ((BrowserPids).Count -gt 0) {
        Start-Sleep -Milliseconds 250
        if (((Get-Date) - $last).TotalSeconds -ge 3) {
            $s = Sample
            if ($s.browserPrivateMB -gt 0) { $taken.Add($s); Write-Host -NoNewline "." -ForegroundColor DarkGray }
            $last = Get-Date
        }
    }
    $exited = Get-Date
    Write-Host ""
    Write-Host ("  closed after {0:N0} s; {1} measurements" -f ($exited - $t0).TotalSeconds, $taken.Count) -ForegroundColor Green
    [pscustomobject]@{ launched = $t0.ToString("o"); exited = $exited.ToString("o"); samples = $taken.ToArray() }
}

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if (-not (Test-Path $live)) { Write-Host "ABORT: no 40-pinned-section.patch" -ForegroundColor Red; exit 1 }
    # Stale = a source file the patch names is newer than the binary. Not the .patch file itself: a
    # quilt refresh after the build rewrites it without changing any code (E15b met exactly that).
    $src = "$ws\helium-windows\build\src"
    $newest = Get-Content $live | Where-Object { $_ -like '+++ b/*' } | ForEach-Object { Get-Item (Join-Path $src $_.Substring(6)) } | Sort-Object LastWriteTime | Select-Object -Last 1
    if ((Get-Item $exe).LastWriteTime -lt $newest.LastWriteTime) { Write-Host "ABORT: $OutDir chrome.exe is older than $($newest.Name) (stale binary)" -ForegroundColor Red; exit 1 }
    # A quick relink can be siso skipping the work (LOCAL.md 41): the dll must carry the section's own line.
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'pins: drew ')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 40" -ForegroundColor Red; exit 1 }
    if (-not (Test-Path $keep)) { Write-Host "ABORT: needs the clean pre-import copy at $keep" -ForegroundColor Red; exit 1 }
    if ($Rehearsal) {
        if ((Test-Path $prof) -and $prof.EndsWith("-e15b-rehearsal")) { Remove-Item -Recurse -Force $prof }
        Write-Host "rehearsal profile: copying $keep -> $prof ..." -ForegroundColor Green
        robocopy $keep $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
    } elseif ($Reset) {
        Write-Host "putting the clean copy back: $keep -> $prof ..." -ForegroundColor Green
        Remove-Item -Recurse -Force $prof
        robocopy $keep $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
    } else {
        # testprofile already holds E14c's import (3,862 tabs, an import time): a run without -Reset
        # would import nothing and measure the old shape.
        Write-Host "ABORT: the gate needs -Reset (testprofile still holds E14c's tab-group import)" -ForegroundColor Red; exit 1
    }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    if (Test-Path "$prof\Default\Workspace Pins") { Write-Host "ABORT: the reset profile already has a pins file" -ForegroundColor Red; exit 1 }
    if (-not $Sidebar) { $Sidebar = "$ws\arc-made-up\StorableSidebar.json" }  # Arc's shape, made up (LOCAL.md 133)
    if (-not (Test-Path $Sidebar)) { Write-Host "ABORT: no such file: $Sidebar (make-test-profiles.py writes it)" -ForegroundColor Red; exit 1 }
    $env:HELIUM_ARC_SIDEBAR = $Sidebar
    Remove-Item $log1, $log2, $samples -EA SilentlyContinue

    if ($Rehearsal) {
        Write-Host @"

THIS IS THE REHEARSAL: a sample file (no Arc data), the DCHECK build, a throwaway profile. Nothing here
touches testprofile or Arc. Its job: crash the DCHECK build now, on a few rows, rather than later on
thousands -- and let you SEE the pinned section. The browser opens twice. Use the LEFT mouse button.
"@ -ForegroundColor Magenta
        $steps1 = @"
 1. [any workspace]  LEFT-click the + at the END of the rail (after the last workspace) -> "Import from Arc".
            EXPECT: a bubble "Imported 8 tabs from Arc", then "19 pinned tabs are now in the workspaces'
            pinned sections, in 2 folders. 2 tabs were skipped ...", and the "On startup" line. Click OK.
 2. EXPECT: you are still in the workspace you were in; no new tab opened. Two pinned tabs at the top
            (Arc's favorites). The rail has "Arc Sample One" (rocket icon) and "Arc Sample Two".
 3. LEFT-click "Arc Sample One" in the rail.
            EXPECT, from the top of the tab list: a PINNED SECTION of plain rows -- page names with a small
            icon each (a globe is fine), one row "Alpha" with a CLOSED folder icon -- then a thin line,
            then 6 ordinary tabs, greyed (asleep). The rows are not tabs: no close X, no tab shape.
 4. LEFT-click the "Alpha" row. EXPECT: its icon becomes an OPEN folder and new rows appear under it,
            pushed right: a folder "Beta" (closed) and 4 pages. LEFT-click "Beta": 5 more rows, pushed
            further right. LEFT-click "Alpha" again: everything under it goes away. Then open "Alpha" once
            more and LEAVE IT OPEN.
 5. LEFT-click a PAGE row (not a folder). EXPECT: nothing happens -- opening pages is the next part (E15c).
 6. LEFT-click "Arc Sample Two" in the rail. EXPECT: 4 page rows, the line, and one New Tab page below it.
 7. go back to "Arc Sample One", wait about 10 seconds, then close the browser window.
"@
        $steps2 = @"
 8. [wait]  the window restores BY ITSELF (no restore flag this time). LEFT-click "Arc Sample One".
            EXPECT: the pinned section is back, and "Alpha" is still OPEN (the pins file kept it).
 9. LEFT-click + -> "Import from Arc" AGAIN. EXPECT: "Imported 0 tabs from Arc" and "0 pinned tabs ...".
            Click OK. Nothing is added twice.
10. wait about 10 seconds, then close the browser window.
"@
    } else {
        Write-Host @"

THIS IS THE REAL IMPORT AND THE SCALE GATE: the made-up Arc file of Arc's real size, the normal build, testprofile reset to
before any import. Arc may stay open. The browser opens twice. Use the LEFT mouse button.
"@ -ForegroundColor Magenta
        $steps1 = @"
 1. [any workspace]  LEFT-click the + at the END of the rail -> "Import from Arc".
            EXPECT: the status line at the bottom-left counts ("Importing from Arc: N of M tabs"), far
            fewer tabs than last time (only favorites and Today). Then a bubble: "Imported N tabs", a line
            "... pinned tabs are now in the workspaces' pinned sections, in ... folders", and the
            "On startup" line. Click OK.
 2. EXPECT: you are still in the workspace you were in. The rail shows Arc's 3 spaces as 3 NEW
            workspaces at its END -- "Canary", "Private", "Work" a second time: a first import never takes
            a workspace by its name (patch 98), so the profile's own three stay as they were, empty.
 3. LEFT-click the LAST "Canary" on the rail (the import's, the biggest). EXPECT: a pinned section of
            rows at the top -- folders closed -- a thin line, then its Today tabs. Scroll the strip: smooth
            or choppy?
 4. LEFT-click the BIGGEST folder row (about 1,159 pages). EXPECT: its rows appear in about a second,
            and nothing loads (no tab spinner anywhere). Scroll through it. LEFT-click it again to close.
 5. wait about 10 seconds, then close the browser window. Count how long it takes to disappear.
"@
        $steps2 = @"
 6. count in your head from the moment a window appears until you can click something. Note the seconds.
 7. LEFT-click the import's 3 workspaces (the last 3 on the rail). EXPECT: each pinned section is
            back, Today tabs asleep.
 8. LEFT-click + -> "Import from Arc" AGAIN. EXPECT: "Imported 0 tabs" (or only the few Arc gained)
            and "0 pinned tabs". Click OK.
 9. wait about 10 seconds, then close the browser window. Count how long it takes to disappear.
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
function Stamp([string]$line) {
    if ($line -match '\[\d+:\d+:\d{4}/(\d{2})(\d{2})(\d{2})\.(\d{3}):') { return [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000.0 }
    return -1
}
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
# Every "pins: drew N row(s) ... in M ms" line of a log, as objects: an array of two-element arrays
# was unrolled by PowerShell on the way out of the function, and the draw check then compared nothing
# (the grader's own self-test caught it).
function Draws($lines) { @($lines | Where-Object { $_ -match 'pins: drew (\d+) row\(s\) of .* in (\d+) ms' } | ForEach-Object { $null = $_ -match 'pins: drew (\d+) row\(s\) of .* in (\d+) ms'; [pscustomobject]@{ rows = [int]$Matches[1]; ms = [int]$Matches[2] } }) }

$w1 = WsLines $log1; $w2 = WsLines $log2
if ($null -eq $w1) { Write-Host "FAIL: $log1 missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
$g = if (Test-Path $samples) { Get-Content $samples -Raw | ConvertFrom-Json } else { $null }

$doneRe = 'arc import: done: (\d+) tab\(s\), (\d+) pinned row\(s\), (\d+) folder\(s\), (\d+) group\(s\), (\d+) split\(s\), (\d+) workspace\(s\), (\d+) skipped, startup ([a-z ]+), (\d+) ms(, aborted)?'
$iStart = -1; $iDone = -1; $doneAt = -1; $pinnedRows = 0
for ($n = 0; $n -lt $w1.Count; $n++) {
    if ($iStart -lt 0 -and $w1[$n] -match 'arc import: start: (\d+) tab\(s\) planned') { $iStart = $n; $planned = [int]$Matches[1] }
    if ($iStart -ge 0 -and $iDone -lt 0 -and $w1[$n] -match $doneRe) { $iDone = $n; $done = $Matches; $doneAt = Stamp $w1[$n] }
}
Verdict "run 1: the import started and finished (step 1 was done in RUN 1)" (($iStart -ge 0) -and ($iDone -gt $iStart))
if ($iDone -gt $iStart -and $iStart -ge 0) {
    $inside = @($w1[($iStart + 1)..($iDone - 1)])
    $tabs = [int]$done[1]; $pinnedRows = [int]$done[2] + [int]$done[3]; $importS = [int]$done[9] / 1000
    Note ("imported {0} of {1} planned tabs; {2} pinned rows in {3} folders; {4} groups, {5} splits, {6} workspaces, {7} skipped, startup {8}, {9:N1} s{10}" -f $tabs, $planned, $done[2], $done[3], $done[4], $done[5], $done[6], $done[7], $done[8], $importS, $done[10])
    Verdict "the import was not aborted" (-not $done[10])
    Verdict "every planned tab was created" ($tabs -eq $planned -and $tabs -gt 0)
    Verdict "pinned tabs went to the pins file as rows, not tabs ($($done[2]) rows, $($done[3]) folders)" ([int]$done[2] -gt 0 -and [int]$done[3] -gt 0)
    Verdict "no workspace already had pinned rows (a fresh import)" (@($w1 | Where-Object { $_ -match 'already has pinned rows|pinned rows of .* not written' }).Count -eq 0)
    Verdict "one 'tab inserted' line per imported tab, all inside the import" (@($inside | Where-Object { $_ -match 'tab inserted at index' }).Count -eq $tabs)
    Verdict "the import never switched workspace or spawned a tab" (@($inside | Where-Object { $_ -match "active workspace ->|created workspace '[^']*'$" }).Count -eq 0)
    Verdict "startup was set to continue (or already was)" ($done[8] -match 'continue|unchanged')
    Note ("import time {0:N1} s (recorded, not gated)" -f $importS)
}
$d1 = Draws $w1
Verdict "run 1: the pinned section drew rows after the import (step 3)" (@($d1 | Where-Object { $_.rows -gt 0 }).Count -ge 1)

$restoreEnd = -1; $d2 = @()
if ($null -eq $w2) { Write-Host "FAIL: $log2 missing or EMPTY" -ForegroundColor Red; $script:failed++ } else {
    $loaded = @($w2 | Where-Object { $_ -match 'pins: loaded (\d+) row\(s\) in (\d+) workspace' })
    if ($loaded.Count) { $null = $loaded[0] -match 'pins: loaded (\d+) row\(s\)' ; $back = [int]$Matches[1] } else { $back = -1 }
    Verdict "run 2: the pins file loaded every row the import wrote ($back of $pinnedRows)" ($back -eq $pinnedRows -and $back -gt 0)
    $r = RestoreLoop $log2; $restoreEnd = $r.end
    Note ("restart: {0} tabs restored, restore loop ended {1:N1} s after the first log line" -f $r.restored, $r.seconds)
    if ($iDone -ge 0) { Verdict "restart restored at least every imported tab (no restore flag was passed)" ($r.restored -ge [int]$done[1]) }
    Verdict ("cold start: restore loop finished within {0} s ({1:N1} s)" -f $LimitColdStartS, $r.seconds) ($r.seconds -ge 0 -and $r.seconds -le $LimitColdStartS)
    $d2 = Draws $w2
    Verdict "run 2: the pinned section drew rows after the restart" (@($d2 | Where-Object { $_.rows -gt 0 }).Count -ge 1)
    $again = @($w2 | Where-Object { $_ -match $doneRe })
    if ($again.Count) { $null = $again[0] -match $doneRe; Verdict "last step: the re-run imported almost nothing ($($Matches[1]) tabs, $($Matches[2]) pinned rows; Arc may have gained a few tabs)" ([int]$Matches[1] -le 25 -and [int]$Matches[2] -eq 0) }
    else { Verdict "last step: the re-run happened (Import from Arc clicked again in RUN 2)" $false }
}
$draws = @($d1) + @($d2)
if ($draws.Count) {
    $big = $draws | Sort-Object rows | Select-Object -Last 1
    $slow = $draws | Sort-Object ms | Select-Object -Last 1
    Note ("{0} draws; the biggest {1} rows in {2} ms" -f $draws.Count, $big.rows, $big.ms)
    Verdict ("every draw within {0} ms: the slowest was {1} rows in {2} ms (rows made; the paint follows)" -f $LimitDrawMs, $slow.rows, $slow.ms) ($slow.ms -le $LimitDrawMs)
}
if ($g) {
    foreach ($leg in @(@{ n = "run 1"; v = $g.leg1; log = $log1; after = $doneAt }, @{ n = "run 2"; v = $g.leg2; log = $log2; after = $restoreEnd })) {
        if (-not $leg.v) { Write-Host "FAIL  $($leg.n): no measurement (the script did not get that far)" -ForegroundColor Red; $script:failed++; continue }
        $close = @(Get-Content $leg.log | Where-Object { $_ -match '\[workspaces\] removed \d+ tab' }) | Select-Object -Last 1
        $closeS = if ($close) { Stamp $close } else { DayS $leg.v.exited }
        $usable = @($leg.v.samples | Where-Object { $t = DayS $_.at; $t -ge $leg.after + 1 -and $t -le $closeS - 1 })
        Verdict "$($leg.n): measured after the import/restore and before the close ($($usable.Count) of $(@($leg.v.samples).Count) measurements)" ($usable.Count -ge 1)
        if ($usable.Count) {
            $s = $usable[-1]
            Note ("{0}: last measurement {1} processes, {2} renderers, browser {3} MB private" -f $leg.n, $s.processes, $s.renderers, $s.browserPrivateMB)
            Verdict "$($leg.n): browser process under $LimitBrowserMB MB" ($s.browserPrivateMB -gt 0 -and $s.browserPrivateMB -le $LimitBrowserMB)
            Verdict "$($leg.n): nothing loads to draw the rows (renderers <= 20)" ($s.renderers -ge 0 -and $s.renderers -le 20)
        }
        $exitS = if ($close) { (DayS $leg.v.exited) - $closeS } else { -1 }
        Verdict ("$($leg.n): exit took {0:N1} s from the window close (limit $LimitExitS)" -f $exitS) ($exitS -ge 0 -and $exitS -le $LimitExitS)
    }
} else { Write-Host "FAIL: no measurements file ($samples)" -ForegroundColor Red; $script:failed++ }
$pins = Get-Item "$prof\Default\Workspace Pins" -EA SilentlyContinue
if ($pins) { Note ("pins file {0:N0} KB (recorded, not gated)" -f ($pins.Length / 1KB)) }
$markers = (Get-Content $log1, $log2 -EA SilentlyContinue | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the logs" ($markers -eq 0)
Write-Host "`nOwner-observed: rows above a thin line above the tabs; folders open and close; a page row opens nothing yet; the open folder kept after the restart; scrolling smooth; your own start and close counts."
Write-Host "Logs: $log1, $log2. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
