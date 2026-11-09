param([switch]$NoLaunch, [switch]$GradeOnly, [string[]]$Steps = @())
# `pwsh -File ... -Steps 1,4` passes ONE string "1,4" (as [int] it read 14: the comma a thousands separator).
$Steps = @($Steps | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [int]$_ })
# C20 (patch 89 `89-link-preview.patch`, <local-path>\Helium-workspace\c21-progress.md): the owner's own try of the link preview
# -- what a person sees and feels (check-c20.ps1 already passed it hands-free). It opens the built browser (out\Default)
# on a FRESH copy of the smoke profile (never the daily browser's profile), in Light mode, in Home, with two Today tabs
# and a pinned page "C20 pinned" added at the end of Home's pinned rows. The pages are check-c20's (local\c20\*.html),
# served from this PC on 127.0.0.1:<port> and reached as localhost:<port> too: two different SITES, so the pinned
# page's "C20 other link" is a link to another site. ONE question per step: a step starts when the one before it was
# answered, you do it, then answer y/n -- it is graded only on the log lines written in between (the owner's first try
# had a separate "Enter to start" prompt answered at the wrong moments). Every step is graded from the log
# ("[workspaces] link preview: ..." lines); what only eyes can tell is said in its line.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c20.ps1
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again from
# the last try's log and step marks (the browser closed). -Steps 1,2,4: only those steps (a re-try); the rest "not tried".
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = "$ws\helium-windows\build\src\out\Default"
$exe   = "$bin\chrome.exe"
$py    = "C:\Python314\python.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-c20-owner"
$dflt  = "$prof\Default"
$logs  = @("$ws\c20-owner-run1.log")
$txt   = "$ws\c20-owner-try.txt"
$markf = "$ws\c20-owner-marks.json"
$web   = "$ws\c20-owner-pages"
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
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$here\c20\c20pin.html")) { $bad += "no check-c20 pages in $here\c20" }
if (Test-Path -LiteralPath $exe) {
    & $py -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "link preview: opened as tab"
    if ($LASTEXITCODE -ne 0) { $bad += "this build has no patch 89 yet (no 'link preview: opened as tab' in out\Default\chrome.dll): tell Claude" }
}
if ($GradeOnly -and -not (Test-Path -LiteralPath $markf)) { $bad += "no $markf to grade (no finished try)" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

$names = @("a preview from the menu", "links inside the card", "four ways to close it", "a tab switch closes it", "Arc's rule on a pinned page", "Open as tab")
function Ask([int]$i) { $a = "$(Read-Host "    Done with ALL of step $($i + 1)? Did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath (@("$dflt\Workspace Archive", $markf, $txt) + $logs) -EA SilentlyContinue
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    # check-c20's pages, and the plain ones its ServePages makes (a title and a big heading).
    $null = New-Item -ItemType Directory -Force $web
    Copy-Item -Path "$here\c20\*.html" -Destination $web -Force
    foreach ($nm in "c20same", "c20next", "c20side") { Set-Content -Encoding UTF8 -LiteralPath "$web\$nm.html" -Value "<!doctype html><title>E18 $nm</title><h1>E18 $nm</h1>" }
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    # The pinned page "C20 pinned" (id c20p) at the end of Home's rows, as check-c20 adds it to Work.
    & $py -I -c "import json,sys; p,port=sys.argv[1:3]; d=json.load(open(p,encoding='utf-8')); d['workspaces']['default'].append({'type':'item','id':'c20p','title':'C20 pinned','url':'http://127.0.0.1:%s/c20pin.html' % port}); open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$dflt\Workspace Pins" $port
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the pinned page 'C20 pinned' was not written"; exit 1 }
    @"

The test browser opens on a fresh COPY of the smoke profile (your daily browser is not touched), in Light mode, in its
workspace Home. Words used below:
  - the CARD: the link preview -- a box over the page holding the linked page, the page around it dimmed.
  - a PINNED PAGE: a row in the section under the workspace's header. Home's rows, top to bottom: Example A, Smoke
    folder (open: Wikipedia, Renamed C), Closed folder, Example D, and "C20 pinned" (new, the last row: used in step 5).
  - a TODAY TAB: an ordinary tab in the list under the pinned pages. Home starts with two: "E18 c20home" (one link,
    "C20 target link") and "E18 c20side" (a heading only).
  - the COUNTING PAGE: the page every card shows first ("E18 c20target"): a number counting up, 10 a second, and the
    link "C20 next link". A reload starts the number at 0 again.
Do every step in WINDOW 1 (the only window), IN HOME, each starting with NO card up. THIS window says "STEP N: do
it now" -- do ALL of step N in the browser, come back here, answer y or n; the next step starts at once.

 1. A preview from the menu. Click the Today tab "E18 c20home". Right-click its link "C20 target link"; in the menu
    choose "Preview link" (just under "Open link in new tab").
    PASS: a card over the page, about 85% of it, centred; at its top the site 127.0.0.1:$port and an x at the
    right; "Open as tab" at its bottom right; the page round the card dimmed; in the card the counting page. No new
    Today tab. Then press Esc.
 2. Links inside the card. Open the card again as in step 1. In the CARD click "C20 next link".
    PASS: the card now shows the heading "E18 c20next", still IN the card; the tab behind is still "E18 c20home"
    (dimmed), and no new Today tab. Then press Alt+Left.
    PASS: back to the counting page IN the card, the card still up. Then press Esc.
 3. Four ways to close it. Each time open the card as in step 1 first:
    a) click once on the card's white middle, press Esc;  b) click the dimmed page OUTSIDE the card (the strip below it);
    c) click the card's x (its top right);  d) click once on the card's white middle, press Ctrl+W.
    PASS each time: the card goes, and "E18 c20home" stays open behind it (Ctrl+W must NOT close the tab).
 4. A tab switch closes it. Open the card as in step 1. Without clicking anything, press Ctrl+Tab.
    PASS: the card closes and "E18 c20side" comes in front. Click "E18 c20home": no card on it (it closed, not hid).
 5. Arc's rule on a pinned page. Click the pinned page "C20 pinned" (the last pinned row): a page with two links.
    Click its "C20 other link".
    PASS: a card opens BY ITSELF (no menu), its top naming the site localhost:$port (another site), the counting page in
    it; behind it the pinned page still shows its two links (it did not move). Press Esc.
    Then click "C20 same link". PASS: NO card; the pinned page itself goes to the heading "E18 c20same", as before C20.
 6. Open as tab. Click the Today tab "E18 c20home" and open the card as in step 1. Wait until its number is past 100,
    then click "Open as tab".
    PASS: the card closes; "E18 c20target" is now the FIRST Today tab of Home and in front, its number counting on from
    where it was (NOT back at 0: the same page, not reloaded); the window stays in Home.
