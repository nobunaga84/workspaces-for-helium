param([double]$IdleMinutes = 15)
# Rehearsal of the OWNER's try (try-c4.ps1, C4) with no one at the keyboard -- try-c35-driver.ps1's pattern. The owner
# script runs UNMODIFIED in its own pwsh process; its answers are PIPED FROM A FILE (Get-Content -Wait <feed> | ...),
# its output goes through cmd straight into a file the driver watches. Every answer is 'y', appended only AFTER the
# driver has done that step in the browser: the owner script marks its log at each answer, so its own grading then
# proves each step end to end. What the driver could not confirm goes in the closing comment ("driver saw NOT OK: ...").
# How each owner action is done (check-c4.ps1's helpers, copied below):
#   a workspace's shortcut   its CHIP pressed through MSAA (the owner script waits for the switch in its log)
#   click / Ctrl+click       a guarded real click on the tab (C4Input.CtrlClick)
#   a drag                   a guarded real drag (C4Input.Hold / Release), held about a second where the step says so
#   right-click + item       a guarded real right-click; the item pressed through MSAA by its name
#   close the browser        WM_CLOSE to each window (what its X sends)
#   zen mode                 the cursor parked at the window's left edge (the sidebar slides out) before every read
# Real input moves the mouse: the run starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. Started by
# hand: add -IdleMinutes 0 and let go of the mouse. Run it in its own process, one line:
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c4-driver.ps1
# Output: try-c4-rehearsal-driver.txt (what the driver did and saw, then the owner script's RESULT line),
# try-c4-rehearsal.txt (the owner script's own output); the owner script's files are its usual c4-owner-*.
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$check   = "$here\try-c4.ps1"
$prof    = "$ws\testprofile-c4-owner"
$bin     = "$ws\helium-windows\build\src\out\Default"
$logs    = @("$ws\c4-owner-run.log", "$ws\c4-owner-run2.log")
$feed    = "$ws\try-c4-rehearsal-feed.txt"
$out     = "$ws\try-c4-rehearsal.txt"
$drv     = "$ws\try-c4-rehearsal-driver.txt"
$runner  = "$ws\try-c4-rehearsal-run.ps1"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
$active  = "\[workspaces\] active workspace -> '([^']*)'"
$lit     = "\[workspaces\] rail drop: over '$canary'"
$drop    = "\[workspaces\] rail drop: (\d+) tab\(s\) -> '$canary'"
$moved   = "\[workspaces\] moved (\d+) tab\(s\) -> workspace '$canary'"
$anyMove = "\[workspaces\] (rail drop: \d+ tab|moved \d+ tab)"
$stopRe  = 'STOPPED: |A test browser is already open|This build has no C4|could not be served|Could not seed'
$doneRe  = 'RESULT c4-owner'
$script:main = [IntPtr]::Zero; $script:bpid = 0; $script:log = $logs[0]; $script:zen = $false
$script:bad = [Collections.Generic.List[string]]::new()

function Note([string]$s) { $line = "$((Get-Date).ToString('HH:mm:ss')) $s"; Write-Host $line; Add-Content -LiteralPath $drv -Value $line -Encoding utf8 }
function Saw([string]$what, $ok) { Note ($(if ($ok) { "ok      " } else { "NOT OK  " }) + $what); if (-not $ok) { $script:bad.Add($what) } }

