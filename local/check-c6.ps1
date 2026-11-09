param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c6", [double]$IdleMinutes = 15,
      [string[]]$Rows = @())
# C6 (patch 90 90-little-window.patch, <local-path>\Helium-workspace\c21-progress.md; the design is "7. GUI check" in the C6
# section of <local-path>\Helium-workspace\c21-understand.md): a link from ANOTHER APP opens in a little window of its own while
# the browser runs; "Open in main window" (its button, Shift+Alt+O) moves the SAME page to the top of Today of the
# workspace on screen; closing the little window throws the page away; the setting "Open links from other apps in a
# small window" (helium.workspaces.little_window) turns it off.
# An outside link is simulated as Windows sends one (the installer's ProgID): a second
#   chrome.exe --user-data-dir=<profile> --single-argument <url>
# with --single-argument LAST (everything after it is the one argument). It forwards its line to the running test
# browser and exits; that browser has no --enable-automation (it drops a forwarded line, chrome_browser_main.cc).
# On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin), the sidebar 280 wide, the main
# window placed topmost over the work area (as a maximized daily window: the little one is then smaller both ways);
# each little window is made topmost where it opened once its rect is read. Shift+Alt+O, Ctrl+Shift+T and the clicks
# that bring a window in front are REAL input (SendKeys / SendInput, guarded): it starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE.
#   pwsh -NoProfile -File local\check-c6.ps1 [-Build Dcheck] [-IdleMinutes 0] [-Rows S1,M1]
# Every row starts from the MAIN window with Work on screen and no little window open (one left over is closed first,
# so a slip does not cascade) and says so in its verdict. Launch 1:
#   setup  Work shown; E18 c6m opened (DevTools); 1 window
#   S1     an outside link to c6s: "little window: opened window <id> at <x>,<y> <w>x<h>"; windows 1 -> 2; c6s loads
#          in the new window, not as a main tab; its OUTER rect smaller than the main window's both ways; the logged
#          rect = LittleWindowBounds of the primary work area in DIPs (55% x 70%, held in 480-1100 x 400-900, never
#          larger than the area, centred) +-2 DIP; the OUTER rect = the logged one times the scale +-8 px
#   N1     an own launch WITHOUT --single-argument to c6n: no opened line, still 1 window, the insert stamped Work, c6n
#          first in Work's Today (as before the patch)
#   M1     c6a in a little window, window.__c6 = 6 set in its page; its "Open in main window" button (drawn in the
#          right half of the little window) pressed through MSAA: "little window: moved into window <id> at index <n>"
#          (not the little window's id), "tab inserted at index <n> -> workspace '<Work>' (active '<Work>')", the little
#          window gone and the main one kept (1 window), c6a FIRST in Work's Today, window.__c6 still 6 (no reload)
#   K1     the same for c6b (marker 7) by Shift+Alt+O in the little window, brought in front by a click on its page
#   K2     the same for c6k (marker 8) by Shift+Alt+O sent through DevTools (Input.dispatchKeyEvent enters where a real
#          key does: PreHandleKeyboardEvent, the page, the window's accelerators): K1 FAIL + K2 PASS = Windows did not
#          deliver the key; both FAIL = the browser's own path
#   X1     a decoy c6x opened in main and closed (DevTools: archived, Recently Closed's newest); c6c in a little window,
#          closed (WM_CLOSE, what its X sends): 1 window, c6c gone from DevTools, no archive entry for c6c while c6x has
#          one; Ctrl+Shift+T in main brings back c6x and no c6c (the little window's close made no Recently Closed entry)
#   O1     the setting off through chrome.settingsPrivate (Settings opened on the DevTools port): setPref true, getPref
#          false; an outside link to c6d: no opened line, 1 window, the insert stamped Work, c6d first in Work's Today;
#          then back on (setPref true, getPref true) and the Settings tab closed
#   R1     c6e in a little window; the MAIN window's X first (the browser runs on in the little one; the session keeps
#          main as a pending close, and its tabs are archived too: D15's accepted duplicate), then the little window's;
#          launch 2 (--restore-last-session): 1 window, every E18 c6* tab of Work's Today before the quit back (the
#          moved c6a / c6b too: the TabRestored after the move), c6e nowhere (a little window is not restored)
#   Z      0 crash markers in both logs (case-sensitive, DanglingPtr too)
# A pass needs all 9 verdicts ($total below). The work area is the PRIMARY monitor's (GetDisplayForNewWindows' fallback);
# the main window sits there. If a run tests nothing: the window in front and WindowFromPoint first (a Snipping Tool
# overlay passes the gate, LOCAL.md 90).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows S1,M1` passes ONE string "S1,M1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = "$ws\helium-windows\build\src\out\$Build"
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$archive = "$prof\Default\Workspace Archive"
$logs    = @(1..2 | ForEach-Object { if ($Build -eq "Dcheck") { "$ws\$Tag-dcheck-exercise$_.log" } else { "$ws\$Tag-run$_.log" } })
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = 10
$pref    = "helium.workspaces.little_window"
# The patch's lines, graded case-sensitively: 90-little-window.patch 413-415 (MaybeOpenLittleWindow) and 466-467
# (MoveToMainWindow), workspace_little_window.cc; workspace_service.cc 2261-2263 (StampInsertedTab, 36-arc-import.patch
# 193-195) and 418 (03-commands.patch 190). startup_browser_creator.cc's hook logs nothing: a link it lets through
# shows as no opened line and no second window.
$opened   = "\[workspaces\] little window: opened window (\d+) at (-?\d+),(-?\d+) (\d+)x(\d+)"
$moved    = "\[workspaces\] little window: moved into window (\d+) at index (\d+)"
$inserted = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"
$active   = "\[workspaces\] active workspace -> '([^']*)'"

