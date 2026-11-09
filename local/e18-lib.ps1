# What the three E18 checks share: check-e18-auto.ps1, check-e18.ps1 (the owner's) and check-e18-driver.ps1 (its
# rehearsal) dot-source it, and so do check-93.ps1 and check-e14d3-auto.ps1 (PopupWindows, Controls). Functions only: none reads a script's variables, and nothing is compiled until a script
# calls E18InputType. (The prefs writer they share is prefs.py beside it.)

# The guarded real input (SendInput) and the window calls, compiled once per process ("-as [type]"): input is sent
# only on the user's unlocked desktop, with the browser's window under the point (or in front, for keys), the cursor
# put back -- as in check-e15d3-auto.ps1.
function E18InputType {
    if ("E18Input" -as [type]) { return }
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class E18Input {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool SystemParametersInfo(uint action, uint param, out bool value, uint ini);

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
  // Null when the input desktop is the user's (not the lock screen); else why not.
  static string Desktop() {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);  // UOI_NAME
    CloseDesktop(d);
    return name.ToString() == "Default" ? null : "the input desktop is '" + name + "' (the screen is locked?)";
  }
  // Null when input may be sent at (x, y): the user's desktop, `hwnd` the window there; else why not.
  static string Guard(IntPtr hwnd, int x, int y) {
    string e = Desktop(); if (e != null) return e;
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "not sent: another window is at " + x + "," + y;  // GA_ROOT
    return null;
  }
  // Moves there and checks it got there (a DPI mismatch would not).
  static string MoveTo(int x, int y) {
    Move(x, y); Thread.Sleep(150);
    POINT p; GetCursorPos(out p);
    if (Math.Abs(p.x - x) > 2 || Math.Abs(p.y - y) > 2) return "not sent: the cursor went to " + p.x + "," + p.y + ", not " + x + "," + y;
    return null;
  }

  // A left or right click at (x, y), guarded; brings that window in front.
  public static string Click(IntPtr hwnd, int x, int y, bool right) {
    Aware();
    string e = Guard(hwnd, x, y); if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    try {
      e = MoveTo(x, y); if (e != null) return e;
      Button(right ? 0x0008u : 0x0002u); Thread.Sleep(60); Button(right ? 0x0010u : 0x0004u); Thread.Sleep(600);
    } finally { SetCursorPos(saved.x, saved.y); }
    return right ? "right-clicked" : "clicked";
  }
  // The cursor moved to (x, y), guarded, and left there: a hover (zen mode's sidebar shows while it is over it).
  public static string Hover(IntPtr hwnd, int x, int y) {
    Aware();
    string e = Guard(hwnd, x, y); if (e != null) return e;
    e = MoveTo(x, y);
    return e ?? "hovered";
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
  // One key alone (Escape) to the window in front -- only when it is the browser's.
  public static string Tap(uint pid, ushort vk) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    Key(vk, false); Key(vk, true); Thread.Sleep(400);
    return "sent";
  }
  // `text` typed as characters, then Delete (drops an inline autocompletion) and Enter -- only when the window in
  // front is the browser's (check-e14d1's TypeEnter; an address typed after Ctrl+L, patch 109).
  public static string TypeEnter(uint pid, string text) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    foreach (char c in text) {
      foreach (bool up in new bool[] { false, true }) { INPUT i = new INPUT(); i.type = 1; i.u.ki.scan = c; i.u.ki.flags = 4u | (up ? 2u : 0u); Send(i); }  // KEYEVENTF_UNICODE
      Thread.Sleep(20);
    }
    Key(0x2E, false); Key(0x2E, true); Thread.Sleep(100);
    Key(0x0D, false); Key(0x0D, true); Thread.Sleep(500);
    return "typed";
  }
  // One key pressed and held (Ctrl across several Tab presses, C2) -- only when the window in front is the browser's;
  // Tap then presses the others under it. KeyUp lets it go.
  public static string KeyDown(uint pid, ushort vk) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    if (p != pid) return "not sent: the window in front is not the browser's";
    Key(vk, false); Thread.Sleep(150);
    return "sent";
  }
  // The release is sent whatever is in front: a refused one would leave the key held down for the owner too. It
  // says so when the window in front was not the browser's.
  public static string KeyUp(uint pid, ushort vk) {
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    Key(vk, true); Thread.Sleep(400);
    return p == pid ? "sent" : "sent, but the window in front was not the browser's";
  }
  // Press at (x0, y0), move to (x1, y1) in steps, let go; both points guarded.
  public static string Drag(IntPtr hwnd, int x0, int y0, int x1, int y1) {
    Aware();
    string e = Guard(hwnd, x0, y0); if (e == null) e = Guard(hwnd, x1, y1); if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    bool down = false;
    try {
      e = MoveTo(x0, y0); if (e != null) return e;
      Button(0x0002); down = true; Thread.Sleep(150);  // LEFTDOWN
      const int steps = 30;
      for (int s = 1; s <= steps; s++) { Move(x0 + (x1 - x0) * s / steps, y0 + (y1 - y0) * s / steps); Thread.Sleep(25); }
      Thread.Sleep(300);
    } finally {
      if (down) { Button(0x0004); Thread.Sleep(300); }  // LEFTUP
      SetCursorPos(saved.x, saved.y);
    }
    return "dragged";
  }
  // Drag's press and steps to (x1, y1), held there `holdMs`, then on in steps to (x2, y2) and let go; all three
  // points guarded (C8: a drag held over a closed folder opens it, then drops in what it opened).
  public static string DragHold(IntPtr hwnd, int x0, int y0, int x1, int y1, int holdMs, int x2, int y2) {
    Aware();
    string e = Guard(hwnd, x0, y0); if (e == null) e = Guard(hwnd, x1, y1); if (e == null) e = Guard(hwnd, x2, y2);
    if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    bool down = false;
    try {
      e = MoveTo(x0, y0); if (e != null) return e;
      Button(0x0002); down = true; Thread.Sleep(150);  // LEFTDOWN
      const int steps = 30;
      for (int s = 1; s <= steps; s++) { Move(x0 + (x1 - x0) * s / steps, y0 + (y1 - y0) * s / steps); Thread.Sleep(25); }
      Thread.Sleep(holdMs);
      for (int s = 1; s <= steps; s++) { Move(x1 + (x2 - x1) * s / steps, y1 + (y2 - y1) * s / steps); Thread.Sleep(25); }
      Thread.Sleep(300);
    } finally {
      if (down) { Button(0x0004); Thread.Sleep(300); }  // LEFTUP
      SetCursorPos(saved.x, saved.y);
    }
    return "dragged, held " + holdMs + " ms";
  }
  // Wheel steps (WHEEL_DELTA 120 a notch; negative: down) at (x, y), `gap` ms apart, guarded.
  public static string Wheel(IntPtr hwnd, int x, int y, int[] deltas, int gap) {
    Aware();
    string e = Guard(hwnd, x, y); if (e != null) return e;
    POINT saved; GetCursorPos(out saved);
    try {
      e = MoveTo(x, y); if (e != null) return e;
      foreach (int d in deltas) { INPUT i = new INPUT(); i.type = 0; i.u.mi.flags = 0x0800; i.u.mi.data = unchecked((uint)d); Send(i); Thread.Sleep(gap); }  // MOUSEEVENTF_WHEEL
    } finally { SetCursorPos(saved.x, saved.y); }
    return "wheeled " + deltas.Length + " step(s)";
  }

  // The process's visible windows other than `main`, top first: a menu, a bubble.
  public static IntPtr[] Others(uint pid, IntPtr main) {
    List<IntPtr> found = new List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid && h != main && IsWindowVisible(h)) found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found.ToArray();
  }
  // The process's browser windows: visible, not owned by another window (as a bubble or a menu is).
  public static IntPtr[] Windows(uint pid) {
    List<IntPtr> found = new List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      StringBuilder c = new StringBuilder(64); GetClassName(h, c, 64);
      if (p == pid && IsWindowVisible(h) && c.ToString() == "Chrome_WidgetWin_1" && GetWindow(h, 4) == IntPtr.Zero) found.Add(h);  // GW_OWNER
      return true;
    }, IntPtr.Zero);
    return found.ToArray();
  }
  public static void CloseWindow(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }  // WM_CLOSE, what the X sends
  // Restored, placed and topmost, not activated.
  public static void Place(IntPtr h, int x, int y, int w, int height) { Aware(); ShowWindow(h, 9); SetWindowPos(h, new IntPtr(-1), x, y, w, height, 0x0010); }
  // The client area on screen: left, top, width, height (physical pixels).
  public static int[] Client(IntPtr h) {
    Aware(); RECT r; GetClientRect(h, out r); POINT p; p.x = 0; p.y = 0; ClientToScreen(h, ref p);
    return new int[] { p.x, p.y, r.r - r.l, r.b - r.t };
  }
  public static int Dpi(IntPtr h) { return (int)GetDpiForWindow(h); }
  public static int[] Screen() { Aware(); return new int[] { GetSystemMetrics(0), GetSystemMetrics(1) }; }
  // Windows' "Animation effects" (SPI_GETCLIENTAREAANIMATION): off, and gfx::Animation::ShouldRenderRichAnimation
  // is false -- nothing glides (D13).
  public static bool Animations() { bool on; return SystemParametersInfo(0x1042, 0, out on, 0) && on; }
}
"@
}

