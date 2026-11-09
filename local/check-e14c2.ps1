param([switch]$GradeOnly,
      [string]$Log = "<local-path>\Helium-workspace\e14c2-run.log",
      [string]$Guid = "",
      [int]$ExpectTitles = 4)
# E14c.2 (LOCAL.md 42): "Close group" needs no count confirm, because closing a group is ONE Recently
# Closed entry holding every tab of it (TabRestoreServiceHelper::CreateHistoricalGroup), each tab's
# workspace tag, anchor and custom title riding in its extra_data -- unlike Close all tabs (32), where
# every tab is its own entry and only the last 25 survive. Reading said so; this proves it on a
# throwaway copy of the imported testprofile, release build, owner at the keyboard.
# -GradeOnly re-grades a log (-Guid names Canary when the copy is gone).
#
# Why the steps are shaped this way:
# - the reopen is done FROM HOME: a tab that lost its tag is stamped with the ACTIVE workspace, so a
#   reopen inside Canary reads the same whether the tag came back or not (LOCAL.md 16);
# - the group is closed a SECOND time: a restored anchor logs nothing, so the second close's
#   "K anchored" is the proof that the anchors came back;
# - Arc Basics is the only group holding renamed tabs ($ExpectTitles of its 8 in Arc's file);
# - the 1,159-tab group is optional, and only timed.
# The grader reads events in log order, never a line count (LOCAL.md 30).
$ws   = "<local-path>\Helium-workspace"
$prof = "$ws\testprofile-e14c2"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$last = "$ws\helium-windows\patches\local\workspaces\37-strip-bulk-layout.patch"
# Process.HasExited lies for a browser started from a nested shell (LOCAL.md 40): find it by command line.
function BrowserPid { $b = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' }); if ($b.Count) { $b[0].ProcessId } else { 0 } }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $last).LastWriteTime) { Write-Host "ABORT: chrome.exe is older than patch 37 (stale binary)" -ForegroundColor Red; exit 1 }
    if (Test-Path $prof) { [IO.Directory]::Delete($prof, $true) }
    robocopy "$ws\testprofile" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
    Write-Host "copied testprofile -> $prof (robocopy $LASTEXITCODE)"
    if (-not (Select-String -Path "$prof\Default\Secure Preferences" -Pattern '"restore_on_startup"\s*:\s*1\b' -Quiet)) { Write-Host "ABORT: the copy's 'On startup' is not 'Continue where you left off' -- it would open empty" -ForegroundColor Red; exit 1 }
    # Recently Closed starts EMPTY in the copy. testprofile's (Tabs_*, TabRestoreService's file) holds a
    # 3,864-tab WINDOW entry from the E14c gate; the first run's Ctrl+Shift+T found nothing newer, reopened
    # it, froze 3 minutes and CHECK-crashed in RestoreSplit (LOCAL.md 42). Only the copy is touched.
    Get-ChildItem "$prof\Default\Sessions" -Filter 'Tabs_*' | Remove-Item
    if (Get-ChildItem "$prof\Default\Sessions" -Filter 'Tabs_*') { Write-Host "ABORT: the copy's Recently Closed could not be emptied" -ForegroundColor Red; exit 1 }
    if (Test-Path $Log) { [IO.File]::Delete($Log) }
}
if (-not $Guid) {
    $show = & python "$ws\helium\local\set-workspaces-pref.py" $prof --show
    $ok = $LASTEXITCODE -eq 0
    $show | Select-Object -Last 2 | Write-Host
    if (-not $ok) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    $Guid = @($show | Where-Object { $_ -match '^\s+(\S+)\s+Canary\s*$' } | ForEach-Object { ($_.Trim() -split '\s+')[0] })[0]
    if (-not $Guid) { Write-Host "ABORT: no workspace called 'Canary' in $prof" -ForegroundColor Red; exit 1 }
}
Write-Host "Canary = $Guid"

