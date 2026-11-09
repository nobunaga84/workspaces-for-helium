param([string]$OutDir = "Default")
# E14d.2 without a person (design 5, "The Archive screen"; the class comment of workspace_archive_view.h is the
# contract graded here: its log lines and its accessible names). The screen is opened as a person opens it --
# the bar's Archive button (E17a) -- through MSAA (msaa-press.ps1: accDoDefaultAction, a synthesized click on the
# view, view.cc kDoDefault). The search box gets REAL keys, a row's or a tab's menu a REAL right click, a tab
# Ctrl+W and the window Ctrl+Shift+T (SendInput), each guarded as in check-e15d3-auto.ps1: sent only while the
# input desktop is the user's and the fork's window (or its bubble) is the one under the point or in front; the
# cursor is put back. The screen and a menu are each their own top-level window, found among the browser's
# visible windows by a node only they have ("Search archive"; "Archive", "Delete" or "Pin" in a menu). Graded
# from each run's log, the archive file (written 2.5 s after a change: read 5 s later) and the page server's
# request log (no-store, so a page that loads MUST ask for it); K also from the Recently Closed file. Run it in
# its OWN process (powershell -File): a second check script in one session reuses the first's C# type. The rows,
# in the order they run, and what each proves:
#   P  the copy can answer the rest: Workspaces on, vertical, Work listed; no archive file; Work's and Home's
#      rail marks read from its Preferences as the rail draws them (the icon, else the name's first character)
#   J  a favorite closed is kept in the Archive since C27 (patch 87, the owner's answer; E14d.2 had "never
#      archived"): the copy's own favorite, or gum pinned from its tab's menu ("Pin", not the fork's "Pin to
#      workspace"), closed with Ctrl+W -> "archived a manual close in '<Work>' (favorite)", its entry favorite
#      and in Work; then Ctrl+Shift+T brings it back pinned and out of the Archive, so A-G start as before
#   A  amber, birch, cedar closed in Work with Ctrl+W -> three "archived a manual close in '<work>'"; the file:
#      3 entries, manual, Work                                        (the screen has real entries to show)
#   B  the bar's "Archive" -> "rail: archive", "opened, 3 entr(ies), 3 shown"; the three newest first under
#      exactly ONE "Today"                        (it opens; the order; a header per day, not one per row)
#      The window is first made 500 px tall (put back once the screen has closed, in D), so the rail sits near
#      its bottom; a precondition row: the screen opened ABOVE the rail -- the bottom of "Search archive"'s box
#      above the top of the rail's "+" (both MSAA boxes). Only there is its bottom edge the fixed one
#      (bubble_frame_view.cc:972-983), the placement where a shrinking list moves the search box.
#   C  "ceda" typed into "Search archive" -> "filter of 4 char(s) -> 1 shown", only cedar's row shown; the
#      search box's screen box within 1 px of before the typing, graded only when B's precondition holds, else
#      "not graded" (below the rail the top edge is fixed: it cannot move either way)
#                                                  (the search hides rows; the screen keeps still)
#   D  cedar's row pressed -> "restored an entry into '<work>'" and "its Recently Closed entry left too"; the
#      screen closes; cedar leaves the file; cedar is the active tab at the top of Today, and LOADED: a new
#      "GET /cedar.html" after the press (its title alone proves nothing: the restore sets the archived one).
#      Then Ctrl+Shift+T reopens birch, the close before cedar's ("a reopened close leaves the archive"),
#      never a second cedar; birch is closed again      (restore, E15c.1's place; one place, both directions)
#   E  in Home, fir opened and closed ("archived a manual close in 'default'"); fir2 and fir3 opened there (on
#      top: fir3, fir2) and fir2 clicked -- active, not the top tab; the screen: "opened, 3 entr(ies), 1
#      shown", fir's row alone and unmarked; "All workspaces" -> "all workspaces on -> 3 shown in T ms", each
#      row led by its workspace's rail mark; birch pressed -> "active workspace -> '<work>'", restored into Work
#      with its Recently Closed entry, the screen closes, birch active on top and loaded; then "Home" on the
#      rail lands on fir2, the tab the restore left (EnterWorkspaceForInsert: a bare switch lands on the tab
#      Home was left on at the set-up, no record on the top tab); "Work" pressed again for F, fir2 and fir3
#      left open and unarchived     (the switch; a restore goes to the entry's workspace; the way back)
#   F  dahlia and elm closed; the screen: "opened, 4 entr(ies), 3 shown", the switch off again (no marks, no
#      fir); amber's row right-clicked, its menu's "Delete" -> "deleted an entry", "rebuilt after a change, 3
#      entr(ies)"; the screen stays open; amber leaves it and the file         (Delete; the posted rebuild)
#   G  from Work, the switch off, Home's fir in the file: "Clear..." (a menu button since E14d.3) -> "All time"
#      -> "clear asked, all time (3)" with two rows shown and the question "Delete 3 archived tabs..." ->
#      "Cancel" -> "clear cancelled", the file unchanged; "Clear..." -> "All time" -> "Delete" -> "cleared 3
#      entr(ies)", the file 0 entries, "Nothing archived yet" (E17c; was "No archived tabs")
#                                             (All time empties EVERY workspace, not only the rows shown)
#   H  (run 2) make-archive-fixture.py writes 1,750 entries over 59 days with Arc's split (design 5: Work about
#      1,400); a restart loads them; from Work "opened, 1750 entr(ies), <Work's> shown in T ms", T <= 1000;
#      "All workspaces" -> "all workspaces on -> 1750 shown in T ms", T <= 1000; one "Today", one "Yesterday"
#      and at most 61 headers over the 1,750 rows; one key -> "filter of 1 char(s) ... in T ms", T <= 300 (the
#      search box's box reported, not graded: the rows left still fill the list, so it cannot move either way);
#      the top row restored -> "no Recently Closed tab of its own to remove" (a close that never went through
#      Recently Closed). The three times are design 5's gate on Default, reported only on
#      another OutDir (a DCHECK build checks every view). MSAA is on for the whole run (a press turns
#      Chromium's accessibility on), so the times are an upper bound on a person's.
#   K  (run 2, last) a restore's Recently Closed removal is SAVED, not back after a restart: kiwi and lime, two
#      never-used pages, opened in Work; lime (the CONTROL) then kiwi closed with Ctrl+W; kiwi's row restored ->
#      "its Recently Closed entry left too"; 10 s for the save (kSaveDelay 2.5 s, command_storage_manager.cc);
#      then every process of the profile force-stopped -- a close would record a WINDOW entry of every open tab,
#      kiwi too -- and the NEWEST Sessions\Tabs_* file, the one the next start reads (FindLastSessionFile), read
#      as bytes (a URL is plain UTF-8 there): 'kiwi.html' 0 times, 'lime.html' at least once (the control: the
#      file was written and read; without it, or without the "left too" line, "not graded", never a PASS). Only
#      the newest: a rewrite keeps the file before it as a fallback until the next rewrite (AppendCommands,
#      command_storage_backend.cc), and that one still holds kiwi (reported)
#   I  every run log has bytes and 0 markers; no [workspaces] line holds a test page's title or address, or
#      the search text (47's rule: a log is pasted when asking for help)
# Reported, not graded: how often the pages' icon was asked for (MSAA cannot see an icon; the owner's check asks
# about it). Not covered hands-free, left to the owner's check (check-e14d2.ps1) or not tested: Enter or Space
# on a focused row and the row menu's Restore (the same restore as a click); the marks' tooltips; the icons
# drawn; dates past Yesterday; the scroll offset a rebuild keeps; a close in another window redrawing an open
# screen; a deleted workspace's entries under Home.
$ws      = "<local-path>\Helium-workspace"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Tag     = "e14d2-auto"
$sfx     = if ($OutDir -eq "Default") { "" } else { "-" + $OutDir.ToLower() }
$prof    = "$ws\testprofile-$Tag"
$src     = "$ws\helium-windows\build\src"
$bin     = "$src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\48-archive-screen.patch"
$pages   = "$ws\$Tag-pages"
$results = "$ws\e14d2-auto$sfx.txt"
$srvlog  = "$ws\e14d2-auto$sfx-requests.log"
$afile   = "$prof\Default\Workspace Archive"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
# Not J's favorite (C27), whose line ends " (favorite)".
$manual   = "archived a manual close in '$work'(?! \(favorite\))"
$manualH  = "archived a manual close in 'default'"
$archived = "\] archived a "
$refused  = "archived a .*\(refused\)"
$notFav   = "not archived: a favorite \(a pinned tab\)"
$opened   = "archive screen: opened, (\d+) entr\(ies\), (\d+) shown, in (\d+) ms"
$filter   = "archive screen: filter of (\d+) char\(s\) -> (\d+) shown in (\d+) ms"
$allOn    = "archive screen: all workspaces on -> (\d+) shown in (\d+) ms"
$restored = "archive: restored an entry into '$work'"
$restAny  = "archive: restored an entry into '"
$leftToo  = "archive: its Recently Closed entry left too"
$noneToo  = "archive: no Recently Closed tab of its own to remove"
$reopened = "archive: a reopened close leaves the archive"
$notIn    = "archive: a reopened close was not in the archive"
$deleted  = "archive: deleted an entry"
$asked    = "archive screen: clear asked, all time \((\d+)\)"
$cleared  = "archive: cleared (\d+) entr\(ies\)"
# The timing gate is the release build's (design 5: what a person waits for); a DCHECK build runs its extra
# checks on every view and is reported, not graded (E14d.2: 1,616 ms there against 430 ms on release).
$gateOff = $OutDir -ne "Default"
function Gate { if ($gateOff) { " (not graded on $OutDir, reported)" } else { "" } }
$script:failed = 0
$script:win = [IntPtr]::Zero
$script:logs = @()
$script:log = ""
$script:out = New-Object System.Collections.Generic.List[string]
# Every line goes to the screen and to $results; Write-Host, so a function can report and still return a value.
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name" } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; $script:out | Set-Content -Encoding UTF8 $results; exit 1 }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
# Every process of the profile, children too (they carry --user-data-dir, chrome_content_browser_client.cc).
function AllPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" } | ForEach-Object { $_.ProcessId }) }
function Pid1 { [uint32](Pids)[0] }
function Hwnd { (Get-Process -Id (Pids)[0]).MainWindowHandle }
function Title { (Get-Process -Id (Pids)[0]).MainWindowTitle }
# msaa-press.ps1 on window `h` (the browser's window by default).
function Msaa([string[]]$a, [IntPtr]$h = [IntPtr]::Zero) {
    if ($h -eq [IntPtr]::Zero) { $h = $script:win }
    if ($h -ne [IntPtr]::Zero) { $a += @("-Window", [string][long]$h) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof @a
}
function Press([string]$name, [int]$role = 0, [IntPtr]$h = [IntPtr]::Zero) { "$(Msaa @("-Name", $name, "-Role", $role) $h)" }
# Every node of window `h` with its box: name, role, hidden (INVISIBLE), left, top, width, height.
function Nodes([IntPtr]$h = [IntPtr]::Zero) {
    @(Msaa @("-List", "-Rect") $h | ForEach-Object {
        if ($_ -match '^\s*(.*)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                               l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7] }
        }
    })
}
function Shown($n) { (-not $n.hidden) -and $n.h -gt 0 -and $n.w -gt 0 }
function Node([string]$name, [int]$role) { @(Nodes | Where-Object { $_.name -eq $name -and $_.role -eq $role -and (Shown $_) }) | Select-Object -First 1 }
# The list's Today tabs as drawn, top to bottom; favorites ("<title> - Pinned") sit above it and are left out.
function ShownTabs { @(Nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and $_.name -notmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { $_.name }) }
# The row showing `text` among a window's nodes: of the shown nodes whose name holds it, the biggest -- the row
# itself, not the label inside it (a press goes to the node pressed, never its parent).
function RowOf($nodes, [string]$text) { @($nodes | Where-Object { (Shown $_) -and $_.name.Contains($text) } | Sort-Object { $_.w * $_.h } -Descending) | Select-Object -First 1 }
function Names($nodes) { (@($nodes | Where-Object { (Shown $_) -and $_.name } | Sort-Object t | ForEach-Object { $_.name }) -join ' | ') }
function Named($nodes, [string]$name) { @($nodes | Where-Object { (Shown $_) -and $_.name -eq $name }) }
# With "All workspaces" on, a row's name is its workspace's rail mark, two spaces, the title (the class
# comment). A mark that is not ASCII may come back from MSAA's text round trip as '?' (PressNode).
function Marked($n, [string]$mark, [string]$title) {
    [bool]($n -and $mark -and ($n.name -eq "$mark  $title" -or ($mark -match '[^\x00-\x7F]' -and $n.name -match ('^\?+  ' + [regex]::Escape($title) + '$'))))
}
# The search box has not moved: the same screen box within 1 px (E14d.2 review: the bubble resized itself as
# rows hid, and being placed above the rail its top -- the box being typed into -- moved).
function Still($a, $b) { [bool]($a -and $b -and [Math]::Abs($a.l - $b.l) -le 1 -and [Math]::Abs($a.t - $b.t) -le 1 -and [Math]::Abs($a.w - $b.w) -le 1 -and [Math]::Abs($a.h - $b.h) -le 1) }
function Box($n) { if ($n) { "$($n.l),$($n.t) $($n.w)x$($n.h)" } else { "none" } }
function WaitLog([string]$re, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $script:log) -and (Select-String -Path $script:log -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function Count([string]$re) { if (-not (Test-Path $script:log)) { return 0 }; @(Select-String -Path $script:log -Pattern $re).Count }
function WaitCount([string]$re, [int]$n, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# The groups of the LAST line matching `re` (call as @(Last ...)): [0] the match, [1].. the numbers.
function Last([string]$re) {
    if (-not (Test-Path $script:log)) { return }
    $m = @(Select-String -Path $script:log -Pattern $re)
    if ($m.Count) { @($m[-1].Matches[0].Groups | ForEach-Object { $_.Value }) }
}
function WaitShown([string]$tab, [int]$s = 15) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((ShownTabs) -contains $tab) { return $true }; Start-Sleep 1 }
    return $false
}
function WaitTitle([string]$re, [int]$s = 15) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Title) -match $re) { return $true }; Start-Sleep 1 }
    return $false
}
# How often the server was asked for file `f` (E14d.1's rule: no-store, so a page that loads MUST ask).
function Requests([string]$f) { if (-not (Test-Path $srvlog)) { return 0 }; @(Select-String -Path $srvlog -SimpleMatch "GET /$f ").Count }
function WaitReq([string]$f, [int]$atLeast, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Requests $f) -ge $atLeast) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function Launch([int]$n) {
    $script:log = "$ws\e14d2$sfx-run$n.log"; $script:logs += $script:log
    Remove-Item -LiteralPath $script:log -EA SilentlyContinue
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$script:log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session") | Out-Null
}
function Close {
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { Say "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
}
function Alive { if (-not (Pids).Count) { Verdict "the browser is still running" $false; throw "the browser is gone -- a crash? See $script:log" } }
function Markers([string]$l) { @(Select-String -Path $l -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }
# The archive's entries (call as @(Archive)) and its raw text, waited for past the 2.5 s write.
function Archive { Start-Sleep 5; if (-not (Test-Path -LiteralPath $afile)) { return @() }; @((Get-Content -Raw -Encoding UTF8 -LiteralPath $afile | ConvertFrom-Json).entries) }
function Raw { Start-Sleep 5; if (Test-Path -LiteralPath $afile) { Get-Content -Raw -Encoding UTF8 -LiteralPath $afile } else { "" } }
function Show($e) { Say ("      file: " + (@($e | ForEach-Object { "$($_.reason) $($_.workspace) '$($_.title)'" }) -join ' | ')) }
function Lines { if (Test-Path $script:log) { Select-String -Path $script:log -Pattern "\[workspaces\] (archive|not archived: a favorite|rail: archive|active workspace)" | ForEach-Object { Say ("      log: " + ($_.Line -replace '^.*?\] ', '')) } } }

if (-not ("E14d2Input" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class E14d2Input {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
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
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  delegate bool EnumProc(IntPtr h, IntPtr l);

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
  // One character as itself (KEYEVENTF_UNICODE), whatever the keyboard layout.
  static void Char(char c, bool up) { INPUT i = new INPUT(); i.type = 1; i.u.ki.scan = c; i.u.ki.flags = 4u | (up ? 2u : 0u); Send(i); }
  // Null when the input desktop is the user's (not the lock screen); else why not.
  static string Desktop() {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);  // UOI_NAME
    CloseDesktop(d);
    return name.ToString() == "Default" ? null : "the input desktop is '" + name + "'";
  }
  // Null when the window in front is the browser's (its window, the screen or a menu); else why not.
  static string Front(uint pid) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    return p == pid ? null : "not sent: the window in front is not the browser's";
  }

  public static void Topmost(IntPtr hwnd, bool on) { SetWindowPos(hwnd, new IntPtr(on ? -1 : -2), 0, 0, 0, 0, 0x0013); }
  public static bool Visible(IntPtr h) { return IsWindow(h) && IsWindowVisible(h); }
  // `hwnd` made `height` tall where it is (physical pixels; its width, place, z-order and activation kept);
  // answers the height it had.
  public static int Height(IntPtr hwnd, int height) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    RECT r; GetWindowRect(hwnd, out r);
    SetWindowPos(hwnd, IntPtr.Zero, 0, 0, r.r - r.l, height, 0x0016);  // NOMOVE | NOZORDER | NOACTIVATE
    return r.b - r.t;
  }

  // A left or right click at (x, y) -- only on `hwnd` there, and only where the cursor really lands (physical
  // pixels, as MSAA gives the boxes). Brings that window in front.
  public static string Click(IntPtr hwnd, int x, int y, bool right) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    string e = Desktop(); if (e != null) return e;
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "not clicked: another window is at " + x + "," + y;  // GA_ROOT
    POINT saved; GetCursorPos(out saved);
    try {
      Move(x, y); Thread.Sleep(150);
      POINT at; GetCursorPos(out at);
      if (Math.Abs(at.x - x) > 2 || Math.Abs(at.y - y) > 2) return "not clicked: the cursor went to " + at.x + "," + at.y;
      Button(right ? 0x0008u : 0x0002u); Thread.Sleep(60); Button(right ? 0x0010u : 0x0004u); Thread.Sleep(600);
    } finally { SetCursorPos(saved.x, saved.y); }
    return right ? "right-clicked" : "clicked";
  }

  // Ctrl(+Shift)+key to the window in front -- only when it is the browser's.
  public static string Keys(uint pid, bool shift, ushort vk) {
    string e = Front(pid); if (e != null) return e;
    Key(0x11, false); if (shift) Key(0x10, false);
    Key(vk, false); Key(vk, true);
    if (shift) Key(0x10, true); Key(0x11, true);
    Thread.Sleep(500);
    return "sent";
  }

  // `text`, one key at a time, to the window in front -- only when it is the browser's.
  public static string Type(uint pid, string text) {
    string e = Front(pid); if (e != null) return e;
    foreach (char c in text) { Char(c, false); Char(c, true); Thread.Sleep(150); }
    Thread.Sleep(300);
    return "typed";
  }

  // The process's visible windows other than `main`, top first: a menu, the Archive screen's bubble.
  public static IntPtr[] Others(uint pid, IntPtr main) {
    List<IntPtr> found = new List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid && h != main && IsWindowVisible(h)) found.Add(h);
      return true;
    }, IntPtr.Zero);
    return found.ToArray();
  }
}
"@
}

