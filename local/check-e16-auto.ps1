param([string]$OutDir = "Default", [string]$Tag = "e16-auto")
# E16 without a person (LOCAL.md 58), with E18c's wider sidebar (patch 57, design 5 "E18 spec" part 4): the zen-mode
# FLOATING sidebar can be resized by its edge, as the pinned one can. Helium's zen-mode.patch hid the edge while the
# sidebar floats (zen mode on, "Always show the sidebar" off); patch 50 keeps it, and a floating strip dragged narrow
# stops at its narrowest instead of collapsing. Patch 57: with helium.workspaces.wide_sidebar on (the default) the
# widest is the window's width - 200 instead of Helium's 400, logged at each drag's end as
# "[workspaces] sidebar: width W (max M)" (W the drawn width, which the layout's toolbar minimum may keep below M).
# The drags are REAL mouse input (SendInput), guarded as check-e15d3-auto.ps1's: the input desktop must be the
# user's, the fork's window must be the one under every point, and the cursor must land where it was sent; else
# nothing is pressed and the step FAILs. Every drag ends inside the window. The cursor is put back at the end.
# Two runs, each on a fresh throwaway profile (deleted and re-made), seeded: vertical layout, zen mode on, the
# sidebar NOT pinned, width 240; the second also wide_sidebar false. The window is 1000 DIPs wide, so the widest
# (about 800) still ends left of step H's point at 85%. Widths are read from where the edge is drawn (MSAA), in
# DIPs; the window's width from its client area; the saved width from Preferences after the browser closes.
#   S  the cursor at the window's left edge slides the sidebar in: its tabs are shown
#   E  its resize edge is shown (Helium hid it: this is the red step on a build without 50)
#   0  the width is the seeded 240
#   1  dragged +60 -> 300; while the button is still held the sidebar is shown
#   2  on:  dragged +400 -> 700, or the widest drawn in W if that is less (graded after W)
#      off: dragged +400 (past the widest) and HELD 3.5 s, longer than zen mode's "cursor left" timer (3 s) ->
#           still shown, 400 wide; the log says "width 400 (max 400)"; let go
#   W  on only: dragged +800 (past the widest) and HELD 3.5 s -> still shown; the log's M is the window's width
#      - 200 (16 DIPs of slack for the frame), W <= M, W > 400 (wider than Helium's), and the strip is drawn W wide
#   H  the cursor on the page: the sidebar hides (it still floats)
#   3  slid in again, dragged -800 -> stops at 160, NOT collapsed (its tabs keep their width)
#   P  closed: Preferences has uncollapsed_width 160 and collapsed_state false; 0 crash markers
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$src   = "$ws\helium-windows\build\src"
$bin   = "$src\out\$OutDir"
$exe   = "$bin\chrome.exe"
$edgeName = "Vertical Tab Strip Resize Handle (Draggable)"
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { "PASS  $name" } else { "FAIL  $name"; $script:failed++ } }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Nodes {
    @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -List -Rect | ForEach-Object {
        if ($_ -match '^\s*(.*)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                               l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7] }
        }
    })
}
# What the sidebar shows now: its edge (or $null) and its tabs.
function Look {
    $n = Nodes
    $shown = @($n | Where-Object { -not $_.hidden -and $_.w -gt 0 -and $_.h -gt 0 })
    [pscustomobject]@{ edge = @($shown | Where-Object { $_.name -eq $edgeName }) | Select-Object -First 1
                       tabs = @($shown | Where-Object { $_.role -eq 0x25 }) }
}
# The sidebar's width in DIPs, from its edge's right side: the floating strip starts 8 DIPs in (kZenModeVTSPadding).
function Width($look) { if (-not $look.edge) { return -1 }; [math]::Round(($look.edge.l + $look.edge.w - $script:cl) / $script:scale - 8) }
function Near($a, $b) { [math]::Abs($a - $b) -le 3 }
# Presses the edge's middle and moves $dip DIPs sideways, ending inside the client area (the guard refuses a point
# outside the fork's window); the button stays down until Up().
function Drag($look, [int]$dip) {
    $x = $look.edge.l + [int]($look.edge.w / 2); $y = $look.edge.t + [int]($look.edge.h / 2)
    $to = [math]::Min([math]::Max($x + [int]($dip * $script:scale), $script:c[0] + 4), $script:c[0] + $script:c[2] - 10)
    [E16Mouse]::Press($script:win, $x, $y, $to, $y)
}
# Patch 57's lines so far; and the first one after $after of them as (W, M), waiting up to 5 s (Get-Content: the log
# is still being written).
function WidthLines { @(Get-Content -LiteralPath $script:log -EA SilentlyContinue | Select-String -Pattern '\[workspaces\] sidebar: width (\d+) \(max (\d+)\)') }
function NextWidthLine([int]$after) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 5) {
        $l = WidthLines
        if ($l.Count -gt $after) { $g = $l[$after].Matches[0].Groups; return @([int]$g[1].Value, [int]$g[2].Value) }
        Start-Sleep -Milliseconds 300
    }
    $null
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class E16Mouse {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public MOUSEINPUT mi; }  // the union's largest member: 40 bytes on x64
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);

  static bool down = false;
  static POINT saved;
  // Physical pixels, as MSAA gives the fork's boxes.
  static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
  static void Send(uint flags, int x, int y) {
    INPUT i = new INPUT(); i.type = 0; i.mi.flags = flags;
    if ((flags & 0x8000) != 0) {
      int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
      i.mi.dx = (int)(((long)(x - vx) * 65535) / (vw - 1));
      i.mi.dy = (int)(((long)(y - vy) * 65535) / (vh - 1));
    }
    SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT)));
  }
  static void Move(int x, int y) { Send(0x0001 | 0x8000 | 0x4000, x, y); }  // MOVE | ABSOLUTE | VIRTUALDESK

  // Null when input may be sent at (x, y); else why not.
  public static string Guard(IntPtr hwnd, int x, int y) {
    Aware();
    IntPtr d = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);  // UOI_NAME
    CloseDesktop(d);
    if (name.ToString() != "Default") return "the input desktop is '" + name + "' (the screen is locked?)";
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "another window is at " + x + "," + y;  // GA_ROOT
    return null;
  }
  // Moves there (guarded) and checks it got there.
  public static string MoveTo(IntPtr hwnd, int x, int y) {
    string e = Guard(hwnd, x, y); if (e != null) return e;
    Move(x, y); Thread.Sleep(150);
    POINT p; GetCursorPos(out p);
    if (Math.Abs(p.x - x) > 2 || Math.Abs(p.y - y) > 2) return "the cursor went to " + p.x + "," + p.y + ", not " + x + "," + y;
    return null;
  }
  // Presses at (x0, y0) and moves to (x1, y1) in steps; the button stays DOWN until Up().
  public static string Press(IntPtr hwnd, int x0, int y0, int x1, int y1) {
    string e = Guard(hwnd, x1, y1); if (e == null) e = MoveTo(hwnd, x0, y0); if (e != null) return e;
    Send(0x0002, 0, 0); down = true; Thread.Sleep(150);  // LEFTDOWN
    const int steps = 30;
    for (int s = 1; s <= steps; s++) { Move(x0 + (x1 - x0) * s / steps, y0 + (y1 - y0) * s / steps); Thread.Sleep(25); }
    Thread.Sleep(300);
    return null;
  }
  public static void Up() { if (down) { Send(0x0004, 0, 0); down = false; Thread.Sleep(300); } }  // LEFTUP
  public static void SaveCursor() { GetCursorPos(out saved); }
  public static void RestoreCursor() { Up(); SetCursorPos(saved.x, saved.y); }

  // Restored, placed and topmost, not activated.
  public static void Place(IntPtr h, int x, int y, int w, int height) { Aware(); ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), x, y, w, height, 0x0010); }
  public static void NotTopmost(IntPtr h) { SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x0013); }
  // The client area on screen: left, top, width, height (physical pixels).
  public static int[] Client(IntPtr h) {
    Aware(); RECT r; GetClientRect(h, out r); POINT p; p.x = 0; p.y = 0; ClientToScreen(h, ref p);
    return new int[] { p.x, p.y, r.r - r.l, r.b - r.t };
  }
  public static int Dpi(IntPtr h) { return (int)GetDpiForWindow(h); }
  public static int[] Screen() { Aware(); return new int[] { GetSystemMetrics(0), GetSystemMetrics(1) }; }
}
"@

