param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "p109", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# Patch 109 (review 2's chunk 7, <local-path>\Helium-workspace\patch-review-2-findings.md): R2-9, R2-13, R2-14, R2-21. R2-7 is
# check-98's case F; R2-22 is workspace_archive_unittest's ASnoozedEntryIsKeptUntilItWakes.
# On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin; every workspace's pinned rows
# Example A, Smoke folder, Closed folder, Example D, none open), Sessions and the Archive emptied, the sidebar 280 wide,
# plus, at the end of Work: a SPLIT row "U14 left | U14 right", and the rows "U14 solo" and "U13 page". The pages are
# ServePages' plain "E18 <name>" pages on 127.0.0.1, opened through DevTools (/json/new: in front, in the workspace on
# screen). Launched WITHOUT --helium-workspaces-log-addresses (what L9 grades), so no row reads an address from the
# log. Right-clicks, clicks, keys and the wheel are REAL input (SendInput, guarded); menu items are pressed through
# MSAA. It starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (-IdleMinutes 0: the owner's "Skip the gate").
#   pwsh -NoProfile -File local\check-109.ps1 [-Tag p109-red] [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Rows L9,R21]
#   setup  the window opened on Home, Example A drawn
#   L9   R2-9   Home: l109a anchored from its menu; Ctrl+L, l109b's address typed, Enter: "typed url diverted off
#               anchored tab -> new tab" logged WITHOUT the address (the log names no address unless asked); l109b
#               opened, l109a kept
#   U14A R2-14  Work: u14f in front; Ctrl+click "U14 left | U14 right" and Example D (both closed), the selection's
#               menu > Unpin: the split's two pages open, u14f STILL in front (document.visibilityState)
#   U14B R2-14  a second window (Ctrl+N) on Work presses "U14 solo" (its page opens THERE); the first window, u14f in
#               front: Ctrl+click "U14 solo" and Example A, the selection's Unpin: u14s brought into the first window,
#               u14f still in front
#   U13  R2-13  the second window presses "U13 page"; Workspaces off (settingsPrivate); that window's u13 tab pinned
#               (a favorite, from its menu); Workspaces on; the FIRST window's "U13 page" menu > Unpin: the favorite is
#               not brought over -- no "brought" line, a page opened here instead, two u13 pages open
#   R21  R2-21  a second launch: 30 workspaces, the sidebar collapsed (expand on hover off), the window 720 px tall:
#               "+" inside the window; the last chip (W30) pressed: it scrolls into the window, "+" still in; the wheel
#               up over the column brings Home's chip back down; a picture of the window (<Tag>-r21.png); expand on
#               hover turned on, the pointer on the bar: "+" still inside (a guard; <Tag>-r21-hover.png); the sidebar
#               expanded: "+" inside the window
#   Z           0 crash markers in both logs (case-sensitive, DanglingPtr too)
# -Rows L9,R21: only those rows (and the setup and Z). A pass needs every verdict run ($total).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows L9,R21` passes ONE string "L9,R21": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$dflt    = "$prof\Default"
$logs    = @("$ws\$Tag$suffix-run.log", "$ws\$Tag$suffix-r21-run.log")
$script:log = $logs[0]
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$every   = @("L9", "U14A", "U14B", "U13", "R21")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 2   # + the setup and Z
$splitRow = "U14 left | U14 right"
$plus     = "New tab, workspace or search"
# The lines graded, case-sensitively.
$diverted = "\[workspaces\] typed url diverted off anchored tab -> new tab"
$active   = "\[workspaces\] active workspace -> '([^']*)'"
$selected = "\[workspaces\] pins: selected (\d+) row\(s\)"

