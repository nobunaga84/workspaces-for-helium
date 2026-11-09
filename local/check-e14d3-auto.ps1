param([switch]$Dcheck, [switch]$GradeOnly)
# E14d.3 without a person (design 5, "Auto-archive (E14d.3)"; the contract graded here is the log lines in the
# comments of workspace_service.h -- UpdateAutoArchiveTimer, SweepForAutoArchive, ArchiveClosingTab -- and the
# sweep rules at the end of workspace_archive.h). Three runs of a throwaway copy of the smoke profile, as the
# siblings make one; helium.workspaces.archive_after_minutes is written to 2 before run 1, so the timer sweeps
# every 60 s (SweepInterval: half the setting, at most 5 min). Real input where a person's is needed, each
# guarded as in check-e15d3-auto.ps1 (the input desktop the user's, the fork's window under the point or in
# front, the cursor put back): a click on a tab, a right click for its menu, Ctrl+W / Ctrl+T / Ctrl+L, typing --
# typing into a page is what performance_manager's HadUserEdits needs (composite_edit_command.cc). The rest
# through MSAA (msaa-press.ps1: accDoDefaultAction), the settings box's dropdown and its list's items too. Graded from
# each run's log -- its time stamps against the script's own clock, one machine -- the archive file ("Workspace
# Archive", written 2.5 s after a change: read 5 s later), the newest Recently Closed file and Preferences. The
# run keeps what it saw (MSAA, the clicks and their times, the file between steps) in e14d3-auto-facts.json;
# -GradeOnly grades that and the logs again. -Dcheck runs out\Dcheck. Run it in its OWN process (powershell
# -File): a second check script in one session reuses the first's C# type. About 15 minutes: the 2-minute clock
# sets the pace, so the import (F) runs first and the rows of run 1 wait together.
#   run 1 (2 min): the Arc import (F); the never-list set up (C) -- a favorite pinned from the tab menu, a tab
#     anchored ("Anchor" > "Anchor to this page"), a tab put in a group from its menu ("Add tab to new group"), a
#     page typed into, a pinned item opened from its row, a page playing a quiet looped tone, a page with a
#     beforeunload listener; a control closed by hand (D); then the plain page and the unload + pagehide page
#     (B) opened last and every tab shown once, home last (the tour); then two sweeps past due; then the
#     Workspace settings box (E), and a normal quit.
#   run 2 (1 day, from E): the archive fixture merged in; the Archive screen's four Clear ranges (G).
#   run 3 (2 min, Workspaces OFF): two intervals watched (H).
# The rows and what a pass looks like are $Pass below; each is printed above its row's verdicts. Not covered
# hands-free: captured / DevTools / picture-in-picture, a split and a device (the same judge, JudgeForSweep, is
# unit-tested); the 25-per-sweep cap; a sweep during a drag or a window close, before the archive is loaded or
# on a read-only one ("skipped (...)"); 7 and 30 days. Every child process and every wait is bounded (Child):
# the first -Dcheck run hung 30+ minutes after row E with the browser gone.
$ws      = "<local-path>\Helium-workspace"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
# Only for Controls (row E): functions, nothing compiled -- this script keeps its own input type, E14d3Input.
. "$here\e18-lib.ps1"
$Tag     = "e14d3-auto"
$OutDir  = if ($Dcheck) { "Dcheck" } else { "Default" }
$sfx     = if ($Dcheck) { "-dcheck" } else { "" }
$prof    = "$ws\testprofile-$Tag$sfx"
$src     = "$ws\helium-windows\build\src"
$bin     = "$src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$pages   = "$ws\$Tag-pages"
$results = "$ws\$Tag$sfx.txt"
$factsFile = "$ws\$Tag$sfx-facts.json"
$srvlog  = "$ws\$Tag$sfx-requests.log"
$afile   = "$prof\Default\Workspace Archive"
$prefs   = "$prof\Default\Preferences"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$logs    = @(1, 2, 3 | ForEach-Object { "$ws\$Tag$sfx-run$_.log" })
# Typed into the form page: it must never reach a log (47's rule).
$token   = "zqxdraft"
# The contract's log lines.
$timer2   = "\[workspaces\] auto-archive: after 2 min, sweeping every 60 s"
$timerDay = "\[workspaces\] auto-archive: after 1440 min, sweeping every 300 s"
$off      = "\[workspaces\] auto-archive: off"
$sweepAny = "\[workspaces\] auto-archive sweep"
$sweep    = "\[workspaces\] auto-archive sweep: \d+ tab\(s\), \d+ due, \d+ archived"
$autoWork = "\[workspaces\] archived a auto close in '$work'"
$autoAny  = "\[workspaces\] archived a auto close in '"
$refused  = "\[workspaces\] archived a auto close .*\(refused\)"
$ownClose = "\[workspaces\] not archived: the auto-archive's own close"
$manual   = "\[workspaces\] archived a manual close in '$work'"
$done     = "\[workspaces\] arc import: done: (\d+) tab\(s\)"
$asked    = "\[workspaces\] archive screen: clear asked, ([a-z0-9 ]+) \((\d+)\)"
$cancelled = "\[workspaces\] archive screen: clear cancelled"
$cleared  = "\[workspaces\] archive: cleared (\d+) entr\(ies\)"
# The never-list the sweep must keep (archive::SweepVerdictName), each held by one page of run 1.
$keptC = @("active", "favorite", "pinned item", "anchored", "group", "audible", "leave site", "unsaved work")
$Pass = [ordered]@{
    P = "the copy is ready (set-workspaces-pref.py --show exits 0: enabled, vertical, Work listed), has no archive file, holds archive_after_minutes 2; every set-up step did what it says"
    A = "run 1's first auto-archive line is '[workspaces] auto-archive: after 2 min, sweeping every 60 s'"
    B = "the plain page and the page with unload + pagehide listeners, left in Work: exactly 2 'archived a auto close in '<work>'' lines, none refused, each stamped 120..190 s after the tour's clicks that left them; the file holds each page once, reason auto, Work, archived 120 s or more after the click that left it and 190 s or less; exactly 1 'not archived: the auto-archive's own close' (the unload page's deferred close)"
    C = "the two sweep lines stamped after every never-list page was due (120 s after the tour's last click) each keep active, favorite, pinned item, anchored, group, audible, leave site and unsaved work (1 or more each); none of those pages is in the file; after the second, each is still open (MSAA)"
    D = "once run 1 is gone, the newest Sessions\Tabs_* holds the control 'ctrl.html' (a close by hand) and no auto-closed page: 'plain.html', 'unload.html' and 'arcN.html' 0 times"
    E = "the rail's '+' > 'Workspace settings...' opens the settings box ('settings: opened'); its 'Archive tabs after' dropdown set to Never -> exactly one '[workspaces] auto-archive: off'; then to 1 day -> exactly one '[workspaces] auto-archive: after 1440 min, sweeping every 300 s'; after the quit Preferences holds 1440"
    F = "'Import from Arc' (HELIUM_ARC_SIDEBAR: three Today tabs Arc last used 40 days ago) -> 'arc import: done: 3 tab(s)'; the file holds the three, reason auto, in the imported workspace, each archived 110 s or more after 'done' (the clock starts at the import) and 195 s or less; 3 'archived a auto close' lines there"
    G = "the fixture (30 min, 5 h, 3 days, 10 days ago) merged into run 1's file; on the Archive screen 'Clear...' > Last hour -> 'clear asked, last hour (N)' and the confirm names N -> Cancel -> 'clear cancelled', the file unchanged; then Last hour, Last 24 hours, Last 7 days, All time, each -> Delete: 'clear asked, <range> (N)', the confirm N, 'cleared N entr(ies)', the file exactly the entries older than the range; each later range takes exactly its one fixture entry; All time leaves 0"
    H = "Workspaces off, the setting 2 min: run 3 logs the timer line and then, over 125 s or more, no auto-archive sweep line and no 'archived a auto close'"
    I = "each run log has bytes and 0 markers (Check failed|FATAL|ReentrancyCheck|dangling|NOTREACHED); no [workspaces] line holds a test page's title or address or the typed text (21's 'anchor at index N -> <address>' line, older than 47's rule, left out and counted)"
}
$script:failed = 0
$script:out = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name" } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; $script:out | Set-Content -Encoding UTF8 $results; exit 1 }
function Iso { (Get-Date).ToString("o") }
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }
function Markers([string]$l) { @(Select-String -Path $l -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }
# A log line's time: "[pid:tid:MMDD/HHMMSS.mmm:..." in local time, the year given.
function LogTime([string]$line, [int]$year) {
    if ($line -match '\[\d+:\d+:(\d{2})(\d{2})/(\d{2})(\d{2})(\d{2})\.(\d{3}):') {
        [datetime]::new($year, [int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6])
    }
}
# A fact's time back from its "o" string (Windows PowerShell leaves it a string; a newer one may not).
function T($s) { if ($s -is [datetime]) { $s } elseif ($s) { [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } }
# An archive entry's archived_at (base::Time: microseconds since 1601 UTC, a string) as local time: a FILETIME
# is 100 ns since the same epoch.
function At($e) { [DateTime]::FromFileTimeUtc([long]$e.archived_at * 10).ToLocalTime() }
function Entries([string]$json) { if (-not $json) { return @() }; @(($json | ConvertFrom-Json).entries) }

if (-not $GradeOnly) {
# ==== the runs ====================================================================================================
$F = [ordered]@{ binary = ""; obs = @(); P = [ordered]@{}; tour = @(); C = [ordered]@{}; D = $null; E = [ordered]@{}; archive1 = ""; G = @(); Gmenu = [ordered]@{}; H = [ordered]@{} }
# An observation the log cannot give (MSAA, a click, a set-up step), kept for the grading; "<row>: ..." names it.
function Obs([string]$name, $ok, [string]$note = "") {
    $script:F.obs += @(@{ n = $name; ok = [bool]$ok; note = $note })
    Say ("      " + $(if ($ok) { "ok      " } else { "NOT OK  " }) + $name + $(if ($note) { " -- $note" }))
}
$script:win = [IntPtr]::Zero
$script:log = ""
# WMI, bounded: a query that times out writes its error and returns nothing (read as "gone").
# The browser Launch started, while it runs -- no WMI: its queries hung run 1 of the first -Dcheck run for 30 min
# and the second run was killed (0x40010004) at the same place, the Close after row E.
function Pids { if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) { @($script:bpid) } else { @() } }
# Every fork chrome.exe, children too: the guards refuse to start while another fork browser runs, so these are
# the profile's.
function AllPids { @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | ForEach-Object { $_.Id }) }
function Pid1 { [uint32](Pids)[0] }
function Hwnd { (Get-Process -Id (Pids)[0]).MainWindowHandle }
function Title { (Get-Process -Id (Pids)[0]).MainWindowTitle }
# A child process (msaa-press.ps1, e14d3-web.ps1, python, robocopy), killed after `s` seconds -- the call
# operator & waits for ever, and an MSAA call into a hung browser never returns. Its output lines, stdout then
# stderr (2>&1's); $script:rc its exit code, -1 when it was killed. An argument with a space or a quote is quoted
# as & quotes it, the backslashes before a quote doubled (CommandLineToArgvW's rule).
function Child([string]$file, [string[]]$a, [int]$s = 60) {
    $psi = New-Object Diagnostics.ProcessStartInfo $file
    $psi.Arguments = @($a | ForEach-Object { if ($_ -match '[\s"]' -or -not $_) { '"' + ($_ -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($p.WaitForExit($s * 1000)) { $script:rc = $p.ExitCode } else { try { $p.Kill() } catch {}; $script:rc = -1 }
    foreach ($t in $o, $e) { try { if ($t.Wait(5000) -and $t.Result) { $t.Result.TrimEnd() -split '\r?\n' } } catch {} }
    if ($script:rc -eq -1) { "(killed after $s s: $file $($a -join ' '))" }
}
# msaa-press.ps1 on window `h` (the browser's window by default).
function Msaa([string[]]$a, [IntPtr]$h = [IntPtr]::Zero) {
    if ($h -eq [IntPtr]::Zero) { $h = $script:win }
    if ($h -ne [IntPtr]::Zero) { $a += @("-Window", [string][long]$h) }
    Child "powershell.exe" (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$here\msaa-press.ps1", "-Profile", $prof) + $a)
}
function Press([string]$name, [int]$role = 0, [IntPtr]$h = [IntPtr]::Zero) { "$(Msaa @("-Name", $name, "-Role", $role) $h)" }
# e14d3-web.ps1 on the browser's window: the walk into the page.
function Web([string[]]$a, [IntPtr]$h = $script:win) { Child "powershell.exe" (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$here\e14d3-web.ps1", "-Profile", $prof, "-Window", [string][long]$h) + $a) 120 }
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
# The tab titled `title` among `nodes`, shown: MSAA adds a state to the name ("E14d3 fav - Pinned", "E14d3 audio -
# Audio playing"), so the title alone or the title and " - ...".
function TabNode($nodes, [string]$title) { @($nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and ($_.name -eq $title -or $_.name.StartsWith("$title - ")) }) | Select-Object -First 1 }
function ShownTabs { @(Nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and $_.name -notmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { $_.name }) }
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
function WaitTitle([string]$re, [int]$s = 15) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Title) -match $re) { return $true }; Start-Sleep 1 }
    return $false
}
# Every title in `titles` a shown tab, polled.
function WaitTabs([string[]]$titles, [int]$s = 30) {
    $t = Get-Date
    do { Start-Sleep 2; $n = @(Nodes); $miss = @($titles | Where-Object { -not (TabNode $n $_) }) } while ($miss.Count -and ((Get-Date) - $t).TotalSeconds -lt $s)
    return $miss
}
# check-gate.ps1's logging flags; --restore-last-session as the siblings.
function Launch([int]$n, [string[]]$more = @()) {
    $script:log = $logs[$n - 1]
    Remove-Item -LiteralPath $script:log -EA SilentlyContinue
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList (@("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$script:log`"", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--restore-last-session") + $more)).Id
}
# A normal close, then every process of the profile gone (Tabs_* and Preferences are read after).
function Close {
    foreach ($id in Pids) { Get-Process -Id $id -EA SilentlyContinue | ForEach-Object { $null = $_.CloseMainWindow() } }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { Say "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
    $t = Get-Date
    while ((AllPids).Count -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }
}
function Alive { if (-not (Pids).Count) { Obs "the browser is still running" $false; throw "the browser is gone -- a crash? See $script:log" } }
# The archive file's text, waited for past the 2.5 s write.
# A plain string: Get-Contents carries PSPath/PSProvider notes, and ConvertTo-Json -Depth 8 then walks the
# providers type into its assembly and never finishes -- the "hang" after row E in runs 1 to 3 (cdb stack).
function Raw { Start-Sleep 5; if (Test-Path -LiteralPath $afile) { [IO.File]::ReadAllText($afile, [Text.Encoding]::UTF8) } else { "" } }
function Save { $script:F | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 $factsFile }

if (-not ("E14d3Input" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class E14d3Input {
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
  // Null when the window in front is the browser's (its window, a bubble or a menu); else why not.
  static string Front(uint pid) {
    string e = Desktop(); if (e != null) return e;
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    return p == pid ? null : "not sent: the window in front is not the browser's";
  }

  // SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_ASYNCWINDOWPOS: posted to the window's thread, never waited
  // on -- a plain SetWindowPos sends to it and blocks while that thread (a hung browser) does not answer.
  public static void Topmost(IntPtr hwnd, bool on) { SetWindowPos(hwnd, new IntPtr(on ? -1 : -2), 0, 0, 0, 0, 0x4013); }
  public static bool Visible(IntPtr h) { return IsWindow(h) && IsWindowVisible(h); }

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

  // One key alone (Tab) to the window in front -- only when it is the browser's.
  public static string Tap(uint pid, ushort vk) {
    string e = Front(pid); if (e != null) return e;
    Key(vk, false); Key(vk, true); Thread.Sleep(300);
    return "sent";
  }

  // `text`, one key at a time, to the window in front -- only when it is the browser's.
  public static string Type(uint pid, string text) {
    string e = Front(pid); if (e != null) return e;
    foreach (char c in text) { Char(c, false); Char(c, true); Thread.Sleep(150); }
    Thread.Sleep(300);
    return "typed";
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
}
"@
}

# A guarded click (left, or right for its menu) on the tab titled `title` in the browser's window.
function ClickTab([string]$title, [switch]$Right) {
    $n = TabNode @(Nodes) $title
    if (-not $n) { return "no tab '$title'" }
    [E14d3Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $Right.IsPresent)
}
# The first of the browser's other windows with a shown node whose name matches `re`, polled; zero if none.
function WindowWith([string]$re, [int]$s = 10) {
    $t = Get-Date
    do {
        foreach ($h in [E14d3Input]::Others((Pid1), $script:win)) {
            if (@(Nodes $h | Where-Object { (Shown $_) -and $_.name -match $re }).Count) { return $h }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t).TotalSeconds -lt $s)
    return [IntPtr]::Zero
}
# A node of window `h` pressed through MSAA -- or, when its name did not survive MSAA's text round trip (a
# non-ASCII character, as "Clear..."'s U+2026, may come back as '?'), a guarded real click at its middle.
function PressNode([IntPtr]$h, $n) {
    $r = Press $n.name $n.role $h
    if ($r -match '^MSAA: pressed') { return $r }
    "$r; " + [E14d3Input]::Click($h, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false)
}
# The item matching `re` in the menu (or bubble) that has one, pressed. Menu item names may carry a shortcut
# ("Close Ctrl+W"), so `re` anchors the start only where a shortcut is possible.
function PressIn([string]$re, [int]$s = 5) {
    $h = WindowWith $re $s
    $n = if ($h -ne [IntPtr]::Zero) { @(Nodes $h | Where-Object { (Shown $_) -and $_.name -match $re }) | Select-Object -First 1 }
    if (-not $n) { return "nothing matching '$re' in a menu" }
    "'$($n.name)' " + (PressNode $h $n)
}
# The rail's "+" (named by its tooltip, IDS_HELIUM_WORKSPACE_ADD_MENU; a menu button, 0x39), then the item.
function OpenPlus([string]$re) {
    $plus = @(Nodes | Where-Object { (Shown $_) -and $_.role -eq 0x39 -and $_.name -match '^New tab, workspace' }) | Select-Object -First 1
    if (-not $plus) { return "no '+' on the rail" }
    "'+' " + (Press $plus.name 0x39) + "; " + (PressIn $re 5)
}
# The settings box's "Archive tabs after" dropdown opened through MSAA -- the control (e18-lib's Controls), never the
# row's title label of the same name -- then `item` pressed in its list. The setting is 2 min here, none of the dropdown's
# values, so it shows no item until one is pressed.
function PickArchive([string]$item) {
    $h = WindowWith '^Archive tabs after$' 5
    $n = if ($h -ne [IntPtr]::Zero) { @(Controls (Nodes $h) { Shown $args[0] } | Where-Object { $_.name -eq 'Archive tabs after' }) | Select-Object -First 1 }
    if (-not $n) { return "no 'Archive tabs after' dropdown in a window" }
    $r = "'Archive tabs after' " + (Press $n.name $n.role $h)
    Start-Sleep 2
    "$r; " + (PressIn ('^' + [regex]::Escape($item) + '$') 5)
}
# The Archive screen, as a person opens it -- the bar's Archive button (a push button, E17a; it left the "+"
# menu); its window, or zero.
function OpenScreen {
    $n = Count "archive screen: opened"
    Say ("      G: 'Archive' " + (Press "Archive" 0x2B))
    $null = WaitCount "archive screen: opened" ($n + 1) 10
    WindowWith '^Search archive$' 10
}
# The screen's "Clear..." (a menu button, E14d.3), then the range `label` in its menu. E17c made it the search
# row's icon-only button, still named "Clear..."; its menu's first row is a title "Clear..." -- every range is
# matched by its whole name (^label$), so the title row is never pressed or read as a range.
function ClearButton([IntPtr]$h) { @(Nodes $h | Where-Object { (Shown $_) -and $_.name -match '^Clear' -and ($_.role -eq 0x39 -or $_.role -eq 0x2B) }) | Select-Object -First 1 }
function ClearAsk([IntPtr]$h, [string]$label) {
    $b = ClearButton $h
    if (-not $b) { return "no 'Clear...' button on the screen" }
    "'Clear...' " + (PressNode $h $b) + "; " + (PressIn ('^' + [regex]::Escape($label) + '$') 5)
}
# setpref.py on the copy's Preferences: writes archive_after_minutes, or reads it back with "show". Its last
# line: profile_write.py prints "backup written: ..." before it on the first write.
function ArchivePref([string]$v) { "$(@(Child python @("$pages\setpref.py", $prefs, $v, $here))[-1])".Trim() }

# ---- guards ------------------------------------------------------------------------------------------------------
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Abort "a fork browser is running -- close it first" }
if (-not (Test-Path "$bin\chrome.dll")) { Abort "no $bin\chrome.dll" }
# Against the newest SOURCE of patch 49 that goes into chrome.dll (LOCAL.md 52: a quilt refresh rewrites the
# patch after the build): the files quilt tracks for it, and every .cc/.h/.gn of the patch once it exists.
$sources = @("chrome\browser\ui\browser_tab_strip_model_delegate.cc", "chrome\browser\ui\tabs\workspaces\BUILD.gn",
             "chrome\browser\ui\tabs\workspaces\workspace_archive.h", "chrome\browser\ui\tabs\workspaces\workspace_archive.cc",
             "chrome\browser\ui\tabs\workspaces\workspace_prefs.h", "chrome\browser\ui\tabs\workspaces\workspace_prefs.cc",
             "chrome\browser\ui\tabs\workspaces\workspace_service.h", "chrome\browser\ui\tabs\workspaces\workspace_service.cc",
             "chrome\browser\ui\tabs\workspaces\workspace_tab_data.h", "chrome\browser\ui\tabs\workspaces\workspace_tab_data.cc",
             "chrome\browser\ui\views\tabs\vertical\BUILD.gn", "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.h",
             "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.cc", "chrome\browser\ui\views\tabs\vertical\workspace_arc_importer.cc",
             "chrome\browser\extensions\api\settings_private\prefs_util.cc", "chrome\browser\ui\webui\settings\settings_localized_strings_provider.cc")
$patch = "$ws\helium-windows\patches\local\workspaces\49-auto-archive.patch"
if (Test-Path $patch) { $sources += @(Select-String -Path $patch -Pattern '^\+\+\+ b/(\S+\.(cc|h|gn))$' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
$missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
if ($missing.Count) { Abort "missing source(s) of patch 49: $($missing -join ', ')" }
$newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Abort "$OutDir\chrome.dll is older than a source of patch 49 (stale binary)" }
$null = Child python @("-c", "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'auto-archive: ')>=0 else 1)", "$bin\chrome.dll") 120
if ($script:rc -ne 0) { Abort "$OutDir\chrome.dll does not contain patch 49 ('auto-archive: ')" }
$F.binary = "$OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime.ToString('o'))"
Say "binary: $($F.binary)"

$server = $null
try {
    # ---- P: the copy, the pages, a server -------------------------------------------------------------------
    if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = Child robocopy @("$ws\testprofile-e15b-smoke", $prof, "/E", "/NFL", "/NDL", "/NJH", "/NP", "/R:1", "/W:1") 600
    # robocopy: 8 and up is a failure; -1 killed.
    if ($script:rc -lt 0 -or $script:rc -ge 8 -or -not (Test-Path $prefs)) { throw "the copy failed (robocopy $script:rc)" }
    # An empty Recently Closed: D reads what this run adds (LOCAL.md 52).
    Remove-Item "$prof\Default\Sessions\Tabs_*" -Force -EA SilentlyContinue
    $show = @(Child python @("$here\set-workspaces-pref.py", $prof, "--show"))
    $F.P.showExit = $script:rc
    $F.P.show = ($show -join "`n")
    $show | ForEach-Object { Say "      $_" }
    $F.P.afileBefore = Test-Path -LiteralPath $afile
    $null = New-Item -ItemType Directory -Force $pages
    Set-Content "$pages\setpref.py" -Encoding utf8 @'
import json, pathlib, sys
sys.path.insert(0, sys.argv[3])
from profile_write import write_json_atomically
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text(encoding="utf-8"))
if sys.argv[2] != "show":
    d.setdefault("helium", {}).setdefault("workspaces", {})["archive_after_minutes"] = int(sys.argv[2])
    write_json_atomically([(p, d)], ".e14d3")
    d = json.loads(p.read_text(encoding="utf-8"))
print(d.get("helium", {}).get("workspaces", {}).get("archive_after_minutes"))
'@
    $F.P.pref = ArchivePref "2"
    # The pages: each titled "E14d3 <name>". unload: both listeners, so the close is deferred and comes back
    # through CloseContents (NeedToFireBeforeUnloadOrUnloadEvents counts both, web_contents_impl.cc); leave: a
    # beforeunload listener; audio: a quiet tone (-40 dBFS; "audible" is above -72 dBFS, output_stream.cc);
    # form: one text field over the whole page, so a click on the page lands in it.
    $body = @{
        home = ""; plain = ""; fav = ""; anchor = ""; group = ""; ctrl = ""; arc1 = ""; arc2 = ""; arc3 = ""
        unload = "<script>addEventListener('unload', () => {}); addEventListener('pagehide', () => {});</script>"
        leave  = "<script>addEventListener('beforeunload', e => { e.preventDefault(); e.returnValue = ''; });</script>"
        audio  = "<audio src=tone.wav autoplay loop></audio>"
        form   = "<form><input aria-label=notes style='position:fixed;left:0;top:0;width:100%;height:100%;font-size:40px'></form>"
    }
    foreach ($k in $body.Keys) { Set-Content -Encoding UTF8 -Path "$pages\$k.html" -Value "<!doctype html><title>E14d3 $k</title><h1>E14d3 $k</h1>$($body[$k])" }
    $null = Child python @("-c", "import wave,math,struct,sys; w=wave.open(sys.argv[1],'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(22050); w.writeframes(b''.join(struct.pack('<h', int(327*math.sin(2*math.pi*440*i/22050))) for i in range(22050))); w.close()", "$pages\tone.wav")
    # The Arc fixture (arc_import_plan.cc): the "global" container, one space whose unpinned container holds
    # three tabs, each created and last used 40 days ago -- Arc stamps seconds since 2001-01-01 UTC
    # (kArcEpochOffsetSeconds). No favorites, no pinned container. The importer reads it from HELIUM_ARC_SIDEBAR
    # (workspace_arc_importer.cc), set before the launch so the browser inherits it.
    $arcT = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 978307200 - 40 * 86400
    $items = @("e14d3u", [ordered]@{ id = "e14d3u"; title = $null; createdAt = $arcT; parentID = $null; childrenIds = @("e14d3a1", "e14d3a2", "e14d3a3"); data = @{ itemContainer = @{} } })
    foreach ($i in 1..3) {
        $items += "e14d3a$i"
        $items += ,[ordered]@{ id = "e14d3a$i"; title = $null; createdAt = $arcT; parentID = "e14d3u"; childrenIds = @()
                              data = @{ tab = [ordered]@{ savedURL = (Url "arc$i"); savedTitle = "E14d3 arc$i"; timeLastActiveAt = $arcT } } }
    }
    $arc = [ordered]@{ version = 1; sidebar = @{ containers = @(@{ global = @{} }, [ordered]@{ items = $items
                spaces = @("e14d3s", [ordered]@{ id = "e14d3s"; title = "Arc Fixture Space"; containerIDs = @("unpinned", "e14d3u") }); topAppsContainerIDs = @() }) } }
    $arc | ConvertTo-Json -Depth 12 -Compress | Set-Content -Encoding ASCII "$pages\arc-sidebar.json"
    $env:HELIUM_ARC_SIDEBAR = "$pages\arc-sidebar.json"
    # http.server with caching off, its request log kept (the siblings' server).
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
    # This folder's page, not merely a 200: a server left on the port by another check serves another folder.
    $probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 (Url "home")).Content } catch { "" }
    Obs "P: the pages are served on port $port (home.html is this run's)" ($probe -match 'E14d3 home')
    Obs "P: tone.wav and the Arc fixture written" ((Test-Path "$pages\tone.wav") -and (Get-Item "$pages\tone.wav").Length -gt 40000 -and (Test-Path "$pages\arc-sidebar.json"))
    if ($F.P.showExit -ne 0 -or $F.P.afileBefore -or $F.P.pref -ne "2" -or $probe -notmatch 'E14d3 home') { throw "the preconditions are not met (P)" }

    # ---- run 1: F, then the never-list (C), the control (D), B's pages, the tour; the waits; E -----------------
    Launch 1 @("--autoplay-policy=no-user-gesture-required")
    Obs "P: run 1 drew the pinned section" (WaitLog "pins: drew \d+ row\(s\) of 'default'" 30)
    Start-Sleep 3
    $script:win = Hwnd
    [E14d3Input]::Topmost($script:win, $true)
    $null = Press "Work" 0x2B
    Obs "P: switched to Work" (WaitLog "pins: drew \d+ row\(s\) of '$work'" 15)

    # F first: its 2 minutes run while the rest is set up.
    Say ("      F: " + (OpenPlus '^Import from Arc'))
    Obs "F: the import finished" (WaitLog $done 60)
    Say ("      F: the bubble: " + (PressIn '^OK$' 10))
    Alive

    # C's set-up pages and D's control, in Work.
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "fav"), (Url "anchor"), (Url "group"), (Url "form"), (Url "ctrl")) | Out-Null
    $miss = WaitTabs @("E14d3 fav", "E14d3 anchor", "E14d3 group", "E14d3 form", "E14d3 ctrl")
    Obs "P: fav, anchor, group, form and ctrl are loaded tabs of Work" ($miss.Count -eq 0) "missing: $($miss -join ', ')"
    # The favorite: Chromium's Pin from the tab's menu, never the fork's "Pin to this workspace".
    Say ("      C: " + (ClickTab "E14d3 fav" -Right) + " fav's tab; " + (PressIn '^Add to Favorites'))
    $miss = WaitTabs @("E14d3 fav - Pinned") 10
    Obs "C: fav is a favorite ('E14d3 fav - Pinned')" ($miss.Count -eq 0)
    # The anchor: "Anchor" opens a submenu; a closed submenu's items are not in the tree.
    Say ("      C: " + (ClickTab "E14d3 anchor" -Right) + " anchor's tab; " + (PressIn '^Anchor$') + "; " + (PressIn '^Anchor to this page(?! instead)'))
    Obs "C: anchor is anchored ('anchor at index N -> <its address>')" (WaitLog ("anchor at index \d+ -> '" + [regex]::Escape((Url "anchor")) + "'") 10)
    # The group: Chromium's "Add tab to new group" from the tab's menu; the new group's name bubble closed with
    # Esc (check-e15d3-auto.ps1 row G). In a group a tab is named "<title> - Part of <group>".
    Say ("      C: " + (ClickTab "E14d3 group" -Right) + " group's tab; " + (PressIn '^Add tab to new group$'))
    Start-Sleep 2
    Say ("      C: Esc " + [E14d3Input]::Tap((Pid1), 0x1B))
    $miss = WaitTabs @("E14d3 group - Part of unnamed group") 10
    Obs "C: group is in a tab group ('E14d3 group - Part of unnamed group')" ($miss.Count -eq 0)
    # Unsaved work: a real click into the page's field, real keys, and Tab (the field's change event).
    $c = ClickTab "E14d3 form"
    $null = WaitTitle '^E14d3 form' 10
    $doc = @(Nodes | Where-Object { $_.role -eq 0xF -and $_.name -eq 'E14d3 form' -and (Shown $_) }) | Select-Object -First 1
    $c2 = if ($doc) { [E14d3Input]::Click($script:win, $doc.l + [int]($doc.w / 2), $doc.t + [int]($doc.h / 2), $false) } else { "no page 'E14d3 form' in the tree" }
    $k = [E14d3Input]::Type((Pid1), $token); $k2 = [E14d3Input]::Tap((Pid1), 0x09)
    Obs "C: typed into form's field (click on the tab, click on the page, keys, Tab)" ($c -eq "clicked" -and $c2 -eq "clicked" -and $k -eq "typed" -and $k2 -eq "sent") "$c; $c2; $k; $k2"
    # The pinned item: Work's "Example A" row (the smoke profile's), opened.
    Say ("      C: Example A " + (Press "Example A" 0x24))
    Obs "C: the pinned item's page opened ('pins: opened item')" (WaitLog "pins: opened item '" 15)
    # D's control: a close by hand, in Recently Closed and the archive.
    $c = ClickTab "E14d3 ctrl"; $k = [E14d3Input]::Keys((Pid1), $false, 0x57)
    Obs "D: ctrl closed by hand -> '$manual'" (WaitCount $manual 1 10) "$c, Ctrl+W $k"
    Alive

    # B's pages and the last two of C's, opened late so nothing is due before the tour.
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "home"), (Url "plain"), (Url "unload"), (Url "leave"), (Url "audio")) | Out-Null
    $miss = WaitTabs @("E14d3 home", "E14d3 plain", "E14d3 unload", "E14d3 leave", "E14d3 audio")
    Obs "P: home, plain, unload, leave and audio are loaded tabs of Work" ($miss.Count -eq 0) "missing: $($miss -join ', ')"

    # The tour: every page shown once, home last. The click on tab k+1 leaves tab k: its [t0, t1] brackets the
    # left_at the sweep counts from (the audio page's media also starts here: a page never shown defers it).
    $t0 = Get-Date; $r = Press "Example A" 0x24
    $F.tour += @(@{ name = "Example A"; t0 = $t0.ToString("o"); t1 = (Iso); r = $r })
    Start-Sleep 2
    $snap = @(Nodes)
    foreach ($n in "E14d3 fav", "E14d3 anchor", "E14d3 group", "E14d3 form", "E14d3 audio", "E14d3 leave", "E14d3 plain", "E14d3 unload", "E14d3 home") {
        $node = TabNode $snap $n
        $t0 = Get-Date
        $r = if ($node) { [E14d3Input]::Click($script:win, $node.l + [int]($node.w / 2), $node.t + [int]($node.h / 2), $false) } else { "no tab '$n'" }
        $F.tour += @(@{ name = $n; t0 = $t0.ToString("o"); t1 = (Iso); r = $r })
        Start-Sleep 1
    }
    $bad = @($F.tour | Where-Object { $_.r -notmatch '^(clicked|MSAA: pressed)' })
    Obs "C: the tour -- Example A's row, then fav, anchor, group, form, audio, leave, plain, unload, home clicked" ($bad.Count -eq 0) (@($bad | ForEach-Object { "$($_.name): $($_.r)" }) -join '; ')
    $due = (T $F.tour[-1].t1).AddSeconds(120)
    $F.C.dueAll = $due.ToString("o")
    Say "      C: every never-list page due by $($due.ToString('HH:mm:ss')); waiting for two sweeps after it (B and F land meanwhile)"
    Save
    $year = (Get-Date).Year
    do { Start-Sleep 3; $after = @(Select-String -Path $script:log -Pattern $sweep | Where-Object { (LogTime $_.Line $year) -gt $due }) } while ($after.Count -lt 2 -and (Get-Date) -lt $due.AddSeconds(150))
    Alive
    $snap = @(Nodes)
    $F.C.checkAt = Iso
    $F.C.tabs = @($snap | Where-Object { $_.role -eq 0x25 } | ForEach-Object { $_.name })
    $F.C.closePage = [bool]@($snap | Where-Object { $_.name -eq 'Close page' -and $_.role -eq 0x2B -and -not $_.hidden }).Count
    $F.archive1 = Raw
    Select-String -Path $script:log -Pattern "\[workspaces\] (auto-archive|archived a auto|not archived: the auto)" | ForEach-Object { Say ("      log: " + ($_.Line -replace '^.*?\] ', '')) }

    # E: the Workspace settings box, as a person opens it (patch 93 took the row off chrome://settings).
    $F.E.where = "the rail's '+' > 'Workspace settings...' (patch 93's settings box)"
    $o = OpenPlus '^Workspace settings'
    Obs "E: the settings box opened ('settings: opened')" (WaitLog "\[workspaces\] settings: opened" 10) $o
    $F.E.tNever = Iso; $p = PickArchive "Never"
    Obs "E: 'Archive tabs after' (its dropdown, not its label) opened and 'Never' pressed in its list" ($p -match "^'Archive tabs after' MSAA: pressed.*; 'Never' MSAA: pressed") $p
    Say "      E: Never: $(WaitLog $off 10)"
    Start-Sleep 2
    $F.E.tDay = Iso; $p = PickArchive "1 day"
    Obs "E: the dropdown opened again and '1 day' pressed" ($p -match "^'Archive tabs after' MSAA: pressed.*; '1 day' MSAA: pressed") $p
    Say "      E: 1 day: $(WaitLog $timerDay 10)"
    [E14d3Input]::Topmost($script:win, $false)
    Close
    $F.E.pref = ArchivePref "show"

    # D: the newest Tabs_* (the one the next start reads: FindLastSessionFile), read as bytes -- a URL is plain
    # UTF-8 there -- once every process of the profile is gone (it is opened exclusively).
    $tabsF = Get-ChildItem -LiteralPath "$prof\Default\Sessions" -Filter "Tabs_*" -EA SilentlyContinue | Sort-Object Name | Select-Object -Last 1
    $txt = if ($tabsF -and -not (AllPids).Count) { try { [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($tabsF.FullName)) } catch { $null } }
    $F.D = [ordered]@{ name = "$($tabsF.Name)"; left = (AllPids).Count; read = $null -ne $txt
                       ctrl = [regex]::Matches("$txt", 'ctrl\.html').Count; plain = [regex]::Matches("$txt", 'plain\.html').Count
                       unload = [regex]::Matches("$txt", 'unload\.html').Count; arc = [regex]::Matches("$txt", 'arc\d\.html').Count }
    Save

    # ---- run 2: G, the screen's ranges (the setting is E's 1 day: nothing is archived under the steps) ---------
    # The fixture refuses while any fork chrome.exe runs: a helper can outlive the browser a moment.
    $t = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }
    # The ages one quoted string: bare, Windows PowerShell reads 3d and 10d as the decimals 3 and 10 (review 14).
    $fx = @(Child python @("$here\make-archive-fixture.py", $prof, "--ages", "30m,5h,3d,10d", "--merge") 120)
    $fxOk = $script:rc -eq 0
    $fx | ForEach-Object { Say "      $_" }
    Obs "G: make-archive-fixture.py --ages 30m,5h,3d,10d --merge exits 0 (fixture-0001..0004, in that order)" $fxOk
    Launch 2
    $null = WaitLog "pins: drew \d+ row\(s\) of" 30
    Alive
    Start-Sleep 3
    $script:win = Hwnd
    [E14d3Input]::Topmost($script:win, $true)
    $null = Press "Work" 0x2B
    Start-Sleep 2
    $first = @(ShownTabs)[0]
    Say ("      G: " + $(if ($first) { ClickTab $first } else { "no tab to click" }) + " (the window in front)")
    $screen = OpenScreen
    Obs "G: the Archive screen opened (a window with 'Search archive')" ($screen -ne [IntPtr]::Zero)
    if ($screen -ne [IntPtr]::Zero) {
        $before = Raw
        foreach ($st in @(@("Last hour", "Cancel"), @("Last hour", "Delete"), @("Last 24 hours", "Delete"), @("Last 7 days", "Delete"), @("All time", "Delete"))) {
            if (-not [E14d3Input]::Visible($screen)) { $screen = OpenScreen }
            $na = Count "archive screen: clear asked"; $nc = Count $cleared
            $r = ClearAsk $screen $st[0]
            $null = WaitCount "archive screen: clear asked" ($na + 1) 10
            Start-Sleep 1
            $q = @(Nodes $screen | Where-Object { (Shown $_) -and $_.name -match '^Delete \d+ archived tab' }) | Select-Object -First 1
            $t = Iso
            $p = Press $st[1] 0 $screen
            if ($st[1] -eq "Cancel") { $null = WaitLog $cancelled 10 } else { $null = WaitCount $cleared ($nc + 1) 10 }
            $after = Raw
            $F.G += @(@{ label = $st[0]; range = $st[0].ToLower(); action = $st[1]; t = $t; before = $before; after = $after; question = "$($q.name)"; r = "$r; '$($st[1])' $p" })
            Say "      G: $($st[0]), $($st[1]): $r; '$($st[1])' $p; the confirm: '$($q.name)'"
            $before = $after
            # The fix check's row: once Last hour is emptied, the open Clear... menu shows it disabled
            # (STATE_SYSTEM_UNAVAILABLE, 0x1) and Last 24 hours, which still holds the 5 h entry, enabled.
            if ($st[0] -eq "Last hour" -and $st[1] -eq "Delete") {
                $b = ClearButton $screen
                $pm = if ($b) { PressNode $screen $b } else { "no 'Clear...' button" }
                $mh = WindowWith '^Last 24 hours$' 5
                foreach ($item in @("Last hour", "Last 24 hours")) {
                    $d = if ($mh -ne [IntPtr]::Zero) { @(Web @("-Name", $item) $mh) -join ' ' } else { "no menu window" }
                    $F.Gmenu[$item] = $d
                    Say "      G: the menu's '$item': $d"
                }
                Say ("      G: 'Clear...' $pm; Esc " + [E14d3Input]::Tap((Pid1), 0x1B))
                # The Esc closes the screen too; the loop's Visible test reopens it. Wait for the close, not a fixed
                # second: on 157 it came later, the screen was still up but empty, and Last 24 hours pressed nothing.
                $w = Get-Date
                while ([E14d3Input]::Visible($screen) -and ((Get-Date) - $w).TotalSeconds -lt 5) { Start-Sleep -Milliseconds 200 }
                Say ("      G: after the Esc the screen is " + $(if ([E14d3Input]::Visible($screen)) { "still up after 5 s" } else { "closed after {0:N1} s" -f ((Get-Date) - $w).TotalSeconds }))
            }
        }
    }
    [E14d3Input]::Topmost($script:win, $false)
    Close
    Save

    # ---- run 3: H, Workspaces off at 2 minutes ---------------------------------------------------------------
    $hp = @(Child python @("$here\set-workspaces-pref.py", $prof, "false")); $hOk = $script:rc -eq 0
    $v = ArchivePref "2"
    Obs "H: Workspaces switched off (set-workspaces-pref.py false exits 0), archive_after_minutes 2" ($hOk -and $v -eq "2") "$($hp -join ' ') / $v"
    $script:win = [IntPtr]::Zero
    Launch 3
    $F.H.launchAt = Iso
    $null = WaitLog $timer2 30
    Alive
    Say "      H: watching two intervals and a little more (130 s)"
    Start-Sleep 130
    Alive
    $F.H.endAt = Iso
    Close
} catch {
    Obs "the run went to its end" $false "$_"
} finally {
    if ((Pids).Count) { Close }
    if ($server) { Stop-Process -Id $server.Id -EA SilentlyContinue }
    Remove-Item Env:HELIUM_ARC_SIDEBAR -EA SilentlyContinue
    Save
}
}

