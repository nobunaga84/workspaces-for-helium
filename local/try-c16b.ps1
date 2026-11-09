param([switch]$NoLaunch, [switch]$GradeOnly)
# C16 batch (patch 87): the owner's short RE-TRY of try-c16's steps 5, 6 and 10 (2026-10-23), with every row named as the
# profile names it, the exact menu item spelled out, and two windows kept for the restart. Same rules as try-c16.ps1: a
# FRESH copy of the smoke profile (never the daily browser's), Light mode, graded from the logs and the files.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c16b.ps1
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again.
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = "$ws\helium-windows\build\src\out\Default"
$exe   = "$bin\chrome.exe"
$py    = "C:\Python314\python.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-c16-retry"
$dflt  = "$prof\Default"
$logs  = @("$ws\c16-owner-retry-run1.log", "$ws\c16-owner-retry-run2.log")
$txt   = "$ws\c16-owner-retry.txt"
# No Wikipedia page among the Today tabs: the pinned page "Wikipedia" is the only one of that name.
$pages = @("https://example.com/", "https://www.iana.org/help/example-domains", "https://httpbin.org/html")
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
$script:out = [System.Collections.Generic.List[string]]::new()
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Running { [bool](Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) }
function WaitClosed { while (Running) { Start-Sleep 2 } }
function WaitOpen { $t0 = Get-Date; while (-not (Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 } }

# ---- the preconditions --------------------------------------------------------------------------------------------
$bad = @()
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { $bad += "a test browser is already open: close it first" }
if (-not (Test-Path -LiteralPath $exe)) { $bad += "no $exe (build first)" }
if (-not (Test-Path -LiteralPath $py)) { $bad += "no $py" }
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { $bad += "no smoke profile at $smoke" }
if ($GradeOnly -and -not (Test-Path -LiteralPath $logs[0])) { $bad += "no $($logs[0]) to grade" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath (@("$dflt\Workspace Archive") + $logs + @($txt)) -EA SilentlyContinue
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    if (-not $NoLaunch) { Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[0])`"") + $flags + $pages) }
    @"

The test browser is opening on a fresh COPY of the smoke profile, in Home. Its pinned rows, top to bottom:
  Example A / Smoke folder (OPEN: its pages "Wikipedia", then "Renamed C") / Closed folder / Example D
and three Today tabs under them: "Example Domain", "Example Domains", "Herman Melville - Moby-Dick".
Do every step from WINDOW 1 (the one opening now), in Home, unless it says otherwise.

 A. The drag to a folder's end (try-c16's step 5).
    Press and hold on the pinned page "Example D" (the last pinned row) and move it up over "Renamed C" -- the
    second page INSIDE Smoke folder, NOT the "Smoke folder" row itself (a drop on the folder row puts a page FIRST in
    it, Arc's rule, kept). Keep the pointer on the LOWER half of "Renamed C" until the drop line under it is
    INDENTED like Renamed C; then let go.
    PASS: Example D is the LAST page inside Smoke folder, under Renamed C.
    Then press and hold on "Example A" (the top row), move it down over the UPPER half of "Closed folder", until a
    line shows just above Closed folder at the folder's own left edge (not indented); let go.
    PASS: Example A now sits between Smoke folder's pages and Closed folder, OUTSIDE Smoke folder.
 B. A favorite in the Archive (try-c16's step 6).
    Right-click the Today tab "Herman Melville - Moby-Dick". In its menu choose "Add to Favorites" -- in the MIDDLE group,
    between "Duplicate" and "Mute site" -- NOT "Pin to this workspace" in the top group.
    PASS: the tab leaves the Today list and shows as a FAVORITE at the very top of the sidebar. If it does not show
    there, take a screenshot of the whole sidebar and answer n.
    Then right-click that favorite > "Close" (if a notice asks you to press again, press Ctrl+W once more).
    Click the Archive button on the bar.
    PASS: a row reading "★ Herman Melville - Moby-Dick"; hovering it, the tooltip begins "Favorite:".
    Click that row. PASS: it comes back as a favorite at the top, and the window stays in Home.
 C. Two windows over a restart (try-c16's step 10, with BOTH windows kept).
    Press Ctrl+N: window 2 opens (click Home on ITS bar if it shows another workspace). In WINDOW 2 click the folder
    "Smoke folder" (it closes there only). In WINDOW 1 click "Closed folder" (it opens there only).
    Keep BOTH windows open, and quit with the app menu of either: Alt+F > More tools > Exit.
    Wait: the script opens the browser again by itself.
    PASS: TWO windows come back. On each window's bar click Home: one window shows Smoke folder AND Closed folder
    open, the other shows both closed. Then close the browser any way you like.
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof)"; exit 0 }
    Write-Host "`nWaiting for you to quit the browser (step C)..."
    WaitOpen
    WaitClosed
    Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[1])`"") + $flags + @("--restore-last-session"))
    Say "`nThe browser is opening again with the last session (step C). Check it, then close it."
    WaitOpen
    WaitClosed
    Start-Sleep 3
}

