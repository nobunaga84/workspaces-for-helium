param([switch]$NoLaunch, [switch]$GradeOnly, [string[]]$Steps = @(), [ValidateSet("Default", "Dcheck")][string]$Build = "Default",
      [string]$BinDir = "")
# `pwsh -File ... -Steps 1,4` passes ONE string "1,4" (as [int] it read 14: the comma a thousands separator).
$Steps = @($Steps | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [int]$_ })
# C5 (patch 91 `91-site-rules.patch`, <local-path>\Helium-workspace\c5-progress.md): the owner's own try of "links by rule" --
# what a person sees (check-c5.ps1 passes it hands-free). It opens the built browser (out\Default, or -Build Dcheck /
# -BinDir) on a FRESH copy of the smoke profile (never the daily browser's profile), in Light mode, in Home, with one
# Today tab "C5 links". The pages are served from this PC: "C5 links" and the rule page on 127.0.0.1 / localhost, the
# ruled pages on sub.localhost (a subdomain of localhost, as gist.github.com is of github.com). When a step says so the
# script opens a page (a second chrome.exe with the address: the workspace on screen, as a typed command does) or plays
# Outlook (the same with --single-argument LAST, as Windows hands over a link). Each step is graded only on the log
# lines written after "STEP N: do it now"; after it you answer y/n and the next step starts. Graded from the
# "[workspaces] site ..." / "site rule: ..." / "little window: skipped ..." / "active workspace ->" / "export: wrote"
# lines and the exported file. One browser run, one log.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c5.ps1 [-Build Dcheck] [-Steps 1,4]
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again from
# the last try's log and step marks (the browser closed).
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe   = "$bin\chrome.exe"
$py    = "C:\Python314\python.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$sfx   = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof  = "$ws\testprofile-c5-owner$sfx"
$dflt  = "$prof\Default"
$log   = "$ws\c5-owner$sfx-run.log"
$txt   = "$ws\c5-owner$sfx-try.txt"
$markf = "$ws\c5-owner$sfx-marks.json"
$web   = "$ws\c5-owner-pages"
$work  = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check")
$script:out = [System.Collections.Generic.List[string]]::new()
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Running { [bool](Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) }
function WaitClosed { while (Running) { Start-Sleep 2 } }
# Up to a minute for the started browser to show up, so a slow cold start is not taken for a quit.
function WaitOpen { $t0 = Get-Date; while (-not (Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 } }
# The log's length now, in lines: a step is graded on the lines after its start only.
function LineCount { if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log).Count } else { 0 } }

