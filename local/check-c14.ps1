param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "c14", [double]$IdleMinutes = 15)
# C14 + C34 (patches 72, 73), on a throwaway copy of the smoke profile (Home, Work, Canary...; Sessions
# emptied). Real keys -- the workspace shortcuts, Ctrl+W, Shift+Alt+K -- so it starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (a person starting it passes -IdleMinutes 0 and lets go of the mouse
# and keyboard). The pages are local\c14-pages\page.html, told what to be by their query, served on a port Windows
# gives. Which page shows is read from DevTools (document.visibilityState), the chip from MSAA, the rest from the log.
# The tone is faint (about -49 dBFS) but it does play on the speakers for a few seconds.
#   C14a  a tone playing in Work (a second page in front there), the window on Canary: "rail badge '<Work>'
#         -> 2" (kAudioPlaying), and the bar's chip is still named "Work" (a push button, 0x2B) with the tone's line
#         ("<alert text> - c14 tone") in its description.
#   C14b  that chip pressed: "-> the tab behind its badge", the window back in Work with the TONE in front -- a plain
#         switch would show the second page, the one left there last.
#   C14c  from Canary again (the badge back), the tone's tab closed: "-> none".
#   C14d  a page holding the fake camera and microphone in Work, the window on Canary: a recording badge,
#         "-> 0" (kMediaRecording; 12 / 13 for the microphone or the camera alone).
#   C34a  in Work p3, p1, p2 opened in that order (p2 the strip's last, no opener), shown p1, p3, p2; Ctrl+W on p2 ->
#         p3 in front, "last used tab -> index". Chromium's rule would show p1, the left neighbour.
#   C34b  a page Ctrl+clicks its two links (background tabs, the page their opener); the first shown, then Ctrl+W ->
#         the page in front again. Chromium's rule would show the second link (a tab the same opener opened).
#   C34c  Example A's pinned page opened, then p1 shown (the pinned page left last); Ctrl+W on p1 -> Example A's page
#         in front and still there 2 s later (D14: E15c's repair would move to the list's neighbour).
#   C34d  a tone in Work anchored (its menu's Anchor > Anchor to this page), a plain page q shown, then the tone again;
#         Ctrl+W on it -> hibernated, q in front (D15). From Canary no "rail badge -> 2" (the sleeping tab's
#         stale alert, review C14-1); back in Work, Ctrl+W on q does NOT wake the anchored tab (D17, review C34-1).
#   C34e  l2 then the links page shown (l2, a doomed tab after it in the strip, left last); Shift+Alt+K (Clear Today)
#         -> exactly ONE "last used tab" line -- closed in strip order the links page would land on l2 and walk again
#         (A4) -- the browser alive, Example A's page in front.
#   C34f  a page pinned (Chromium's Pin: a favorite), s opened, the favorite shown, r opened; Ctrl+W on r -> the
#         favorite in front (left last), not s (r's neighbour, Chromium's rule).
#   C34g  a page put in a new group, t opened (the grouped page left last), the group folded (a left click on its
#         header); Ctrl+W on t -> NOT the grouped page (D1: a folded tab is never landed on), the group still folded.
#   Z     0 crash markers in the log (case-sensitive).
# A pass needs every row. Run it in its own process -- pwsh -File local\check-c14.ps1 [-OutDir Dcheck]
# [-IdleMinutes 0] -- it compiles C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = if ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise.log" } else { "$ws\$Tag-run.log" }
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$active = "\[workspaces\] active workspace -> '([^']*)'"
# The contract's lines (c14-progress.md, FINAL DESIGN). A badge is int(tabs::TabAlert) (tab_alert.h: kMediaRecording 0,
# kAudioPlaying 2, kAudioRecording 12, kVideoRecording 13) or "none".
function Badge([string]$v) { "\[workspaces\] rail badge '$work' -> ($v)$" }
$pressed = "\[workspaces\] rail chip '$work' -> the tab behind its badge"
$last    = "\[workspaces\] last used tab -> index (\d+)"
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:port = 0; $script:pagePort = 0; $script:server = $null
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Last([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Matches[0] }) } }
# The last line matching `re`: the whole match, then its groups, as strings (empty when none).
function Grp([string]$re) { $m = @(Last $re); if ($m.Count) { @($m[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function ActiveWs { $g = Grp $active; if ($g.Count) { $g[1] } else { "" } }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
# Every MSAA node of window `h`, through e18-lib's one parser.
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
# The first shown node matching `re` in the browser's other windows (a menu, a submenu), pressed via MSAA (check-c3's).
function OtherPress([IntPtr]$main, [string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    "nothing matching '$re'"
}
# The descriptions of the shown push buttons (0x2B) named `name`: the bar's chips. msaa-press -Desc prints a view's
# description, its tooltip when that differs from the name -- newlines as " / ".
function ChipDesc([IntPtr]$h, [string]$name) {
    @(Msaa $h @("-List", "-Rect", "-Desc") | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x2B(\|INVISIBLE)?\|@-?\d+,-?\d+,(\d+),(\d+)\|desc=(.*)$' -and $Matches[1] -eq $name -and
            -not $Matches[2] -and [int]$Matches[3] -gt 0 -and [int]$Matches[4] -gt 0) { $Matches[5] }
    })
}
# Keys to the browser's window in front, through SendKeys ("%+2" is Shift+Alt+2) -- never to another window.
function Keys([string]$k) {
    if ([C14Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
# A workspace by its shortcut; the run stops when it does not show.
function Go([string]$k, [string]$guid) {
    $c = Count $active; $r = Keys $k
    if (-not ((WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid)) { throw "$k did not show workspace '$guid' ($r)" }
    Start-Sleep (1 * $slow)
}

# ---- the pages and DevTools (check-c2's) ------------------------------------------------------------------------
# local\c14-pages served by python's http.server on a port Windows gives (Windows reserved 8702-8801 on 2026-10-13,
# Logi Options+ holds 8765), polled until it answers: the server's process, or $null (stopped) when it never did.
function Serve([string]$dir) {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $script:pagePort = $l.LocalEndpoint.Port; $l.Stop()
    $p = Start-Process python -ArgumentList "-m", "http.server", $script:pagePort, "--bind", "127.0.0.1", "--directory", $dir -WindowStyle Hidden -PassThru
    foreach ($i in 1..20) {
        Start-Sleep -Milliseconds 500
        try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$($script:pagePort)/page.html").StatusCode -eq 200) { return $p } } catch {}
    }
    Stop-Process -Id $p.Id -EA SilentlyContinue
    $null
}
function Url([string]$n) { "http://127.0.0.1:$($script:pagePort)/page.html?$n" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array to the pipeline as ONE object.
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
# A page by its short name: "c14-tone" for .../page.html?c14-tone, else its address.
function Short([string]$u) { if ($u -match '/page\.html\?([\w-]+)') { $Matches[1] } else { $u } }
function Has([string]$n) { @(Targets | Where-Object { (Short $_.url) -eq $n }).Count }
# The page that shows: the one whose document is visible, by its short name ("none", or "a+b" when two say so).
function Visible {
    Start-Sleep -Milliseconds (300 * $slow)
    $v = @(Targets | Where-Object { (Evaluate $_.webSocketDebuggerUrl "document.visibilityState") -eq "visible" } | ForEach-Object { Short $_.url })
    if ($v.Count) { $v -join "+" } else { "none" }
}
# Page `n` opened in front (/json/new: appended, no opener -- PAGE_TRANSITION_AUTO_TOPLEVEL), once its title is in:
# its target (id, url, webSocketDebuggerUrl).
function NewTab([string]$n) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $n)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$n'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.title") -ne ($n -replace "-", " ") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A page brought in front (/json/activate: the tab activated, as a click on it).
function Show($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
function CloseTarget($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/close/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# The page's own word on its tone or camera (page.html's c14state), polled until it says `want`.
function State($t, [string]$want) {
    $t0 = Get-Date
    do { $s = Evaluate $t.webSocketDebuggerUrl "c14state"; if ($s -eq $want) { break }; Start-Sleep -Milliseconds 300 } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "$s"
}
# One DevTools call on page `t`: the reply ({id, result} or {id, error}), or $null. (e18-lib's Evaluate is
# Runtime.evaluate only.)
function Cdp($t, [string]$method, [hashtable]$params) {
    $sock = [Net.WebSockets.ClientWebSocket]::new(); $none = [Threading.CancellationToken]::None
    try {
        if (-not $sock.ConnectAsync([Uri]$t.webSocketDebuggerUrl, $none).Wait(10000)) { return $null }
        $o = [Text.Encoding]::UTF8.GetBytes((@{ id = 1; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 4))
        if (-not $sock.SendAsync([ArraySegment[byte]]::new($o), [Net.WebSockets.WebSocketMessageType]::Text, $true, $none).Wait(10000)) { return $null }
        $buf = [byte[]]::new(65536); $got = 0
        do {
            $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf, $got, $buf.Length - $got), $none)
            if (-not $r.Wait(15000)) { return $null }
            $got += $r.Result.Count
        } until ($r.Result.EndOfMessage)
        [Text.Encoding]::UTF8.GetString($buf, 0, $got) | ConvertFrom-Json
    } catch { $null } finally { $sock.Dispose() }
}
# A Ctrl+click on link `id` of page `t`. DevTools' Input.dispatchMouseEvent is trusted input that goes through the
# renderer as a mouse's does: Blink reads Ctrl as a new background tab, and the browser adds it as a LINK, which
# takes the page in front as its opener (tab_strip_model.cc AddWebContents, inherit_opener) -- a real Ctrl+click's
# road, with no window needed in front. A script's window.open or a synthetic click is not that road.
function CtrlClick($t, [string]$id) {
    $xy = @(Evaluate $t.webSocketDebuggerUrl "(() => { const r = document.getElementById('$id').getBoundingClientRect(); return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]; })()")
    if ($xy.Count -ne 2) { return "no link '$id' ($xy)" }
    foreach ($e in @(@{ type = "mousePressed"; buttons = 1 }, @{ type = "mouseReleased"; buttons = 0 })) {
        $r = Cdp $t "Input.dispatchMouseEvent" @{ type = $e.type; x = $xy[0]; y = $xy[1]; button = "left"; buttons = $e.buttons; clickCount = 1; modifiers = 2 }
        if (-not $r -or $r.error) { return "$($e.type) refused ($(if ($r) { $r.error.message } else { 'no reply' }))" }
    }
    "Ctrl+clicked at $($xy[0]),$($xy[1])"
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
$with = foreach ($s in @("the tab behind its badge", "last used tab -> index")) {
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -eq 0) { "WITH" } else { "WITHOUT" }
}
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $($with[0]) patch 72, $($with[1]) patch 73"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real keys ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C14Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath "$prof\DevToolsActivePort", $log -EA SilentlyContinue
$script:server = Serve "$here\c14-pages"
if (-not $script:server) { Abort "the local pages were not served" }
# Camera + mic allowed for the pages in the copy (e18-lib: why not --use-fake-ui-for-media-stream).
if (-not (AllowCameraAt "$prof\Default\Preferences" $script:pagePort)) { Abort "could not allow the camera for the pages in the copy" }
try {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--helium-workspaces-log-addresses", "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check",
                                                               "--autoplay-policy=no-user-gesture-required", "--use-fake-device-for-media-stream")).Id
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port), pages on port $($script:pagePort), log $log"

    # C14a: a tone in Work, the window on Canary.
    Go "%+2" $work
    $tone = NewTab "c14-tone"
    $st = State $tone "running"
    # A second page in front in Work: the tab left there last, where a plain switch back would land (C14b).
    $null = NewTab "c14-other"
    $c = Count (Badge 2)
    Go "%+3" $canary
    $ok = WaitLog (Badge 2) ($c + 1) 15
    Start-Sleep (1 * $slow)
    $d = @(ChipDesc $main "Work")
    $desc = $d -join " | "
    Verdict "C14a a tone in Work (its AudioContext: $st), the window on Canary: 'rail badge -> 2' (logged: $ok); a chip still named 'Work' (shown: $($d.Count)) describes it ('$desc')" ($ok -and $d.Count -ge 1 -and $desc -like "*c14 tone*")

    # C14b: the badged chip goes to the tab behind its badge.
    $cp = Count $pressed; $ca = Count $active
    $r = Press $main "Work" 0x2B
    $ok = WaitLog $pressed ($cp + 1) 10
    $sw = (WaitLog $active ($ca + 1) 10) -and (ActiveWs) -eq $work
    $v = Visible
    Verdict "C14b the chip 'Work' pressed ($r): 'the tab behind its badge' (logged: $ok), the window in Work ($sw) on the tone, not c14-other (shown: $v)" ($ok -and $sw -and $v -eq "c14-tone")

    # C14c: the badge again from Canary, then the tone's tab closed.
    $c = Count (Badge 2)
    Go "%+3" $canary
    $back = WaitLog (Badge 2) ($c + 1) 15
    $c = Count (Badge "none")
    CloseTarget $tone
    $ok = WaitLog (Badge "none") ($c + 1) 10
    Verdict "C14c from Canary again the badge is back (-> 2: $back); the tone's tab closed (open: $(Has 'c14-tone')): 'rail badge -> none' (logged: $ok)" ($back -and $ok -and (Has "c14-tone") -eq 0)

    # C14d: the fake camera and microphone in Work.
    Go "%+2" $work
    $cam = NewTab "c14-cam"
    $st = State $cam "capturing"
    $rec = Badge "0|12|13"
    $c = Count $rec
    Go "%+3" $canary
    $ok = WaitLog $rec ($c + 1) 15
    $g = Grp $rec
    Verdict "C14d a page with the fake camera and microphone in Work ($st), the window on Canary: a recording badge (logged: $ok$(if ($g.Count) { ", -> $($g[1])" }); 0 is kMediaRecording)" $ok
    CloseTarget $cam

    # C34a: Ctrl+W lands on the tab left last, not Chromium's neighbour. p2 is the strip's last and has no opener, so
    # Chromium's rule shows its left neighbour p1; p3, the tab left last, sits two to its left.
    Go "%+2" $work
    $p3 = NewTab "c34-p3"; $p1 = NewTab "c34-p1"; $p2 = NewTab "c34-p2"
    Show $p1; Show $p3; Show $p2
    $v0 = Visible
    $c = Count $last
    $k = Keys "^w"
    $ok = WaitLog $last ($c + 1) 10
    Start-Sleep (1 * $slow)
    $g = Grp $last; $v = Visible
    Verdict "C34a p3 p1 p2 shown p1, p3, p2 (in front: $v0); Ctrl+W ($k) on p2 (open: $(Has 'c34-p2')): p3 in front, Chromium's rule p1 (shown: $v); 'last used tab' logged: $ok$(if ($g.Count) { ", index $($g[1])" })" ($v0 -eq "c34-p2" -and $ok -and $v -eq "c34-p3" -and (Has "c34-p2") -eq 0)

    # C34b: a link opened in the background, shown and closed, returns to the page that opened it -- Chromium's rule
    # prefers a tab the same opener opened (its sibling l2, tab_strip_model.cc "Second preference").
    $lk = NewTab "c34-links"
    $r = "l1 $(CtrlClick $lk 'l1'); l2 $(CtrlClick $lk 'l2')"
    $t0 = Get-Date
    while (((Has "c34-l1") -lt 1 -or (Has "c34-l2") -lt 1) -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    $v0 = Visible
    $l1 = @(Targets | Where-Object { (Short $_.url) -eq "c34-l1" }) | Select-Object -First 1
    if ($l1) {
        Show $l1
        $c = Count $last; $k = Keys "^w"
        $ok = WaitLog $last ($c + 1) 10
    } else { $k = "no 'c34 l1' to show"; $ok = $false }
    Start-Sleep (1 * $slow)
    $v = Visible
    Verdict "C34b the links page Ctrl+clicked its two links ($r; open: $(Has 'c34-l1'), $(Has 'c34-l2'); in front then: $v0); l1 shown, Ctrl+W ($k): the links page in front, Chromium's rule l2 (shown: $v); 'last used tab' logged: $ok" ($v0 -eq "c34-links" -and $ok -and $v -eq "c34-links" -and (Has "c34-l1") -eq 0)

    # C34c (D14): a close lands on the pinned page left last and stays -- E15c's repair, still there for Chromium's
    # own picks, would move to the list's neighbour.
    $c = Count "pins: opened item 'a1'"
    $r = Press $main "Example A"
    $opened = WaitLog "pins: opened item 'a1'" ($c + 1) 10
    Start-Sleep (2 * $slow)
    Show $p1
    $c = Count $last; $k = Keys "^w"
    $ok = WaitLog $last ($c + 1) 10
    Start-Sleep (2 * $slow)
    $v = Visible
    Verdict "C34c Example A's page opened ($r; logged: $opened), p1 shown, Ctrl+W ($k) on p1 (open: $(Has 'c34-p1')): 'last used tab' logged: $ok, Example A's page in front 2 s later (shown: $v)" ($opened -and $ok -and $v -like "*example.com*" -and (Has "c34-p1") -eq 0)

    # C34d (D15, D17, review C14-1 / C34-1): Ctrl+W on an anchored tab puts it to sleep and lands on the tab left
    # last; the sleeping tab's stale sound lights no chip; the next close does not wake it.
    $q = NewTab "c34-q"
    $at = NewTab "c34-anchor-tone"
    $st = State $at "running"
    $row = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "c34 anchor tone*" }) | Select-Object -First 1
    $m = if ($row) { [E18Input]::Click($main, $row.l + [int]($row.w / 3), $row.t + [int]($row.h / 2), $true) } else { "no Today tab 'c34 anchor tone' drawn" }
    Start-Sleep -Milliseconds (800 * $slow)
    $m += "; $(OtherPress $main '^Anchor$')"
    Start-Sleep (1 * $slow)
    $m += "; $(OtherPress $main '^Anchor to this page(?! instead)')"
    $anch = WaitLog "anchor at index \d+ -> '[^']*c34-anchor-tone'" 1 10
    Show $q; Show $at
    $hre = "hibernated anchored tab at index \d+ -> '[^']*c34-anchor-tone'"
    $c = Count $last; $ch = Count $hre
    $k = Keys "^w"
    $hib = WaitLog $hre ($ch + 1) 10
    $ok = WaitLog $last ($c + 1) 10
    Start-Sleep (1 * $slow)
    $v = Visible
    $c2 = Count (Badge 2)
    Go "%+3" $canary
    Start-Sleep (3 * $slow)
    $stale = (Count (Badge 2)) - $c2
    Go "%+2" $work
    $v1 = Visible
    $c = Count $last; $k2 = Keys "^w"
    $ok2 = WaitLog $last ($c + 1) 10
    Start-Sleep (2 * $slow)
    $v2 = Visible
    Verdict "C34d the tone anchored ($st; $m; logged: $anch), q then the tone shown, Ctrl+W ($k): hibernated ($hib), 'last used tab' ($ok), q in front (shown: $v); from Canary $stale stale 'rail badge -> 2'; back in Work on q ($v1), Ctrl+W ($k2; logged: $ok2) does not wake the anchored tab (shown: $v2)" ($st -eq "running" -and $anch -and $hib -and $ok -and $v -eq "c34-q" -and $stale -eq 0 -and $v1 -eq "c34-q" -and $ok2 -and $v2 -ne "none" -and $v2 -notlike "*anchor-tone*")

    # C34e (A4): Clear Today closes the active tab LAST, so one pick. l2 sits after the links page in the strip and is
    # left last: closed in strip order, the links page would land on l2, which would then close and pick again.
    $l2 = @(Targets | Where-Object { (Short $_.url) -eq "c34-l2" }) | Select-Object -First 1
    if ($l2) { Show $l2 }
    Show $lk
    $v0 = Visible
    $c = Count $last; $cc = Count "\[workspaces\] shortcut: clear Today"
    $k = Keys "%+k"
    $cleared = WaitLog "\[workspaces\] shortcut: clear Today" ($cc + 1) 10
    Start-Sleep (3 * $slow)
    $n = (Count $last) - $c
    $alive = [bool](Get-Process -Id $script:bpid -EA SilentlyContinue)
    $v = Visible
    $left = @(Targets | Where-Object { (Short $_.url) -like "c34-*" }).Count
    Verdict "C34e l2 then the links page shown (in front: $v0), Shift+Alt+K ($k; Clear Today logged: $cleared; c34 pages left open: $left): $n 'last used tab' line(s), the browser alive: $alive, Example A's page in front (shown: $v)" ([bool]$l2 -and $v0 -eq "c34-links" -and $cleared -and $n -eq 1 -and $alive -and $v -like "*example.com*")

    # C34f (D1): a favorite left last is a landing -- it is drawn in every workspace.
    $fav = NewTab "c34-fav"
    $row = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "c34 fav*" }) | Select-Object -First 1
    $m = if ($row) { [E18Input]::Click($main, $row.l + [int]($row.w / 3), $row.t + [int]($row.h / 2), $true) } else { "no Today tab 'c34 fav' drawn" }
    Start-Sleep -Milliseconds (800 * $slow)
    $m += "; $(OtherPress $main '^Add to Favorites')"
    Start-Sleep (1 * $slow)
    $pinned = [bool]@(Nodes $main | Where-Object { $_.role -eq 0x25 -and $_.name -like "c34 fav*Pinned*" }).Count
    $null = NewTab "c34-s"; Show $fav; $null = NewTab "c34-r"
    $c = Count $last; $k = Keys "^w"
    $ok = WaitLog $last ($c + 1) 10
    Start-Sleep (1 * $slow)
    $v = Visible
    Verdict "C34f 'c34 fav' pinned ($m; a favorite: $pinned), s opened, the favorite shown, r opened; Ctrl+W ($k) on r (open: $(Has 'c34-r')): the favorite in front, Chromium's rule s (shown: $v); 'last used tab' logged: $ok" ($pinned -and $ok -and $v -eq "c34-fav" -and (Has "c34-r") -eq 0)

    # C34g (D1): a page folded away in a collapsed group is never landed on, even when it was left last.
    $null = NewTab "c34-g"
    $row = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "c34 g*" }) | Select-Object -First 1
    $m = if ($row) { [E18Input]::Click($main, $row.l + [int]($row.w / 3), $row.t + [int]($row.h / 2), $true) } else { "no Today tab 'c34 g' drawn" }
    Start-Sleep -Milliseconds (800 * $slow)
    $m += "; $(OtherPress $main '^Add tab to new group$')"
    # The new group's name bubble, closed (check-e14d3-auto's way).
    Start-Sleep (2 * $slow); $null = Keys "{ESC}"
    $null = NewTab "c34-t"
    # The vertical strip names an unnamed group's header "unnamed group - 1 tab, <bullet>  c34 g - Expanded" (read
    # off MSAA, role 0x3C); a LEFT click on it folds the group.
    $hdr = @(Nodes $main | Where-Object { $_.shown -and $_.name -match '^ ?unnamed group - .*c34 g' }) | Select-Object -First 1
    $f = if ($hdr) { [E18Input]::Click($main, $hdr.l + [int]($hdr.w / 2), $hdr.t + [int]($hdr.h / 2), $false) } else { "no header 'unnamed group - ... c34 g'" }
    Start-Sleep (1 * $slow)
    $folded = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "c34 g*" }).Count -eq 0
    $c = Count $last; $k = Keys "^w"
    $ok = WaitLog $last ($c + 1) 10
    Start-Sleep (1 * $slow)
    $v = Visible
    $still = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "c34 g*" }).Count -eq 0
    Verdict "C34g 'c34 g' in a new group ($m), t opened, the group folded ($f; folded: $folded); Ctrl+W ($k) on t: not the grouped page (shown: $v), the group still folded ($still); 'last used tab' logged: $ok" ($folded -and $ok -and $v -ne "c34-g" -and $v -ne "none" -and $still)
} catch {
    Say "ERROR: $_"; $script:failed++
} finally {
    if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    }
    if ($script:server) { Stop-Process -Id $script:server.Id -EA SilentlyContinue }
}
# Case-sensitive, as LOCAL.md grades: a Dcheck exit can dump the histogram
# "Commerce.PriceTracking.DanglingUserSubscriptionCountAtStartup", no crash (LOCAL.md 3968, 7372).
$markers = if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling").Count } else { 0 }
Verdict "Z crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
