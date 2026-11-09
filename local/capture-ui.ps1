param([string]$OutDir = "Default", [string]$Tag = "before", [ValidateSet("System", "Light", "Dark")][string]$Scheme = "System",
      [ValidateRange(30, 48)][int]$RowHeight = 0, [switch]$Dump)
# Screenshots of the fork's own UI for a design review (LOCAL.md 60), and the "after" set to compare once a
# redesign is built: a throwaway demo profile (local/demo-profile.py: made-up workspaces, pinned rows, folders,
# an archive; nothing personal), the window placed at 1280x860 top-left and topmost, then one PNG per state in
# <local-path>\Helium-workspace\ui-shots\<Tag>[-light|-dark]\: 01 home, 02 the bar's + menu, 03 a workspace's menu, 04 its
# "Edit workspace" bubble, 05 Work, 06 the Archive, 07 the strip collapsed, 08 zen mode (the floating sidebar,
# slid in), 09-11 a Today tab's, a pinned page's and a folder's menu, 12 Workspace settings, 13 the + menu's "Find
# tabs and pages" pressed. Each PNG holds the window and any open menu/bubble.
# Buttons are pressed through MSAA (msaa-press.ps1); the right-click, the left-click fallback and the zen reveal
# are real input, guarded as in check-e15d3-auto.ps1 (the screen unlocked, the fork's window under the point) --
# so: screen unlocked, hands off. The display is kept on for the run (it may be off: the run is unattended).
# Windows PowerShell 5.1 (System.Drawing). -Scheme sets Chromium's appearance setting in the demo profile
# (System follows Windows; --force-dark-mode would add nothing on a dark system). -RowHeight seeds E18's
# helium.workspaces.tab_row_height (30 compact .. 48; 42 roomy) and adds -h<N> to the names, e.g.
# ui-shots\<Tag>-light-h42; without it nothing is written: compact. -Dump also writes <shots>\menus.txt: each
# menu's items in order and the settings bubble's focus (check-101.ps1 grades it).
$ErrorActionPreference = "Stop"
$ws    = "<local-path>\Helium-workspace"
$sfx   = if ($Scheme -ne "System") { "-" + $Scheme.ToLower() } else { "" }
if ($RowHeight) { $sfx += "-h$RowHeight" }
$demo  = @("--scheme", $Scheme.ToLower()) + $(if ($RowHeight) { @("--row-height", [string]$RowHeight) } else { @() })
$prof  = "$ws\testprofile-ui-$Tag$sfx"
$shots = "$ws\ui-shots\$Tag$sfx"
$exe   = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$log   = "$ws\ui-$Tag$sfx.log"

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class UiShot {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);

  // ES_CONTINUOUS | ES_DISPLAY_REQUIRED while on; ES_CONTINUOUS alone clears it. This process's request only.
  public static void Awake(bool on) { SetThreadExecutionState(on ? 0x80000002u : 0x80000000u); }

  // Physical pixels, as MSAA gives the fork's boxes and as the screen is copied.
  static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }

  // Restored, placed and topmost, not activated; or topmost off.
  public static void Place(IntPtr h, int x, int y, int w, int height) { Aware(); ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), x, y, w, height, 0x0010); }
  public static void NotTopmost(IntPtr h) { SetWindowPos(h, new IntPtr(-2), 0, 0, 0, 0, 0x0013); }
  public static void Close(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }  // WM_CLOSE

  // The process's visible windows other than `main`: its open menus and bubbles.
  public static IntPtr[] Popups(uint pid, IntPtr main) {
    var found = new System.Collections.Generic.List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p); RECT r;
      if (p == pid && h != main && IsWindowVisible(h) && GetWindowRect(h, out r) && r.r > r.l && r.b > r.t) found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found.ToArray();
  }

  // One PNG of `main` and every window of the process on screen with it (menus, bubbles). Whatever else the
  // rectangle holds -- the desktop behind a menu that hangs outside the window -- is painted grey: a shot
  // carries the browser's windows and nothing of the PC's (the polish batch, LOCAL.md 129).
  public static string Shot(uint pid, IntPtr main, string path) {
    Aware();
    var rects = new System.Collections.Generic.List<RECT>();
    RECT u; GetWindowRect(main, out u); rects.Add(u);
    foreach (IntPtr h in Popups(pid, main)) { RECT r; GetWindowRect(h, out r); rects.Add(r); u.l = Math.Min(u.l, r.l); u.t = Math.Min(u.t, r.t); u.r = Math.Max(u.r, r.r); u.b = Math.Max(u.b, r.b); }
    u.l = Math.Max(u.l, 0); u.t = Math.Max(u.t, 0);
    using (var bmp = new Bitmap(u.r - u.l, u.b - u.t))
    using (var g = Graphics.FromImage(bmp)) {
      g.CopyFromScreen(u.l, u.t, 0, 0, bmp.Size);
      using (var keep = new Region(Rectangle.Empty)) {
        foreach (RECT r in rects) keep.Union(new Rectangle(r.l - u.l, r.t - u.t, r.r - r.l, r.b - r.t));
        g.ExcludeClip(keep);
        g.Clear(Color.FromArgb(128, 128, 128));
      }
      bmp.Save(path, ImageFormat.Png);
    }
    return (u.r - u.l) + "x" + (u.b - u.t);
  }

  static void Send(INPUT i) { SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT))); }
  static void Button(uint flags) { INPUT i = new INPUT(); i.type = 0; i.u.mi.flags = flags; Send(i); }
  static void Key(ushort vk) { INPUT i = new INPUT(); i.type = 1; i.u.ki.vk = vk; Send(i); i.u.ki.flags = 2; Send(i); }

  // Null when input may be sent at (x, y): the user's unlocked desktop, `hwnd` under the point; else why not.
  static string Guard(IntPtr hwnd, int x, int y) {
    Aware();
    IntPtr d = OpenInputDesktop(0, false, 0x0001);
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed); CloseDesktop(d);
    if (name.ToString() != "Default") return "the input desktop is '" + name + "'";
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "another window is at " + x + "," + y;
    return null;
  }

  // A right (or left) click at (x, y), guarded; the cursor is put back.
  public static string Click(IntPtr hwnd, int x, int y, bool right) {
    string e = Guard(hwnd, x, y); if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    try {
      SetCursorPos(x, y); Thread.Sleep(150);
      POINT c; GetCursorPos(out c);
      if (Math.Abs(c.x - x) > 2 || Math.Abs(c.y - y) > 2) return "the cursor went to " + c.x + "," + c.y;
      if (right) { Button(0x0008); Thread.Sleep(60); Button(0x0010); }  // RIGHTDOWN, RIGHTUP
      else { Button(0x0002); Thread.Sleep(60); Button(0x0004); }        // LEFTDOWN, LEFTUP
      Thread.Sleep(500);
    } finally { SetCursorPos(saved.x, saved.y); }
    return right ? "right-clicked" : "clicked";
  }

  // A real mouse MOVE to (x, y), guarded, and left there (zen mode slides its sidebar in on a move, as
  // check-e16-auto.ps1's MoveTo); null, or why not. The caller puts the cursor back with SetCursor.
  public static string MoveTo(IntPtr hwnd, int x, int y) {
    string e = Guard(hwnd, x, y); if (e != null) return e;
    INPUT i = new INPUT(); i.type = 0; i.u.mi.flags = 0x0001 | 0x8000 | 0x4000;  // MOVE | ABSOLUTE | VIRTUALDESK
    int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
    i.u.mi.dx = (int)(((long)(x - vx) * 65535) / (vw - 1));
    i.u.mi.dy = (int)(((long)(y - vy) * 65535) / (vh - 1));
    Send(i); Thread.Sleep(150);
    POINT c; GetCursorPos(out c);
    if (Math.Abs(c.x - x) > 2 || Math.Abs(c.y - y) > 2) return "the cursor went to " + c.x + "," + c.y;
    return null;
  }
  public static int[] Cursor() { Aware(); POINT c; GetCursorPos(out c); return new int[] { c.x, c.y }; }
  public static void SetCursor(int x, int y) { Aware(); SetCursorPos(x, y); }

  // The client area on screen: left, top, width, height (physical pixels).
  public static int[] Client(IntPtr h) {
    Aware(); RECT r; GetClientRect(h, out r); POINT p; p.x = 0; p.y = 0; ClientToScreen(h, ref p);
    return new int[] { p.x, p.y, r.r - r.l, r.b - r.t };
  }

  // A key to the window in front -- only when it is the browser's.
  public static string KeyTo(uint pid, ushort vk) {
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    Key(vk); Thread.Sleep(400); return "sent";
  }
  public static string Escape(uint pid) { return KeyTo(pid, 0x1B); }
}
"@