# A guarded click on a list tab of the browser's window: activates it and brings the window in front.
function ClickTab([string]$tab) {
    $n = Node $tab 0x25
    if (-not $n) { return "no list tab '$tab'" }
    [E14d2Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false)
}
function CloseTab([string]$tab) { $c = ClickTab $tab; $k = [E14d2Input]::Keys((Pid1), $false, 0x57); "$c '$tab', Ctrl+W $k" }
# The first of the browser's other windows with a shown node whose name matches `re`, polled; zero if none.
function WindowWith([string]$re, [int]$s = 10) {
    $t = Get-Date
    do {
        foreach ($h in [E14d2Input]::Others((Pid1), $script:win)) {
            if (@(Nodes $h | Where-Object { (Shown $_) -and $_.name -match $re }).Count) { return $h }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t).TotalSeconds -lt $s)
    return [IntPtr]::Zero
}
# A node of window `h` pressed through MSAA -- or, when its name did not survive MSAA's text round trip (a
# non-ASCII character comes back as '?', e.g. a workspace mark), a guarded real click at its middle.
function PressNode([IntPtr]$h, $n) {
    $r = Press $n.name $n.role $h
    if ($r -match '^MSAA: pressed') { return $r }
    "$r; " + [E14d2Input]::Click($h, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false)
}
function WaitNode([IntPtr]$h, [string]$name, [int]$s = 10) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if (@(Nodes $h | Where-Object { (Shown $_) -and $_.name -eq $name }).Count) { return $true }; Start-Sleep 1 }
    return $false
}
function WaitGone([IntPtr]$h, [int]$s = 10) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if (-not [E14d2Input]::Visible($h)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# The Archive screen, opened as a person opens it: the bar's Archive button (E17a moved it out of the "+" menu;
# a push button named by IDS_HELIUM_WORKSPACE_ARCHIVE). Answers the screen's window; a screen that does not open
# ends the run -- nothing after it means anything. The button's node is kept in $script:bar: B compares the
# screen against the bar.
function OpenScreen([string]$step) {
    $n = Count "archive screen: opened"
    $arch = Node "Archive" 0x2B
    $script:bar = $arch
    if (-not $arch) { Verdict "${step}: the bar's Archive button is there" $false; throw "no Archive button on the bar" }
    Say ("      ${step}: 'Archive' " + (Press "Archive" 0x2B))
    $null = WaitCount "archive screen: opened" ($n + 1) 10
    $screen = WindowWith '^Search archive$' 10
    if ($screen -eq [IntPtr]::Zero) { Verdict "${step}: the Archive screen opened (a window with 'Search archive')" $false; throw "the Archive screen did not open" }
    return $screen
}
# "Clear..." then "All time" on the screen `h` (E14d.3 made Clear all a menu of ranges, workspace_archive_view.h).
# Its name ends in U+2026, which may not survive MSAA's text round trip: PressNode then clicks it for real.
# E17c made it the search row's icon-only menu button, still named "Clear..."; its menu opens with a title row
# "Clear..." -- only the range is looked up in the menu, by its exact name, so the title row never matches.
function ClearAllTime([IntPtr]$h) {
    $b = @(Nodes $h | Where-Object { (Shown $_) -and $_.name -match '^Clear' -and ($_.role -eq 0x39 -or $_.role -eq 0x2B) }) | Select-Object -First 1
    if (-not $b) { return "no 'Clear...' button" }
    $r = "'Clear...' " + (PressNode $h $b)
    $menu = WindowWith '^All time$' 5
    $item = if ($menu -ne [IntPtr]::Zero) { @(Nodes $menu | Where-Object { (Shown $_) -and $_.name -eq 'All time' }) | Select-Object -First 1 }
    "$r; " + $(if ($item) { "'All time' " + (PressNode $menu $item) } else { "no 'All time' in its menu" })
}

# ---- guards --------------------------------------------------------------------------------------------------
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Abort "a fork browser is running -- close it first" }
if (-not (Test-Path "$bin\chrome.dll")) { Abort "no $bin\chrome.dll" }
# Against the newest SOURCE of patch 48, not the patch file: a quilt refresh after the build rewrites the patch
# from the same sources (LOCAL.md 52). The contract's files, and every file of the patch once it exists.
$sources = @("chrome\browser\ui\tabs\workspaces\workspace_archive.h", "chrome\browser\ui\tabs\workspaces\workspace_archive.cc",
             "chrome\browser\ui\tabs\workspaces\BUILD.gn", "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.h",
             "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.cc", "chrome\browser\ui\views\tabs\vertical\workspace_rail_view.h",
             "chrome\browser\ui\views\tabs\vertical\workspace_rail_view.cc", "chrome\browser\ui\views\tabs\vertical\BUILD.gn")