# ---- the owner script: answers from the feed, output into $out (try-c35-driver's) --------------------------------
function OutText { try { $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite'); try { [IO.StreamReader]::new($fs).ReadToEnd() } finally { $fs.Close() } } catch { "" } }
function Answer([string]$a, [string]$why) { Add-Content -LiteralPath $feed -Value $a -Encoding utf8; Note "ANSWER '$a' -- $why"; Start-Sleep 2 }
function StopOwner {
    Stop-Process -Id $child.Id -EA SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='cmd.exe'" | Where-Object { $_.CommandLine -like "*\try-c4.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
}
function Finish {
    if ($script:bpid) { foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) } }
    $t = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*") -and ((Get-Date) - $t).TotalSeconds -lt 45) { Start-Sleep 1 }
    Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*" | Stop-Process -Force -EA SilentlyContinue
    StopOwner
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like "*c4-owner-pages*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
}
function Bail([string]$why) {
    Note "DRIVER STOPPED: $why"
    Finish
    Note "--- the owner script's output, last lines ---"
    (OutText) -split "`r?`n" | Select-Object -Last 25 | ForEach-Object { Note "  | $_" }
    exit 1
}
function WaitOut([string]$text, [int]$s) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) {
        $o = OutText
        if ($o.Contains($text)) { return }
        if ($o -match $stopRe) { Bail "the owner script stopped before '$text'" }
        if ($o -match $doneRe) { Bail "the owner script finished before '$text'" }
        if ($child.HasExited) { Bail "the owner script's runner exited before '$text'" }
        Start-Sleep 1
    }
    Bail "no '$text' from the owner script in $s s"
}

