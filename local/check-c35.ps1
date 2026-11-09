param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c35", [double]$IdleMinutes = 15)
# C35 + C31 + C32 (patches 74-76), on a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin;
# Sessions emptied), seeded before the start: Work gets a pinned page "C35 home" (a local page with one link), Canary
# a pinned page "C35 pinned Y" (never opened), Unpin no pinned page at all; the toolbar's New Tab off (LOCAL.md
# 86), the scheme dark. Real right-clicks and keys -- so it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says
# FREE (a person starting it passes -IdleMinutes 0 and lets go of the mouse and keyboard). Two starts: the second after
# a WM_CLOSE, with --restore-last-session and the scheme light. Both with --force-color-profile=srgb (this PC's display
# has HDR on: unforced, every captured colour reads ~4.6x too bright), and C35 is measured RELATIVE, from one capture:
# the card's fill against the strip beside it, its edge and the line under it against the bar's own hairline
# (ui::kColorSeparator). The pages are local (c35-pages, a port Windows gives); a page's title is "E18 <name>" plus
# its #part ("E18 c35x a" for c35x.html?c32#a).
#   C35a  dark, in Private (every row asleep: nothing active or hovered in the card): the fill 12..20 levels over the
#         strip (0x0B's +8 fails), the card's edge at its top and bottom middle and the line in the band under it each
#         the hairline's colour (2 levels); ui-tree: the section's Separator shown.
#   C35b  light, the same in Private after the restart: the fill 4..10 under the strip, the edge, the line.
#   C35c  Unpin (no pinned page): ui-tree: the section's Separator not shown, no card.
#   C31b  "C35 home" pressed (open, at home): its menu has Close page, not "Use current page".
#   C35d  (C35.1) that page in front: its highlight ringed in its workspace's colour, 30+ levels from the fill
#         and the card. C35e the same in the light (after C35b), on that page brought in front in Work.
#   C31a  its page follows its link (a trusted click through DevTools): the back arrow shows, the menu has the item;
#         pressed -> "takes the page in front as its address", the anchor moves there, the pins file holds the new
#         address and title (after the 2.5 s save), the back arrow goes, the row reads the new title, the item goes.
#   C32a  Canary: Today x?c32#a, x#b (the lower one left later), y#copy (Y = the pinned page's address), f#fav pinned (a
#         favorite), f#copy, z: its header's menu logs "duplicates: 3", "Close duplicate tabs..." enabled, the confirm
#         says 3; Close tabs -> Today the lower x + z (and the favorite), the Archive file +3, exactly those three.
#   C32a-rc  Recently Closed holds those three: read from Sessions\Tabs_* after the quit (the browser holds its session
#         files while it runs).
#   C32b  then: "duplicates: 0", the item greyed (msaa-press -States: UNAVAILABLE).
#   C32c  w?c32c#a, w#b, z in front, quit; after the restart (neither shown since): "duplicates: 1", the TOP one stays.
#   C32d  v#s1 + v#s2 made one split, v#g in a new group, v#loose: "duplicates: 1", the loose one closes, the split's
#         pages and the grouped one stay (D12).
#   Z     0 crash markers in both logs (case-sensitive, DanglingPtr too).
# A pass needs every row. Run it in its own process -- pwsh -File local\check-c35.ps1 [-Build Dcheck]
# [-IdleMinutes 0] -- it compiles C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = "$ws\helium-windows\build\src\out\$Build"
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$logs    = if ($Build -eq "Dcheck") { @("$ws\$Tag-dcheck-exercise.log", "$ws\$Tag-dcheck-exercise2.log") } else { @("$ws\$Tag-run.log", "$ws\$Tag-run2.log") }
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$private = "c9990cf0-c141-42fd-bb39-de33171ad078"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = 13
$active  = "\[workspaces\] active workspace -> '([^']*)'"
# The contract's lines (c35-progress.md, FINAL DESIGN W1 / W2).
$menuDup  = "\[workspaces\] duplicates: (\d+) of workspace '$canary' \(menu\)"
$askedDup = "\[workspaces\] duplicates: asked to close (\d+)"
$closeDup = "\[workspaces\] duplicates: closing (\d+) of (\d+) listed in workspace '$canary'"
$took     = "pins: 'c35p' takes the page in front as its address"
$archived = "\[workspaces\] archived a \w+ close in '$canary'"
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:port = 0; $script:main = [IntPtr]::Zero
$script:log = $logs[0]; $script:srv = $null; $script:gx = 0; $script:gy = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $script:log)) { return 0 }; @(Select-String -LiteralPath $script:log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Last([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Matches[0] }) } }
# The last line matching `re`: the whole match, then its groups, as strings (empty when none).
function Grp([string]$re) { $m = @(Last $re); if ($m.Count) { @($m[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function ActiveWs { $g = Grp $active; if ($g.Count) { $g[1] } else { "" } }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
# Every MSAA node of window `h` through e18-lib's one parser, each also "unavailable" (greyed: msaa-press -States).
function Nodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Rect", "-States") | ForEach-Object {
        $n = @(ParseMsaaNodes @("$_"))
        if ($n.Count) { $n[0] | Add-Member -NotePropertyName unavailable -NotePropertyValue ("$_" -match '\|UNAVAILABLE$') -PassThru }
    })
}
function RowNode([string]$name) { @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x24 -and $_.name -eq $name }) | Select-Object -Last 1 }
# Shown node `name` (role `role`) in the main window, polled until its being there is `want`.
function WaitNode([string]$name, [int]$role, [bool]$want) {
    $t0 = Get-Date
    do {
        if ([bool]@(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name }).Count -eq $want) { return $true }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $false
}
# Keys through SendKeys ("%+2" is Shift+Alt+2) to the browser's MAIN window in front: a dialog of the browser's own
# process passes a pid guard and swallows the key (LOCAL.md 88). -Any: to whatever browser window is in front (a menu,
# a bubble).
function Keys([string]$k, [switch]$Any) {
    if (-not $Any) {
        $t0 = Get-Date
        while ([C35Fg]::Front() -ne $script:main -and ((Get-Date) - $t0).TotalSeconds -lt 5 * $slow) { Start-Sleep -Milliseconds 200 }
        if ([C35Fg]::Front() -ne $script:main) {
            # Windows lets no program pull itself in front of the window last used (the session's own, 10-18): a real
            # click is the input that always may. The bottom middle of the page, blank on the test pages and the New Tab
            # page (the window is placed at 40,40 1400x900 in Launch).
            $c = [E18Input]::Click($script:main, 740, 900, $false)
            $t0 = Get-Date
            while ([C35Fg]::Front() -ne $script:main -and ((Get-Date) - $t0).TotalSeconds -lt 3 * $slow) { Start-Sleep -Milliseconds 200 }
            if ([C35Fg]::Front() -ne $script:main) { return "not sent: the browser's main window is not in front (a click: $c)" }
        }
    }
    if ([C35Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
# A workspace by its shortcut, its section drawn; the run stops when it does not show.
function Go([string]$k, [string]$guid) {
    if ((ActiveWs) -eq $guid) { return }
    $c = Count $active; $ch = Count "pins: header '$guid'"; $r = Keys $k
    if (-not ((WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid)) { throw "$k did not show workspace '$guid' ($r)" }
    $null = WaitLog "pins: header '$guid'" ($ch + 1) 10
    Start-Sleep (1 * $slow)
}
# A guarded right-click on `node` of window `h`, then the shown nodes of the menu that opened -- polled: the first
# popup read after a reboot can take over 5 s (LOCAL.md 88).
function OpenMenu([IntPtr]$h, $node) {
    if (-not $node) { return [pscustomobject]@{ result = "nothing to right-click"; items = @() } }
    $c = [E18Input]::Click($h, $node.l + [int]($node.w / 3), $node.t + [int]($node.h / 2), $true)
    $items = @(); $t0 = Get-Date
    do {
        Start-Sleep -Milliseconds 500
        $items = @(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $h)) { Nodes $w | Where-Object { $_.shown } })
    } while (-not $items.Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    [pscustomobject]@{ result = $c; items = $items }
}
function Names($items) { @($items | ForEach-Object { "$($_.name)$(if ($_.unavailable) { ' (greyed)' })" }) -join ", " }
# The first shown node matching `re` in the browser's other windows (a menu, a bubble), pressed via MSAA -- or, when
# its name did not survive MSAA's text round trip (Close duplicate tabs' U+2026 can come back as '?'), a guarded
# click at its middle (check-e14d3-auto's PressNode).
function OtherPress([IntPtr]$main, [string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) {
                $r = "$(Msaa $w @('-Name', $n.name, '-Role', $n.role))"
                if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
                return "'$($n.name)' $r"
            }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re'"
}
# Every line msaa-press lists in the browser's other windows: a bubble's text, its line breaks included.
function OtherText([IntPtr]$main) { (@(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) { Msaa $w @("-List") | ForEach-Object { "$_".Trim() } }) | Where-Object { $_ }) -join " / " }
# Today tab `title`'s menu (a guarded right-click), its item matching `re` pressed; Escape when there is none.
function TabMenu([string]$title, [string]$re) {
    $n = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "$title*" }) | Select-Object -First 1
    if (-not $n) { return "no Today tab '$title' drawn" }
    $m = [E18Input]::Click($script:main, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $r = OtherPress $script:main $re
    if ($r -like "nothing matching*") { $null = Keys "{ESC}" -Any }
    "$m; $r"
}
# Canary's menu from its header (the bar's own menu, E17b): the count it logged as it was built, its
# "Close duplicate tabs..." item (null when missing), every item -- the menu left open.
function DupMenu {
    $c = Count $menuDup
    $hdr = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x14 -and $_.name -eq "Canary" }) | Select-Object -First 1
    $m = OpenMenu $script:main $hdr
    $logged = WaitLog $menuDup ($c + 1) 10
    $g = Grp $menuDup
    [pscustomobject]@{ result = $m.result; logged = $logged; n = $(if ($logged -and $g.Count) { [int]$g[1] } else { -1 })
                       item = (@($m.items | Where-Object { $_.name -match '^Close duplicate tabs' }) | Select-Object -First 1); names = (Names $m.items) }
}
# The open menu's "Close duplicate tabs..." pressed, the confirm read, its "Close tabs" pressed: what each said --
# Escape instead when DupMenu's `d` has no enabled item.
function CloseDuplicates($d) {
    if (-not $d.item -or $d.item.unavailable) { $null = Keys "{ESC}" -Any; return [pscustomobject]@{ result = "not pressed"; asked = -1; text = ""; closing = "none" } }
    $ca = Count $askedDup; $cc = Count $closeDup
    $r = OtherPress $script:main '^Close duplicate tabs'
    $asked = WaitLog $askedDup ($ca + 1) 10
    $text = ""; $t0 = Get-Date
    do { Start-Sleep -Milliseconds 500; $text = OtherText $script:main } while ($text -notmatch 'duplicate tab' -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $ok = OtherPress $script:main '^Close tabs$'
    if ($ok -like "nothing matching*") { $null = Keys "{ESC}" -Any }
    $closing = WaitLog $closeDup ($cc + 1) 10
    $g = Grp $closeDup
    [pscustomobject]@{ result = "$r; $ok"; asked = $(if ($asked) { [int](Grp $askedDup)[1] } else { -1 }); text = $text
                       closing = $(if ($closing -and $g.Count) { "$($g[1]) of $($g[2])" } else { "none" }) }
}

# ---- the pages and DevTools (check-c14's) -------------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array to the pipeline as ONE object. The list is HTTP only:
# no tab is attached (attaching could load a restored tab that C32c needs never shown).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
# A page's short name: "c35x#a" for .../c35x.html?c32#a, "c35z" for .../c35z.html; "" for any other address.
function Tag([string]$u) { if ($u -match '/(c35\w+)\.html(?:\?\w+)?(?:#(\w+))?$') { "$($Matches[1])$(if ($Matches[2]) { '#' + $Matches[2] })" } else { "" } }
# The open pages whose short name matches `re`, sorted, one string.
function Tabs([string]$re) { (@(Targets | ForEach-Object { Tag $_.url } | Where-Object { $_ -and $_ -match $re }) | Sort-Object) -join " " }
function WaitTabs([string]$re, [string]$want) {
    $t0 = Get-Date
    do { $now = Tabs $re; if ($now -eq $want) { break }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $now
}
# Page `path` opened in front (/json/new: no opener), once loaded with
# title `title`: its target (id, url, webSocketDebuggerUrl).
function NewTab([string]$path, [string]$title) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $path)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$path'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne $title -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# The open page named `tag` once loaded, or $null.
function WaitTarget([string]$tag) {
    $t0 = Get-Date
    do {
        $t = @(Targets | Where-Object { (Tag $_.url) -eq $tag }) | Select-Object -First 1
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState") -eq "complete") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
# A page brought in front (/json/activate: the tab activated, as a click on it).
function Show($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# One DevTools call on page `t`: the reply ({id, result} or {id, error}), or $null. (e18-lib's Evaluate is
# Runtime.evaluate only.)
function Cdp($t, [string]$method, [hashtable]$params) {
    $sock = [Net.WebSockets.ClientWebSocket]::new(); $none = [Threading.CancellationToken]::None
    try {
        if (-not $sock.ConnectAsync([Uri]$t.webSocketDebuggerUrl, $none).Wait(10000)) { return $null }
        $o = [Text.Encoding]::UTF8.GetBytes((@{ id = 1; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 4))
        if (-not $sock.SendAsync([ArraySegment[byte]]::new($o), [Net.WebSockets.WebSocketMessageType]::Text, $true, $none).Wait(10000)) { return $null }
        $buf = [byte[]]::new(65536); $got = 0
        do {
            $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf, $got, $buf.Length - $got), $none)
            if (-not $r.Wait(15000)) { return $null }
            $got += $r.Result.Count
        } until ($r.Result.EndOfMessage)
        [Text.Encoding]::UTF8.GetString($buf, 0, $got) | ConvertFrom-Json
    } catch { $null } finally { $sock.Dispose() }
}
# A plain click on link `id` of page `t`: DevTools' Input.dispatchMouseEvent is trusted input through the renderer,
# a real click's road (check-c14's CtrlClick, no Ctrl) -- the page navigates in its own tab.
function ClickLink($t, [string]$id) {
    $xy = @(Evaluate $t.webSocketDebuggerUrl "(() => { const r = document.getElementById('$id').getBoundingClientRect(); return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]; })()")
    if ($xy.Count -ne 2) { return "no link '$id' ($xy)" }
    foreach ($e in @(@{ type = "mousePressed"; buttons = 1 }, @{ type = "mouseReleased"; buttons = 0 })) {
        $r = Cdp $t "Input.dispatchMouseEvent" @{ type = $e.type; x = $xy[0]; y = $xy[1]; button = "left"; buttons = $e.buttons; clickCount = 1 }
        if (-not $r -or $r.error) { return "$($e.type) refused ($(if ($r) { $r.error.message } else { 'no reply' }))" }
    }
    "clicked at $($xy[0]),$($xy[1])"
}

# ---- the files -----------------------------------------------------------------------------------------------------
# Item `id` at the top level of workspace `guid` as saved (the file is written 2.5 s after a change).
function PinItem([string]$guid, [string]$id) {
    try { $d = Get-Content -Raw -Encoding UTF8 -LiteralPath "$prof\Default\Workspace Pins" | ConvertFrom-Json } catch { return $null }
    @($d.workspaces.$guid | Where-Object { $_ -and $_.id -eq $id }) | Select-Object -First 1
}
function WaitPin([string]$guid, [string]$id, [string]$url) {
    $t0 = Get-Date
    do { Start-Sleep 1; $i = PinItem $guid $id; if ($i -and $i.url -eq $url) { break } } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $i
}
function ArchiveEntries {
    $f = "$prof\Default\Workspace Archive"
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    try { @((Get-Content -Raw -Encoding UTF8 -LiteralPath $f | ConvertFrom-Json).entries | Where-Object { $_ }) } catch { @() }
}
function WaitArchive([int]$n) {
    $t0 = Get-Date
    do { Start-Sleep 1; $e = @(ArchiveEntries) } while ($e.Count -lt $n -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow)
    $e
}
# Which of `urls` the Recently Closed file holds: Sessions\Tabs_* keeps each closed tab's address as plain text. Read
# with the browser closed.
function InTabsFile([string[]]$urls) {
    $text = (@(Get-ChildItem -LiteralPath "$prof\Default\Sessions" -Filter "Tabs_*" -File -EA SilentlyContinue | ForEach-Object { [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($_.FullName)) })) -join ""
    @($urls | Where-Object { $text.Contains($_) })
}
# The pinned section's own children through Chromium's UI DevTools (ui-tree.py; the browser started with
# --enable-ui-devtools=0): class, shown, line -- and all ui-tree printed, for a FAIL.
function SectionKids {
    $out = @(& python -I "$here\ui-tree.py" $prof --root WorkspacePinnedSectionView 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ raw = (@($out | ForEach-Object { $_.Trim() }) -join " / ")
                       kids = @($out | ForEach-Object { if ($_ -match '^  (\S+) @') { [pscustomobject]@{ cls = $Matches[1]; shown = $_ -notmatch ' INVISIBLE'; line = $_.Trim() } } }) }
}
# The line under the card (C35): the section's first Separator.
function CardLine($kids) { @($kids.kids | Where-Object { $_.cls -eq "Separator" }) | Select-Object -First 1 }

# ---- pixels (C35) --------------------------------------------------------------------------------------------------
# Colors are 0xRRGGBB; a channel k = 0 red, 1 green, 2 blue; the distance is the largest channel's.
function Ch([int]$c, [int]$k) { ($c -shr (16 - 8 * $k)) -band 255 }
function Dist([int]$a, [int]$b) { $m = 0; foreach ($k in 0..2) { $d = [Math]::Abs((Ch $a $k) - (Ch $b $k)); if ($d -gt $m) { $m = $d } }; $m }
function Hex([int]$c) { if ($c -lt 0) { "none" } else { '#{0:x6}' -f $c } }
# The screen's pixels in a box (physical, per-monitor aware as the MSAA boxes are): a Bitmap whose 0,0 is (x, y).
function Grab([int]$x, [int]$y, [int]$w, [int]$h) {
    [C35Fg]::Aware()
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size) } finally { $g.Dispose() }
    $bmp
}
function At($bmp, [int]$x, [int]$y) { $bmp.GetPixel($x - $script:gx, $y - $script:gy).ToArgb() -band 0xFFFFFF }
function Column($bmp, [int]$x, [int]$y0, [int]$y1) { @(for ($y = $y0; $y -le $y1; $y++) { At $bmp $x $y }) }
# A column as runs, for a FAIL: "#1e2020x2 #5d5e5fx1 ...".
function Rle([int[]]$col) {
    $out = @(); $i = 0
    while ($i -lt $col.Count) { $j = $i; while ($j + 1 -lt $col.Count -and $col[$j + 1] -eq $col[$i]) { $j++ }; $out += "$(Hex $col[$i])x$($j - $i + 1)"; $i = $j + 1 }
    $out -join " "
}
# The runs of `col` (top first) that stand out from `bg` by more than `min`: where each starts, and its strongest
# pixel (an edge drawn across two rows at a fractional scale is one run).
function Peaks([int[]]$col, [int]$bg, [double]$min) {
    $runs = @(); $start = -1
    for ($i = 0; $i -le $col.Count; $i++) {
        $on = $i -lt $col.Count -and (Dist $col[$i] $bg) -gt $min
        if ($on -and $start -lt 0) { $start = $i }
        if (-not $on -and $start -ge 0) {
            $best = $col[$start]
            for ($j = $start; $j -lt $i; $j++) { if ((Dist $col[$j] $bg) -gt (Dist $best $bg)) { $best = $col[$j] } }
            $runs += [pscustomobject]@{ at = $start; px = $best }
            $start = -1
        }
    }
    $runs
}
# C35 in window `h` on workspace `name` (its header's MSAA name), from ONE capture saved as `png`, boxes from MSAA:
# the fill (just inside the card's top padding, at its middle) against the strip at the same height (the card's side
# margin); the bar's own hairline (a column through the bar's Archive button, from above the bar down to the
# button's empty top); the card's top edge (between the header and the first row) and, under the last row, its
# bottom edge then the line, each as a run standing out from the strip by over half the hairline's distance --
# never beside a row. ok: the fill's mean shift in lo..hi and the three runs the hairline's colour (2 levels).
# C35.1: the pinned page in front (row `name`) ringed in its workspace's colour -- the row's top edge vs its fill just
# inside and the card just above, the mouse on the page (a hovered row paints its own background). One capture, saved.
function MeasureRing([IntPtr]$h, [string]$name, [string]$png) {
    $res = [pscustomobject]@{ ok = $false; text = "" }
    $bmp = $null
    try {
        $cl = [E18Input]::Client($h)
        $moved = [C35Fg]::Hover($h, $cl[0] + [int]($cl[2] * 0.7), $cl[1] + [int]($cl[3] * 0.5))
        Start-Sleep -Milliseconds (600 * $slow)
        $row = RowNode $name
        if (-not $row) { $res.text = "not measured: no row '$name' (mouse $moved)"; return $res }
        $script:gx = $row.l - 4; $script:gy = $row.t - 4
        $bmp = Grab $script:gx $script:gy ($row.w + 8) ($row.h + 8)
        $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $x = $row.l + [int]($row.w * 0.8)
        $col = Column $bmp $x ($row.t - 3) ($row.t + 5)
        $ring = At $bmp $x $row.t; $fill = At $bmp $x ($row.t + 4); $card = At $bmp $x ($row.t - 2)
        $dFill = Dist $ring $fill; $dCard = Dist $ring $card
        $res.ok = $dFill -ge 30 -and $dCard -ge 30
        $res.text = "row '$name' @$($row.l),$($row.t) $($row.w)x$($row.h) (mouse $moved): its top edge $(Hex $ring), the fill $(Hex $fill) ($dFill levels apart, want 30+), the card above $(Hex $card) ($dCard apart, want 30+); column x=$x from y=$($row.t - 3): [$(@($col | ForEach-Object { Hex $_ }) -join ' ')]; capture $png"
    } catch { $res.text = "not measured: $_" } finally { if ($bmp) { $bmp.Dispose() } }
    $res
}
function MeasureCard([IntPtr]$h, [string]$name, [string]$png, [double]$lo, [double]$hi) {
    $res = [pscustomobject]@{ ok = $false; text = "" }
    $bmp = $null
    try {
        # The mouse over the page first: a hovered header, row or "+ New Tab" paints its own background.
        $cl = [E18Input]::Client($h)
        $moved = [C35Fg]::Hover($h, $cl[0] + [int]($cl[2] * 0.7), $cl[1] + [int]($cl[3] * 0.5))
        $t0 = Get-Date
        while ([C35Fg]::Front() -ne $h -and ((Get-Date) - $t0).TotalSeconds -lt 3 * $slow) { Start-Sleep -Milliseconds 200 }
        $front = [C35Fg]::Front() -eq $h
        Start-Sleep -Milliseconds (600 * $slow)
        $nodes = @(Nodes $h)
        $rows = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x24 } | Sort-Object t)
        $hdr = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x14 -and $_.name -eq $name }) | Select-Object -First 1
        $bar = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq "Archive" }) | Sort-Object t | Select-Object -Last 1
        if (-not $rows.Count -or -not $hdr -or -not $bar) { $res.text = "not measured: rows $($rows.Count), header '$name' $([bool]$hdr), the bar's Archive button $([bool]$bar)"; return $res }
        $first = $rows[0]
        $bottom = @($rows | ForEach-Object { $_.t + $_.h } | Sort-Object)[-1]
        $nt = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq "New Tab" -and $_.t -ge $bottom }) | Sort-Object t | Select-Object -First 1
        $dpi = [E18Input]::Dpi($h); $s = $dpi / 96.0
        $end = if ($nt) { $nt.t - 1 } else { $bottom + [int](18 * $s) }
        $mid = $first.l + [int]($first.w / 2)
        $bgx = $first.l - 1 - [int][Math]::Round(4 * $s)
        $barx = $bar.l + [int]($bar.w / 2)
        $hy0 = $bar.t - [int][Math]::Round(10 * $s)
        $ty0 = $hdr.t + $hdr.h - 2
        $script:gx = [Math]::Min($bgx, $barx); $script:gy = $ty0 - 1
        $bmp = Grab $script:gx $script:gy ([Math]::Max($mid, $barx) - $script:gx + 1) ($bar.t + 3 - $script:gy + 1)
        $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $bg = At $bmp $bgx ($first.t - 1)
        $fill = At $bmp $mid ($first.t - 1)
        $delta = 0.0; foreach ($k in 0..2) { $delta += ((Ch $fill $k) - (Ch $bg $k)) / 3.0 }
        $hcol = Column $bmp $barx $hy0 ($bar.t + 2)
        $hp = @(Peaks $hcol $hcol[0] 6)
        $hair = if ($hp.Count) { @($hp | Sort-Object { Dist $_.px $hcol[0] })[-1].px } else { -1 }
        $top = Column $bmp $mid $ty0 ($first.t - 1)
        $low = Column $bmp $mid $bottom $end
        $thr = if ($hair -ge 0) { (Dist $hair $bg) / 2.0 } else { 255 }
        $tp = @(Peaks $top $bg $thr); $lp = @(Peaks $low $bg $thr)
        $edges = @($tp | Select-Object -First 1 | ForEach-Object { $_.px }) + @($lp | Select-Object -First 2 | ForEach-Object { $_.px })
        $match = $hair -ge 0 -and $tp.Count -eq 1 -and $lp.Count -eq 2 -and @($edges | Where-Object { (Dist $_ $hair) -le 2 }).Count -eq 3
        $res.ok = $match -and $delta -ge $lo -and $delta -le $hi
        $res.text = "dpi $dpi, the main window in front: $front (mouse $moved); strip $(Hex $bg), fill $(Hex $fill) ($('{0:+0.0;-0.0}' -f $delta), want $lo..$hi); " +
                    "the bar's hairline $(Hex $hair); the card's top edge $(@($tp | ForEach-Object { Hex $_.px }) -join ', ') ($($tp.Count) run(s), want 1); " +
                    "under the last row $(@($lp | ForEach-Object { "$(Hex $_.px) at +$($_.at)" }) -join ', ') ($($lp.Count) run(s), want 2: the edge, then the line); " +
                    "columns at x=${mid}: top y=$ty0 [$(Rle $top)], bottom y=$bottom [$(Rle $low)]; hairline x=$barx y=$hy0 [$(Rle $hcol)]; capture $png"
    } catch {
        $res.text = "not measured: $_ (line $($_.InvocationInfo.ScriptLineNumber))"
    } finally {
        if ($bmp) { $bmp.Dispose() }
    }
    $res
}

