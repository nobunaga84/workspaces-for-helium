param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "p106", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# Patch 106 (review 2's chunk 4, <local-path>\Helium-workspace\patch-review-2-findings.md R2-16 R2-17 R2-19 R2-20): the import's
# address check, and an Arc import running meanwhile. check-105's shape: a throwaway copy of the smoke profile (Home,
# Work, Canary, Private, Unpin), one launch and one log per row. The rail's + and its items, the confirm's Replace are
# pressed through MSAA (msaa-press.ps1); the Open box is filled by window messages (its File name box, then its OK);
# the Work chip's menu is a REAL right-click (SendInput, guarded). It starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. An Arc import pointed at \\192.0.2.1 (TEST-NET-1) reads for ~40 s
# before Windows gives up (check-99's X5): the window in which one runs. The R2-16/R2-17 address rule itself is
# workspace_transfer_unittest.cc's; this checks the browser around it.
#   pwsh -NoProfile -File local\check-106.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Rows K1,A1]
#   red: the build before 106 (out\Default before the build, 105 on top): ... -Tag p106-red
#   K1 R2-16/17  Import workspaces... of a file whose Archive holds file://fileserver/docs/report.pdf (a closed page of
#                a work share) and whose pinned pages hold file:////fileserver/share/x (four slashes: the old text
#                check let it by): the file is read, "2 left out" logged, the confirm says "Left out: 2 ...", Replace
#                applies it, and neither address is in the store files after (the old: the whole file refused)
#   A1 R2-19     the Work chip's "Delete workspace": enabled, then greyed while an Arc import reads
#   A2 R2-20     a second window opened; Import workspaces... in the first (its Open box up), Import from Arc... in the
#                second, then the file picked: refused, "Import from Arc is still running", nothing applied (the old:
#                the confirm, and Replace applied the file mid-import)
#   E1 R2-20's  the same for Export workspaces... (its Save box up in the first window, then saved): refused, no file
#      race     written (the old: the file written mid-import). Its red is 106's first build, before the review's fix
#   Z            0 crash markers in the logs (case-sensitive, DanglingPtr too)
# -Rows K1,A2: only those rows (and Z). A pass needs every verdict run ($total).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows K1,A2` passes ONE string "K1,A2": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$files   = "$ws\$Tag-files"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$every   = @("K1", "A1", "A2", "E1")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 1   # + Z
$dots    = [char]0x2026
$plus    = "New tab, workspace or search"
$import  = "Import workspaces$dots"
$export  = "Export workspaces$dots"
$arc     = "Import from Arc$dots"
$arcFile = "\\192.0.2.1\c106\StorableSidebar.json"
# The lines graded, case-sensitively.
$holds   = "\[workspaces\] import: the file holds [^\r\n]*"
$refused  = "\[workspaces\] import: refused: ([^\r\n]*)"
$applied  = "\[workspaces\] import: applied"
$exported = "\[workspaces\] export: (refused[^\r\n]*|wrote|could not)"
$arcRead  = "\[workspaces\] arc import: reading"
$arcEnd   = "\[workspaces\] arc import: (nothing imported|done:)"