if (Test-Path $patch) { $sources += @(Select-String -Path $patch -Pattern '^\+\+\+ b/(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
$missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
if ($missing.Count) { Abort "missing source(s) of patch 48: $($missing -join ', ')" }
$newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Abort "$OutDir\chrome.dll is older than a source of patch 48 (stale binary)" }
# A literal the code has whole: a log line built from two pieces is not one string in the binary (LOCAL.md 52).
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'archive screen:')>=0 else 1)" "$bin\chrome.dll"
if ($LASTEXITCODE -ne 0) { Abort "$OutDir\chrome.dll does not contain patch 48 ('archive screen:')" }
Say "binary: $OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime)"

# ---- set-up: a copy of the smoke profile, eleven pages, a server -------------------------------------------------
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path "$prof\Default\Preferences")) { Abort "copy failed" }
# An empty Recently Closed: the copy's own held a whole window (LOCAL.md 52).
Remove-Item "$prof\Default\Sessions\Tabs_*" -Force -EA SilentlyContinue

# P: the profile answers the question, or nothing below means anything
$show = @(& python "$here\set-workspaces-pref.py" $prof --show 2>&1)
$ready = $LASTEXITCODE -eq 0
$show | ForEach-Object { Say "      $_" }
Verdict "P: enabled, vertical, Work ($work) in the list -- set-workspaces-pref.py --show exits 0" ($ready -and (($show -join "`n") -match [regex]::Escape($work)))
Verdict "P: no archive file in the copied profile" (-not (Test-Path -LiteralPath $afile))
# Each workspace's rail mark as the rail draws it (WorkspaceRailView::ButtonText): its icon, else its name's
# first character. Through json.dumps' \u escapes, so an emoji survives the pipe from python.
$marks = & python -c "import json,sys; w=json.load(open(sys.argv[1],encoding='utf-8'))['helium']['workspaces']['list']['items']; print(json.dumps({i['guid']: i.get('icon') or i.get('title','')[:1] for i in w}))" "$prof\Default\Preferences" | ConvertFrom-Json
$wm = if ($marks) { [string]$marks.$work } else { "" }
$hm = if ($marks) { [string]$marks.'default' } else { "" }
Verdict "P: Work's and Home's rail marks read from the copy's Preferences" ($wm -and $hm)
if ($script:failed) { Abort "$($script:failed) precondition(s) not met" }