$script:passed = 0; $script:failed = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Grp([string]$re) { $l = @(Lines $re); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA (msaa-press.ps1), as check-c33's ---------------------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A restored page never loaded since is named by its address ("127.0.0.1:<port>/c6a.html"): "E18 c6a" matches that too.
function TabIn($nodes, [string]$title) {
    $page = if ($title -like "E18 *") { "*/$($title.Substring(4)).html" } else { $null }
    @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq $title -or $_.name.StartsWith("$title - ") -or ($page -and $_.name -like $page)) }) | Select-Object -First 1
}
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
function FirstToday { $t = @(Today (Nodes $script:main)); if ($t.Count) { $t[0].name } else { "(none)" } }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function Go([string]$name, [string]$guid) {
    if (NodeIn (Nodes $script:main) $name 0x14) { return $true }
    $c = Count $active
    $null = Press $script:main $name 0x2B
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Grp $active)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}
function Row([string]$row, [scriptblock]$body) {
    # -Rows S1,M1: only those rows (and the setup); the RESULT then counts fewer verdicts.
    if ($Rows.Count -and $row -ne "setup" -and $Rows -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the windows -----------------------------------------------------------------------------------------------------
# What e18-lib's E18Input lacks: the window in front, a window's OUTER rect, the primary monitor's work area -- all in
# physical pixels (per-monitor aware), as E18Input's Place and Client.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class C6Win {
  [StructLayout(LayoutKind.Sequential)] struct R { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] struct P { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] struct MI { public int size; public R mon, work; public uint flags; }
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(P p, uint flags);
  [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MI i);
  public static IntPtr Front() { return GetForegroundWindow(); }
  // Left, top, width, height of the whole window, its frame included.
  public static int[] Rect(IntPtr h) { SetThreadDpiAwarenessContext(new IntPtr(-4)); R r; GetWindowRect(h, out r); return new int[] { r.l, r.t, r.r - r.l, r.b - r.t }; }
  // The primary monitor's (MONITOR_DEFAULTTOPRIMARY at 0,0) screen less the taskbar.
  public static int[] Work() {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    P p; p.x = 0; p.y = 0; MI i = new MI(); i.size = Marshal.SizeOf(typeof(MI));
    GetMonitorInfo(MonitorFromPoint(p, 1), ref i);
    return new int[] { i.work.l, i.work.t, i.work.r - i.work.l, i.work.b - i.work.t };
  }
}
'@
# LittleWindowBounds (workspace_prefs.cc, 90-little-window.patch 147-169) of a work area in DIPs, its integer maths:
# 55% x 70% held in 480-1100 x 400-900, never larger than the area, centred. Left, top, width, height.
function Bounds([int]$x, [int]$y, [int]$w, [int]$h) {
    $bw = [Math]::Min([Math]::Clamp([int][Math]::Floor($w * 55 / 100), 480, 1100), $w)
    $bh = [Math]::Min([Math]::Clamp([int][Math]::Floor($h * 70 / 100), 400, 900), $h)
    @(($x + [int][Math]::Floor(($w - $bw) / 2)), ($y + [int][Math]::Floor(($h - $bh) / 2)), $bw, $bh)
}
# Two left, top, width, height boxes within `tol` of each other on all four.
function Near([double[]]$a, [double[]]$b, [double]$tol) { $a.Count -eq 4 -and $b.Count -eq 4 -and -not @(0..3 | Where-Object { [Math]::Abs($a[$_] - $b[$_]) -gt $tol }).Count }
# The browser's windows other than the main one: the little windows.
function Littles { @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main }) }
# Keys through SendKeys ("%+o" is Shift+Alt+O, "^+t" Ctrl+Shift+T) to browser window `h`, in front first: Windows lets
# no program pull itself in front of the window used last (the Claude window, LOCAL.md 90), so one guarded click on the
# page's blank bottom middle when it is not; and a dialog of the browser's own process passes a pid guard (LOCAL.md
# 88), so the window itself is waited for (check-c35's Keys).
function Keys([IntPtr]$h, [string]$k) {
    $t0 = Get-Date
    while ([C6Win]::Front() -ne $h -and ((Get-Date) - $t0).TotalSeconds -lt 3 * $slow) { Start-Sleep -Milliseconds 200 }
    $c = ""
    if ([C6Win]::Front() -ne $h) {
        $b = [E18Input]::Client($h)
        $c = " (a click: $([E18Input]::Click($h, $b[0] + [int]($b[2] / 2), $b[1] + $b[3] - 40, $false)))"
        $t0 = Get-Date
        while ([C6Win]::Front() -ne $h -and ((Get-Date) - $t0).TotalSeconds -lt 3 * $slow) { Start-Sleep -Milliseconds 200 }
        if ([C6Win]::Front() -ne $h) { return "not sent: that window is not in front$c" }
    }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent$c"
}
# Every row starts here: no little window left over (closed), Work on screen in the main window, 1 window.
function Ready {
    foreach ($h in @(Littles)) { [E18Input]::CloseWindow($h) }
    $t0 = Get-Date
    while (@(Littles).Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    $w = Go "Work" $work
    $n = @([E18Input]::Windows([uint32]$script:bpid)).Count
    [pscustomobject]@{ ok = $w -and $n -eq 1; said = "from the main window: Work shown $w, $n window(s)" }
}

# ---- the pages, DevTools, the archive file ---------------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url "$name.html")))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
}
# The parentheses unroll the JSON array: piped bare, Invoke-RestMethod hands it on as ONE object and every lookup
# below returned all targets at once (the first run: ids glued together, a WebSocket URL the browser refused).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 -Uri "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
function Target([string]$name) { @(Targets | Where-Object { $_.url -like "*/$name.html" }) | Select-Object -First 1 }
function CloseTarget($t) { if (-not $t) { return "no target" }; try { "$(Invoke-RestMethod -TimeoutSec 10 -Uri "$(Base)/close/$($t.id)")" } catch { "error: $_" } }
# Page `name`'s DevTools target once it has loaded (its title "E18 <name>"), else $null.
function Loaded([string]$name) {
    $t0 = Get-Date
    do {
        $t = Target $name
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -eq "E18 $name") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
# One Input.dispatchKeyEvent of Shift+Alt+O (modifiers Alt 1 + Shift 8) to page target `wsUrl`.
function CdpKey([string]$wsUrl, [string]$type) {
    $sock = [Net.WebSockets.ClientWebSocket]::new(); $none = [Threading.CancellationToken]::None
    try {
        if (-not $sock.ConnectAsync([Uri]$wsUrl, $none).Wait(10000)) { return "no connection" }
        $o = [Text.Encoding]::UTF8.GetBytes((@{ id = 1; method = "Input.dispatchKeyEvent"; params = @{ type = $type; modifiers = 9; windowsVirtualKeyCode = 79; nativeVirtualKeyCode = 79; code = "KeyO"; key = "O" } } | ConvertTo-Json -Compress -Depth 4))
        if (-not $sock.SendAsync([ArraySegment[byte]]::new($o), [Net.WebSockets.WebSocketMessageType]::Text, $true, $none).Wait(10000)) { return "not sent" }
        $buf = [byte[]]::new(65536); $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf), $none)
        if ($r.Wait(5000)) { "sent: $([Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count))" } else { "sent (no reply)" }
    } catch { "error: $_" } finally { $sock.Dispose() }
}
# The archive file's entries as saved (written 2.5 s after a change).
function Entries { Start-Sleep (4 * $slow); try { @((Get-Content -Raw -Encoding UTF8 -LiteralPath $archive | ConvertFrom-Json).entries) } catch { @() } }