# ==== the grading (also -GradeOnly) ==============================================================================
if (-not (Test-Path $factsFile)) { Abort "no $factsFile -- run without -GradeOnly first" }
$F = Get-Content -Raw -Encoding UTF8 $factsFile | ConvertFrom-Json
Say ""
Say "graded: $factsFile (binary $($F.binary)); logs $($logs -join ', ')"
function Lines([int]$n, [string]$re) { $l = $logs[$n - 1]; if (-not (Test-Path $l)) { return @() }; @(Select-String -Path $l -Pattern $re | ForEach-Object { $_.Line }) }
function Year([int]$n) { $l = $logs[$n - 1]; if (Test-Path $l) { (Get-Item $l).LastWriteTime.Year } else { (Get-Date).Year } }
function Row([string]$r) {
    Say ""
    Say "== $r  pass: $($Pass[$r])"
    foreach ($o in @($F.obs | Where-Object { $_.n -like "${r}:*" })) { Verdict ($o.n + $(if ($o.note) { " ($($o.note))" })) $o.ok }
}
function Log([string]$line) { Say ("      log: " + ($line -replace '^.*?\] ', '')) }
$y1 = Year 1
$e1 = Entries $F.archive1
$tour = @($F.tour)
# The click that left tab `name`: the next click of the tour.
function LeaveOf([string]$name) { for ($i = 0; $i -lt $tour.Count - 1; $i++) { if ($tour[$i].name -eq $name) { return $tour[$i + 1] } } }

