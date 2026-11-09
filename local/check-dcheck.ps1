# Runs the LOCAL.md 5.8.1 check -- "a chunk that adds or changes a views::View is
# not done until out/Dcheck has been LAUNCHED" -- in the one form that cannot
# quietly answer the wrong question.
#
# Why this is a script and not four lines of instructions. 5.8.1 WAS four lines
# of instructions, and on 2026-09-13 (E9e part 2, LOCAL.md 22) they produced a
# clean pass on a log that was zero bytes long. Three traps, and every one of
# them looks like success:
#
#   1. THE FORWARDED LAUNCH. A profile folder may only be used by one browser at
#      a time, so a second Chromium started against a --user-data-dir that is
#      already in use does not start a browser at all: it hands its command line
#      to the running instance and exits. The release build was still open, so
#      out/Dcheck created its log file, handed off, and died -- and every window
#      exercised afterwards belonged to the RELEASE build, where DCHECKs are
#      compiled out. check-gate.ps1 has guarded this since E6c in as many words:
#      "a forwarded launch would log into its window, not ours."
#
#   2. AN EMPTY LOG GREPS EXACTLY LIKE A CLEAN ONE. "No output" from the grep
#      means either "nothing bad happened" or "nothing happened at all", and the
#      two are indistinguishable from the result. 8 says the same thing about the
#      gate check: if logging is off, no line means nothing at all. So this
#      script refuses to report a verdict until the log has bytes in it.
#
#   3. A STALE BINARY answers the previous chunk's question. Guarded as in
#      check-gate.ps1 and 12.
#
#   4. A LOG THAT NEVER REACHED THE NEW CODE greps exactly like a clean one
#      too. Guards 1-3 prove the right binary started and that logging works.
#      NONE of them proves the chunk's own code ran, and on 2026-09-14 (E9e.4)
#      that gap produced a green PASS over a 13,969-byte log in which
#      Reconcile() had never once executed: the test profile had been left in
#      CLASSIC layout by the previous step, where the rail, the toggle and the
#      visibility predicate are all switched off by design 2.8, so every
#      workspace code path correctly declined to run. The log printed
#      "[workspaces]: 1 lines" -- a startup tab insert -- and the script
#      reported success, because counting those lines was information rather
#      than a gate.
#
#      -Expect closes it: give the pattern the exercise must produce, and a run
#      that does not produce it FAILS. Run --show on the profile first; a
#      NOT READY profile is how you get here.
#
#        .\local\check-dcheck.ps1 -Chunk e9e4 -Expect "reconcile:"
#
# A dead process with a NON-empty log is not a failure of this script -- it is
# the E9a case, the one this whole directory exists for: the browser died on the
# first paint of a new view. The log is read either way.
#
#   .\local\check-dcheck.ps1 -Chunk e9e2 -Expect "moved workspace"
#   .\local\check-dcheck.ps1 -Chunk e9f -OutDir Default -Expect "relayout requested"
#
# -OutDir Default runs the same guards over the RELEASE build, which is what an
# owner-verification list actually exercises. Before E9f that launch was a bare
# chrome.exe command line with no guard on it at all.
#
# Run it in an ordinary PowerShell window: it waits for you to exercise the UI
# and press Enter, so it cannot be driven from an agent turn.