# ---- check-c4.ps1's helpers (the log is the owner script's run log) ------------------------------------------------
function Count([string]$re) { if (-not (Test-Path -LiteralPath $script:log)) { return 0 }; @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function LastOf([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Line -replace '^.*?\[workspaces\] ', '' }) } }
function ActiveWs { $m = @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $active -EA SilentlyContinue | Select-Object -Last 1); if ($m.Count) { $m[0].Matches[0].Groups[1].Value } else { "" } }
function Reveal {
    $cl = [E18Input]::Client($script:main)
    $null = [C4Input]::Park($script:main, $cl[0] + 2, $cl[1] + [int]($cl[3] / 2))
    Start-Sleep 1
}
function Msaa([IntPtr]$h, [object[]]$a) {
    if ($script:zen) { Reveal }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a
}
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function ChipIn($nodes, [string]$name) { NodeIn $nodes $name 0x2B }
function TabIn($nodes, [string]$title) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq $title -or $_.name.StartsWith("$title - ")) }) | Select-Object -First 1 }
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Rows($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x24 } | Sort-Object t) }
function Order($nodes) { @(@("Home", "Work", "Canary", "Private", "Unpin") | ForEach-Object { ChipIn $nodes $_ } | Where-Object { $_ } | Sort-Object l | ForEach-Object { $_.name }) }
function At($n, [double]$fx = 0.5, [double]$fy = 0.5) { @(($n.l + [int]($n.w * $fx)), ($n.t + [int]($n.h * $fy))) }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function Wins { @([E18Input]::Windows([uint32]$script:bpid)).Count }
# Workspace `name` shown by its chip pressed through MSAA: true once the log says so.
function Go([string]$name, [string]$guid) {
    if ((ActiveWs) -eq $guid) { return $true }
    $c = Count $active
    $null = Press $script:main $name 0x2B
    $ok = (WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid
    Start-Sleep 1
    $ok
}
# The Today tabs and pinned rows workspace `name` draws (its chip pressed, read, Work pressed again).
function Look([string]$name, [string]$guid) {
    $went = Go $name $guid
    $n = if ($went) { Nodes $script:main } else { @() }
    $back = Go "Work" $work
    [pscustomobject]@{ today = @(Today $n | ForEach-Object { $_.name }); rows = @(Rows $n | ForEach-Object { $_.name }); ok = $went -and $back }
}
# A guarded real drag through screen points `xy` in the main window, held `hold` ms at each point but the last.
function DragPath([int[]]$xy, [int]$hold = 0) {
    if ($script:zen) { Reveal }
    $h = [C4Input]::Hold($script:main, $script:main, $xy, $hold)
    if ($h -ne "held") { return $h }
    "held; $([C4Input]::Release([int[]]@(), $false, 600))"
}
function Found([int]$s) {
    $t0 = Get-Date; $p = $null
    do {
        $p = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" -and $_.MainWindowHandle -ne [IntPtr]::Zero }) | Select-Object -First 1
        if ($p) { break }
        Start-Sleep 1
    } while (((Get-Date) - $t0).TotalSeconds -lt $s)
    if (-not $p) { return $false }
    $script:bpid = $p.Id; $script:main = $p.MainWindowHandle
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
    [E18Input]::Place($script:main, 40, 40, 1400, 1000)
    Start-Sleep 2
    Note "browser $($script:bpid), log $($script:log); session '$env:SESSIONNAME', screen $([E18Input]::Screen() -join 'x'), window dpi $([E18Input]::Dpi($script:main))"
    $true
}
function CloseBrowser { foreach ($hw in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($hw) } }

E18InputType
# check-c4.ps1's C4Input, the parts this driver uses (a process of its own: no clash with check-c4's).
if (-not ("C4Input" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class C4Input {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  static bool down = false;
  static POINT saved;
  static IntPtr onto = IntPtr.Zero;
  static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
  static void Send(INPUT i) { SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT))); }
  static void Move(int x, int y) {
    int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
    INPUT i = new INPUT(); i.type = 0;
    i.u.mi.dx = (int)(((long)(x - vx) * 65535) / (vw - 1));
    i.u.mi.dy = (int)(((long)(y - vy) * 65535) / (vh - 1));
    i.u.mi.flags = 0x0001 | 0x8000 | 0x4000;
    Send(i);
  }
  static void Button(uint flags) { INPUT i = new INPUT(); i.type = 0; i.u.mi.flags = flags; Send(i); }
  static void Key(ushort vk, bool up) { INPUT i = new INPUT(); i.type = 1; i.u.ki.vk = vk; i.u.ki.flags = up ? 2u : 0u; Send(i); }
  static string Guard(IntPtr hwnd, int x, int y) {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);
    CloseDesktop(d);
    if (name.ToString() != "Default") return "the input desktop is '" + name + "' (the screen is locked?)";
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "not sent: another window is at " + x + "," + y;
    return null;
  }
  static string MoveTo(int x, int y) {
    Move(x, y); Thread.Sleep(150);
    POINT p; GetCursorPos(out p);
    if (Math.Abs(p.x - x) > 2 || Math.Abs(p.y - y) > 2) return "not sent: the cursor went to " + p.x + "," + p.y + ", not " + x + "," + y;
    return null;
  }
  static void Steps(int x0, int y0, int x1, int y1) {
    for (int s = 1; s <= 30; s++) { Move(x0 + (x1 - x0) * s / 30, y0 + (y1 - y0) * s / 30); Thread.Sleep(25); }
  }
  public static string CtrlClick(IntPtr hwnd, int x, int y) {
    Aware();
    string e = Guard(hwnd, x, y); if (e != null) return e;
    POINT back; GetCursorPos(out back);
    try {
      e = MoveTo(x, y); if (e != null) return e;
      Key(0x11, false); Button(0x0002); Thread.Sleep(60); Button(0x0004); Key(0x11, true); Thread.Sleep(600);
    } finally { SetCursorPos(back.x, back.y); }
    return "ctrl-clicked";
  }
  public static string Park(IntPtr hwnd, int x, int y) {
    Aware();
    return Guard(hwnd, x, y) ?? MoveTo(x, y) ?? "parked";
  }
  public static string Hold(IntPtr from, IntPtr to, int[] xy, int holdMs) {
    Aware();
    if (down) return "not sent: a drag is already held";
    string e = Guard(from, xy[0], xy[1]);
    for (int i = 2; e == null && i + 1 < xy.Length; i += 2) e = Guard(to, xy[i], xy[i + 1]);
    if (e != null) return e;
    GetCursorPos(out saved);
    e = MoveTo(xy[0], xy[1]);
    if (e != null) { SetCursorPos(saved.x, saved.y); return e; }
    Button(0x0002); down = true; onto = to; Thread.Sleep(150);
    for (int i = 2; i + 1 < xy.Length; i += 2) {
      Steps(xy[i - 2], xy[i - 1], xy[i], xy[i + 1]);
      if (i + 3 < xy.Length) Thread.Sleep(holdMs);
    }
    Thread.Sleep(300);
    return "held";
  }
  public static string Release(int[] xy, bool escape, int settleMs) {
    if (!down) return "nothing held";
    Aware();
    string e = null;
    try {
      POINT p; GetCursorPos(out p);
      for (int i = 0; e == null && i + 1 < xy.Length; i += 2) {
        e = Guard(onto, xy[i], xy[i + 1]);
        if (e == null) { Steps(p.x, p.y, xy[i], xy[i + 1]); p.x = xy[i]; p.y = xy[i + 1]; }
      }
      Move(p.x, p.y + 1); Thread.Sleep(200); Move(p.x, p.y); Thread.Sleep(settleMs);
      if (escape) { Key(0x1B, false); Key(0x1B, true); Thread.Sleep(400); }
    } finally {
      Button(0x0004); down = false; Thread.Sleep(300);
      SetCursorPos(saved.x, saved.y);
    }
    return e == null ? (escape ? "Escape, let go" : "let go") : e + ", let go where it was";
  }
}
"@
}