# ---- one start of the browser, and its quit ----------------------------------------------------------------------
function Launch([string[]]$extra, [string]$ready) {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", "$prof\UIDevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--helium-workspaces-log-addresses", "--remote-debugging-port=0", "--enable-ui-devtools=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check") + $extra
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog $ready 1 30
    [E18Input]::Place($script:main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid) $($extra -join ' '), DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log); session '$env:SESSIONNAME', screen $([E18Input]::Screen() -join 'x'), window dpi $([E18Input]::Dpi($script:main))"
}
# Every window closed as its X does (WM_CLOSE: the session kept for --restore-last-session), the browser waited for;
# stragglers of this build stopped. What happened.
function Quit {
    if (-not ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue))) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Get-Process -Id $script:bpid -EA SilentlyContinue)
    $secs = [int]((Get-Date) - $t0).TotalSeconds; $t1 = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) -and ((Get-Date) - $t1).TotalSeconds -lt 10) { Start-Sleep 1 }
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' }) in $secs s$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
$with = foreach ($s in @("takes the page in front as its address", "duplicates: closing")) {
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -eq 0) { "WITH" } else { "WITHOUT" }
}
Say "build: $Build\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $($with[0]) patch 75, $($with[1]) patch 76 (74 logs nothing: C35a-b are its check)"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C35Fg { [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; } [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c); [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(P p); [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } public static IntPtr Front() { return GetForegroundWindow(); } public static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); } public static string Hover(IntPtr h, int x, int y) { Aware(); P p; p.x = x; p.y = y; if (GetAncestor(WindowFromPoint(p), 2) != h) return "not moved: another window is at " + x + "," + y; SetCursorPos(x, y); System.Threading.Thread.Sleep(400); return "moved"; } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $logs -EA SilentlyContinue
$names = @("c35home", "c35away", "c35x", "c35y", "c35f", "c35z", "c35w", "c35v")
$script:srv = ServePages $pages $names
if (-not $script:srv.ok) { Abort "the local pages were not served" }
# Over ServePages' plain pages: the #part joins the title (two copies of one address told apart), and one link.
foreach ($nm in $names) {
    Set-Content -Encoding ASCII -LiteralPath "$pages\$nm.html" -Value "<!doctype html><title>E18 $nm</title><script>if (location.hash) document.title += ' ' + location.hash.slice(1);</script><h1>E18 $nm</h1><p><a id='next' href='c35away.html'>next</a>"
}
# The pins: "C35 home" (c35p) at the end of Work, "C35 pinned Y" (c35y) at the end of Canary, Unpin emptied.
# Written as UTF-8, its version (1) kept, as check-c3 does.
& python -c "import json,sys; p,port,work,canary,unpin=sys.argv[1:6]; u='http://127.0.0.1:%s/' % port; d=json.load(open(p,encoding='utf-8')); d['workspaces'][work].append({'type':'item','id':'c35p','title':'C35 home','url':u+'c35home.html'}); d['workspaces'][canary].append({'type':'item','id':'c35y','title':'C35 pinned Y','url':u+'c35y.html'}); d['workspaces'][unpin]=[]; open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins" $script:srv.port $work $canary $unpin
if ($LASTEXITCODE -ne 0) { Abort "the pinned pages were not seeded into $prof" }
# Dark first; the toolbar's own New Tab off, so "New Tab" is the sidebar's alone (LOCAL.md 86).
& python -I "$here\prefs.py" "$prof\Default\Preferences" "browser.theme.color_scheme2=2" "helium.browser.show_dynamic_new_tab_button=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$awayUrl = Url "c35away.html"
$xKeep = "a"; $xGone = "b"
$wBefore = @(); $atQuit = ""
# The two copies of `stem` (?`q`#a, #b) as drawn, top first: "a","b" -- by their page tabs' screen tops (a loaded
# copy's name is its title "E18 <stem> a", a never-loaded one's its address).
function CopyOrder([string]$stem, [string]$q) { $re = "$stem(?:\.html\?$q#| )([ab])\b"; @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -match $re } | Sort-Object t | ForEach-Object { if ($_.name -match $re) { $Matches[1] } }) }
function WTabs { CopyOrder 'c35w' 'c32c' }