Then close the browser any way you like: the script grades.
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof, the pages $web, port $port)"; exit 0 }
    $srv = Start-Process $py -ArgumentList "-I", "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $web -WindowStyle Hidden -PassThru
    $up = $false
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://localhost:$port/c20pin.html").Content -match "E18 c20pin") { $up = $true; break } } catch {} }
    if (-not $up) { Stop-Process -Id $srv.Id -EA SilentlyContinue; Write-Host "NOT READY: the pages were not served on localhost:$port (step 5's other site)"; exit 1 }
    $marks = @(); $said = @()
    try {
        Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[0])`"") + $flags + @("http://127.0.0.1:$port/c20home.html", "http://127.0.0.1:$port/c20side.html"))
        WaitOpen
        for ($i = 0; $i -lt $names.Count; $i++) {
            $m = [pscustomobject]@{ run = 0; start = (LineCount 0); end = 0 }
            if ($Steps.Count -and $Steps -notcontains ($i + 1)) { $said += "-"; $m.end = $m.start; $marks += $m; continue }
            Write-Host "`n==> STEP $($i + 1) ($($names[$i])): do it NOW in the browser (its words are above, under '$($i + 1).')."
            $said += Ask $i
            $m.end = LineCount 0; $marks += $m
        }
        Write-Host "`nNow close the test browser (any way). Waiting for it..."
        WaitClosed
        Start-Sleep 3
    } finally { Stop-Process -Id $srv.Id -EA SilentlyContinue }
    ConvertTo-Json -InputObject @($marks) | Set-Content -Encoding UTF8 -LiteralPath $markf
} else {
    $marks = @(Get-Content -Raw -LiteralPath $markf | ConvertFrom-Json)
    Say ""
    $said = @(for ($i = 0; $i -lt $names.Count; $i++) { Ask $i })
}

