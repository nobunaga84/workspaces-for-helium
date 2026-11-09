param([string]$OutDir = "Default", [string]$Tag = "e14d1-auto")
# E14d.1 without a person (design 5, "E14d spec"; LOCAL.md 51): every close the user makes is kept in the
# profile's "Workspace Archive" file -- except a window's tabs the session keeps and a pinned item's page. Real
# keyboard input where a person would use it (Ctrl+W, Ctrl+T, Ctrl+Shift+T, Ctrl+Shift+W, Ctrl+L, Alt+F), sent
# only while the fork's window is the one in front and the input desktop is the user's; the click that brings a
# window in front is guarded as in check-e15d3-auto.ps1. The rail's Work, a pinned row and the app menu's Exit
# are pressed through MSAA; a window's X is its WM_CLOSE. Graded from each run's log AND the file (written
# 2.5 s after a change: read 5 s later; no file = 0 entries). Pages come from a local server with caching off
# whose request log proves a page was never loaded (check-r4.ps1's serve.py). All closes in Work, not the
# default workspace. Run it in its OWN process: a second check script in one session reuses the first's Input.
#   P  preconditions checked, not assumed (set-workspaces-pref.py --show exits 0; no archive file yet)
#   A  Ctrl+W on a loaded page          -> "archived a manual close in '<work>'"; 1 entry: manual, Work, its url
#   B  Ctrl+T, Ctrl+W                   -> "not archived: an untouched New Tab page"; the file unchanged
#   C  Ctrl+Shift+T                     -> the page is back; "a reopened close leaves the archive"; 0 entries
#   K  the tab menu's "Close" (right-click) -> archived manual (Chromium's .52 slip, fixed in 47); Ctrl+Shift+T
#      puts it back and takes it out
#   D  Exit with TWO windows (window 2: two pages, the second never activated) -> nothing archived; the door
#      refused every tab of both windows but a favorite ("not archived: the browser is quitting" or "...the
#      session keeps the last window's tabs"; a favorite logs "not archived: a favorite (a pinned tab)")
#   E  a restart: both windows back, the never-activated page NOT requested; window 2 closed (Ctrl+Shift+W)
#      while window 1 stays -> 2 "archived a window close" lines; 2 entries, one the never-loaded page's url
#   F  Ctrl+Shift+T reopens window 2    -> 2 "a reopened close leaves the archive"; 0 entries
#   G  window 2 closed again (2 entries), then the last window -> "not archived: the session keeps the last
#      window's tabs", the file unchanged; a restart brings its tabs back
#   I  (run 3) a second window with a page and a pinned item's page (its row pressed), closed by its X while
#      window 1 stays -> "not archived: a pinned item's page"; 1 "archived a window close"; the file gains
#      only the Today page
#   J  (run 3) a second window with a page, then the app menu's Exit (Alt+F, Exit) -> the browser exits; no
#      "archived" line, the file unchanged, 3+ "not archived: the session keeps the last window's tabs", one
#      per tab that is not a favorite; the next start brings both windows back
#   H  Workspaces off, a restart: J's second window closed by its X, then a click, a load and Ctrl+W on a page,
#      each graded, the tab gone -> no "archived" line, the file unchanged
#   M  0 markers in every run's log
# Exit (D) is chrome://quit TYPED in the address bar: the same URL given on the command line is dropped
# (startup/url_util.cc ValidateLaunchUrlWebUnsafe: no chrome:// outside headless), and the existing scripts'
# Close (CloseMainWindow) closes ONE window -- with two open that is the `window` close, not an Exit. J is the
# app menu's Exit: chrome::AttemptUserExit, which unlike chrome://quit never sets IsTryingToQuit (review,
# LOCAL.md 52).
# Not covered hands-free, left to the owner's check:
#   - the tab menu's Close / Close others / below, Close group, a selection, tab search's X, X and middle-click,
#     a page closing itself: the same door as Ctrl+W (the record is made at CreateHistoricalTab, design 5's
#     table), each needing a menu, a hover-only button or a page script this script does not drive
#   - a pinned page's X or Ctrl+W (E15c): a page with an unload-type handler reaches the door through
#     CloseContents and is refused as I's is; proving it needs such a page pinned
#   - an anchored tab's X (34), a drag to another window or Move to new window: they never reach the door;
#     proving the negative needs an anchor set, a real drag
#   - the rail's Close all tabs and Delete workspace (an open pinned page among them is refused as in I): the
#     rail's menu and its confirm dialog
#   - a profile's Close all windows: J's path, through the profile menu
#   - log-off and a silent exit ("not archived: the browser is quitting"; not simulated) and incognito (no
#     WorkspaceService)
$ws     = "<local-path>\Helium-workspace"
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof   = "$ws\testprofile-$Tag"
$exe    = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$pages  = "$ws\$Tag-pages"
$srvlog = "$ws\$Tag-requests.log"
$afile  = "$prof\Default\Workspace Archive"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$archived = "\[workspaces\] archived a "
$manual   = "archived a manual close in '$work'"
$window   = "archived a window close in '$work'"
$refused  = "archived a .*\(refused\)"
$reopened = "archive: a reopened close leaves the archive"
$kept     = "not archived: the session keeps the last window's tabs"
$pinned   = "not archived: a pinned item's page"
# At an Exit: "quitting" is HasShutdownStarted, which chrome://quit may not reach before its windows close.
$atExit   = "not archived: (the browser is quitting|the session keeps the last window's tabs)"
$script:failed = 0
$script:win = [IntPtr]::Zero
$script:logs = @()
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
function Node([string]$name, [int]$role) { @(Nodes | Where-Object { $_.name -eq $name -and $_.role -eq $role -and -not $_.hidden -and $_.h -gt 0 }) | Select-Object -First 1 }
function ShownTabs { @(Nodes | Where-Object { $_.role -eq 0x25 -and -not $_.hidden -and $_.h -gt 0 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { $_.name }) }
# A tab of the window, shown or not (a tab of another workspace is in the tree, INVISIBLE).
function HasTab([string]$tab) { [bool]@(Nodes | Where-Object { $_.role -eq 0x25 -and $_.name -eq $tab }).Count }
# A page's tab by either name: a tab never loaded since a restart shows its address, not its title.
function PageTab([string]$n) { if (HasTab "E14d1 $n") { "E14d1 $n" } else { "127.0.0.1:$port/$n.html" } }
# How many tabs window `h` holds, shown or not, favorites ("<title> - Pinned") left out: at an Exit every one of
# them passes the door (the fix review: a fixed "4+" was met by window 1 alone); a favorite logs "not archived:
# a favorite (a pinned tab)" there since patch 48, not a quit or last-window line.
function TabCount([IntPtr]$h) { $keep = $script:win; $script:win = $h; $c = @(Nodes | Where-Object { $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' }).Count; $script:win = $keep; return $c }
function WaitShown([string]$tab, [int]$s = 15) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((ShownTabs) -contains $tab) { return $true }; Start-Sleep 1 }
    return $false
}
function WaitLog([string]$log, [string]$re, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and (Select-String -Path $log -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function WaitCount([string]$log, [string]$re, [int]$n, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and @(Select-String -Path $log -Pattern $re).Count -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function Count([string]$log, [string]$re) { if (-not (Test-Path $log)) { return 0 }; @(Select-String -Path $log -Pattern $re).Count }
# A restart every time: the session is what D, E and G are about.
function Launch([int]$n) {
    $script:log = "$ws\$Tag-run$n.log"; $script:logs += $script:log
    Remove-Item -LiteralPath $script:log -EA SilentlyContinue
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$script:log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session") | Out-Null
}
function Close {
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
}
# True when the browser ended by itself within 60 s; otherwise it is force-stopped (a throwaway profile).
function Exited {
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if (-not (Pids).Count) { return $true }
    Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2
    return $false
}
function Markers([string]$log) { @(Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }
# The archive's entries (call as @(Archive)), and its raw text for "unchanged"; waited for past the 2.5 s write.
function Archive { Start-Sleep 5; if (-not (Test-Path -LiteralPath $afile)) { return @() }; @((Get-Content -Raw -Encoding UTF8 -LiteralPath $afile | ConvertFrom-Json).entries) }
function Raw { Start-Sleep 5; if (Test-Path -LiteralPath $afile) { Get-Content -Raw -Encoding UTF8 -LiteralPath $afile } else { "" } }
function Show($e) { "      file: " + (@($e | ForEach-Object { "$($_.reason) $($_.workspace) $($_.url)" }) -join ' | ') }
# How often the server was asked for a page: a restored tab that loads MUST fetch (no-store).
function Requests([string]$n) { if (-not (Test-Path $srvlog)) { return 0 }; @(Select-String -Path $srvlog -SimpleMatch "GET /$n.html").Count }
function WaitReq([string]$n, [int]$atLeast, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Requests $n) -ge $atLeast) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# This run's archive lines, for grading by eye.
function Lines { if (Test-Path $log) { Select-String -Path $log -Pattern "\[workspaces\] (archive|not archived)" | ForEach-Object { "      log: " + ($_.Line -replace '^.*?\] ', '') } } }

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
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
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
  // One character as itself (KEYEVENTF_UNICODE), whatever the keyboard layout.
  static void Char(char c, bool up) { INPUT i = new INPUT(); i.type = 1; i.u.ki.scan = c; i.u.ki.flags = 4u | (up ? 2u : 0u); Send(i); }
  static string Desktop() {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);
    CloseDesktop(d);
    return name.ToString() == "Default" ? null : "the input desktop is '" + name + "'";
  }

  public static void Topmost(IntPtr hwnd, bool on) { SetWindowPos(hwnd, new IntPtr(on ? -1 : -2), 0, 0, 0, 0, 0x0013); }
  // Restored, placed and topmost, not activated.
  public static void Place(IntPtr h, int x, int y, int w, int height) { ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), x, y, w, height, 0x0010); }
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

  // A RIGHT click, with Click's guards (row K: the tab menu).
  public static string RightClick(IntPtr hwnd, int x, int y) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    string e = Desktop(); if (e != null) return e;
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "another window is at " + x + "," + y;
    POINT saved; GetCursorPos(out saved);
    try {
      Move(x, y); Thread.Sleep(150);
      Button(0x0008); Thread.Sleep(60); Button(0x0010); Thread.Sleep(600);
    } finally { SetCursorPos(saved.x, saved.y); }
    return "right-clicked";
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

  // `text`, then Delete (an inline autocompletion) and Enter, to the window in front -- only when it is the
  // browser's.
  public static string TypeEnter(uint pid, string text) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    foreach (char c in text) { Char(c, false); Char(c, true); Thread.Sleep(20); }
    Key(0x2E, false); Key(0x2E, true); Thread.Sleep(100);
    Key(0x0D, false); Key(0x0D, true); Thread.Sleep(500);
    return "typed";
  }

  // Alt+key to the window in front -- only when it is the browser's (Alt+F: the app menu, accelerator_table.cc).
  public static string AltKey(uint pid, ushort vk) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    Key(0x12, false); Key(vk, false); Key(vk, true); Key(0x12, true);
    Thread.Sleep(1000);
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
# A guarded click on a list tab of $script:win: activates it and brings the window in front.
function ClickTab([string]$tab) {
    $n = Node $tab 0x25
    if (-not $n) { return "no list tab '$tab'" }
    [Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2))
}
# Waits for a second window, returns it.
function Second { $w = [IntPtr]::Zero; $t = Get-Date; while (((Get-Date) - $t).TotalSeconds -lt 20 -and $w -eq [IntPtr]::Zero) { Start-Sleep 1; $w = [Input]::Other((Pid1), $script:win) }; return $w }
function WaitWindows([int]$n, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Pids).Count -and [Input]::Windows((Pid1)) -eq $n) { return $true }; Start-Sleep 1 }
    return $false
}
# The window whose tabs include `tab`, or zero. Both browser windows by enumeration, not MainWindowHandle:
# after a restore that can be neither of them, and the second window was then never looked at (the first run).
function WindowWith([string]$tab, [int]$s = 15) {
    $keep = $script:win; $found = [IntPtr]::Zero; $t = Get-Date
    while ($found -eq [IntPtr]::Zero -and ((Get-Date) - $t).TotalSeconds -lt $s) {
        $a = [Input]::Other((Pid1), [IntPtr]::Zero)
        foreach ($h in @($a, [Input]::Other((Pid1), $a))) {
            if ($h -eq [IntPtr]::Zero) { continue }
            $script:win = $h
            if (HasTab $tab) { $found = $h; break }
        }
        if ($found -eq [IntPtr]::Zero) { Start-Sleep 1 }
    }
    $script:win = $keep
    return $found
}
function Alive { if (-not (Pids).Count) { Verdict "the browser is still running" $false; throw "the browser is gone -- a crash? See $log" } }

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running"; exit 1 }
"binary: $OutDir, $((Get-Item $exe).LastWriteTime)"
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path "$prof\Default\Preferences")) { "ABORT: copy failed"; exit 1 }