# amber..elm and gum open in Work, fir, fir2 and fir3 in Home (E), kiwi and lime in Work in run 2 (K). Each page
# names an icon, so a loaded page leaves one in history for the row's lookup (reported below; the owner's check
# asks what it drew).
$names  = @("amber", "birch", "cedar", "dahlia", "elm", "gum")
$null = New-Item -ItemType Directory -Force $pages
foreach ($n in $names + @("fir", "fir2", "fir3", "kiwi", "lime")) { Set-Content -Encoding UTF8 -Path "$pages\$n.html" -Value "<!doctype html><link rel=icon href=icon.png><title>E14d2 $n</title><h1>E14d2 $n</h1>" }
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap 32, 32
$gfx = [System.Drawing.Graphics]::FromImage($bmp); $gfx.Clear([System.Drawing.Color]::Red); $gfx.Dispose()
$bmp.Save("$pages\icon.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
# http.server with caching off, its request log kept: a restored tab that loads MUST fetch (E14d.1's server).
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
# This folder's page, not merely a 200: a server left on the port by another check serves another folder. And
# its request in the log, or no "loaded" below can pass.
$probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 (Url "amber")).StatusCode } catch { 0 }
if ($probe -ne 200 -or $server.HasExited) { Stop-Process -Id $server.Id -EA SilentlyContinue; Abort "the pages are not served on port $port" }
if (-not (WaitReq "amber.html" 1 5)) { Stop-Process -Id $server.Id -EA SilentlyContinue; Abort "the server's request log $srvlog does not show the probe" }

