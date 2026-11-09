param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c93", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [switch]$Zen)
# Patch 93 (the slim chunk, upstream-slim.md): the "Workspace settings..." bubble on the rail's "+" menu, and the
# Settings page left with two fork rows. On a throwaway copy of the smoke profile, Sessions emptied, the sidebar 280
# wide, and the four moved settings seeded as the old Settings rows would have left them: Archive tabs after 7 days
# (10080), Tab style Roomy 40, Smooth scrolling OFF, wider sidebar OFF. Menu items, dropdown items and switches are
# pressed through MSAA (no mouse); the Settings page is read and set through DevTools. It starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. One launch, one log.
#   pwsh -NoProfile -File local\check-93.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0]
#   setup  the window opened on Home
#   B1     "+" > Workspace settings...: "settings: opened"; the bubble shows 7 days, Roomy 40, both switches off
#          (the values from before the slim chunk survive: the same prefs)
#   B2     Archive tabs after > 1 day, Tab style > Spacious 42, both switches pressed: the four "settings: <pref> ->"
#          lines (1440, 42, 1, 1) and "tab style: row height 40 -> 42" (the strip follows at once)
#   B3     Escape, then the bubble again: it shows 1 day, Spacious 42, both on
#   S1     chrome://settings/appearance: its helium.workspaces rows are exactly enabled and little_window; the on/off
#          row still saves (settingsPrivate setPref false/getPref false, then true/true); tab_row_height is refused
#   P1     after the quit, Preferences holds 1440, 42, true, true
#   ZB     -Zen only (zen mode on, sidebar unpinned -- the daily browser's setting; patch 94): the bubble B1 opened
#          lies inside the window, and "zen: box over the page" is logged. A box anchored in the hidden sidebar
#          opens off its left edge: run with -BinDir on a build without 94 for the red control
#   Z      0 crash markers in the log (case-sensitive, DanglingPtr too)
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Zen) { '-zen' })$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$dflt    = "$prof\Default"
$script:log = "$ws\$Tag$suffix-run.log"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = if ($Zen) { 8 } else { 7 }
$plus    = "New tab, workspace or search"
$opened  = "\[workspaces\] settings: opened"
$wrote   = "\[workspaces\] settings: helium\.workspaces\.(\w+) -> (\d+)"
$style   = "\[workspaces\] tab style: row height (\d+) -> (\d+)"

$script:passed = 0; $script:failed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero
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
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA, as check-92's ----------------------------------------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Popups { PopupWindows ([uint32]$script:bpid) $script:main }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B); Start-Sleep -Milliseconds 400 } }
# A window's nodes with -Values: name, role, shown, on (a switch), value (a dropdown's item).
function ValNodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Values") | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?(\|CHECKED)?\|=(.*)$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); shown = -not $Matches[3]; on = [bool]$Matches[4]; value = $Matches[5] }
        }
    })
}
# The first control (e18-lib's Controls) in a menu or bubble named `re`, pressed with accDoDefaultAction: a menu item,
# a dropdown (opens its list), a switch (flips it).
function PopupPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Controls (ValNodes $w) { $args[0].shown } | Where-Object { $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 400
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re'"
}
# Zen: the unpinned sidebar shows only while the mouse is at the window's left edge (it slides away soon after the
# launch, sooner than a Dcheck build reaches setup's row), so its rows can be read and its "+" pressed.
function Reveal {
    if (-not $Zen) { return }
    $cl = [E18Input]::Client($script:main)
    $script:reveal = [E18Input]::Hover($script:main, $cl[0] + 3, $cl[1] + [int]($cl[3] / 2))
    Start-Sleep -Milliseconds (800 * $slow)
}
# "+" > Workspace settings...; true once its "opened" line is logged.
function OpenBubble {
    NoPopups
    $c = Count $opened
    Reveal
    $r1 = "$(Msaa $script:main @('-Name', $plus))"
    Start-Sleep -Milliseconds (800 * $slow)
    # A stem: MSAA can hand the ellipsis back as '?', and the red control's 154 build (-BinDir) has the plural.
    $r2 = PopupPress '^Workspaces? settings'
    [pscustomobject]@{ ok = (WaitLog $opened ($c + 1) 10); said = "$($r1.Substring(0, [Math]::Min(50, $r1.Length))); $r2" }
}
# What the open bubble shows: "archive=<item>; style=<item>; smooth=<on>; wide=<on>", or what the popups hold.
function Shown {
    Start-Sleep -Milliseconds (600 * $slow)
    foreach ($w in Popups) {
        $nodes = Controls (ValNodes $w) { $args[0].shown }
        $one = { param($name) @($nodes | Where-Object { $_.name -eq $name }) | Select-Object -First 1 }
        $a = & $one "Archive tabs after"
        if (-not $a) { continue }
        $t = & $one "Tab style"; $s = & $one "Smooth scrolling in the tab list"; $wd = & $one "Allow a wider sidebar"
        return "archive=$($a.value); style=$($t.value); smooth=$($s.on); wide=$($wd.on)"
    }
    "no bubble (popups: $((@(Popups | ForEach-Object { ValNodes $_ | Where-Object shown | ForEach-Object { "$($_.name)/0x$($_.role.ToString('X'))" } }) | Select-Object -First 30) -join ' | '))"
}
# The open Workspace settings bubble's window, or zero.
function BubbleWindow {
    foreach ($w in Popups) { if (@(ValNodes $w | Where-Object { $_.shown -and $_.name -eq "Archive tabs after" }).Count) { return $w } }
    [IntPtr]::Zero
}
# A dropdown `name` opened and the item starting `item` picked. B2's "Spacious, 42 px" is hook shrink part 3's label: the
# red control's 154 build (-BinDir) has the old labels, so its B rows fail there: it is run for ZB's verdict alone.
function Pick([string]$name, [string]$item) { "$(PopupPress "^$([regex]::Escape($name))$"); $(Start-Sleep -Milliseconds (600 * $slow); PopupPress "^$([regex]::Escape($item))")" }

