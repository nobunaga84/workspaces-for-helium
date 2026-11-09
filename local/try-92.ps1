param([switch]$NoLaunch, [switch]$GradeOnly, [string[]]$Steps = @(), [ValidateSet("Default", "Dcheck")][string]$Build = "Default",
      [string]$BinDir = "")
# `pwsh -File ... -Steps 1,4` passes ONE string "1,4" (as [int] it read 14: the comma a thousands separator).
$Steps = @($Steps | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [int]$_ })
# Patch 92 (92-review-fixes.patch, <local-path>\Helium-workspace\patch92-progress.md): the owner's own try of the review's fixes
# -- what a person sees (check-92.ps1 passes it hands-free). It opens the built browser (out\Default, or -Build Dcheck /
# -BinDir) on a FRESH copy of the smoke profile (never the daily browser's profile), in Light mode, in Home, with one
# pinned split row "P92 left | P92 right" added at the end of Work. The pages are served from this PC. When a step
# says so, the script opens its pages (a second chrome.exe with the addresses: the workspace on screen, as a typed
# command does) or closes one (through DevTools, as the auto-archive closes a due tab -- while a menu is open). Each
# step is graded only on the log lines written after "STEP N: do it now"; after it you answer y/n and the next step
# starts. One browser run, one log.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-92.ps1 [-Build Dcheck] [-Steps 1,4]
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again from
# the last try's log and step marks (the browser closed).
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$py      = "C:\Python314\python.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$sfx     = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof    = "$ws\testprofile-92-owner$sfx"
$dflt    = "$prof\Default"
$log     = "$ws\92-owner$sfx-run.log"
$txt     = "$ws\92-owner$sfx-try.txt"
$markf   = "$ws\92-owner$sfx-marks.json"
$web     = "$ws\92-owner-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$private = "c9990cf0-c141-42fd-bb39-de33171ad078"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0")
$script:out = [System.Collections.Generic.List[string]]::new()
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Running { [bool](Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) }
function WaitClosed { while (Running) { Start-Sleep 2 } }
# Up to a minute for the started browser to show up, so a slow cold start is not taken for a quit.
function WaitOpen { $t0 = Get-Date; while (-not (Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 } }
# The log's length now, in lines: a step is graded on the lines after its start only.
function LineCount { if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log).Count } else { 0 } }
# Page `name` closed through the browser's DevTools port (the profile's DevToolsActivePort): what happened.
function ClosePage([string]$name) {
    try {
        $port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
        $t = @((Invoke-RestMethod -TimeoutSec 10 "http://127.0.0.1:$port/json/list") | Where-Object { $_ -and $_.type -eq "page" -and $_.url -like "*/p92-$name.html*" }) | Select-Object -First 1
        if (-not $t) { return "no open page '$name'" }
        $null = Invoke-RestMethod -TimeoutSec 10 "http://127.0.0.1:$port/json/close/$($t.id)"
        "closed '$name'"
    } catch { "could not close '$name': $_" }
}
# Whether page `name` is open now (DevTools).
function IsOpen([string]$name) {
    try {
        $port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
        [bool](@((Invoke-RestMethod -TimeoutSec 10 "http://127.0.0.1:$port/json/list") | Where-Object { $_ -and $_.type -eq "page" -and $_.url -like "*/p92-$name.html*" }).Count)
    } catch { $false }
}

