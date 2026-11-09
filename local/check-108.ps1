param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "p108", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string]$Against = "", [string[]]$Rows = @(), [string[]]$Trace = @())
# Patch 108 (review 2's chunk 6, <local-path>\Helium-workspace\patch-review-2-findings.md R2-6 R2-8 R2-11 R2-12): big-profile
# speed. A throwaway copy of the made-up testprofile with three folders in Work (the 2nd, Shift+Alt+2, no rows of its
# own): "C108 big" (1,159 pages, closed), "C108 pair" (C108 P1, C108 P2) and "C108 pair2" (C108 Q1, C108 Q2), both
# open. Then Open all on the big "Canary"'s (the 6th) "Imported From Chrome" (3,163 pages): the window holds ~3,240
# tabs, asleep. M1 S1 D2 D1 run in Work, T1 R1 D3 in the big Canary, C1 in Home.
# One launch, one log. A freeze timer (Freeze108) pings the window's thread with WM_NULL while an action runs: "max" is
# the longest the window did not answer, "busy" the sum of the waits over 2 ms. Real clicks and keys: it starts only
# when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE.
#   pwsh -NoProfile -File local\check-108.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Against p108-red]
#        [-Rows S1,M1] [-Trace ui,views]
#   red: the build before 108, first: ... -Tag p108-red (its numbers: <local-path>\Helium-workspace\p108-red-numbers.json)
#   green: ... -Against p108-red: T1 R1 C1 D3 pass at half the red's number or less (without it they are recorded)
#   -Rows: only those rows (and S0 when one needs the big window, and Z); the numbers file keeps the others' numbers.
#   In run order: S1 and D2 first (no big window needed), then S0, M1, D1, T1, R1, C1, D3.
#   S0           Open all opened the 3,163 pages: the setup M1 D1 T1 R1 C1 D3 stand on
#   M1 R2-6      "C108 big" and "C108 pair" Ctrl+clicked, then right-clicked: the selection's menu, max under 1 s (the
#                old: a whole-strip index walk per page to ask whether any is open)
#   S1 R2-11     C108 P1, P2, P1 shown (P2 left last), both Ctrl+clicked, the menu's Close: one "last used tab" pick
#                (the old: P1 closed first, landed on P2, which closed in its turn: two)
#   D2 R2-11     C108 Q1, Q2, Q1 shown, then "C108 pair2"'s Delete folder: one pick (the old: two)
#   T1 R2-12     two Today tabs (t108a, t108b, opened by /json/new) shown in turn 10 times by /json/activate: median busy
#   R1 R2-8      t108a's tab right-clicked 3 times (Chromium's close commands ask, for their enabled state, of every
#                tab past the one clicked: the fork's hidden-tab skip there): median max
#   C1 R2-8      the favorites closed (each pressed, Ctrl+W), Home (Shift+Alt+1): Ctrl+Tab 8 times from its one tab, its only
#                stop -- each press walks every hidden tab and changes nothing: median busy
#   D1 R2-6      "C108 big" deleted (none of its pages open): max under 2 s (the old: a walk per page for the Archive)
#   D3 R2-11     "Imported From Chrome" deleted with its 3,163 pages open: max
#   Z            0 crash markers (case-sensitive, DanglingPtr too)
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$base    = "$ws\testprofile"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$log     = "$ws\$Tag$suffix-run.log"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$canary  = "3f6986cf-7a6a-46a9-9362-365dcb4a74bd"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"   # the 2nd, Shift+Alt+2: no pinned rows of its own
$chrome  = "26A0C694-C"   # the start of "Imported From Chrome"'s id
$red     = if ($Against) { [IO.File]::ReadAllText("$ws\$Against-numbers.json") | ConvertFrom-Json } else { $null }
# `pwsh -File ... -Rows S1,M1` passes ONE string "S1,M1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$every   = @("S1", "D2", "M1", "D1", "T1", "R1", "C1", "D3")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$big     = [bool]@($want | Where-Object { @("M1", "D1", "T1", "R1", "C1", "D3") -contains $_ }).Count
# The verdicts a pass needs: the fixed-line rows, S0 when it runs, Z, and the relative rows when graded.
$expect  = @($want | Where-Object { @("S1", "D2", "M1", "D1") -contains $_ }).Count + [int]$big + 1 +
           $(if ($red) { @($want | Where-Object { @("T1", "R1", "C1", "D3") -contains $_ }).Count } else { 0 })
