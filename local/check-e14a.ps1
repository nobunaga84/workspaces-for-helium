param([switch]$GradeOnly,
      [string]$Log1 = "<local-path>\Helium-workspace\e14a-run1.log",
      [string]$Log2 = "<local-path>\Helium-workspace\e14a-run2.log")
# E14a smoke test (LOCAL.md 38): the X button, a middle-click and the tab menu's "Close tab" RESET
# an anchored tab like Ctrl+W does; "Close other tabs" skips anchored tabs; a multi-selection
# still closes for real. Two launches against testprofile: the exercise, then a restart with
# --restore-last-session for the never-loaded anchor. -GradeOnly re-grades existing logs.
#
# The grader reads EVENTS IN ORDER, never a line count (LOCAL.md 30): every diverted close logs
# "close of an anchored tab diverted (<door>)", every real close logs "removed N tab(s), K anchored".
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check")
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\34-anchor-close-reset.patch"

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if (-not (Test-Path $live)) { Write-Host "ABORT: no 34-anchor-close-reset.patch" -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe is older than patch 34 (stale binary)" -ForegroundColor Red; exit 1 }
    & python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    Remove-Item $Log1, $Log2 -EA SilentlyContinue

    Write-Host @"

RUN 1 -- every step is done IN THE WORK WORKSPACE unless it says otherwise.
 1. [Home]  click WORK in the rail. [Work] open three more tabs and load, one in each:
            https://example.com   https://example.org   https://example.net
            (Tabs already in Work from older tests do not matter. Leave them.)
 2. [Work]  right-click the example.COM tab -> Anchor -> "Anchor to this page". Same for the example.ORG tab.
            example.NET stays a plain tab.
 3. [Work]  click the example.COM tab so it is ACTIVE, then click its X.
            EXPECT: it is NOT closed. Another tab becomes active; example.com stays in the strip, asleep.
 4. [Work]  click example.NET so it is active. MIDDLE-CLICK (wheel click) the example.ORG tab.
            EXPECT: example.org is NOT closed; it stays in the strip, asleep.
 5. [Work]  click the X of the sleeping example.COM tab again (hover it to see the X; do not click the tab itself).
            EXPECT: nothing happens at all. That is the rule you accepted: an anchor leaves only by Remove anchor.
 6. [Work]  click example.COM (it wakes and reloads). Right-click it -> "Close tab".
            EXPECT: not closed; asleep again.
 7. [Work]  click example.COM again (wakes). Press Ctrl+W.
            EXPECT: not closed; asleep again. (The old path, re-routed by this patch.)
 8. [Work]  right-click the example.NET tab -> "Close other tabs".
            EXPECT: the plain tabs in Work close; example.COM and example.ORG both STAY.
 9. [Work]  click example.NET, then Ctrl+click example.COM (two tabs selected). Right-click one -> "Close tabs".
            EXPECT: BOTH really close -- a multi-selection is a real close.
10. [Work]  click the X of example.ORG (the last anchor).  EXPECT: it stays.
11. Click HOME in the rail, so a Home tab is the active one. Then close the browser WINDOW (do not close tabs first).

"@ -ForegroundColor Yellow
    Start-Process -FilePath $exe -ArgumentList @($flags; "--log-file=`"$Log1`"") -Wait
    Start-Sleep 2
    if (-not (Test-Path $Log1) -or (Get-Item $Log1).Length -eq 0) { Write-Host "FAIL: run-1 log missing or EMPTY" -ForegroundColor Red; exit 1 }

    Write-Host @"

RUN 2 -- the window restores; the Work tabs have NOT been loaded since the restart.
12. [Home]  click WORK in the rail. Do NOT click the example.ORG tab. Click its X.
            EXPECT: it stays in the strip.
13. [Work]  now click example.ORG (it loads). Press Ctrl+W.  EXPECT: not closed; asleep -> the anchor survived.
14. [Work]  tidy up: right-click example.ORG -> Anchor -> "Remove anchor", then click its X.  EXPECT: it closes for real.
15. Close the browser window.

"@ -ForegroundColor Yellow
    Start-Process -FilePath $exe -ArgumentList @($flags; "--restore-last-session"; "--log-file=`"$Log2`"") -Wait
    Start-Sleep 2
}

# ---- grading -------------------------------------------------------------------------------
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$script:failed = 0

# One token per event, in log order: H:<url> hibernated, K kept live, D:<door> diverted, R:<n>:<k> removed.
function Events($path) {
    if (-not (Test-Path $path) -or (Get-Item $path).Length -eq 0) { return $null }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content $path) {
        if     ($line -match "\[workspaces\] hibernated anchored tab at index \d+ -> '([^']*)'") { $out.Add("H:" + $Matches[1]) }
        elseif ($line -match "\[workspaces\] anchored tab at index \d+ (asks before leaving|could not be discarded)") { $out.Add("K") }
        elseif ($line -match "\[workspaces\] close of an anchored tab diverted \(([^)]*)\)") { $out.Add("D:" + $Matches[1]) }
        elseif ($line -match "\[workspaces\] removed (\d+) tab\(s\), (\d+) anchored") { $out.Add("R:" + $Matches[1] + ":" + $Matches[2]) }
        elseif ($line -match "\[workspaces\] anchor at index \d+ -> ''") { $out.Add("U") }
    }
    return ,$out.ToArray()
}
# Window k (1-based) = the events after diverted-close k-1 (or the start) and before diverted-close k;
# k = count+1 is everything after the last one. 1-based on purpose: a literal -1 argument is read by
# PowerShell as a parameter NAME, and the function then silently gets nothing (found by running this).
function Window($ev, [int]$k) {
    $d = @(); for ($n = 0; $n -lt $ev.Count; $n++) { if ($ev[$n] -like "D:*") { $d += $n } }
    $from = if ($k -le 1) { 0 } else { $d[$k - 2] + 1 }
    $to   = if ($k -le $d.Count) { $d[$k - 1] - 1 } else { $ev.Count - 1 }
    if ($from -gt $to) { return @() }
    return @($ev[$from..$to])
}
function AnchoredRemoved($evs) { ($evs | Where-Object { $_ -like "R:*" } | ForEach-Object { [int]($_.Split(":")[2]) } | Measure-Object -Sum).Sum }