Row "P"
foreach ($o in @($F.obs | Where-Object { $_.n -notmatch '^[A-IP]:' })) { Verdict ($o.n + $(if ($o.note) { " ($($o.note))" })) $o.ok }
Verdict "P: set-workspaces-pref.py --show exits 0 and lists Work ($work)" ($F.P.showExit -eq 0 -and "$($F.P.show)" -match [regex]::Escape($work))
Verdict "P: no archive file in the copied profile" ($F.P.afileBefore -eq $false)
Verdict "P: archive_after_minutes 2 in the copy's Preferences before run 1 (read back: '$($F.P.pref)')" ("$($F.P.pref)" -eq "2")

Row "A"
$first = @(Lines 1 "\[workspaces\] auto-archive(:| sweep)") | Select-Object -First 1
if ($first) { Log $first }
Verdict "A: run 1's first auto-archive line is the timer's, 2 min / 60 s" ($first -match $timer2)

Row "B"
foreach ($p in "plain", "unload") {
    $x = @($e1 | Where-Object { $_.url -eq (Url $p) })
    $lv = LeaveOf "E14d3 $p"
    $age = if ($x.Count -eq 1 -and $lv) { [Math]::Round(((At $x[0]) - (T $lv.t0)).TotalSeconds, 1) } else { "?" }
    $ok = $x.Count -eq 1 -and $lv -and $x[0].reason -eq 'auto' -and $x[0].workspace -eq $work -and (At $x[0]) -ge (T $lv.t0).AddSeconds(120) -and (At $x[0]) -le (T $lv.t1).AddSeconds(190)
    Verdict "B: '$p.html' in the file once ($($x.Count)), auto, Work, archived $age s after the click that left it (120..190)" $ok
}
$aw = @(Lines 1 $autoWork)
$aw | ForEach-Object { Log $_ }
Verdict "B: exactly 2 'archived a auto close in '<work>'' lines ($($aw.Count)), none refused" ($aw.Count -eq 2 -and (Lines 1 $refused).Count -eq 0)
$lp = LeaveOf "E14d3 plain"; $lu = LeaveOf "E14d3 unload"
$lo = if ($lp -and $lu) { (@((T $lp.t0), (T $lu.t0)) | Sort-Object)[0].AddSeconds(120) }
$hi = if ($lp -and $lu) { (@((T $lp.t1), (T $lu.t1)) | Sort-Object)[-1].AddSeconds(190) }
Verdict "B: both lines stamped 120..190 s after the clicks that left the two pages" ($aw.Count -eq 2 -and $lo -and @($aw | Where-Object { $s = LogTime $_ $y1; $s -ge $lo -and $s -le $hi }).Count -eq 2)
$oc = @(Lines 1 $ownClose)
Verdict "B: exactly one 'not archived: the auto-archive's own close' ($($oc.Count)): the unload page's deferred close, not archived twice" ($oc.Count -eq 1)