# ---- the preconditions, each checked before anything is touched ------------------------------------------------
$bad = @()
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { $bad += "a test browser is already open: close it first" }
if (-not (Test-Path -LiteralPath $exe)) { $bad += "no $exe (build first)" }
if (-not (Test-Path -LiteralPath $py)) { $bad += "no $py" }
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { $bad += "no smoke profile at $smoke" }
if (Test-Path -LiteralPath $exe) {
    & $py -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "site rule: to the top of '"
    if ($LASTEXITCODE -ne 0) { $bad += "this build has no patch 91 yet (no 'site rule: to the top of' in $bin\chrome.dll): tell Claude" }
}
if ($GradeOnly -and -not (Test-Path -LiteralPath $markf)) { $bad += "no $markf to grade (no finished try)" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

$names = @("a rule from a tab's menu", "a background link waits in Work", "a foreground link follows", "a click inside a tab stays", "a link from another app", "the rule in an export", "remove the site")
# What the script does at your Enter in each step: open the rule page, send the outside link, or nothing.
$sends = @("open", "", "", "", "send", "", "")
function Ask([int]$i) { $a = "$(Read-Host "    Done with ALL of step $($i + 1)? Did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath "$dflt\Workspace Archive", $markf, $txt, $log -EA SilentlyContinue
    # Light mode; vertical, Workspaces on and the small window ON (the smoke profile's own, written so a stale copy
    # cannot start otherwise); the sidebar wide enough for the chips and the +.
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" "helium.browser.layout=2" "helium.workspaces.enabled=true" "helium.workspaces.little_window=true" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    $null = New-Item -ItemType Directory -Force $web
    # The ruled pages and the rule page: a title and a big heading each.
    foreach ($p in @(@("c5rule", "C5 rule page"), @("c5one", "C5 ruled one"), @("c5two", "C5 ruled two"), @("c5three", "C5 ruled three"), @("c5out", "C5 outside"))) {
        Set-Content -Encoding UTF8 -LiteralPath "$web\$($p[0]).html" -Value "<!doctype html><title>$($p[1])</title><body style=`"margin:24px;font:32px sans-serif`"><h1>$($p[1])</h1></body>"
    }
    # "C5 links": three links to sub.localhost on the server's own port, filled in by the page.
    Set-Content -Encoding UTF8 -LiteralPath "$web\c5links.html" -Value @'
<!doctype html>
<title>C5 links</title>
<body style="margin:24px;font:32px sans-serif">
<h1>C5 links</h1>
<p><a id="one" href="#">Ruled link one</a></p>
<p><a id="two" href="#">Ruled link two</a></p>
<p><a id="three" href="#">Ruled link three</a></p>
<script>
  for (const id of ["one", "two", "three"])
    document.getElementById(id).href = "http://sub.localhost:" + location.port + "/c5" + id + ".html";
</script>
</body>
'@
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    @"

The test browser opens on a fresh COPY of the smoke profile (your daily browser is not touched), in Light mode, in its
workspace Home, with one Today tab "C5 links". Words used below:
  - a TODAY TAB: an ordinary tab in the sidebar's list, under the pinned pages.
  - the BAR: the row at the bottom of the sidebar: the Archive button, one round WORKSPACE CHIP per workspace, "+".
  - the + MENU: what the "+" at the right end of the bar opens.
  - OPEN THE PAGE: press Enter in THIS window: the page "C5 rule page" (its address starts with localhost) opens as a
    Today tab in the workspace on screen.
  - SEND THE LINK: press Enter in THIS window: the script hands the browser a link exactly as Windows does for a link
    clicked in Outlook or Teams.
  - localhost and sub.localhost: two names of this PC. A rule for localhost covers sub.localhost too (a subdomain),
    as a rule for github.com covers gist.github.com. The "Ruled link" pages are all on sub.localhost.
THIS window says "STEP N: do it now" -- do ALL of step N (pressing Enter here only where it says OPEN THE PAGE or SEND
THE LINK), come back here, answer y or n; the next step starts at once.

 1. A rule from a tab's menu. Click the workspace chip "Work" on the bar (the second chip, a face blowing a kiss;
    hovering it shows "Work"). Then OPEN THE PAGE (Enter here): "C5 rule page" opens as a Today tab in Work.
    Right-click that Today tab and click "Always open localhost in the Work workspace". Then right-click it again.
    PASS: the same item now reads "Stop always opening localhost in the Work workspace". Do NOT click it: press Esc.
 2. A background link waits in Work. Click the workspace chip "Home" (the first chip). In the Today tab "C5 links",
    hold Ctrl and click "Ruled link one".
    PASS: NO new Today tab appears in Home and the window stays in Home. Then click the chip "Work": "C5 ruled one" is
    the FIRST Today tab there.
 3. A foreground link follows. Click the chip "Home". In "C5 links", hold Ctrl AND Shift and click "Ruled link two".
    PASS: the window goes to Work by itself, "C5 ruled two" in front and the FIRST Today tab (above "C5 ruled one").
 4. A click inside a tab stays. Click the chip "Home". In "C5 links", click "Ruled link three" plainly (no key held).
    PASS: "C5 ruled three" opens IN THE SAME Today tab, in Home; the window stays in Home. Then press Alt+Left to go
    back to "C5 links".
 5. A link from another app. Stay in Home. SEND THE LINK (Enter here).
    PASS: NO small window opens; the window goes to Work with "C5 outside" in front, the FIRST Today tab.
 6. (optional: answer with Enter alone to skip) The rule in an export. Click the + MENU > "Export workspaces$([char]0x2026)" and
    save the file anywhere (the Desktop is fine), keeping the .json type.
    PASS: no error message. The script opens the file afterwards and looks for the rule in it.
 7. Remove the site. Right-click the workspace chip "Work" > "Edit workspace...". At the bottom, under "Sites", is
    "localhost" with a small x. Click the x.
    PASS: the "localhost" row goes, and "None yet. Right-click a tab to always open its site here." shows in its place.
    Press Esc to close the bubble.
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof, the pages $web, port $port, the log would be $log)"; exit 0 }
    $srv = Start-Process $py -ArgumentList "-I", "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $web -WindowStyle Hidden -PassThru
    $up = $false
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://localhost:$port/c5rule.html").Content -match "C5 rule page") { $up = $true; break } } catch {} }
    if (-not $up) { Stop-Process -Id $srv.Id -EA SilentlyContinue; Write-Host "NOT READY: the pages were not served on localhost:$port"; exit 1 }
    $marks = @(); $said = @()
    try {
        Start-Process $exe -ArgumentList (@("--log-file=`"$log`"") + $flags + @("http://127.0.0.1:$port/c5links.html"))
        WaitOpen
        for ($i = 0; $i -lt $names.Count; $i++) {
            if ($Steps.Count -and $Steps -notcontains ($i + 1)) { $said += "-"; $n = LineCount; $marks += [pscustomobject]@{ start = $n; send = $n; end = $n }; continue }
            Write-Host "`n==> STEP $($i + 1) ($($names[$i])): do it NOW in the browser (its words are above, under '$($i + 1).')."
            $m = [pscustomobject]@{ start = (LineCount); send = 0; end = 0 }
            $m.send = $m.start
            if ($sends[$i]) {
                $what = if ($sends[$i] -eq "open") { "OPEN THE PAGE 'C5 rule page'" } else { "SEND THE LINK 'C5 outside'" }
                $null = Read-Host "   Step $($i + 1): when the step says so, press Enter here to $what"
                $m.send = LineCount
                # A second chrome.exe hands its line to the running browser and exits. Without --single-argument: the
                # main window, the workspace on screen; with it LAST: as Windows hands over a link from another app.
                $a = if ($sends[$i] -eq "open") { @("--user-data-dir=$prof", "http://localhost:$port/c5rule.html") } else { @("--user-data-dir=$prof", "--single-argument", "http://sub.localhost:$port/c5out.html") }
                $p = Start-Process $exe -PassThru -ArgumentList $a
                Write-Host "   (done; the hand-over $(if ($p.WaitForExit(15000)) { 'finished' } else { 'is STILL RUNNING: tell Claude' }))"
            }
            $said += Ask $i
            $m.end = LineCount
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

# ---- the grades: patch 91's lines (workspace_service.cc, workspace_little_window.cc), case-sensitive ----------------
function Lines([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern $re) } else { @() } }
# Step i's lines matching re, written after its mark `from` ("start", or "send": the Enter) and before `to`.
function In([int]$i, [string]$re, [string]$from = "start", [string]$to = "end") { $m = $marks[$i]; if (-not $m) { return @() }; @(Lines $re | Where-Object { $_.LineNumber -gt $m.$from -and $_.LineNumber -le $m.$to }) }
function G($line) { if ($line) { @($line.Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Ws([string]$g) { if ($g -eq $work) { "Work" } elseif ($g -eq "default") { "Home" } else { "'$g'" } }
$siteSet = "\[workspaces\] site '([^']*)' -> workspace '([^']*)'"
$removed = "\[workspaces\] site '([^']*)' removed"
$stamp   = "\[workspaces\] site rule: '([^']*)' -> workspace '([^']*)' \(active '([^']*)'\)"
$top     = "\[workspaces\] site rule: to the top of '([^']*)'(.*)"
$anyRule = "\[workspaces\] site rule: "
$skipped = "\[workspaces\] little window: skipped, site rule for '([^']*)'"
$opened  = "\[workspaces\] little window: opened window "
$ins     = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"
$active  = "\[workspaces\] active workspace -> '([^']*)'"
$wrote   = "\[workspaces\] export: wrote (.+)"
# A routed open in step i (from its mark `from`): its first stamp for sub.localhost, the to-the-top line after it, and
# the switches to Work after the stamp -- all of them, and those before the to-the-top line (the auto-switch's place).
function Routed([int]$i, [string]$from = "start") {
    $s = @(In $i $stamp $from | Where-Object { $_.Matches[0].Groups[1].Value -eq "sub.localhost" }) | Select-Object -First 1
    $t = if ($s) { @(In $i $top $from | Where-Object { $_.LineNumber -gt $s.LineNumber }) | Select-Object -First 1 }
    $after = if ($s) { @(In $i $active $from | Where-Object { $_.LineNumber -gt $s.LineNumber -and $_.Matches[0].Groups[1].Value -eq $work }) } else { @() }
    $before = @($after | Where-Object { $t -and $_.LineNumber -lt $t.LineNumber })
    $sg = G $s; $tg = G $t
    [pscustomobject]@{
        ok = [bool]($sg.Count -and $sg[2] -eq $work -and $sg[3] -eq "default" -and $tg.Count -and $tg[1] -eq $work)
        after = $after.Count; before = $before.Count
        why = "$(if ($sg.Count) { "site rule '$($sg[1])' -> $(Ws $sg[2]) (on screen $(Ws $sg[3]))" } else { 'no site rule line for sub.localhost' }) (want -> Work from Home); $(if ($tg.Count) { "to the top of $(Ws $tg[1])$($tg[2])" } else { 'no to-the-top line' })"
    }
}

$grades = @()
$s1 = G (In 0 $siteSet "send" | Select-Object -Last 1)
$i1 = @(In 0 $ins "send" | Where-Object { $_.Matches[0].Groups[2].Value -eq $work }).Count
$grades += [pscustomobject]@{ ok = [bool]($s1.Count -and $s1[1] -eq "localhost" -and $s1[2] -eq $work -and $i1 -ge 1); why = "the rule page opened in Work x$i1 (want 1+); $(if ($s1.Count) { "site '$($s1[1])' -> $(Ws $s1[2])" } else { 'no site line' }) (want localhost -> Work); the menu's new words are your eyes" }
$r = Routed 1
$grades += [pscustomobject]@{ ok = ($r.ok -and $r.before -eq 0); why = "$($r.why); a switch to Work before it x$($r.before) (want 0: it waited); first in Work is your eyes" }
$r = Routed 2
$grades += [pscustomobject]@{ ok = ($r.ok -and $r.after -ge 1); why = "$($r.why); the window followed to Work x$($r.after) (want 1+); first in Work is your eyes" }
$a4 = @(In 3 $anyRule).Count; $w4 = @(In 3 $active | Where-Object { $_.Matches[0].Groups[1].Value -eq $work }).Count
$grades += [pscustomobject]@{ ok = ($a4 -eq 0 -and $w4 -eq 0); why = "site rule lines x$a4, switches to Work x$w4 (want 0, 0); the same tab is your eyes" }
$k5 = G (In 4 $skipped "send" | Select-Object -First 1); $r = Routed 4 "send"; $o5 = @(In 4 $opened "send").Count
$grades += [pscustomobject]@{ ok = ($k5.Count -and $k5[1] -eq "sub.localhost" -and $r.ok -and $o5 -eq 0); why = "after the link: $(if ($k5.Count) { "small window skipped for '$($k5[1])'" } else { 'no skipped line' }) (want sub.localhost); $($r.why); small windows opened x$o5 (want 0)" }
$w6 = G (In 5 $wrote | Select-Object -Last 1)
$f6 = if ($w6.Count) { $w6[1].Trim().Trim('"') } else { "" }
$sites6 = @(); $has6 = $false
if ($f6 -and (Test-Path -LiteralPath $f6)) {
    try {
        $c6 = [string](([IO.File]::ReadAllText($f6) | ConvertFrom-Json).files.'prefs.json'.content)
        $has6 = $c6 -match '"sites"'
        $sites6 = @(@(($c6 | ConvertFrom-Json).helium.workspaces.list.items | Where-Object { $_.guid -eq $work }) | ForEach-Object { $_.sites } | Where-Object { $_ })
    } catch {}
}
$grades += [pscustomobject]@{ ok = [bool]($has6 -and $sites6 -contains "localhost"); why = "$(if ($f6) { "exported to $f6" } else { 'no export: wrote line' }); its prefs.json has `"sites`" $has6, Work's sites [$($sites6 -join ',')] (want localhost)" }
$r7 = G (In 6 $removed | Select-Object -Last 1)
$grades += [pscustomobject]@{ ok = [bool]($r7.Count -and $r7[1] -eq "localhost"); why = "$(if ($r7.Count) { "site '$($r7[1])' removed" } else { 'no removed line' }) (want localhost); the none line is your eyes" }

Say ""
$pass = 0
for ($i = 0; $i -lt $names.Count; $i++) {
    $g = $grades[$i]; $a = $said[$i]
    $v = if ($a -eq "y" -and $g.ok) { "PASS" } elseif ($a -eq "n") { "FAIL" } elseif ($a -eq "-") { "NOT TRIED" } else { "LOOK" }
    if ($v -eq "PASS") { $pass++ }
    Say ("{0,-9} step {1} {2}: you said {3}; the log: {4}" -f $v, ($i + 1), $names[$i], $a, $g.why)
}
$markers = 0
if (Test-Path -LiteralPath $log) { $markers = @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count }
Say "crash markers in the log: $markers (want 0)"
Say "RESULT try-c5$sfx $pass of $($names.Count) PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Log: $log"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