if (-not $GradeOnly) {
    Write-Host @"

THE STEPS. The window takes about 2 minutes to fill (the known cold start); wait until it answers
(the tab list scrolls) before step 1. Canary is the workspace on screen. Every group in it
is collapsed, and group headers are counted from the TOP of the tab list.

 RIGHT-CLICK means the RIGHT mouse button. A LEFT click on a group header only opens or folds the
 group -- that is what happened on the first run, and it closes nothing. The right-click opens a small
 panel: a name box at the top, colour dots, then a list ending in "Close group", "Ungroup", "Delete group".
 If a NEW WINDOW ever opens, stop and tell Claude.

 1. [Canary] RIGHT-click the 9TH group header: a folder under "Imported From Chrome > Bookmarks bar" (26 tabs).
      The name box shows the name; if it is not that 26-tab folder, press Esc and try the next header.
      Click "Close group" -- NOT "Delete group".                EXPECT: that header disappears.
 2. [Canary] click HOME in the rail at the bottom of the tab list.
 3. [Home] press Ctrl+Shift+T once.
      EXPECT: that group is back, in this same window. The window may jump to Canary by
      itself; if it stays in Home, click Canary in the rail. The header may sit somewhere else.
 4. [Canary] RIGHT-click that group's header -> "Close group" again.  EXPECT: gone. Do NOT reopen it.
 5. OPTIONAL, the scale test -- expect a frozen window each way, maybe 1-3 minutes:
    [Canary] RIGHT-click the 2ND group header, "Imported From Chrome > Bookmarks bar" (1,159 tabs)
      -> "Close group". Wait until the window answers. Press Ctrl+Shift+T. Wait until it answers.
      EXPECT: the group is back. Note roughly how long each wait felt.
 6. LAST on purpose (it holds a split view, the ingredient of the first run's crash):
    [Canary] RIGHT-click the 1ST group header, "Arc Basics" (8 tabs) -> "Close group". Press Ctrl+Shift+T.
      EXPECT: Arc Basics is back; LEFT-click its header to open it: four tabs read Pinned Tabs, Spaces,
      Split View and Import Bookmarks (the names from Arc, not the long page titles).
 7. Close the browser WINDOW. Exiting takes about 3 minutes (the known close); this script waits, then grades.

"@ -ForegroundColor Yellow
    Start-Process -FilePath $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--log-file=`"$Log`"") | Out-Null
    Start-Sleep 5
    $n0 = -1; $stable = 0; $t = 0
    while ((BrowserPid) -and $stable -lt 15 -and $t -lt 900) {
        Start-Sleep 3; $t += 3
        $n = if (Test-Path $Log) { (Select-String -Path $Log -Pattern 'tab inserted at index' | Measure-Object).Count } else { 0 }
        if ($n -ne $n0) { $n0 = $n; $stable = 0 } else { $stable += 3 }
    }
    Write-Host "READY: the restore settled at $n0 tabs, $t s after launch. Do the steps; close the window when done." -ForegroundColor Cyan
    $t = 0; while ((BrowserPid) -and $t -lt 7200) { Start-Sleep 3; $t += 3 }
    if (BrowserPid) { Stop-Process -Id (BrowserPid) -Force; Write-Host "force-stopped after 2 hours" }
    $w = 0; while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') -and $w -lt 60) { Start-Sleep 1; $w++ }
}

# ---- grading -------------------------------------------------------------------------------
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$script:failed = 0
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: $Log missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }

# R = a removal (N tabs, A anchored), I = an insert (workspace W while Act was active), T = a restored custom title.
$ev = New-Object System.Collections.Generic.List[object]
foreach ($line in Get-Content $Log) {
    $ts = $null
    if ($line -match '\[\d+:\d+:\d{4}/(\d\d)(\d\d)(\d\d)\.(\d{3}):') { $ts = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + [int]$Matches[4] / 1000 }
    if     ($line -match "\[workspaces\] removed (\d+) tab\(s\), (\d+) anchored") { $ev.Add([pscustomobject]@{ K = 'R'; N = [int]$Matches[1]; A = [int]$Matches[2]; T = $ts }) }
    elseif ($line -match "\[workspaces\] tab inserted at index \d+ -> workspace '([^']*)' \(active '([^']*)'\)") { $ev.Add([pscustomobject]@{ K = 'I'; W = $Matches[1]; Act = $Matches[2]; T = $ts }) }
    elseif ($line -match "\[workspaces\] restored custom title '") { $ev.Add([pscustomobject]@{ K = 'T'; T = $ts }) }
}
$rs = @(for ($n = 0; $n -lt $ev.Count; $n++) { if ($ev[$n].K -eq 'R') { $n } })
# The events after removal p and before the next one: what that close's Ctrl+Shift+T brought back.
function Segment([int]$p) { $to = if ($p + 1 -lt $rs.Count) { $rs[$p + 1] - 1 } else { $ev.Count - 1 }; if ($rs[$p] + 1 -gt $to) { return @() }; return @($ev[($rs[$p] + 1)..$to]) }
function Back($seg) { @($seg | Where-Object { $_.K -eq 'I' -and $_.W -eq $Guid }) }