$script:passed = 0; $script:failed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero; $script:b = [IntPtr]::Zero; $script:set = $null
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
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA, the menus and the clicks, as check-92's -----------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function IsTab([string]$n, [string]$title) { $n -eq $title -or $n.StartsWith("$title - ") -or ($title -like "E18 *" -and $n -like "*/$($title.Substring(4)).html*") }
function TabIn($nodes, [string]$title) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and (IsTab $_.name $title) }) | Select-Object -First 1 }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
function PressNode([IntPtr]$w, $n) {
    if (-not $n) { return "nothing to press" }
    $r = Press $w $n.name $n.role
    if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
    "'$($n.name)' $r"
}
function OtherPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return PressNode $w $n }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re' (shown: $((@(PopupNames) | Select-Object -First 40) -join ' | '))"
}
function RightClick([IntPtr]$h, $n, [string]$what) {
    if (-not $n) { return "no $what drawn" }
    $r = [E18Input]::Click($h, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $r
}
# A guarded real click on pinned row `title` in window `h`, Ctrl or Shift held ("" for none); a right-click when asked.
function ClickRow([IntPtr]$h, [string]$title, [string]$mod = "", [switch]$Right) {
    $n = NodeIn (Nodes $h) $title 0x24
    if (-not $n) { return "no row '$title' drawn" }
    $vk = @{ ctrl = 0x11; shift = 0x10 }[$mod]
    $pid32 = [uint32]$script:bpid
    if ($vk) { $d = [E18Input]::KeyDown($pid32, $vk); if ($d -ne "sent") { return "key not held: $d" } }
    try { [E18Input]::Click($h, $n.l + [int]($n.w * 0.4), $n.t + [int]($n.h / 2), $Right.IsPresent) }
    finally { if ($vk) { $null = [E18Input]::KeyUp($pid32, $vk) } }
}
# Window `h` in front for a key: one guarded click on its page's blank bottom.
function Front([IntPtr]$h = $script:main) { $c = [E18Input]::Client($h); [E18Input]::Click($h, $c[0] + [int]($c[2] * 0.6), $c[1] + $c[3] - 40, $false) }
# The workspace shown by its chip (the bottom-most push button of that name, a toolbar Home button may come first).
function Go([string]$name, [string]$guid, [IntPtr]$h = $script:main) {
    $nodes = @(Nodes $h)
    if (NodeIn $nodes $name 0x14) { return $true }
    $c = Count $active
    $chips = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq $name })
    if ($chips.Count -eq 1) { $null = Press $h $name 0x2B } else { $n = NodeIn $nodes $name 0x2B; if ($n) { $null = [E18Input]::Click($h, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false) } }
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Nth $active $c)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}
# Ctrl+N with the first window in front: the second window, placed beside, on Work. Kept in $script:b.
function SecondWindow {
    if ($script:b -ne [IntPtr]::Zero) { return "already open" }
    $f = Front
    $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x4E)
    $t0 = Get-Date
    while ($script:b -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow) {
        Start-Sleep 1
        $w = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main }) | Select-Object -First 1
        if ($w) { $script:b = $w }
    }
    if ($script:b -eq [IntPtr]::Zero) { return "no second window ($f; Ctrl+N $k)" }
    # The right half, short of the first window's bottom: the first one's sidebar and its page's bottom (Front's
    # point) stay uncovered.
    $script:boxB = @(($script:box[0] + [int]($script:box[2] / 2)), ($script:box[1] + 60), [int]($script:box[2] / 2), ($script:box[3] - 160))
    Raise $script:b
    Start-Sleep (3 * $slow)
    "opened ($f; Ctrl+N $k), on Work $(Go 'Work' $work $script:b)"
}
# Window `h` put on top of the others again (topmost, not activated), at its own place: a guarded click there then
# finds it under the point.
function Raise([IntPtr]$h) {
    $x = if ($h -eq $script:main) { $script:box } else { $script:boxB }
    [E18Input]::Place($h, $x[0], $x[1], $x[2], $x[3])
    Start-Sleep -Milliseconds (500 * $slow)
}
function Row([string]$row, [scriptblock]$body) {
    if ($row -ne "setup" -and $want -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the pages and DevTools, as check-92's -------------------------------------------------------------------------
function Url([string]$name) { "http://127.0.0.1:$($script:srv.port)/$name.html" }
function Base { "http://127.0.0.1:$($script:port)/json" }
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_ }) } catch { @() } }
function PageOf([string]$name) { @(Targets | Where-Object { $_.type -eq "page" -and $_.url -like "*/$name.html*" }) | Select-Object -First 1 }
function PagesOf([string]$name) { @(Targets | Where-Object { $_.type -eq "page" -and $_.url -like "*/$name.html*" }).Count }
function WaitPage([string]$name) {
    $t0 = Get-Date
    do {
        $t = PageOf $name
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState") -eq "complete") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $name)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
function Show($t) { if (-not $t) { return }; try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# Whether page `name` is the one on screen in its window: "visible" or "hidden".
function Visible([string]$name) { $t = PageOf $name; if ($t) { "$(Evaluate $t.webSocketDebuggerUrl 'document.visibilityState')" } else { "no page" } }
# Workspaces on or off through chrome.settingsPrivate on one settings tab, opened the first time; true once logged.
function SetEnabled([bool]$on) {
    if (-not $script:set) { $script:set = OpenSettings $prof }
    if (-not $script:set.ready) { return $false }
    $c = Count "enabled pref -> $("$on".ToLower())"
    $null = Evaluate $script:set.page.webSocketDebuggerUrl "chrome.settingsPrivate.setPref('helium.workspaces.enabled', $("$on".ToLower()), '')"
    WaitLog "enabled pref -> $("$on".ToLower())" ($c + 1) 10
}

function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $script:b = [IntPtr]::Zero; $script:set = $null; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 15
    [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid) from $exe, DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log); window dpi $([E18Input]::Dpi($script:main))"
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
# The main window's client area, as it is on screen, saved as a PNG (the window is topmost, Place).
function Snap([string]$path) {
    Add-Type -AssemblyName System.Drawing
    $c = [E18Input]::Client($script:main)
    $bmp = [System.Drawing.Bitmap]::new($c[2], $c[3]); $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($c[0], $c[1], 0, 0, $bmp.Size); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); "saved $path" } catch { "no picture: $_" } finally { $g.Dispose(); $bmp.Dispose() }
}
# Whether node `n` lies inside the main window's client area, top to bottom (1 px of slack).
function Inside($n) { if (-not $n) { return $false }; $c = [E18Input]::Client($script:main); $n.t -ge $c[1] - 1 -and $n.t + $n.h -le $c[1] + $c[3] + 1 }
function Spot($n) { if ($n) { "$($n.t)..$($n.t + $n.h)" } else { "not drawn" } }

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
# 108's address line ends "new tab: " in the binary; 109's puts the address after it only when asked.
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "anchored tab -> new tab: "
$with109 = $LASTEXITCODE -ne 0
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($with109) { 'WITH' } else { 'WITHOUT' }) patch 109; rows: $($want -join ', ')"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$dflt\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath "$dflt\Workspace Archive" -EA SilentlyContinue
foreach ($l in $logs) { Remove-Item -LiteralPath $l -EA SilentlyContinue }
& python -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "helium.workspaces.enabled=true"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$script:srv = ServePages $pages @("l109a", "l109b", "u14f", "u14l", "u14r", "u14s", "u13")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
# At the end of Work: the split row, "U14 solo", "U13 page" (a version-2 pins file, E19's split shape).
$seed = @'
import json, sys
p, work, base = sys.argv[1:4]
d = json.load(open(p, encoding='utf-8'))
d['version'] = 2
item = lambda i, t: {'type': 'item', 'id': i, 'title': t, 'url': base + i + '.html'}
d['workspaces'][work] += [{'type': 'split', 'id': 'u14sp', 'children': [item('u14l', 'U14 left'), item('u14r', 'U14 right')]},
                          item('u14s', 'U14 solo'), item('u13', 'U13 page')]
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
'@
& python -I -c $seed "$dflt\Workspace Pins" $work "http://127.0.0.1:$($script:srv.port)/"
if ($LASTEXITCODE -ne 0) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue; Abort "the rows were not seeded into $prof" }

