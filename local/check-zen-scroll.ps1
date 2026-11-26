param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$Tag = "zs", [int]$WaitSeconds = 90,
      [double]$IdleMinutes = 15, [ValidateSet("A", "B", "C", "W", "X", "F")][string[]]$Rows = @("A", "B", "C"),
      [ValidateSet("middle", "bottom")][string[]]$At = @("middle", "bottom"), [string]$BinDir = "")
# The owner's report (2026-11-22): in zen mode, with the sidebar hidden, after a while (often a YouTube video in a
# Today tab) the sidebar shown again has its long list back at the very top -- not where it was left, not at the
# current tab. The cause: a space switch (row W, found 2026-11-22), fixed by patch 115 (W, X, F green on its 115g
# build); A/B/C are the first guesses, which did not reproduce it. On a throwaway copy of the smoke profile:
# zen mode on, the sidebar unpinned and wide (415, rows 40, the owner's), 80 local pages "ZS z01".."ZS z80" as Today
# tabs of Home (newest first: z80 at the top), the window 1000x800 DIP. Run 3 (280 wide, rows 30, 90 s): 5 of 6
# kept, 0 px -- the bug did NOT reproduce; B/bottom was a set-up miss, fixed. Each row, once per -At place (the owner: "the active tab at the bottom or middle of the list,
# that's the most obvious scenario"): the sidebar shown (the mouse at the window's left edge); middle: the list rolled
# to its top, then 8 wheel notches down, the Today tab nearest the window's middle clicked; bottom: the list rolled
# to its end, its last Today tab clicked. Every Today tab's top noted; the page clicked, the mouse left on it (the
# sidebar slides away), the row's action, -WaitSeconds, the sidebar shown again, the tops read again.
#   A  nothing: a plain page, no video (is it YouTube at all?)
#   B  "p" pressed on the page: its title changes every second and it plays a tone at -60 dB (a video's tab: audible,
#      its title changing) -- "p" again after the reading
#   C  "f" pressed on the page: the page goes full screen (YouTube's own key), "f" again after -WaitSeconds
#   W  THE BUG (found 2026-11-22 with watch-sidebar.ps1; <local-path>\Helium-workspace\zen-scroll-findings.md): Home given a
#      long pinned section first (an open folder "ZS big" of 150 made-up items, ~6,000 px like the owner's Canary);
#      the list rolled to its end (bottom), or to its end and 10 notches back (middle); then Shift+Alt+2 (Work, its
#      pinned section short) and Shift+Alt+1 back, with the sidebar hidden. Red: the tab is scrolled in while Work's
#      short pinned rows are still drawn, Home's 150 then push it down. -Rows W alone (the folder would push A/B/C's
#      Today tabs out of their reach); both switches must be logged ("active workspace ->") or the row fails
#   X  THE AUTO-SWITCH (patch 115's review, finding 1, 2026-11-25): W's folder and places, MRU Ctrl+Tab on. The tab
#      clicked, the sidebar let go, a keyboard trip to Work and back (Ctrl+T first, once: a New Tab in Work) leaves
#      Work's tab the one left last; the tops read; then one Ctrl+Tab (Work's tab: the window follows it, FollowTab)
#      and one more (the Home tab: it follows back), the sidebar hidden. The tab is activated BEFORE the switch here,
#      so the place saved may already be moved toward it. Both trips logged or the row fails. -Rows X alone.
#      STRICT: kept only (the current tab drawn whole would hide exactly what this row looks for)
#   F  THE FLASH (patch 115's review, finding 2, 2026-11-26): W's folder and places, zen mode OFF (the sidebar shown
#      throughout). The tab clicked, the page clicked, then Chrome's own trace (DevTools Tracing, check-108's way)
#      while Home -> Work -> Home runs 3 times by the keyboard; all 6 switches logged or the row fails. The switch task
#      scrolls the list against the old space's rows (ActivateTabAt) and only POSTS the pinned section's Rebuild,
#      where patch 115 restores the place: a frame committed between the two shows that scroll for one frame.
#      trace-flash.py reads testprofile-$Tag\f-<at>-trace.jsonl (~45 MB, kept until this tag's next run): PASS = no
#      frame (a commit or a main frame) between any switch and its Rebuild.
#      -Rows F alone.
#   Z  0 crash markers in the log
# PASS per row: the list was left where it was (the shared tabs moved 2 px or less), OR the current tab is drawn
# whole inside the window -- the owner takes either (X: kept only). Real mouse and keys: it starts only when
# e17-pc-free.ps1 says FREE. Run in its own process:
#   pwsh -NoProfile -File local\check-zen-scroll.ps1 [-WaitSeconds 120] [-Rows A,B,C | -Rows W | -Rows X | -Rows F] [-IdleMinutes 0]
#   -BinDir <dir>: another build's folder (the 157 build moved aside for R9: <local-path>\Helium-workspace\src-157-78\out\Default)
. "$PSScriptRoot\e18-lib.ps1"
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
# `pwsh -File ... -Rows A,B` passes ONE string "A,B": split it (check-108's way).
$Rows  = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$At    = @($At | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })
$long  = $Rows -contains "W" -or $Rows -contains "X" -or $Rows -contains "F"   # Home given the 150-item folder
if ($long -and $Rows.Count -gt 1) { Write-Host "ABORT: -Rows W, -Rows X and -Rows F each run alone"; exit 1 }
$exe   = "$bin\chrome.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-$Tag"
$pages = "$ws\$Tag-pages"
$script:log = "$ws\$Tag-run.log"
$count = 80
# A switch in the run's log, the workspace switched to captured (W, X and F count them). Not "$switch": that is
# PowerShell's own variable inside a switch statement.
$switchRe = "\[workspaces\] active workspace -> '([^']*)'"
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:win = [IntPtr]::Zero; $script:workTab = $false
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Running { [bool]($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) }
function Msaa([string[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$script:win) @a }
# The Today tabs of the list (role 0x25, "ZS z.."), shown or not: name, box (physical px), shown.
function Tabs { @(ParseMsaaNodes (Msaa @("-List", "-Rect")) | Where-Object { $_.role -eq 0x25 -and $_.name -match '^ZS z\d\d' }) }
# Each shown tab's top, by its page's name ("ZS z07"; B's ticking title keeps that start).
function Tops($tabs) { $o = @{}; foreach ($t in @($tabs | Where-Object shown)) { $o[$t.name.Substring(0, 6)] = $t.t }; $o }
# How far the tabs shown both times moved (the median, px), and how many there were.
function Moved($a, $b) {
    $d = @($a.Keys | Where-Object { $b.ContainsKey($_) } | ForEach-Object { $b[$_] - $a[$_] } | Sort-Object)
    [pscustomobject]@{ common = $d.Count; by = $(if ($d.Count) { $d[[int][math]::Floor($d.Count / 2)] } else { $null }) }
}
function Client { [E18Input]::Client($script:win) }
# The run's log lines matching `re`, and how many (case-sensitive: the fork's own words).
function Lines([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
# Shift+Alt+N and the like (SendKeys: "%+2"), only when the browser's window is in front (check-108's Keys).
function Keys([string]$k) {
    if ([ZsFg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds 500; "sent"
}
# The sidebar shown: the mouse at the window's left edge, the slide given time, then the mouse parked over the list.
# Parked there because every helper (Wheel, Click) puts the cursor back where it was: back to the edge from over the
# list is zen's "leaving through the side gap" (BrowserView::IsLeavingZenSideGap), and the sidebar hid mid-step
# (first run, 2026-11-22: every row found no tab shown).
function Reveal {
    $c = Client; $s = [E18Input]::Dpi($script:win) / 96.0; $y = $c[1] + [int]($c[3] / 2)
    $r = [E18Input]::Hover($script:win, $c[0] + 3, $y); Start-Sleep 2
    $r += ", parked: " + [E18Input]::Hover($script:win, $c[0] + [int](120 * $s), $y); Start-Sleep 1
    $r
}
# The mouse onto the page, right of the sidebar: it slides away after zen's grace period.
function Away { $c = Client; $r = [E18Input]::Hover($script:win, $c[0] + [int]($c[2] * 0.75), $c[1] + [int]($c[3] * 0.6)); Start-Sleep 3; $r }

function ServeZs {
    $null = New-Item -ItemType Directory -Force $pages
    foreach ($i in 1..$count) {
        $n = "z{0:D2}" -f $i
        # "f": full screen and back (a key press is the gesture it needs); "p": the title ticks and a -60 dB tone
        # plays, "p" again stops both.
        $js = "let k=0,t=null,a=null;onkeydown=e=>{if(e.key==='f'){document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen();}" +
              "if(e.key==='p'){if(t){clearInterval(t);t=null;a.close();a=null;document.title='ZS $n';return;}" +
              "a=new AudioContext();const o=a.createOscillator(),g=a.createGain();g.gain.value=0.001;o.connect(g).connect(a.destination);o.start();" +
              "t=setInterval(()=>document.title='ZS $n '+(++k),1000);}};"
        Set-Content -Encoding UTF8 -LiteralPath "$pages\$n.html" -Value "<!doctype html><title>ZS $n</title><h1>ZS $n</h1><p>f: full screen, p: play<script>$js</script>"
    }
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    $server = Start-Process python -ArgumentList "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $pages -WindowStyle Hidden -PassThru
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$port/z01.html").Content -match "ZS z01") { return [pscustomobject]@{ port = $port; server = $server } } } catch {} }
    Stop-Process -Id $server.Id -EA SilentlyContinue
    $null
}

# ---- F: Chrome's own trace over the browser's DevTools socket (check-108's Traced) ----------------------------------
$script:sock = $null; $script:traceN = 0
function Ws {
    if (-not $script:sock) {
        $port = (Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1).Trim()
        $script:sock = [Net.WebSockets.ClientWebSocket]::new()
        $script:sock.ConnectAsync([Uri](Invoke-RestMethod "http://127.0.0.1:$port/json/version").webSocketDebuggerUrl,
            [Threading.CancellationToken]::None).Wait()
    }
    $script:sock
}
function WsSend([string]$s) {
    $by = [Text.Encoding]::UTF8.GetBytes($s)
    (Ws).SendAsync([ArraySegment[byte]]::new($by), 'Text', $true, [Threading.CancellationToken]::None).Wait()
}
# Each message waited for 120 s at most (Dcheck 360): a browser that hangs with its socket open would otherwise hold
# the check -- and the PC -- for ever (review, 11-27). The wait's end throws; OneRow's caller records the ERROR.
function WsRecv {
    $cts = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($(if ($Build -eq "Dcheck") { 360 } else { 120 })))
    try {
        $buf = [byte[]]::new(1MB); $ms = [IO.MemoryStream]::new()
        do {
            $r = (Ws).ReceiveAsync([ArraySegment[byte]]::new($buf), $cts.Token).GetAwaiter().GetResult()
            $ms.Write($buf, 0, $r.Count)
        } while (-not $r.EndOfMessage)
        [Text.Encoding]::UTF8.GetString($ms.ToArray())
    } finally { $cts.Dispose() }
}
# One trace while `act` runs; each Tracing.dataCollected message a line of `file`. "toplevel": every task a thread
# runs and where it was posted from; "toplevel.flow": which task posted it; "cc": the window's compositor
# (SingleThreadProxy::DoCommit, then DoComposite: a frame); "views", "ui": layout and paint.
function Traced([string]$file, [scriptblock]$act) {
    $script:traceN++; $n = 10 * $script:traceN
    WsSend ('{"id":' + $n + ',"method":"Tracing.start","params":{"traceConfig":{"includedCategories":' +
        '["toplevel","toplevel.flow","cc","views","ui"]},"transferMode":"ReportEvents"}}')
    do { $m = WsRecv } while ($m -notmatch ('"id":' + $n + '\b'))
    if ($m -match '"error"') { return "trace NOT started: $m" }
    try { $null = & $act } finally {
        WsSend ('{"id":' + ($n + 1) + ',"method":"Tracing.end"}')
        $w = [IO.StreamWriter]::new($file)
        try {
            do { $m = WsRecv; if ($m -match '"method":"Tracing.dataCollected"') { $w.WriteLine($m) } }
            while ($m -notmatch '"method":"Tracing.tracingComplete"')
        } finally { $w.Close() }
    }
    "traced"
}
# F after OneRow's set-up (W's places, the tab clicked): the page clicked, so the keys reach the window and not the
# list; three keyboard trips Home -> Work -> Home under the trace; trace-flash.py grades the frames.
function FlashRow([string]$at, [string]$name, [string[]]$said) {
    $c = Client
    $said += "page: " + [E18Input]::Click($script:win, $c[0] + [int]($c[2] * 0.75), $c[1] + [int]($c[3] * 0.6), $false)
    Start-Sleep 1
    $c0 = Count $switchRe
    # In the throwaway profile (~45 MB each): kept for re-reading, gone with the profile at this tag's next run.
    $file = "$prof\f-$at-trace.jsonl"
    $script:fkeys = @()
    $said += Traced $file {
        foreach ($i in 1..3) {
            $script:fkeys += "Shift+Alt+2: $(Keys '%+2')"; Start-Sleep 2
            $script:fkeys += "Shift+Alt+1: $(Keys '%+1')"; Start-Sleep 2
        }
    }
    $said += $script:fkeys
    $switched = @(Lines $switchRe | Select-Object -Skip $c0 | ForEach-Object { $_.Matches[0].Groups[1].Value })
    # Exactly Work, Home, three times (a lost or doubled key must not pass).
    $switchOk = $switched.Count -eq 6 -and $switched[0] -ne "default" -and
                (($switched -join ',') -eq ((@($switched[0], "default") * 3) -join ','))
    $mb = if (Test-Path -LiteralPath $file) { [math]::Round((Get-Item -LiteralPath $file).Length / 1MB, 1) } else { 0 }
    $read = @(& python -I "$here\trace-flash.py" $file $script:bpid 2>&1 | ForEach-Object { "$_" })
    $rc = $LASTEXITCODE
    $read | ForEach-Object { Say "      $_" }
    Verdict ("F/$at the flash, the sidebar shown: current '$name'; trace $file ($mb MB); switches logged " +
             "[$($switched -join ' -> ')] ok $switchOk; trace-flash.py exit $rc (0 = no frame between a switch and its " +
             "Rebuild) [$($said -join '; ')]") ($switchOk -and $rc -eq 0)
}

function OneRow([string]$row, [string]$at) {
    if (-not (Running)) { throw "the browser is gone before row $row" }
    $s = [E18Input]::Dpi($script:win) / 96.0
    # Away first: the last row ended with the sidebar shown and the mouse parked on it, and from there to the edge is
    # "leaving through the side gap" again (run 3: B/bottom found no tab shown).
    $said = @("away first: $(Away)", "reveal: $(Reveal)")
    # Over the list (the sidebar keeps showing while the mouse is on it): middle -- to the top, then 8 notches down;
    # bottom -- to the end.
    $c = Client; $x = $c[0] + [int](120 * $s); $y = $c[1] + [int]($c[3] / 2)
    if ($row -in "W", "X", "F") {
        # Below the ~6,000 px folder: to the end (90 notches), and for middle 10 notches back up.
        $said += "wheel: " + [E18Input]::Wheel($script:win, $x, $y, [int[]](@(-120) * 90), 40)
        Start-Sleep 2
        if ($at -eq "middle") { $said += [E18Input]::Wheel($script:win, $x, $y, [int[]](@(120) * 10), 300); Start-Sleep 2 }
    } else {
        $said += "wheel: " + [E18Input]::Wheel($script:win, $x, $y, [int[]](@($(if ($at -eq "bottom") { -120 } else { 120 })) * 30), 40)
        Start-Sleep 2
        if ($at -eq "middle") { $said += [E18Input]::Wheel($script:win, $x, $y, [int[]](@(-120) * 8), 300); Start-Sleep 2 }
    }
    # The current tab: middle -- the Today tab nearest the window's middle; bottom -- the lowest one drawn whole.
    # Click puts the cursor back on the list.
    $mid = $c[1] + $c[3] / 2
    $shown = @(Tabs | Where-Object { $_.shown -and $_.t + $_.h -le $c[1] + $c[3] })
    $pick = if ($at -eq "bottom") { $shown | Sort-Object t | Select-Object -Last 1 } else { $shown | Sort-Object { [math]::Abs($_.t + $_.h / 2 - $mid) } | Select-Object -First 1 }
    if (-not $pick) { Verdict "$row/$at a Today tab to click (none shown: $($said -join '; '))" $false; return }
    $name = $pick.name.Substring(0, 6)
    $said += "'$name' " + [E18Input]::Click($script:win, $pick.l + [int]($pick.w / 2), $pick.t + [int]($pick.h / 2), $false)
    Start-Sleep 2
    if ($row -eq "F") { FlashRow $at $name $said; return }
    if ($row -eq "X") {
        # Work's tab made the one left LAST (MRU's order: the active tab, then the latest left): W's keyboard trip,
        # the sidebar let go first. The click above left another Home tab, so this trip comes after it.
        $c = Client
        $said += "page: " + [E18Input]::Click($script:win, $c[0] + [int]($c[2] * 0.75), $c[1] + [int]($c[3] * 0.6), $false)
        $said += "away: $(Away)"
        $c0 = Count $switchRe
        $said += "Shift+Alt+2: $(Keys '%+2')"; Start-Sleep 3
        if (-not $script:workTab) { $said += "Ctrl+T: $(Keys '^t')"; Start-Sleep 3; $script:workTab = $true }
        $said += "Shift+Alt+1: $(Keys '%+1')"; Start-Sleep 3
        $manual = @(Lines $switchRe | Select-Object -Skip $c0 | ForEach-Object { $_.Matches[0].Groups[1].Value })
        $said += "reveal: $(Reveal)"
    }
    $before = Tops (Tabs)
    # The page clicked, so "p" and "f" reach it (the tab's click left the keys in the tab strip); the cursor comes back
    # to the list, then goes onto the page.
    $c = Client
    $said += "page: " + [E18Input]::Click($script:win, $c[0] + [int]($c[2] * 0.75), $c[1] + [int]($c[3] * 0.6), $false)
    $said += "away: $(Away)"
    $hidden = @(Tabs | Where-Object shown).Count
    switch ($row) {
        "B" { $said += "p: " + [E18Input]::Tap([uint32]$script:bpid, 0x50) }
        "C" { $said += "f: " + [E18Input]::Tap([uint32]$script:bpid, 0x46) }
    }
    $switched = $null
    if ($row -eq "W") {
        # Away to Work and back to Home by the keyboard, the sidebar hidden; each switch must be logged.
        $c0 = Count $switchRe
        $said += "Shift+Alt+2: $(Keys '%+2')"; Start-Sleep 3
        $said += "Shift+Alt+1: $(Keys '%+1')"; Start-Sleep 3
        $switched = @(Lines $switchRe | Select-Object -Skip $c0 | ForEach-Object { $_.Matches[0].Groups[1].Value })
        Say "      $row/$at switched: $($switched -join ' -> ') (the sidebar hidden: $hidden shown tab(s), want 0)"
    } elseif ($row -eq "X") {
        # The auto-switch both ways, the sidebar hidden: Work's tab, then the Home tab, each by one MRU Ctrl+Tab.
        $c1 = Count $switchRe
        $said += "Ctrl+Tab: $(Keys '^{TAB}')"; Start-Sleep 3
        $said += "Ctrl+Tab: $(Keys '^{TAB}')"; Start-Sleep 3
        $switched = @(Lines $switchRe | Select-Object -Skip $c1 | ForEach-Object { $_.Matches[0].Groups[1].Value })
        Say "      $row/$at switched: by keys $($manual -join ' -> '), by Ctrl+Tab $($switched -join ' -> ') (the sidebar hidden: $hidden shown tab(s), want 0)"
    } else {
        Say "      $row/$at waiting $WaitSeconds s (the sidebar hidden: $hidden shown tab(s), want 0) ..."
        Start-Sleep $WaitSeconds
    }
    if ($row -eq "C") { $said += "f again: " + [E18Input]::Tap([uint32]$script:bpid, 0x46); Start-Sleep 3 }
    $said += "reveal: $(Reveal)"
    $now = Tabs
    $after = Tops $now
    if ($row -eq "B") { $said += "p again: " + [E18Input]::Tap([uint32]$script:bpid, 0x50) }
    $m = Moved $before $after
    $cur = @($now | Where-Object { $_.shown -and $_.name.StartsWith($name) }) | Select-Object -First 1
    $c = Client
    $curWhole = [bool]($cur -and $cur.t -ge $c[1] -and $cur.t + $cur.h -le $c[1] + $c[3])
    $first = @($now | Where-Object { $_.shown -and $_.name.StartsWith("ZS z01") }) | Select-Object -First 1
    $kept = $m.common -ge 5 -and [math]::Abs($m.by) -le 2
    # W counts only when both switches happened: away from Home, then back to it ('default').
    $switchOk = $row -notin "W", "X" -or ($switched.Count -ge 2 -and $switched[-1] -eq "default" -and @($switched | Where-Object { $_ -ne "default" }).Count -ge 1)
    # X: both trips exactly Home -> Work -> Home -- the keyboard's, then Ctrl+Tab's (a lost key must not pass).
    if ($row -eq "X") {
        $switchOk = (($manual -join ',') -eq ($switched -join ',')) -and $switched.Count -eq 2 -and $switched[0] -ne "default" -and $switched[1] -eq "default"
    }
    $label = @{A = 'plain page'; B = 'title ticking + tone'; C = 'full screen'; W = 'space switch away and back';
               X = 'auto-switch away and back (MRU Ctrl+Tab), kept only'}[$row]
    $ok = if ($row -eq "X") { $switchOk -and $kept } else { $switchOk -and ($kept -or $curWhole) }
    Verdict ("$row/$at ${label}: tabs shown before $($before.Count), hidden $hidden, after $($after.Count); " +
             "shared $($m.common) moved by $($m.by) px (kept: $kept); current '$name' drawn whole $curWhole; 'ZS z01' shown $([bool]$first)" +
             "$(if ($row -eq 'W') { "; switches logged [$($switched -join ' -> ')] ok $switchOk" })" +
             "$(if ($row -eq 'X') { "; switches logged: keys [$($manual -join ' -> ')], Ctrl+Tab [$($switched -join ' -> ')] ok $switchOk" }) [$($said -join '; ')]") $ok
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) { Abort "a browser of $bin is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "] zen: box over the page"
if ($LASTEXITCODE -ne 0) { Abort "$bin\chrome.dll has no patch 94 ('] zen: box over the page')" }
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for the browser's windows ($free); started by hand: -IdleMinutes 0, then let go of the mouse" }
# Only A, B and C wait -WaitSeconds (W, X and F switch at once).
$waits = if (@($Rows | Where-Object { $_ -in "A", "B", "C" }).Count) { ", $WaitSeconds s each" } else { "" }
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime); rows $($Rows -join ',') at $($At -join ',')$waits"
E18InputType
Add-Type -AssemblyName System.Windows.Forms
if (-not ("ZsFg" -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class ZsFg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }' }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
# Archive after 7 days: no sweep closes a test page during the waits.
# The owner's daily settings (read 2026-11-22): sidebar 415 wide, rows 40, the top bar hidden too.
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=415" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "helium.workspaces.enabled=true" "helium.workspaces.archive_after_minutes=10080" "helium.workspaces.tab_row_height=40" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" "helium.browser.zen_mode_top_chrome_pinned=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
if ($Rows -contains "F") {
    # The sidebar shown throughout (finding 2: a frame of the list drawn mid-switch is seen only then).
    & python -I "$here\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=false" | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort "zen mode was not turned off in $prof" }
}
if ($Rows -contains "X") {
    # MRU Ctrl+Tab crosses workspaces (patch 63, check-c2's c2): the keyboard's way to an auto-switch.
    & python -I "$here\prefs.py" "$prof\Default\Preferences" "helium.browser.mru_tab_cycling=true" | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort "MRU cycling was not seeded into $prof" }
}
if ($long) {
    # Home ('default') given the long pinned section first: an open folder of 150 made-up items (check-108's way).
    $seed = @'
import json, sys
path = sys.argv[1]
d = json.load(open(path, encoding="utf-8"))
items = [{"type": "item", "id": "zsbig%03d" % i, "title": "ZS big %d" % i, "url": "https://zs-big.test/%d" % i} for i in range(1, 151)]
d["workspaces"]["default"][0:0] = [{"type": "folder", "id": "zsbig", "title": "ZS big", "open": True, "children": items}]
assert d["workspaces"]["2ab592d4-a80b-4a1d-aeaa-6acd51c12134"], "no Work"
open(path, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False))
'@
    $seedFile = "$env:TEMP\check-zen-scroll-seed.py"
    [IO.File]::WriteAllText($seedFile, $seed)
    & python -I $seedFile "$prof\Default\Workspace Pins"
    if ($LASTEXITCODE -ne 0) { Abort "the folder was not added to $prof's pins" }
}
$sv = ServeZs
if (-not $sv) { Abort "the pages are not served" }

try {
    Remove-Item -LiteralPath $script:log -EA SilentlyContinue
    $urls = @(1..$count | ForEach-Object { "http://127.0.0.1:$($sv.port)/z{0:D2}.html" -f $_ })
    # F traces over DevTools: its port in $prof\DevToolsActivePort (check-108's way).
    $dev  = if ($Rows -contains "F") { @("--remote-debugging-port=0") } else { @() }
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList (@("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0",
                     "--no-first-run", "--no-default-browser-check") + $dev + $urls)).Id
    $t0 = Get-Date
    while ($script:win -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:win = $p.MainWindowHandle } }
    if ($script:win -eq [IntPtr]::Zero) { throw "no browser window in 30 s" }
    $s = [E18Input]::Dpi($script:win) / 96.0; $scr = [E18Input]::Screen()
    [E18Input]::Place($script:win, 40, 40, [math]::Min($scr[0] - 80, [int](1000 * $s)), [math]::Min($scr[1] - 120, [int](800 * $s)))
    $t0 = Get-Date
    do { Start-Sleep 2; $n = @(Tabs).Count } while ($n -lt $count -and ((Get-Date) - $t0).TotalSeconds -lt 60)
    Verdict "setup: $n of $count pages are Today tabs, their titles loaded; window $((Client) -join ',') px" ($n -ge $count)
    foreach ($r in $Rows) { foreach ($a in $At) { try { OneRow $r $a } catch { Say "ERROR $r/$a (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ } } }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    if ($script:sock) { $script:sock.Dispose() }
    if (Running) {
        foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) }
        $t0 = Get-Date; while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1 }
    }
    Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    if ($sv) { Stop-Process -Id $sv.server.Id -EA SilentlyContinue }
}
$markers = if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } else { -1 }
Verdict "Z crash markers in $($script:log): $markers" ($markers -eq 0)
$total = 2 + $Rows.Count * $At.Count
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
