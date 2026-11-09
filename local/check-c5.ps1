param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c5", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# C5 "links by rule" + the C29 screen-reader fix (patch 91 91-site-rules.patch, <local-path>\Helium-workspace\c5-progress.md):
# a site (a host) given to a workspace by the tab menu's "Always open <site> in the <workspace> workspace"; a NEW tab opened with an
# address of that site or a subdomain (a link in a new tab, Ctrl/middle-click, a bookmark, a link from another app)
# joins that workspace at the top of its Today; never a navigation inside a tab (D3), a typed address (D4), or anything
# with Workspaces off (D5); a ruled outside link skips C6's little window (D7). C29: the pinned rows' list is a tree
# named "Pinned pages" that says several rows can be selected.
# On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin; every workspace's pinned rows
# Example A, Smoke folder, Closed folder, Example D), Sessions emptied, the sidebar 280 wide (the five chips and the
# "+"), one bookmark "C5 bookmark" (sub.localhost; Helium draws no bookmarks bar), the little window ON. The pages are
# ServePages' plain "E18 <name>" pages + c5home (four links to sub.localhost), python on 127.0.0.1:<port>; the browser
# reaches the same server as localhost and sub.localhost (Chromium resolves *.localhost to loopback). The rule is for
# "localhost", so sub.localhost is its subdomain (HostMatchesSite) and 127.0.0.1 is no part of it.
# Right-clicks, clicks and keys are REAL input (SendInput, guarded: the user's desktop, the fork's window under the
# point or in front): it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. Menu items and buttons are
# pressed through MSAA. One launch, one log.
#   pwsh -NoProfile -File local\check-c5.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Rows M1,R1]
#   setup  Private: c5p (localhost) opened; Work: c5a (localhost); Home: c5home (127.0.0.1) -- all through DevTools,
#          before any rule exists (DevTools' /json/new may open as AUTO_TOPLEVEL, which a rule would route)
#   A1     (C29) MSAA: the node "Pinned pages" is role 0x23 (outline) with STATE_SYSTEM_MULTISELECTABLE (0x1000000);
#          Home's pinned row "Example A" is still found as 0x24 + its name
#   M1     Work: a guarded REAL right-click on Today tab c5a; the menu lists "Always open localhost in the Work workspace" (exact);
#          pressed (MSAA): "site 'localhost' -> workspace '<Work>'"; a second right-click lists "Stop always opening
#          localhost in Work"
#   M2     Private: c5p's menu "Always open localhost in the Private workspace" pressed: "site 'localhost' -> workspace '<Private>'";
#          c5p's menu now "Stop always opening localhost in the Private workspace"; chrome://prefs-internals (the live pref): Private's
#          sites hold localhost, Work's do not; then Work: c5a's menu reads "Always open localhost in the Work workspace" again, pressed
#          (the rule back in Work for the rows after): "site 'localhost' -> workspace '<Work>'"
#   R1     Home: Ctrl+click "C5 ruled link" (sub.localhost/c5r): "site rule: 'sub.localhost' -> workspace '<Work>'
#          (active 'default')" once, "site rule: to the top of '<Work>'" (placed); no switch line; Home still on screen;
#          then Work: its first Today tab is E18 c5r
#   R2     Home: Ctrl+Shift+click "C5 front link" (c5f): the same stamp and top lines, a switch to Work AFTER the stamp,
#          Work on screen, its first Today tab E18 c5f
#   R3     Home: "C5 bookmark" (c5k) opened by the bookmark manager's Open in new tab: the same stamp and top lines
#   N1     Home: a plain click on "C5 same link" (c5s): c5home's own tab goes there; no "site rule: " line, no switch,
#          the tab still in Home's Today; then history.back()
#   N2     Home: Ctrl+T, sub.localhost/c5t typed + Enter: no "site rule: " line, no switch, E18 c5t in Home's Today
#   L1     Home: an outside link (chrome.exe --single-argument, as check-c6) to sub.localhost/c5b: "little window:
#          skipped, site rule for 'sub.localhost'", the stamp + top lines, "tab inserted ... -> workspace '<Work>'", no
#          opened line, 1 window; then the guard: an outside link to 127.0.0.1/c5u still opens a little window (opened
#          line, 2 windows), closed after
#   X1     the "+" menu's "Export workspaces" (--helium-workspaces-transfer-auto=<file>: no dialog, check-c191's way):
#          "export: wrote"; the file's prefs.json content has "sites" and Work's entry lists localhost
#   N3     Workspaces OFF (settingsPrivate, as check-c6 O1 turns its setting): Ctrl+click "C5 off link" (c5o): no "site
#          rule: " line; then back ON (setPref true, getPref true)
#   E1     the Work chip's menu > "Edit workspace...": the bubble shows "localhost" and "Remove localhost"; pressed:
#          "site 'localhost' removed"; the line "None yet. ..." shown and the button gone
#   Z      0 crash markers in the log (case-sensitive, DanglingPtr too)
# -Rows M1,R1: only those rows (and the setup and Z); every row but A1 needs the rule, so M1 joins them. A pass needs
# every verdict run ($total).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows M1,R1` passes ONE string "M1,R1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
if (@($Rows | Where-Object { $_ -ne "A1" }).Count -and $Rows -notcontains "M1") { $Rows += "M1" }
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$dflt    = "$prof\Default"
$script:log = "$ws\$Tag$suffix-run.log"
$export  = "$ws\$Tag$suffix-export.json"
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$private = "c9990cf0-c141-42fd-bb39-de33171ad078"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$every   = @("A1", "M1", "M2", "R1", "R2", "R3", "N1", "N2", "L1", "X1", "N3", "E1")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 2   # + the setup and Z
$enabled = "helium.workspaces.enabled"
# Patch 91's lines (workspace_service.cc SetSiteWorkspace / RemoveSite / SiteRuleGuidFor / MoveRuledTab,
# workspace_little_window.cc), graded case-sensitively; "site rule: " also matches the split view's "undone" line.
$siteSet  = "\[workspaces\] site '([^']*)' -> workspace '([^']*)'"
$removed  = "\[workspaces\] site '([^']*)' removed"
$stamp    = "\[workspaces\] site rule: '([^']*)' -> workspace '([^']*)' \(active '([^']*)'\)"
$top      = "\[workspaces\] site rule: to the top of '([^']*)'(.*)"
$anyRule  = "\[workspaces\] site rule: "
$skipped  = "\[workspaces\] little window: skipped, site rule for '([^']*)'"
# Older patches': 90 (little window), 36 (StampInsertedTab), 03 (the switch), 85 (export).
$opened   = "\[workspaces\] little window: opened window (\d+) at (-?\d+),(-?\d+) (\d+)x(\d+)"
$inserted = "\[workspaces\] tab inserted at index (\d+) -> workspace '([^']*)' \(active '([^']*)'\)"
$active   = "\[workspaces\] active workspace -> '([^']*)'"
$wrote    = "\[workspaces\] export: wrote (.+)"

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
# `get` polled until its value matches `re`: the last value. (Its own names are odd: `get` sees the caller's.)
function Until([scriptblock]$get, [string]$re) {
    $untilT0 = Get-Date
    do { $untilV = "$(& $get)"; if ($untilV -match $re) { break }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $untilT0).TotalSeconds -lt 10 * $slow)
    $untilV
}