# One DevTools call on a page: Runtime.evaluate of `expr` (a promise awaited); its value, or "error: ...", or $null.
function Evaluate([string]$wsUrl, [string]$expr) {
    $sock = [Net.WebSockets.ClientWebSocket]::new()
    $none = [Threading.CancellationToken]::None
    try {
        if (-not $sock.ConnectAsync([Uri]$wsUrl, $none).Wait(10000)) { return $null }
        $o = [Text.Encoding]::UTF8.GetBytes((@{ id = 1; method = "Runtime.evaluate"; params = @{ expression = $expr; awaitPromise = $true; returnByValue = $true } } | ConvertTo-Json -Compress -Depth 4))
        if (-not $sock.SendAsync([ArraySegment[byte]]::new($o), [Net.WebSockets.WebSocketMessageType]::Text, $true, $none).Wait(10000)) { return $null }
        $buf = [byte[]]::new(1048576); $got = 0
        do {
            $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf, $got, $buf.Length - $got), $none)
            if (-not $r.Wait(15000)) { return $null }
            $got += $r.Result.Count
        } until ($r.Result.EndOfMessage)
        $reply = ([Text.Encoding]::UTF8.GetString($buf, 0, $got) | ConvertFrom-Json).result
        if ($reply.exceptionDetails) { "error: $($reply.exceptionDetails.exception.description)" } else { $reply.result.value }
    } catch { "error: $_" } finally { $sock.Dispose() }
}