param(
    [Parameter(Mandatory = $true)]
    [string]$Chunk,
    [string]$ProfileDir = "<local-path>\Helium-workspace\testprofile",
    # "Dcheck" runs the 5.8.1 check. "Default" runs the SAME four guards over
    # the release build, which every owner-verification list needs and which was
    # hand-rolled as a bare chrome.exe command line up to E9e.4 -- so none of the
    # guards applied to it. Duplicating them into a second script is how they
    # drift; one parameter is cheaper than two copies.
    [ValidateSet("Dcheck", "Default")]
    [string]$OutDir = "Dcheck",
    [int]$LogWaitSeconds = 90,
    # A pattern the exercise MUST produce, or the run is reported as a failure
    # rather than a pass. See trap 4 below.
    [string]$Expect = "",
    # Restart into the last session (testprofile has no restore_on_startup). R4:
    # lazy session restore is new upstream code our insert-time stamping rides on,
    # and without this switch a Dcheck launch never runs it.
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

$exe       = "<local-path>\Helium-workspace\helium-windows\build\src\out\$OutDir\chrome.exe"
# The LIVE patch (helium-windows), NOT the committed copy in this repo. quilt
# refreshes the live one and then you build, so its timestamp genuinely precedes
# the binary. The committed copy is re-stamped by `cp` at sync time -- 5.7 step 3
# -- which happens AFTER the build, so comparing against it reports every landed
# chunk as stale. Found by running this script for the first time, immediately
# after landing E9e part 2.
$patchDir  = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces"
# "dcheck" is kept verbatim for the Dcheck build so 16's log naming and every
# LOCAL.md reference to it still resolve.
$tag       = if ($OutDir -eq "Dcheck") { "dcheck" } else { "run" }
$log       = "<local-path>\Helium-workspace\$Chunk-$tag-exercise.log"

# The five words. Deliberately NOT the bare string "DCHECK": Select-String is
# case-insensitive, so a test URL or a path containing "dcheck" matches it and
# reads as twenty failures that are not there (5.8).
$danger = "Check failed|FATAL|ReentrancyCheck|dangling|NOTREACHED"

function Fail($msg) { Write-Host "ABORT: $msg" -ForegroundColor Red; exit 1 }

# --- guard 1: the binary exists and is not the previous chunk's -------------
if (-not (Test-Path $exe)) {
    Fail "no out\$OutDir\chrome.exe. Build it first:`n       .\resume-build.ps1 -OutDir $OutDir -Targets chrome"
}
$newestPatch = Get-ChildItem "$patchDir\*.patch" | Sort-Object LastWriteTime | Select-Object -Last 1
if ((Get-Item $exe).LastWriteTime -lt $newestPatch.LastWriteTime) {
    Write-Host "ABORT: out\$OutDir\chrome.exe is OLDER than $($newestPatch.Name)." -ForegroundColor Red
    Write-Host "       exe:   $((Get-Item $exe).LastWriteTime)" -ForegroundColor Red
    Write-Host "       patch: $($newestPatch.LastWriteTime)" -ForegroundColor Red
    Write-Host "       This binary predates the chunk; any result would answer the previous one." -ForegroundColor Red
    exit 1
}

# --- guard 2: nothing of ours is running (the forwarded launch) -------------
$running = @(Get-Process chrome -ErrorAction SilentlyContinue |
             Where-Object { $_.Path -like '*Helium-workspace*' })
if ($running.Count -gt 0) {
    Write-Host "ABORT: $($running.Count) fork process(es) are already running." -ForegroundColor Red
    Write-Host "       A second Chromium on the same --user-data-dir does not start a browser -- it" -ForegroundColor Red
    Write-Host "       forwards its command line to the running one and exits, so out\Dcheck would" -ForegroundColor Red
    Write-Host "       never run and this check would pass on an empty log (LOCAL.md 22)." -ForegroundColor Red
    Write-Host "       Close them with:" -ForegroundColor Yellow
    Write-Host "       Get-Process chrome | Where-Object { `$_.Path -like '*Helium-workspace*' } | Stop-Process -Force" -ForegroundColor Yellow
    exit 1
}

# --- guard 0: the profile can answer the question being asked of it --------
# E9e.4 ran this whole script against a profile left in CLASSIC layout by the
# previous step, where design 2.8 switches the feature off entirely -- so every
# workspace path correctly declined to run and the result was a green pass over
# nothing. --show already knew; nobody had asked it. Now the script does.
$show = & python "<local-path>\Helium-workspace\helium\local\set-workspaces-pref.py" $ProfileDir --show 2>&1
$showOk = $LASTEXITCODE -eq 0
$show | ForEach-Object { Write-Host "  $_" }
if (-not $showOk) {
    Write-Host ""
    Write-Host "ABORT: the profile cannot answer a workspaces question in this state." -ForegroundColor Red
    Write-Host "       Repair it (the browser is closed, so this is safe) -- the line above" -ForegroundColor Yellow
    Write-Host "       names which of these you need:" -ForegroundColor Yellow
    Write-Host "       python local\set-workspaces-pref.py $ProfileDir --layout vertical" -ForegroundColor Yellow
    Write-Host "       python local\set-workspaces-pref.py $ProfileDir true" -ForegroundColor Yellow
    exit 1
}

Remove-Item $log -ErrorAction SilentlyContinue

Write-Host "launching out\$OutDir against $ProfileDir ..." -ForegroundColor Yellow
$launchArgs = @(
    "--user-data-dir=$ProfileDir",
    "--enable-logging", "--log-file=$log", "--v=0",
    "--no-first-run", "--no-default-browser-check"
)
# Built BEFORE the call: after a command name "@(...) + ..." is not arithmetic, the "+" is just
# another argument, and Start-Process refuses it ("positional parameter ... '+'", R4).
if ($Restore) { $launchArgs += "--restore-last-session" }
$proc = Start-Process $exe -PassThru -ArgumentList $launchArgs

# --- guard 3: the positive control -- prove the instrument works ------------
# Waiting for BYTES, not for the file: the forwarded launch creates the file and
# writes nothing. A startup DCHECK writes the FATAL line and dies, which is a
# result rather than an abort, so this loop is happy either way.
$deadline = (Get-Date).AddSeconds($LogWaitSeconds)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 0) { break }
    Start-Sleep -Milliseconds 500
}
$startSize = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }
if ($startSize -eq 0) {
    Write-Host "ABORT: the log is still 0 bytes after $LogWaitSeconds s -- NOTHING HAS BEEN CHECKED." -ForegroundColor Red
    Write-Host "       Either the launch was forwarded to another instance, or the logging flags" -ForegroundColor Red
    Write-Host "       did not take. A grep of this file would return silence for the wrong reason." -ForegroundColor Red
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Host "  log has $startSize bytes -- the instrument works, a silent result now means something." -ForegroundColor Green

if ($proc.HasExited) {
    Write-Host "  NOTE: the browser has already exited. With a non-empty log that is the E9a case" -ForegroundColor Yellow
    Write-Host "        -- died on the first paint of a new view. Reading the log anyway." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "Now EXERCISE the thing this chunk changed -- open the menus, click the items," -ForegroundColor Cyan
    Write-Host "switch workspaces. Building this binary proves nothing; the check is at runtime." -ForegroundColor Cyan
    Read-Host "Press Enter when done"
}

# --- the check --------------------------------------------------------------
$hits = @(Select-String -Path $log -Pattern $danger)
$wsLines = @(Select-String -Path $log -SimpleMatch "[workspaces]").Count

# Re-measured, NOT the $startSize above. That one was taken the moment the log
# first had bytes in it -- seconds after launch, before you exercised anything --
# and printing it beside a grep of the FINISHED file describes a different file
# than the one that was checked. E9e.3 reported "296 bytes" for a log that ended
# at 19 MB. The verdict was sound; the number was not, and a number that reads as
# evidence while measuring something else is what 22 is about.
$size = if (Test-Path $log) { (Get-Item $log).Length } else { 0 }

Write-Host ""
Write-Host "log:              $log"
Write-Host "size:             $size bytes (was $startSize at launch)"
Write-Host "[workspaces]:     $wsLines lines"
Write-Host ""
# --- guard 4: the exercise actually reached the code under test -------------
# Checked BEFORE the danger grep is reported, because "no crash" is not a
# result worth printing about code that never ran.
if ($Expect -ne "") {
    $expectHits = @(Select-String -Path $log -Pattern $Expect)
    Write-Host "expected ($Expect): $($expectHits.Count) line(s)"
    if ($expectHits.Count -eq 0) {
        Write-Host ""
        Write-Host "FAIL: nothing in the log matches '$Expect' -- THE CODE UNDER TEST NEVER RAN." -ForegroundColor Red
        Write-Host "      A clean grep over a log that never reached the new code is not a pass." -ForegroundColor Red
        Write-Host "      Most likely the profile was not in a state the feature runs in. Check it:" -ForegroundColor Yellow
        Write-Host "      python local\set-workspaces-pref.py $ProfileDir --show" -ForegroundColor Yellow
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        exit 1
    }
} else {
    Write-Host "WARNING: no -Expect given, so this run proves 'did not crash' and NOT" -ForegroundColor Yellow
    Write-Host "         'the new code ran'. Pass -Expect <pattern> to gate on that." -ForegroundColor Yellow
}

if ($hits.Count -eq 0) {
    Write-Host "PASS: none of $danger in a $size-byte log." -ForegroundColor Green
} else {
    Write-Host "FAIL: $($hits.Count) hit(s)." -ForegroundColor Red
    $hits | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor Red }
}

if (-not $proc.HasExited) {
    Write-Host ""
    Write-Host "closing the instance this script started (PID $($proc.Id))." -ForegroundColor Yellow
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