$picks   = "\[workspaces\] last used tab -> index"
$numFile = "$ws\$Tag$suffix-numbers.json"

$script:passed = 0; $script:failed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero; $script:numbers = [ordered]@{}
# A run of some rows keeps the numbers the others recorded before.
if ($Rows.Count -and (Test-Path -LiteralPath $numFile)) {
    ([IO.File]::ReadAllText($numFile) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $script:numbers[$_.Name] = $_.Value }
}
function Want([string]$row) { $want -contains $row }
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }
function Median([double[]]$v) {
    $s = @($v | Sort-Object); if (-not $s.Count) { return -1 }
    $m = [int][Math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 }
}
# A row graded against the red run's number: at most half of it. Without -Against, recorded only.
function Relative([string]$row, [string]$what, [double]$now) {
    $script:numbers[$row] = $now
    if (-not $red) { Say "RECORD $row $what $now ms"; return }
    $was = [double]$red.$row
    Verdict "$row $what $now ms, the red $was ms (want at most half)" ($was -gt 0 -and $now -le $was / 2)
}
# The browser main thread's tasks in a trace file (check-108 -Trace's lines) that `file`'s `func` posted: how many,
# their total and the longest, in ms.
function TaskMs([string]$path, [int]$bpid, [string]$file, [string]$func) {
    $events = foreach ($line in [IO.File]::ReadLines($path)) { (ConvertFrom-Json $line).params.value }
    $main = @($events | Where-Object { $_.ph -eq 'M' -and $_.name -eq 'thread_name' -and $_.pid -eq $bpid -and
                                       $_.args.name -eq 'CrBrowserMain' } | ForEach-Object tid)
    $durs = @(foreach ($e in $events) {
        if ($e.ph -eq 'X' -and $e.name -eq 'ThreadControllerImpl::RunTask' -and $e.pid -eq $bpid -and
            $main -contains $e.tid -and "$($e.args.src_file)".EndsWith($file) -and $e.args.src_func -eq $func) { $e.dur / 1000 }
    })
    [pscustomobject]@{ count = $durs.Count; total = ($durs | Measure-Object -Sum).Sum
                       longest = ($durs | Measure-Object -Maximum).Maximum }
}