function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Msaa([string[]]$a, [long]$win = 0) {
  if ($win) { $a += @("-Window", [string]$win) }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof @a
}
# Every node with its box: name, role, hidden, left, top, width, height.
function Nodes([long]$win = 0) {
  @(Msaa @("-List", "-Rect") $win | ForEach-Object {
    if ($_ -match '^\s*(.*)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)$') {
      [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                         l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7] }
    }
  })
}
function Find([string]$re, [int]$role = 0, [long]$win = 0) {
  @(Nodes $win | Where-Object { $_.name -match $re -and ($role -eq 0 -or $_.role -eq $role) -and -not $_.hidden -and $_.h -gt 0 }) | Select-Object -First 1
}
function Press($node, [long]$win = 0) { "$(Msaa @("-Name", $node.name, "-Role", $node.role) $win)" }
# Through MSAA -- or, when the name did not survive MSAA's text round trip (U+2026 may come back as '?'), a
# guarded real click at the node's middle (as check-e14d2-auto.ps1's PressNode).
function PressNode($node, [long]$win = 0) {
  $r = Press $node $win
  if ($r -match '^MSAA: pressed') { return $r }
  $h = if ($win) { [IntPtr]$win } else { $script:win }
  "$r; " + [UiShot]::Click($h, $node.l + [int]($node.w / 2), $node.t + [int]($node.h / 2), $false)
}
function WaitPopups([int]$n, [int]$s = 5) {
  $t = Get-Date
  while (((Get-Date) - $t).TotalSeconds -lt $s) { $p = @([UiShot]::Popups($script:pid0, $script:win)); if ($p.Count -ge $n) { Start-Sleep -Milliseconds 600; return $p }; Start-Sleep -Milliseconds 250 }
  return @([UiShot]::Popups($script:pid0, $script:win))
}
function CloseMenus {
  foreach ($i in 1..3) { if (@([UiShot]::Popups($script:pid0, $script:win)).Count -eq 0) { return }; $null = [UiShot]::Escape($script:pid0) }
  foreach ($h in [UiShot]::Popups($script:pid0, $script:win)) { [UiShot]::Close($h) }
  Start-Sleep -Milliseconds 500
}
function Snap([string]$name) {
  [System.Windows.Forms.Application]::DoEvents()  # the backdrop repainted
  $size = [UiShot]::Shot($script:pid0, $script:win, "$shots\$name.png")
  "  $name.png  $size"
}
# -Dump (part E, check-101.ps1): the open menu `win`'s items in order, a divider (ROLE_SYSTEM_SEPARATOR) as "|", under
# "== <state>" in <shots>\menus.txt.
function Dump([string]$state, [long]$win) {
  if (-not $Dump) { return }
  $items = @(Msaa @("-List") $win | ForEach-Object {
    if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)') { if ($Matches[2] -eq "15") { "|" } elseif ($Matches[2] -eq "C") { $Matches[1] } }
  })
  [IO.File]::AppendAllLines("$shots\menus.txt", [string[]](@("== $state") + $items))
}
# -Dump: what has the focus (UI Automation) as a bubble opens, and after each of two Tabs -- a bubble's Close button
# comes first in its order.
function Focus([string]$state) {
  if (-not $Dump) { return }
  $f = { try { $e = [System.Windows.Automation.AutomationElement]::FocusedElement; "$($e.Current.ControlType.ProgrammaticName) '$($e.Current.Name)'" } catch { "unknown ($_)" } }
  $lines = @("== $state", "focus at open: $(& $f)")
  foreach ($i in 1..2) { $sent = [UiShot]::KeyTo($script:pid0, 0x09); $lines += "focus after Tab ${i} ($sent): $(& $f)" }
  [IO.File]::AppendAllLines("$shots\menus.txt", [string[]]$lines)
}
function Launch([string[]]$more) {
  $null = Start-Process $exe -ArgumentList (@("--user-data-dir=$prof", "--no-first-run", "--no-default-browser-check",
    "--window-position=0,0", "--window-size=1280,860", "--force-color-profile=srgb") + $more)
  $t = Get-Date
  while (((Get-Date) - $t).TotalSeconds -lt 40) {
    $p = Pids
    if ($p.Count) { $h = (Get-Process -Id $p[0]).MainWindowHandle; if ($h -ne [IntPtr]::Zero) { $script:pid0 = [uint32]$p[0]; $script:win = $h; return } }
    Start-Sleep 1
  }
  throw "no browser window in 40 s"
}
function Quit {
  [UiShot]::Close($script:win)
  $t = Get-Date
  while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 40) { Start-Sleep 1 }
  if ((Pids).Count) { throw "the browser did not exit in 40 s" }
}

