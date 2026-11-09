param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [ValidateSet("plain", "pinned")][string]$Scene = "pinned",
      [ValidateSet("below", "top", "self")][string]$Menu = "below", [ValidateSet("Work", "Home")][string]$Workspace = "Work", [switch]$Keep)
# E19.1: a Today split view drawn broken (the owner's try of E19, step 7). Hands-free: no real mouse, no keys -- the
# tab menu is opened by a right-click POSTED to the window (PostMessage), its item pressed through MSAA.
# A fresh copy of the smoke profile with the made-up Arc file's 3 pinned splits seeded into Work (e19-seed-splits.py), then:
#   -Scene pinned  the 3 pinned splits opened first (hidden rows in the Today list, as in the owner's try); plain: not
#   two pages opened from outside (a new tab: 42 puts it at the top of Today), alpha first, then bravo
#   -Menu below    the upper Today tab in front, the lower one gets the menu; top: the lower in front, the upper the menu
#   -Menu self     the menu on the tab in front: Chromium adds a NEW tab below it and makes the two a split
#   -Workspace Home  all of it in Home (the default workspace) instead of Work
#   then right-click > "New split view with current tab" ("Add tab to new split view" on the tab in front).
# The strip is read through Chromium's UI DevTools (ui-tree.py): PASS = one split row holding both pages, both
# drawn, and neither page drawn as a row of its own. A screenshot of the window for Claude's eyes.
# -Scene pinned then also unpins the first (open) pinned split through its row menu: PASS = it lands at the top of
# Today as one split row with both halves drawn (before patch 66: an EMPTY row, both halves hidden).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\repro-e191.ps1 [-OutDir Dcheck] [-Scene plain] [-Menu self] [-Workspace Home] [-Keep]
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$name   = "e191-$Workspace-$Scene-$Menu$suffix"
$prof   = "$ws\testprofile-e191$suffix"
$log    = "$ws\$name-run.log"
$pages  = "$ws\e191-pages"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$script:failed = 0; $script:passed = 0; $script:win = [IntPtr]::Zero
function Say([string]$s) { Write-Host $s }
function Verdict($what, $ok) { if ($ok) { Say "PASS  $what"; $script:passed++ } else { Say "FAIL  $what"; $script:failed++ } }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Msaa([object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$script:win) @a }
function Tab([string]$title) {
    foreach ($r in @(Msaa @("-List", "-Rect"))) {
        if ($r -match "^\s*$([regex]::Escape($title))\|0x25\|@(-?\d+),(-?\d+),(\d+),(\d+)$") {
            return [pscustomobject]@{ l = [int]$Matches[1]; t = [int]$Matches[2]; w = [int]$Matches[3]; h = [int]$Matches[4] }
        }
    }
}
function Tree { & python -I "$here\ui-tree.py" $prof }
# The Today list's rows (depth 1 of ui-tree.py's print), each split row with its two halves (depth 2).
function Rows([string[]]$tree) {
    $rows = @(); $cur = $null
    foreach ($ln in $tree) {
        $depth = ($ln.Length - $ln.TrimStart().Length) / 2
        $title = if ($ln -match '"(.*)"$') { $Matches[1] } else { "" }
        $shown = $ln -notmatch "INVISIBLE|not-drawn"
        if ($depth -eq 1) { $cur = [pscustomobject]@{ split = $ln.TrimStart() -like "SplitTabView*"; shown = $shown; title = $title; halves = @() }; $rows += $cur }
        elseif ($depth -eq 2 -and $cur -and $cur.split) { $cur.halves += [pscustomobject]@{ title = $title; shown = $shown } }
    }
    $rows
}
# The halves of the drawn split row holding a page titled $title (none: @()).
function HalvesOf($rows, [string]$title) { $s = @($rows | Where-Object { $_.split -and $_.shown -and ($_.halves.title -contains $title) })[0]; if ($s) { @($s.halves) } else { @() } }
function Shot([string]$png) {
    Add-Type -AssemblyName System.Drawing
    $cl = [E18Input]::Client($script:win)
    $bmp = New-Object System.Drawing.Bitmap $cl[2], $cl[3]
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($cl[0], $cl[1], 0, 0, $bmp.Size); $bmp.Save($png) } finally { $g.Dispose(); $bmp.Dispose() }
}
if (-not ("PostRC" -as [type])) { Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class PostRC {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  // A right-click delivered as window messages: the real mouse never moves, the window need not be in front.
  public static string RightClick(IntPtr h, int sx, int sy) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    POINT p; p.x = sx; p.y = sy; ScreenToClient(h, ref p);
    IntPtr l = new IntPtr((p.y << 16) | (p.x & 0xFFFF));
    PostMessage(h, 0x0200, IntPtr.Zero, l);    // WM_MOUSEMOVE
    PostMessage(h, 0x0204, new IntPtr(2), l);  // WM_RBUTTONDOWN, MK_RBUTTON
    PostMessage(h, 0x0205, IntPtr.Zero, l);    // WM_RBUTTONUP
    return "right-click posted at " + p.x + "," + p.y;
  }
}
"@ }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Say "ABORT: a fork browser is already running"; exit 1 }
if (-not (Test-Path -LiteralPath $exe)) { Say "ABORT: no $exe"; exit 1 }
E18InputType
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime); $Workspace, scene $Scene, menu $Menu; Windows animations $(if ([E18Input]::Animations()) { 'ON' } else { 'OFF' })"
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Say "ABORT: the profile copy failed"; exit 1 }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$null = & python "$here\e19-seed-splits.py" $prof
if ($LASTEXITCODE -ne 0) { Say "ABORT: seeding failed"; exit 1 }
$env:HELIUM_ARC_SIDEBAR = "$ws\arc-made-up\StorableSidebar.json"  # the repair reads Arc's file: the made-up one (LOCAL.md 133)
$null = New-Item -ItemType Directory -Force $pages
Set-Content -Encoding UTF8 -Path "$pages\alpha.html" -Value "<!doctype html><title>alpha page</title><h1>alpha page</h1>"
Set-Content -Encoding UTF8 -Path "$pages\bravo.html" -Value "<!doctype html><title>bravo page</title><h1>bravo page</h1>"
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$server = Start-Process python -ArgumentList "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $pages -WindowStyle Hidden -PassThru
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log }
$bpid = 0
try {
    $bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0",
        "--no-first-run", "--no-default-browser-check", "--enable-ui-devtools=0")).Id
    $t0 = Get-Date
    while ($script:win -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $bpid -EA SilentlyContinue; if ($p) { $script:win = $p.MainWindowHandle } }
    if ($script:win -eq [IntPtr]::Zero) { throw "no browser window" }
    [E18Input]::Place($script:win, 40, 40, 1100, 800)
    $null = WaitLog "pins: re-paired \d+ of \d+" 1 30
    if ($Workspace -eq "Work") {
        Say "      $((Msaa @('-Name', 'Work', '-Role', 0x2B)) -join ' ')"
        $null = WaitLog "active workspace -> '2ab592d4" 1 10
    }
    Start-Sleep (2 * $slow)

    if ($Scene -eq "pinned") {
        $rows = @(Msaa @("-List") | ForEach-Object { if ($_ -match '^\s*(.+ \| .+)\|0x24') { $Matches[1] } })
        foreach ($r in $rows) { $j = Count "joined as one split view"; $null = Msaa @("-Name", $r, "-Role", 0x24); $null = WaitLog "joined as one split view" ($j + 1) 10 }
        Say "      pinned splits opened: $(Count 'joined as one split view') of $($rows.Count)"
        Start-Sleep (1 * $slow)
    }

    $null = Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "http://127.0.0.1:$port/alpha.html"); Start-Sleep (3 * $slow)
    $null = Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "http://127.0.0.1:$port/bravo.html"); Start-Sleep (3 * $slow)

    $a = Tab "alpha page"; $b = Tab "bravo page"
    if (-not $a -or -not $b) { throw "the two Today tabs are not both in the list (alpha $([bool]$a), bravo $([bool]$b))" }
    $upper, $lower = if ($a.t -lt $b.t) { "alpha page", "bravo page" } else { "bravo page", "alpha page" }
    $front, $menuTab = switch ($Menu) { "below" { $upper, $lower } "top" { $lower, $upper } "self" { $upper, $upper } }
    Say "      in front: $front ($((Msaa @('-Name', $front, '-Role', 0x25)) -join ' ')); the menu on: $menuTab"
    Start-Sleep (2 * $slow)
    $other = Tab $menuTab
    Say "      $([PostRC]::RightClick($script:win, $other.l + [int]($other.w / 2), $other.t + [int]($other.h / 2)))"
    Start-Sleep (1 * $slow)
    $item = if ($Menu -eq "self") { "Add tab to new split view" } else { "New split view with current tab" }
    Say "      $((Msaa @('-Popup', '-Name', $item)) -join ' ')"
    Start-Sleep (3 * $slow)

    $after = @(Tree)
    $after | Set-Content -Encoding UTF8 "$ws\$name-tree.txt"
    Shot "$ws\$name.png"
    Say "      after the split ($name-tree.txt, $name.png):"; $after | ForEach-Object { Say "        $_" }
    # The split row = the drawn split holding the page that was in front. PASS: its two halves are both drawn, and no
    # page of it (nor the page the menu was on) is ALSO drawn as a row of its own.
    $rows = Rows $after
    $halves = HalvesOf $rows $front
    $names = @($halves.title) + @($menuTab) | Select-Object -Unique
    $dup = @($rows | Where-Object { -not $_.split -and $_.shown -and $names -contains $_.title })
    Verdict "the split row holds two pages, both drawn ($((@($halves | Where-Object shown)).Count) of $($halves.Count): $(@($halves | ForEach-Object { "$($_.title)$(if (-not $_.shown) { ' HIDDEN' })" }) -join ' | '))" ($halves.Count -eq 2 -and @($halves | Where-Object shown).Count -eq 2)
    Verdict "no page of the split also drawn as a row of its own ($($dup.Count))" ($dup.Count -eq 0)

    if ($Scene -eq "pinned") {
        $r = @(Msaa @("-List", "-Rect") | ForEach-Object { if ($_ -match '^\s*(.+ \| .+)\|0x24\|@(-?\d+),(-?\d+),(\d+),(\d+)$') { $Matches } })[0]
        if (-not $r) { throw "no pinned split row to unpin" }
        Say "      $([PostRC]::RightClick($script:win, [int]$r[2] + 20, [int]$r[3] + [int]([int]$r[5] / 2))) on the pinned split '$($r[1])'"
        Start-Sleep (1 * $slow)
        $u = Count "pins: unpinned item"
        Say "      $((Msaa @('-Popup', '-Name', 'Unpin')) -join ' ')"
        $null = WaitLog "pins: unpinned item" ($u + 1) 10
        Start-Sleep (2 * $slow)
        $tree = @(Tree)
        $tree | Set-Content -Encoding UTF8 "$ws\$name-unpin-tree.txt"
        Shot "$ws\$name-unpin.png"
        # The unpinned split = the drawn split row that is not the Today split made above (titles of a pinned row and
        # of its pages need not match: a renamed page, one not loaded yet).
        $others = @(Rows $tree | Where-Object { $_.split -and $_.shown -and -not ($_.halves.title -contains $front) })
        $halves = if ($others.Count -eq 1) { @($others[0].halves) } else { @() }
        Verdict "the unpinned split is one Today row, both halves drawn ($((@($halves | Where-Object shown)).Count) of $($halves.Count), $($others.Count) other split row(s); $name-unpin.png)" ($halves.Count -eq 2 -and @($halves | Where-Object shown).Count -eq 2)
    }
} catch {
    Say "ERROR: $_"; $script:failed++
} finally {
    if (-not $Keep -and $bpid -and (Get-Process -Id $bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    }
    if (-not $Keep) { Stop-Process -Id $server.Id -EA SilentlyContinue }
}
$markers = if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling").Count } else { "no log" }
Verdict "crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $name pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