Row "C"
$due = T $F.C.dueAll
$sw = @(Lines 1 $sweep | Where-Object { $due -and (LogTime $_ $y1) -gt $due })
Verdict "C: two sweep lines after every never-list page was due ($(if ($due) { $due.ToString('HH:mm:ss') })): $($sw.Count)" ($sw.Count -ge 2)
foreach ($i in 0, 1) {
    if ($i -ge $sw.Count) { continue }
    Log $sw[$i]
    $k = @{}
    if ($sw[$i] -match 'kept: (.+?)(, \d+ left for the next sweep)?$') { foreach ($part in $Matches[1] -split ', ') { if ($part -match '^(.+) (\d+)$') { $k[$Matches[1]] = [int]$Matches[2] } } }
    $miss = @($keptC | Where-Object { -not $k[$_] })
    Verdict "C: sweep $($i + 1) after due keeps all eight$(if ($miss.Count) { " -- missing: $($miss -join ', ')" })" ($miss.Count -eq 0)
}
$pagesC = @("home", "fav", "anchor", "group", "form", "audio", "leave" | ForEach-Object { Url $_ })
$gone = @($e1 | Where-Object { $pagesC -contains $_.url -or $_.url -like 'https://example.com*' })
Verdict "C: none of the never-list pages is in the archive file ($($gone.Count))" ($F.archive1 -and $gone.Count -eq 0)
foreach ($n in "E14d3 home", "E14d3 fav", "E14d3 anchor", "E14d3 group", "E14d3 form", "E14d3 audio", "E14d3 leave") {
    Verdict "C: '$n' still open (MSAA)" (@($F.C.tabs | Where-Object { $_ -eq $n -or "$_".StartsWith("$n - ") }).Count -ge 1)
}
Verdict "C: the pinned item's page still open (its row's 'Close page' shown, MSAA)" ($F.C.closePage -eq $true)
Verdict "C: MSAA read after the second sweep past due" ($sw.Count -ge 2 -and (T $F.C.checkAt) -gt (LogTime $sw[1] $y1))