function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
    [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
    Start-Sleep (2 * $slow)
    Say "browser $($script:bpid) from $exe, log $($script:log); window dpi $([E18Input]::Dpi($script:main))"
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
function Row([string]$row, [scriptblock]$body) {
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "] settings: opened"
$with93 = $LASTEXITCODE -eq 0
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($with93) { 'WITH' } else { 'WITHOUT' }) patch 93"
if (-not $with93) { Abort "this chrome.dll has no patch 93 ('] settings: opened' is not in it)" }
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for the browser's windows ($free)" }
E18InputType
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$dflt\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
& python -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "helium.workspaces.enabled=true" "helium.workspaces.archive_after_minutes=10080" "helium.workspaces.tab_row_height=40" "helium.workspaces.smooth_scrolling=false" "helium.workspaces.wide_sidebar=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
if ($Zen) {
    & python -I "$here\prefs.py" "$dflt\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false"
    if ($LASTEXITCODE -ne 0) { Abort "zen mode was not seeded into $prof" }
}

try {
    Launch
    Row "setup" {
        Reveal
        $chip = [bool](@(ValNodes $script:main | Where-Object { $_.shown -and $_.name -eq "Home" }).Count)
        Verdict "setup: the window opened, a Home chip drawn $chip" $chip
    }
    Row "B1" {
        $o = OpenBubble
        $s = Shown
        Verdict "B1 + > Workspace settings... ($($o.said)): opened $($o.ok); shows [$s] (want archive=7 days; style=Roomy, 40 px; smooth=False; wide=False)" ($o.ok -and $s -eq "archive=7 days; style=Roomy, 40 px; smooth=False; wide=False")
    }
    if ($Zen) {
        Row "ZB" {
            $w = [E18Input]::Client($script:main)
            # The mouse onto the page, low and right of a centred bubble: zen slides the sidebar away, and a box
            # anchored in it goes with it.
            $away = [E18Input]::Hover($script:main, $w[0] + [int]($w[2] * 0.85), $w[1] + [int]($w[3] * 0.9))
            Start-Sleep -Milliseconds (1500 * $slow)
            $h = BubbleWindow
            $b = if ($h -ne [IntPtr]::Zero) { [E18Input]::Client($h) } else { @() }
            $inside = $b.Count -eq 4 -and $b[0] -ge $w[0] -and $b[1] -ge $w[1] -and $b[0] + $b[2] -le $w[0] + $w[2] -and $b[1] + $b[3] -le $w[1] + $w[3]
            $over = Count "\[workspaces\] zen: box over the page"
            Verdict "ZB zen (reveal: $($script:reveal); mouse away: $away): bubble found $($h -ne [IntPtr]::Zero) at [$($b -join ', ')], inside the window [$($w -join ', ')] $inside; 'zen: box over the page' logged $over time(s) (want 1+)" ($inside -and $over -ge 1)
        }
    }
    Row "B2" {
        $c = Count $wrote; $cs = Count $style
        $p = @((Pick "Archive tabs after" "1 day"), (Pick "Tab style" "Spacious, 42 px"),
               (PopupPress '^Smooth scrolling in the tab list$'), (PopupPress '^Allow a wider sidebar$'))
        $ok = WaitLog $wrote ($c + 4) 10
        $got = @(Lines $wrote | Select-Object -Skip $c | ForEach-Object { "$($_.Matches[0].Groups[1].Value)=$($_.Matches[0].Groups[2].Value)" }) -join ", "
        $live = WaitLog $style ($cs + 1) 10
        $st = @(Lines $style | Select-Object -Skip $cs | ForEach-Object { "$($_.Matches[0].Groups[1].Value) -> $($_.Matches[0].Groups[2].Value)" }) -join ", "
        $want = "archive_after_minutes=1440, tab_row_height=42, smooth_scrolling=1, wide_sidebar=1"
        Verdict "B2 pressed [$($p -join ' | ')]: wrote [$got] (want $want); the strip followed: [$st] (want 40 -> 42)" ($ok -and $got -eq $want -and $live -and $st -eq "40 -> 42")
    }
    Row "B3" {
        NoPopups
        $gone = -not @(Popups).Count
        $o = OpenBubble
        $s = Shown
        Verdict "B3 Escape closed it $gone; reopened ($($o.said)) $($o.ok): shows [$s] (want archive=1 day; style=Spacious, 42 px; smooth=True; wide=True)" ($gone -and $o.ok -and $s -like "archive=1 day; style=Spacious, 42 px*; smooth=True; wide=True")
        NoPopups
    }
    Row "S1" {
        $set = OpenSettings $prof
        $dev = if ($set.ready) { $set.page.webSocketDebuggerUrl } else { $null }
        # The page's helium.workspaces rows, through every shadow root (the page renders in Lit components).
        $keys = "(no page)"
        if ($dev) {
            $walk = "(() => { const k = new Set(); const walk = n => { if (n.shadowRoot) walk(n.shadowRoot); for (const c of n.children || []) walk(c); const p = n.getAttribute && n.getAttribute('pref-key'); if (p && p.startsWith('helium.workspaces.')) k.add(p); }; walk(document.documentElement); return [...k].sort().join(','); })()"
            $t0 = Get-Date
            do { $keys = "$(Evaluate $dev $walk)"; if ($keys -and $keys -notlike "error:*") { break }; Start-Sleep 1 } while (((Get-Date) - $t0).TotalSeconds -lt 15 * $slow)
        }
        $en = "helium.workspaces.enabled"
        $off = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('$en', false, '')" }
        $was = if ($dev) { Evaluate $dev "chrome.settingsPrivate.getPref('$en').then(p => p.value)" }
        $on = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('$en', true, '')" }
        $now = if ($dev) { Evaluate $dev "chrome.settingsPrivate.getPref('$en').then(p => p.value)" }
        $moved = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('helium.workspaces.tab_row_height', 30, '')" }
        if ($set.page) { try { $null = Invoke-RestMethod -TimeoutSec 10 -Uri "$($set.base)/close/$($set.page.id)" } catch {} }
        Start-Sleep (2 * $slow)
        Verdict "S1 Settings ($($set.note)): rows [$keys] (want helium.workspaces.enabled,helium.workspaces.little_window); on/off setPref $off/getPref $was, then $on/$now (want True/False, True/True); tab_row_height setPref [$moved] (want anything but True)" ($keys -eq "helium.workspaces.enabled,helium.workspaces.little_window" -and "$off" -eq "True" -and "$was" -eq "False" -and "$on" -eq "True" -and "$now" -eq "True" -and "$moved" -ne "True")
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    if ($script:bpid) { NoPopups }
    $q = Quit
}
$saved = "$(& python -I "$here\prefs.py" "$dflt\Preferences" helium.workspaces.archive_after_minutes helium.workspaces.tab_row_height helium.workspaces.smooth_scrolling helium.workspaces.wide_sidebar)" -replace '\s+', ' '
Verdict "P1 after the quit ($q), Preferences holds [$saved] (want 1440 42 true true)" ($saved.Trim() -eq "1440 42 true true")
$markers = 0
if (Test-Path -LiteralPath $script:log) { $markers = @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count }
Verdict "Z crash markers in $($script:log): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