"E16 floating sidebar resize -- out\$OutDir"
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running -- close it first"; exit 1 }
if (-not (Test-Path "$bin\chrome.dll")) { "ABORT: no $bin\chrome.dll"; exit 1 }
# Against the newest SOURCE of patch 57, not the patch file (LOCAL.md 52: a quilt refresh rewrites the patch after
# the build): every .cc/.h/.gn file the patch touches.
$patch = "$ws\helium-windows\patches\local\workspaces\57-wide-sidebar.patch"
if (-not (Test-Path $patch)) { "ABORT: no patch 57 ($patch)"; exit 1 }
$sources = @(Select-String -Path $patch -Pattern '^\+\+\+ b/(\S+\.(cc|h|gn))$' | ForEach-Object { $_.Matches[0].Groups[1].Value })
if (-not $sources.Count) { "ABORT: patch 57 names no .cc/.h/.gn file"; exit 1 }
$missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
if ($missing.Count) { "ABORT: missing source(s) of patch 57: $($missing -join ', ')"; exit 1 }
$newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { "ABORT: $OutDir\chrome.dll is older than a source of patch 57 (stale binary)"; exit 1 }
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'sidebar: width')>=0 else 1)" "$bin\chrome.dll"
if ($LASTEXITCODE -ne 0) { "ABORT: $OutDir\chrome.dll does not contain patch 57 ('sidebar: width')"; exit 1 }
"binary: $OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime)"

