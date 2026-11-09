param([string]$OutDir = "Default", [string]$Tag = "e15d3-auto")
# E15d.3 without a person (LOCAL.md 49): a Today tab dragged INTO the pinned section is pinned where it is
# dropped. The drags are REAL mouse input (SendInput) -- MSAA can press but not drag -- so every drag is
# guarded: the input desktop must be the user's (not the lock screen), the fork's window must be the one
# under the start AND the end point, and the cursor must land where it was sent (a DPI mismatch would not);
# otherwise nothing is pressed and the step FAILs. The window is made topmost for the run, and the cursor is
# put back. Positions come from MSAA (msaa-press.ps1 -Rect); the pages are served by a local python server,
# since only an http(s) page can be pinned. Graded from the log, the saved pins file and the accessibility
# tree (a pinned page's tab is there, INVISIBLE; its row is shown).
#   From "Work" (not the default workspace), rows: Example A, Smoke folder (open: Wikipedia, github), Closed
#   folder, Example D -- a copy of testprofile-e15b-smoke with five pages opened in Work:
#   A  "E15d3 one" dropped on the upper half of "Example A"  -> pinned FIRST, before Example A
#   B  "E15d3 two" dropped on the middle of "Smoke folder"   -> pinned first INSIDE the folder
#   K  "E15d3 eight" dropped on the middle of "Closed folder" -> pinned first INSIDE it; the folder OPENS and
#      its row is drawn (review #2)
#   C  "E15d3 three" dropped on "+ New Tab"                  -> NOT pinned: "+ New Tab" is the list's
#   E  "E15d3 three" dragged over "Example A", Escape, let go -> NOT pinned
#   N  the "New Tab" page dragged onto "Example A"            -> NOT pinned; the list places it, at the top (#1)
#   X  "New Tab" + ctrl-clicked "E15d3 three" dragged onto "Example A" -> NOTHING pinned, not part (#5)
#   M  "E15d3 four" + ctrl-clicked "E15d3 five" dropped on the upper half of "Example D"
#                                                            -> both pinned before Example D, in list order
#   D  "E15d3 three" dropped on the lower half of "Example D" (the last row) -> pinned at the END
#   W  a SECOND window with "E15d3 nine" and "ten" -- it opens on Work, the workspace of the window in front
#      (E15e, 46): "nine" dragged onto this window's "Example A" -> pinned just before it in Work, its row here; two
#      windows, no third (#6)
#   R  a restart: the rows are still there, their pages hidden in the list
#   G  "E15d3 six" put in a new group (its menu), "E15d3 seven" dropped on it -> in the group, no crash
#   L  first, "E15d3 five" dropped on "E15d3 two" in the list -> reordered, not pinned (E15b's box crashed this)
#   every drag: the browser still runs, in one window (a drag over the section never tears the tab off); 0 markers
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof  = "$ws\testprofile-$Tag"
$exe   = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$pages = "$ws\$Tag-pages"
# Asked of Windows, not fixed: at R5 8765 was taken -- Logi Options+ (LogiPluginService.exe) registers
# http://localhost:8765/ with http.sys, which answered every test page "Bad Request" (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work  = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { "PASS  $name" } else { "FAIL  $name"; $script:failed++ } }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
# The window the steps act on: set once there is one, as MainWindowHandle picks either of two (W).
$script:win = [IntPtr]::Zero
function Msaa([string[]]$a) {
    if ($script:win -ne [IntPtr]::Zero) { $a += @("-Window", [string][long]$script:win) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof @a
}
function Press([string]$name, [int]$role = 0x24) { Msaa @("-Name", $name, "-Role", $role) }
# Every node with its box: name, role, hidden (INVISIBLE), left, top, width, height.
function Nodes {
    @(Msaa @("-List", "-Rect") | ForEach-Object {
        if ($_ -match '^\s*(.*)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                               l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7] }
        }
    })
}
function Node([string]$name, [int]$role) { @(Nodes | Where-Object { $_.name -eq $name -and $_.role -eq $role -and -not $_.hidden -and $_.h -gt 0 }) | Select-Object -First 1 }
# The list's tabs as drawn, top to bottom (favorites, " - Pinned", sit above it).
function ShownTabs { @(Nodes | Where-Object { $_.role -eq 0x25 -and -not $_.hidden -and $_.h -gt 0 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { $_.name }) }
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
function Launch([string]$log, [string[]]$more = @()) {
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    Start-Process $exe -ArgumentList (@("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session") + $more) | Out-Null
}
function Close {
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
}
function Markers([string]$log) { @(Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }
function Pinned([string]$log) { @(Select-String -Path $log -Pattern "\[workspaces\] pins: pinned a tab as item").Count }
# A workspace's rows in the saved file, as "url" per item and "[title: urls...]" per folder. Written 2.5 s
# after a change: waited for.
function SavedWork { Saved $work }
function Saved([string]$guid) {
    Start-Sleep 4
    $d = Get-Content -Raw -Encoding UTF8 "$prof\Default\Workspace Pins" | ConvertFrom-Json
    @($d.workspaces.$guid | ForEach-Object {
        if ($_.type -eq 'folder') { "[" + $_.title + ": " + (@($_.children | ForEach-Object { $_.url }) -join ' ') + "]" } else { $_.url }
    })
}
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
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
  delegate bool EnumProc(IntPtr h, IntPtr l);

  // Physical pixels, as MSAA gives the fork's boxes.
  static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
  static void Send(INPUT i) { SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT))); }
  static void Move(int x, int y) {
    int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
    INPUT i = new INPUT(); i.type = 0;
    i.u.mi.dx = (int)(((long)(x - vx) * 65535) / (vw - 1));
    i.u.mi.dy = (int)(((long)(y - vy) * 65535) / (vh - 1));
    i.u.mi.flags = 0x0001 | 0x8000 | 0x4000;  // MOVE | ABSOLUTE | VIRTUALDESK
    Send(i);
  }
  static void Button(uint flags) { INPUT i = new INPUT(); i.type = 0; i.u.mi.flags = flags; Send(i); }
  static void Key(ushort vk, bool up) { INPUT i = new INPUT(); i.type = 1; i.u.ki.vk = vk; i.u.ki.flags = up ? 2u : 0u; Send(i); }

  // Null when input may be sent at (x, y); else why not.
  static string Guard(IntPtr hwnd, int x, int y) {
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
  // Moves there and checks it got there.
  static string MoveTo(int x, int y) {
    Move(x, y); Thread.Sleep(120);
    POINT p; GetCursorPos(out p);
    if (Math.Abs(p.x - x) > 2 || Math.Abs(p.y - y) > 2) return "the cursor went to " + p.x + "," + p.y + ", not " + x + "," + y;
    return null;
  }

  public static void Topmost(IntPtr hwnd, bool on) { SetWindowPos(hwnd, new IntPtr(on ? -1 : -2), 0, 0, 0, 0, 0x0013); }
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  // Restored, placed and topmost, not activated.
  public static void Place(IntPtr h, int x, int y, int w, int height) { ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), x, y, w, height, 0x0010); }
  public static void CloseWindow(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }  // WM_CLOSE

  public static string Click(IntPtr hwnd, int x, int y, bool ctrl, bool right) {
    Aware();
    string e = Guard(hwnd, x, y); if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    try {
      e = MoveTo(x, y); if (e != null) return e;
      if (ctrl) Key(0x11, false);
      Button(right ? 0x0008u : 0x0002u); Thread.Sleep(60); Button(right ? 0x0010u : 0x0004u);
      if (ctrl) Key(0x11, true);
      Thread.Sleep(400);
    } finally { SetCursorPos(saved.x, saved.y); }
    return "clicked";
  }

  // Press at (x0, y0), move to (x1, y1) in steps, hold, let go -- or press Escape first.
  public static string Drag(IntPtr from, IntPtr to, int x0, int y0, int x1, int y1, bool escape) {
    Aware();
    string e = Guard(from, x0, y0); if (e == null) e = Guard(to, x1, y1); if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    bool down = false;
    try {
      e = MoveTo(x0, y0); if (e != null) return e;
      Button(0x0002); down = true; Thread.Sleep(150);  // LEFTDOWN
      const int steps = 30;
      for (int s = 1; s <= steps; s++) { Move(x0 + (x1 - x0) * s / steps, y0 + (y1 - y0) * s / steps); Thread.Sleep(25); }
      Thread.Sleep(300); Move(x1, y1 + 1); Thread.Sleep(200); Move(x1, y1); Thread.Sleep(600);
      if (escape) { Key(0x1B, false); Key(0x1B, true); Thread.Sleep(400); }
    } finally {
      if (down) { Button(0x0004); Thread.Sleep(300); }  // LEFTUP
      SetCursorPos(saved.x, saved.y);
    }
    return escape ? "dragged, Escape, let go" : "dragged";
  }

  // Escape to the window in front -- only when it is the browser's (a bubble of it, say).
  public static string Escape(uint pid) {
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    Key(0x1B, false); Key(0x1B, true); Thread.Sleep(400);
    return "Escape";
  }

  // A browser window of the process other than `main`, or zero.
  public static IntPtr Other(uint pid, IntPtr main) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      StringBuilder c = new StringBuilder(64); GetClassName(h, c, 64);
      if (p == pid && h != main && IsWindowVisible(h) && c.ToString() == "Chrome_WidgetWin_1" && GetWindow(h, 4) == IntPtr.Zero) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }

  // The visible browser windows of a process: not owned by another window, as a bubble or a menu is.
  public static int Windows(uint pid) {
    int n = 0;
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      StringBuilder c = new StringBuilder(64); GetClassName(h, c, 64);
      if (p == pid && IsWindowVisible(h) && c.ToString() == "Chrome_WidgetWin_1" && GetWindow(h, 4) == IntPtr.Zero) n++;  // GW_OWNER
      return true;
    }, IntPtr.Zero);
    return n;
  }
}
"@

