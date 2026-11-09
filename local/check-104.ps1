param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "p104", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# Patch 104 (review 2's chunk 2, <local-path>\Helium-workspace\patch-review-2-findings.md R2-3 R2-4 R2-5 R2-10 R2-ID): hidden tabs
# and stale menus. check-92's shape: a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin), the
# sidebar 280 wide, ServePages' plain "E18 <name>" pages opened through DevTools (/json/new: in front, in the workspace
# on screen). Right-clicks, clicks and Shift are REAL input (SendInput, guarded); menu items are pressed through MSAA
# (msaa-press.ps1). It starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. Two launches, two logs.
#   pwsh -NoProfile -File local\check-104.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Rows A1,I1]
#   red: the build before 104 (out\Default before the build, 103 on top): ... -Tag p104-red
#   setup  the window opened on Home, Example A drawn
#   A1 R2-3   Home: a104a-c; the middle one's menu > Anchor (its list open), the TOP one closed through DevTools under
#             it, "Anchor to this page": the middle page is anchored (the old index named the bottom one)
#   S1 R2-4/5 Home: s104a-c; the middle one moved to Work (it stays between the other two in the strip); a click on the
#             top one, Shift+click on the bottom one; its menu > Snooze tab > In 2 hours: "snooze: 2 of 2" -- the range
#             left Work's tab out (R2-5; R2-4's own guard alone would say 2 of 3) -- Work's tab still open (the old: 3 of 3)
#   G1 R2-5   Home: g104a-c, the same range; the bottom one's menu > "Add tabs to new group": Work still shows its tab
#             (the old range pulled it into Home's new group)
#   R1 R2-10  Home: r104 on localhost; its menu shows "Always open localhost in the Home workspace"; under the open menu
#             the page goes to 127.0.0.1 (DevTools); pressed: "site rule: refused, the tab's site changed", no rule
#             (the old click made one for 127.0.0.1, a site the menu never named)
#   (no S2) a selection made in the classic layout does not reach vertical: the switch leaves only the tab in front
#             selected (r2c2-check-red-s2.txt, 2026-11-07, on 103): Chromium's BrowserView::OnVerticalTabStripModeChanged
#             resets it first, which rebase-overnight.ps1's step 0 checks -- so R2-4's CanSnooze guard has no path left
#             a user can take once R2-5 filters the range: it stays as the second line, ungraded.
#   I1 R2-ID  launch 2, the profile with 102 workspaces (W006..W102 after the smoke five): i104's menu > Move tab to
#             workspace > the 101st name: the tab leaves Home, no anchor line (the old id, 2101 + 100, was the anchor
#             submenu's first item: the tab was anchored instead)
#   Z         0 crash markers in the two logs (case-sensitive, DanglingPtr too)
# -Rows A1,I1: only those rows (and the setup and Z). A pass needs every verdict run ($total).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows A1,I1` passes ONE string "A1,I1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$every   = @("A1", "S1", "G1", "R1", "I1")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 2   # + the setup and Z
# The lines graded, case-sensitively.
$anchorAt = "\[workspaces\] anchor at index \d+ -> '([^']*)'"
$snoozed  = "\[workspaces\] snooze: (\d+) of (\d+) tab\(s\)"
$siteLine = "\[workspaces\] site '([^']*)' -> workspace '([^']*)'"
$refused  = "\[workspaces\] site rule: refused, the tab's site changed"
$active   = "\[workspaces\] active workspace -> '([^']*)'"

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
# The `i`-th line (from 0) matching `re`: the whole match, then its groups (empty when none).
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA and the menus, as check-92's --------------------------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $script:prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A tab drawn as `title`, or (a page not loaded yet) as its address: "E18 a104a" matches ".../a104a.html" too.
function IsTab([string]$n, [string]$title) { $n -eq $title -or $n.StartsWith("$title - ") -or ($title -like "E18 *" -and $n -like "*/$($title.Substring(4)).html*") }
function TabIn($nodes, [string]$title) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and (IsTab $_.name $title) }) | Select-Object -First 1 }
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
# The tabs of `titles` as drawn, top first (left first in the classic strip): their titles.
function Drawn([string[]]$titles) { $t = Today (Nodes $script:main); @(foreach ($n in $t) { $titles | Where-Object { IsTab $n.name $_ } | Select-Object -First 1 }) }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
function PressNode([IntPtr]$w, $n) {
    $r = Press $w $n.name $n.role
    if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
    "'$($n.name)' $r"
}
# The first node matching `re` in a menu or bubble, pressed: a shown one, or with -Any one scrolled out of a long
# menu too (MSAA's press selects the item and sends Enter, which needs no box on screen).
function OtherPress([string]$re, [switch]$Any) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Nodes $w | Where-Object { ($Any -or $_.shown) -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return $(if ($Any) { "'$($n.name)' $(Press $w $n.name $n.role)" } else { PressNode $w $n }) }
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
# Tab `title`'s menu (a guarded right-click), then its items matching each of `res` pressed in turn.
function TabMenu([string]$title, [string[]]$res) {
    NoPopups
    $r = RightClick $script:main (TabIn (Nodes $script:main) $title) "tab '$title'"
    if ($r -ne "right-clicked") { return $r }
    foreach ($re in $res) {
        $p = OtherPress $re
        $r += "; $p"
        if ($p -like "nothing matching*") { NoPopups; break }
        Start-Sleep -Milliseconds (500 * $slow)
    }
    $r
}
# A guarded real click on tab `title`, Shift held when asked.
function ClickTab([string]$title, [switch]$Shift) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no tab '$title' drawn" }
    $p = [uint32]$script:bpid
    if ($Shift) { $d = [E18Input]::KeyDown($p, 0x10); if ($d -ne "sent") { return "Shift not held: $d" } }
    try { [E18Input]::Click($script:main, $n.l + [int]($n.w * 0.4), $n.t + [int]($n.h / 2), $false) }
    finally { if ($Shift) { $null = [E18Input]::KeyUp($p, 0x10) } }
}
# The workspace shown by its chip: true once "active workspace -> <guid>" is logged (or it is already shown). The
# bottom-most push button of that name: a second "Home" (a toolbar button) gets a guarded click on the chip instead.
function Go([string]$name, [string]$guid) {
    $nodes = @(Nodes $script:main)
    if (NodeIn $nodes $name 0x14) { return $true }
    $c = Count $active
    $chips = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq $name })
    if ($chips.Count -eq 1) { $null = Press $script:main $name 0x2B } else { $n = NodeIn $nodes $name 0x2B; if ($n) { $null = [E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false) } }
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Nth $active $c)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}
# Home: pages `names` opened, then the middle one (as drawn) moved to Work by its menu, so it stays between the other
# two in the strip, hidden. Which was which, and whether Home then draws the other two only.
function HiddenBetween([string[]]$names) {
    foreach ($n in $names) { $null = NewTab $n }
    $titles = @($names | ForEach-Object { "E18 $_" })
    $d = @(Drawn $titles)
    if ($d.Count -ne 3) { return [pscustomobject]@{ ok = $false; said = "drawn [$($d -join ', ')], not three"; top = ""; mid = ""; bottom = "" } }
    $top, $mid, $bottom = $d
    $p = TabMenu $mid @('^Move tab to workspace', '^Work$')
    Start-Sleep (2 * $slow)
    $left = @(Drawn $titles)
    [pscustomobject]@{ ok = ("$left" -eq "$top $bottom"); said = "'$mid' moved to Work ($p), Home shows [$($left -join ', ')]"; top = $top; mid = $mid; bottom = $bottom }
}
# Tab `title`'s menu > "Add tabs to new group" -- or, once the window has a group, "Add tabs to group" > "New group".
function NewGroup([string]$title) {
    $r = TabMenu $title @('^Add tabs? to (new )?group$')
    if ($r -match "'Add tabs? to group' ") { $r += "; $(OtherPress '^New group$')" }
    Start-Sleep (2 * $slow)
    NoPopups   # the new group's editor bubble
    $r
}
# A click on the top tab and Shift+click on the bottom one: the range of the strip between them.
function SelectRange($h) { "click '$($h.top)' ($(ClickTab $h.top)), Shift+click '$($h.bottom)' ($(ClickTab $h.bottom -Shift))" }
function Row([string]$row, [scriptblock]$body) {
    if ($row -ne "setup" -and $want -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the pages and DevTools, as check-92's ----------------------------------------------------------------------------
function Url([string]$name, [string]$hostName = "127.0.0.1") { "http://$($hostName):$($script:srv.port)/$name.html" }
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
function NewTab([string]$name, [string]$hostName = "127.0.0.1") {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $name $hostName)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A tab brought in front (/json/activate). Only a tab of the workspace on screen: another's would switch the window.
function Show($t) { if (-not $t) { return }; try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
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
function Launch([string]$prof, [string]$log) {
    $script:prof = $prof; $script:log = $log; $script:logs += $log
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--helium-workspaces-log-addresses", "--remote-debugging-port=0",
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
    Say "browser $($script:bpid) from $exe, DevTools port $($script:port), pages on port $($script:srv.port), log $log"
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
# Which build this is, for the record only: the red run is the build without 104.
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "the tab's site changed"
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 104; rows: $($want -join ', ')"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
$prof1 = "$ws\testprofile-$Tag$suffix"
$prof2 = "$ws\testprofile-$Tag-ids$suffix"
NewProfile $prof1
if ($want -contains "I1") {
    NewProfile $prof2
    # 102 workspaces: W006..W102 after the smoke five, each named by its place in the list; the 101st is printed.
    $grow = @'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
items = d['helium']['workspaces']['list']['items']
while len(items) < 102:
    n = len(items) + 1
    items.append({'guid': 'p104w%03d' % n, 'title': 'W%03d' % n})
json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(items[100]['title'])
'@
    $nth101 = "$(& python -I -c $grow "$prof2\Default\Preferences")".Trim()
    if ($LASTEXITCODE -ne 0 -or -not $nth101) { Abort "the 102 workspaces were not seeded into $prof2" }
}
$script:srv = ServePages $pages @("a104a", "a104b", "a104c", "s104a", "s104b", "s104c", "g104a", "g104b", "g104c", "r104", "r104b",
                                  "i104")
if (-not $script:srv.ok) { Abort "the local pages were not served" }

try {
    Launch $prof1 "$ws\$Tag$suffix-run.log"
    Row "setup" {
        $h = Go "Home" "default"
        Verdict "setup: the window opened on Home ($h), Example A drawn $([bool](NodeIn (Nodes $script:main) 'Example A' 0x24))" ($h -and (NodeIn (Nodes $script:main) "Example A" 0x24))
    }
    Row "A1" {
        $h = Go "Home" "default"
        foreach ($n in @("a104a", "a104b", "a104c")) { $null = NewTab $n }
        $d = @(Drawn @("E18 a104a", "E18 a104b", "E18 a104c"))
        if ($d.Count -ne 3) { Verdict "A1 R2-3 Home $h, drawn [$($d -join ', ')], not three" $false; return }
        $top, $mid, $bottom = $d
        # The bottom one in front, so closing the top one moves no selection; the middle one's menu, its Anchor list open.
        Show (PageOf $bottom.Substring(4))
        NoPopups
        $c = Count $anchorAt
        $r = RightClick $script:main (TabIn (Nodes $script:main) $mid) "Today tab '$mid'"
        $p = if ($r -eq "right-clicked") { OtherPress '^Anchor$' } else { "not pressed" }
        $item = '^Anchor to this page(?! instead)'
        $open = MenuShows $item
        $shut = CloseTarget (PageOf $top.Substring(4))
        $gone = Gone $top.Substring(4)
        $still = MenuShows $item
        $q = if ($still) { OtherPress $item } else { "the list closed with the strip change" }
        $ok = WaitLog $anchorAt ($c + 1) 10
        $g = @(Nth $anchorAt $c)
        $page = if ($g.Count) { $g[1] } else { "" }
        Verdict "A1 R2-3 Home $h; menu of '$mid' ($r; $p), list open $open; '$top' closed ($shut) gone $gone; list still open $still; pressed ($q): anchored '$page' (want .../$($mid.Substring(4)).html, not $($bottom.Substring(4)))" (
            $h -and $open -and $gone -and $still -and $ok -and $page -like "*/$($mid.Substring(4)).html")
    }
    Row "S1" {
        $h = Go "Home" "default"
        $b = HiddenBetween @("s104a", "s104b", "s104c")
        $sel = if ($b.ok) { SelectRange $b } else { "not selected" }
        $c = Count $snoozed
        $p = if ($b.ok) { TabMenu $b.bottom @('^Snooze tab$', '^In 2 hours') } else { "not pressed" }
        $ok = WaitLog $snoozed ($c + 1) 10
        $g = @(Nth $snoozed $c)
        $hiddenOpen = $b.mid -and [bool](PageOf $b.mid.Substring(4))
        $twoGone = $b.ok -and (Gone $b.top.Substring(4)) -and (Gone $b.bottom.Substring(4))
        Verdict "S1 R2-4/5 Home $h; $($b.said); $sel; Snooze ($p): $(if ($g.Count) { "'$($g[0])'" } else { 'no snooze line' }) (want 2 of 2); Work's '$($b.mid)' still open $hiddenOpen, the two seen gone $twoGone" (
            $h -and $b.ok -and $ok -and $g[1] -eq "2" -and $g[2] -eq "2" -and $hiddenOpen -and $twoGone)
    }
    Row "G1" {
        $h = Go "Home" "default"
        $b = HiddenBetween @("g104a", "g104b", "g104c")
        $sel = if ($b.ok) { SelectRange $b } else { "not selected" }
        $p = if ($b.ok) { NewGroup $b.bottom } else { "not pressed" }
        $w = Go "Work" $work
        $inWork = @(Drawn @($b.top, $b.mid, $b.bottom))
        $back = Go "Home" "default"
        Verdict "G1 R2-5 Home $h; $($b.said); $sel; Add tabs to new group ($p); Work $w shows [$($inWork -join ', ')] (want '$($b.mid)' only: it stayed out of the group); back on Home $back" (
            $h -and $b.ok -and $w -and "$inWork" -eq $b.mid -and $back)
    }
    Row "R1" {
        $h = Go "Home" "default"
        $t = NewTab "r104" "localhost"
        $label = "Always open localhost in the Home workspace"
        $c = Count $siteLine; $x = Count $refused
        NoPopups
        $r = RightClick $script:main (TabIn (Nodes $script:main) "E18 r104") "Today tab 'E18 r104'"
        $shown = $r -eq "right-clicked" -and (MenuShows "^$([regex]::Escape($label))$")
        # Under the open menu, the page goes on to another site.
        $nav = Evaluate $t.webSocketDebuggerUrl "location.href = '$(Url 'r104b')'; 'sent'"
        $moved = [bool](WaitPage "r104b")
        $q = if ($shown) { OtherPress "^$([regex]::Escape($label))$" } else { "not pressed" }
        $no = WaitLog $refused ($x + 1) 10
        Start-Sleep (1 * $slow)
        $made = @(Lines $siteLine | Select-Object -Skip $c | ForEach-Object { "'$($_.Matches[0].Groups[1].Value)'" })
        Verdict "R1 R2-10 Home $h; r104's menu ($r) shows '$label' $shown; the page sent to 127.0.0.1 ($nav) loaded $moved; pressed ($q): refused $no, rules made [$($made -join ', ')] (want none)" (
            $h -and $shown -and $moved -and $no -and $made.Count -eq 0)
    }
    if ($want -contains "I1") {
        $q1 = Quit
        Say "launch 1: $q1"
        Launch $prof2 "$ws\$Tag-ids$suffix-run.log"
        Row "I1" {
            $h = Go "Home" "default"
            $null = NewTab "i104"
            $c = Count $anchorAt
            NoPopups
            $r = RightClick $script:main (TabIn (Nodes $script:main) "E18 i104") "Today tab 'E18 i104'"
            $p = if ($r -eq "right-clicked") { OtherPress '^Move tab to workspace' } else { "not pressed" }
            $open = MenuShows "^W00[6-9]$"
            $q = if ($open) { OtherPress "^$nth101$" -Any } else { "the list never opened" }
            Start-Sleep (3 * $slow)
            NoPopups
            $anchored = (Count $anchorAt) - $c
            $left = -not (TabIn (Nodes $script:main) "E18 i104")
            $alive = [bool](PageOf "i104")
            Verdict "I1 R2-ID 102 workspaces, Home $h; i104's menu ($r; $p), the list open $open; '$nth101' pressed ($q): anchor lines $anchored (want 0); i104 left Home $left, its page still open $alive" (
                $h -and $open -and $anchored -eq 0 -and $left -and $alive)
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
foreach ($l in $script:logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($script:logs.Count) log(s) (the quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