# ---- the answers, then the grades -----------------------------------------------------------------------------------
$names = @("the drag to a folder's end", "a favorite in the Archive", "two windows over a restart")
$keys  = @("A", "B", "C")
Say ""
$said = @(for ($i = 0; $i -lt 3; $i++) { $a = "$(Read-Host "Step $($keys[$i]) ($($names[$i])): did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } })
function Lines([int]$run, [string]$re) { if (Test-Path -LiteralPath $logs[$run]) { @(Select-String -LiteralPath $logs[$run] -CaseSensitive -Pattern $re) } else { @() } }
function Last([int]$run, [string]$re) { $l = @(Lines $run $re); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Json([string]$path) { try { Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json } catch { $null } }
function FindPin($list, [string]$id) {
    foreach ($n in @($list)) { if (-not $n) { continue }; if ($n.id -eq $id) { return $n }; $f = FindPin $n.children $id; if ($f) { return $f } }
    $null
}
$pins = Json "$dflt\Workspace Pins"
$homeRows = @($pins.workspaces.default | Where-Object { $_ })
$f0 = FindPin $homeRows "f0"

$grades = @()
# Every move the drags made, so a miss shows where the drop went.
$moves = @(Lines 0 "\[workspaces\] pins: moved '[^']*' (before|after|into) '[^']*'" | ForEach-Object { $_.Line -replace '^.*\[workspaces\] pins: ', '' }) -join " | "
$m1 = (Lines 0 "\[workspaces\] pins: moved 'd0' after 'c0'").Count -gt 0
$m2 = (Lines 0 "\[workspaces\] pins: moved 'a0' before 'g0'").Count -gt 0
$kids = @($f0.children | Where-Object { $_ } | ForEach-Object { $_.id }) -join ","
$tops = @($homeRows | ForEach-Object { $_.id }) -join ","
$grades += [pscustomobject]@{ ok = ($m1 -and $m2 -and $kids -like "*,d0" -and $tops -like "*f0,a0,g0*"); why = "moves: [$moves]; the file: Smoke folder holds $kids (want b0,c0,d0), Home's rows $tops (want ...f0,a0,g0)" }
$fp = (Lines 0 "\[workspaces\] tag 'default' -> ''").Count
$fa = @(Last 0 "\[workspaces\] archived a manual close in '([^']*)' \(favorite\)")
$fb = @(Last 0 "\[workspaces\] archive: restored an entry into '([^']*)' a favorite")
$grades += [pscustomobject]@{ ok = ($fa.Count -and $fb.Count); why = "made a favorite (a tag cleared) x$fp; filed $(if ($fa.Count) { "under '$($fa[1])'" } else { 'NOT logged' }) (favorite); restored $(if ($fb.Count) { "into '$($fb[1])' a favorite" } else { 'NOT logged' })" }
$wins = (Lines 1 "\[workspaces\] a window opens on workspace").Count
$wr = @(Lines 1 "\[workspaces\] window folders: restored (\d+)" | ForEach-Object { $_.Matches[0].Groups[1].Value })
# Only the clicks after window 2 opened: step A's drag can spring Closed folder open and shut (C8), which logs too.
$second = @(Lines 0 "\[workspaces\] a window opens on workspace")
$from = if ($second.Count -ge 2) { $second[1].LineNumber } else { [int]::MaxValue }
$c1 = @(Lines 0 "\[workspaces\] folder 'f0' closed in this window" | Where-Object { $_.LineNumber -gt $from }).Count
$c2 = @(Lines 0 "\[workspaces\] folder 'g0' open in this window" | Where-Object { $_.LineNumber -gt $from }).Count
$grades += [pscustomobject]@{ ok = ($wins -ge 2 -and $wr.Count -ge 2 -and $c1 -and $c2); why = "before the quit: Smoke folder closed x$c1, Closed folder opened x$c2; after the restart: $wins window(s) opened, 'window folders: restored N' N = [$($wr -join ', ')] (want 2 windows, 2 lines)" }

Say ""
$pass = 0
for ($i = 0; $i -lt 3; $i++) {
    $g = $grades[$i]; $a = $said[$i]
    $v = if ($a -eq "y" -and $g.ok) { "PASS" } elseif ($a -eq "n") { "FAIL" } elseif ($a -eq "-") { "NOT TRIED" } else { "LOOK" }
    if ($v -eq "PASS") { $pass++ }
    Say ("{0,-9} step {1} {2}: you said {3}; the log: {4}" -f $v, $keys[$i], $names[$i], $a, $g.why)
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Say "crash markers in the two logs: $markers (want 0)"
Say "RESULT try-c16b $pass of 3 PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Logs: $($logs -join ', ')"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
