param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$BinDir = "", [string]$Tag = "c7")
# C7 -- a sideways scroll over the sidebar shows the workspace beside this one, once per swipe, stopping at the ends --
# on a throwaway copy of the smoke profile (Sessions emptied; five workspaces: Home, Work, Canary, Private,
# Unpin; a new window opens on Home). The wheel is POSTED to the browser's window (WM_MOUSEHWHEEL / WM_MOUSEWHEEL): no
# real mouse, no keys, no screenshots -- it runs with the screen locked. The window is placed topmost: Chromium drops
# a wheel whose point another program's window covers (RerouteMouseWheel). Graded by the log only.
#   C1  on Home, a swipe LEFT: "no workspace there", no switch (the start is an end)
#   C2  a swipe RIGHT over the tab list: Home -> Work
#   C3  ONE swipe of 12 small steps (a touchpad's): exactly one switch, Work -> Canary
#   C4  a pause, then another swipe: Canary -> Private (a new swipe switches again)
#   C5  a vertical wheel, then sideways steps at once: no switch (the swipe is the list's scroll)
#   C6  sideways with the left button held (a drag): no switch
#   C7  sideways over the web page: no switch
#   C8  sideways at the bottom of the sidebar (the bar): Private -> Unpin -- measured 2026-10-20 by UI DevTools at
#       this window size: the bar spans client y 852-885, x 6-194; the point is client (70, 876)
#   C9  on the last workspace, a swipe right: "no workspace there", no switch
#   C10 a swipe left: Unpin -> Private
#   C11 one swipe that starts a little up-down (6), then sideways: still one switch, Private -> Unpin (the direction
#       locks on a 15-unit lead, as Chromium's controller, not on the first wheel)
#   Z   0 crash markers (case-sensitive, DanglingPtr too)
# -BinDir: another folder's chrome.exe (a negative control: a build without patch 82 must FAIL C1-C4, C8-C10).
#   pwsh -File local\check-c7.ps1 [-Build Dcheck] [-BinDir <folder>]
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$bin    = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = "$ws\$Tag$suffix-run.log"
$slow   = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total  = 13
$work   ="2ab592d4-a80b-4a1d-aeaa-6acd51c12134"; $canary = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$priv   = "c9990cf0-c141-42fd-bb39-de33171ad078"; $unpin = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Get-Content -LiteralPath $log | Select-String -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}

Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Threading;
public static class C7Post {
  [StructLayout(LayoutKind.Sequential)] struct POINT { public int x, y; }
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  // Each delta posted `gap` ms apart at screen (x, y): WM_MOUSEHWHEEL when sideways (positive = right), else
  // WM_MOUSEWHEEL; `keys` = the MK_ flags (1 = the left button). Null when posted, else why not.
  public static string Wheel(IntPtr hwnd, bool sideways, int x, int y, int[] deltas, int gap, int keys) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "another window is at " + x + "," + y;  // GA_ROOT
    IntPtr l = new IntPtr((y << 16) | (x & 0xFFFF));
    foreach (int d in deltas) { PostMessage(hwnd, sideways ? 0x020Eu : 0x020Au, new IntPtr((d << 16) | (keys & 0xFFFF)), l); Thread.Sleep(gap); }
    return null;
  }
}
'@

# Posts one gesture at point `at`, then waits past the end of a swipe (300 ms) for the posted switch and its lines.
function Swipe([int[]]$deltas, [string]$at = "list", [int]$keys = 0) {
    $p = $script:points[$at]
    $r = [C7Post]::Wheel($script:main, $true, $p[0], $p[1], $deltas, 8, $keys)
    Start-Sleep -Milliseconds (700 * $slow)
    if ($r) { "NOT POSTED: $r" } else { "posted $($deltas.Count) at $at ($($p -join ','))" }
}
function Swipes { Count "\[workspaces\] swipe " }
function Switches { Count "\[workspaces\] active workspace -> " }

function Launch {
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($script:main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    # Physical pixels. The sidebar is on the left, 200 DIPs wide in this profile; the bar is its bottom.
    $c = [E18Input]::Client($script:main); $s = [E18Input]::Dpi($script:main) / 96.0
    $script:points = @{
        list = @([int]($c[0] + 70 * $s), [int]($c[1] + $c[3] * 0.45))
        bar  = @([int]($c[0] + 70 * $s), [int]($c[1] + $c[3] - 16 * $s))
        page = @([int]($c[0] + $c[2] - 200 * $s), [int]($c[1] + $c[3] * 0.5))
    }
    Say "browser $($script:bpid) from $exe, log $log; session '$env:SESSIONNAME', client $($c -join ','), scale $s"
}
function Quit {
    if (-not ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue))) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Get-Process -Id $script:bpid -EA SilentlyContinue)
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' })$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a browser from $bin or the build tree is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
Say "build: $exe, chrome.dll of $((Get-ChildItem -LiteralPath $bin -Recurse -Filter chrome.dll | Select-Object -First 1).LastWriteTime)"
E18InputType
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force