$id = @{}
try {
    # ---- run 1: J, A-G -----------------------------------------------------------------------------------------
    Launch 1
    Verdict "setup: the section drew its rows" (WaitLog "pins: drew \d+ row\(s\) of 'default'" 30)
    Start-Sleep 3
    $script:win = Hwnd
    [E14d2Input]::Topmost($script:win, $true)
    $null = Press "Work" 0x2B
    Verdict "setup: switched to Work" (WaitLog "pins: drew \d+ row\(s\) of '$work'" 15)
    # Opened in the running browser, in the workspace it shows: Work.
    Start-Process $exe -ArgumentList (@("--user-data-dir=$prof") + @($names | ForEach-Object { Url $_ })) | Out-Null
    $t = Get-Date
    do { Start-Sleep 2; $list = @(ShownTabs) } while (((Get-Date) - $t).TotalSeconds -lt 30 -and @($names | Where-Object { $list -contains "E14d2 $_" }).Count -lt $names.Count)
    Say ("      list: " + ($list -join ', '))
    Verdict "setup: the six pages are loaded Today tabs of Work (named by their titles)" (@($names | Where-Object { $list -contains "E14d2 $_" }).Count -eq $names.Count)

    # J: a favorite closed -- the copy's own, else gum pinned from its tab's menu
    $fav = @(Nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and $_.name -match ' - Pinned$' }) | Select-Object -First 1
    if (-not $fav) {
        $n = Node "E14d2 gum" 0x25
        $rc = if ($n) { [E14d2Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $true) } else { "no tab 'E14d2 gum'" }
        # Menu names may carry a shortcut; never the fork's "Pin to this workspace".
        $menu = WindowWith '^Add to Favorites' 5
        $item = if ($menu -ne [IntPtr]::Zero) { @(Nodes $menu | Where-Object { (Shown $_) -and $_.name -match '^Add to Favorites' }) | Select-Object -First 1 }
        Say ("      J: $rc gum's tab; " + $(if ($item) { "'$($item.name)' " + (PressNode $menu $item) } else { "no 'Pin' in its menu" }))
        $t = Get-Date
        do { Start-Sleep 1; $fav = Node "E14d2 gum - Pinned" 0x25 } while (-not $fav -and ((Get-Date) - $t).TotalSeconds -lt 10)
    }
    Verdict "J: a favorite to close ($(if ($fav) { "'$($fav.name)'" } else { 'none' }))" ([bool]$fav)
    $favArchived = "archived a manual close in '$work' \(favorite\)"
    $nf = Count $notFav; $nfa = Count $favArchived
    # Twice: Chromium's first Ctrl+W on a pinned tab only shows a toast asking for a second one
    # (browser_commands.cc CloseTab, ToastId::kClosePinnedTab).
    Say ("      J: " + $(if ($fav) { (CloseTab $fav.name) + "; again, as the toast asks: " + [E14d2Input]::Keys((Pid1), $false, 0x57) } else { "nothing to close" }))
    Alive
    # C27 (patch 87, the owner's answer): a favorite closed is KEPT, filed under the workspace on screen and marked;
    # E14d.2's "never archived" is gone. Ctrl+Shift+T then brings it back pinned and takes the close back out of the
    # Archive, so A-G meet the archive this check was written for.
    $title = if ($fav) { $fav.name -replace ' - Pinned$', '' } else { "" }
    Verdict "J: kept in the Archive as a favorite (C27): '$favArchived', no 'not archived: a favorite'" ((WaitCount $favArchived ($nfa + 1) 10) -and (Count $notFav) -eq $nf)
    $e = @(Archive | Where-Object { $_.title -eq $title })
    Show $e
    Verdict "J: the file's entry for it: favorite, in Work" ($fav -and -not (Node $fav.name 0x25) -and $e.Count -eq 1 -and $e[0].favorite -eq $true -and $e[0].workspace -eq $work)
    Say ("      J: Ctrl+Shift+T " + [E14d2Input]::Keys((Pid1), $true, 0x54))
    $t = Get-Date
    do { Start-Sleep 1; $back = if ($fav) { Node $fav.name 0x25 } } while (-not $back -and ((Get-Date) - $t).TotalSeconds -lt 10)
    Verdict "J: Ctrl+Shift+T brought it back a favorite ('$(if ($fav) { $fav.name })' drawn) and out of the Archive" ($back -and -not @(Archive | Where-Object { $_.title -eq $title }).Count)

    # A: three manual closes in Work
    $i = 0
    foreach ($n in "amber", "birch", "cedar") { $i++; Say ("      A: " + (CloseTab "E14d2 $n")); $null = WaitCount $manual $i 10 }
    Alive
    Verdict "A: three '$manual', none refused" ((WaitCount $manual 3 10) -and (Count $manual) -eq 3 -and (Count $refused) -eq 0)
    $e = @(Archive); Show $e
    foreach ($x in $e) { $id[$x.title] = $x.id }
    Verdict "A: the file: 3 entries, manual, Work -- amber, birch, cedar" ($e.Count -eq 3 -and @($e | Where-Object { $_.reason -eq 'manual' -and $_.workspace -eq $work }).Count -eq 3 -and $id.ContainsKey("E14d2 amber") -and $id.ContainsKey("E14d2 birch") -and $id.ContainsKey("E14d2 cedar"))

    # B: the screen, from Work. The window first made 500 px tall, so the rail sits near its bottom and the
    # screen opens ABOVE it, its bottom edge fixed (the anchor window's bounds decide the flip,
    # bubble_frame_view.cc:972-983): only there can a shrinking list move the search box (C). The height is
    # put back once the screen has closed (D): a resize under the open screen would move it.
    $h0 = [E14d2Input]::Height($script:win, 500)
    Say "      B: the window made 500 px tall (it was $h0)"
    Start-Sleep 2
    $screen = OpenScreen "B"
    Verdict "B: 'rail: archive'" ((Count "rail: archive") -eq 1)
    $g = @(Last $opened)
    Say "      B: opened: $($g[1]) entr(ies), $($g[2]) shown, in $($g[3]) ms"
    Verdict "B: 'opened, 3 entr(ies), 3 shown'" ($g.Count -eq 4 -and $g[1] -eq '3' -and $g[2] -eq '3')
    Start-Sleep 1
    $bn = @(Nodes $screen)
    Say ("      B: screen: " + (Names $bn))
    $ra = RowOf $bn "E14d2 amber"; $rb = RowOf $bn "E14d2 birch"; $rc = RowOf $bn "E14d2 cedar"
    Verdict "B: the screen shows amber, birch and cedar under exactly one 'Today' header" ($ra -and $rb -and $rc -and @(Named $bn 'Today').Count -eq 1)
    Verdict "B: newest first -- cedar, birch, amber from the top" ($ra -and $rb -and $rc -and $rc.t -lt $rb.t -and $rb.t -lt $ra.t)
    $f = @($bn | Where-Object { (Shown $_) -and $_.name -eq 'Search archive' }) | Select-Object -First 1
    $above = [bool]($f -and $script:bar -and ($f.t + $f.h) -lt $script:bar.t)
    Verdict "B: precondition for C -- the screen opened ABOVE the rail (the search box $(Box $f), the bar's Archive button $(Box $script:bar))" $above

    # C: the search box, typed into
    $c = if ($f) { [E14d2Input]::Click($screen, $f.l + [int]($f.w / 2), $f.t + [int]($f.h / 2), $false) } else { "no 'Search archive' field" }
    $k = [E14d2Input]::Type((Pid1), "ceda")
    Say "      C: $c 'Search archive', 'ceda' $k"
    $ok = WaitLog "archive screen: filter of 4 char" 10
    $g = @(Last $filter)
    Say "      C: filter: $($g[1]) char(s) -> $($g[2]) shown in $($g[3]) ms"
    Verdict "C: 'filter of 4 char(s) -> 1 shown'" ($ok -and $g.Count -eq 4 -and $g[1] -eq '4' -and $g[2] -eq '1')
    Start-Sleep 1
    $bn = @(Nodes $screen)
    Say ("      C: screen: " + (Names $bn))
    $rc = RowOf $bn "E14d2 cedar"
    Verdict "C: only cedar's row is shown -- amber's and birch's hidden" ($rc -and -not (RowOf $bn "E14d2 amber") -and -not (RowOf $bn "E14d2 birch"))
    $f2 = @($bn | Where-Object { (Shown $_) -and $_.name -eq 'Search archive' }) | Select-Object -First 1
    if ($above) { Verdict "C: the search box did not move while typing ($(Box $f) -> $(Box $f2))" (Still $f $f2) }
    else { Say "      C: not graded: the screen opened below the rail -- the search box $(Box $f) -> $(Box $f2)" }

    # D: a row pressed restores it, loaded, and takes its Recently Closed tab with it
    $nr = Count $restored; $nl = Count $leftToo; $nn = Count $noneToo; $ng = Requests "cedar.html"
    Say ("      D: " + $(if ($rc) { PressNode $screen $rc } else { "no row for cedar" }))
    Verdict "D: '$restored'" ((WaitCount $restored ($nr + 1) 10) -and (Count $restored) -eq ($nr + 1))
    Verdict "D: '$leftToo', not '$noneToo'" ((WaitCount $leftToo ($nl + 1) 10) -and (Count $leftToo) -eq ($nl + 1) -and (Count $noneToo) -eq $nn)
    Verdict "D: the screen closed" (WaitGone $screen)
    $null = [E14d2Input]::Height($script:win, $h0)
    Say "      D: the window's height put back ($h0)"
    $e = @(Archive); Show $e
    Verdict "D: the file: cedar's entry gone, amber's and birch's kept" ($id["E14d2 cedar"] -and $e.Count -eq 2 -and @($e.id) -notcontains $id["E14d2 cedar"])
    $null = WaitTitle '^E14d2 cedar' 15
    $list = @(ShownTabs)
    Say "      D: window: $(Title); list: $($list -join ', ')"
    Verdict "D: cedar is the active tab (the window's title) and LOADED -- a new 'GET /cedar.html' after the press" (((Title) -match '^E14d2 cedar') -and (WaitReq "cedar.html" ($ng + 1)))
    Verdict "D: cedar is at the top of Today" ($list.Count -and $list[0] -eq "E14d2 cedar")
    # Recently Closed now ends with birch (A closed amber, birch, cedar): Ctrl+Shift+T must bring birch back,
    # and E14d.1 takes it out of the archive. Before the fix it reopened cedar a second time.
    $np = Count $reopened; $nx = Count $notIn
    Say ("      D: " + (ClickTab "E14d2 cedar") + " (the window in front), Ctrl+Shift+T " + [E14d2Input]::Keys((Pid1), $true, 0x54))
    $null = WaitShown "E14d2 birch" 15
    $list = @(ShownTabs)
    Say "      D: list: $($list -join ', ')"
    Verdict "D: Ctrl+Shift+T reopened birch ('$reopened'), not a second cedar -- cedar listed once" (($list -contains "E14d2 birch") -and @($list | Where-Object { $_ -eq "E14d2 cedar" }).Count -eq 1 -and (WaitCount $reopened ($np + 1) 10) -and (Count $notIn) -eq $nx)
    # birch closed again, so E and F start from amber and birch in Work as before.
    if ($list -contains "E14d2 birch") { $i++; Say ("      D: " + (CloseTab "E14d2 birch")); $null = WaitCount $manual $i 10 }
    Alive
    $e = @(Archive); Show $e
    Verdict "D: the file: amber and birch (birch closed again)" ($e.Count -eq 2 -and @($e.title) -contains "E14d2 amber" -and @($e.title) -contains "E14d2 birch")

    # E: in Home, a close there (G's other workspace); the screen from Home; "All workspaces"; a restore that
    # goes back to Work
    $nh = Count "active workspace -> 'default'"
    Say ("      E: Home " + (Press "Home" 0x2B))
    Verdict "E: switched to Home ('active workspace -> 'default'')" (WaitCount "active workspace -> 'default'" ($nh + 1) 10)
    Start-Sleep 2
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "fir")) | Out-Null
    $null = WaitShown "E14d2 fir" 30
    $nm = Count $manualH
    Say ("      E: " + (CloseTab "E14d2 fir"))
    Alive
    Verdict "E: fir opened and closed in Home -> one '$manualH'" ((WaitCount $manualH ($nm + 1) 10) -and (Count $manualH) -eq ($nm + 1))
    $e = @(Archive); Show $e
    foreach ($x in $e) { $id[$x.title] = $x.id }
    # For the way back by the rail: fir2 and fir3 open on top (fir3, fir2, ...) and fir2 clicked -- the active
    # tab, neither the top one (where a switch with no record lands) nor the tab Home was left on at the set-up
    # (where a bare switch's stale record lands).
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "fir2"), (Url "fir3")) | Out-Null
    $null = WaitShown "E14d2 fir3" 30; $null = WaitShown "E14d2 fir2" 5
    Say ("      E: " + (ClickTab "E14d2 fir2"))
    $null = WaitTitle '^E14d2 fir2' 10
    $list = @(ShownTabs)
    Say "      E: window: $(Title); list: $($list -join ', ')"
    Verdict "E: fir2 and fir3 opened in Home, fir2 clicked -- the active tab, not the top one" (((Title) -match '^E14d2 fir2') -and ($list -contains "E14d2 fir3") -and $list.Count -and $list[0] -ne "E14d2 fir2")
    $screen = OpenScreen "E"
    $g = @(Last $opened)
    Say "      E: opened: $($g[1]) entr(ies), $($g[2]) shown, in $($g[3]) ms"
    Verdict "E: from Home 'opened, 3 entr(ies), 1 shown' -- Home's fir, not Work's two" ($g.Count -eq 4 -and $g[1] -eq '3' -and $g[2] -eq '1')
    Start-Sleep 1
    $bn = @(Nodes $screen)
    Say ("      E: screen: " + (Names $bn))
    Verdict "E: fir's row alone, with no mark (the switch off at the open)" ((RowOf $bn "E14d2 fir").name -eq "E14d2 fir" -and -not (RowOf $bn "E14d2 birch") -and -not (RowOf $bn "E14d2 amber"))
    $nw = Count "active workspace -> '$work'"; $nr = Count $restored; $nl = Count $leftToo
    Say ("      E: " + (Press "All workspaces" 0 $screen))
    $ok = WaitLog "archive screen: all workspaces on" 10
    $g = @(Last $allOn)
    Say "      E: all workspaces on: $($g[1]) shown in $($g[2]) ms"
    Verdict "E: 'all workspaces on -> 3 shown in T ms'" ($ok -and $g.Count -eq 3 -and $g[1] -eq '3')
    Start-Sleep 1
    $bn = @(Nodes $screen)
    Say ("      E: screen: " + (Names $bn))
    $rb = RowOf $bn "E14d2 birch"; $ra = RowOf $bn "E14d2 amber"; $rf = RowOf $bn "E14d2 fir"
    Verdict "E: each row led by its workspace's rail mark -- Work's on amber and birch, Home's '$hm' on fir" ((Marked $rb $wm "E14d2 birch") -and (Marked $ra $wm "E14d2 amber") -and (Marked $rf $hm "E14d2 fir"))
    $ng = Requests "birch.html"
    Say ("      E: " + $(if ($rb) { PressNode $screen $rb } else { "no row for birch" }))
    Verdict "E: '$restored', and '$leftToo'" ((WaitCount $restored ($nr + 1) 10) -and (Count $restored) -eq ($nr + 1) -and (WaitCount $leftToo ($nl + 1) 10))
    Verdict "E: the window went to Work ('active workspace -> '$work'')" (WaitCount "active workspace -> '$work'" ($nw + 1) 10)
    Verdict "E: the screen closed" (WaitGone $screen)
    $e = @(Archive); Show $e
    Verdict "E: the file: birch's entry gone, amber's and fir's kept (2 entries)" ($e.Count -eq 2 -and @($e.id) -notcontains $id["E14d2 birch"] -and @($e.id) -contains $id["E14d2 amber"] -and @($e.id) -contains $id["E14d2 fir"])
    $null = WaitTitle '^E14d2 birch' 15
    $list = @(ShownTabs)
    Say "      E: window: $(Title); list: $($list -join ', ')"
    Verdict "E: birch is the active tab, at the top of Work's Today, and loaded (a new 'GET /birch.html')" (((Title) -match '^E14d2 birch') -and $list.Count -and $list[0] -eq "E14d2 birch" -and (WaitReq "birch.html" ($ng + 1)))
    # Back in Home by the rail: the tab the restore took the window away from (EnterWorkspaceForInsert).
    $nh = Count "active workspace -> 'default'"
    Say ("      E: Home " + (Press "Home" 0x2B))
    $ok = WaitCount "active workspace -> 'default'" ($nh + 1) 10
    $null = WaitTitle '^E14d2 fir2' 10
    Say "      E: window: $(Title)"
    Verdict "E: back in Home by the rail, the active tab is fir2 -- the tab the restore left" ($ok -and (Title) -match '^E14d2 fir2')
    # F runs in Work; fir2 and fir3 stay open in Home, never archived.
    $nw = Count "active workspace -> '$work'"
    Say ("      E: Work " + (Press "Work" 0x2B))
    Verdict "E: back to Work for F ('active workspace -> '$work'')" (WaitCount "active workspace -> '$work'" ($nw + 1) 10)
    Start-Sleep 2

    # F: two more closes; the switch off again; a row's menu, Delete
    foreach ($n in "dahlia", "elm") { $i++; Say ("      F: " + (CloseTab "E14d2 $n")); $null = WaitCount $manual $i 10 }
    Alive
    Verdict "F: two more '$manual' ($i in all)" ((WaitCount $manual $i 10) -and (Count $manual) -eq $i)
    $e = @(Archive); Show $e
    $screen = OpenScreen "F"
    $g = @(Last $opened)
    Verdict "F: 'opened, 4 entr(ies), 3 shown' -- Work's amber, dahlia, elm; not Home's fir" ($g.Count -eq 4 -and $g[1] -eq '4' -and $g[2] -eq '3')
    Start-Sleep 1
    $bn = @(Nodes $screen)
    Say ("      F: screen: " + (Names $bn))
    $ra = RowOf $bn "E14d2 amber"
    Verdict "F: 'All workspaces' off again at this open -- rows without a mark, fir not listed" ($ra.name -eq "E14d2 amber" -and (RowOf $bn "E14d2 elm").name -eq "E14d2 elm" -and -not (RowOf $bn "E14d2 fir"))
    $nd = Count $deleted
    $rc = if ($ra) { [E14d2Input]::Click($screen, $ra.l + [int]($ra.w / 2), $ra.t + [int]($ra.h / 2), $true) } else { "no row for amber" }
    # The row's menu: Restore, Delete -- never the footer's "Delete all".
    $menu = WindowWith '^Delete(?! all)' 5
    $mn = if ($menu -ne [IntPtr]::Zero) { @(Nodes $menu) } else { @() }
    Say ("      F: $rc amber's row; menu: " + (Names $mn))
    $item = @($mn | Where-Object { (Shown $_) -and $_.name -match '^Delete(?! all)' }) | Select-Object -First 1
    Verdict "F: the row's menu offers Restore and Delete" ($item -and @($mn | Where-Object { (Shown $_) -and $_.name -match '^Restore' }).Count)
    Say ("      F: " + $(if ($item) { PressNode $menu $item } else { "no 'Delete'" }))
    Verdict "F: '$deleted', not refused" ((WaitCount $deleted ($nd + 1) 10) -and (Count "$deleted \(refused\)") -eq 0)
    Verdict "F: the screen redrew once the store changed ('rebuilt after a change, 3 entr(ies)')" (WaitLog "archive screen: rebuilt after a change, 3 entr\(ies\)" 10)
    Start-Sleep 2
    Verdict "F: the screen stays open" ([E14d2Input]::Visible($screen))
    $bn = @(Nodes $screen)
    Say ("      F: screen: " + (Names $bn))
    Verdict "F: amber's row is gone; dahlia's and elm's are shown" (-not (RowOf $bn "E14d2 amber") -and (RowOf $bn "E14d2 dahlia") -and (RowOf $bn "E14d2 elm"))
    $e = @(Archive); Show $e
    Verdict "F: the file: amber's entry gone (3 entries: dahlia, elm, fir)" ($id["E14d2 amber"] -and $e.Count -eq 3 -and @($e.id) -notcontains $id["E14d2 amber"])

    # G: Clear... > All time from Work, the switch off, while Home's fir is in the file: cancelled, then confirmed
    $raw = Raw
    $na = Count "archive screen: clear asked, all time"
    Say ("      G: " + (ClearAllTime $screen))
    $ok = WaitCount "archive screen: clear asked, all time" ($na + 1) 10
    $g = @(Last $asked)
    Verdict "G: 'clear asked, all time (3)' -- Home's fir counted too" ($ok -and $g.Count -eq 2 -and $g[1] -eq '3')
    Start-Sleep 1
    $bn = @(Nodes $screen)
    Say ("      G: screen: " + (Names $bn))
    Verdict "G: two rows shown, and the question counts three ('Delete 3 archived tabs...')" ((RowOf $bn "E14d2 dahlia") -and (RowOf $bn "E14d2 elm") -and -not (RowOf $bn "E14d2 fir") -and @($bn | Where-Object { (Shown $_) -and $_.name -match '^Delete 3 archived tabs' }).Count -eq 1)
    Say ("      G: " + (Press "Cancel" 0 $screen))
    Verdict "G: 'clear cancelled'" (WaitLog "archive screen: clear cancelled" 10)
    Verdict "G: the file unchanged after Cancel" ((Raw) -eq $raw)
    Verdict "G: the screen stays open" ([E14d2Input]::Visible($screen))
    Say ("      G: " + (ClearAllTime $screen))
    $null = WaitCount "archive screen: clear asked, all time" ($na + 2) 10
    Start-Sleep 1
    Say ("      G: " + (Press "Delete" 0 $screen))
    $ok = WaitLog "archive: cleared \d+ entr" 10
    $g = @(Last $cleared)
    Verdict "G: 'archive: cleared 3 entr(ies)'" ($ok -and $g.Count -eq 2 -and $g[1] -eq '3')
    $e = @(Archive)
    Verdict "G: the file: 0 entries -- Home's fir went too" ((Test-Path -LiteralPath $afile) -and $e.Count -eq 0)
    Verdict "G: the screen says 'Nothing archived yet'" (WaitNode $screen "Nothing archived yet" 10)
    Lines
    [E14d2Input]::Topmost($script:win, $false)
    Close

    # ---- run 2: H, the scale gate; K, the saved removal ---------------------------------------------------------
    # The fixture refuses while any fork chrome.exe runs: a renderer can outlive the browser process a moment.
    $t = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }
    $fx = @(& python "$here\make-archive-fixture.py" $prof --count 1750 --days 59 2>&1)
    $ok = $LASTEXITCODE -eq 0
    $fx | ForEach-Object { Say "      $_" }
    # Work's share, as the fixture printed it ("  1400  <guid>"): the rows the open must show.
    $wn = @($fx | ForEach-Object { if ("$_" -match "^\s*(\d+)\s+$([regex]::Escape($work))$") { [int]$Matches[1] } })[0]
    Verdict "H: make-archive-fixture.py wrote 1,750 entries, Arc's split -- Work $wn of them (design 5: 1,406 of 1,757)" ($ok -and $wn -ge 1400)
    Launch 2
    Verdict "H: the store loaded them ('archive: loaded 1750 entr(ies)')" (WaitLog "archive: loaded 1750 entr\(ies\)" 60)
    $null = WaitLog "pins: drew \d+ row\(s\) of" 30
    Alive
    Start-Sleep 3
    $script:win = Hwnd
    [E14d2Input]::Topmost($script:win, $true)
    # From Work, whatever the session restored (a press on the workspace shown changes nothing).
    $null = Press "Work" 0x2B
    Start-Sleep 2
    $first = @(ShownTabs)[0]
    Say ("      H: " + $(if ($first) { ClickTab $first } else { "no Today tab to click" }) + " (the window in front)")
    $screen = OpenScreen "H"
    $g = @(Last $opened)
    Say "      H: opened: $($g[1]) entr(ies), $($g[2]) shown, in $($g[3]) ms"
    Verdict "H: from Work 'opened, 1750 entr(ies), $wn shown'$(Gate) in <= 1000 ms (measured: $($g[3]) ms)" ($g.Count -eq 4 -and $g[1] -eq '1750' -and $wn -and [int]$g[2] -eq $wn -and ($gateOff -or [int]$g[3] -le 1000))
    Say ("      H: " + (Press "All workspaces" 0 $screen))
    $ok = WaitLog "archive screen: all workspaces on" 30
    $g = @(Last $allOn)
    Say "      H: all workspaces on: $($g[1]) shown in $($g[2]) ms"
    Verdict "H: 'all workspaces on -> 1750 shown'$(Gate) in <= 1000 ms (measured: $($g[2]) ms)" ($ok -and $g.Count -eq 3 -and $g[1] -eq '1750' -and ($gateOff -or [int]$g[2] -le 1000))
    # One walk of 1,750 rows (seconds): the day headers, the rows, and where the search box is. A header is
    # a node of the role 'Today' has (a heading); a row one of the role the biggest row node has.
    $bn = @(Nodes $screen)
    $today = @(Named $bn 'Today'); $yday = @(Named $bn 'Yesterday')
    $rowRole = (RowOf $bn "Fixture page").role
    $rows = @($bn | Where-Object { (Shown $_) -and $_.role -eq $rowRole -and $_.name -match 'Fixture page \d+$' })
    $heads = @(if ($today.Count) { $bn | Where-Object { (Shown $_) -and $_.role -eq $today[0].role -and $_.name -and $_.name -notmatch 'Fixture page' } })
    Say ("      H: $($rows.Count) rows, $($heads.Count) headers: " + (@($heads | Select-Object -First 4 | ForEach-Object { $_.name }) -join ' | ') + " ...")
    Verdict "H: rows by day -- one 'Today', one 'Yesterday', at most 61 headers over the 1,750 rows (59 days)" ($today.Count -eq 1 -and $yday.Count -eq 1 -and $rows.Count -eq 1750 -and $heads.Count -ge 2 -and $heads.Count -le 61)
    $f = @($bn | Where-Object { (Shown $_) -and $_.name -eq 'Search archive' }) | Select-Object -First 1
    $c = if ($f) { [E14d2Input]::Click($screen, $f.l + [int]($f.w / 2), $f.t + [int]($f.h / 2), $false) } else { "no 'Search archive' field" }
    $k = [E14d2Input]::Type((Pid1), "9")
    Say "      H: $c 'Search archive', '9' $k"
    $ok = WaitLog "archive screen: filter of 1 char" 20
    $g = @(Last $filter)
    Say "      H: filter: $($g[1]) char(s) -> $($g[2]) shown in $($g[3]) ms"
    Verdict "H: one key filters 1,750 rows$(Gate) in <= 300 ms (measured: $($g[3]) ms)" ($ok -and $g.Count -eq 4 -and $g[1] -eq '1' -and ($gateOff -or [int]$g[3] -le 300))
    $bn = @(Nodes $screen)
    $f2 = @($bn | Where-Object { (Shown $_) -and $_.name -eq 'Search archive' }) | Select-Object -First 1
    # Reported only: the rows left (about 400) still fill the list's 480 px, so the box cannot move either way
    # (C grades it).
    Say "      H: the search box $(Box $f) -> $(Box $f2) (reported, not graded: $($g[2]) rows still fill the list)"
    # A fixture entry never went through Recently Closed: its restore finds nothing there to take away.
    $top = @($bn | Where-Object { (Shown $_) -and $_.role -eq $rowRole -and $_.name -match 'Fixture page \d+$' } | Sort-Object t) | Select-Object -First 1
    $nr = Count $restAny; $nl = Count $leftToo; $nn = Count $noneToo
    Say ("      H: " + $(if ($top) { PressNode $screen $top } else { "no row shown" }))
    Verdict "H: the top row restored -- '$noneToo', not '$leftToo'" ((WaitCount $restAny ($nr + 1) 10) -and (WaitCount $noneToo ($nn + 1) 10) -and (Count $leftToo) -eq $nl)

    # K: a restore's Recently Closed removal is SAVED. Two never-used pages, so no other entry holds their
    # addresses; lime, closed first and never restored, is the control. Back in Work: H's restore may have
    # switched to the fixture row's workspace.
    $null = WaitGone $screen 5
    $null = Press "Work" 0x2B
    Start-Sleep 2
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "kiwi"), (Url "lime")) | Out-Null
    $null = WaitShown "E14d2 kiwi" 30; $null = WaitShown "E14d2 lime" 5
    $list = @(ShownTabs)
    Say "      K: list: $($list -join ', ')"
    # Never a Ctrl+W without its tab: it would close the active one.
    $ok = ($list -contains "E14d2 kiwi") -and ($list -contains "E14d2 lime")
    Verdict "K: kiwi and lime are loaded Today tabs (named by their titles)" $ok
    if (-not $ok) { throw "kiwi and lime did not open" }
    $nm = Count $manual
    foreach ($n in "lime", "kiwi") { $nm++; Say ("      K: " + (CloseTab "E14d2 $n")); $null = WaitCount $manual $nm 10 }
    Alive
    Verdict "K: lime, then kiwi closed in Work -> two more '$manual'" ((WaitCount $manual $nm 10) -and (Count $manual) -eq $nm)
    $screen = OpenScreen "K"
    $rk = RowOf @(Nodes $screen) "E14d2 kiwi"
    $nr = Count $restored; $nl = Count $leftToo; $nn = Count $noneToo
    Say ("      K: " + $(if ($rk) { PressNode $screen $rk } else { "no row for kiwi" }))
    $kr = (WaitCount $restored ($nr + 1) 10) -and (Count $restored) -eq ($nr + 1) -and (WaitCount $leftToo ($nl + 1) 10) -and (Count $leftToo) -eq ($nl + 1) -and (Count $noneToo) -eq $nn
    Verdict "K: kiwi's row restored -- '$restored', '$leftToo'" $kr
    $null = WaitGone $screen
    # The removal rewrites the file at the next save, kSaveDelay (2.5 s, command_storage_manager.cc) later: four.
    Start-Sleep 10
    Lines
    [E14d2Input]::Topmost($script:win, $false)
    # Force-stopped, never closed: the last window's close records a WINDOW entry holding every open tab, the
    # restored kiwi too. Tabs_* is opened exclusive while the browser runs: read once every process is gone.
    AllPids | ForEach-Object { Stop-Process -Id $_ -Force -EA SilentlyContinue }
    $t = Get-Date
    while ((AllPids).Count -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }
    Start-Sleep 1
    Say "      K: force-stopped; $((AllPids).Count) process(es) of the profile left"
    # Each Tabs_* file as bytes, one char per byte (Latin-1), oldest first; the newest is the one graded.
    $hits = @(Get-ChildItem -LiteralPath "$prof\Default\Sessions" -Filter "Tabs_*" -EA SilentlyContinue | Sort-Object Name | ForEach-Object {
        $file = $_
        $txt = try { [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($file.FullName)) } catch { $null }
        [pscustomobject]@{ name = $file.Name; bytes = $file.Length; read = $null -ne $txt
                           kiwi = if ($txt) { [regex]::Matches($txt, 'kiwi\.html').Count } else { 0 }
                           lime = if ($txt) { [regex]::Matches($txt, 'lime\.html').Count } else { 0 } }
    })
    $hits | ForEach-Object { Say "      K: $($_.name), $($_.bytes) bytes: 'kiwi.html' $($_.kiwi), 'lime.html' $($_.lime)$(if (-not $_.read) { ' (not readable)' })" }
    $last = $hits | Select-Object -Last 1
    $why = if ((AllPids).Count) { "a process of the profile still runs (Tabs_* is opened exclusive)" }
           elseif (-not $last) { "no Sessions\Tabs_* file" }
           elseif (-not $last.read) { "$($last.name) could not be read" }
           elseif (-not $kr) { "the restore did not log '$leftToo': an absent kiwi proves nothing" }
           elseif ($last.lime -lt 1) { "the control 'lime.html' is not in $($last.name): the file was not written, or not read" }
    if ($why) { Say "      K: not graded: $why" }
    else { Verdict "K: the newest Tabs_* ($($last.name)), the one the next start reads: 'kiwi.html' 0 times, the control 'lime.html' $($last.lime)" ($last.kiwi -eq 0) }
} catch {
    Say "ABORT: $_"
    $script:failed++
} finally {
    if ((Pids).Count) { Close }
    Stop-Process -Id $server.Id -EA SilentlyContinue
}

# I: every run's log, graded only when it has bytes
foreach ($l in $script:logs) {
    $bytes = if (Test-Path $l) { (Get-Item $l).Length } else { 0 }
    Verdict "I: $(Split-Path -Leaf $l) has bytes ($bytes) and 0 markers" ($bytes -gt 0 -and (Markers $l) -eq 0)
}
$leak = @($script:logs | Where-Object { Test-Path $_ } | ForEach-Object { Select-String -Path $_ -CaseSensitive -Pattern '\[workspaces\].*(E14d2 |ceda|127\.0\.0\.1|Fixture page)' })
$leak | Select-Object -First 3 | ForEach-Object { Say ("      leak: " + $_.Line) }
Verdict "I: no [workspaces] line holds a test page's title or address, or the search text" ($script:logs.Count -and $leak.Count -eq 0)
Say "      icon: the pages' icon.png was asked for $(Requests 'icon.png') time(s) (reported, not graded: MSAA cannot see an icon)"
if ($script:failed) { Say "$($script:failed) FAIL" } else { Say "ALL PASS" }
Say "results: $results; logs: $($script:logs -join ', '); requests: $srvlog"
$script:out | Set-Content -Encoding UTF8 $results
exit $script:failed