try {
    Launch
    Row "setup" {
        $h = Go "Home" "default"
        Verdict "setup: the window opened on Home ($h), Example A drawn $([bool](NodeIn (Nodes $script:main) 'Example A' 0x24))" ($h -and (NodeIn (Nodes $script:main) "Example A" 0x24))
    }
    Row "L9" {
        $h = Go "Home" "default"
        $null = NewTab "l109a"
        # Anchored from its menu. No "anchor at index" line without the address switch: the diverted line below is
        # the proof, since only an anchored tab diverts.
        $r = RightClick $script:main (TabIn (Nodes $script:main) "E18 l109a") "Today tab 'E18 l109a'"
        $p = if ($r -eq "right-clicked") { "$(OtherPress '^Anchor$'); $(OtherPress '^Anchor to this page(?! instead)')" } else { "not pressed" }
        Start-Sleep (1 * $slow)
        NoPopups
        $c = Count $diverted
        $f = Front
        $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x4C)
        $t = [E18Input]::TypeEnter([uint32]$script:bpid, (Url "l109b"))
        $ok = WaitLog $diverted ($c + 1) 10
        $line = if ($ok) { "$(@(Lines $diverted)[$c].Line)" -replace '^.*?\[workspaces\]', '[workspaces]' } else { "" }
        $named = $line -match 'l109b|127\.0\.0\.1'
        $opened = [bool](WaitPage "l109b"); $kept = [bool](PageOf "l109a")
        $others = @(Lines "l109b" | Where-Object { $_.Line -notmatch 'typed url diverted' }).Count
        Verdict "L9 R2-9 Home $h; l109a anchored ($r; $p); Ctrl+L ($f; $k), l109b's address typed ($t): diverted $ok, '$line' names the address $named (want False); l109b opened $opened, l109a kept $kept; other lines naming l109b: $others" ($h -and $ok -and -not $named -and $opened -and $kept)
    }
    Row "U14A" {
        $w = Go "Work" $work
        $null = NewTab "u14f"
        $pre = Visible "u14f"
        $s = Count $selected
        $c1 = ClickRow $script:main $splitRow "ctrl"; $c2 = ClickRow $script:main "Example D" "ctrl"
        $two = (WaitLog $selected ($s + 2) 6) -and @(Nth $selected ($s + 1))[1] -eq "2"
        $rc = ClickRow $script:main "Example D" -Right
        Start-Sleep -Milliseconds (800 * $slow)
        $u = Count "pins: unpinned 2 selected row\(s\)"
        $q = if ($rc -eq "right-clicked") { OtherPress '^Unpin$' } else { "not pressed" }
        $un = WaitLog "pins: unpinned 2 selected row\(s\)" ($u + 1) 10
        # Opened, not loaded: a page opened behind loads only when shown (kLoadIfVisible).
        $t0 = Get-Date
        do { $both = [bool](PageOf "u14l") -and [bool](PageOf "u14r"); if (-not $both) { Start-Sleep -Milliseconds 500 } } while (-not $both -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
        Start-Sleep (1 * $slow)
        $front = Visible "u14f"
        Verdict "U14A R2-14 Work $w; u14f $pre; Ctrl+click the split row ($c1) and Example D ($c2): 2 selected $two; the selection's menu ($rc) > Unpin ($q): unpinned $un; u14l and u14r open $both; u14f now $front (want visible: the Unpin is in the background)" ($w -and $pre -eq "visible" -and $two -and $un -and $both -and $front -eq "visible")
    }
    Row "U14B" {
        $w = Go "Work" $work
        $sw = SecondWindow
        $o = Count "pins: opened item 'u14s'"
        $pr = PressNode $script:b (NodeIn (Nodes $script:b) "U14 solo" 0x24)
        $there = (WaitLog "pins: opened item 'u14s'" ($o + 1) 10) -and [bool](WaitPage "u14s")
        # The first window in front, u14f on screen in it.
        Raise $script:main
        $f = Front
        if (-not (PageOf "u14f")) { $null = NewTab "u14f" } else { Show (PageOf "u14f") }
        $pre = Visible "u14f"
        $s = Count $selected
        $c1 = ClickRow $script:main "U14 solo" "ctrl"; $c2 = ClickRow $script:main "Example A" "ctrl"
        $two = (WaitLog $selected ($s + 2) 6) -and @(Nth $selected ($s + 1))[1] -eq "2"
        $rc = ClickRow $script:main "Example A" -Right
        Start-Sleep -Milliseconds (800 * $slow)
        $u = Count "pins: unpinned 2 selected row\(s\)"
        $q = if ($rc -eq "right-clicked") { OtherPress '^Unpin$' } else { "not pressed" }
        $un = WaitLog "pins: unpinned 2 selected row\(s\)" ($u + 1) 10
        $brought = WaitLog "pins: brought the page of 'u14s' from another window" 1 10
        Start-Sleep (1 * $slow)
        $front = Visible "u14f"
        $inA = [bool](TabIn (Nodes $script:main) "E18 u14s")
        Verdict "U14B R2-14 Work $w; second window $sw, its 'U14 solo' pressed ($pr): open there $there; first window in front ($f), u14f $pre; Ctrl+click 'U14 solo' ($c1) and Example A ($c2): 2 selected $two; the selection's menu ($rc) > Unpin ($q): unpinned $un, u14s brought $brought, drawn here $inA; u14f now $front (want visible)" ($w -and $there -and $pre -eq "visible" -and $two -and $un -and $brought -and $inA -and $front -eq "visible")
    }
    Row "U13" {
        $sw = SecondWindow
        $bw = Go "Work" $work $script:b
        $o = Count "pins: opened item 'u13'"
        $pr = PressNode $script:b (NodeIn (Nodes $script:b) "U13 page" 0x24)
        $there = (WaitLog "pins: opened item 'u13'" ($o + 1) 10) -and [bool](WaitPage "u13")
        $off = SetEnabled $false
        Start-Sleep (2 * $slow)
        # Helium's word for Pin is "Add to Favorites".
        Raise $script:b
        $rc = RightClick $script:b (TabIn (Nodes $script:b) "E18 u13") "the u13 tab in the second window"
        $q = if ($rc -eq "right-clicked") { OtherPress '^(Pin( tab)?|Add to Favorites)$' } else { "not pressed" }
        Start-Sleep (1 * $slow)
        $fav = [bool](@(Nodes $script:b | Where-Object { $_.shown -and $_.role -eq 0x25 -and (IsTab $_.name "E18 u13") -and $_.name -match ' - Pinned$' }).Count)
        $on = SetEnabled $true
        Start-Sleep (2 * $slow)
        $h = Go "Work" $work
        Raise $script:main
        $o = Count "pins: opened item 'u13'"; $br = Count "pins: brought the page of 'u13'"
        $rc2 = RightClick $script:main (NodeIn (Nodes $script:main) "U13 page" 0x24) "row 'U13 page'"
        $q2 = if ($rc2 -eq "right-clicked") { OtherPress '^Unpin$' } else { "not pressed" }
        $un = WaitLog "pins: unpinned item 'u13'" 1 10
        Start-Sleep (2 * $slow)
        $broughtN = (Count "pins: brought the page of 'u13'") - $br
        $openedN = (Count "pins: opened item 'u13'") - $o
        $n = PagesOf "u13"
        Verdict "U13 R2-13 second window $sw, on Work $bw, 'U13 page' pressed there ($pr): open $there; Workspaces off $off; its u13 tab's menu ($rc) > Pin ($q): a favorite $fav; Workspaces on $on; the first window on Work $h, 'U13 page' menu ($rc2) > Unpin ($q2): unpinned $un; brought from the other window $broughtN (want 0), opened here $openedN (want 1), u13 pages $n (want 2: the favorite kept)" ($bw -and $there -and $off -and $fav -and $on -and $h -and $un -and $broughtN -eq 0 -and $openedN -eq 1 -and $n -eq 2)
    }
    if ($want -contains "R21") {
        Say "quit for R21: $(Quit)"
        $script:log = $logs[1]
        # 25 more workspaces (W06..W30), the sidebar collapsed, no expand on hover (the wheel's pointer would expand
        # it); the window short.
        $more = @'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
items = d['helium']['workspaces']['list']['items']
items += [{'guid': 'r21-%02d' % i, 'title': 'W%02d' % i} for i in range(len(items) + 1, 31)]
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
'@
        & python -I -c $more "$dflt\Preferences"
        & python -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.collapsed_state=true" "vertical_tabs.expand_on_hover=false"
        $script:box = @(40, 40, [Math]::Min(1000, $scr[0] - 80), 720)
        Launch
        Row "R21" {
            Start-Sleep (2 * $slow)
            $c = [E18Input]::Client($script:main)
            $n = @(Nodes $script:main)
            $chips = @($n | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -match '^W\d\d$' }).Count
            $p1 = NodeIn $n $plus 0x39
            $in1 = Inside $p1
            # The last chip pressed (MSAA): it becomes current and is brought into view (UpdateHighlight).
            $a = Count $active
            $pr = Press $script:main "W30" 0x2B
            $sw = (WaitLog $active ($a + 1) 10) -and @(Nth $active $a)[1] -eq "r21-30"
            Start-Sleep (2 * $slow)
            $n = @(Nodes $script:main)
            $last = NodeIn $n "W30" 0x2B; $p2 = NodeIn $n $plus 0x39
            $in2 = (Inside $last) -and (Inside $p2)
            # The wheel up over that chip: the column scrolls back, Home's chip moves down. Home's chip is the "Home"
            # push button in W30's column (a toolbar Home button is elsewhere).
            function HomeChip($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq "Home" -and $last -and [Math]::Abs($_.l - $last.l) -le 6 }) | Select-Object -First 1 }
            $home1 = HomeChip $n
            $wh = if ($last -and (Inside $last)) { [E18Input]::Wheel($script:main, $last.l + [int]($last.w / 2), $last.t + [int]($last.h / 2), @(120, 120, 120, 120, 120, 120, 120, 120, 120, 120), 60) } else { "W30 not on screen" }
            Start-Sleep (1 * $slow)
            $n = @(Nodes $script:main)
            $home2 = HomeChip $n
            $scrolled = $home1 -and $home2 -and $home2.t -gt $home1.t -and (Inside $home2)
            $pic = Snap "$ws\$Tag$suffix-r21.png"
            # Expand on hover on (what users may have): the pointer rested on the bar widens the strip; "+" stays
            # inside the window, whatever shape the bar takes. A guard, not a red: 108 may pass it too.
            $script:set = OpenSettings $prof
            $hv = if ($script:set.ready) { "$(Evaluate $script:set.page.webSocketDebuggerUrl "chrome.settingsPrivate.setPref('vertical_tabs.expand_on_hover', true, '')")" } else { $script:set.note }
            $ho = if ($home2) { [E18Input]::Hover($script:main, $home2.l + [int]($home2.w / 2), $home2.t + [int]($home2.h / 2)) } else { "Home's chip not drawn" }
            Start-Sleep (2 * $slow)
            $p4 = NodeIn (Nodes $script:main) $plus 0x39
            $inH = Inside $p4
            $pic2 = Snap "$ws\$Tag$suffix-r21-hover.png"
            $null = [E18Input]::Hover($script:main, $c[0] + [int]($c[2] * 0.7), $c[1] + [int]($c[3] / 2))
            Start-Sleep (2 * $slow)
            $n = @(Nodes $script:main)
            # Expanded again: the row, "+" inside.
            $x = @($n | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -match 'xpand' }) | Select-Object -First 1
            $xp = PressNode $script:main $x
            Start-Sleep (2 * $slow)
            $p3 = NodeIn (Nodes $script:main) $plus 0x39
            $in3 = Inside $p3
            Verdict "R21 R2-21 30 workspaces ($chips W chips drawn), collapsed, client $($c[1])..$($c[1] + $c[3]): '+' at $(Spot $p1) inside $in1; W30 pressed ($pr) shown $sw, now at $(Spot $last), '+' at $(Spot $p2): both inside $in2; the wheel up over it ($wh): Home's chip $(Spot $home1) -> $(Spot $home2), scrolled back $scrolled; $pic; expand on hover on ($hv), the pointer on the bar ($ho): '+' at $(Spot $p4) inside $inH, $pic2; expanded ($xp): '+' at $(Spot $p3) inside $in3" ($chips -ge 25 -and $in1 -and $sw -and $in2 -and $scrolled -and $inH -and $in3)
        }
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    NoPopups
    $q = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($logs -join ', ') (the quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