# A second chrome.exe on the test profile: it forwards its line to the running browser and exits. Without -Own, as
# Windows hands over a link from another app: --single-argument LAST. -Own: no switch, as a typed command (and every
# other check script) does.
function Outside([string]$name, [switch]$Own) {
    $a = @("--user-data-dir=$prof")
    if (-not $Own) { $a += "--single-argument" }
    $a += Url "$name.html"
    $p = Start-Process $exe -PassThru -ArgumentList $a
    # Waited for: while it runs, msaa-press.ps1 finds two processes on the profile.
    "launcher $($p.Id) $(if ($p.WaitForExit(15000 * $slow)) { 'exited' } else { 'STILL RUNNING' })"
}
# An outside link to page `name`: the opened line's groups (whole, id, x, y, w, h), the little window that appeared, its
# page loaded, its OUTER rect read before anything moves it -- then it is made topmost where it is, so a guarded click
# reaches it over the topmost main window.
function Little([string]$name) {
    $c = Count $opened
    $said = Outside $name
    $logged = WaitLog $opened ($c + 1) 15
    $h = [IntPtr]::Zero; $t0 = Get-Date
    while ($h -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { $found = @(Littles); if ($found.Count) { $h = $found[0] } else { Start-Sleep -Milliseconds 300 } }
    $page = Loaded $name
    $rect = @()
    if ($h -ne [IntPtr]::Zero) { $rect = [C6Win]::Rect($h); [E18Input]::Place($h, $rect[0], $rect[1], $rect[2], $rect[3]) }
    [pscustomobject]@{ name = $name; said = $said; line = @(Nth $opened $c); win = $h; page = $page; rect = $rect
                       ok = $logged -and $h -ne [IntPtr]::Zero -and [bool]$page -and @(Littles).Count -eq 1 }
}
# After "Open in main window" on little window `lw` whose page carries marker `mark` (the counts taken before): the
# moved line and the insert it made in Work, the little window gone and the main one kept, the page first in Work's
# Today, and the SAME page (the marker answers: no reload).
function MoveGrade($lw, [int]$mark, [int]$cm, [int]$ci) {
    $ok = (WaitLog $moved ($cm + 1) 10) -and (WaitLog $inserted ($ci + 1) 5)
    $mv = @(Nth $moved $cm); $in = @(Nth $inserted $ci)
    $t0 = Get-Date
    while (@(Littles).Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep (1 * $slow)
    $wins = @([E18Input]::Windows([uint32]$script:bpid))
    $first = FirstToday
    $t = Target $lw.name
    $kept = if ($t) { Evaluate $t.webSocketDebuggerUrl "window.__c6" } else { "no target" }
    $same = [bool]($t -and $lw.page -and $t.id -eq $lw.page.id)
    [pscustomobject]@{
        said = "$(if ($mv.Count) { "'$($mv[0])'" } else { 'no moved line' }) (the little window: $(if ($lw.line.Count) { $lw.line[1] } else { '-' })); $(if ($in.Count) { "'$($in[0])'" } else { 'no insert line' }) (want index $(if ($mv.Count) { $mv[2] } else { '-' }), Work twice); windows $($wins.Count), the main one kept $($wins -contains $script:main); first in Work's Today '$first' (want E18 $($lw.name)); window.__c6 $kept (want $mark), the same DevTools target $same"
        ok   = [bool]($ok -and $mv.Count -and $lw.line.Count -and $mv[1] -ne $lw.line[1] -and $in.Count -and $in[1] -eq $mv[2] -and $in[2] -eq $work -and $in[3] -eq $work -and $wins.Count -eq 1 -and $wins -contains $script:main -and $first -eq "E18 $($lw.name)" -and "$kept" -eq "$mark")
    }
}

function Launch([string[]]$extra) {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check", "--restore-last-session") + $extra
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
    [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid) $($extra -join ' '), DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log)"
}
function Quit {
    if (-not (Running)) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Running)
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' })$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

# ==== the run =====================================================================================================
# The one runnable self-check of Bounds: LittleWindowBounds' first unit-test case (workspace_prefs_unittest.cc).
if ("$(Bounds 0 0 1920 1040)" -ne "432 156 1056 728") { Abort "Bounds gives $(Bounds 0 0 1920 1040), not LittleWindowBounds' 432 156 1056 728" }
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "little window: opened window "
Say "build: $Build\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 90"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
# The main window over the primary work area, 16 px in: as big as a maximized daily window, so the little one (at most
# 55% x 70% of that area) is smaller both ways.
$wa = [C6Win]::Work()
$script:box = @(($wa[0] + 16), ($wa[1] + 16), ($wa[2] - 32), ($wa[3] - 32))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath (@($archive) + $logs) -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$script:srv = ServePages $pages @("c6m", "c6s", "c6n", "c6a", "c6b", "c6k", "c6x", "c6c", "c6d", "c6e")
if (-not $script:srv.ok) { Abort "the local pages were not served" }

try {
    # ---- launch 1 --------------------------------------------------------------------------------------------------
    $script:log = $logs[0]
    Launch @()
    Row "setup" {
        $w = Go "Work" $work
        NewTab "c6m"
        $n = @([E18Input]::Windows([uint32]$script:bpid)).Count
        $t = @(Today (Nodes $script:main))
        Verdict "setup: Work shown $w; windows $n (want 1); Work's Today $(Names $t)" ($w -and $n -eq 1 -and (TabIn $t "E18 c6m"))
    }
    Row "S1" {
        $r = Ready
        $lw = Little "c6s"
        $n = @([E18Input]::Windows([uint32]$script:bpid)).Count
        $inMain = [bool](TabIn (Nodes $script:main) "E18 c6s")
        $m = [C6Win]::Rect($script:main)
        # The scale of the primary monitor, where the main window sits; its work area in DIPs as Chromium encloses it.
        $sc = [E18Input]::Dpi($script:main) / 96
        $wk = [C6Win]::Work()
        $wx = [int][Math]::Floor($wk[0] / $sc); $wy = [int][Math]::Floor($wk[1] / $sc)
        $want = Bounds $wx $wy ([int][Math]::Ceiling(($wk[0] + $wk[2]) / $sc) - $wx) ([int][Math]::Ceiling(($wk[1] + $wk[3]) / $sc) - $wy)
        $got = if ($lw.line.Count) { @($lw.line[2..5] | ForEach-Object { [int]$_ }) } else { @() }
        $px = @($got | ForEach-Object { $_ * $sc })
        $small = $lw.rect.Count -eq 4 -and $lw.rect[2] -lt $m[2] -and $lw.rect[3] -lt $m[3]
        Verdict "S1 an outside link to c6s ($($r.said); $($lw.said)): $(if ($lw.line.Count) { "'$($lw.line[0])'" } else { 'no opened line' }); windows $n (want 2); c6s loaded in it $([bool]$lw.page), a main tab $inMain (want False); its outer rect $($lw.rect -join ',') px, the main window's $($m -join ',') (smaller both ways $small); logged $($got -join ',') DIP vs LittleWindowBounds of the work area $($wk -join ',') px at scale $sc = $($want -join ',') (+-2); outer vs logged x scale $(@($px | ForEach-Object { [Math]::Round($_) }) -join ',') (+-8 px)" ($r.ok -and $lw.ok -and $n -eq 2 -and -not $inMain -and $small -and (Near $got $want 2) -and (Near $lw.rect $px 8))
    }
    Row "N1" {
        $r = Ready
        $co = Count $opened; $ci = Count $inserted
        $said = Outside "c6n" -Own
        $page = Loaded "c6n"
        $null = WaitLog $inserted ($ci + 1) 5
        Start-Sleep (2 * $slow)
        $in = @(Nth $inserted $ci); $n = @([E18Input]::Windows([uint32]$script:bpid)).Count; $first = FirstToday; $lines = (Count $opened) - $co
        Verdict "N1 an own launch to c6n, no --single-argument ($($r.said); $said): loaded $([bool]$page); opened lines +$lines (want 0); windows $n (want 1); $(if ($in.Count) { "'$($in[0])'" } else { 'no insert line' }) (want Work); first in Work's Today '$first' (want E18 c6n)" ($r.ok -and $page -and $lines -eq 0 -and $n -eq 1 -and $in.Count -and $in[2] -eq $work -and $first -eq "E18 c6n")
    }
    Row "M1" {
        $r = Ready
        $lw = Little "c6a"
        $mark = if ($lw.page) { Evaluate $lw.page.webSocketDebuggerUrl "window.__c6 = 6; 6" }
        $cm = Count $moved; $ci = Count $inserted
        $b = @(Nodes $lw.win | Where-Object { $_.shown -and $_.name -eq "Open in main window" }) | Select-Object -First 1
        $cl = [E18Input]::Client($lw.win)
        $right = [bool]($b -and ($b.l + $b.w / 2) -gt ($cl[0] + $cl[2] / 2))
        $p = "no 'Open in main window' button drawn"
        if ($b) {
            $p = Press $lw.win $b.name $b.role
            if ($p -notmatch '^MSAA: pressed') { $p += "; $([E18Input]::Click($lw.win, $b.l + [int]($b.w / 2), $b.t + [int]($b.h / 2), $false))" }
        }
        $g = MoveGrade $lw 6 $cm $ci
        Verdict "M1 c6a in a little window ($($r.said); $($lw.said)), marker $mark; its button $(if ($b) { "role 0x$('{0:X}' -f $b.role) at $($b.l),$($b.t) $($b.w)x$($b.h), in the right half $right" } else { 'not drawn' }) ($p): $($g.said)" ($r.ok -and $lw.ok -and "$mark" -eq "6" -and $b -and $right -and $g.ok)
    }
    Row "K1" {
        $r = Ready
        $lw = Little "c6b"
        $mark = if ($lw.page) { Evaluate $lw.page.webSocketDebuggerUrl "window.__c6 = 7; 7" }
        $cm = Count $moved; $ci = Count $inserted
        $k = Keys $lw.win "%+o"
        $g = MoveGrade $lw 7 $cm $ci
        Verdict "K1 c6b in a little window ($($r.said); $($lw.said)), marker $mark; Shift+Alt+O in it ($k): $($g.said)" ($r.ok -and $lw.ok -and "$mark" -eq "7" -and $k -like "sent*" -and $g.ok)
    }
    Row "K2" {
        $r = Ready
        $lw = Little "c6k"
        $ws = if ($lw.page) { $lw.page.webSocketDebuggerUrl }
        $mark = if ($ws) { Evaluate $ws "window.__c6 = 8; 8" }
        $cm = Count $moved; $ci = Count $inserted
        $k = if ($ws) { "$(CdpKey $ws 'rawKeyDown') / $(CdpKey $ws 'keyUp')" } else { "no page" }
        $g = MoveGrade $lw 8 $cm $ci
        Verdict "K2 c6k in a little window ($($r.said); $($lw.said)), marker $mark; Shift+Alt+O through DevTools ($k): $($g.said)" ($r.ok -and $lw.ok -and "$mark" -eq "8" -and $k -like "sent*" -and $g.ok)
    }
    Row "X1" {
        $r = Ready
        # The decoy: closed through DevTools (CloseContents: archived, and Recently Closed's newest entry).
        NewTab "c6x"
        $x = CloseTarget (Target "c6x")
        $t0 = Get-Date
        while ((Target "c6x") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
        $lw = Little "c6c"
        if ($lw.win -ne [IntPtr]::Zero) { [E18Input]::CloseWindow($lw.win) }
        $t0 = Get-Date
        while (@(Littles).Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
        $n = @([E18Input]::Windows([uint32]$script:bpid)).Count
        $gone = -not (Target "c6c")
        $all = @(Entries)
        $ec = @($all | Where-Object { $_.url -like "*/c6c.html" }).Count
        $ex = @($all | Where-Object { $_.url -like "*/c6x.html" }).Count
        $k = Keys $script:main "^+t"
        $t0 = Get-Date
        while (-not (Target "c6x") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
        $back = [bool](Target "c6x"); $c6c = [bool](Target "c6c")
        Verdict "X1 decoy c6x closed ($x); c6c in a little window ($($r.said); $($lw.said)) closed: windows $n (want 1), c6c gone $gone; archive entries c6c $ec (want 0), c6x $ex (want 1+); Ctrl+Shift+T in main ($k): c6x back $back, c6c back $c6c (want False)" ($r.ok -and $lw.ok -and $n -eq 1 -and $gone -and $ec -eq 0 -and $ex -ge 1 -and $back -and -not $c6c)
    }
    Row "O1" {
        $r = Ready
        $s = OpenSettings $prof
        $dev = if ($s.ready) { $s.page.webSocketDebuggerUrl }
        $off = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('$pref', false, '')" }
        $was = if ($dev) { Evaluate $dev "chrome.settingsPrivate.getPref('$pref').then(p => p.value)" }
        $co = Count $opened; $ci = Count $inserted
        $said = Outside "c6d"
        $page = Loaded "c6d"
        $null = WaitLog $inserted ($ci + 1) 5
        Start-Sleep (2 * $slow)
        $in = @(Nth $inserted $ci); $n = @([E18Input]::Windows([uint32]$script:bpid)).Count; $first = FirstToday; $lines = (Count $opened) - $co
        $on = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('$pref', true, '')" }
        $now = if ($dev) { Evaluate $dev "chrome.settingsPrivate.getPref('$pref').then(p => p.value)" }
        $shut = CloseTarget $s.page
        Verdict "O1 the setting off ($($r.said); Settings $($s.note)): setPref $off (want True), getPref $was (want False); an outside link to c6d ($said): loaded $([bool]$page); opened lines +$lines (want 0); windows $n (want 1); $(if ($in.Count) { "'$($in[0])'" } else { 'no insert line' }) (want Work); first in Work's Today '$first' (want E18 c6d); back on: setPref $on, getPref $now (want True twice); Settings closed ($shut)" ($r.ok -and $off -eq $true -and $was -eq $false -and $page -and $lines -eq 0 -and $n -eq 1 -and $in.Count -and $in[2] -eq $work -and $first -eq "E18 c6d" -and $on -eq $true -and $now -eq $true)
    }
    Row "R1" {
        $r = Ready
        $lw = Little "c6e"
        # Work's E18 c6* tabs before the quit, their titles alone (a drawn name may carry " - ..." after it).
        $keep = @(Today (Nodes $script:main) | ForEach-Object { if ($_.name -match '^(E18 c6[a-z]+)') { $Matches[1] } } | Where-Object { $_ -ne "E18 c6e" })
        $was = $script:main
        [E18Input]::CloseWindow($was)
        $t0 = Get-Date
        while (@([E18Input]::Windows([uint32]$script:bpid)) -contains $was -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow) { Start-Sleep -Milliseconds 300 }
        $mainGone = -not (@([E18Input]::Windows([uint32]$script:bpid)) -contains $was)
        $alive = [bool](Running)
        $q1 = Quit
        # ---- launch 2: the restart ----------------------------------------------------------------------------------
        $script:log = $logs[1]
        Launch @()
        Start-Sleep (5 * $slow)
        $n = @([E18Input]::Windows([uint32]$script:bpid)).Count
        $went = Go "Work" $work
        $nodes = @(Nodes $script:main)
        $missing = @($keep | Where-Object { -not (TabIn $nodes $_) })
        $c6e = [bool](TabIn $nodes "E18 c6e") -or [bool](Target "c6e")
        Verdict "R1 c6e in a little window ($($r.said); $($lw.said)); the main window's X first: gone $mainGone, the browser running on $alive; then the little window's ($q1); relaunched: windows $n (want 1), Work shown $went; back $($keep.Count - $missing.Count) of $($keep.Count) ($($keep -join ', '))$(if ($missing.Count) { ", MISSING $($missing -join ', ')" }); c6e anywhere $c6e (want False)" ($r.ok -and $lw.ok -and $keep.Count -and $mainGone -and $alive -and $q1 -like "closed*" -and $n -eq 1 -and $went -and -not $missing.Count -and -not $c6e)
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($logs -join ', ') (the last quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