foreach ($wide in $true, $false) {
    # Script scope throughout: Drag, Width and WidthLines read $c, $win, $scale, $cl and $log from here.
    $prof = if ($wide) { "$ws\testprofile-$Tag" } else { "$ws\testprofile-$Tag-narrow" }
    $log  = if ($wide) { "$ws\e16-run-$($OutDir.ToLower()).log" } else { "$ws\e16-run-$($OutDir.ToLower())-narrow.log" }
    $w2 = -1; $widest = -1
    if ($wide) { "--- wide_sidebar on (the default): the widest is the window's width - 200 -- profile $prof" }
    else { "--- wide_sidebar off: Helium's 400 -- profile $prof" }
    if ((Pids).Count) { "FAIL  a browser already runs on $prof -- close it first"; $script:failed++; continue }
    # The throwaway profile, made fresh: only ever this script's own folders.
    if ((Split-Path -Leaf $prof) -notin @("testprofile-$Tag", "testprofile-$Tag-narrow")) { "FAIL  refusing to reset $prof"; $script:failed++; continue }
    if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = New-Item -ItemType Directory -Force "$prof\Default"
    $wsPref = if ($wide) { "" } else { ',"workspaces":{"wide_sidebar":false}' }
    $seed = '{"helium":{"browser":{"layout":2,"zen_mode":true,"zen_mode_sidebar_pinned":false}' + $wsPref + '},"vertical_tabs":{"uncollapsed_width":240,"collapsed_state":false}}'
    [IO.File]::WriteAllText("$prof\Default\Preferences", $seed)

    Remove-Item -LiteralPath $log -EA SilentlyContinue
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "about:blank", "about:blank") | Out-Null
    $t = Get-Date; $win = [IntPtr]::Zero
    while ($win -eq [IntPtr]::Zero -and ((Get-Date) - $t).TotalSeconds -lt 30) {
        Start-Sleep 1; if ((Pids).Count) { $win = (Get-Process -Id (Pids)[0]).MainWindowHandle }
    }
    if ($win -eq [IntPtr]::Zero) { "FAIL  no browser window in 30 s"; $script:failed++; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; continue }
    Start-Sleep 3

    [E16Mouse]::SaveCursor()
    try {
        $scale = [E16Mouse]::Dpi($win) / 96.0
        $scr = [E16Mouse]::Screen()
        [E16Mouse]::Place($win, 0, 0, [math]::Min($scr[0], [int](1000 * $scale)), [math]::Min($scr[1] - 80, [int](800 * $scale)))
        Start-Sleep 1
        $c = [E16Mouse]::Client($win); $cl = $c[0]
        $clientDip = [int][math]::Round($c[2] / $scale)
        $maxWant = [math]::Max(160, $clientDip - 200)
        "      scale $scale, client $($c -join ',') ($clientDip DIPs wide)"
        $midY = $c[1] + [int]($c[3] / 2)
        $edgeX = $c[0] + 2  # inside zen mode's 6-DIP side trigger

        # S, E, 0: slide it in; its edge is shown; seeded width.
        $e = [E16Mouse]::MoveTo($win, $edgeX, $midY); if ($e) { throw "S: $e" }
        Start-Sleep 1; $look = Look
        Verdict "S  the sidebar slides in (tabs shown: $($look.tabs.Count))" ($look.tabs.Count -ge 2)
        Verdict "E  its resize edge is shown" ($null -ne $look.edge)
        if (-not $look.edge) { throw "nothing to drag: stopping" }
        $w0 = Width $look
        Verdict "0  the width is the seeded 240 (measured $w0)" (Near $w0 240)

        # 1: +60, shown while held.
        $e = Drag $look 60
        if ($e) { "FAIL  1: $e"; $script:failed++ } else {
            $held = Look
            [E16Mouse]::Up(); Start-Sleep 1; $look = Look
            Verdict "1  shown while held (tabs $($held.tabs.Count)), then 300 wide (measured $(Width $look))" ($held.tabs.Count -ge 2 -and (Near (Width $look) 300))
        }
        $w1 = Width $look

        # 2: +400. Off, that is past the widest: held longer than the "cursor left" timer.
        $before = @(WidthLines).Count
        $e = Drag $look 400
        if ($e) { "FAIL  2: $e"; $script:failed++ } else {
            if (-not $wide) { Start-Sleep -Milliseconds 3500 }
            $held = Look
            [E16Mouse]::Up()
            $w2 = Width $held
            if (-not $wide) {
                $line = NextWidthLine $before
                $said = if ($line) { "width $($line[0]) (max $($line[1]))" } else { "no 'sidebar: width' line" }
                Verdict "2  held 3.5 s past the widest: still shown (tabs $($held.tabs.Count)), 400 wide (measured $w2); the log: $said (400, 400)" ($held.tabs.Count -ge 2 -and (Near $w2 400) -and $line -and $line[0] -eq 400 -and $line[1] -eq 400)
            }
        }

        # W (on only): past the widest -- the window's, not 400 -- held longer than the "cursor left" timer.
        if ($wide) {
            $e = [E16Mouse]::MoveTo($win, $edgeX, $midY); Start-Sleep 1; $look = Look
            if ($e -or -not $look.edge) { "FAIL  W: no edge to drag ($e)"; $script:failed++ } else {
                $before = @(WidthLines).Count
                $e = Drag $look 800
                if ($e) { "FAIL  W: $e"; $script:failed++ } else {
                    Start-Sleep -Milliseconds 3500
                    $held = Look
                    [E16Mouse]::Up()
                    $widest = Width $held
                    Verdict "W  held 3.5 s past the widest: still shown (tabs $($held.tabs.Count))" ($held.tabs.Count -ge 2)
                    $line = NextWidthLine $before
                    if (-not $line) { Verdict "W  the log has a 'sidebar: width W (max M)' line" $false } else {
                        Verdict "W  the log: width $($line[0]) (max $($line[1])); max = $clientDip - 200 = $maxWant (+-16), width <= max, width > 400, drawn $widest wide" (([math]::Abs($line[1] - $maxWant) -le 16) -and $line[0] -le $line[1] -and $line[0] -gt 400 -and (Near $widest $line[0]))
                    }
                }
            }
            if ($w2 -ge 0) {
                $top = if ($widest -gt 0) { $widest } else { $maxWant }
                $want = [math]::Min($w1 + 400, $top)
                Verdict "2  dragged +400 from $w1 -> $want (the lesser of $($w1 + 400) and the widest drawn, $top; measured $w2)" (Near $w2 $want)
            }
        }

        # H: on the page, it hides.
        $e = [E16Mouse]::MoveTo($win, $c[0] + [int]($c[2] * 0.85), $midY); if ($e) { throw "H: $e" }
        Start-Sleep 2; $look = Look
        Verdict "H  the cursor on the page: the sidebar hides (tabs shown: $($look.tabs.Count))" ($look.tabs.Count -eq 0)

        # 3: in again, far narrower: stops at 160, not collapsed.
        $e = [E16Mouse]::MoveTo($win, $edgeX, $midY); if ($e) { throw "3: $e" }
        Start-Sleep 1; $look = Look
        if (-not $look.edge) { "FAIL  3: no edge after sliding in again"; $script:failed++ } else {
            $e = Drag $look -800
            if ($e) { "FAIL  3: $e"; $script:failed++ } else {
                [E16Mouse]::Up(); Start-Sleep 1
                $null = [E16Mouse]::MoveTo($win, $edgeX, $midY); Start-Sleep 1; $look = Look
                $tabW = if ($look.tabs.Count) { [math]::Round(($look.tabs | Measure-Object w -Maximum).Maximum / $scale) } else { 0 }
                Verdict "3  dragged far narrower: 160 wide (measured $(Width $look)), not collapsed (widest tab $tabW DIPs)" ((Near (Width $look) 160) -and $tabW -gt 100)
            }
        }
    } catch { "FAIL  $_"; $script:failed++ } finally {
        [E16Mouse]::RestoreCursor()
        if ((Pids).Count) { [E16Mouse]::NotTopmost($win) }
    }

    # P: closed; the saved width.
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
    $p = [IO.File]::ReadAllText("$prof\Default\Preferences") | ConvertFrom-Json
    Verdict "P  saved: uncollapsed_width $($p.vertical_tabs.uncollapsed_width) (160), collapsed_state $($p.vertical_tabs.collapsed_state) (False)" ($p.vertical_tabs.uncollapsed_width -eq 160 -and -not $p.vertical_tabs.collapsed_state)
    $m = @(Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count
    Verdict "   crash markers in the log: $m" ($m -eq 0)
}
if ($script:failed) { "E16 AUTO: FAIL ($($script:failed))"; exit 1 } else { "E16 AUTO: ALL PASS" }