# chrome://settings/appearance opened as a tab of profile `prof`'s browser through the DevTools port
# (--remote-debugging-port=0 writes the port to <profile>\DevToolsActivePort), then up to 20 s for chrome.settingsPrivate:
# base (the port's /json), page (its webSocketDebuggerUrl, id, url; $null when none opened), ready, and a note on how it went.
function OpenSettings([string]$prof) {
    $file = "$prof\DevToolsActivePort"; $t0 = Get-Date
    while (-not (Test-Path -LiteralPath $file) -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep 1 }
    $port = if (Test-Path -LiteralPath $file) { [int](Get-Content -LiteralPath $file -TotalCount 1) } else { 0 }
    if (-not $port) { return [pscustomobject]@{ base = $null; page = $null; ready = $false; note = "no DevToolsActivePort in the profile" } }
    $base = "http://127.0.0.1:$port/json"
    $page = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$base/new?chrome://settings/appearance" } catch { $null }
    if (-not $page) { return [pscustomobject]@{ base = $base; page = $null; ready = $false; note = "the DevTools port ($port) opened no tab" } }
    $ready = $false; $t0 = Get-Date
    while (-not $ready -and ((Get-Date) - $t0).TotalSeconds -lt 20) { Start-Sleep 1; $ready = (Evaluate $page.webSocketDebuggerUrl "typeof chrome === 'object' && !!chrome.settingsPrivate") -eq $true }
    [pscustomobject]@{ base = $base; page = $page; ready = $ready; note = $(if ($ready) { "on $($page.url)" } else { "chrome.settingsPrivate never appeared on $($page.url)" }) }
}