$startup = if ($rs.Count) { $rs[0] } else { $ev.Count }
# 0..-1 is the two indexes 0 and -1 in PowerShell, not an empty range.
$pre = if ($startup -gt 0) { @($ev[0..($startup - 1)]) } else { @() }
Write-Host "`n--- $(@($pre | Where-Object K -eq 'I').Count) tabs restored at startup; removals after it: $(($rs | ForEach-Object { "$($ev[$_].N)/$($ev[$_].A)" }) -join '  ')"
# Step 1 is the FIRST removal after startup, or nothing is graded: on the first run a stray Ctrl+Shift+T
# moved every group into a new window, and "the first removal over 25" graded that move as the test.
if (-not $rs.Count -or $ev[$rs[0]].N -le 25) { Verdict "step 1: the first thing removed after startup is a group of more than 25 tabs (got $(if ($rs.Count) { $ev[$rs[0]].N } else { 'nothing' }))" $false } else {
    $p = 0; $ra = $ev[$rs[$p]]; $back = Back (Segment $p)
    Verdict "step 1: a real close of $($ra.N) tabs (> 25), all anchored ($($ra.A) of $($ra.N))" ($ra.N -gt 25 -and $ra.A -eq $ra.N)
    Verdict "step 3: Ctrl+Shift+T brought all $($ra.N) back into Canary (got $($back.Count))" ($back.Count -eq $ra.N)
    $elsewhere = @($back | Where-Object Act -ne $Guid).Count
    Verdict "step 3: reopened from another workspace, so the tags were CARRIED, not stamped ($elsewhere inserted while '$(@($back | Where-Object Act -ne $Guid)[0].Act)' was active)" ($elsewhere -ge 1)
    if ($p + 1 -lt $rs.Count) {
        $rb = $ev[$rs[$p + 1]]
        Verdict "step 4: the second close removed the same $($ra.N) tabs with the same $($ra.A) anchored -> anchors came back (got $($rb.N)/$($rb.A))" ($rb.N -eq $ra.N -and $rb.A -eq $ra.A)
    } else { Verdict "step 4: the group was closed a second time" $false }
    # Steps 5 and 6 in either order, each a removal that something came back after: the big group is
    # 100-2,000 tabs, Arc Basics 25 or fewer. The window close at the end brings nothing back.
    $c = -1; $d = -1
    for ($n = $p + 2; $n -lt $rs.Count; $n++) {
        if (-not (Back (Segment $n)).Count) { continue }
        $x = $ev[$rs[$n]].N
        if ($c -lt 0 -and $x -le 25) { $c = $n }
        if ($d -lt 0 -and $x -ge 100 -and $x -le 2000) { $d = $n }
    }
    if ($c -ge 0) {
        $rc = $ev[$rs[$c]]; $seg = Segment $c; $titles = @($seg | Where-Object K -eq 'T').Count
        Verdict "step 6: Arc Basics ($($rc.N) tabs) came back: $((Back $seg).Count) into Canary, $titles of $ExpectTitles custom titles restored" ((Back $seg).Count -eq $rc.N -and $titles -eq $ExpectTitles)
    } else { Verdict "step 6: Arc Basics was closed and reopened" $false }
    if ($d -lt 0) { Write-Host "SKIP  step 5 (optional): no close of a big group" -ForegroundColor DarkYellow } else {
        $rd = $ev[$rs[$d]]; $back = Back (Segment $d)
        Verdict "step 5: all $($rd.N) tabs of the big group came back (got $($back.Count))" ($back.Count -eq $rd.N)
        if ($back.Count -and $null -ne $rd.T) {
            $span = $back[-1].T - $back[0].T
            Write-Host ("      reopen: {0} inserts in {1:N1} s ({2:N0} ms/tab); Ctrl+Shift+T came {3:N0} s after the close was logged" -f $back.Count, $span, (1000 * $span / $back.Count), ($back[0].T - $rd.T))
        }
    }
}
$markers = (Select-String -Path $Log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|dangling|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers ($markers)" ($markers -eq 0)
Write-Host "`nOwner-observed, not gradeable from a log: each header disappears and comes back; Arc Basics shows the four Arc names."
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green; exit 0 }