# ---- the first start: dark ----------------------------------------------------------------------------------------
try {
    Launch @() "pins: drew \d+ row\(s\) of 'default'"

    # C35a: the card in the dark, in Private (no page open there: no row active).
    Go "%+4" $private
    $null = WaitLog "pins: drew \d+ row\(s\) of '$private'" 1 10
    Start-Sleep (1 * $slow)
    $m = MeasureCard $script:main "Private" "$ws\$Tag$suffix-c35a-dark.png" 12 20
    $k = SectionKids; $sep = CardLine $k
    Verdict "C35a dark: $($m.text); ui-tree: the line $(if ($sep) { $sep.line } else { "not found ($($k.raw))" })" ($m.ok -and $sep -and $sep.shown)

    # C35c: no pinned page, no card, no line.
    Go "%+5" $unpin
    Start-Sleep (1 * $slow)
    $k = SectionKids; $sep = CardLine $k
    $cards = @($k.kids | Where-Object { $_.cls -eq "View" -and $_.shown }).Count
    $rows = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x24 }).Count
    Verdict "C35c Unpin, no pinned page (rows drawn: $rows): the line $(if ($sep) { $sep.line } else { 'not found' }), $cards card(s) shown; the section's children: $(if ($k.kids.Count) { @($k.kids | ForEach-Object { $_.line }) -join ' | ' } else { $k.raw })" ($sep -and -not $sep.shown -and $cards -eq 0 -and $rows -eq 0)

    # C31b: a pinned page at home offers no replace.
    Go "%+2" $work
    $null = WaitLog "pins: drew \d+ row\(s\) of '$work'" 1 10
    $c = Count "pins: opened item 'c35p'"
    $r = Press $script:main "C35 home"
    $opened = WaitLog "pins: opened item 'c35p'" ($c + 1) 10
    $homePage = WaitTarget "c35home"
    Start-Sleep (1 * $slow)
    $ring = MeasureRing $script:main "C35 home" "$ws\$Tag$suffix-c35d-ring-dark.png"
    Verdict "C35d dark: the page in front ringed in its workspace's colour: $($ring.text)" $ring.ok
    $m = OpenMenu $script:main (RowNode "C35 home")
    $null = Keys "{ESC}" -Any
    $items = @($m.items | ForEach-Object { $_.name })
    Verdict "C31b 'C35 home' pressed ($r; opened: $opened; its page loaded: $([bool]$homePage)), at home its menu ($($m.result)): $(Names $m.items)" ($opened -and $homePage -and ($items -contains "Close page") -and -not ($items -contains "Use current page"))

    # C31a: the page follows its link; the item replaces the pinned address with it.
    $link = if ($homePage) { ClickLink $homePage "next" } else { "no page to click in" }
    $away = WaitTarget "c35away"
    $back = WaitNode "Back to the pinned page" 0x2B $true
    $m = OpenMenu $script:main (RowNode "C35 home")
    $offered = @($m.items | Where-Object { $_.name -eq "Use current page" }).Count -gt 0
    $anchor = "anchor at index \d+ -> '$([regex]::Escape($awayUrl))'"
    $ct = Count $took; $ca = Count $anchor
    $p = if ($offered) { OtherPress $script:main '^Use current page$' } else { $null = Keys "{ESC}" -Any; "not offered" }
    $logged = WaitLog $took ($ct + 1) 10
    $anch = WaitLog $anchor ($ca + 1) 5
    $item = WaitPin $work "c35p" $awayUrl
    $gone = WaitNode "Back to the pinned page" 0x2B $false
    $renamed = WaitNode "E18 c35away" 0x24 $true
    $m2 = OpenMenu $script:main (RowNode "E18 c35away")
    $null = Keys "{ESC}" -Any
    $again = @($m2.items | Where-Object { $_.name -eq "Use current page" }).Count -gt 0
    Verdict "C31a its link ($link; the page now: $(if ($away) { $away.url } else { 'not c35away' })): the back arrow showed: $back; the menu ($($m.result)): $(Names $m.items); the item pressed ($p): '$took' logged: $logged, the anchor moved: $anch; the pins file: url '$($item.url)' title '$($item.title)' (want '$awayUrl', 'E18 c35away'); the back arrow gone: $gone; the row reads 'E18 c35away': $renamed; its menu again ($($m2.result)): $(Names $m2.items)" ($back -and $offered -and $logged -and $anch -and $item -and $item.url -eq $awayUrl -and $item.title -eq "E18 c35away" -and $gone -and $renamed -and $m2.items.Count -and -not $again)

    # C32a: three copies close, the one used last stays -- the LOWER x copy, shown again after both opened, so "the
    # top one" would be the wrong keeper (review C35-CHK-1). Which is lower is read off the screen: where /json/new
    # puts a tab is the browser's to decide (10-18: below the one before, not at the top as first assumed).
    Go "%+3" $canary
    $null = WaitLog "pins: drew \d+ row\(s\) of '$canary'" 1 10
    $xa = NewTab "c35x.html?c32#a" "E18 c35x a"
    $xb = NewTab "c35x.html?c32#b" "E18 c35x b"
    $xo = @(CopyOrder 'c35x' 'c32')
    if ($xo.Count -eq 2) { $xKeep = $xo[1]; $xGone = $xo[0] }
    Show $(if ($xKeep -eq "a") { $xa } else { $xb })
    $null = NewTab "c35y.html#copy" "E18 c35y copy"
    $null = NewTab "c35f.html#fav" "E18 c35f fav"
    $pin = TabMenu "E18 c35f fav" '^Add to Favorites'
    Start-Sleep (1 * $slow)
    $fav = @(Nodes $script:main | Where-Object { $_.role -eq 0x25 -and $_.name -like "E18 c35f fav*Pinned*" }).Count -gt 0
    $null = NewTab "c35f.html#copy" "E18 c35f copy"
    $z = NewTab "c35z.html" "E18 c35z"
    $before = Tabs '^c35[xyfz]'
    $ae = @(ArchiveEntries).Count; $al = Count $archived
    $d = DupMenu
    $enabled = $d.item -and -not $d.item.unavailable
    $x = CloseDuplicates $d
    $today = WaitTabs '^c35[xyfz]' "c35f#fav c35x#$xKeep c35z"
    $arch = @(WaitArchive ($ae + 3))
    $archTags = (@($arch | Where-Object { $_.workspace -eq $canary } | ForEach-Object { Tag $_.url } | Where-Object { $_ }) | Sort-Object) -join " "
    Verdict "C32a 'E18 c35f fav' pinned ($pin; a favorite: $fav); Today $before (the x copies drawn top first: $($xo -join ','); the lower one shown last); the menu ($($d.result)) logged $($d.n) (want 3): $($d.names); pressed ($($x.result)): asked $($x.asked), the confirm '$($x.text)', closing $($x.closing); Today now $today (want c35f#fav c35x#$xKeep c35z); the Archive file $ae -> $($arch.Count) entries, this workspace's c35 pages: $archTags (want c35f#copy c35x#$xGone c35y#copy); 'archived' lines +$((Count $archived) - $al)" ($xo.Count -eq 2 -and $fav -and $d.logged -and $d.n -eq 3 -and $enabled -and $x.asked -eq 3 -and $x.text.Contains("Close 3 duplicate tabs?") -and $x.closing -eq "3 of 3" -and $today -eq "c35f#fav c35x#$xKeep c35z" -and $arch.Count -eq $ae + 3 -and $archTags -eq "c35f#copy c35x#$xGone c35y#copy")

    # C32b: nothing left to close, the item greyed.
    $d = DupMenu
    $null = Keys "{ESC}" -Any
    Verdict "C32b no copies left: the menu ($($d.result)) logged $($d.n) (want 0), its item $(if ($d.item) { if ($d.item.unavailable) { 'greyed' } else { 'NOT greyed' } } else { 'missing' }): $($d.names)" ($d.logged -and $d.n -eq 0 -and $d.item -and $d.item.unavailable)

    # C32c's two copies, z in front at the quit: after the restart neither has been shown. The LOWER one is left
    # last in THIS run, so a clock carried over the restart would keep it, not the top one (review C35-CHK-2).
    $wa = NewTab "c35w.html?c32c#a" "E18 c35w a"
    $wb = NewTab "c35w.html?c32c#b" "E18 c35w b"
    $wo = @(WTabs)
    Show $(if ($wo.Count -eq 2 -and $wo[1] -eq "b") { $wb } else { $wa })
    Show $z
    $wBefore = @(WTabs)
    $atQuit = Tabs '^c35[xyfzw]'
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q1 = Quit
}
$found = @(InTabsFile @((Url "c35x.html?c32#$xGone"), (Url "c35y.html#copy"), (Url "c35f.html#copy")))
Verdict "C32a-rc Recently Closed (Sessions\Tabs_* after the quit: $q1) holds $($found.Count) of the 3 closed copies ($(@($found | ForEach-Object { Tag $_ }) -join ' ')), none of them open at the quit (open: $atQuit)" ($found.Count -eq 3 -and $atQuit -and $atQuit -notmatch "c35x#$xGone|c35y#copy|c35f#copy")