# ---- guards -------------------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $check)) { Write-Host "ABORT: no $check"; exit 1 }
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is running -- close it first"; exit 1 }
$gate = "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes)"
if ($gate -notmatch '^FREE') {
    Write-Host "VOID: the rehearsal moves the real mouse and needs the PC to itself -- the gate says: $gate. Nothing was run."
    Write-Host "      Leave the screen UNLOCKED and hands off and run it again; started by hand, add -IdleMinutes 0 and let go of the mouse."
    exit 2
}

Remove-Item -LiteralPath $feed, $out, "$out.err", $drv -EA SilentlyContinue
$null = New-Item -ItemType File -Path $feed
Set-Content -LiteralPath $runner -Encoding utf8 -Value "Get-Content -Wait -LiteralPath '$feed' | cmd /d /c `"pwsh -NoProfile -File $check 1>$out 2>$out.err`""
$child = Start-Process pwsh -ArgumentList @("-NoProfile", "-File", $runner) -WindowStyle Hidden -PassThru
Note "PC: $gate"
Note "owner script started (runner pid $($child.Id))"

WaitOut "WORDS USED BELOW" 600
if (-not (Found 60)) { Bail "no browser window" }

# ---- 0 ------------------------------------------------------------------------------------------------------------
WaitOut " 0. Press Shift+Alt+3" 60
Saw "0: Canary shown (its chip pressed)" (Go "Canary" $canary)
WaitOut "Done. Now press Shift+Alt+2" 120
Saw "0: Work shown" (Go "Work" $work)
WaitOut " 1. DRAG the TODAY TAB" 120
$o = OutText
Saw "0: the owner script opened every seeded tab" (-not $o.Contains("The script opened only"))

# ---- 1 ------------------------------------------------------------------------------------------------------------
$n = Nodes $script:main
$src = TabIn $n "C4 alpha"; $dst = ChipIn $n "Canary"
$cl = Count $lit; $cd = Count $drop; $cm = Count $moved; $w0 = Wins
$r = if ($src -and $dst) { DragPath ([int[]]((At $src) + (At $dst) + (At $dst))) 1200 } else { "not dragged: tab $([bool]$src), chip $([bool]$dst)" }
$ok = WaitLog $moved ($cm + 1) 10
Saw "1: C4 alpha dragged onto Canary's chip, held ($r): lit +$((Count $lit) - $cl), '$(LastOf $drop)', '$(LastOf $moved)'" ($ok -and (Count $lit) -gt $cl -and (Count $drop) -eq $cd + 1 -and (LastOf $moved) -match 'moved 1 tab\(s\).*, 1 unit\(s\) to the top')
Saw "1: no window added ($w0 -> $(Wins)), still on Work" ((Wins) -eq $w0 -and (ActiveWs) -eq $work)
$c = Look "Canary" $canary
Saw "1: Canary's Today tabs: $($c.today -join ', ') (C4 alpha first)" ($c.ok -and $c.today.Count -and $c.today[0] -eq "C4 alpha")
Answer "y" "step 1 done"

# ---- 2 ------------------------------------------------------------------------------------------------------------
WaitOut " 2. Click the TODAY TAB" 60
$n = Nodes $script:main
$b = TabIn $n "C4 beta"; $g = TabIn $n "C4 gamma"; $dst = ChipIn $n "Canary"
$cm = Count $moved
$r = if ($b -and $g -and $dst) {
    $c1 = [E18Input]::Click($script:main, (At $b)[0], (At $b)[1], $false)
    $c2 = [C4Input]::CtrlClick($script:main, (At $g)[0], (At $g)[1])
    "$c1; $c2; $(DragPath ([int[]]((At $b) + (At $dst))))"
} else { "not dragged" }
$ok = WaitLog $moved ($cm + 1) 10
Saw "2: C4 beta + C4 gamma selected and dragged onto Canary's chip ($r): '$(LastOf $moved)'" ($ok -and (LastOf $moved) -match 'moved 2 tab\(s\).*, 2 unit\(s\) to the top')
$c = Look "Canary" $canary
Saw "2: Canary's Today tabs: $($c.today -join ', ') (C4 beta, C4 gamma, C4 alpha first)" ($c.ok -and ((@($c.today | Select-Object -First 3)) -join ',') -eq "C4 beta,C4 gamma,C4 alpha")
Answer "y" "step 2 done"

# ---- 3 ------------------------------------------------------------------------------------------------------------
WaitOut " 3. Where a drop moves nothing" 60
$ca = Count $anyMove; $w0 = Wins
$n = Nodes $script:main
$d = TabIn $n "C4 delta"; $wk = ChipIn $n "Work"
$r1 = if ($d -and $wk) { DragPath ([int[]]((At $d) + (At $wk))) } else { "not dragged" }
Start-Sleep 2
$n = Nodes $script:main
$d = TabIn $n "C4 delta"; $ar = NodeIn $n "Archive" 0x2B
$r2 = if ($d -and $ar) { DragPath ([int[]]((At $d) + (At $ar))) } else { "not dragged" }
Start-Sleep 2
$still = [bool](TabIn (Nodes $script:main) "C4 delta")
Saw "3: C4 delta onto Work's chip ($r1), then Archive ($r2): $((Count $anyMove) - $ca) drop/move line(s), windows $w0 -> $(Wins), menus $(@(Popups).Count), still in Work $still" ((Count $anyMove) -eq $ca -and (Wins) -eq $w0 -and -not @(Popups).Count -and $still)
Answer "y" "step 3 done"

# ---- 4 ------------------------------------------------------------------------------------------------------------
WaitOut " 4. DRAG the PINNED PAGE" 60
$pm = "pins: moved 'c4p' to workspace '$canary'"
$cp = Count $pm
$n = Nodes $script:main
$src = NodeIn $n "C4 pinned" 0x24; $dst = ChipIn $n "Canary"
$r = if ($src -and $dst) { DragPath ([int[]]((At $src) + (At $dst) + (At $dst))) 1200 } else { "not dragged: row $([bool]$src), chip $([bool]$dst)" }
$ok = WaitLog $pm ($cp + 1) 10
Saw "4: the PINNED PAGE C4 pinned dragged onto Canary's chip, held ($r): '$(LastOf "pins: moved 'c4p'")'" $ok
$c = Look "Canary" $canary
Saw "4: Canary's pinned rows: $($c.rows -join ', ') (C4 pinned last)" ($c.ok -and $c.rows.Count -and $c.rows[-1] -eq "C4 pinned")
Answer "y" "step 4 done"

# ---- 5 ------------------------------------------------------------------------------------------------------------
WaitOut " 5. The menu does the same now" 60
$cm = Count $moved; $cd = Count $drop
$n = Nodes $script:main
$e = TabIn $n "C4 epsilon"; $chip = ChipIn $n "Canary"
$r = "no tab or chip"
if ($e -and $chip) {
    $r = [E18Input]::Click($script:main, (At $e)[0], (At $e)[1], $false)
    Start-Sleep 1
    $r += "; $([E18Input]::Click($script:main, (At $chip 0.33)[0], (At $chip)[1], $true))"
    $t0 = Get-Date; $item = $null
    do {
        Start-Sleep -Milliseconds 500
        foreach ($w in Popups) { $item = @(Nodes $w | Where-Object { $_.shown -and $_.name -match '^Move tab here' }) | Select-Object -First 1; if ($item) { $r += "; $(Press $w $item.name $item.role)"; break } }
    } while (-not $item -and ((Get-Date) - $t0).TotalSeconds -lt 10)
    if (-not $item) { $r += "; no 'Move tab here' in the menu"; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) }
}
$ok = WaitLog $moved ($cm + 1) 10
Saw "5: Move tab here on Canary's chip ($r): '$(LastOf $moved)', drop lines +$((Count $drop) - $cd)" ($ok -and (LastOf $moved) -match 'moved 1 tab\(s\).*, 1 unit\(s\) to the top' -and (Count $drop) -eq $cd)
$c = Look "Canary" $canary
Saw "5: Canary's Today tabs: $($c.today -join ', ') (C4 epsilon first)" ($c.ok -and $c.today.Count -and $c.today[0] -eq "C4 epsilon")
Answer "y" "step 5 done"

# ---- 6 ------------------------------------------------------------------------------------------------------------
WaitOut " 6. The order of the workspaces" 60
$re6 = "rail reorder: '$unpin' gap 1 -> offset -3"
$cr = Count $re6
$n = Nodes $script:main
$src = ChipIn $n "Unpin"; $dst = ChipIn $n "Work"
$r = if ($src -and $dst) { DragPath ([int[]]((At $src) + (At $dst 0.25))) } else { "no chips" }
$ok = WaitLog "moved workspace '$unpin' by -3" 1 10
Start-Sleep 2
$ord = Order (Nodes $script:main)
Saw "6: Unpin's chip dragged before Work's ($r): reorder line $((Count $re6) - $cr), moved by -3 $ok; the chips $($ord -join ', ')" ($ok -and (Count $re6) -eq $cr + 1 -and ($ord -join ',') -eq "Home,Unpin,Work,Canary,Private")
Answer "y" "step 6 done"

# ---- 7: zen ---------------------------------------------------------------------------------------------------------
WaitOut "Now close the test browser" 60
CloseBrowser
$script:log = $logs[1]; $script:bpid = 0
WaitOut " 7. ZEN MODE" 180
if (-not (Found 60)) { Bail "no browser window after the restart" }
$script:zen = $true
Start-Sleep 3
$n = Nodes $script:main
$ord = Order $n
Saw "7: zen, the chips $($ord -join ', ') (the order kept)" (($ord -join ',') -eq "Home,Unpin,Work,Canary,Private")
$src = TabIn $n "C4 zeta"; $dst = ChipIn $n "Canary"; $ar = NodeIn $n "Archive" 0x2B
$cl = Count $lit; $cm = Count $moved; $w0 = Wins
# Through a point held 4 px above the bar's top (the band CHK-1 found nobody claimed in zen), then held on the chip.
$band = if ($dst -and $ar) { @(($dst.l + [int]($dst.w / 2)), ($ar.t - 4)) } else { @() }
$r = if ($src -and $dst -and $band.Count) { DragPath ([int[]]((At $src) + $band + (At $dst) + (At $dst))) 1000 } else { "not dragged: tab $([bool]$src), chip $([bool]$dst)" }
$ok = WaitLog $moved ($cm + 1) 10
Saw "7: zen, C4 zeta through the band onto Canary's chip, held ($r): lit +$((Count $lit) - $cl), '$(LastOf $moved)', windows $w0 -> $(Wins)" ($ok -and (Count $lit) -gt $cl -and (Wins) -eq $w0)
Answer "y" "step 7 done"
WaitOut "Close the test browser. This window then grades the run." 30
CloseBrowser
$comment = if ($script:bad.Count) { "driver saw NOT OK: $($script:bad -join ' | ')" } else { "" }
Answer $comment "the closing comment"
$t = Get-Date
while (-not ((OutText) -match $doneRe) -and ((Get-Date) - $t).TotalSeconds -lt 120) { Start-Sleep 2 }
Finish
Note "--- the owner script's grading ---"
(OutText) -split "`r?`n" | Where-Object { $_ -match '^(PASS|FAIL|RESULT|your answers|seeding)' } | ForEach-Object { Note "  | $_" }
Note "RESULT try-c4 rehearsal: the driver saw $($script:bad.Count) thing(s) NOT OK"