$script:passed = 0; $script:failed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero; $script:logs = @()
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
# The text of the first line matching `re` (its first group when it has one), or "".
function First([string]$re) { $l = @(Lines $re); if (-not $l.Count) { return "" }; $g = $l[0].Matches[0].Groups; if ($g.Count -gt 1) { $g[1].Value } else { $g[0].Value } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA and the menus, as check-105's -------------------------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $script:prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# The process's menus, bubbles and the Open box: its shown windows that are no browser window.
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { if (-not (Running)) { return }; foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
# A popup that was not in `before`, once one shows (or zero).
function NewPopup($before, [int]$s = 10) {
    $t0 = Get-Date
    do { $n = @(Popups | Where-Object { $before -notcontains $_ }); if ($n.Count) { return $n[0] }; Start-Sleep -Milliseconds 300 } while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow)
    [IntPtr]::Zero
}
# The + of browser window `win`, then `item` in the menu it opened (found by its handle: the Open box or the import's
# progress box may be up too).
function MenuItem([IntPtr]$win, [string]$item) {
    $before = @(Popups)
    $r = Press $win $plus 57
    $menu = NewPopup $before
    if ($menu -eq [IntPtr]::Zero) { return "+: $r; no menu" }
    "+: $r; $(Press $menu $item 0)"
}
# The Work chip's menu opened by a guarded right-click: its "Delete workspace" line with -States, then closed.
function DeleteLine {
    NoPopups
    $n = NodeIn (Nodes $script:main) "Work" 0x2B
    if (-not $n) { return "no Work chip drawn" }
    $before = @(Popups)
    $r = [E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $true)
    if ($r -ne "right-clicked") { return $r }
    $menu = NewPopup $before
    if ($menu -eq [IntPtr]::Zero) { return "$r; no menu" }
    Start-Sleep -Milliseconds (500 * $slow)
    $line = @(Msaa $menu @("-List", "-States") | Where-Object { $_ -match '^\s*Delete workspace\|' }) | Select-Object -First 1
    NoPopups
    if ($line) { $line.Trim() } else { "$r; no Delete workspace item" }
}

# ---- the Open box, by window messages ---------------------------------------------------------------------------------
# Chrome shows it from a utility process of its own (chrome_select_file_dialog_factory.cc), whose controls UI
# Automation does not reach: found by its class and title, its File name box (the first Edit in a combo box: id 1148
# in the Open box, 1001 in the Save box) given the path by WM_SETTEXT, then the box sent WM_COMMAND IDOK, what its
# Open or Save button (id 1) sends.
if (-not ("OpenBox106" -as [type])) {
Add-Type -TypeDefinition @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class OpenBox106 {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static IntPtr Find(string title, out uint pid) { IntPtr h = FindWindow("#32770", title); pid = 0; if (h != IntPtr.Zero) GetWindowThreadProcessId(h, out pid); return h; }
  public static string Pick(IntPtr box, string path) {
    IntPtr edit = IntPtr.Zero;
    EnumChildWindows(box, delegate (IntPtr h, IntPtr l) {
      var c = new StringBuilder(32); GetClassName(h, c, 32);
      var parent = new StringBuilder(32); GetClassName(GetParent(h), parent, 32);
      if (edit == IntPtr.Zero && c.ToString() == "Edit" && parent.ToString() == "ComboBox") edit = h;
      return true;
    }, IntPtr.Zero);
    if (edit == IntPtr.Zero) return "no File name box";
    SendMessage(edit, 0x000C, IntPtr.Zero, path);       // WM_SETTEXT
    PostMessage(box, 0x0111, new IntPtr(1), IntPtr.Zero);  // WM_COMMAND IDOK
    return "sent";
  }
}
"@
}
# The Open box of Import workspaces (or the Save box of Export workspaces), from a chrome.exe of this build (or zero).
function OpenBox([string]$title = "Import workspaces") { [uint32]$id = 0; $h = [OpenBox106]::Find($title, [ref]$id); if ($h -ne [IntPtr]::Zero -and "$((Get-Process -Id $id -EA SilentlyContinue).Path)" -like "$bin\*") { $h } else { [IntPtr]::Zero } }
# Waits for the Open box and lets it settle (a path given while it is still setting itself up is lost), then picks `path`.
function PickFile([string]$path, [string]$title = "Import workspaces") {
    $t0 = Get-Date
    while (($box = OpenBox $title) -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow) { Start-Sleep -Milliseconds 300 }
    if ($box -eq [IntPtr]::Zero) { return "no Open box" }
    Start-Sleep (3 * $slow)
    $r = [OpenBox106]::Pick($box, $path)
    $t0 = Get-Date
    while ((OpenBox $title) -ne [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    if ((OpenBox $title) -ne [IntPtr]::Zero) { "$r; the box is still up" } else { "picked" }
}
# The import's confirm, once shown: its texts, then Replace pressed. Null when none showed in `s` seconds.
function Confirm($before, [int]$s = 10) {
    $t0 = Get-Date
    do {
        foreach ($w in @(Popups | Where-Object { $before -notcontains $_ })) {
            $nodes = @(Nodes $w | Where-Object { $_.shown })
            if (NodeIn $nodes "Replace" 0x2B) {
                return [pscustomobject]@{ texts = @($nodes | ForEach-Object { $_.name }); pressed = (Press $w "Replace" 0x2B) }
            }
        }
        Start-Sleep -Milliseconds 400
    } while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow)
    $null
}

# ---- profiles, files and launches -------------------------------------------------------------------------------------
# A throwaway copy of the smoke profile at `prof`, Sessions and the Archive emptied, the vertical layout, 280 wide.
function NewProfile([string]$prof) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
    Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath "$prof\Default\Workspace Archive" -EA SilentlyContinue
    & python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "helium.workspaces.enabled=true"
    if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
}
# Chromium's time (microseconds since 1601) for now, as the store files keep it.
function ChromeNow { [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000 + 11644473600000000) }
function Item([string]$id, [string]$url) { (@{ type = "item"; id = $id; title = $id; url = $url } | ConvertTo-Json -Compress) }
function Entry([string]$id, [string]$url) { $n = ChromeNow; (@{ id = $id; url = $url; title = $id; workspace = "default"; reason = "manual"; archived_at = $n; last_active = $n } | ConvertTo-Json -Compress) }
# An export file (the browser's format, every checksum right) of `prof`'s workspace settings and these rows, written
# here: the Python tool refuses to write one that holds a file on another computer.
function ImportFile([string]$prof, [string]$name, [string[]]$pins, [string[]]$entries) {
    $settings = ([IO.File]::ReadAllText("$prof\Default\Preferences") | ConvertFrom-Json -AsHashtable).helium.workspaces
    $members = [ordered]@{
        "prefs.json"        = (@{ helium = @{ workspaces = $settings } } | ConvertTo-Json -Depth 50 -Compress)
        "Workspace Pins"    = '{"version":2,"workspaces":{"default":[' + ($pins -join ",") + ']}}'
        "Workspace Archive" = '{"version":1,"entries":[' + ($entries -join ",") + ']}'
    }
    $meta = [ordered]@{}
    foreach ($k in $members.Keys) {
        $b = [Text.Encoding]::UTF8.GetBytes($members[$k])
        $meta[$k] = [ordered]@{ bytes = $b.Length; sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)).ToLower(); content = $members[$k] }
    }
    $doc = [ordered]@{ format = "helium-workspaces-export"; version = 1; exported_at = "2026-11-07T00:00:00+0800"; source = "check-106"; files = $meta }
    $null = New-Item -ItemType Directory -Force $files
    $path = "$files\$name.json"
    [IO.File]::WriteAllText($path, ($doc | ConvertTo-Json -Depth 10 -Compress))
    $path
}
function Launch([string]$prof, [string]$log, [string]$arcSidebar = "") {
    $script:prof = $prof; $script:log = $log; $script:logs += $log
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")
    # Read by the browser when Import from Arc starts: a variable of its own environment, set for this launch only.
    if ($arcSidebar) { $env:HELIUM_ARC_SIDEBAR = $arcSidebar }
    try { $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id } finally { Remove-Item Env:HELIUM_ARC_SIDEBAR -EA SilentlyContinue }
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
    [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
    Start-Sleep (2 * $slow)
    Say "browser $($script:bpid) from $exe, log $log"
}
function Quit {
    if (-not (Running)) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Running)
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' })$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}
function ReadFile([string]$path) { if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { "" } }
function Row([string]$row, [scriptblock]$body) {
    if ($want -notcontains $row) { return }
    try { & $body } catch { Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ }
    # K1 quits by itself, to read the store files after.
    if (Running) { NoPopups; Say "$row quit: $(Quit)" }
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
# Which build this is, for the record only: the red run is the build without 106.
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "left out (a script or a file on another computer)"
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 106; rows: $($want -join ', ')"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))

try {
    Row "K1" {
        $prof = "$ws\testprofile-$Tag-K1$suffix"
        NewProfile $prof
        $file = ImportFile $prof "k1" @((Item "k106p" "https://k106.example/p"), (Item "k106s" "file:////fileserver/share/x")) @(
            (Entry "k106a" "https://k106.example/a"), (Entry "k106f" "file://fileserver/docs/report.pdf"))
        Launch $prof "$ws\$Tag-K1$suffix-run.log"
        $m = MenuItem $script:main $import
        $before = @(Popups)
        $p = PickFile $file
        $read = WaitLog "$holds|$refused" 1 15
        $c = Confirm $before
        $done = if ($c) { WaitLog $applied 1 15 } else { $false }
        $holdsLine = First $holds; $why = First $refused
        $leftLine = if ($c) { @($c.texts | Where-Object { $_ -match '^Left out: ' }) -join " / " } else { "" }
        Say "K1 $import ($m); the Open box: $p; read $read; holds '$holdsLine'; refused '$why'; confirm $(if ($c) { "shown, '$leftLine', Replace $($c.pressed)" } else { 'none' }); applied $done"
        Say "K1 quit: $(Quit)"
        $pinsFile = ReadFile "$prof\Default\Workspace Pins"; $archiveFile = ReadFile "$prof\Default\Workspace Archive"
        $kept = $pinsFile -match 'k106p' -and $archiveFile -match 'k106a'
        $none = $pinsFile -notmatch 'fileserver' -and $archiveFile -notmatch 'fileserver'
        Verdict "K1 R2-16/17 the file read with '2 left out' ($($holdsLine -match '; 2 left out')), the confirm says it ('$leftLine'), Replace applied ($done), the web rows in ($kept), no fileserver address in the store files ($none) (want all; the old: refused '$why')" (
            $holdsLine -match '; 2 left out' -and $leftLine -match '^Left out: 2 pinned pages or archived tabs' -and $done -and $kept -and $none)
    }
    Row "A1" {
        $prof = "$ws\testprofile-$Tag-A1$suffix"
        NewProfile $prof
        Launch $prof "$ws\$Tag-A1$suffix-run.log" $arcFile
        $idle = DeleteLine
        $m = MenuItem $script:main $arc
        $started = WaitLog $arcRead 1 15
        $during = DeleteLine
        $still = $started -and -not (Count $arcEnd)
        Say "A1 before the import: '$idle'; $arc ($m), reading $started; during it: '$during'; the import still reading then: $still"
        Verdict "A1 R2-19 Delete workspace enabled, then greyed while an Arc import reads (want '|0xC' without UNAVAILABLE, then UNAVAILABLE)" (
            $idle -match '^Delete workspace\|' -and $idle -notmatch 'UNAVAILABLE' -and $during -match '^Delete workspace\|.*UNAVAILABLE' -and $still)
    }
    Row "A2" {
        $prof = "$ws\testprofile-$Tag-A2$suffix"
        NewProfile $prof
        $file = ImportFile $prof "a2" @((Item "a106p" "https://a106.example/p")) @((Entry "a106a" "https://a106.example/a"))
        Launch $prof "$ws\$Tag-A2$suffix-run.log" $arcFile
        # Window B: the running browser opens it for a second start with the same profile.
        Start-Process $exe -ArgumentList "--user-data-dir=$prof", "--new-window", "about:blank"
        $t0 = Get-Date
        while (@([E18Input]::Windows([uint32]$script:bpid)).Count -lt 2 -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow) { Start-Sleep -Milliseconds 400 }
        $b = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main }) | Select-Object -First 1
        if (-not $b) { throw "no second window" }
        Start-Sleep (2 * $slow)
        $mi = MenuItem $script:main $import
        $boxUp = $false; $t0 = Get-Date
        while (-not ($boxUp = (OpenBox) -ne [IntPtr]::Zero) -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow) { Start-Sleep -Milliseconds 300 }
        $ma = MenuItem $b $arc
        $started = WaitLog $arcRead 1 15
        $before = @(Popups)
        $p = PickFile $file
        $read = WaitLog "$holds|$refused" 1 15
        $c = Confirm $before 6
        if ($c) { $null = WaitLog "$applied|$refused" 1 15 }
        $still = $started -and -not (Count $arcEnd)
        $why = First $refused; $did = Count $applied
        Say "A2 window B $b; $import in A ($mi), the Open box up $boxUp; $arc in B ($ma), reading $started; the Open box: $p; confirm $(if ($c) { "shown, Replace $($c.pressed)" } else { 'none' }); refused '$why'; applied x$did; the Arc import still reading then: $still"
        Verdict "A2 R2-20 picked while an Arc import reads: refused with 'Import from Arc is still running', nothing applied (want both, decided while it read: $still)" (
            $boxUp -and $started -and $why -match '^Import from Arc is still running' -and $did -eq 0 -and $still)
    }
    Row "E1" {
        $prof = "$ws\testprofile-$Tag-E1$suffix"
        NewProfile $prof
        $out = "$files\e1-export.json"
        $null = New-Item -ItemType Directory -Force $files
        Remove-Item -LiteralPath $out -EA SilentlyContinue
        Launch $prof "$ws\$Tag-E1$suffix-run.log" $arcFile
        Start-Process $exe -ArgumentList "--user-data-dir=$prof", "--new-window", "about:blank"
        $t0 = Get-Date
        while (@([E18Input]::Windows([uint32]$script:bpid)).Count -lt 2 -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow) { Start-Sleep -Milliseconds 400 }
        $b = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main }) | Select-Object -First 1
        if (-not $b) { throw "no second window" }
        Start-Sleep (2 * $slow)
        $me = MenuItem $script:main $export
        $boxUp = $false; $t0 = Get-Date
        while (-not ($boxUp = (OpenBox "Export workspaces") -ne [IntPtr]::Zero) -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow) { Start-Sleep -Milliseconds 300 }
        $ma = MenuItem $b $arc
        $started = WaitLog $arcRead 1 15
        $p = PickFile $out "Export workspaces"
        $null = WaitLog $exported 1 15
        $still = $started -and -not (Count $arcEnd)
        $said = First $exported
        Start-Sleep (1 * $slow)
        $written = Test-Path -LiteralPath $out
        Say "E1 window B $b; $export in A ($me), the Save box up $boxUp; $arc in B ($ma), reading $started; the Save box: $p; export '$said'; the file written $written; the Arc import still reading then: $still"
        Verdict "E1 R2-20's race for Export: saved while an Arc import reads: refused, no file (want both, decided while it read: $still)" (
            $boxUp -and $started -and $said -match '^refused, an Arc import is running' -and -not $written -and $still)
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q = Quit
}
$markers = 0
foreach ($l in $script:logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($script:logs.Count) log(s) (the last quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