Row "D"
$d = $F.D
$why = if (-not $d) { "run 1 did not get that far" }
       elseif ($d.left) { "$($d.left) process(es) of the profile still ran (Tabs_* is opened exclusively)" }
       elseif (-not $d.name) { "no Sessions\Tabs_* file" }
       elseif (-not $d.read) { "$($d.name) could not be read" }
       elseif ($d.ctrl -lt 1) { "the control 'ctrl.html' is not in $($d.name): the file was not written, or not read" }
if ($why) { Verdict "D: not graded: $why" $false }
else { Verdict "D: $($d.name): 'ctrl.html' $($d.ctrl) (the control); 'plain.html' $($d.plain), 'unload.html' $($d.unload), 'arcN.html' $($d.arc) -- each 0" ($d.plain -eq 0 -and $d.unload -eq 0 -and $d.arc -eq 0) }

Row "E"
Say "      E: opened in $($F.E.where)"
$offs = @(Lines 1 $off); $days = @(Lines 1 $timerDay)
$offs + $days | ForEach-Object { Log $_ }
Verdict "E: Never -> exactly one 'auto-archive: off' ($($offs.Count)), after the press" ($offs.Count -eq 1 -and $F.E.tNever -and (LogTime $offs[0] $y1) -ge (T $F.E.tNever).AddSeconds(-1))
Verdict "E: 1 day -> exactly one 'auto-archive: after 1440 min, sweeping every 300 s' ($($days.Count)), after 'off' and the press" ($days.Count -eq 1 -and $offs.Count -eq 1 -and $F.E.tDay -and (LogTime $days[0] $y1) -ge (LogTime $offs[0] $y1) -and (LogTime $days[0] $y1) -ge (T $F.E.tDay).AddSeconds(-1))
Verdict "E: after the quit Preferences holds 1440 ('$($F.E.pref)')" ("$($F.E.pref)" -eq "1440")

