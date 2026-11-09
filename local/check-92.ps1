param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c92", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# Patch 92 (92-review-fixes.patch, <local-path>\Helium-workspace\patch92-progress.md): the 2026-10-25 review's confirmed bugs.
# On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin; every workspace's pinned rows
# Example A, Smoke folder, Closed folder, Example D, none open), Sessions and the Archive emptied, the sidebar 280 wide,
# plus one pinned SPLIT row "P92 left | P92 right" at the end of Work. The pages are ServePages' plain "E18 <name>"
# pages on 127.0.0.1, opened through DevTools (/json/new: in front, in the workspace on screen). Right-clicks, clicks
# and keys are REAL input (SendInput, guarded); menu items are pressed through MSAA. It starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. One launch, one log.
#   pwsh -NoProfile -File local\check-92.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Rows M1,W1]
#   setup  the window opened, Home's pinned rows drawn
#   M1 #1  Work: m92a, m92b, m92c; the bottom one in front; the MIDDLE one's menu > Move tab to workspace (its list
#          open), then the TOP one closed through DevTools while the menu is up (the strip shifts under it), then
#          "Private" pressed: the middle tab is in Private, the bottom one still in Work (the old index named the
#          bottom one -- or, on the strip's last tab, CHECK-crashed)
#   S1 #25 Home: s92a, s92b, s92c, the same shape: the middle one's menu > Snooze tab, the top one closed, "In 2 hours"
#          pressed: "snooze: 1 of 1"; the middle page gone, the bottom page still open
#   W1 #2  Private: w92 alone in its Today (every other Today tab there closed from its menu first: the New Tab a switch
#          into an empty workspace spawns, M1's moved tab), anchored from its menu (Anchor > Anchor to this page); Ctrl+W: "close of an
#          anchored tab diverted" and the anchor put to sleep (or kept live), w92 still in the list beside the New Tab
#          the close spawned (the old compare took the New Tab for the anchor, and Chromium closed it)
#   K1 #5  Canary: k92a, k92b (anchored), k92c, and the New Tab the switch spawned; Shift+Alt+K (Clear Today):
#          every Today tab but the anchor closed, "... 1 anchored kept", k92b still open; then k92d and the chip's
#          "Close all tabs": the same, k92b still open
#   U1 #3  Home: u92a, u92b, u92c; the middle one moved to Work (it stays between the other two in the strip); a click
#          on the top one, Shift+click on the bottom one (the range holds the hidden one too); the Home chip's "Unload
#          other workspaces": no Home tab is put to sleep ("tab contents replaced ... carried workspace 'default'" x0),
#          the top page still answers DevTools (the old per-index command took the whole selection with it)
#   P1 #42 Work: the split row pressed (both pages open), its right page closed through DevTools, the window to Home;
#          a second window (Ctrl+N) to Work, the split row's menu > Unpin: both pages land in the SECOND window (the
#          owner's rule, try-92 2026-10-26) -- the left one brought from the first window, the right one opened, both
#          tagged Work; no workspace switches, the first window still on Home
#   Z      0 crash markers in the log (case-sensitive, DanglingPtr too)
# -Rows M1,W1: only those rows (and the setup and Z). A pass needs every verdict run ($total).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows M1,W1` passes ONE string "M1,W1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$dflt    = "$prof\Default"
$script:log = "$ws\$Tag$suffix-run.log"
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$private = "c9990cf0-c141-42fd-bb39-de33171ad078"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$every   = @("M1", "S1", "W1", "K1", "U1", "P1")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 2   # + the setup and Z
$splitRow = "P92 left | P92 right"
# The lines graded, case-sensitively: 92's own (workspace_service.cc CloseWorkspaceTabs) and the older ones it relies on.
$closing  = "\[workspaces\] closing (\d+) tab\(s\) of workspace '([^']*)' in this window, \d+ pinned kept(, pinned pages kept \(Clear Today\))?, (\d+) anchored kept"
$anchorAt = "\[workspaces\] anchor at index \d+ -> '"
$diverted = "\[workspaces\] close of an anchored tab diverted"
$asleep   = "\[workspaces\] (hibernated anchored tab at index|anchored tab at index \d+ (asks before leaving|could not be discarded))"
$snoozed  = "\[workspaces\] snooze: (\d+) of (\d+) tab\(s\)"
$unload   = "\[workspaces\] unload all but 'default': asking (\d+) tab\(s\)"
$homeZzz  = "\[workspaces\] tab contents replaced at index \d+ -> carried workspace 'default'"
$inserted = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"
$active   = "\[workspaces\] active workspace -> '([^']*)'"

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
# The `i`-th line (from 0) matching `re`: the whole match, then its groups (empty when none).
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA and the menus, as check-c5's -------------------------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A tab drawn as `title`, or (a page not loaded yet, or asleep) as its address: "E18 m92a" matches ".../m92a.html" too.
function IsTab([string]$n, [string]$title) { $n -eq $title -or $n.StartsWith("$title - ") -or ($title -like "E18 *" -and $n -like "*/$($title.Substring(4)).html*") }
function TabIn($nodes, [string]$title) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and (IsTab $_.name $title) }) | Select-Object -First 1 }
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
# The Today tabs of `titles` as drawn, top first: their titles.
function Drawn([string[]]$titles) { $t = Today (Nodes $script:main); @(foreach ($n in $t) { $titles | Where-Object { IsTab $n.name $_ } | Select-Object -First 1 }) }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
function PressNode([IntPtr]$w, $n) {
    $r = Press $w $n.name $n.role
    if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
    "'$($n.name)' $r"
}
# The first shown node matching `re` in a menu or bubble, pressed.
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
# True once a shown menu item matches `re` (a submenu's list is open).
function MenuShows([string]$re) {
    $t0 = Get-Date
    do { if (@(PopupNames | Where-Object { $_ -match $re }).Count) { return $true }; Start-Sleep -Milliseconds 400 } while (((Get-Date) - $t0).TotalSeconds -lt 8 * $slow)
    $false
}
function RightClick([IntPtr]$h, $n, [string]$what) {
    if (-not $n) { return "no $what drawn" }
    $r = [E18Input]::Click($h, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $r
}
# A guarded real click on Today tab `title`, Shift held when asked.
function ClickTab([string]$title, [switch]$Shift) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no Today tab '$title' drawn" }
    $p = [uint32]$script:bpid
    if ($Shift) { $d = [E18Input]::KeyDown($p, 0x10); if ($d -ne "sent") { return "Shift not held: $d" } }
    try { [E18Input]::Click($script:main, $n.l + [int]($n.w * 0.4), $n.t + [int]($n.h / 2), $false) }
    finally { if ($Shift) { $null = [E18Input]::KeyUp($p, 0x10) } }
}
# The window in front for a key: one guarded click on the page's blank bottom (Windows lets no program pull itself in
# front of the window used last).
function Front { $b = [E18Input]::Client($script:main); [E18Input]::Click($script:main, $b[0] + [int]($b[2] * 0.6), $b[1] + $b[3] - 40, $false) }
# The workspace shown by its chip: true once "active workspace -> <guid>" is logged (or it is already shown). The chip
# is the bottom-most push button of that name: MSAA presses the first in tree order, so a second "Home" (a toolbar
# button) gets a guarded click on the chip instead. In window `h` (the main one by default).
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
# Today tab `title`'s menu: Anchor > Anchor to this page; true once its "anchor at index" line is logged.
function Anchor([string]$title) {
    NoPopups
    $c = Count $anchorAt
    $r = RightClick $script:main (TabIn (Nodes $script:main) $title) "Today tab '$title'"
    $p = if ($r -eq "right-clicked") { "$(OtherPress '^Anchor$'); $(OtherPress '^Anchor to this page(?! instead)')" } else { "not pressed" }
    $ok = WaitLog $anchorAt ($c + 1) 10
    NoPopups
    [pscustomobject]@{ ok = $ok; said = "$r; $p" }
}
# The shape M1 and S1 share: the bottom tab of three in front, the middle one's menu open with submenu `parent`'s list
# showing, the top one closed through DevTools under it, then `item` pressed. What happened, and which tab was which.
function UnderOpenMenu([string[]]$three, [string]$parent, [string]$item) {
    $d = @(Drawn $three)
    if ($d.Count -ne 3) { return [pscustomobject]@{ ok = $false; said = "drawn [$($d -join ', ')], not three"; top = ""; mid = ""; bottom = "" } }
    $top, $mid, $bottom = $d
    Show (PageOf $bottom.Substring(4))
    NoPopups
    $r = RightClick $script:main (TabIn (Nodes $script:main) $mid) "Today tab '$mid'"
    $p = if ($r -eq "right-clicked") { OtherPress "^$parent" } else { "not pressed" }
    $open = MenuShows $item
    $shut = CloseTarget (PageOf $top.Substring(4))
    $gone = Gone $top.Substring(4)
    $still = MenuShows $item
    $q = if ($still) { OtherPress $item } else { "the list closed with the strip change" }
    Start-Sleep (2 * $slow)
    NoPopups
    [pscustomobject]@{ ok = ($open -and $gone -and $still); said = "menu of '$mid' ($r; $p), list open $open; '$top' closed ($shut) gone $gone; list still open $still; pressed ($q)"; top = $top; mid = $mid; bottom = $bottom }
}
function Row([string]$row, [scriptblock]$body) {
    if ($row -ne "setup" -and $want -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the pages and DevTools, as check-c5's ---------------------------------------------------------------------------
function Url([string]$name) { "http://127.0.0.1:$($script:srv.port)/$name.html" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array as ONE object (check-c35's).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_ }) } catch { @() } }
function PageOf([string]$name) { @(Targets | Where-Object { $_.type -eq "page" -and $_.url -like "*/$name.html*" }) | Select-Object -First 1 }
function CloseTarget($t) { if (-not $t) { return "no target" }; try { "$(Invoke-RestMethod -TimeoutSec 10 -Uri "$(Base)/close/$($t.id)")" } catch { "error: $_" } }
# True once page `name` is no longer open.
function Gone([string]$name) { $t0 = Get-Date; do { if (-not (PageOf $name)) { return $true }; Start-Sleep -Milliseconds 400 } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow); $false }
# Page `name` once loaded, or $null.
function WaitPage([string]$name) {
    $t0 = Get-Date
    do {
        $t = PageOf $name
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState") -eq "complete") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
# Page `name` opened in front in the workspace on screen (/json/new), once titled: its target.
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $name)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A tab brought in front (/json/activate). Only a tab of the workspace on screen: another's would switch the window.
function Show($t) { if (-not $t) { return }; try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# A workspace's saved top-level rows, as ids: the pins file is written 2.5 s after a change.
function Roots([string]$guid) {
    Start-Sleep (4 * $slow)
    try { $d = [IO.File]::ReadAllText("$dflt\Workspace Pins") | ConvertFrom-Json } catch { return "" }
    @($d.workspaces.$guid | Where-Object { $_ } | ForEach-Object { $_.id }) -join ","
}

function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--helium-workspaces-log-addresses", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
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

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" " anchored kept"
$with92 = $LASTEXITCODE -eq 0
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($with92) { 'WITH' } else { 'WITHOUT' }) patch 92; rows: $($want -join ', ')"
if (-not $with92) { Abort "this chrome.dll has no patch 92 (' anchored kept' is not in it)" }
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
Remove-Item -LiteralPath "$dflt\Workspace Archive", $script:log -EA SilentlyContinue
& python -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "helium.workspaces.enabled=true"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$script:srv = ServePages $pages @("m92a", "m92b", "m92c", "s92a", "s92b", "s92c", "w92", "k92a", "k92b", "k92c", "k92d", "u92a", "u92b", "u92c", "p92l", "p92r")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
# P1's split row, last in Work, in a version-2 pins file (E19's shape: a split of two items).
$seed = @'
import json, sys
p, left, right, work = sys.argv[1:5]
d = json.load(open(p, encoding='utf-8'))
d['version'] = 2
d['workspaces'][work].append({'type': 'split', 'id': 'p92s', 'children': [
    {'type': 'item', 'id': 'p92l', 'title': 'P92 left', 'url': left},
    {'type': 'item', 'id': 'p92r', 'title': 'P92 right', 'url': right}]})
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
'@
& python -I -c $seed "$dflt\Workspace Pins" (Url "p92l") (Url "p92r") $work
if ($LASTEXITCODE -ne 0) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue; Abort "the split row was not seeded into $prof" }

try {
    Launch
    Row "setup" {
        $h = Go "Home" "default"
        Verdict "setup: the window opened on Home ($h), Example A drawn $([bool](NodeIn (Nodes $script:main) 'Example A' 0x24))" ($h -and (NodeIn (Nodes $script:main) "Example A" 0x24))
    }
    Row "M1" {
        $w = Go "Work" $work
        foreach ($n in @("m92a", "m92b", "m92c")) { $null = NewTab $n }
        $u = UnderOpenMenu @("E18 m92a", "E18 m92b", "E18 m92c") "Move tab to workspace" '^Private$'
        $inWork = @(Drawn @($u.mid, $u.bottom))
        $pv = Go "Private" $private
        $inPrivate = @(Drawn @($u.mid, $u.bottom))
        $null = Go "Work" $work
        Verdict "M1 #1 Work $w; $($u.said); Work now [$($inWork -join ', ')] (want '$($u.bottom)' only), Private $pv [$($inPrivate -join ', ')] (want '$($u.mid)' only)" ($w -and $u.ok -and $pv -and "$inWork" -eq $u.bottom -and "$inPrivate" -eq $u.mid)
    }
    Row "S1" {
        $h = Go "Home" "default"
        foreach ($n in @("s92a", "s92b", "s92c")) { $null = NewTab $n }
        $c = Count $snoozed
        $u = UnderOpenMenu @("E18 s92a", "E18 s92b", "E18 s92c") "Snooze tab" '^In 2 hours'
        $ok = WaitLog $snoozed ($c + 1) 10
        $g = @(Nth $snoozed $c)
        $midGone = $u.mid -and (Gone ($u.mid.Substring(4)))
        $bottomOpen = $u.bottom -and [bool](PageOf ($u.bottom.Substring(4)))
        Verdict "S1 #25 Home $h; $($u.said); $(if ($g.Count) { "'$($g[0])'" } else { 'no snooze line' }) (want 1 of 1); '$($u.mid)' gone $midGone, '$($u.bottom)' still open $bottomOpen" ($h -and $u.ok -and $ok -and $g[1] -eq "1" -and $g[2] -eq "1" -and $midGone -and $bottomOpen)
    }
    Row "W1" {
        $pv = Go "Private" $private
        $null = NewTab "w92"
        # Alone: every other Today tab here closed (a click on it, then Ctrl+W) -- the New Tab a switch into an empty
        # workspace spawns, and M1's moved tab. Otherwise Ctrl+W lands on one of them and never spawns (the path #2
        # is about).
        $closed = @()
        foreach ($i in 1..4) {
            $other = @(Today (Nodes $script:main) | Where-Object { -not (IsTab $_.name "E18 w92") }) | Select-Object -First 1
            if (-not $other) { break }
            $ck = [E18Input]::Click($script:main, $other.l + [int]($other.w * 0.4), $other.t + [int]($other.h / 2), $false)
            $closed += "'$($other.name)' ($ck; Ctrl+W $([E18Input]::Keys([uint32]$script:bpid, $false, 0x57)))"
            Start-Sleep (1 * $slow)
        }
        $before = @(Today (Nodes $script:main))
        $alone = "$(Names $before)$(if ($closed.Count) { "; closed first: $($closed -join ', ')" })"
        $a = Anchor "E18 w92"
        $c = Count $diverted; $s = Count $asleep
        $f = Front
        $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x57)
        $dv = WaitLog $diverted ($c + 1) 10
        $zz = WaitLog $asleep ($s + 1) 10
        Start-Sleep (2 * $slow)
        $after = @(Today (Nodes $script:main))
        $kept = [bool](TabIn $after "E18 w92")
        $spawned = @($after | Where-Object { -not (IsTab $_.name "E18 w92") }).Count
        Verdict "W1 #2 Private $pv, its Today [$alone] (want E18 w92 alone); anchored $($a.ok) ($($a.said)); Ctrl+W ($f; $k): diverted $dv, put to sleep or kept live $zz; Today now [$(Names $after)]: w92 kept $kept, spawned $spawned (want w92 and 1 spawned New Tab)" ($pv -and $before.Count -eq 1 -and $a.ok -and $dv -and $zz -and $kept -and $after.Count -eq 2 -and $spawned -eq 1)
    }
    Row "K1" {
        $cn = Go "Canary" $canary
        foreach ($n in @("k92a", "k92b", "k92c")) { $null = NewTab $n }
        $a = Anchor "E18 k92b"
        # Every Today tab here but the anchor closes -- the three pages and the New Tab the switch into an empty
        # workspace spawned.
        $n1 = @(Today (Nodes $script:main)).Count
        $c = Count $closing
        $f = Front
        $p = [uint32]$script:bpid
        $k = "$([E18Input]::KeyDown($p, 0x10)) $([E18Input]::KeyDown($p, 0x12)) $([E18Input]::Tap($p, 0x4B)) $([E18Input]::KeyUp($p, 0x12)) $([E18Input]::KeyUp($p, 0x10))"
        $ok1 = WaitLog $closing ($c + 1) 10
        $g1 = @(Nth $closing $c)
        $shut1 = (Gone "k92a") -and (Gone "k92c"); $kept1 = [bool](PageOf "k92b")
        $null = NewTab "k92d"
        $n2 = @(Today (Nodes $script:main)).Count
        $c2 = Count $closing
        $r = RightClick $script:main (NodeIn (Nodes $script:main) "Canary" 0x2B) "Canary chip"
        $q = if ($r -eq "right-clicked") { OtherPress '^Close all tabs$' } else { "not pressed" }
        $ok2 = WaitLog $closing ($c2 + 1) 10
        $g2 = @(Nth $closing $c2)
        $shut2 = Gone "k92d"; $kept2 = [bool](PageOf "k92b")
        Verdict "K1 #5 Canary $cn; k92b anchored $($a.ok); Shift+Alt+K ($f; $k): $(if ($g1.Count) { "'$($g1[0])'" } else { 'no closing line' }) (want $($n1 - 1) closed = $n1 Today tabs less the anchor, Clear Today, 1 anchored kept); k92b open $kept1, k92a + k92c gone $shut1; Close all tabs ($r; $q): $(if ($g2.Count) { "'$($g2[0])'" } else { 'no closing line' }) (want $($n2 - 1) closed, 1 anchored kept); k92b open $kept2, k92d gone $shut2" ($cn -and $a.ok -and $n1 -ge 4 -and $ok1 -and [int]$g1[1] -eq $n1 - 1 -and $g1[2] -eq $canary -and $g1[3] -and $g1[4] -eq "1" -and $kept1 -and $shut1 -and $ok2 -and [int]$g2[1] -eq $n2 - 1 -and -not $g2[3] -and $g2[4] -eq "1" -and $kept2 -and $shut2)
    }
    Row "U1" {
        $h = Go "Home" "default"
        foreach ($n in @("u92a", "u92b", "u92c")) { $null = NewTab $n }
        $d = @(Drawn @("E18 u92a", "E18 u92b", "E18 u92c"))
        if ($d.Count -ne 3) { Verdict "U1 #3 Home $($h), drawn [$($d -join ', ')], not three" $false; return }
        $top, $mid, $bottom = $d
        $r = RightClick $script:main (TabIn (Nodes $script:main) $mid) "Today tab '$mid'"
        $p = if ($r -eq "right-clicked") { "$(OtherPress '^Move tab to workspace'); $(OtherPress '^Work$')" } else { "not pressed" }
        Start-Sleep (2 * $slow)
        $left = @(Drawn $d)
        $c1 = ClickTab $top
        $c2 = ClickTab $bottom -Shift
        $topPage = PageOf $top.Substring(4)
        $z = Count $homeZzz; $c = Count $unload
        $rc = RightClick $script:main (NodeIn (Nodes $script:main) "Home" 0x2B) "Home chip"
        $q = if ($rc -eq "right-clicked") { OtherPress '^Hibernate other workspaces$' } else { "not pressed" }
        $ok = WaitLog $unload ($c + 1) 10
        $g = @(Nth $unload $c)
        Start-Sleep (3 * $slow)
        $homeSlept = (Count $homeZzz) - $z
        $live = if ($topPage) { Evaluate $topPage.webSocketDebuggerUrl "1 + 1" } else { "no page" }
        Verdict "U1 #3 Home $h; '$mid' moved to Work ($r; $p), Home shows [$($left -join ', ')] (want '$top', '$bottom'); click '$top' ($c1), Shift+click '$bottom' ($c2); Hibernate other workspaces ($rc; $q): $(if ($g.Count) { "'$($g[0])'" } else { 'no unload line' }); Home tabs put to sleep $homeSlept (want 0); '$top' answers 1 + 1 = $live (want 2)" ($h -and "$left" -eq "$top $bottom" -and $ok -and [int]$g[1] -ge 1 -and $homeSlept -eq 0 -and $live -eq 2)
    }
    Row "P1" {
        $w = Go "Work" $work
        $o = Count "pins: opened item '"
        $row = NodeIn (Nodes $script:main) $splitRow 0x24
        $r = if ($row) { PressNode $script:main $row } else { "no row '$splitRow' drawn" }
        $both = (WaitLog "pins: opened item '" ($o + 2) 10) -and [bool](WaitPage "p92l") -and [bool](WaitPage "p92r")
        $shut = CloseTarget (PageOf "p92r")
        $gone = Gone "p92r"
        $h = Go "Home" "default"
        # The second window: Ctrl+N with the first in front; it opens on Home, the workspace of the window used last.
        $f = Front
        $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x4E)
        $b = [IntPtr]::Zero; $t0 = Get-Date
        while ($b -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow) { Start-Sleep 1; $b = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main }) | Select-Object -First 1; if (-not $b) { $b = [IntPtr]::Zero } }
        $bw = $false; $rc = "no second window"; $q = "not pressed"; $ok = $false; $g = @(); $switched = -1; $stillHome = $false
        $brought = $false; $ins = @(); $allWork = $false; $inB = "not looked"
        if ($b -ne [IntPtr]::Zero) {
            [E18Input]::Place($b, $script:box[0] + 60, $script:box[1] + 60, $script:box[2] - 60, $script:box[3] - 60)
            Start-Sleep (3 * $slow)
            $bw = Go "Work" $work $b
            $i = Count $inserted
            $rc = RightClick $b (NodeIn (Nodes $b) $splitRow 0x24) "split row in the second window"
            $s0 = Count $active
            $q = if ($rc -eq "right-clicked") { OtherPress '^Unpin$' } else { "not pressed" }
            # The owner's rule (try-92, 2026-10-26): the pages land in THIS window -- the left one brought from the
            # first, the right one opened here -- both tagged Work in a window on Work; no window switches (a
            # switch is what once brought the first window in front, and the owner closed the wrong one).
            $brought = WaitLog "pins: brought the page of 'p92l' from another window" 1 10
            $ok = WaitLog $inserted ($i + 2) 10
            Start-Sleep (2 * $slow)
            $ins = @(Lines $inserted | Select-Object -Skip $i)
            $g = if ($ins.Count) { @($ins[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() }
            $allWork = $ins.Count -ge 2 -and -not @($ins | Where-Object { $_.Matches[0].Groups[2].Value -ne $work -or $_.Matches[0].Groups[3].Value -ne $work }).Count
            $switched = (Count $active) - $s0
            $nb = @(Nodes $b)
            $inB = "left $([bool](TabIn $nb 'E18 p92l')), right $([bool](TabIn $nb 'E18 p92r'))"
            $stillHome = [bool](NodeIn (Nodes $script:main) "Home" 0x14)
            NoPopups
        }
        $roots = Roots $work
        Verdict "P1 #42 Work $w; the split row pressed ($r): both pages open $both; the right page closed ($shut) gone $gone; the window to Home $h; Ctrl+N ($f; $k), the second window to Work $bw; its split row's menu ($rc) > Unpin ($q): $(if ($g.Count) { "'$($g[0])'" } else { 'no insert line' }) (the last insert); the left page brought from the first window $brought; $($ins.Count) insert(s) after it, all tagged Work in a window on Work $allWork (want 2+, True); drawn in the second window: $inB (want True, True); workspace switches $switched (want 0), the first window still on Home $stillHome; Work's saved rows [$roots] (want no p92s)" ($w -and $both -and $gone -and $h -and $bw -and $brought -and $ok -and $allWork -and $inB -eq "left True, right True" -and $switched -eq 0 -and $stillHome -and $roots -and $roots -notmatch '\bp92s\b')
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    NoPopups
    $q = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = 0
if (Test-Path -LiteralPath $script:log) { $markers = @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count }
Verdict "Z crash markers in $($script:log) (the quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
