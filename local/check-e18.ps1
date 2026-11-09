param([switch]$GradeOnly,
      [string]$OutDir = "Default",
      [string]$Tag = "e18-owner",
      [switch]$DevToolsPort)          # the rehearsal driver's only: also opens a DevTools port (it sets Settings through it)
# E18 by hand (design 5, "E18 spec"): the header's counts (54), Tab style (55), Smooth scrolling (56) and the wider
# sidebar (57). Runs on a fresh throwaway copy of testprofile-e15b-smoke (Home holds Example A, Smoke folder (open:
# Wikipedia, Renamed C), Closed folder (Hidden), Example D: 5 pinned pages); testprofile and the daily browser are never
# touched. Before the launch the copy's Sessions folder is emptied (no Recently Closed, no last session) and its
# sidebar width set to 280 (below 240 THE HEADER shows the pinned count only, D6). The browser opens sixty local pages,
# "E18 g01" to "E18 g60", as Today tabs, so the list scrolls. The steps come one at a time, each answered y/n here; the
# log is graded too. What each graded row proves:
#   step 1  the last 'pins: header counts P/T' line by your answer is 5/60 (what THE HEADER showed)
#   step 3  'tab style: row height 30 -> 36|40|42' (a taller height) first and '... -> 30' (Default) last, during step 3
#   step 4  a 'glide: A -> B (N ms)' line that moved the list (A != B) while Smooth scrolling was on
#   step 5  a 'sidebar: width W (max M)' line with W > 400; after the close Preferences holds the last W; the restart
#           (--restore-last-session) brings that width back: your s5r answer (D16; since R6 Helium restores the
#           width itself and the fork's 'sidebar: restored window width' line is gone)
#   both logs: 0 crash markers
# Run it in its own process, one line:
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-e18.ps1
#   (PowerShell 7, the owner's. Add -GradeOnly to grade the saved logs and answers again)
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof    = "$ws\testprofile-$Tag"
$smoke   = "$ws\testprofile-e15b-smoke"
$src     = "$ws\helium-windows\build\src"
$bin     = "$src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$log     = "$ws\$Tag-run.log"
$log2    = "$ws\$Tag-restart.log"
$answers = "$ws\$Tag-answers.json"
$pages   = "$ws\$Tag-pages"
$width0  = 280
# The header's separator, U+00B7, built here so this file stays ASCII.
$dot     = [char]0x00B7
$reCounts = '\[workspaces\] pins: header counts ([\d,]+)/([\d,]+)(?:/([\d,]+))?'
$reStyle  = '\[workspaces\] tab style: row height (\d+) -> (\d+)'
$reGlide  = '\[workspaces\] glide: (-?[\d.]+) -> (-?[\d.]+) \((\d+) ms\)'
$reWidth  = '\[workspaces\] sidebar: width (\d+) \(max (\d+)\)'
$markers  = 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling'
$questions = [ordered]@{
    s1    = "1. THE HEADER showed 5 $dot 60 at its right end; hovering it said 5 pinned pages and 60 Today tabs; Smoke folder showed 2, Closed folder 1 (y/n)"
    s2    = "2. under 'Show vertical tabs on right side': Tab style (Default), Smooth scrolling in the tab list (on), Allow a wider sidebar (on), and only then Workspaces (y/n)"
    s3    = "3. each taller height made the Today tabs, pinned pages, folders and + New Tab taller at once; Default made them small again at once (y/n)"
    s4    = "4. with Smooth scrolling on, the Today tabs GLIDED when you rolled the wheel (y/n)"
    s4off = "4. with it off they JUMPED, with no slide; you switched it back on (y/n)"
    s5    = "5. THE SIDEBAR'S EDGE followed the mouse past 400 px, to the middle of the window (y/n)"
    s5r   = "5. after the restart the sidebar came back as wide as you left it (y/n)"
}
function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function AllPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { $_.ProcessId }) }
function Fail([string]$why) { Write-Host "ABORT: $why" -ForegroundColor Red; exit 1 }
function Quit([string]$why) {
    foreach ($id in BrowserPids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    if ($server) { Stop-Process -Id $server.Id -EA SilentlyContinue }
    Fail "$why -- the browser was closed; run the script again"
}
function WaitLog([string]$re, [int]$s, [string]$file = $log) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $file) -and (Select-String -Path $file -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function LogCount { if (Test-Path $log) { @(Get-Content $log).Count } else { 0 } }
# Reads ("a.b") or writes ("a.b=<json>") dotted prefs of the copy (prefs.py beside this script); write only while it is CLOSED.
function Prefs([string[]]$a) { & python "$here\prefs.py" "$prof\Default\Preferences" @a }
function Save { $F | ConvertTo-Json -Depth 6 | Set-Content $answers -Encoding utf8 }
# The y/n for step `k`, and the log's length at that moment (the grading reads the lines between two answers).
function Ask([string]$k) {
    do { $r = "$(Read-Host $questions[$k])".Trim().ToLower() } while ($r -notin @('y', 'n'))
    $F.answers[$k] = $r
    $F.marks[$k] = LogCount
    Save
}
function Step([string]$text) { Write-Host $text -ForegroundColor Yellow }
# The browser, its stdout and stderr in files of their own (with --enable-logging Chrome prints ERROR lines into the
# console that started it -- check-e14d3.ps1).
function Browser([string[]]$argv, [string]$what) {
    Start-Process -FilePath $exe -ArgumentList $argv -RedirectStandardOutput "$ws\$Tag-chrome-$what-out.txt" -RedirectStandardError "$ws\$Tag-chrome-$what-err.txt" | Out-Null
}
# Until the browser and every process of it are gone (a relaunch before that would only reach the dying one).
function WaitClosed {
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    $t = Get-Date
    while ((AllPids).Count -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }
}

if (-not $GradeOnly) {
    if ($Tag -notmatch '^[\w.-]+$') { Fail "-Tag takes letters, digits, '.', '-' and '_' only (it names a folder that is deleted)" }
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Fail "a fork browser is already running -- close it first (forwarded-launch trap)." }
    if (-not (Test-Path "$bin\chrome.dll")) { Fail "no $bin\chrome.dll" }
    # Stale binary: chrome.dll older than a SOURCE of patches 54-57 (not the patch file: a quilt refresh after the build
    # rewrites it from the same sources, LOCAL.md 52), or without each patch's own log text (check-e18-auto.ps1's guard).
    $sources = @(Get-ChildItem -LiteralPath "$ws\helium-windows\patches\local\workspaces" -Filter "5*.patch" | Where-Object { $_.Name -match '^5[4-7]-' } |
                 ForEach-Object { Select-String -LiteralPath $_.FullName -Pattern '^\+\+\+ b/(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } } | Sort-Object -Unique)
    if (-not $sources.Count) { Fail "no patches 54-57 in $ws\helium-windows\patches\local\workspaces" }
    $missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
    if ($missing.Count) { Fail "missing source(s) of patches 54-57: $($missing -join ', ')" }
    $newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Fail "$OutDir chrome.dll is older than a source of patches 54-57 (stale binary: build first)" }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if all(m.find(n.encode())>=0 for n in sys.argv[2:]) else 1)" "$bin\chrome.dll" "header counts" "tab style:" "glide:" "sidebar: width"
    if ($LASTEXITCODE -ne 0) { Fail "$OutDir\chrome.dll does not contain all of patches 54-57 (not built yet?)" }
    # Windows' "Animation effects" off: nothing glides (D13), and step 4 would fail for that alone.
    E18InputType
    if (-not [E18Input]::Animations()) { Fail "Windows' animation effects are off, so nothing can glide. Turn them on (Settings > Accessibility > Visual effects > Animation effects) and run this again." }

    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if ($LASTEXITCODE -ge 8 -or -not (Test-Path "$prof\Default\Preferences")) { Fail "the copy of $smoke failed (robocopy $LASTEXITCODE)" }
    Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    & python "$here\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Fail "preconditions not met (vertical layout, a non-default workspace, enabled)" }
    foreach ($f in $log, $log2, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    # The three settings at their defaults (step 2 looks at them), and the sidebar wide enough for both numbers.
    $was = @(Prefs @("helium.workspaces.tab_row_height", "helium.workspaces.smooth_scrolling", "helium.workspaces.wide_sidebar"))
    if (($was -join ',') -ne 'null,null,null') { Fail "the copy already sets Tab style / Smooth scrolling / wider sidebar ($($was -join ', ')) -- step 2 checks their defaults" }
    $null = Prefs @("vertical_tabs.uncollapsed_width=$width0")
    if ("$(Prefs @('vertical_tabs.uncollapsed_width'))".Trim() -ne "$width0") { Fail "the copy's sidebar width is not $width0" }
    # The sixty pages, served on a port Windows picks (e18-lib.ps1's ServePages).
    $names = @(1..60 | ForEach-Object { "g{0:D2}" -f $_ })
    $sv = ServePages $pages $names
    $port = $sv.port; $server = $sv.server
    if (-not $sv.ok) { Fail "the test pages are not served on port $port" }

    $flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
    if ($DevToolsPort) { $flags += "--remote-debugging-port=0" }
    $F = [ordered]@{ binary = "$OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime.ToString('o'))$(if ($DevToolsPort) { ', DevTools port (rehearsal)' })"
                     answers = [ordered]@{}; marks = [ordered]@{}; feel = ""; saved = ""; comment = "" }
    Write-Host "Opening the browser with sixty test pages; the steps come in a moment ..." -ForegroundColor Green
    Browser ($flags + @("--log-file=`"$log`"") + @($names | ForEach-Object { "http://127.0.0.1:$port/$_.html" })) "start"
    if (-not (WaitLog "pins: drew \d+ row\(s\) of '" 60)) { Quit "the browser did not draw its sidebar" }
    $null = WaitLog "pins: header counts [\d,]+/60\b" 60

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window, the SIDEBAR:
  THE HEADER          the workspace's name at the TOP of the sidebar ("Home").
  PINNED PAGE         a page in the pinned section, ABOVE the thin line (e.g. "Example A"). It is not a tab.
  FOLDER              an entry above the thin line with a folder icon ("Smoke folder", "Closed folder").
  + NEW TAB           the entry with a "+" and the words "New Tab", right UNDER the thin line.
  TODAY TAB           a tab BELOW the thin line (e.g. "E18 g01").
  THE SIDEBAR'S EDGE  the sidebar's right border, where the web page starts: over it the mouse pointer
                      becomes a <-> arrow, and you can drag it.
Answer each question HERE, in this window: y or n, then Enter.
"@ -ForegroundColor Magenta

    Step @"

 1. LOOK at THE HEADER.            EXPECT: at its right end, two numbers in a lighter grey: 5 $dot 60
                                           (5 pinned pages, 60 Today tabs).
    Rest the mouse on THE HEADER for a second, without clicking.
                                   EXPECT: a small box says "5 pinned pages" and "60 Today tabs".
    LOOK at the FOLDERS.           EXPECT: "Smoke folder" shows 2 at its right end, "Closed folder" shows 1.
"@
    Ask "s1"

    Step @"

 2. Click the "+" at the top of the sidebar, then "Workspace settings$([char]0x2026)" (since patch 93 these
    settings live in this box, not on the Settings page).
                                   EXPECT: a box opens with, in this order:
                                             Archive tabs after
                                             Tab style                         showing "Default"
                                             Smooth scrolling in the tab list  switched ON
                                             Allow a wider sidebar             switched ON
    Leave the box open: step 3 uses it.
"@
    Ask "s2"

    Step @"

 3. In that box: click "Tab style" and choose "Comfortable, 36 px", then "Roomy, 40 px",
    then "Spacious, 42 px" -- look at the sidebar after each.
                                   EXPECT: at once, the TODAY TABS, the PINNED PAGES, the FOLDERS and
                                           "+ NEW TAB" get taller, a little more each time.
    Click "Tab style" again and choose "Default".
                                   EXPECT: they all go back to the smaller size at once.
    Then press Escape to close the box.
"@
    Ask "s3"

    Step @"

 4. Put the mouse over the TODAY TABS in the sidebar and roll the mouse wheel down a few clicks, then up.
                                   EXPECT: the list GLIDES: it slides smoothly to its new place, it does not jump.
"@
    Ask "s4"
    Write-Host "    How did the glide feel? Type  slow,  right  or  fast  (or a few words), then Enter." -ForegroundColor Yellow
    do { $r = "$(Read-Host '    the feel')".Trim() } while (-not $r)
    $F.feel = $r
    Save
    Step @"
    Now open "+" > "Workspace settings$([char]0x2026)" again, switch "Smooth scrolling in the tab list" OFF and press
    Escape. Roll the wheel over the TODAY TABS again.
                                   EXPECT: the list JUMPS straight to its new place, with no slide.
    Then switch "Smooth scrolling in the tab list" back ON the same way.
"@
    Ask "s4off"

    Step @"

 5. If the window does not fill the screen, press the Windows key + Up arrow.
    Put the mouse on THE SIDEBAR'S EDGE, press the LEFT button, drag to the right to about the MIDDLE of the
    window, and let go.
                                   EXPECT: the edge keeps following the mouse all the way to the middle
                                           (before, it stopped at 400 px -- about a fifth of a full screen).
"@
    Ask "s5"
    Step @"
    Look where THE SIDEBAR'S EDGE is now. Then close the browser with its X (top right).
    This window waits, then opens the browser again by itself, with your tabs.
"@
    WaitClosed
    $F.saved = "$(Prefs @('vertical_tabs.uncollapsed_width'))".Trim()
    Save
    Write-Host "Browser closed (sidebar width saved: $($F.saved)). Opening it again ..." -ForegroundColor Green
    Browser ($flags + @("--log-file=`"$log2`"", "--restore-last-session")) "restart"
    if (-not (WaitLog "pins: drew \d+ row\(s\) of '" 60 $log2)) { Quit "the browser did not come back" }
    Start-Sleep 2
    Step @"
    The browser is open again.     EXPECT: THE SIDEBAR'S EDGE is where you left it -- the sidebar is as wide as
                                           when you closed the browser, not narrow again.
"@
    Ask "s5r"

    Step @"

 6. Close the browser with its X (top right).
"@
    Write-Host "Nothing to press here: this window waits for the browser to close." -ForegroundColor Cyan
    WaitClosed
    Stop-Process -Id $server.Id -EA SilentlyContinue
    Write-Host "Browser closed." -ForegroundColor Green
    $F.comment = "$(Read-Host "Anything that looked wrong or odd? (Enter for nothing)")".Trim()
    Save
}

# ---- grading (also -GradeOnly) -----------------------------------------------------------------
if (-not (Test-Path $answers)) { Fail "no $answers -- run without -GradeOnly first" }
$F = [IO.File]::ReadAllText($answers) | ConvertFrom-Json
if (-not (Test-Path $log) -or (Get-Item $log).Length -eq 0) { Fail "$log missing or EMPTY -- nothing to grade" }
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$lines  = @(Get-Content $log)
$lines2 = if (Test-Path $log2) { @(Get-Content $log2) } else { @() }
# The log's length at step `k`'s answer (a missing mark: past the end, so a range from it is empty).
function M([string]$k) { if ($null -ne $F.marks.$k) { [int]$F.marks.$k } else { [int]::MaxValue } }
# The run log's lines matching `re` after line `a`, up to line `b`.
function In([string]$re, [int]$a, [int]$b = [int]::MaxValue) { @($lines | Select-String -Pattern $re | Where-Object { $_.LineNumber -gt $a -and $_.LineNumber -le $b }) }
# The leading comma keeps a one-number list a list: PowerShell hands a function's one-item result back bare, and
# (Nums $x)[0] would then index the string itself ("680"[0] is "6" -- the rehearsal found it).
function Nums($hit) { , @($hit.Matches[0].Groups | Select-Object -Skip 1 | ForEach-Object { $_.Value }) }
function Int([string]$s) { if ($s) { [int]($s -replace ',', '') } else { 0 } }
Write-Host "      binary: $($F.binary)"

$c = @(In $reCounts 0 (M s1))
$cn = if ($c.Count) { Nums $c[-1] } else { @('', '', '') }
Verdict "1: $($c.Count) 'header counts' line(s); the last by your answer: $($cn[0])/$($cn[1])$(if ($cn[2]) { "/$($cn[2])" }) -- 5 pinned pages, 60 Today tabs, no anchored tab" ($c.Count -and (Int $cn[0]) -eq 5 -and (Int $cn[1]) -eq 60 -and (Int $cn[2]) -eq 0)

$st = @(In $reStyle (M s2) (M s3) | ForEach-Object { $n = Nums $_; "$($n[0]) -> $($n[1])" })
Verdict "3: 'tab style: row height 30 -> <a taller height>' first and '<that> -> 30' (Default) last, during step 3 (seen: $(if ($st.Count) { $st -join ', ' } else { 'none' }))" ($st.Count -ge 2 -and $st[0] -match '^30 -> (36|40|42)$' -and $st[-1] -match '^(36|40|42) -> 30$')

$g = @(In $reGlide (M s3) (M s4))
$moved = @($g | Where-Object { $n = Nums $_; [double]$n[0] -ne [double]$n[1] })
Verdict "4: $($g.Count) 'glide:' line(s) while Smooth scrolling was on, $($moved.Count) that moved the list (1 or more)" ($moved.Count -ge 1)

$wl = @(In $reWidth (M s4) | ForEach-Object { [int]((Nums $_)[0]) })
$wMax = if ($wl.Count) { ($wl | Measure-Object -Maximum).Maximum } else { 0 }
$wLast = if ($wl.Count) { $wl[-1] } else { -1 }
Verdict "5: a drag past 400 px: 'sidebar: width W' line(s) $(if ($wl.Count) { $wl -join ', ' } else { 'none' }) -- the widest $wMax, above 400" ($wMax -gt 400)
Verdict "5: after the close Preferences held the sidebar width $($F.saved) -- the last drag's W ($wLast)" ($wl.Count -and "$($F.saved)" -eq "$wLast")

$m1 = @($lines | Select-String -CaseSensitive -Pattern $markers).Count
$m2 = @($lines2 | Select-String -CaseSensitive -Pattern $markers).Count
Verdict "0 crash markers: run log $m1, restart log $m2 ($($lines2.Count) lines)" ($m1 -eq 0 -and $m2 -eq 0 -and $lines2.Count -gt 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($F.answers.$k -eq 'y') }
Write-Host "      the glide's feel: $($F.feel)" -ForegroundColor Cyan
if ($F.comment) { Write-Host "      your comment: $($F.comment)" -ForegroundColor Cyan }
Write-Host "`nLog: $log   Restart log: $log2   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