# Local test pages <dir>\<name>.html titled "E18 <name>", served by python's http.server on a port Windows picks
# (8765 is Logi Options+'s, LOCAL.md 59), polled until the first one is served: port, server (its process), ok.
# Not ok: the server is stopped.
function ServePages([string]$dir, [string[]]$names) {
    $null = New-Item -ItemType Directory -Force $dir
    foreach ($nm in $names) { Set-Content -Encoding UTF8 -LiteralPath "$dir\$nm.html" -Value "<!doctype html><title>E18 $nm</title><h1>E18 $nm</h1>" }
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    $server = Start-Process python -ArgumentList "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $dir -WindowStyle Hidden -PassThru
    $ok = $false
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$port/$($names[0]).html").Content -match "E18 $($names[0])") { $ok = $true; break } } catch {} }
    if (-not $ok) { Stop-Process -Id $server.Id -EA SilentlyContinue }
    [pscustomobject]@{ port = $port; server = $server; ok = $ok }
}

# `msaa-press.ps1 -List -Rect` lines as nodes: name, role, box (physical pixels), shown (not INVISIBLE, a box with
# size). The one parser of that format: a script's Nodes passes it its own Msaa's lines (check-c14).
# -List indents 2 spaces a level, so an odd indent is a name's own leading space -- a tab group's menu item
# " E38 group group - Closed" (IDS_GROUP_AX_LABEL_GROUP_MENU_ITEM_FORMAT, no "Shared" before it), which a press must
# match exactly (LOCAL.md 119).
function ParseMsaaNodes([string[]]$lines) {
    @($lines | ForEach-Object {
        if ($_ -match '^( *)(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)') {
            [pscustomobject]@{ name = $(if ($Matches[1].Length % 2) { " " } else { "" }) + $Matches[2]; role = [Convert]::ToInt32($Matches[3], 16)
                               l = [int]$Matches[5]; t = [int]$Matches[6]; w = [int]$Matches[7]; h = [int]$Matches[8]
                               shown = (-not $Matches[4]) -and [int]$Matches[7] -gt 0 -and [int]$Matches[8] -gt 0 }
        }
    })
}

# The browser's popups -- its menus and bubbles: its visible windows other than `main` that are no browser window
# (a menu or a bubble is owned by one). A second browser window is never searched or pressed in. Needs E18InputType.
function PopupWindows([uint32]$bpid, [IntPtr]$main) {
    $w = @([E18Input]::Windows($bpid)); @([E18Input]::Others($bpid, $main) | Where-Object { $w -notcontains $_ })
}
# The shown nodes of `nodes` that can be pressed: a settings row's title is a plain label (0x29) with its control's
# name, and pressing it does nothing. `shown` is the caller's test, as each script lists nodes its own way (check-93,
# check-e18-auto, check-e14d3-auto).
function Controls($nodes, [scriptblock]$shown) { @($nodes | Where-Object { (& $shown $_) -and $_.role -ne 0x29 }) }

# Camera and microphone ALLOWED for http://127.0.0.1:<port> in the profile copy's Preferences file `prefs`, so a test
# page's getUserMedia takes the real permission road with no prompt. --use-fake-ui-for-media-stream (and
# --auto-accept-camera-and-microphone-capture) swap in content's FakeMediaStreamUIProxy, which never reaches Chrome's
# MediaStreamCaptureIndicator: no tab then carries a recording alert at all (C14's first run). Pair it with
# --use-fake-device-for-media-stream -- a fake camera, never the real one. True when written.
function AllowCameraAt([string]$prefs, [int]$port) {
    & python -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); e=d.setdefault('profile',{}).setdefault('content_settings',{}).setdefault('exceptions',{}); [e.setdefault(k,{}).__setitem__('http://127.0.0.1:%s,*' % sys.argv[2],{'setting':1}) for k in ('media_stream_camera','media_stream_mic')]; json.dump(d,open(p,'w',encoding='utf-8'))" $prefs $port
    $LASTEXITCODE -eq 0
}