function Hwnd { (Get-Process -Id (Pids)[0]).MainWindowHandle }
# The browser still runs, in one window (a drag over the section never tears the tab off). A crash ends the run.
function Still([string]$step) {
    if (-not (Pids).Count) { Verdict "${step}: the browser is still running" $false; throw "the browser is gone -- a crash? See $log" }
    Verdict "${step}: one window" ([Input]::Windows([uint32](Pids)[0]) -eq 1)
}
# Drags the list tab `tab` to `yfrac` of the node (`name`, `role`): 0.25 = its upper quarter.
function DragTo([string]$tab, [string]$name, [int]$role, [double]$yfrac, [switch]$Escape, [IntPtr]$FromWindow = [IntPtr]::Zero) {
    $toWindow = $script:win
    if ($FromWindow -ne [IntPtr]::Zero) { $script:win = $FromWindow }
    $from = Node $tab 0x25
    $script:win = $toWindow
    $to = Node $name $role
    if (-not $from) { return "no list tab '$tab'" }
    if (-not $to) { return "no node '$name'" }
    $fw = if ($FromWindow -ne [IntPtr]::Zero) { $FromWindow } else { $toWindow }
    [Input]::Drag($fw, $toWindow, $from.l + [int]($from.w / 2), $from.t + [int]($from.h / 2), $to.l + [int]($to.w / 2), $to.t + [int]($to.h * $yfrac), $Escape.IsPresent)
}
function ClickTab([string]$tab, [switch]$Ctrl, [switch]$Right) {
    $n = Node $tab 0x25
    if (-not $n) { return "no list tab '$tab'" }
    [Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $Ctrl.IsPresent, $Right.IsPresent)
}
# Pinned: its tab hidden in the list, a row by its name shown.
function IsPinnedPage([string]$tab) { (-not ((ShownTabs) -contains $tab)) -and [bool](Node $tab 0x24) }

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running"; exit 1 }
"binary: $OutDir, $((Get-Item $exe).LastWriteTime)"