# ---- guards and the demo profile ---------------------------------------------------------------------------
if (Get-Process chrome -ErrorAction SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running"; exit 1 }
if (-not (Test-Path $exe)) { "ABORT: no $exe"; exit 1 }
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
$lists = & python "$PSScriptRoot\demo-profile.py" $prof @demo
if ($LASTEXITCODE -ne 0) { "ABORT: demo-profile.py failed"; exit 1 }
$i = [array]::IndexOf($lists, "TODAY")
$pins = $lists[1..($i - 1)]; $today = $lists[($i + 1)..($lists.Count - 1)]
$null = New-Item -ItemType Directory -Force $shots

[UiShot]::Awake($true)

# A plain grey window over the whole screen, under the browser (which Place makes topmost after it): a menu's shadow
# margin and a window's invisible resize border are see-through, and the grey is all they show of the PC. Shown
# before the first launch, closed at the end; DoEvents in Snap repaints it.
Add-Type -AssemblyName System.Windows.Forms, UIAutomationClient, UIAutomationTypes
if ($Dump -and (Test-Path -LiteralPath "$shots\menus.txt")) { Remove-Item -LiteralPath "$shots\menus.txt" }
# The script sleeps without pumping the backdrop's messages; after 5 s Windows would swap it for a "not responding"
# ghost, which is not topmost (the first run showed the desktop through the border).
Add-Type -Namespace CaptureUi -Name Ghosting -MemberDefinition '[DllImport("user32.dll")] public static extern void DisableProcessWindowsGhosting();'
[CaptureUi.Ghosting]::DisableProcessWindowsGhosting()
$backdrop = New-Object System.Windows.Forms.Form
$backdrop.FormBorderStyle = "None"; $backdrop.ShowInTaskbar = $false; $backdrop.TopMost = $true
$backdrop.BackColor = [System.Drawing.Color]::FromArgb(128, 128, 128)
$backdrop.StartPosition = "Manual"; $backdrop.Bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$backdrop.Show(); [System.Windows.Forms.Application]::DoEvents()

# ---- warm-up: every pinned row's page once, so its favicon is in the profile; then a fresh window ----------
"warm-up: $($pins.Count + $today.Count) pages"
Launch ($pins + $today)
Start-Sleep 25
Quit
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

# ---- the shots ----------------------------------------------------------------------------------------------
"capture: $shots"
Launch (@("--enable-logging", "--log-file=$log", "--v=0") + $today)
try {
  [UiShot]::Place($script:win, 0, 0, 1280, 860)
  Start-Sleep 10
  Snap "01-home"

  $plus = Find '^New tab, workspace' 0x39
  if ($plus) {
    $null = Press $plus; $menu = @(WaitPopups 1); Snap "02-plus-menu"
    if ($menu.Count) { Dump "02-plus-menu" ([long]$menu[0]) }
    CloseMenus
  } else { "  02: no '+' on the rail" }

  $work = Find '^Work$' 0x2B
  if ($work) {
    $r = [UiShot]::Click($script:win, $work.l + [int]($work.w / 2), $work.t + [int]($work.h / 2), $true)
    $menu = @(WaitPopups 1)
    if ($menu.Count) {
      Snap "03-workspace-menu"; Dump "03-workspace-menu" ([long]$menu[0])
      # "Edit workspace..." (E17a) closes the menu and opens ONE bubble.
      $edit = Find '^Edit workspace' 0 ([long]$menu[0])
      if ($edit) { "  04: " + (PressNode $edit ([long]$menu[0])); Start-Sleep 1; $null = WaitPopups 1; Snap "04-edit-workspace" } else { "  04: no 'Edit workspace' in the menu" }
    } else { "  03: no menu ($r)" }
    CloseMenus
    $null = Press $work; Start-Sleep 3; Snap "05-work"
    $homeBtn = Find '^Home$' 0x2B; if ($homeBtn) { $null = Press $homeBtn; Start-Sleep 2 }  # not $home: that is $HOME
  } else { "  03-05: no 'Work' on the rail" }

  $arch = Find '^Archive$' 0x2B  # the bar's own button (E17a)
  if ($arch) { $null = Press $arch; Start-Sleep 3; Snap "06-archive"; CloseMenus } else { "  06: no Archive button on the bar" }

  # The polish batch's menus review (LOCAL.md 129): a Today tab's menu, a pinned page's, a folder's, and the
  # Workspace settings bubble. A right-click is real input, guarded as the workspace menu's above.
  foreach ($m in @(@("09-tab-menu", '^Hacker News', 0x25), @("10-pinned-page-menu", '^Gmail$', 0), @("11-folder-menu", '^Reading', 0))) {
    $n = Find $m[1] $m[2]
    if (-not $n) { "  $($m[0]): no '$($m[1])' found"; continue }
    $r = [UiShot]::Click($script:win, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    $menu = @(WaitPopups 1)
    if ($menu.Count) { Snap $m[0]; Dump $m[0] ([long]$menu[0]) } else { "  $($m[0]): no menu ($r)" }
    CloseMenus
  }
  $plus = Find '^New tab, workspace' 0x39
  if ($plus) {
    $null = Press $plus
    $menu = @(WaitPopups 1)
    $set = if ($menu.Count) { Find '^Workspace settings' 0 ([long]$menu[0]) }
    if ($set) {
      # A real click, the mouse's way: an MSAA press arrives as Enter, the keyboard's (12k below).
      $r = [UiShot]::Click([IntPtr][long]$menu[0], $set.l + [int]($set.w / 2), $set.t + [int]($set.h / 2), $false)
      if ($r -ne "clicked") { "  12: $r" }
      Start-Sleep 1; $null = WaitPopups 1; Snap "12-settings-bubble"; Focus "12-settings-bubble"
    } else { "  12: no 'Workspace settings' in the + menu" }
    CloseMenus
  }
  # -Dump, 12k: the same bubble opened the keyboard's way (an MSAA press), for its focus only.
  $plus = Find '^New tab, workspace' 0x39
  if ($Dump -and $plus) {
    $null = Press $plus
    $menu = @(WaitPopups 1)
    $set = if ($menu.Count) { Find '^Workspace settings' 0 ([long]$menu[0]) }
    if ($set -and (Press $set ([long]$menu[0])) -match '^MSAA: pressed') { Start-Sleep 1; $null = WaitPopups 1; Focus "12k-settings-keyboard" } else { "  12k: not pressed through MSAA" }
    CloseMenus
  }
  # 13: the + menu's "Find tabs and pages" (part E), the quick search box it opens.
  $plus = Find '^New tab, workspace' 0x39
  if ($plus) {
    $null = Press $plus
    $menu = @(WaitPopups 1)
    $find = if ($menu.Count) { Find '^Find tabs and pages$' 0 ([long]$menu[0]) }
    if ($find) { $null = PressNode $find ([long]$menu[0]); Start-Sleep 1; $null = WaitPopups 1; Snap "13-find" } else { "  13: no 'Find tabs and pages' in the + menu" }
    CloseMenus
  }

  $col = Find 'ollapse' 0x2B
  if ($col) { $null = Press $col; Start-Sleep 2; Snap "07-collapsed"; $exp = Find 'xpand' 0x2B; if ($exp) { $null = Press $exp; Start-Sleep 1 } } else { "  07: no collapse button found" }
} finally {
  CloseMenus
  [UiShot]::NotTopmost($script:win)
  Quit
}

# ---- 08: zen mode, the sidebar floating (not pinned) and slid in by the cursor at the window's left edge ------
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }
$null = & python "$PSScriptRoot\demo-profile.py" $prof @demo --zen
if ($LASTEXITCODE -ne 0) { "  08: demo-profile.py --zen failed" } else {
  Launch $today
  $saved = [UiShot]::Cursor()
  try {
    [UiShot]::Place($script:win, 0, 0, 1280, 860)
    Start-Sleep 10
    $c = [UiShot]::Client($script:win)
    $e = [UiShot]::MoveTo($script:win, $c[0] + 2, $c[1] + [int]($c[3] / 2))  # inside zen mode's 6-DIP side trigger
    if ($e) { "  08: $e" } else { Start-Sleep 1; Snap "08-zen" }
  } finally {
    [UiShot]::SetCursor($saved[0], $saved[1])
    [UiShot]::NotTopmost($script:win)
    Quit
  }
}
$backdrop.Close()
[UiShot]::Awake($false)
"done: $((Get-ChildItem $shots -Filter *.png).Count) PNGs in $shots"