Row "F"
$dl = @(Lines 1 $done) | Select-Object -First 1
if ($dl) { Log $dl }
$dt = if ($dl) { LogTime $dl $y1 }
Verdict "F: 'arc import: done: 3 tab(s)'" ($dl -match 'done: 3 tab\(s\)')
$arcE = @($e1 | Where-Object { $_.url -match '/arc\d\.html$' })
$g = @($arcE | ForEach-Object { $_.workspace } | Sort-Object -Unique)
Verdict "F: the file holds the three imported pages, auto, in one imported workspace ($($g -join ', '))" ($arcE.Count -eq 3 -and @($arcE | Where-Object { $_.reason -eq 'auto' }).Count -eq 3 -and $g.Count -eq 1 -and $g[0] -ne $work -and $g[0] -ne 'default')
foreach ($x in $arcE) {
    $age = if ($dt) { [Math]::Round(((At $x) - $dt).TotalSeconds, 1) } else { -1 }
    Verdict "F: '$($x.url -replace '^.*/', '')' archived $age s after 'done' (110..195: not before the import's own 2 minutes)" ($age -ge 110 -and $age -le 195)
}
$al = if ($g.Count -eq 1) { @(Lines 1 ("\[workspaces\] archived a auto close in '" + [regex]::Escape($g[0]) + "'")) } else { @() }
Verdict "F: 3 'archived a auto close' lines in that workspace ($($al.Count))" ($al.Count -eq 3)