# ---- the grades: workspace_link_preview.cc's lines (patch 89), case-sensitive -----------------------------------------
function Lines([int]$run, [string]$re) { if (Test-Path -LiteralPath $logs[$run]) { @(Select-String -LiteralPath $logs[$run] -CaseSensitive -Pattern $re) } else { @() } }
# Step i's lines matching re: only those written after it began and before your answer.
function In([int]$i, [string]$re) { $m = $marks[$i]; if (-not $m) { return @() }; @(Lines $m.run $re | Where-Object { $_.LineNumber -gt $m.start -and $_.LineNumber -le $m.end }) }
function Last($l) { $l = @($l | Where-Object { $_ }); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Shown([int]$i, [string]$how) { @(In $i "\[workspaces\] link preview: shown \($how\) over tab \d+").Count }
# The causes of step i's closes, in order ("escape", "outside", "x", "ctrl+w", "tab switch", "open as tab", ...).
function Causes([int]$i) { @(In $i "\[workspaces\] link preview: closed \(([^)]*)\)" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
function Refused([int]$i) { @(In $i "\[workspaces\] link preview: (cannot show|dropped)").Count }
$ins = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"

$grades = @()
$s = Shown 0 "menu"; $n = @(In 0 $ins).Count; $r = Refused 0
$grades += [pscustomobject]@{ ok = ($s -ge 1 -and $n -eq 0 -and $r -eq 0); why = "'shown (menu)' x$s (want 1+), refused/dropped x$r, new tabs x$n (want 0, 0); its size, place and the dim are your eyes (check-c20's M1 measured them)" }
$c = Causes 1; $s = Shown 1 "menu"; $n = @(In 1 $ins).Count; $o = @(In 1 "link preview: opened as tab").Count
$grades += [pscustomobject]@{ ok = ($s -ge 1 -and $c.Count -le 1 -and -not @($c | Where-Object { $_ -ne "escape" }).Count -and $n -eq 0 -and $o -eq 0); why = "'shown (menu)' x$s; closes [$($c -join ', ')] (want only your last Esc: the card stayed up through the link and Alt+Left); new tabs x$($n + $o) (want 0); what the card showed is your eyes" }
$c = Causes 2; $miss = @("escape", "outside", "x", "ctrl+w" | Where-Object { $c -notcontains $_ }); $a = @(In 2 "\[workspaces\] archived a manual close").Count
$grades += [pscustomobject]@{ ok = (-not $miss.Count -and $a -eq 0); why = "closes [$($c -join ', ')]$(if ($miss.Count) { ", MISSING $($miss -join ', ')" }); tabs closed x$a (want 0: Ctrl+W closed the card, not E18 c20home)" }
$c = Causes 3
$grades += [pscustomobject]@{ ok = ($c -contains "tab switch"); why = "closes [$($c -join ', ')] (want 'tab switch'$(if ($c -contains 'outside') { "; 'outside' = a click, not Ctrl+Tab" }))" }
$rule = @(In 4 "\[workspaces\] link preview: a pinned page's link to another site").Count; $s = Shown 4 "pinned page"; $r = Refused 4
$op = @(In 4 "\[workspaces\] pins: opened item 'c20p'").Count
$grades += [pscustomobject]@{ ok = ($s -ge 1 -and $s -eq $rule -and $r -eq 0); why = "'C20 pinned' opened x$op; 'a pinned page's link to another site' x$rule, 'shown (pinned page)' x$s (want the same, 1+), refused/dropped x$r; the same-site link (no card, the pinned page moved) logs nothing: your eyes" }
$oc = @(Causes 5 | Where-Object { $_ -eq "open as tab" }).Count
$ot = Last (In 5 "\[workspaces\] link preview: opened as tab at index (-?\d+), (\d+) entries, loading (\d)")
$it = if ($ot.Count) { Last @(In 5 $ins | Where-Object { $_.Matches[0].Groups[1].Value -eq $ot[1] }) } else { @() }
$grades += [pscustomobject]@{ ok = ($oc -ge 1 -and $ot.Count -and $ot[3] -eq "0" -and $it.Count -and $it[2] -eq "default" -and $it[3] -eq "default"); why = "'closed (open as tab)' x$oc; $(if ($ot.Count) { "'opened as tab at index $($ot[1]), $($ot[2]) entries, loading $($ot[3])' (want loading 0: not reloaded)" } else { 'no opened-as-tab line' }); $(if ($it.Count) { "inserted -> '$($it[2])' (on screen '$($it[3])')" } else { 'no insert at that index' }) (want 'default' = Home twice); the FIRST Today tab is your eyes" }

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
Say "crash markers in the log: $markers (want 0)"
Say "RESULT try-c20 $pass of $($names.Count) PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Log: $($logs -join ', ')"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