# ---- MSAA (msaa-press.ps1, e14d3-web.ps1) and the menus, as check-c16's ---------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A tab drawn as `title`, or (a page not loaded yet) as its address: "E18 c5r" matches ".../c5r.html" too.
function IsTab([string]$n, [string]$title) { $n -eq $title -or $n.StartsWith("$title - ") -or ($title -like "E18 *" -and $n -like "*/$($title.Substring(4)).html*") }
function TabIn($nodes, [string]$title) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and (IsTab $_.name $title) }) | Select-Object -First 1 }
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
function FirstToday { $t = @(Today (Nodes $script:main)); if ($t.Count) { $t[0].name } else { "(none)" } }
function OnScreen([string]$name) { [bool](NodeIn (Nodes $script:main) $name 0x14) }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
# Node `n` of window `w` pressed through MSAA -- or clicked at its middle when its name did not survive MSAA's text
# round trip (an ellipsis: "Edit workspace..." ends in U+2026).
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
function RightClick([IntPtr]$h, $n, [string]$what) {
    if (-not $n) { return "no $what drawn" }
    $r = [E18Input]::Click($h, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $r
}
function ClickNode($n) { if (-not $n) { return "nothing to click" }; [E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false) }
# Today tab `title`'s menu (a guarded real right-click): what was said and the menu's items, the menu left open.
function TabMenuItems([string]$title) {
    NoPopups
    $r = RightClick $script:main (TabIn (Nodes $script:main) $title) "Today tab '$title'"
    $items = @(); $t0 = Get-Date
    if ($r -eq "right-clicked") { do { Start-Sleep -Milliseconds 500; $items = @(PopupNames) } while (-not $items.Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) }
    [pscustomobject]@{ said = $r; items = $items; rule = (@($items | Where-Object { $_ -match 'always open' }) -join ' | ') }
}
# The workspace shown by its chip: true once its header (a heading of its name) is drawn. The chip is the bottom-most
# shown push button of that name -- MSAA presses the first in tree order, so a second "Home" (a toolbar button) gets
# a guarded click on the chip instead.
function Go([string]$name, [string]$guid) {
    $nodes = @(Nodes $script:main)
    if (NodeIn $nodes $name 0x14) { return $true }
    $c = Count $active
    $chips = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq $name })
    if ($chips.Count -eq 1) { $null = Press $script:main $name 0x2B } else { $null = ClickNode (NodeIn $nodes $name 0x2B) }
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Nth $active $c)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}
# Link `name` of the page in front, through e14d3-web.ps1 (msaa-press's walk INTO pages): its box, polled (the first
# walk turns the page's accessibility on); $null when none is shown. check-c20's.
function Link([string]$name) {
    $t0 = Get-Date
    do {
        foreach ($line in @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\e14d3-web.ps1" -Profile $prof -Window ([long]$script:main) -Name $name -Role 0x1E)) {
            if ("$line" -match '\|0x([0-9A-F]+)\|@(-?\d+),(-?\d+),(\d+),(\d+)\|' -and -not ([Convert]::ToInt32($Matches[1], 16) -band 0x18000) -and [int]$Matches[4] -gt 0 -and [int]$Matches[5] -gt 0) {
                return [pscustomobject]@{ l = [int]$Matches[2]; t = [int]$Matches[3]; w = [int]$Matches[4]; h = [int]$Matches[5] }
            }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
# The main window in front: Windows lets no program pull itself in front of the window used last (the Claude window),
# and a held key is refused unless the browser is in front -- so one guarded click on the page's blank bottom.
function Front {
    if ([C5Input]::Front() -eq $script:main) { return "in front" }
    $b = [E18Input]::Client($script:main)
    $c = [E18Input]::Click($script:main, $b[0] + [int]($b[2] * 0.6), $b[1] + $b[3] - 40, $false)
    Start-Sleep -Milliseconds (300 * $slow)
    "a click on the page ($c): in front $([C5Input]::Front() -eq $script:main)"
}
# A guarded real click on link `name` of the page in front with the keys `hold` held (0x11 Ctrl, 0x10 Shift), let go
# in reverse whatever happens. What happened.
function ClickLink([string]$name, [int[]]$hold = @()) {
    $n = Link $name
    if (-not $n) { return "no link '$name' drawn" }
    $f = Front
    $p = [uint32]$script:bpid; $held = [System.Collections.Generic.List[int]]::new()
    try {
        foreach ($vk in $hold) {
            $d = [E18Input]::KeyDown($p, [uint16]$vk)
            if ($d -ne "sent") { return "$f; key 0x$('{0:X}' -f $vk) not held: $d" }
            $held.Insert(0, $vk)
        }
        "$f; $([E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))"
    } finally { foreach ($vk in $held) { $null = [E18Input]::KeyUp($p, [uint16]$vk) } }
}
function Row([string]$row, [scriptblock]$body) {
    if ($row -ne "setup" -and $want -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the site-rule lines ---------------------------------------------------------------------------------------------
function Marks { [pscustomobject]@{ stamp = (Count $stamp); top = (Count $top); active = (Count $active); rule = (Count $anyRule) } }
# What a routed open wrote after the marks `m`: its stamp ('sub.localhost' -> Work from Home, once), its move to the
# top of Work's Today (placed, not out of a group), and the switches to Work after the stamp.
function Route($m) {
    $null = WaitLog $stamp ($m.stamp + 1) 10
    $null = WaitLog $top ($m.top + 1) 10
    Start-Sleep (1 * $slow)
    $s = @(Lines $stamp | Select-Object -Skip $m.stamp)
    $t = @(Lines $top | Select-Object -Skip $m.top)
    $sg = if ($s.Count) { @($s[0].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() }
    $tg = if ($t.Count) { @($t[0].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() }
    $at = if ($s.Count) { $s[0].LineNumber } else { [int]::MaxValue }
    $sw = @(Lines $active | Select-Object -Skip $m.active | Where-Object { $_.LineNumber -gt $at -and $_.Matches[0].Groups[1].Value -eq $work })
    [pscustomobject]@{
        ok     = [bool]($s.Count -eq 1 -and $sg[1] -eq "sub.localhost" -and $sg[2] -eq $work -and $sg[3] -eq "default" -and $t.Count -eq 1 -and $tg[1] -eq $work -and $tg[2] -eq "")
        follow = $sw.Count
        said   = "$(if ($s.Count) { "'$($sg[0])'" } else { 'no site rule stamp' }) x$($s.Count) (want sub.localhost -> Work, active default, once); $(if ($t.Count) { "'$($tg[0])'" } else { 'no to-the-top line' }) x$($t.Count) (want Work, nothing after it); switches to Work after the stamp $($sw.Count)"
    }
}

# ---- the pages, DevTools, the prefs ------------------------------------------------------------------------------------
function Url([string]$name, [string]$on = "127.0.0.1") { "http://$($on):$($script:srv.port)/$name.html" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array as ONE object (check-c35's).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_ }) } catch { @() } }
function Pages { @(Targets | Where-Object { $_.type -eq "page" }) }
function PageOf([string]$name) { @(Pages | Where-Object { $_.url -like "*/$name.html*" }) | Select-Object -First 1 }
function UrlOf([string]$id) { "$(@(Targets | Where-Object { $_.id -eq $id }) | Select-Object -First 1 | ForEach-Object { $_.url })" }
function CloseTarget($t) { if (-not $t) { return "no target" }; try { "$(Invoke-RestMethod -TimeoutSec 10 -Uri "$(Base)/close/$($t.id)")" } catch { "error: $_" } }
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
# Page `name` on host `on` opened in front in the workspace on screen (/json/new), once titled: its target.
function NewTab([string]$name, [string]$on = "127.0.0.1") {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $name $on)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A tab brought in front (/json/activate). Only a tab of the workspace on screen: another's would switch the window.
function Show($t) { if (-not $t) { return }; try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# Every workspace's sites as the LIVE pref holds them: chrome://prefs-internals (the profile's prefs as JSON text)
# opened as a tab through DevTools, read, closed. ok, of (guid -> sites), said.
function Sites {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?chrome://prefs-internals" } catch { $null }
    if (-not $t) { return [pscustomobject]@{ ok = $false; of = @{}; said = "DevTools opened no prefs-internals tab" } }
    # Found by its shape, not by a path: the first run read helium.workspaces.list.items and got undefined, though the
    # export file holds exactly that shape -- prefs-internals' nesting is not the Preferences file's. On a miss it says
    # which top-level keys the page did have.
    $js = "(() => { const p = JSON.parse(document.body.innerText); const find = o => { if (!o || typeof o !== 'object') return null; if (Array.isArray(o.items) && o.items.length && o.items[0] && typeof o.items[0].guid === 'string') return o; for (const k of Object.keys(o)) { const r = find(o[k]); if (r) return r; } return null; }; const l = find(p); return l ? JSON.stringify(Object.fromEntries(l.items.map(e => [e.guid, e.sites || []]))) : 'no workspace list; top keys: ' + Object.keys(p).slice(0, 12).join(','); })()"
    $v = Until { Evaluate $t.webSocketDebuggerUrl $js } '^\{'
    $null = CloseTarget $t
    $of = @{}
    if ($v -match '^\{') { ($v | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $of[$_.Name] = @($_.Value) } }
    [pscustomobject]@{ ok = [bool]($v -match '^\{'); of = $of; said = $(if ($v -match '^\{') { "Private [$($of[$private] -join ',')], Work [$($of[$work] -join ',')]" } else { "prefs-internals unreadable: $("$v".Substring(0, [Math]::Min(120, "$v".Length)))" }) }
}
# A second chrome.exe on the test profile, as Windows hands over a link from another app (--single-argument LAST): it
# forwards its line to the running browser and exits (check-c6's Outside).
function Outside([string]$url) {
    $p = Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--single-argument", $url)
    "launcher $($p.Id) $(if ($p.WaitForExit(15000 * $slow)) { 'exited' } else { 'STILL RUNNING' })"
}
function Littles { @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main }) }
function WindowCount { @([E18Input]::Windows([uint32]$script:bpid)).Count }

function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--helium-workspaces-log-addresses", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check", "--restore-last-session",
           "--helium-workspaces-transfer-auto=`"$export`"")
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
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "site rule: to the top of '"
$with91 = $LASTEXITCODE -eq 0
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($with91) { 'WITH' } else { 'WITHOUT' }) patch 91; rows: $($want -join ', ')"
if (-not $with91) { Abort "this chrome.dll has no patch 91 ('site rule: to the top of' is not in it)" }
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
# What E18Input has not: the window in front, and characters typed as characters (check-c16's C16Input.Type), only
# to the browser's window in front, on the user's desktop.
if (-not ("C5Input" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class C5Input {
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  public static IntPtr Front() { return GetForegroundWindow(); }
  // Null when the input desktop is the user's (not the lock screen) and the window in front is `pid`'s; else why not.
  static string Guard(uint pid) {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);  // UOI_NAME
    CloseDesktop(d);
    if (name.ToString() != "Default") return "the input desktop is '" + name + "' (the screen is locked?)";
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    return p == pid ? null : "not sent: the window in front is not the browser's";
  }
  static INPUT Key(ushort vk, ushort scan, uint flags) { INPUT i = new INPUT(); i.type = 1; i.u.ki.vk = vk; i.u.ki.scan = scan; i.u.ki.flags = flags; return i; }
  // KEYEVENTF_UNICODE (4), each UTF-16 unit down then up (KEYUP 2), all in one SendInput.
  public static string Type(uint pid, string text) {
    string e = Guard(pid); if (e != null) return e;
    List<INPUT> all = new List<INPUT>();
    foreach (char c in text) { all.Add(Key(0, c, 4)); all.Add(Key(0, c, 4 | 2)); }
    SendInput((uint)all.Count, all.ToArray(), Marshal.SizeOf(typeof(INPUT)));
    Thread.Sleep(500);
    return "typed";
  }
}
"@
}
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$dflt\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath "$dflt\Workspace Archive", $script:log, $export -EA SilentlyContinue
# The smoke profile is already vertical with Workspaces on; written again so a stale copy cannot start otherwise.
& python -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "helium.browser.layout=2" "$enabled=true" "helium.workspaces.little_window=true"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$script:srv = ServePages $pages @("c5r", "c5a", "c5p", "c5f", "c5s", "c5t", "c5k", "c5o", "c5b", "c5u")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
# c5home: four links to sub.localhost on the server's own port, filled in by the page (the port is Windows' pick).
Set-Content -Encoding UTF8 -LiteralPath "$pages\c5home.html" -Value @'
<!doctype html>
<title>E18 c5home</title>
<body style="margin:0;background:#fff;font:24px sans-serif">
<p style="margin:24px"><a id="r" href="#">C5 ruled link</a></p>
<p style="margin:24px"><a id="f" href="#">C5 front link</a></p>
<p style="margin:24px"><a id="s" href="#">C5 same link</a></p>
<p style="margin:24px"><a id="o" href="#">C5 off link</a></p>
<script>
  for (const [id, page] of [["r", "c5r"], ["f", "c5f"], ["s", "c5s"], ["o", "c5o"]])
    document.getElementById(id).href = "http://sub.localhost:" + location.port + "/" + page + ".html";
</script>
</body>
'@
$other = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 "http://localhost:$($script:srv.port)/c5a.html").Content -match "E18 c5a" } catch { $false }
if (-not $other) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue; Abort "c5a.html is not served on localhost:$($script:srv.port)" }
# R3's bookmark on the bookmarks bar: "C5 bookmark" -> sub.localhost/c5k, the next free id; the checksum dropped.
$bm = @'
import json, sys, uuid
p, url = sys.argv[1], sys.argv[2]
d = json.load(open(p, encoding='utf-8'))
d.pop('checksum', None)
def ids(n):
    yield int(n.get('id', 0))
    for c in n.get('children', []):
        yield from ids(c)
top = max(max(ids(r)) for r in d['roots'].values() if isinstance(r, dict))
d['roots']['bookmark_bar']['children'].append({'date_added': '13434309301290036', 'date_last_used': '0', 'guid': str(uuid.uuid4()), 'id': str(top + 1), 'name': 'C5 bookmark', 'type': 'url', 'url': url})
open(p, 'w', encoding='utf-8').write(json.dumps(d, ensure_ascii=False))
'@
& python -I -c $bm "$dflt\Bookmarks" (Url "c5k" "sub.localhost")
if ($LASTEXITCODE -ne 0) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue; Abort "the bookmark was not seeded into $prof" }

try {
    Launch
    Row "setup" {
        $p = Go "Private" $private; $null = NewTab "c5p" "localhost"; $pt = [bool](TabIn (Today (Nodes $script:main)) "E18 c5p")
        $w = Go "Work" $work; $null = NewTab "c5a" "localhost"; $wt = [bool](TabIn (Today (Nodes $script:main)) "E18 c5a")
        $h = Go "Home" "default"; $null = NewTab "c5home"
        $n = @(Nodes $script:main)
        $ht = [bool](TabIn (Today $n) "E18 c5home")
        Verdict "setup: Private $p, c5p in its Today $pt; Work $w, c5a in its Today $wt; Home $h, c5home in its Today $ht" ($p -and $pt -and $w -and $wt -and $h -and $ht)
    }
    Row "A1" {
        $h = Go "Home" "default"
        $found = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\e14d3-web.ps1" -Profile $prof -Window ([long]$script:main) -Name "Pinned pages" -Role 0x23)
        # name|0x23|0xSTATE|@l,t,w,h|value, not INVISIBLE (0x8000), a box with a size.
        $state = @($found | ForEach-Object { if ("$_" -match '\|0x23\|0x([0-9A-F]+)\|@(-?\d+),(-?\d+),(\d+),(\d+)\|' -and -not ([Convert]::ToInt64($Matches[1], 16) -band 0x8000) -and [int]$Matches[4] -gt 0) { [Convert]::ToInt64($Matches[1], 16) } }) | Select-Object -First 1
        $multi = $null -ne $state -and ($state -band 0x1000000) -ne 0
        $pinRow = [bool](NodeIn (Nodes $script:main) "Example A" 0x24)
        Verdict "A1 (C29) Home $($h): 'Pinned pages' as role 0x23 $(if ($null -ne $state) { "state 0x$('{0:X}' -f $state), MULTISELECTABLE (0x1000000) $multi" } else { "NOT found shown (e14d3-web: $((@($found) | Select-Object -First 3) -join ' | '))" }); the pinned row 'Example A' found as 0x24 $pinRow" ($h -and $multi -and $pinRow)
    }
    Row "M1" {
        $w = Go "Work" $work
        $c = Count $siteSet
        $m = TabMenuItems "E18 c5a"
        $has = $m.items -ccontains "Always open localhost in the Work workspace"
        $p = if ($has) { OtherPress '^Always open localhost in the Work workspace$' } else { NoPopups; "not pressed" }
        $ok = WaitLog $siteSet ($c + 1) 10
        $g = @(Nth $siteSet $c)
        $m2 = TabMenuItems "E18 c5a"
        $stop = $m2.items -ccontains "Stop always opening localhost in the Work workspace"
        NoPopups
        Verdict "M1 Work $w; c5a's menu ($($m.said)): [$($m.rule)] (want exactly 'Always open localhost in the Work workspace'); pressed ($p): $(if ($g.Count) { "'$($g[0])'" } else { 'no site line' }) (want localhost -> Work); the menu again ($($m2.said)): [$($m2.rule)] (want 'Stop always opening localhost in the Work workspace')" ($w -and $has -and $ok -and $g[1] -eq "localhost" -and $g[2] -eq $work -and $stop)
    }
    Row "M2" {
        $pv = Go "Private" $private
        $c = Count $siteSet
        $m = TabMenuItems "E18 c5p"
        $has = $m.items -ccontains "Always open localhost in the Private workspace"
        $p = if ($has) { OtherPress '^Always open localhost in the Private workspace$' } else { NoPopups; "not pressed" }
        $ok = WaitLog $siteSet ($c + 1) 10
        $g = @(Nth $siteSet $c)
        $m2 = TabMenuItems "E18 c5p"
        $stop = $m2.items -ccontains "Stop always opening localhost in the Private workspace"
        NoPopups
        $s = Sites
        $moved = $s.ok -and @($s.of[$private]) -contains "localhost" -and @($s.of[$work]) -notcontains "localhost"
        # Back to Work for the rows after: c5a's menu must offer it again.
        $w = Go "Work" $work
        $c2 = Count $siteSet
        $m3 = TabMenuItems "E18 c5a"
        $again = $m3.items -ccontains "Always open localhost in the Work workspace"
        $p3 = if ($again) { OtherPress '^Always open localhost in the Work workspace$' } else { NoPopups; "not pressed" }
        $back = (WaitLog $siteSet ($c2 + 1) 10) -and (@(Nth $siteSet $c2)[2] -eq $work)
        Verdict "M2 Private $pv; c5p's menu [$($m.rule)] (want 'Always open localhost in the Private workspace'); pressed ($p): $(if ($g.Count) { "'$($g[0])'" } else { 'no site line' }) (want localhost -> Private); again [$($m2.rule)] (want 'Stop always opening localhost in the Private workspace'); the live pref: $($s.said) (want localhost in Private only); Work $w, c5a's menu [$($m3.rule)] (want 'Always open localhost in the Work workspace'), pressed ($p3): back in Work $back" ($pv -and $has -and $ok -and $g[1] -eq "localhost" -and $g[2] -eq $private -and $stop -and $moved -and $w -and $again -and $back)
    }
    Row "R1" {
        $h = Go "Home" "default"
        Show (PageOf "c5home")
        $m = Marks
        $r = ClickLink "C5 ruled link" @(0x11)
        $g = Route $m
        $pg = [bool](WaitPage "c5r")
        $sw = (Count $active) - $m.active
        $stay = OnScreen "Home"
        $w = Go "Work" $work
        $first = FirstToday
        Verdict "R1 Home $h; Ctrl+click 'C5 ruled link' ($r): $($g.said); switches +$sw (want 0), Home still on screen $stay, c5r loaded $pg; then Work $($w): first Today tab '$first' (want E18 c5r)" ($h -and $g.ok -and $sw -eq 0 -and $stay -and $pg -and $w -and (IsTab $first "E18 c5r"))
    }
    Row "R2" {
        $h = Go "Home" "default"
        Show (PageOf "c5home")
        $m = Marks
        $r = ClickLink "C5 front link" @(0x11, 0x10)
        $g = Route $m
        $pg = [bool](WaitPage "c5f")
        $onWork = OnScreen "Work"
        $first = FirstToday
        Verdict "R2 Home $h; Ctrl+Shift+click 'C5 front link' ($r): $($g.said) (want 1+); Work on screen $onWork, c5f loaded $pg, first Today tab '$first' (want E18 c5f)" ($h -and $g.ok -and $g.follow -ge 1 -and $onWork -and $pg -and (IsTab $first "E18 c5f"))
    }
    Row "R3" {
        # Helium switches the bookmarks bar off (patches/helium/core/disable-bookmarks-bar.patch): the first run found
        # no "C5 bookmark" to right-click. The bookmark manager's own "Open in new tab" instead --
        # chrome.bookmarkManagerPrivate.openInNewTab, a background tab through OpenTabHelper (a LINK transition),
        # run in a chrome://bookmarks tab opened and closed through DevTools. The bookmarks MENU's AUTO_BOOKMARK road
        # stays untested hands-free (c5-progress.md).
        $h = Go "Home" "default"
        $m = Marks
        $bm = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?chrome://bookmarks" } catch { $null }
        $p = if (-not $bm) { "DevTools opened no chrome://bookmarks tab" } else {
            $js = "(async () => { const r = await chrome.bookmarks.search({ title: 'C5 bookmark' }); if (!r.length) return 'no C5 bookmark'; await chrome.bookmarkManagerPrivate.openInNewTab(r[0].id, { active: false, split: false }); return 'opened ' + r[0].id; })()"
            $said = Until { Evaluate $bm.webSocketDebuggerUrl $js } '^(opened|no C5)'
            $null = CloseTarget $bm
            "$said"
        }
        $g = Route $m
        $pg = [bool](WaitPage "c5k")
        $sw = (Count $active) - $m.active
        Verdict "R3 Home $h; the bookmark manager's Open in new tab on 'C5 bookmark' ($p): $($g.said); c5k loaded $pg (switches +$($sw), printed, not graded)" ($h -and $p -like "opened*" -and $g.ok -and $pg)
    }
    Row "N1" {
        $h = Go "Home" "default"
        $t = PageOf "c5home"
        Show $t
        $m = Marks
        $r = ClickLink "C5 same link"
        $u = Until { UrlOf $t.id } '/c5s\.html'
        Start-Sleep (2 * $slow)
        $rules = (Count $anyRule) - $m.rule; $sw = (Count $active) - $m.active
        $stay = OnScreen "Home"
        $inHome = [bool](TabIn (Today (Nodes $script:main)) "E18 c5s")
        $null = if ($t) { Evaluate $t.webSocketDebuggerUrl "history.back()" }
        $back = Until { UrlOf $t.id } '/c5home\.html'
        Verdict "N1 Home $h; a plain click on 'C5 same link' ($r): c5home's tab now '$u' (want sub.localhost/c5s.html); 'site rule: ' lines +$rules, switches +$sw (want 0, 0); Home still on screen $stay, E18 c5s in Home's Today $inHome; back to '$back'" ($h -and $t -and $u -match '^http://sub\.localhost:\d+/c5s\.html' -and $rules -eq 0 -and $sw -eq 0 -and $stay -and $inHome)
    }
    Row "N2" {
        $h = Go "Home" "default"
        Show (PageOf "c5home")
        $f = Front
        $m = Marks
        $pid32 = [uint32]$script:bpid
        $k = "Ctrl+T $([E18Input]::Keys($pid32, $false, 0x54))"
        Start-Sleep (1 * $slow)
        $k += "; '$(Url 'c5t' 'sub.localhost')' $([C5Input]::Type($pid32, (Url 'c5t' 'sub.localhost'))); Enter $([E18Input]::Tap($pid32, 0x0D))"
        $pg = [bool](WaitPage "c5t")
        Start-Sleep (1 * $slow)
        $rules = (Count $anyRule) - $m.rule; $sw = (Count $active) - $m.active
        $stay = OnScreen "Home"
        $inHome = [bool](TabIn (Today (Nodes $script:main)) "E18 c5t")
        Verdict "N2 Home $h ($f); $($k): c5t loaded $pg; 'site rule: ' lines +$rules, switches +$sw (want 0, 0); Home still on screen $stay, E18 c5t in Home's Today $inHome" ($h -and $pg -and $rules -eq 0 -and $sw -eq 0 -and $stay -and $inHome)
    }
    Row "L1" {
        $h = Go "Home" "default"
        $n0 = WindowCount
        $m = Marks; $cs = Count $skipped; $co = Count $opened; $ci = Count $inserted
        $said = Outside (Url "c5b" "sub.localhost")
        $sk = WaitLog $skipped ($cs + 1) 15
        $g = Route $m
        $pg = [bool](WaitPage "c5b")
        $kg = @(Nth $skipped $cs)
        $in = @(Lines $inserted | Select-Object -Skip $ci | Where-Object { $_.Matches[0].Groups[2].Value -eq $work }).Count
        $op = (Count $opened) - $co; $n1 = WindowCount
        # The guard: a host with no rule still opens the little window (check-c6 S1's first assertion).
        $co2 = Count $opened
        $said2 = Outside (Url "c5u")
        $lo = WaitLog $opened ($co2 + 1) 15
        $lw = @(); $t0 = Get-Date
        while (-not $lw.Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { $lw = @(Littles); if (-not $lw.Count) { Start-Sleep -Milliseconds 300 } }
        $pu = [bool](WaitPage "c5u")
        $n2 = WindowCount
        foreach ($x in @(Littles)) { [E18Input]::CloseWindow($x) }
        $t0 = Get-Date
        while (@(Littles).Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
        $n3 = WindowCount
        Verdict "L1 Home $h, windows $n0; an outside link to sub.localhost/c5b ($said): $(if ($kg.Count) { "'$($kg[0])'" } else { 'no skipped line' }) (want sub.localhost); $($g.said); inserts into Work +$in (want 1+); opened lines +$op (want 0); windows $n1 (want 1); c5b loaded $pg. The guard, 127.0.0.1/c5u ($said2): opened line $lo, windows $n2 (want 2), c5u loaded $pu; closed: windows $n3" ($h -and $n0 -eq 1 -and $sk -and $kg[1] -eq "sub.localhost" -and $g.ok -and $in -ge 1 -and $op -eq 0 -and $n1 -eq 1 -and $pg -and $lo -and $n2 -eq 2 -and $pu -and $n3 -eq 1)
    }
    Row "X1" {
        Remove-Item -LiteralPath $export -EA SilentlyContinue
        $c = Count $wrote
        NoPopups
        $r1 = Press $script:main "New tab, workspace or search" 0
        Start-Sleep -Milliseconds (800 * $slow)
        $r = "+ ($($r1.Substring(0, [Math]::Min(60, $r1.Length)))); $(OtherPress '^Export workspaces')"
        $ok = WaitLog $wrote ($c + 1) 30
        $g = @(Nth $wrote $c)
        $text = ""; $sites = @()
        try {
            $text = [string](([IO.File]::ReadAllText($export) | ConvertFrom-Json).files.'prefs.json'.content)
            $sites = @(@(($text | ConvertFrom-Json).helium.workspaces.list.items | Where-Object { $_.guid -eq $work }) | ForEach-Object { $_.sites } | Where-Object { $_ })
        } catch {}
        $has = $text -match '"sites"'
        Verdict "X1 the + menu's Export workspaces ($r): $(if ($g.Count) { "'$($g[0])'" } else { 'no wrote line' }); $export's prefs.json has `"sites`" $has, Work's sites [$($sites -join ',')] (want localhost)" ($ok -and $has -and $sites -contains "localhost")
    }
    Row "N3" {
        $s = OpenSettings $prof
        $dev = if ($s.ready) { $s.page.webSocketDebuggerUrl }
        $off = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('$enabled', false, '')" }
        $was = if ($dev) { Evaluate $dev "chrome.settingsPrivate.getPref('$enabled').then(p => p.value)" }
        Start-Sleep (2 * $slow)
        Show (PageOf "c5home")
        $m = Marks
        $r = ClickLink "C5 off link" @(0x11)
        $pg = [bool](WaitPage "c5o")
        Start-Sleep (2 * $slow)
        $rules = (Count $anyRule) - $m.rule
        $on = if ($dev) { Evaluate $dev "chrome.settingsPrivate.setPref('$enabled', true, '')" }
        $now = if ($dev) { Evaluate $dev "chrome.settingsPrivate.getPref('$enabled').then(p => p.value)" }
        $shut = CloseTarget $s.page
        Start-Sleep (2 * $slow)
        Verdict "N3 Workspaces off (Settings $($s.note)): setPref $off (want True), getPref $was (want False); Ctrl+click 'C5 off link' ($r): c5o loaded $pg, 'site rule: ' lines +$rules (want 0); back on: setPref $on, getPref $now (want True twice); Settings closed ($shut)" ($off -eq $true -and $was -eq $false -and $pg -and $rules -eq 0 -and $on -eq $true -and $now -eq $true)
    }
    Row "E1" {
        NoPopups
        $r = RightClick $script:main (NodeIn (Nodes $script:main) "Work" 0x2B) "Work chip"
        $p = if ($r -eq "right-clicked") { OtherPress '^Edit workspace' } else { "not pressed" }
        # The bubble: the popup holding "Remove localhost".
        $bw = [IntPtr]::Zero; $btn = $null; $before = @(); $t0 = Get-Date
        do {
            foreach ($x in Popups) {
                $nodes = @(Nodes $x)
                $b = @($nodes | Where-Object { $_.shown -and $_.name -eq "Remove localhost" }) | Select-Object -First 1
                if ($b) { $bw = $x; $btn = $b; $before = $nodes; break }
            }
            if (-not $btn) { Start-Sleep -Milliseconds 500 }
        } while (-not $btn -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
        $label = [bool](@($before | Where-Object { $_.shown -and $_.name -eq "localhost" }).Count)
        $none0 = [bool](@($before | Where-Object { $_.shown -and $_.name -match '^None yet\.' }).Count)
        $c = Count $removed
        $q = if ($btn) { PressNode $bw $btn } else { "no 'Remove localhost' drawn (popups: $((@(PopupNames) | Select-Object -First 30) -join ' | '))" }
        $ok = WaitLog $removed ($c + 1) 10
        $g = @(Nth $removed $c)
        $none1 = $false; $gone = $false; $t0 = Get-Date
        while ($btn -and -not ($none1 -and $gone) -and ((Get-Date) - $t0).TotalSeconds -lt 5 * $slow) {
            Start-Sleep -Milliseconds 500
            $after = @(Nodes $bw)
            $none1 = [bool](@($after | Where-Object { $_.shown -and $_.name -match '^None yet\. Right-click a tab' }).Count)
            $gone = -not @($after | Where-Object { $_.shown -and $_.name -eq "Remove localhost" }).Count
        }
        NoPopups
        Verdict "E1 the Work chip's menu ($r) > Edit workspace ($p): 'localhost' shown $label, 'Remove localhost' shown $([bool]$btn), the none line shown $none0 (want False); pressed ($q): $(if ($g.Count) { "'$($g[0])'" } else { 'no removed line' }) (want localhost); after: the none line shown $none1, the button gone $gone" ($label -and $btn -and -not $none0 -and $ok -and $g[1] -eq "localhost" -and $none1 -and $gone)
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
