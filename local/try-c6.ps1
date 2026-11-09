param([switch]$NoLaunch, [switch]$GradeOnly, [string[]]$Steps = @())
# `pwsh -File ... -Steps 1,4` passes ONE string "1,4" (as [int] it read 14: the comma a thousands separator).
$Steps = @($Steps | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [int]$_ })
# C6 (patch 90 `90-little-window.patch`, <local-path>\Helium-workspace\c21-progress.md): the owner's own try of the small window
# for links from other apps -- what a person sees and feels (check-c6.ps1 already passed it hands-free). Your Outlook
# would open the DAILY browser, so THIS script plays the other app: when a step says so it hands the test browser a
# link exactly as Windows does (a second chrome.exe --user-data-dir=<the try profile> --single-argument <url>, the
# switch LAST, as check-c6's Outside). It opens the built browser (out\Default) on a FRESH copy of the smoke profile
# (never the daily browser's profile), in Light mode, in Home; the steps are done in Work. The links' pages are served
# from this PC (127.0.0.1), each a number counting up, so a page moved without a reload is seen counting on. Before
# each step you press Enter here, so each step is graded only on the log lines written after it began; after it you
# answer y/n. Graded from the "[workspaces] little window: ..." and "tab inserted ..." lines, the Archive file, the
# saved sessions (Recently closed included) and the pref helium.workspaces.little_window; step 6 quits and the script
# opens the browser again by itself (a second log).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c6.ps1
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again from
# the last try's logs, step marks and files (the browser closed).
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = "$ws\helium-windows\build\src\out\Default"
$exe   = "$bin\chrome.exe"
$py    = "C:\Python314\python.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-c6-owner"
$dflt  = "$prof\Default"
$logs  = @("$ws\c6-owner-run1.log", "$ws\c6-owner-run2.log")
$txt   = "$ws\c6-owner-try.txt"
$markf = "$ws\c6-owner-marks.json"
$web   = "$ws\c6-owner-pages"
$work  = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
$script:out = [System.Collections.Generic.List[string]]::new()
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Running { [bool](Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) }
function WaitClosed { while (Running) { Start-Sleep 2 } }
# Up to a minute for the started browser to show up, so a slow cold start is not taken for a quit.
function WaitOpen { $t0 = Get-Date; while (-not (Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 } }
# The log's length now, in lines: a step is graded on the lines after its start only.
function LineCount([int]$run) { if (Test-Path -LiteralPath $logs[$run]) { @(Get-Content -LiteralPath $logs[$run]).Count } else { 0 } }

# ---- the preconditions, each checked before anything is touched ------------------------------------------------
$bad = @()
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { $bad += "a test browser is already open: close it first" }
if (-not (Test-Path -LiteralPath $exe)) { $bad += "no $exe (build first)" }
if (-not (Test-Path -LiteralPath $py)) { $bad += "no $py" }
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { $bad += "no smoke profile at $smoke" }
if (Test-Path -LiteralPath $exe) {
    & $py -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "little window: moved into window "
    if ($LASTEXITCODE -ne 0) { $bad += "this build has no patch 90 yet (no 'little window: moved into window' in out\Default\chrome.dll): tell Claude" }
}
if ($GradeOnly -and -not (Test-Path -LiteralPath $markf)) { $bad += "no $markf to grade (no finished try)" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

$names = @("a link from another app", "Open in main window", "Shift+Alt+O", "closing throws it away", "the setting off", "not back after a restart")
# The link each step sends (a page of $web), none for step 2; its page's title is "Outside link <word>".
$sends = @("one", "", "two", "three", "four", "five")
function Ask([int]$i) { $a = "$(Read-Host "    Done with ALL of step $($i + 1)? Did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath (@("$dflt\Workspace Archive", $markf, $txt) + $logs) -EA SilentlyContinue
    # Light mode; the small window ON (the default, written so a stale copy cannot start it off).
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" "helium.workspaces.little_window=true" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    $null = New-Item -ItemType Directory -Force $web
    foreach ($w in @($sends | Where-Object { $_ })) {
        Set-Content -Encoding UTF8 -LiteralPath "$web\c6$w.html" -Value "<!doctype html><title>Outside link $w</title><body style=`"margin:24px;font:32px sans-serif`"><h1>Outside link $w</h1><p id=`"n`">0</p><script>let n = 0; setInterval(() => { document.getElementById(`"n`").textContent = ++n; }, 100);</script></body>"
    }
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    @"

The test browser opens on a fresh COPY of the smoke profile (your daily browser is not touched), in Light mode, in its
workspace Home. Words used below:
  - the MAIN WINDOW: the browser window that opens now (the sidebar, the workspaces).
  - a SMALL WINDOW: the window a link from another app opens in: an address row at its top, NO sidebar.
  - SEND THE LINK: this script plays Outlook. When a step says so, press Enter in THIS window: the script hands the
    test browser a link exactly as Windows does for a link clicked in Outlook or Teams. Each link's page is titled
    "Outside link one" (two, three, four, five) and shows a number counting up, 10 a second: a page MOVED goes on
    counting; a page RELOADED starts again at 0.
  - a TODAY TAB: an ordinary tab in the sidebar's list, under the pinned pages.
  - the BAR: the row at the bottom of the sidebar: the Archive button, one round WORKSPACE CHIP per workspace, "+".
Do every step in WORK: in step 1 you switch the main window to it. THIS window says "STEP N: do it now" -- do ALL of
step N (pressing Enter here only where it says SEND THE LINK), come back here, answer y or n; the next step starts at once.

 1. A link from another app. In the main window click the workspace chip "Work" on the bar (the second chip, a face
    blowing a kiss; hovering it shows "Work"). Then SEND THE LINK (Enter here).
    PASS: a SMALL WINDOW opens in the middle of the screen, about half the screen wide and two-thirds of it high (at
    most 1100 x 900), showing "Outside link one" counting up; the main window gets no new tab. Leave it open.
 2. Open in main window. In the small window of step 1, wait until its number is past 100, then click the button at
    the RIGHT end of its address row (hovering it shows "Open in main window").
    PASS: the small window closes; in the main window, in Work, "Outside link one" is the FIRST Today tab and in front,
    its number counting on from where it was (NOT back at 0).
 3. Shift+Alt+O. SEND THE LINK. Click once on the small window's page, wait until its number is past 100, then press
    Shift+Alt+O.
    PASS: as in step 2: the small window closes; "Outside link two" is now the FIRST Today tab in Work, above
    "Outside link one", counting on.
 4. Closing throws it away. FIRST, in the main window, click the Today tab "Outside link one" and close it with Ctrl+W
    (a closed tab goes to the Archive and to Recently closed). THEN SEND THE LINK. Close the SMALL window with ITS
    x (its top right corner).
    PASS: the small window goes and nothing new appears in the main window.
    Click the main window's page once and press Ctrl+Shift+T (reopen the last closed tab).
    PASS: "Outside link one" comes back -- NOT "Outside link three".
    Click the Archive button on the bar. PASS: no "Outside link three" in the list. Close the Archive (Esc).
 5. The setting off. In the main window: Alt+F > Settings > Appearance > turn OFF "Open links from other apps in a
    small window" (just above the "Workspaces" switch). Leave Settings open. Then SEND THE LINK.
    PASS: NO small window; "Outside link four" opens as a Today tab of the MAIN window, the first one in Work.
    Then go back to the Settings tab, turn the switch back ON, and close the Settings tab with Ctrl+W.
 6. Not back after a restart. SEND THE LINK and leave its small window OPEN. Click the MAIN window, then quit with its
    app menu: Alt+F > More tools > Exit. Wait: the script opens the browser again by itself.
    PASS: only the main window comes back, with Work's Today tabs ("Outside link four", "Outside link two", "Outside
    link one"); NO small window, and "Outside link five" nowhere. Then close the browser any way you like.
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof, the pages $web, port $port)"; exit 0 }
    $srv = Start-Process $py -ArgumentList "-I", "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $web -WindowStyle Hidden -PassThru
    $up = $false
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$port/c6one.html").Content -match "Outside link one") { $up = $true; break } } catch {} }
    if (-not $up) { Stop-Process -Id $srv.Id -EA SilentlyContinue; Write-Host "NOT READY: the pages were not served on 127.0.0.1:$port"; exit 1 }
    $marks = @(); $said = @()
    try {
        Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[0])`"") + $flags)
        WaitOpen
        for ($i = 0; $i -lt $names.Count; $i++) {
            if ($Steps.Count -and $Steps -notcontains ($i + 1)) { $said += "-"; $marks += [pscustomobject]@{ run = 0; start = (LineCount 0); send = 0; end = (LineCount 0) }; continue }
            Write-Host "`n==> STEP $($i + 1) ($($names[$i])): do it NOW in the browser (its words are above, under '$($i + 1).')."
            $m = [pscustomobject]@{ run = 0; start = (LineCount 0); send = 0; end = 0 }
            $m.send = $m.start
            if ($sends[$i]) {
                $null = Read-Host "   Step $($i + 1): when the step says so, press Enter here to SEND THE LINK 'Outside link $($sends[$i])'"
                $m.send = LineCount 0
                # As Windows hands a link over: --single-argument LAST. It passes the line to the running browser and exits.
                $p = Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--single-argument", "http://127.0.0.1:$port/c6$($sends[$i]).html")
                Write-Host "   (link sent; the hand-over $(if ($p.WaitForExit(15000)) { 'finished' } else { 'is STILL RUNNING: tell Claude' }))"
            }
            if ($i -eq 5) {
                Write-Host "   Waiting for you to quit with Alt+F > More tools > Exit..."
                WaitClosed
                $m.end = LineCount 0
                Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[1])`"") + $flags + @("--restore-last-session"))
                Say "`nThe browser is opening again with the last session (step 6). Check it, then close it."
                WaitOpen
                WaitClosed
                Start-Sleep 3
            }
            $said += Ask $i
            if ($i -ne 5) { $m.end = LineCount 0 }
            $marks += $m
        }
        if (Running) { Write-Host "`nNow close the test browser (any way). Waiting for it..."; WaitClosed; Start-Sleep 3 }
    } finally { Stop-Process -Id $srv.Id -EA SilentlyContinue }
    ConvertTo-Json -InputObject @($marks) | Set-Content -Encoding UTF8 -LiteralPath $markf
} else {
    $marks = @(Get-Content -Raw -LiteralPath $markf | ConvertFrom-Json)
    Say ""
    $said = @(for ($i = 0; $i -lt $names.Count; $i++) { Ask $i })
}

# ---- the grades: workspace_little_window.cc's lines (patch 90) and StampInsertedTab's, case-sensitive ---------------
function Lines([int]$run, [string]$re) { if (Test-Path -LiteralPath $logs[$run]) { @(Select-String -LiteralPath $logs[$run] -CaseSensitive -Pattern $re) } else { @() } }
# Step i's lines matching re, written after its mark `from` ("start", or "send": the link sent) and before `to`.
function In([int]$i, [string]$re, [string]$from = "start", [string]$to = "end") { $m = $marks[$i]; if (-not $m) { return @() }; @(Lines $m.run $re | Where-Object { $_.LineNumber -gt $m.$from -and $_.LineNumber -le $m.$to }) }
function Last($l) { $l = @($l | Where-Object { $_ }); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Ws([string]$g) { if ($g -eq $work) { "Work" } elseif ($g -eq "default") { "Home" } else { "'$g'" } }
# The files a page `w` ("Outside link <w>") is written in: the Archive file, the saved sessions, Recently closed (Tabs_*).
function Saved([string]$w) {
    @(@(Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue) + @(Get-Item -LiteralPath "$dflt\Workspace Archive" -EA SilentlyContinue) |
      Where-Object { Select-String -LiteralPath $_.FullName -SimpleMatch -Quiet -Pattern "/c6$w.html" } | ForEach-Object { $_.Name })
}
$opened = "\[workspaces\] little window: opened window (\d+) at (-?\d+),(-?\d+) (\d+)x(\d+)"
$moved  = "\[workspaces\] little window: moved into window (\d+) at index (\d+)"
$ins    = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"
# A move in step i: its line (into a window that is not the small one `small`) and the insert it made, in Work.
function MoveGrade([int]$i, [string]$small) {
    $mv = Last (In $i $moved)
    $it = if ($mv.Count) { Last @(In $i $ins | Where-Object { $_.Matches[0].Groups[1].Value -eq $mv[2] }) } else { @() }
    [pscustomobject]@{
        ok  = [bool]($mv.Count -and $mv[1] -ne $small -and $it.Count -and $it[2] -eq $it[3])
        why = "$(if ($mv.Count) { "moved into window $($mv[1]) (the small one: $small) at index $($mv[2])" } else { 'no moved line' }); $(if ($it.Count) { "inserted -> $(Ws $it[2]) (on screen $(Ws $it[3]))" } else { 'no insert at that index' }) (want the same twice: the workspace on screen); first in Today and counting on: your eyes"
    }
}

$grades = @()
$o1 = Last (In 0 $opened "send")
$grades += [pscustomobject]@{ ok = [bool]$o1.Count; why = "$(if ($o1.Count) { "'opened window $($o1[1]) at $($o1[2]),$($o1[3]) $($o1[4])x$($o1[5])' (DIP)" } else { 'no opened line after the link was sent' }); its size and place are your eyes (check-c6's S1 measured them)" }
$g = MoveGrade 1 $(if ($o1.Count) { $o1[1] } else { "-" })
$grades += $g
$o3 = Last (In 2 $opened "send"); $g = MoveGrade 2 $(if ($o3.Count) { $o3[1] } else { "-" })
$grades += [pscustomobject]@{ ok = ($o3.Count -and $g.ok); why = "small window opened $([bool]$o3.Count); $($g.why)" }
$dec = @(In 3 "\[workspaces\] archived a manual close in '" "start" "send").Count
$o4 = @(In 3 $opened "send").Count; $m4 = @(In 3 $moved "send").Count; $s4 = @(Saved "three")
$grades += [pscustomobject]@{ ok = ($dec -ge 1 -and $o4 -ge 1 -and $m4 -eq 0 -and -not $s4.Count); why = "'Outside link one' closed first (archived) x$dec (want 1+); small window opened x$o4, moved x$m4 (want 1, 0); 'Outside link three' written in [$($s4 -join ', ')] (want nowhere: not the Archive, not a session, not Recently closed)" }
$o5 = @(In 4 $opened "send").Count; $i5 = @(In 4 $ins "send" | Where-Object { $_.Matches[0].Groups[2].Value -eq $_.Matches[0].Groups[3].Value }).Count
$pref = "$(& $py -I "$here\prefs.py" "$dflt\Preferences" "helium.workspaces.little_window")".Trim()
$grades += [pscustomobject]@{ ok = ($o5 -eq 0 -and $i5 -ge 1 -and $pref -ne "false"); why = "after the link: small windows opened x$o5 (want 0), tabs inserted in the workspace on screen x$i5 (want 1+); the setting at the end $pref (want true or null = on again)" }
$o6 = @(In 5 $opened "send").Count; $o6b = @(Lines 1 $opened).Count; $w6 = @(Lines 1 "\[workspaces\] a window opens on workspace").Count
$s6 = @(Saved "five"); $k6 = @(Saved "two")
$grades += [pscustomobject]@{ ok = ($o6 -ge 1 -and $o6b -eq 0 -and $w6 -eq 1 -and -not $s6.Count -and $k6.Count); why = "before the quit: small window opened x$o6 (want 1); after the restart: small windows x$o6b (want 0), windows opened x$w6 (want 1); 'Outside link five' written in [$($s6 -join ', ')] (want nowhere); 'Outside link two' kept in [$($k6 -join ', ')] (want a session)" }

Say ""
$pass = 0
for ($i = 0; $i -lt $names.Count; $i++) {
    $g = $grades[$i]; $a = $said[$i]
    $v = if ($a -eq "y" -and $g.ok) { "PASS" } elseif ($a -eq "n") { "FAIL" } elseif ($a -eq "-") { "NOT TRIED" } else { "LOOK" }
    if ($v -eq "PASS") { $pass++ }
    Say ("{0,-9} step {1} {2}: you said {3}; the log: {4}" -f $v, ($i + 1), $names[$i], $a, $g.why)
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Say "crash markers in the two logs: $markers (want 0)"
Say "RESULT try-c6 $pass of $($names.Count) PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Logs: $($logs -join ', ')"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
