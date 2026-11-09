param([string]$OutDir = "Default", [string]$Tag = "e15e-auto")
# E15e without a person (LOCAL.md 50): a new window opens on the workspace of the window the user was in (design
# 1), not on Home; a REOPENED window still follows its own selected tab. Real input where a person would use the
# keyboard (Ctrl+N, Ctrl+Shift+T) -- sent only while the fork's window is the one in front and the input desktop
# is the user's; a click to bring it in front is guarded as in check-e15d3-auto.ps1. Rail buttons are pressed
# through MSAA. Graded from the log ("a window opens on workspace '<guid>'", one line per window) and from what
# each window's list shows.
#   0  startup: the first window opens on Home (no other window to follow)
#   A  from Work, a new window from outside (--new-window)   -> opens on Work
#   B  from Work, Ctrl+N                                      -> opens on Work, its New Tab is Work's
#   C  from Home, --new-window                                -> opens on Home (not always Work)
#   D  a window with a Home page, closed while the window in front shows Work, reopened (Ctrl+Shift+T)
#      -> opens on Work, then follows its own page to Home: the page shows
#   0 markers
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof  = "$ws\testprofile-$Tag"
$exe   = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$pages = "$ws\$Tag-pages"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work  = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$script:failed = 0
$script:win = [IntPtr]::Zero
function Verdict($name, $ok) { if ($ok) { "PASS  $name" } else { "FAIL  $name"; $script:failed++ } }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Msaa([string[]]$a) {
    if ($script:win -ne [IntPtr]::Zero) { $a += @("-Window", [string][long]$script:win) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof @a
}
function Press([string]$name, [int]$role) { Msaa @("-Name", $name, "-Role", $role) }
function Nodes {
    @(Msaa @("-List", "-Rect") | ForEach-Object {
        if ($_ -match '^\s*(.*)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                               l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7] }
        }
    })
}
function ShownTabs { @(Nodes | Where-Object { $_.role -eq 0x25 -and -not $_.hidden -and $_.h -gt 0 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { $_.name }) }
function WaitLog([string]$log, [string]$re, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and (Select-String -Path $log -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# The workspace each window opened on, in order.
function Opened([string]$log) { if (-not (Test-Path $log)) { return @() }; @(Select-String -Path $log -Pattern "a window opens on workspace '([^']+)'" | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
function WaitOpened([string]$log, [int]$n, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Opened $log).Count -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function Close {
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
}
function Markers([string]$log) { @(Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class Input {
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
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  delegate bool EnumProc(IntPtr h, IntPtr l);

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
  static string Desktop() {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);
    CloseDesktop(d);
    return name.ToString() == "Default" ? null : "the input desktop is '" + name + "'";
  }

  public static void Topmost(IntPtr hwnd, bool on) { SetWindowPos(hwnd, new IntPtr(on ? -1 : -2), 0, 0, 0, 0, 0x0013); }
  public static void CloseWindow(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }

  // A left click at (x, y), only on the browser's window there; brings it in front.
  public static string Click(IntPtr hwnd, int x, int y) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    string e = Desktop(); if (e != null) return e;
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "another window is at " + x + "," + y;
    POINT saved; GetCursorPos(out saved);
    try {
      Move(x, y); Thread.Sleep(120);
      Button(0x0002); Thread.Sleep(60); Button(0x0004); Thread.Sleep(500);
    } finally { SetCursorPos(saved.x, saved.y); }
    return "clicked";
  }

  // Ctrl(+Shift)+key to the window in front -- only when it is the browser's.
  public static string Keys(uint pid, bool shift, ushort vk) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    Key(0x11, false); if (shift) Key(0x10, false);
    Key(vk, false); Key(vk, true);
    if (shift) Key(0x10, true); Key(0x11, true);
    Thread.Sleep(500);
    return "sent";
  }

  // The browser windows of a process (not owned: a bubble or a menu is), and one other than `main`.
  static IntPtr Find(uint pid, IntPtr main, ref int count) {
    IntPtr found = IntPtr.Zero; int n = 0;
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      StringBuilder c = new StringBuilder(64); GetClassName(h, c, 64);
      if (p == pid && IsWindowVisible(h) && c.ToString() == "Chrome_WidgetWin_1" && GetWindow(h, 4) == IntPtr.Zero) {
        n++; if (h != main && found == IntPtr.Zero) found = h;
      }
      return true;
    }, IntPtr.Zero);
    count = n;
    return found;
  }
  public static int Windows(uint pid) { int n = 0; Find(pid, IntPtr.Zero, ref n); return n; }
  public static IntPtr Other(uint pid, IntPtr main) { int n = 0; return Find(pid, main, ref n); }
}
"@

function Hwnd { (Get-Process -Id (Pids)[0]).MainWindowHandle }
function Pid1 { [uint32](Pids)[0] }
# Brings window 1 in front with a guarded click on its first list tab (activating a tab of its own list).
function Front {
    $n = @(Nodes | Where-Object { $_.role -eq 0x25 -and -not $_.hidden -and $_.h -gt 0 } | Sort-Object t)[0]
    if (-not $n) { return "no list tab to click" }
    [Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2))
}
# Waits for a second window, returns it.
function Second { $w = [IntPtr]::Zero; $t = Get-Date; while (((Get-Date) - $t).TotalSeconds -lt 20 -and $w -eq [IntPtr]::Zero) { Start-Sleep 1; $w = [Input]::Other((Pid1), $script:win) }; return $w }
function CloseSecond([IntPtr]$w) { [Input]::CloseWindow($w); $t = Get-Date; while (((Get-Date) - $t).TotalSeconds -lt 20 -and [Input]::Windows((Pid1)) -gt 1) { Start-Sleep 1 } }
function Alive { if (-not (Pids).Count) { Verdict "the browser is still running" $false; throw "the browser is gone -- a crash? See $log" } }

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running"; exit 1 }
"binary: $OutDir, $((Get-Item $exe).LastWriteTime)"
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path "$prof\Default\Preferences")) { "ABORT: copy failed"; exit 1 }
$null = New-Item -ItemType Directory -Force $pages
Set-Content -Encoding UTF8 -Path "$pages\nine.html" -Value "<!doctype html><title>E15e nine</title><h1>E15e nine</h1>"
$server = Start-Process python -ArgumentList "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $pages -WindowStyle Hidden -PassThru
$log = "$ws\$Tag.log"
try {
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session") | Out-Null
    Verdict "0: the first window opens on Home" ((WaitOpened $log 1 30) -and @(Opened $log)[0] -eq 'default')
    Start-Sleep 4
    $script:win = Hwnd
    [Input]::Topmost($script:win, $true)
    $null = Press "Work" 0x2B
    Verdict "setup: window 1 switched to Work" (WaitLog $log "pins: drew \d+ row\(s\) of '$work'" 15)

    # A: from outside, a new window. Window 1 brought in front first: a window started by a script may never
    # have been activated, and "the window the user was in" is the one activated last.
    "      A: " + (Front)
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window") | Out-Null
    $w2 = Second; Alive
    Verdict "A: a second window opened" ($w2 -ne [IntPtr]::Zero)
    Verdict "A: it opens on Work" ((WaitOpened $log 2) -and @(Opened $log)[1] -eq $work)
    if ($w2 -ne [IntPtr]::Zero) { CloseSecond $w2 }

    # B: Ctrl+N, a person's way
    "      B: " + (Front) + ", Ctrl+N " + [Input]::Keys((Pid1), $false, 0x4E)
    $w2 = Second; Alive
    Verdict "B: a second window opened" ($w2 -ne [IntPtr]::Zero)
    Verdict "B: it opens on Work" ((WaitOpened $log 3) -and @(Opened $log)[2] -eq $work)
    if ($w2 -ne [IntPtr]::Zero) {
        $w1 = $script:win; $script:win = $w2; Start-Sleep 2
        $tabs = ShownTabs; "      B: its list: " + ($tabs -join ', ')
        Verdict "B: its New Tab shows in its list -- stamped Work, the workspace it shows" ($tabs -contains "New Tab")
        $script:win = $w1
        CloseSecond $w2
    }

    # C: from Home, a new window opens on Home
    $null = Press "Home" 0x2B
    $null = WaitLog $log "pins: drew \d+ row\(s\) of 'default'" 15
    "      C: " + (Front)
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window") | Out-Null
    $w2 = Second; Alive
    Verdict "C: it opens on Home" ((WaitOpened $log 4) -and @(Opened $log)[3] -eq 'default')
    if ($w2 -ne [IntPtr]::Zero) { CloseSecond $w2 }

    # D: a reopened window follows its own page, not the window in front
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "nine")) | Out-Null
    $w2 = Second; Alive
    Verdict "D: a window with the Home page 'E15e nine' opened on Home" ((WaitOpened $log 5) -and @(Opened $log)[4] -eq 'default')
    Start-Sleep 3
    $null = Press "Work" 0x2B
    $null = WaitLog $log "active workspace -> '$work'" 15
    if ($w2 -ne [IntPtr]::Zero) { CloseSecond $w2 }
    "      D: " + (Front) + ", Ctrl+Shift+T " + [Input]::Keys((Pid1), $true, 0x54)
    $w3 = Second; Alive
    Verdict "D: the closed window came back" ($w3 -ne [IntPtr]::Zero)
    Verdict "D: it opens on Work, the window in front" ((WaitOpened $log 6) -and @(Opened $log)[5] -eq $work)
    if ($w3 -ne [IntPtr]::Zero) {
        $w1 = $script:win; $script:win = $w3; $t = Get-Date
        while (((Get-Date) - $t).TotalSeconds -lt 15 -and -not ((ShownTabs) -contains "E15e nine")) { Start-Sleep 1 }
        $tabs = ShownTabs; "      D: its list: " + ($tabs -join ', ')
        Verdict "D: ...then follows its own page to Home: 'E15e nine' shows in its list" ($tabs -contains "E15e nine")
        $script:win = $w1
        CloseSecond $w3
    }
    "      opened on: " + ((Opened $log) -join ', ')

    [Input]::Topmost($script:win, $false)
    Close
    Verdict "0 markers" ((Markers $log) -eq 0)
} catch {
    "ABORT: $_"
    $script:failed++
} finally {
    if ((Pids).Count) { Close }
    Stop-Process -Id $server.Id -EA SilentlyContinue
}
if ($script:failed) { "$($script:failed) check(s) FAILED" } else { "ALL PASS" }