# ---- setup: the smoke profile, five pages, a server ---------------------------------------------------
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path "$prof\Default\Workspace Pins")) { "ABORT: copy failed"; exit 1 }
# Since patch 70 (wish 6c.1) the toolbar draws its own "New Tab" button while this switch is on (the default); step C
# drops on the sidebar's "+ New Tab", found by that name, so the toolbar's is switched off in the copy (LOCAL.md 84).
& python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null
$null = New-Item -ItemType Directory -Force $pages
foreach ($n in "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten") {
    Set-Content -Encoding UTF8 -Path "$pages\$n.html" -Value "<!doctype html><title>E15d3 $n</title><h1>E15d3 $n</h1>"
}
$server = Start-Process python -ArgumentList "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $pages -WindowStyle Hidden -PassThru
$log = "$ws\$Tag.log"
try {
    Launch $log
    Verdict "setup: the section drew its rows" (WaitLog $log "pins: drew \d+ row\(s\) of 'default'" 30)
    Start-Sleep 3
    $null = Press "Work" 0x2B
    Verdict "setup: switched to Work" (WaitLog $log "pins: drew \d+ row\(s\) of '$work'" 15)
    # Opened in the running browser, in the workspace it shows: Work.
    Start-Process $exe -ArgumentList (@("--user-data-dir=$prof") + @("one", "two", "three", "four", "five", "six", "seven", "eight" | ForEach-Object { Url $_ })) | Out-Null
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt 30 -and @((ShownTabs) -match '^E15d3 ').Count -lt 8) { Start-Sleep 2 }
    $tabs0 = ShownTabs
    "      list: " + ($tabs0 -join ', ')
    Verdict "setup: the eight pages are Today tabs of Work" (@($tabs0 -match '^E15d3 ').Count -eq 8)
    Verdict "setup: Work's saved rows are the smoke profile's" (((SavedWork) -join ' | ') -eq 'https://example.com/ | [Smoke folder: https://en.wikipedia.org/ https://github.com/] | [Closed folder: https://hidden.example/] | https://www.iana.org/')
    $script:win = Hwnd
    [Input]::Topmost($script:win, $true)

    # L: a drag within the list -- E15b's box round the section and the list made every such drag crash
    $before = ShownTabs
    "      L: " + (DragTo "E15d3 five" "E15d3 two" 0x25 0.75)
    Still "L"
    $after = ShownTabs
    "      list: " + ($after -join ', ')
    Verdict "L: the list's order changed, the same tabs in it" ((($after -join '|') -ne ($before -join '|')) -and ((@($after | Sort-Object) -join '|') -eq (@($before | Sort-Object) -join '|')))
    Verdict "L: NOT pinned (log)" ((Pinned $log) -eq 0)

    # G: a tab group, made from the tab's menu (pressed through MSAA in the menu's window); a tab dragged into
    # it -- E15b's box made every drag in a group crash too
    "      G: " + (ClickTab "E15d3 six" -Right)
    Start-Sleep 1
    $item = @(Msaa @("-Popup", "-List") | ForEach-Object { if ($_ -match '^\s*(Add tab to new group)\|0x') { $Matches[1] } }) | Select-Object -First 1
    if ($item) { "      " + (Msaa @("-Popup", "-Name", $item)) } else { "      (no 'Add tab to new group' in the menu)" }
    Verdict "G: the tab menu offered 'Add tab to new group'" ([bool]$item)
    Start-Sleep 2
    # A new group opens its name bubble: closed first. In a group a tab is named "<title> - Part of <group>".
    "      G: " + [Input]::Escape([uint32](Pids)[0])
    Start-Sleep 1
    "      G: " + (DragTo "E15d3 seven" "E15d3 six - Part of unnamed group" 0x25 0.5)
    Still "G"
    $groups = @(Msaa @("-List") | Where-Object { $_ -match '(?i)group' -and $_ -notmatch '(?i)add tab|INVISIBLE' })
    $groups | ForEach-Object { "      tree: " + $_.Trim() }
    Verdict "G: a group is drawn in the list" ($groups.Count -ge 1)
    # Dropped INTO the group: the list's drag handed it to the group's own target, the second lookup E15b broke.
    Verdict "G: 'E15d3 seven' joined the group" ([bool](Node "E15d3 seven - Part of unnamed group" 0x25))
    Verdict "G: NOT pinned (log)" ((Pinned $log) -eq 0)

    # A: before the first row
    "      A: " + (DragTo "E15d3 one" "Example A" 0x24 0.25)
    Still "A"
    Verdict "A: pinned (log)" (WaitCount $log "pinned a tab as item" 1 5)
    Verdict "A: its tab left the list, a row 'E15d3 one' is drawn" (IsPinnedPage "E15d3 one")
    $s = SavedWork; "      saved: " + ($s -join ' | ')
    Verdict "A: saved FIRST, before Example A" ($s[0] -eq (Url "one") -and $s[1] -eq 'https://example.com/')

    # B: into the open folder, first
    "      B: " + (DragTo "E15d3 two" "Smoke folder" 0x24 0.5)
    Still "B"
    Verdict "B: pinned (log)" (WaitCount $log "pinned a tab as item" 2 5)
    Verdict "B: its tab left the list, a row 'E15d3 two' is drawn" (IsPinnedPage "E15d3 two")
    $s = SavedWork; "      saved: " + ($s -join ' | ')
    Verdict "B: saved first INSIDE Smoke folder" ($s -contains ("[Smoke folder: " + (Url "two") + " https://en.wikipedia.org/ https://github.com/]"))

    # K: into a CLOSED folder, first. The drag's hold over it opens it mid-drag (C8, patch 71); the drop is in it, so
    # it stays open, and the drop itself opens it too (review #2)
    "      K: " + (DragTo "E15d3 eight" "Closed folder" 0x24 0.5)
    Still "K"
    Verdict "K: pinned (log)" (WaitCount $log "pinned a tab as item" 3 5)
    Verdict "K: its tab left the list, the folder opened, its row 'E15d3 eight' is drawn" (IsPinnedPage "E15d3 eight")
    $s = SavedWork; "      saved: " + ($s -join ' | ')
    Verdict "K: saved first INSIDE Closed folder" ($s -contains ("[Closed folder: " + (Url "eight") + " https://hidden.example/]"))

    # C: "+ New Tab" is the list's
    "      C: " + (DragTo "E15d3 three" "New Tab" 0x2B 0.5)
    Still "C"
    Start-Sleep 2
    Verdict "C: NOT pinned (log)" ((Pinned $log) -eq 3)
    Verdict "C: still a Today tab" ((ShownTabs) -contains "E15d3 three")

    # E: Escape over the rows
    "      E: " + (DragTo "E15d3 three" "Example A" 0x24 0.25 -Escape)
    Still "E"
    Start-Sleep 2
    Verdict "E: NOT pinned (log)" ((Pinned $log) -eq 3)
    Verdict "E: still a Today tab" ((ShownTabs) -contains "E15d3 three")

    # N: a page that cannot be pinned is the list's to place, as before the section (review #1)
    "      N: " + (DragTo "New Tab" "Example A" 0x24 0.25)
    Still "N"
    Start-Sleep 2
    Verdict "N: NOT pinned (log)" ((Pinned $log) -eq 3)
    Verdict "N: still a Today tab, placed by the list at the top" (@(ShownTabs)[0] -eq "New Tab")

    # X: a selection with a page that cannot be pinned: nothing is pinned, not part of it (review #5)
    "      X: " + (ClickTab "New Tab") + ", " + (ClickTab "E15d3 three" -Ctrl) + ", " + (DragTo "E15d3 three" "Example A" 0x24 0.25)
    Still "X"
    Start-Sleep 2
    Verdict "X: NOTHING pinned (log)" ((Pinned $log) -eq 3)
    Verdict "X: both still Today tabs" (((ShownTabs) -contains "New Tab") -and ((ShownTabs) -contains "E15d3 three"))

    # M: two selected tabs, in the list's order
    $order = @(ShownTabs | Where-Object { $_ -eq "E15d3 four" -or $_ -eq "E15d3 five" })
    "      M: " + (ClickTab "E15d3 four") + ", " + (ClickTab "E15d3 five" -Ctrl) + ", " + (DragTo "E15d3 four" "Example D" 0x24 0.25)
    Still "M"
    Verdict "M: both pinned (log)" (WaitCount $log "pinned a tab as item" 5 5)
    Verdict "M: both tabs left the list, both rows drawn" ((IsPinnedPage "E15d3 four") -and (IsPinnedPage "E15d3 five"))
    $s = SavedWork; "      saved: " + ($s -join ' | ')
    $i = [array]::IndexOf($s, 'https://www.iana.org/')
    $want = @($order | ForEach-Object { Url ($_ -replace '^E15d3 ', '') })
    Verdict "M: saved just before Example D, in the list's order ($($order -join ', '))" ($i -ge 2 -and $s[$i - 2] -eq $want[0] -and $s[$i - 1] -eq $want[1])

    # D: the lower half of the last row: the end
    "      D: " + (DragTo "E15d3 three" "Example D" 0x24 0.75)
    Still "D"
    Verdict "D: pinned (log)" (WaitCount $log "pinned a tab as item" 6 5)
    Verdict "D: its tab left the list, a row 'E15d3 three' is drawn" (IsPinnedPage "E15d3 three")
    $s = SavedWork; "      saved: " + ($s -join ' | ')
    Verdict "D: saved LAST" ($s[-1] -eq (Url "three"))

    # W: from a second window into this one's rows (review #6). The new window opens on Work, this window's
    # workspace (E15e); before 46 it opened on Home and this step pressed Home here first (LOCAL.md 49).
    $w1 = $script:win
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "nine"), (Url "ten")) | Out-Null
    $w2 = [IntPtr]::Zero; $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt 20 -and $w2 -eq [IntPtr]::Zero) { Start-Sleep 1; $w2 = [Input]::Other([uint32](Pids)[0], $w1) }
    Verdict "W: a second window opened" ($w2 -ne [IntPtr]::Zero)
    if ($w2 -ne [IntPtr]::Zero) {
        [Input]::Place($w1, 0, 0, 1280, 1400); [Input]::Place($w2, 1280, 0, 1280, 1400)
        Verdict "W: the second window opened on Work (E15e)" (WaitLog $log "a window opens on workspace '$work'" 15)
        $script:win = $w2; $t = Get-Date
        while (((Get-Date) - $t).TotalSeconds -lt 20 -and -not ((ShownTabs) -contains "E15d3 nine")) { Start-Sleep 1 }
        "      W: window 2: " + ((ShownTabs) -join ', ')
        $script:win = $w1
        "      W: " + (DragTo "E15d3 nine" "Example A" 0x24 0.25 -FromWindow $w2)
        if (-not (Pids).Count) { Verdict "W: the browser is still running" $false; throw "the browser is gone -- a crash? See $log" }
        Verdict "W: two windows -- the tab was not torn off into a third" ([Input]::Windows([uint32](Pids)[0]) -eq 2)
        Verdict "W: pinned (log)" (WaitCount $log "pinned a tab as item" 7 5)
        Verdict "W: its row 'E15d3 nine' is drawn in THIS window, its page hidden here" (IsPinnedPage "E15d3 nine")
        $s = SavedWork; "      saved: " + ($s -join ' | ')
        Verdict "W: saved just before Example A, where it was dropped" ($s[[array]::IndexOf($s, 'https://example.com/') - 1] -eq (Url "nine"))
        [Input]::CloseWindow($w2)
        $t = Get-Date
        while (((Get-Date) - $t).TotalSeconds -lt 20 -and [Input]::Windows([uint32](Pids)[0]) -gt 1) { Start-Sleep 1 }
    }

    [Input]::Topmost($script:win, $false)
    Close
    Verdict "run: 0 markers" ((Markers $log) -eq 0)

    # R: a restart
    $script:win = [IntPtr]::Zero
    $logR = "$ws\$Tag-R.log"; Launch $logR
    $null = WaitLog $logR "pins: drew \d+ row\(s\) of '$work'" 30
    Start-Sleep 5
    foreach ($n in "one", "two", "three", "four", "five", "eight", "nine") {
        Verdict "R: 'E15d3 $n' is a row again, its page hidden in the list" (IsPinnedPage "E15d3 $n")
    }
    Close
    Verdict "R: 0 markers" ((Markers $logR) -eq 0)
} catch {
    "ABORT: $_"
    $script:failed++
} finally {
    if ((Pids).Count) { [Input]::Topmost((Hwnd), $false); Close }
    Stop-Process -Id $server.Id -EA SilentlyContinue
}
if ($script:failed) { "$($script:failed) check(s) FAILED" } else { "ALL PASS" }