$e1 = Events $Log1
if ($null -eq $e1) { Write-Host "FAIL: $Log1 missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
Write-Host "`n--- run 1 events: $($e1 -join '  ')"
$doors1 = @($e1 | Where-Object { $_ -like "D:*" })
$cb = "D:close button or middle-click"
Verdict "run 1: the six diverted closes arrive in order (X, middle, X-asleep, menu, Ctrl+W, X)" (($doors1 -join "|") -eq (@($cb, $cb, $cb, "D:tab menu", "D:Ctrl+W", $cb) -join "|"))
if ($doors1.Count -ge 6) {
    Verdict "step 3: X on the ACTIVE anchor hibernated it at example.com"     ((Window $e1 1) -contains "H:https://example.com/")
    Verdict "step 4: middle-click on a BACKGROUND anchor hibernated example.org" ((Window $e1 2) -contains "H:https://example.org/")
    Verdict "step 5: X on an anchor already asleep did nothing (no hibernate, no removal)" (@(Window $e1 3).Count -eq 0)
    Verdict "step 6: tab menu 'Close tab' hibernated it"                       (@(Window $e1 4 | Where-Object { $_ -like "H:*" }).Count -eq 1)
    Verdict "step 7: Ctrl+W still hibernates through the shared door"          (@(Window $e1 5 | Where-Object { $_ -like "H:*" }).Count -eq 1)
    $before = @(); for ($i = 1; $i -le 5; $i++) { $before += Window $e1 $i }
    Verdict "steps 3-7: no anchored tab was removed by any of the five"        ((AnchoredRemoved $before) -eq 0)
    $w = @(Window $e1 6)
    $firstAnch = -1; for ($n = 0; $n -lt $w.Count; $n++) { if ($w[$n] -like "R:*" -and [int]($w[$n].Split(":")[2]) -gt 0) { $firstAnch = $n; break } }
    $plainFirst = $false; for ($n = 0; $n -lt $w.Count -and ($firstAnch -lt 0 -or $n -lt $firstAnch); $n++) { if ($w[$n] -match "^R:[1-9]\d*:0$") { $plainFirst = $true } }
    Verdict "step 8: 'Close other tabs' closed plain tabs and NO anchored one" $plainFirst
    Verdict "step 9: the multi-selection really closed exactly one anchored tab" ((AnchoredRemoved $w) -eq 1)
}

$e2 = Events $Log2
if ($null -eq $e2) { Write-Host "FAIL: $Log2 missing or EMPTY" -ForegroundColor Red; $script:failed++ } else {
    Write-Host "`n--- run 2 events: $($e2 -join '  ')"
    $doors2 = @($e2 | Where-Object { $_ -like "D:*" })
    Verdict "step 12: X on a NEVER-LOADED anchor was diverted, nothing anchored removed before it" (($doors2.Count -ge 1) -and ($doors2[0] -eq $cb) -and ((AnchoredRemoved (Window $e2 1)) -eq 0))
    Write-Host ("      what the never-loaded anchor did: " + $(if ((Window $e2 1) -contains "K") { "could not be discarded; kept live" } elseif (@(Window $e2 1 | Where-Object { $_ -like "H:*" }).Count) { "discarded and hibernated" } else { "treated as already asleep" }))
    Verdict "step 13: the anchor survived the restart (Ctrl+W hibernated example.org)" (($doors2.Count -ge 2) -and ($doors2[1] -eq "D:Ctrl+W") -and ((Window $e2 2) -contains "H:https://example.org/"))
    $after = @(if ($doors2.Count -ge 2) { Window $e2 3 })
    $u = -1; for ($n = 0; $n -lt $after.Count; $n++) { if ($after[$n] -eq "U") { $u = $n; break } }
    Verdict "step 14: unanchored, then the X closed it for real" (($u -ge 0) -and (@($after[$u..($after.Count - 1)] | Where-Object { $_ -match "^R:1:0$" }).Count -ge 1))
}
$markers = (Get-Content $Log1, $Log2 -EA SilentlyContinue | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in both logs" ($markers -eq 0)
Write-Host "`nOwner-observed, not gradeable from a log: the anchored tabs STAY in the strip and look asleep; step 5 changes nothing on screen."
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