Row "G"
$spans = @{ "last hour" = [TimeSpan]::FromHours(1); "last 24 hours" = [TimeSpan]::FromHours(24); "last 7 days" = [TimeSpan]::FromDays(7) }
$askL = @(Lines 2 $asked); $clearL = @(Lines 2 $cleared); $cancelL = @(Lines 2 $cancelled)
$steps = @($F.G)
Verdict "G: the five steps ran (Cancel, then four ranges): $($steps.Count)" ($steps.Count -eq 5)
# The fixture entry each step must take: 30 min for Last hour (twice: the Cancel), then 5 h, 3 days, 10 days.
$fixture = @("fixture-0001", "fixture-0001", "fixture-0002", "fixture-0003", "fixture-0004")
$ci = 0
for ($i = 0; $i -lt $steps.Count; $i++) {
    $s = $steps[$i]; $b = @(Entries $s.before); $a = @(Entries $s.after)
    $since = if ($spans.ContainsKey($s.range)) { (T $s.t) - $spans[$s.range] } else { [datetime]::MinValue }
    $take = @($b | Where-Object { (At $_) -ge $since })
    $n = $take.Count
    $want = if ($s.action -eq 'Cancel') { @($b | ForEach-Object { $_.id } | Sort-Object) } else { @($b | Where-Object { (At $_) -lt $since } | ForEach-Object { $_.id } | Sort-Object) }
    $what = "G: $($s.label), $($s.action)"
    $al = if ($i -lt $askL.Count) { $askL[$i] } else { "" }
    if ($al) { Log $al }
    Verdict "${what}: 'clear asked, $($s.range) ($n)'" ($al -match $asked -and $Matches[1] -eq $s.range -and [int]$Matches[2] -eq $n)
    Verdict "${what}: the confirm names $n ('$($s.question)')" ($s.question -match '^Delete (\d+) archived tabs?\b' -and [int]$Matches[1] -eq $n)
    if ($s.action -eq 'Cancel') { Verdict "${what}: 'clear cancelled'" ($cancelL.Count -eq 1) }
    else {
        $cl = if ($ci -lt $clearL.Count) { $clearL[$ci] } else { "" }; $ci++
        Verdict "${what}: 'cleared $n entr(ies)'" ($cl -match $cleared -and [int]$Matches[1] -eq $n)
    }
    $got = @($a | ForEach-Object { $_.id } | Sort-Object)
    Verdict "${what}: the file after holds exactly the $($want.Count) expected entr(ies) ($($got.Count))" ($s.after -and (($got -join ',') -eq ($want -join ',')))
    $fx = @($take | Where-Object { $_.id -like 'fixture-*' } | ForEach-Object { $_.id })
    Verdict "${what}: the range takes the one fixture entry of its age, $($fixture[$i]) ($($fx -join ', '))" (($fx -join ',') -eq $fixture[$i] -and ($i -gt 1 -or $n -ge 2))
}