# P: the profile answers the question, or nothing below means anything
$show = @(& python "$here\set-workspaces-pref.py" $prof --show 2>&1)
$ready = $LASTEXITCODE -eq 0
$show | ForEach-Object { "      $_" }
Verdict "P: enabled, vertical, Work ($work) in the list -- set-workspaces-pref.py --show exits 0" ($ready -and (($show -join "`n") -match [regex]::Escape($work)))
Verdict "P: no archive file in the copied profile" (-not (Test-Path -LiteralPath $afile))
if ($script:failed) { "$($script:failed) FAIL"; exit $script:failed }

$null = New-Item -ItemType Directory -Force $pages
foreach ($n in "one", "two", "three", "four") {
    Set-Content -Encoding UTF8 -Path "$pages\$n.html" -Value "<!doctype html><title>E14d1 $n</title><h1>E14d1 $n</h1>"
}
# http.server with caching off, so a restored tab that loads MUST fetch (and so be logged).
Set-Content "$pages\serve.py" -Encoding utf8 @'
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
'@
Remove-Item -LiteralPath $srvlog -EA SilentlyContinue
$server = Start-Process -FilePath python -ArgumentList @("-u", "$pages\serve.py", "$port", $pages) -PassThru -WindowStyle Hidden -RedirectStandardError $srvlog
Start-Sleep 2
$probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$port/").StatusCode } catch { 0 }
if ($probe -ne 200 -or $server.HasExited) { Stop-Process -Id $server.Id -EA SilentlyContinue; "ABORT: the pages are not served on port $port"; exit 1 }
try {
    # ---- run 1: A, B, C, D ------------------------------------------------------------------------------
    Launch 1
    Verdict "setup: the section drew its rows" (WaitLog $log "pins: drew \d+ row\(s\) of 'default'" 30)
    Start-Sleep 3
    $script:win = Hwnd
    [Input]::Topmost($script:win, $true)
    $null = Press "Work" 0x2B
    Verdict "setup: switched to Work" (WaitLog $log "pins: drew \d+ row\(s\) of '$work'" 15)
    # Opened in the running browser, in the workspace it shows: Work.
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "one"), (Url "two")) | Out-Null
    $null = WaitShown "E14d1 two" 30
    "      list: " + ((ShownTabs) -join ', ')
    Verdict "setup: 'E14d1 one' and 'E14d1 two' are Today tabs of Work" (((ShownTabs) -contains "E14d1 one") -and ((ShownTabs) -contains "E14d1 two"))

    # A: a manual close
    "      A: " + (ClickTab "E14d1 one") + ", loaded: " + (WaitReq "one" 1) + ", Ctrl+W " + [Input]::Keys((Pid1), $false, 0x57)
    Alive
    Verdict "A: one 'archived a manual close' in Work" ((WaitCount $log $manual 1 10) -and (Count $log $manual) -eq 1 -and (Count $log $refused) -eq 0)
    Verdict "A: the store began with no file ('archive: no file yet')" (WaitLog $log "archive: no file yet at" 5)
    $e = @(Archive); Show $e
    $x = @($e)[0]
    Verdict "A: the file: 1 entry -- manual, Work, its url, an id, title 'E14d1 one'" ($e.Count -eq 1 -and $x.reason -eq 'manual' -and $x.workspace -eq $work -and $x.url -eq (Url "one") -and [bool]$x.id -and $x.title -eq 'E14d1 one')

    # B: an untouched New Tab page has no address to go back to
    $n = Count $log $archived
    "      B: Ctrl+T " + [Input]::Keys((Pid1), $false, 0x54)
    Start-Sleep 2
    "      B: Ctrl+W " + [Input]::Keys((Pid1), $false, 0x57)
    Verdict "B: 'not archived: an untouched New Tab page'" (WaitLog $log "not archived: an untouched New Tab page" 10)
    Verdict "B: no new 'archived' line; the file still 1 entry" ((Count $log $archived) -eq $n -and @(Archive).Count -eq 1)

    # C: Ctrl+Shift+T takes the close back out of the archive
    "      C: Ctrl+Shift+T " + [Input]::Keys((Pid1), $true, 0x54)
    Verdict "C: one 'a reopened close leaves the archive'" ((WaitCount $log $reopened 1 10) -and (Count $log $reopened) -eq 1)
    Verdict "C: 'E14d1 one' is back in Work's list" (WaitShown "E14d1 one" 15)
    $e = @(Archive); Show $e
    Verdict "C: the file: A's entry gone (0 entries)" ($e.Count -eq 0)

    # K: the tab menu's "Close" -- at .52 it passed `true` as close TYPES and reached neither Recently Closed
    # nor the archive (Chromium main's fix, backported in 47; found by the owner check's rehearsal). Then
    # Ctrl+Shift+T puts the page back, so D starts from the same two windows as before.
    $nm = Count $log $manual; $nr = Count $log $reopened
    $n = Node "E14d1 one" 0x25
    $rc = if ($n) { [Input]::RightClick($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2)) } else { "no tab 'E14d1 one'" }
    Start-Sleep 1
    "      K: $rc, " + (Msaa @("-Popup", "-Name", "Close Ctrl+W"))
    Verdict "K: the tab menu's Close is archived -- one more '$manual'" ((WaitCount $log $manual ($nm + 1) 10) -and (Count $log $manual) -eq ($nm + 1))
    $e = @(Archive); Show $e
    Verdict "K: the file: 1 entry, manual, 'E14d1 one'" ($e.Count -eq 1 -and $e[0].reason -eq 'manual' -and $e[0].url -eq (Url "one"))
    "      K: Ctrl+Shift+T " + [Input]::Keys((Pid1), $true, 0x54)
    Verdict "K: Ctrl+Shift+T brings it back and takes it out ('$reopened')" ((WaitShown "E14d1 one" 15) -and (WaitCount $log $reopened ($nr + 1) 10) -and @(Archive).Count -eq 0)

    # D: Exit with two windows -- the session keeps both. Window 1 in front first, so window 2 opens on
    # Work (E15e); "three" is its active page, "four" never activated.
    "      D: " + (ClickTab "E14d1 one")
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "three"), (Url "four")) | Out-Null
    $w1 = $script:win; $w2 = Second; Alive
    $d2 = @()
    if ($w2 -ne [IntPtr]::Zero) { $script:win = $w2; $null = WaitShown "E14d1 four" 20; $d2 = ShownTabs; $script:win = $w1 }
    "      D: window 2: " + ($d2 -join ', ')
    $null = WaitReq "three" 1
    Verdict "D: two windows, window 2 with 'E14d1 three' and 'E14d1 four'" ([Input]::Windows((Pid1)) -eq 2 -and ($d2 -contains "E14d1 three") -and ($d2 -contains "E14d1 four"))
    $n = Count $log $archived; $raw = Raw; $tabs = (TabCount $w1) + (TabCount $w2)
    "      D: $tabs tab(s) in the two windows"
    "      D: " + (ClickTab "E14d1 one") + ", Ctrl+L " + [Input]::Keys((Pid1), $false, 0x4C) + ", chrome://quit " + [Input]::TypeEnter((Pid1), "chrome://quit")
    Verdict "D: the browser exited (chrome://quit -> chrome::AttemptExit)" (Exited)
    # The control: the door saw every tab of BOTH windows (A-C log neither line).
    Verdict "D: the door refused every tab of both windows that is not a favorite ($tabs) -- 'the browser is quitting' or 'the session keeps the last window's tabs'" ($tabs -ge 4 -and (Count $log $atExit) -ge $tabs)
    Verdict "D: nothing archived -- no new 'archived' line" ((Count $log $archived) -eq $n)
    Verdict "D: the file unchanged" ((Raw) -eq $raw)
    Lines
    $three = Requests "three"; $four = Requests "four"

    # ---- run 2: E, F, G ---------------------------------------------------------------------------------
    $script:win = [IntPtr]::Zero
    Launch 2
    Verdict "E: both windows came back" (WaitWindows 2 60)
    Alive
    # The control: a restored tab that loads is seen by the server, so 0 requests below means never loaded.
    Verdict "E: window 2's active page 'E14d1 three' loaded at the restart (the request log sees loads)" (WaitReq "three" ($three + 1) 30)
    Start-Sleep 3
    Verdict "E: 'E14d1 four' NOT requested since the restart -- never loaded" ((Requests "four") -eq $four)
    # Window 2 by its LOADED page: a never-loaded tab is named by its address, not its title (the second run:
    # "127.0.0.1:<port>/four.html").
    $w2 = WindowWith "E14d1 three"
    if ($w2 -eq [IntPtr]::Zero) {
        # Say what each window does hold, so a name that differs is visible rather than guessed.
        $a = [Input]::Other((Pid1), [IntPtr]::Zero)
        foreach ($h in @($a, [Input]::Other((Pid1), $a))) {
            if ($h -eq [IntPtr]::Zero) { continue }
            $script:win = $h
            "      window ${h}: " + (@(Nodes | Where-Object { $_.role -eq 0x25 } | ForEach-Object { $_.name + $(if ($_.hidden) { ' (hidden)' }) }) -join ', ')
        }
        throw "no window holds 'E14d1 three'"
    }
    $w1 = [Input]::Other((Pid1), $w2)
    [Input]::Place($w1, 0, 0, 1280, 1400); [Input]::Place($w2, 1280, 0, 1280, 1400)
    # Brought in front by a click on its ACTIVE page: a click on "four" would load it.
    $script:win = $w2; $null = WaitShown "E14d1 three" 15
    "      E: " + (ClickTab "E14d1 three") + ", Ctrl+Shift+W " + [Input]::Keys((Pid1), $true, 0x57)
    $script:win = $w1
    Verdict "E: two 'archived a window close' in Work" ((WaitCount $log $window 2 15) -and (Count $log $window) -eq 2 -and (Count $log $refused) -eq 0)
    Verdict "E: window 1 stays" (WaitWindows 1)
    Verdict "E: the store loaded the file's 0 entries ('archive: loaded 0 entr...')" (WaitLog $log "archive: loaded 0 entr" 5)
    $e = @(Archive); Show $e
    Verdict "E: the file: 2 entries, window, Work -- 'E14d1 three' and the never-loaded 'E14d1 four'" ($e.Count -eq 2 -and @($e | Where-Object { $_.reason -eq 'window' -and $_.workspace -eq $work }).Count -eq 2 -and @($e.url) -contains (Url "three") -and @($e.url) -contains (Url "four"))
    Verdict "E: 'E14d1 four' still never requested -- archived at its address without a load" ((Requests "four") -eq $four)

    # F: Ctrl+Shift+T reopens the window and takes both closes back out
    "      F: " + (ClickTab "E14d1 one") + ", Ctrl+Shift+T " + [Input]::Keys((Pid1), $true, 0x54)
    $w2 = Second; Alive
    Verdict "F: window 2 came back" ($w2 -ne [IntPtr]::Zero)
    Verdict "F: two 'a reopened close leaves the archive'" ((WaitCount $log $reopened 2 15) -and (Count $log $reopened) -eq 2)
    $e = @(Archive); Show $e
    Verdict "F: the file: both entries gone (0 entries)" ($e.Count -eq 0)

    # G: window 2 closed again, then the last window, which the session keeps
    if ($w2 -ne [IntPtr]::Zero) {
        [Input]::Place($w2, 1280, 0, 1280, 1400)
        $script:win = $w2; $null = WaitShown "E14d1 three" 15
        "      G: " + (ClickTab "E14d1 three") + ", Ctrl+Shift+W " + [Input]::Keys((Pid1), $true, 0x57)
        $script:win = $w1
    }
    Verdict "G: window 2 closed again -- 2 more 'archived a window close' lines, one window left" ((WaitCount $log $window 4 15) -and (Count $log $window) -eq 4 -and (WaitWindows 1))
    $e = @(Archive); Show $e
    Verdict "G: the file: 2 window entries" ($e.Count -eq 2 -and @($e | Where-Object { $_.reason -eq 'window' }).Count -eq 2)
    $n = Count $log $archived; $raw = Raw
    "      G: " + (ClickTab "E14d1 one") + ", Ctrl+Shift+W (the last window) " + [Input]::Keys((Pid1), $true, 0x57)
    Verdict "G: '$kept'" (WaitLog $log $kept 15)
    Verdict "G: the browser exited with its last window" (Exited)
    Verdict "G: nothing archived -- no new 'archived' line, the file unchanged" ((Count $log $archived) -eq $n -and (Raw) -eq $raw)
    Lines

    # ---- run 3: G's restart, I, J --------------------------------------------------------------------------
    $script:win = [IntPtr]::Zero
    Launch 3
    $null = WaitWindows 1 60; Alive
    $null = WaitLog $log "pins: drew \d+ row\(s\) of" 30
    Start-Sleep 3
    $script:win = Hwnd
    Verdict "G: after a restart the last window's tabs are back: 'E14d1 one', 'E14d1 two'" ((HasTab (PageTab "one")) -and (HasTab (PageTab "two")))

    # I: a pinned item's page is never archived, not even by a window close that archives the window's Today
    # pages (Arc; design 5; review, LOCAL.md 52). Window 2 with "three"; its section's "Example A" row (every
    # workspace of the smoke profile has one) pressed through MSAA opens the item's page there.
    $w1 = $script:win
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "three")) | Out-Null
    $w2 = Second; Alive
    if ($w2 -ne [IntPtr]::Zero) {
        $script:win = $w2; $null = WaitShown "E14d1 three" 20; Start-Sleep 2
        "      I: " + (Press "Example A" 0x24)
        $script:win = $w1
    }
    Verdict "I: window 2 opened the pinned item's page ('pins: opened item')" (WaitLog $log "pins: opened item 'a\d+'" 10)
    $ids = @(@(Archive) | ForEach-Object { $_.id })
    if ($w2 -ne [IntPtr]::Zero) { [Input]::CloseWindow($w2) }
    Verdict "I: window 2 closed by its X, window 1 stays" ($w2 -ne [IntPtr]::Zero -and (WaitWindows 1))
    Verdict "I: one '$pinned'" ((WaitCount $log $pinned 1 10) -and (Count $log $pinned) -eq 1)
    Verdict "I: one 'archived a window close' -- window 2's Today page, and nothing else" ((WaitCount $log "archived a window close in '" 1 10) -and (Count $log $archived) -eq 1 -and (Count $log $refused) -eq 0)
    $e = @(Archive); Show $e
    $new = @($e | Where-Object { $ids -notcontains $_.id })
    Verdict "I: the file gains only 'E14d1 three' (1 entry, window) -- not the pinned item's page" ($new.Count -eq 1 -and $new[0].reason -eq 'window' -and $new[0].url -eq (Url "three"))

    # J: the app menu's Exit with two windows. chrome::AttemptUserExit, unlike chrome://quit (D), never sets
    # IsTryingToQuit; BrowserCloseManager shuts the session service down before any window closes, so the session
    # keeps both windows and nothing may be archived (review, LOCAL.md 52). Window 2 with "four", brought in front
    # by a click on it; Alt+F opens the app menu (accelerator_table.cc), its Exit (IDS_EXIT) is pressed through
    # MSAA in the menu's window.
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "four")) | Out-Null
    $w2 = Second; Alive
    $n = Count $log $archived; $nk = Count $log $kept; $raw = Raw
    $item = $null; $tabs = 0
    if ($w2 -ne [IntPtr]::Zero) {
        [Input]::Place($w1, 0, 0, 1280, 1400); [Input]::Place($w2, 1280, 0, 1280, 1400)
        $script:win = $w2; $null = WaitShown "E14d1 four" 20
        $tabs = (TabCount $w1) + (TabCount $w2); "      J: $tabs tab(s) in the two windows"
        "      J: " + (ClickTab "E14d1 four") + ", Alt+F " + [Input]::AltKey((Pid1), 0x46)
        # Helium moves Exit into "More tools" (helium/ui/app-menu-model.patch): open that submenu first; a closed
        # submenu's items are not in the menu's tree (the first run: "no 'Exit' in the menu").
        Start-Sleep 1
        "      J: More tools " + (Msaa @("-Popup", "-Name", "More tools"))
        Start-Sleep 1
        $item = @(Msaa @("-Popup", "-List") | ForEach-Object { if ($_ -match '^\s*(Exit)\|0x') { $Matches[1] } }) | Select-Object -First 1
        if ($item) { "      J: " + (Msaa @("-Popup", "-Name", $item)) } else { "      J: (no 'Exit' in the menu)" }
    }
    Verdict "J: the app menu offered 'Exit'" ([bool]$item)
    Verdict "J: the browser exited (the app menu's Exit -> chrome::AttemptUserExit)" (Exited)
    Verdict "J: nothing archived -- no new 'archived' line, the file unchanged" ((Count $log $archived) -eq $n -and (Raw) -eq $raw)
    # The control: every page of both windows ('one', 'two', 'four' at least) passed the door and was refused.
    Verdict "J: every tab of both windows that is not a favorite ($tabs) refused -- new '$kept'" ($tabs -ge 3 -and (Count $log $kept) -ge ($nk + $tabs))
    Lines

    # ---- run 4: J's restart; H, Workspaces off --------------------------------------------------------------
    $pref = @(& python "$here\set-workspaces-pref.py" $prof false 2>&1)
    $ok = $LASTEXITCODE -eq 0
    $pref | ForEach-Object { "      $_" }
    Verdict "H: Workspaces switched off in the profile (set-workspaces-pref.py false)" $ok
    $raw = Raw; $two = Requests "two"
    $script:win = [IntPtr]::Zero
    Launch 4
    Verdict "J: after a restart both windows are back -- the session kept them" (WaitWindows 2 60)
    Alive
    # J's second window first, by its X while window 1 stays: with Workspaces off not even that is archived.
    $w2 = WindowWith "E14d1 four" 30
    if ($w2 -ne [IntPtr]::Zero) { [Input]::CloseWindow($w2) }
    Verdict "H: J's second window closed by its X, window 1 stays" ($w2 -ne [IntPtr]::Zero -and (WaitWindows 1))
    Start-Sleep 5
    $script:win = Hwnd
    [Input]::Topmost($script:win, $true)
    # The control: the close really happened, so "no archived line" below is about a close.
    $c = ClickTab (PageTab "two"); $l = WaitReq "two" ($two + 1); $k = [Input]::Keys((Pid1), $false, 0x57)
    "      H: $c, loaded: $l, Ctrl+W $k"
    Start-Sleep 5
    Verdict "H: the page clicked, loaded, then Ctrl+W sent" ($c -eq "clicked" -and $l -and $k -eq "sent")
    Verdict "H: the page's tab is gone" (-not (HasTab "E14d1 two") -and -not (HasTab "127.0.0.1:$port/two.html"))
    Verdict "H: no 'archived' line with Workspaces off" ((Count $log $archived) -eq 0)
    [Input]::Topmost($script:win, $false)
    Close
    Verdict "H: the file unchanged" ((Raw) -eq $raw)
    Lines
} catch {
    "ABORT: $_"
    $script:failed++
} finally {
    if ((Pids).Count) { Close }
    Stop-Process -Id $server.Id -EA SilentlyContinue
}
foreach ($l in $script:logs) { Verdict "M: 0 markers in $(Split-Path -Leaf $l)" ((Test-Path $l) -and (Markers $l) -eq 0) }
if ($script:failed) { "$($script:failed) FAIL" } else { "ALL PASS" }
exit $script:failed