# ---- the preconditions, each checked before anything is touched ------------------------------------------------
$bad = @()
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { $bad += "a test browser is already open: close it first" }
if (-not (Test-Path -LiteralPath $exe)) { $bad += "no $exe (build first)" }
if (-not (Test-Path -LiteralPath $py)) { $bad += "no $py" }
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { $bad += "no smoke profile at $smoke" }
if (Test-Path -LiteralPath $exe) {
    & $py -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" " anchored kept"
    if ($LASTEXITCODE -ne 0) { $bad += "this build has no patch 92 yet (no ' anchored kept' in $bin\chrome.dll): tell Claude" }
}
if ($GradeOnly -and -not (Test-Path -LiteralPath $markf)) { $bad += "no $markf to grade (no finished try)" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

$names = @("a lone anchored tab and Ctrl+W", "Clear Today keeps an anchored tab", "move a tab while the list changes", "snooze a tab while the list changes", "unload the other workspaces", "unpin a split from a second window")
# At your first Enter in each step: the pages opened (bottom first, so the LAST one is drawn at the top of Today).
$opens  = @(@("anchor"), @("one", "two", "three"), @("bottom", "middle", "top"), @("s-bottom", "s-middle", "s-top"), @("u-bottom", "u-middle", "u-top"), @())
# At your second Enter: a page closed -- after 10 seconds (time to open the menu), or at once.
$closes = @("", "", "top", "s-top", "", "right")
$waits  = @(0, 0, 10, 10, 0, 0)
function Ask([int]$i) { $a = "$(Read-Host "    Done with ALL of step $($i + 1)? Did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath "$dflt\Workspace Archive", "$prof\DevToolsActivePort", $markf, $txt, $log -EA SilentlyContinue
    # Light mode; vertical with Workspaces on (the smoke profile's own, written so a stale copy cannot start
    # otherwise); the sidebar wide enough for the chips and the +.
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" "helium.browser.layout=2" "helium.workspaces.enabled=true" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    $null = New-Item -ItemType Directory -Force $web
    foreach ($p in @("anchor", "one", "two", "three", "bottom", "middle", "top", "s-bottom", "s-middle", "s-top", "u-bottom", "u-middle", "u-top", "left", "right")) {
        Set-Content -Encoding UTF8 -LiteralPath "$web\p92-$p.html" -Value "<!doctype html><title>P92 $p</title><body style=`"margin:24px;font:32px sans-serif`"><h1>P92 $p</h1></body>"
    }
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    function Url([string]$p) { "http://127.0.0.1:$port/p92-$p.html" }
    # Step 6's pinned split row, last in Work, in a version-2 pins file (E19's shape).
    $seed = @'
import json, sys
p, left, right, work = sys.argv[1:5]
d = json.load(open(p, encoding='utf-8'))
d['version'] = 2
d['workspaces'][work].append({'type': 'split', 'id': 'p92s', 'children': [
    {'type': 'item', 'id': 'p92l', 'title': 'P92 left', 'url': left},
    {'type': 'item', 'id': 'p92r', 'title': 'P92 right', 'url': right}]})
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
'@
    & $py -I -c $seed "$dflt\Workspace Pins" (Url "left") (Url "right") $work
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the split row was not written into the copy"; exit 1 }
    @"

The test browser opens on a fresh COPY of the smoke profile (your daily browser is not touched), in Light mode, in its
workspace Home. Words used below:
  - a TODAY TAB: an ordinary tab in the sidebar's list, under the pinned pages.
  - the BAR: the row at the bottom of the sidebar: the Archive button, one round WORKSPACE CHIP per workspace, "+".
    The chips, left to right: Home, Work, Canary, Private, Unpin (hovering one shows its name).
  - a tab's MENU: what a right-click on a Today tab opens.
  - OPEN THE PAGES: press Enter in THIS window: the step's pages open as Today tabs in the workspace on screen, the
    last one at the top.
THIS window says "STEP N: do it now" -- do ALL of step N (pressing Enter here only where it says so), come back here,
answer y or n; the next step starts at once.

 1. A lone anchored tab and Ctrl+W. Click the chip "Private". OPEN THE PAGES (Enter here): "P92 anchor" is the ONLY
    Today tab in Private. Right-click it > "Anchor" > "Anchor to this page". Then click on the page and press Ctrl+W.
    PASS: a New Tab appears AND "P92 anchor" stays in the list (it is asleep now, not closed).
 2. Clear Today keeps an anchored tab. Click the chip "Canary". OPEN THE PAGES (Enter here): "P92 three",
    "P92 two", "P92 one". Right-click "P92 two" > "Anchor" > "Anchor to this page". Click on the page, press Shift+Alt+K.
    PASS: "P92 one" and "P92 three" close; "P92 two" STAYS.
 3. Move a tab while the list changes. Click the chip "Work". OPEN THE PAGES (Enter here): "P92 top", "P92 middle",
    "P92 bottom". Then press Enter here ONCE MORE: you have 10 seconds. Right-click "P92 middle" and point at "Move tab
    to workspace" so its list of workspaces shows -- do NOT click one yet. After the 10 seconds the script closes
    "P92 top" (it disappears). THEN click "Private" in the list.
    PASS: "P92 middle" left Work and "P92 bottom" is still there; click the chip "Private": "P92 middle" is there.
 4. Snooze a tab while the list changes. Click the chip "Work". OPEN THE PAGES (Enter here): "P92 s-top", "P92
    s-middle", "P92 s-bottom". Press Enter here ONCE MORE: 10 seconds. Right-click "P92 s-middle" and point at "Snooze
    tab" so its list shows. When "P92 s-top" disappears, click "In 2 hours (...)".
    PASS: "P92 s-middle" is gone; "P92 s-bottom" is still there.
 5. Unload the other workspaces. Click the chip "Home". OPEN THE PAGES (Enter here): "P92 u-top", "P92 u-middle",
    "P92 u-bottom". Right-click "P92 u-middle" > "Move tab to workspace" > "Work". Click "P92 u-top", then hold Shift
    and click "P92 u-bottom" (both look selected). Right-click the chip "Home" > "Hibernate other workspaces". Then click
    "P92 u-top".
    PASS: "P92 u-top" shows its page at once, with no reload (no spinner on its tab).
 6. Unpin a split from a second window. Click the chip "Work". Click its pinned row "P92 left | P92 right" (the last
    pinned row): both pages open side by side. Press Enter here: the script closes "P92 right" ("P92 left" stays).
    Click the chip "Home". Press Ctrl+N: a SECOND window opens. In it, click the chip "Work", right-click the row "P92
    left | P92 right" > "Unpin".
    PASS: right there, in the SECOND window, "P92 left" and "P92 right" are BOTH in Work's Today, as one split view;
    the pinned row is gone. The first window does not change (it stays on Home, behind).
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof, the pages $web, port $port, the log would be $log)"; exit 0 }
    $srv = Start-Process $py -ArgumentList "-I", "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $web -WindowStyle Hidden -PassThru
    $up = $false
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 (Url "anchor")).Content -match "P92 anchor") { $up = $true; break } } catch {} }
    if (-not $up) { Stop-Process -Id $srv.Id -EA SilentlyContinue; Write-Host "NOT READY: the pages were not served on 127.0.0.1:$port"; exit 1 }
    $marks = @(); $said = @()
    try {
        Start-Process $exe -ArgumentList (@("--log-file=`"$log`"") + $flags)
        WaitOpen
        for ($i = 0; $i -lt $names.Count; $i++) {
            if ($Steps.Count -and $Steps -notcontains ($i + 1)) { $said += "-"; $n = LineCount; $marks += [pscustomobject]@{ start = $n; send = $n; end = $n; open = @(); kept = @() }; continue }
            Write-Host "`n==> STEP $($i + 1) ($($names[$i])): do it NOW in the browser (its words are above, under '$($i + 1).')."
            $m = [pscustomobject]@{ start = (LineCount); send = 0; end = 0; open = @(); kept = @() }
            $m.send = $m.start
            if ($opens[$i].Count) {
                $null = Read-Host "   Step $($i + 1): in the workspace the step names, press Enter here to OPEN THE PAGES"
                # A second chrome.exe hands its addresses to the running browser and exits: the workspace on screen.
                $p = Start-Process $exe -PassThru -ArgumentList (@("--user-data-dir=$prof") + @($opens[$i] | ForEach-Object { Url $_ }))
                Write-Host "   (done; the hand-over $(if ($p.WaitForExit(15000)) { 'finished' } else { 'is STILL RUNNING: tell Claude' }))"
            }
            if ($closes[$i]) {
                $null = Read-Host "   Step $($i + 1): when the step says so, press Enter here$(if ($waits[$i]) { " -- then $($waits[$i]) seconds to open the menu" })"
                $m.send = LineCount
                if ($waits[$i]) { foreach ($s in $waits[$i]..1) { Write-Host -NoNewline "$s "; Start-Sleep 1 }; Write-Host "" }
                Write-Host "   ($(ClosePage $closes[$i]))"
            }
            $said += Ask $i
            $m.end = LineCount
            # Which of the step's pages are still open, for the grade (the browser is still running here).
            $m.open = @($opens[$i] | Where-Object { IsOpen $_ })
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

# ---- the grades: patch 92's lines and the older ones it relies on, case-sensitive -------------------------------
function Lines([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern $re) } else { @() } }
# Step i's lines matching re, written after its mark `from` ("start", or "send": the Enter) and before `to`.
function In([int]$i, [string]$re, [string]$from = "start", [string]$to = "end") { $m = $marks[$i]; if (-not $m) { return @() }; @(Lines $re | Where-Object { $_.LineNumber -gt $m.$from -and $_.LineNumber -le $m.$to }) }
function G($line) { if ($line) { @($line.Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Open([int]$i) { @($marks[$i].open) }
$closing  = "\[workspaces\] closing (\d+) tab\(s\) of workspace '([^']*)' in this window, \d+ pinned kept(, pinned pages kept \(Clear Today\))?, (\d+) anchored kept"
$diverted = "\[workspaces\] close of an anchored tab diverted"
$asleep   = "\[workspaces\] (hibernated anchored tab at index|anchored tab at index \d+ (asks before leaving|could not be discarded))"
$retag    = "\[workspaces\] tag '([^']*)' -> '([^']*)', relayout requested"
$snoozed  = "\[workspaces\] snooze: (\d+) of (\d+) tab\(s\)"
$unload   = "\[workspaces\] unload all but 'default': asking (\d+) tab\(s\)"
$homeZzz  = "\[workspaces\] tab contents replaced at index \d+ -> carried workspace 'default'"
$ins      = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"

$grades = @()
$d1 = @(In 0 $diverted).Count; $z1 = @(In 0 $asleep).Count
# A sleeping tab may not be a DevTools page at all: the anchor still in the list is your eyes.
$grades += [pscustomobject]@{ ok = ($d1 -ge 1 -and $z1 -ge 1); why = "Ctrl+W diverted x$d1, put to sleep or kept live x$z1 (want 1+ each); DevTools still lists P92 anchor: $((Open 0) -contains 'anchor'); the anchor in the list is your eyes" }
$c2 = G (In 1 $closing | Where-Object { $_.Matches[0].Groups[3].Value } | Select-Object -Last 1)
$grades += [pscustomobject]@{ ok = [bool]($c2.Count -and $c2[2] -eq $canary -and [int]$c2[4] -ge 1 -and (Open 1) -contains "two" -and (Open 1).Count -eq 1); why = "$(if ($c2.Count) { "'$($c2[0])'" } else { 'no Clear Today closing line' }) (want Canary, 1+ anchored kept); still open [$((Open 1) -join ', ')] (want two only)" }
$t3 = @(In 2 $retag "send" | Where-Object { $_.Matches[0].Groups[1].Value -eq $work -and $_.Matches[0].Groups[2].Value -eq $private }).Count
$grades += [pscustomobject]@{ ok = ($t3 -eq 1 -and (Open 2) -contains "middle" -and (Open 2) -contains "bottom" -and (Open 2) -notcontains "top"); why = "tabs moved Work -> Private after the close x$t3 (want 1); still open [$((Open 2) -join ', ')] (want middle, bottom); which one moved is your eyes" }
$s4 = G (In 3 $snoozed "send" | Select-Object -Last 1)
$grades += [pscustomobject]@{ ok = [bool]($s4.Count -and $s4[1] -eq "1" -and (Open 3) -notcontains "s-middle" -and (Open 3) -contains "s-bottom"); why = "$(if ($s4.Count) { "'$($s4[0])'" } else { 'no snooze line after the close' }) (want 1 of 1); still open [$((Open 3) -join ', ')] (want s-bottom, not s-middle)" }
$u5 = G (In 4 $unload | Select-Object -Last 1); $h5 = @(In 4 $homeZzz).Count
$grades += [pscustomobject]@{ ok = [bool]($u5.Count -and $h5 -eq 0); why = "$(if ($u5.Count) { "'$($u5[0])'" } else { 'no unload line' }); Home tabs put to sleep x$h5 (want 0); no reload is your eyes" }
$r6 = @(In 5 "\[workspaces\] pins: brought the page of 'p92l' from another window" "send").Count
$i6 = @(In 5 $ins "send" | Where-Object { $_.Matches[0].Groups[2].Value -eq $work -and $_.Matches[0].Groups[3].Value -eq $work }).Count
$u6 = @(In 5 "\[workspaces\] pins: unpinned item 'p92s'" "send").Count
$grades += [pscustomobject]@{ ok = ($r6 -ge 1 -and $u6 -ge 1); why = "P92 left brought from the first window x$r6 (want 1); pages tagged Work landing in a window on Work x$i6 (the second window's own New Tab is one more); the row unpinned x$u6 (want 1); the split in the second window is your eyes" }

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
Say "RESULT try-92$sfx $pass of $($names.Count) PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Log: $log"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