# The menu's states, read after Last hour's Delete (name|0xROLE|0xSTATE|...): unavailable is 0x1.
function MenuState($d) { if ("$d" -match '^[^|]*\|0x[0-9A-F]+\|0x([0-9A-F]+)\|') { [Convert]::ToInt32($Matches[1], 16) } else { -1 } }
$hs = MenuState $F.Gmenu.'Last hour'; $ds = MenuState $F.Gmenu.'Last 24 hours'
Verdict "G: after Last hour's Delete, the menu's 'Last hour' is disabled (state 0x$('{0:X}' -f $hs))" ($hs -ge 0 -and ($hs -band 1) -ne 0)
Verdict "G: ... and 'Last 24 hours', which holds the 5 h entry, is enabled (state 0x$('{0:X}' -f $ds))" ($ds -ge 0 -and ($ds -band 1) -eq 0)

Row "H"
$tl = @(Lines 3 $timer2) | Select-Object -First 1
if ($tl) { Log $tl }
Verdict "H: run 3 set its timer (2 min, 60 s): the control that the sweeps are due" ([bool]$tl)
$from = if ($tl) { LogTime $tl (Year 3) } else { T $F.H.launchAt }
$waited = if ($from -and $F.H.endAt) { [Math]::Round(((T $F.H.endAt) - $from).TotalSeconds) } else { 0 }
Verdict "H: watched $waited s after it (125 or more: two intervals)" ($waited -ge 125)
$sl = @(Lines 3 $sweepAny)
$sl | Select-Object -First 3 | ForEach-Object { Log $_ }
Verdict "H: no auto-archive sweep line at all ($($sl.Count)) and no 'archived a auto close' ($((Lines 3 $autoAny).Count))" ((Test-Path $logs[2]) -and $sl.Count -eq 0 -and (Lines 3 $autoAny).Count -eq 0)

Row "I"
foreach ($l in $logs) {
    $bytes = if (Test-Path $l) { (Get-Item $l).Length } else { 0 }
    Verdict "I: $(Split-Path -Leaf $l) has bytes ($bytes) and 0 markers" ($bytes -gt 0 -and (Markers $l) -eq 0)
}
$hits = @($logs | Where-Object { Test-Path $_ } | ForEach-Object { Select-String -Path $_ -CaseSensitive -Pattern ('\[workspaces\].*(E14d3 |127\.0\.0\.1|' + $token + '|Fixture page|example\.com)') } | ForEach-Object { $_.Line })
$old = @($hits | Where-Object { $_ -match "\[workspaces\] anchor at index \d+ -> '" })
$leak = @($hits | Where-Object { $_ -notmatch "\[workspaces\] anchor at index \d+ -> '" })
Say "      I: $($old.Count) 'anchor at index N -> <address>' line(s) left out: 21's own line (E10), older than 47's rule"
$leak | Select-Object -First 3 | ForEach-Object { Say ("      leak: " + $_) }
Verdict "I: no [workspaces] line holds a test page's title or address, or the typed text ($($leak.Count))" (@($logs | Where-Object { Test-Path $_ }).Count -eq 3 -and $leak.Count -eq 0)

Say ""
if ($script:failed) { Say "$($script:failed) FAIL" } else { Say "ALL PASS" }
Say "results: $results; facts: $factsFile; logs: $($logs -join ', ')"
$script:out | Set-Content -Encoding UTF8 $results
exit $script:failed