# ---- the second start: light, the last session restored ----------------------------------------------------------
& python -I "$here\prefs.py" "$prof\Default\Preferences" "browser.theme.color_scheme2=1"
$script:log = $logs[1]
try {
    if ($LASTEXITCODE -ne 0) { throw "the light scheme was not seeded" }
    Launch @("--restore-last-session") "pins: drew \d+ row\(s\) of '"

    # C35b: the card in the light, in Private.
    Go "%+4" $private
    $null = WaitLog "pins: drew \d+ row\(s\) of '$private'" 1 10
    Start-Sleep (1 * $slow)
    $m = MeasureCard $script:main "Private" "$ws\$Tag$suffix-c35b-light.png" -10 -4
    $k = SectionKids; $sep = CardLine $k
    Verdict "C35b light: $($m.text); ui-tree: the line $(if ($sep) { $sep.line } else { "not found ($($k.raw))" })" ($m.ok -and $sep -and $sep.shown)

    # C35e: the ring in the light, on Work's pinned page (C31 renamed it; restored by the restart) brought in front.
    Go "%+2" $work
    $null = WaitLog "pins: drew \d+ row\(s\) of '$work'" 1 10
    $pr = Press $script:main "E18 c35away"
    Start-Sleep (2 * $slow)
    $ring = MeasureRing $script:main "E18 c35away" "$ws\$Tag$suffix-c35e-ring-light.png"
    Verdict "C35e light: the page in front ringed ($pr): $($ring.text)" $ring.ok

    # C32c: after a restart, no copy used yet: the top one stays.
    Go "%+3" $canary
    Start-Sleep (2 * $slow)
    $wAfter = @(WTabs)
    $d = DupMenu
    $enabled = $d.item -and -not $d.item.unavailable
    $x = CloseDuplicates $d
    $t0 = Get-Date
    do { Start-Sleep -Milliseconds 500; $wLeft = @(WTabs) } while ($wLeft.Count -gt 1 -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    Verdict "C32c the quit ($q1), the restart: the copies drawn top first $($wAfter -join ',') (before the quit $($wBefore -join ','); read before the lower one was shown: $($wo -join ',')); the menu ($($d.result)) logged $($d.n) (want 1): $($d.names); pressed ($($x.result)): the confirm '$($x.text)', closing $($x.closing); left: $($wLeft -join ',') (want the top one)" ($wo.Count -eq 2 -and $wAfter.Count -eq 2 -and $d.n -eq 1 -and $enabled -and $x.text.Contains("Close 1 duplicate tab?") -and $x.closing -eq "1 of 1" -and $wLeft.Count -eq 1 -and $wLeft[0] -eq $wAfter[0])

    # C32d: a split's pages and a grouped tab are kept; the loose copy closes.
    $null = NewTab "c35v.html?c32d#s1" "E18 c35v s1"
    $null = NewTab "c35v.html?c32d#s2" "E18 c35v s2"
    $sp = TabMenu "E18 c35v s1" '^New split view with current tab'
    Start-Sleep (2 * $slow)
    $null = NewTab "c35v.html?c32d#g" "E18 c35v g"
    $gr = TabMenu "E18 c35v g" '^Add tab to new group$'
    # The new group's name bubble, closed (check-c14 C34g's way).
    Start-Sleep (2 * $slow); $null = Keys "{ESC}" -Any
    $null = NewTab "c35v.html?c32d#loose" "E18 c35v loose"
    $zt = @(Targets | Where-Object { (Tag $_.url) -eq "c35z" }) | Select-Object -First 1
    if ($zt) { Show $zt }
    # The vertical strip names an unnamed group's header "unnamed group - 1 tab, <bullet>  <titles> - Expanded".
    $grouped = @(Nodes $script:main | Where-Object { $_.shown -and $_.name -match '^ ?unnamed group - .*c35v g' }).Count
    $before = Tabs '^c35v'
    $d = DupMenu
    $enabled = $d.item -and -not $d.item.unavailable
    $x = CloseDuplicates $d
    $v = WaitTabs '^c35v' "c35v#g c35v#s1 c35v#s2"
    Verdict "C32d s1 + s2 split ($sp), g grouped ($gr; group headers drawn: $grouped), z in front ($([bool]$zt)); open $before; the menu ($($d.result)) logged $($d.n) (want 1): $($d.names); pressed ($($x.result)): the confirm '$($x.text)', closing $($x.closing); open now $v (want c35v#g c35v#s1 c35v#s2)" ($d.n -eq 1 -and $enabled -and $x.text.Contains("Close 1 duplicate tab?") -and $x.closing -eq "1 of 1" -and $v -eq "c35v#g c35v#s1 c35v#s2")
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q2 = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
# Case-sensitive, as LOCAL.md grades: a Dcheck exit can dump the histogram
# "Commerce.PriceTracking.DanglingUserSubscriptionCountAtStartup", no crash (LOCAL.md 86); the dangling-raw_ptr
# detector's own reports say DanglingPtr.
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($logs -join ', ') (the last quit: $q2): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$verdict"
Say "check-c35 ${Build}: $($script:passed)/$total, crash markers $markers"
exit [int]($verdict -eq "FAIL")