try {
    Launch
    Verdict "P0 the window opened on Home: $(Count "a window opens on workspace 'default'") line(s)" ((Count "a window opens on workspace 'default'") -ge 1)

    $a0 = Switches; $r = Swipe @(-120)
    Verdict "C1 on Home, a swipe left ($r): 'no workspace there' $(Count "swipe -1: no workspace there"), switches +$((Switches) - $a0) (want 1, +0)" ((Count "swipe -1: no workspace there") -eq 1 -and (Switches) -eq $a0)

    $a0 = Switches; $r = Swipe @(120)
    $ok = WaitLog "swipe 1: 'default' -> '$work'" 1 5
    Verdict "C2 a swipe right over the list ($r): Home -> Work $ok, switches +$((Switches) - $a0) (want +1)" ($ok -and (Switches) -eq $a0 + 1 -and (Count "active workspace -> '$work'") -ge 1)

    $a0 = Switches; $s0 = Swipes; $r = Swipe (@(30) * 12)
    $ok = WaitLog "swipe 1: '$work' -> '$canary'" 1 5
    Verdict "C3 one swipe of 12 small steps ($r): Work -> Canary $ok, swipe lines +$((Swipes) - $s0), switches +$((Switches) - $a0) (want +1, +1)" ($ok -and (Swipes) -eq $s0 + 1 -and (Switches) -eq $a0 + 1)

    $a0 = Switches; $r = Swipe @(120)
    $ok = WaitLog "swipe 1: '$canary' -> '$priv'" 1 5
    Verdict "C4 a pause, then another swipe ($r): Canary -> Private $ok, switches +$((Switches) - $a0)" ($ok -and (Switches) -eq $a0 + 1)

    $a0 = Switches; $s0 = Swipes
    $p = $script:points["list"]
    $r1 = [C7Post]::Wheel($script:main, $false, $p[0], $p[1], @(-120), 8, 0)
    $r2 = [C7Post]::Wheel($script:main, $true, $p[0], $p[1], @(120, 120, 120), 8, 0)
    Start-Sleep -Milliseconds (700 * $slow)
    Verdict "C5 a vertical wheel, then sideways at once ($(if ($r1 -or $r2) { "NOT POSTED: $r1 $r2" } else { 'posted' })): swipe lines +$((Swipes) - $s0), switches +$((Switches) - $a0) (want +0, +0)" (-not ($r1 -or $r2) -and (Swipes) -eq $s0 -and (Switches) -eq $a0)

    $a0 = Switches; $s0 = Swipes; $r = Swipe @(120, 120) "list" 1
    Verdict "C6 sideways with the left button held ($r): swipe lines +$((Swipes) - $s0), switches +$((Switches) - $a0) (want +0, +0)" ($r -like "posted*" -and (Swipes) -eq $s0 -and (Switches) -eq $a0)

    $a0 = Switches; $s0 = Swipes; $r = Swipe @(120, 120) "page"
    Verdict "C7 sideways over the web page ($r): swipe lines +$((Swipes) - $s0), switches +$((Switches) - $a0) (want +0, +0)" ($r -like "posted*" -and (Swipes) -eq $s0 -and (Switches) -eq $a0)

    $a0 = Switches; $r = Swipe @(120) "bar"
    $ok = WaitLog "swipe 1: '$priv' -> '$unpin'" 1 5
    Verdict "C8 sideways at the bottom of the sidebar, the bar ($r): Private -> Unpin $ok, switches +$((Switches) - $a0)" ($ok -and (Switches) -eq $a0 + 1)

    $a0 = Switches; $r = Swipe @(120)
    Verdict "C9 on the last workspace, a swipe right ($r): 'no workspace there' $(Count "swipe 1: no workspace there"), switches +$((Switches) - $a0) (want 1, +0)" ((Count "swipe 1: no workspace there") -eq 1 -and (Switches) -eq $a0)

    $a0 = Switches; $r = Swipe @(-120)
    $ok = WaitLog "swipe -1: '$unpin' -> '$priv'" 1 5
    Verdict "C10 a swipe left ($r): Unpin -> Private $ok, switches +$((Switches) - $a0)" ($ok -and (Switches) -eq $a0 + 1)

    $a0 = Switches; $s0 = Swipes
    $p = $script:points["list"]
    $r1 = [C7Post]::Wheel($script:main, $false, $p[0], $p[1], @(6), 8, 0)
    $r2 = [C7Post]::Wheel($script:main, $true, $p[0], $p[1], (@(30) * 5), 8, 0)
    Start-Sleep -Milliseconds (700 * $slow)
    $ok = WaitLog "swipe 1: '$priv' -> '$unpin'" 2 5
    Verdict "C11 a swipe starting a little up-down, then sideways ($(if ($r1 -or $r2) { "NOT POSTED: $r1 $r2" } else { 'posted' })): Private -> Unpin $ok, swipe lines +$((Swipes) - $s0), switches +$((Switches) - $a0) (want +1, +1)" ($ok -and (Swipes) -eq $s0 + 1 -and (Switches) -eq $a0 + 1)
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q = Quit
}
# Case-sensitive, as LOCAL.md grades (LOCAL.md 86, 90).
$markers = 0
if (Test-Path -LiteralPath $log) { $markers = @(Get-Content -LiteralPath $log | Select-String -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count }
Verdict "Z crash markers in $log (the quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$verdict"
exit [int]($verdict -eq "FAIL")