# ---- the freeze timer ---------------------------------------------------------------------------------------------------
if (-not ("Freeze108" -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Diagnostics; using System.Threading; using System.Runtime.InteropServices;
public static class Freeze108 {
  [DllImport("user32.dll")] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint ms, out IntPtr r);
  [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
  [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint ms);
  static volatile bool run; static Thread t; static IntPtr win; static double max, busy;
  // WM_NULL (0) to `h` every millisecond, each wait timed, until Stop.
  public static void Start(IntPtr h) {
    win = h; max = 0; busy = 0; run = true; timeBeginPeriod(1);
    t = new Thread(() => {
      var sw = new Stopwatch(); IntPtr r;
      while (run) {
        sw.Restart();
        SendMessageTimeout(win, 0, IntPtr.Zero, IntPtr.Zero, 0, 1200000, out r);
        double ms = sw.Elapsed.TotalMilliseconds;
        if (ms > max) max = ms;
        if (ms > 2) busy += ms;
        Thread.Sleep(1);
      }
    });
    t.IsBackground = true; t.Start();
  }
  // The longest wait and the sum of the waits over 2 ms, in ms.
  public static double[] Stop() { run = false; t.Join(); timeEndPeriod(1); return new double[] { max, busy }; }
}
"@
}
# `act` run with the timer on: what it returned, the longest freeze and the busy time.
function Timed([scriptblock]$act) {
    [Freeze108]::Start($script:main)
    try { $r = & $act } finally { $f = [Freeze108]::Stop() }
    [pscustomobject]@{ r = "$r"; max = [Math]::Round($f[0]); busy = [Math]::Round($f[1]) }
}

# ---- MSAA, the menus and the mouse, as check-106's and check-c29's ------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { if (-not (Running)) { return }; foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function NewPopup($before, [int]$s = 10) {
    $t0 = Get-Date
    do { $n = @(Popups | Where-Object { $before -notcontains $_ }); if ($n.Count) { return $n[0] }; Start-Sleep -Milliseconds 100 } while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow)
    [IntPtr]::Zero
}
# The first shown node matching `re` in a popup (a menu, a confirm), pressed through MSAA.
function PopupPress([string]$re, [int]$s = 10) {
    $t0 = Get-Date
    do {
        foreach ($w in @(Popups)) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 400
    } while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow)
    "nothing matching '$re'"
}
# Pinned row `title` brought inside the window by the wheel over a row or tab of the sidebar that is (after Open all
# the sidebar scrolls to the page in front, below the big Canary's 145 rows).
# Its node.
function Reveal([string]$title) {
    $c = [E18Input]::Client($script:main)
    $top = $c[1] + 60; $bottom = $c[1] + $c[3] - 40
    foreach ($i in 1..20) {
        $nodes = @(Nodes $script:main)
        $n = NodeIn $nodes $title 0x24
        if (-not $n) { return $null }
        $mid = $n.t + [int]($n.h / 2)
        if ($mid -ge $top -and $mid -le $bottom) { return $n }
        $on = @($nodes | Where-Object { $_.shown -and ($_.role -eq 0x24 -or ($_.role -eq 0x25 -and $_.name -notmatch ' - Pinned')) -and
                                        $_.l -lt $n.l + $n.w -and $_.l + $_.w -gt $n.l -and
                                        ($_.t + [int]($_.h / 2)) -ge $top -and ($_.t + [int]($_.h / 2)) -le $bottom }) | Select-Object -First 1
        if (-not $on) { return $n }
        $steps = [Math]::Min(30, [Math]::Max(1, [int]([Math]::Abs($mid - ($top + $bottom) / 2) / 90)))
        $null = [E18Input]::Wheel($script:main, $on.l + [int]($on.w / 2), $on.t + [int]($on.h / 2), [int[]](@($(if ($mid -lt $top) { 120 } else { -120 })) * $steps), 15)
        Start-Sleep -Milliseconds (500 * $slow)
    }
    $n
}
# A guarded real click on pinned row `title`, Ctrl held when asked; a right-click when asked.
function ClickRow([string]$title, [switch]$Ctrl, [switch]$Right) {
    $n = Reveal $title
    if (-not $n) { return "no row '$title' drawn" }
    $pid32 = [uint32]$script:bpid
    if ($Ctrl) { $d = [E18Input]::KeyDown($pid32, 0x11); if ($d -ne "sent") { return "Ctrl not held: $d" } }
    try { [E18Input]::Click($script:main, $n.l + [int]($n.w * 0.4), $n.t + [int]($n.h / 2), $Right.IsPresent) }
    finally { if ($Ctrl) { $null = [E18Input]::KeyUp($pid32, 0x11) } }
}
# Row `title`'s menu by a right-click, then `item` in it, then (when given) the confirm's `ok` with the timer on until
# the line `until` is logged (within `s` seconds): the OK may run the command in a later task.
function RowCommand([string]$title, [string]$item, [string]$ok = "", [string]$until = "", [int]$s = 30) {
    NoPopups
    $before = @(Popups)
    $c = ClickRow $title -Right
    if ((NewPopup $before) -eq [IntPtr]::Zero) { return [pscustomobject]@{ r = "$c; no menu"; max = -1; busy = -1 } }
    $p = PopupPress $item
    # A menu without the item (the selection's, say, not the row's) ends here, not after the wait for `until`.
    if ($p -like "nothing matching*") { NoPopups; return [pscustomobject]@{ r = "$c; $p"; max = -1; busy = -1 } }
    if (-not $ok) { return [pscustomobject]@{ r = "$c; $p"; max = 0; busy = 0 } }
    Start-Sleep -Milliseconds (800 * $slow)
    $t = Timed { $q = PopupPress $ok 20; "$q, logged $(WaitLog $until 1 $s)" }
    $t.r = "$c; $p; confirm $($t.r)"
    $t
}
# Keys to the browser's window in front, through SendKeys ("%+6" is Shift+Alt+6) -- never to another window.
function Keys([string]$k) {
    if ([Fg108]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
function Picks { Count $picks }
# Workspace `guid` shown by its Shift+Alt+N `keys` ("%+2"), from another one.
function Show([string]$keys, [string]$guid) {
    $last = @(Lines "active workspace -> '([^']*)'") | Select-Object -Last 1
    if ($last -and $last.Matches[0].Groups[1].Value -eq $guid) { return }
    $re = "active workspace -> '$guid'"
    $c = Count $re
    $k = Keys $keys
    if (-not (WaitLog $re ($c + 1) 30)) { throw "workspace '$guid' was not shown ($keys $k)" }
    Start-Sleep (2 * $slow)
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
if ($Against -and -not $red) { Abort "no numbers in $ws\$Against-numbers.json" }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "the selection's Close"
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 108; graded against: $(if ($Against) { $Against } else { 'nothing (recording)' })"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
if (-not ("Fg108" -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class Fg108 { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }' }

# The copy: the vertical layout, 280 wide; the three folders in Work (no other rows there: after Open all the sidebar
# scrolls to the page in front, below the big Canary's 145 rows), "Imported From Chrome"
# at the top of the big Canary.
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $base $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $base failed" }
Remove-Item -LiteralPath "$prof\Default\Workspace Archive" -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "helium.workspaces.enabled=true"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$seed = @'
import json, sys
path, ws, work = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path, encoding="utf-8"))
def item(id, title, url):
    return {"type": "item", "id": id, "title": title, "url": url}
big = [item("c108b%04d" % i, "C108 big %d" % i, "https://c108-big.test/%d" % i) for i in range(1, 1160)]
roots = d["workspaces"][ws]
chrome = [r for r in roots if r.get("title") == "Imported From Chrome"]
assert len(chrome) == 1, "no single 'Imported From Chrome' folder"
roots.remove(chrome[0])
roots[0:0] = chrome
assert not d["workspaces"].get(work), "Work already holds rows"
d["workspaces"][work] = [
    {"type": "folder", "id": "c108big", "title": "C108 big", "open": False, "children": big},
    {"type": "folder", "id": "c108pair", "title": "C108 pair", "open": True,
     "children": [item("c108p1", "C108 P1", "https://c108-p1.test/"), item("c108p2", "C108 P2", "https://c108-p2.test/")]},
    {"type": "folder", "id": "c108q", "title": "C108 pair2", "open": True,
     "children": [item("c108q1", "C108 Q1", "https://c108-q1.test/"), item("c108q2", "C108 Q2", "https://c108-q2.test/")]}]
open(path, "w", encoding="utf-8").write(json.dumps(d, ensure_ascii=False))
'@
$seedFile = "$env:TEMP\check-108-seed.py"
[IO.File]::WriteAllText($seedFile, $seed)
& python -I $seedFile "$prof\Default\Workspace Pins" $canary $work
if ($LASTEXITCODE -ne 0) { Abort "the folders were not added to $prof's pins" }
Remove-Item -LiteralPath $log -EA SilentlyContinue
$scr = [E18Input]::Screen()

try {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--remote-debugging-port=0", "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")).Id
    $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 60
    [E18Input]::Place($script:main, 40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
    Start-Sleep (3 * $slow)
    $port = (Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1).Trim()
    Say "browser $($script:bpid) from $exe, log $log, DevTools $port"
    # The workspace a launch starts in is not logged: the big Canary first (its new draw tells), so that every Show
    # after it is a switch that logs.
    $drew = "pins: drew \d+ row\(s\) of '$canary'"
    $c = Count $drew
    Say "Shift+Alt+6 (the big Canary): $(Keys '%+6')"
    if (-not (WaitLog $drew ($c + 1) 30)) { throw "the big Canary was not shown" }
    Start-Sleep (2 * $slow)

    # S1 (in Work, as D2 M1 D1): the page in front closes last -- P2 is the tab left last, so the old order landed on it.
    # S1 and D2 need no big window: they run before Open all.
    Show '%+2' $work
    if (Want "S1") {
        $r = "P1 $(Press $script:main 'C108 P1')"; $null = WaitLog "pins: opened item 'c108p1'" 1 10; Start-Sleep (1 * $slow)
        $r += "; P2 $(Press $script:main 'C108 P2')"; $null = WaitLog "pins: opened item 'c108p2'" 1 10; Start-Sleep (1 * $slow)
        $r += "; P1 $(Press $script:main 'C108 P1')"; Start-Sleep (2 * $slow)
        $c = Count "pins: selected 2 row\(s\)"
        $r += "; $(ClickRow 'C108 P1' -Ctrl); $(ClickRow 'C108 P2' -Ctrl)"
        $sel = WaitLog "pins: selected 2 row\(s\)" ($c + 1) 10
        $k0 = Picks
        $x = RowCommand "C108 P1" '^Close$'
        $closed = WaitLog "pins: closed the open pages of 2 selected row\(s\)" 1 10
        Start-Sleep (2 * $slow)
        $both = (Count "closed the page of pinned item 'c108p[12]'") -eq 2
        $k = (Picks) - $k0
        # The selection stays after Close; the next plain press lets go of it.
        Verdict "S1 R2-11 P1 P2 P1 shown, both selected ($r; selected 2: $sel), Close ($($x.r); logged: $closed; both closed: $both): $k 'last used tab' pick(s) (want 1; the old: 2)" ($sel -and $closed -and $both -and $k -eq 1)
    }
    if (Want "D2") {
        $r = "Q1 $(Press $script:main 'C108 Q1')"; $null = WaitLog "pins: opened item 'c108q1'" 1 10; Start-Sleep (1 * $slow)
        $r += "; Q2 $(Press $script:main 'C108 Q2')"; $null = WaitLog "pins: opened item 'c108q2'" 1 10; Start-Sleep (1 * $slow)
        $r += "; Q1 $(Press $script:main 'C108 Q1')"; Start-Sleep (2 * $slow)
        $k0 = Picks
        $gone = "pins: deleted 'c108q' \(2 item\(s\), 2 open page\(s\) closed"
        $d = RowCommand "C108 pair2" '^Delete folder$' '^Delete folder$' $gone 15
        $gone = (Count $gone) -eq 1
        Start-Sleep (2 * $slow)
        $k = (Picks) - $k0
        Verdict "D2 R2-11 Q1 Q2 Q1 shown ($r), Delete folder ($($d.r); 2 pages closed: $gone): $k 'last used tab' pick(s) (want 1; the old: 2)" ($gone -and $k -eq 1)
    }
    # The rows that need the big window, run only when one is asked for.
    function BigRows {

    # S0 (in the big Canary): Open all on "Imported From Chrome" -- its confirm's button reads "Open all" too.
    Show '%+6' $canary
    $o = RowCommand "Imported From Chrome" '^Open all$'
    Start-Sleep -Milliseconds (800 * $slow)
    $o2 = PopupPress '^Open all$' 20
    $opened = "pins: opened (\d+) page\(s\) of folder '$chrome[^']*' in (\d+) ms"
    $done = WaitLog $opened 1 900
    $l = @(Lines $opened) | Select-Object -Last 1
    $n = if ($l) { [int]$l.Matches[0].Groups[1].Value } else { 0 }
    $script:numbers["S0"] = if ($l) { [int]$l.Matches[0].Groups[2].Value } else { -1 }
    Verdict "S0 Open all on 'Imported From Chrome' ($($o.r); confirm $o2): $n page(s) in $($script:numbers['S0']) ms (want 3163)" ($done -and $n -eq 3163)
    if (-not $done) { throw "Open all did not finish: no big window" }
    Start-Sleep (5 * $slow)

    Show '%+2' $work
    if (Want "M1") {
        # The selection's menu of two folders, none of their 1,161 pages open.
        $c = Count "pins: selected 2 row\(s\)"
        $s1 = ClickRow "C108 big" -Ctrl; $s2 = ClickRow "C108 pair" -Ctrl
        $sel = WaitLog "pins: selected 2 row\(s\)" ($c + 1) 10
        NoPopups
        $before = @(Popups)
        $m = Timed { $c = ClickRow "C108 big" -Right; $w = NewPopup $before 300; "$c; menu $(if ($w -ne [IntPtr]::Zero) { 'shown' } else { 'none' })" }
        $menu = WaitLog "pins: menu for 2 selected row\(s\)" 1 10
        NoPopups
        # Esc lets go of the selection (the focused row takes it): D1's right-click is then the folder's own menu.
        $c = Count "pins: selection cleared"
        $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
        if (-not (WaitLog "pins: selection cleared" ($c + 1) 10)) { Say "M1 the selection was not let go" }
        $script:numbers["M1"] = $m.max
        Verdict "M1 R2-6 the selection's menu of 'C108 big' + 'C108 pair' ($s1; $s2; selected 2: $sel; $($m.r); logged: $menu): max $($m.max) ms, busy $($m.busy) ms (want under 1000)" ($sel -and $menu -and $m.r -match 'menu shown' -and $m.max -lt 1000)
    }
    if (Want "D1") {
        # Delete folder of 1,159 closed pages; the Archive takes each.
        $gone = "pins: deleted 'c108big' \(1159 item\(s\), 0 open page\(s\) closed, 1159 archived\)"
        $d = RowCommand "C108 big" '^Delete folder$' '^Delete folder$' $gone 600
        $ok = (Count $gone) -eq 1
        $script:numbers["D1"] = $d.max
        Verdict "D1 R2-6 Delete folder 'C108 big' ($($d.r); logged: $ok): max $($d.max) ms, busy $($d.busy) ms (want under 2000)" ($ok -and $d.max -ge 0 -and $d.max -lt 2000)
    }

    Show '%+6' $canary
    if ((Want "T1") -or (Want "R1")) {
        # Two Today tabs of the big Canary (/json/new opens them in the workspace on screen).
        $a = Invoke-RestMethod -Method Put "http://127.0.0.1:$port/json/new?https://t108a.test/"
        Start-Sleep (2 * $slow)
        $b = Invoke-RestMethod -Method Put "http://127.0.0.1:$port/json/new?https://t108b.test/"
        Start-Sleep (3 * $slow)
    }
    if (Want "T1") {
        # Shown in turn under Chrome's own trace ("toplevel": every task a thread runs, how long, and where it was
        # posted from). Graded by the pinned rows' state pass alone -- UpdateRowStates, the task ScheduleRowStates
        # posts -- not by the window's busy time, which is recorded: ~75% of that is the vertical tab strip laid out
        # again on every switch (BrowserView::Layout, ~340 ms at 3,240 tabs; LOCAL.md 142), which R2-12 does not
        # touch. The red (107) was not traced; its pass, from the busy time's drop, ~150-170 ms. A stack sampler
        # (cdb and DebugBreakProcess) was tried first: its breaks stopped coming after a few reads.
        # -Trace a,b: those categories too, and a 7 s trace with no change ($Tag-t1-trace-still.jsonl).
        $sock = [Net.WebSockets.ClientWebSocket]::new()
        $sock.ConnectAsync([Uri](Invoke-RestMethod "http://127.0.0.1:$port/json/version").webSocketDebuggerUrl,
            [Threading.CancellationToken]::None).Wait()
        function WsSend([string]$s) {
            $by = [Text.Encoding]::UTF8.GetBytes($s)
            $sock.SendAsync([ArraySegment[byte]]::new($by), 'Text', $true, [Threading.CancellationToken]::None).Wait()
        }
        function WsRecv {
            $buf = [byte[]]::new(1MB); $ms = [IO.MemoryStream]::new()
            do {
                $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf), [Threading.CancellationToken]::None).GetAwaiter().GetResult()
                $ms.Write($buf, 0, $r.Count)
            } while (-not $r.EndOfMessage)
            [Text.Encoding]::UTF8.GetString($ms.ToArray())
        }
        # One trace while `act` runs, its output passed on; each message of the trace's data a line of `file`.
        function Traced([string]$file, [int]$n, [scriptblock]$act) {
            $cats = @(@('toplevel') + @($Trace | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() }) |
                      Select-Object -Unique | ForEach-Object { '"' + $_ + '"' }) -join ','
            WsSend ('{"id":' + $n + ',"method":"Tracing.start","params":{"traceConfig":{"includedCategories":[' + $cats +
                ']},"transferMode":"ReportEvents"}}')
            while ((WsRecv) -notmatch ('"id":' + $n + '\b')) {}
            & $act
            WsSend ('{"id":' + ($n + 1) + ',"method":"Tracing.end"}')
            $w = [IO.StreamWriter]::new($file)
            do {
                $m = WsRecv
                if ($m -match '"method":"Tracing.dataCollected"') { $w.WriteLine($m) }
            } while ($m -notmatch '"method":"Tracing.tracingComplete"')
            $w.Close()
        }
        $changes = "$ws\$Tag-t1-trace-change.jsonl"
        $busy = @(Traced $changes 1 {
            foreach ($i in 0..10) {
                $id = if ($i % 2) { $b.id } else { $a.id }
                $t = Timed { $null = Invoke-RestMethod "http://127.0.0.1:$port/json/activate/$id"; Start-Sleep -Milliseconds 700 }
                if ($i) { $t.busy }   # the first one warms up
            }
        })
        if ($Trace) { Traced "$ws\$Tag-t1-trace-still.jsonl" 3 { Start-Sleep 7 } }
        $sock.Dispose()
        Say "T1 busy per change (recorded): $($busy -join ', ') ms, median $(Median $busy)"
        $p = TaskMs $changes $script:bpid 'workspace_pinned_section_view.cc' 'ScheduleRowStates'
        $mean = if ($p.count) { [Math]::Round($p.total / $p.count, 1) } else { -1 }
        $script:numbers["T1"] = $mean
        Verdict ("T1 R2-12 the pinned rows' pass per tab change (traced, $changes): $($p.count) pass(es), mean $mean ms, " +
                 "longest $([Math]::Round($p.longest, 1)) ms (want under 50; 107's, from its busy time, ~150-170)") ($p.count -ge 5 -and $mean -ge 0 -and $mean -lt 50)
    }
    if (Want "R1") {
        # t108a's tab menu: Chromium's close commands ask HasIndicesClosedByCommand, walking down from the strip's end
        # past the 3,163 open pages (anchored: skipped) to a Today tab.
        $tabNode = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -match '^t108a' }) | Select-Object -First 1
        if (-not $tabNode) { Say "R1 tabs drawn: $(@(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 } | ForEach-Object { $_.name }) -join ' | ')"; throw "no t108a tab drawn" }
        $maxes = @(foreach ($i in 1..3) {
            NoPopups
            $before = @(Popups)
            $t = Timed { $c = [E18Input]::Click($script:main, $tabNode.l + [int]($tabNode.w * 0.4), $tabNode.t + [int]($tabNode.h / 2), $true); $w = NewPopup $before 60; Start-Sleep -Milliseconds 300; "$c, menu $($w -ne [IntPtr]::Zero)" }
            Say "R1 right-click $i : $($t.r), max $($t.max) ms, busy $($t.busy) ms"
            $t.max
        })
        NoPopups
        Relative "R1" "R2-8 a Today tab's menu, median max" (Median $maxes)
    }
    if (Want "C1") {
        # Home holds one Today tab. With the favorites closed it is Home's only Ctrl+Tab stop, so each press walks every
        # other tab of the strip and lands back on it: no tab change, so no state pass (T1's) -- the walk alone. Each
        # favorite is closed by its own menu's "Close Ctrl+W" (a guarded right-click); the menu's names are printed
        # when it has none.
        $shut = @(foreach ($i in 1..4) {
            $f = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -match ' - Pinned' }) | Select-Object -First 1
            if (-not $f) { break }
            NoPopups
            $before = @(Popups)
            $c = [E18Input]::Click($script:main, $f.l + [int]($f.w / 2), $f.t + [int]($f.h / 2), $true)
            $w = NewPopup $before
            if ($w -eq [IntPtr]::Zero) { "'$($f.name)' $c, no menu"; continue }
            Start-Sleep -Milliseconds (500 * $slow)
            $items = @(Nodes $w | Where-Object { $_.shown -and $_.name })
            $pick = @($items | Where-Object { $_.name -match '^Close\b' -and $_.name -notmatch '^Close (other|tabs|all)' }) | Select-Object -First 1
            if (-not $pick) { NoPopups; "'$($f.name)' $c, the menu: $(@($items | ForEach-Object { $_.name }) -join ' | ')"; continue }
            "'$($f.name)' $c, '$($pick.name)' $(Msaa $w @('-Name', $pick.name, '-Role', $pick.role))"
            Start-Sleep (2 * $slow)
        })
        $left = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -match ' - Pinned' }).Count
        Say "C1 the favorites: $($shut -join '; '); left: $left"
        Show '%+1' "default"
        $b8 = @(foreach ($i in 1..8) { (Timed { [E18Input]::Keys([uint32]$script:bpid, $false, 0x09); Start-Sleep -Milliseconds 300 }).busy })
        Say "C1 busy per Ctrl+Tab: $($b8 -join ', ') ms"
        if ($left -eq 0) { Relative "C1" "R2-8 Ctrl+Tab's walk round the hidden tabs, median busy" (Median $b8) } else { Verdict "C1 the favorites closed first (left: $left)" $false }
        Show '%+6' $canary
    }
    if (Want "D3") {
        # Delete folder with its 3,163 pages open.
        $gone = "pins: deleted '$chrome[^']*' \(3163 item\(s\), 3163 open page\(s\) closed"
        $d = RowCommand "Imported From Chrome" '^Delete folder$' '^Delete folder$' $gone 1800
        $ok = (Count $gone) -eq 1
        Say "D3 Delete folder 'Imported From Chrome' ($($d.r); logged: $ok): max $($d.max) ms, busy $($d.busy) ms"
        if ($ok) { Relative "D3" "R2-11 Delete folder of 3,163 open pages, max" $d.max } else { Verdict "D3 the delete was logged" $false }
    }
    }
    if ($big) { BigRows }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    NoPopups
    $q = "the browser was not running"
    if (Running) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date
        while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 120 * $slow) { Start-Sleep 1 }
        $q = if (Running) { "NOT closed in 120 s" } else { "closed in $([Math]::Round(((Get-Date) - $t0).TotalSeconds)) s" }
    }
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    if ($left.Count) { $q += ", $($left.Count) process(es) force-stopped" }
}
$markers = if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } else { -1 }
Verdict "Z crash markers in the log (the quit: $q): $markers" ($markers -eq 0)
[IO.File]::WriteAllText($numFile, ($script:numbers | ConvertTo-Json))
Say "numbers: $(($script:numbers.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ')"
$verdict = if ($script:failed -or $script:passed -lt $expect) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) want=$expect verdict=$verdict"
exit [int]($verdict -ne "PASS")
