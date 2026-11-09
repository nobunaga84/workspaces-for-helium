param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c4", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# C4 (patches 80-81, c4-progress.md "FINAL DESIGN"): a Today tab or a pinned page dropped on a workspace's chip moves
# there -- a moved Today tab to the TOP of that workspace's Today, the menus' moves too -- and a chip dragged along the
# bar reorders the workspaces. On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin;
# Work's pinned rows Example A, Smoke folder (open), Closed folder, Example D; Sessions emptied), seeded before the
# start: the sidebar 280 wide (all five chips drawn, no scroll arrow) and the toolbar's New Tab off (LOCAL.md 86).
# The drags are REAL mouse input (SendInput), each point guarded (the user's desktop, the fork's window under it, the
# cursor where it was sent): it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE.
#   pwsh -NoProfile -File local\check-c4.ps1 [-Build Dcheck] [-IdleMinutes 0]
# In its own process (it compiles C# types); -IdleMinutes 0 when the owner is away or starts it and lets go.
# The pages are local ("E18 <name>", a port Windows gives), opened through DevTools. Every drop row grades the browser
# still running, no window added (a tear-off) and no switch (no new "active workspace ->" line, the window still drawing
# Work's pinned header) -- then closes any extra window and menu, so one failure is one row's.
#   seed  (CHK-4, made robust) Canary's chip pressed FIRST, before Work has a tab, its 2 pages opened there; then
#         Work's 8 pages for the M rows; then Private's 2 pages: Canary's tabs sit before every Work tab in the strip,
#         Private's after the M rows' -- whichever way DevTools places a tab (LOCAL.md 92: below the one before)
#   M1    "Move tab here" on Canary's chip: Canary's top (graded after a press of its chip). It must FAIL on the build
#         without patch 80 -- else the seed proved nothing and the run is VOID
#   M2-M4 the tab menu's "Move tab to workspace > Private": a tab, a 2-tab group, a split -- Private's top, "from above"
#   M5    a group to Unpin (no Today tab there): "none placed", the browser runs
#   T1    a Today tab onto Canary's chip: lit ("over"), "rail drop: 1", moved 1 "from below", Canary's top
#   T1h   held 2 s over Canary's chip, carried back into the list: lit then "over none", nothing moved
#   T1b   through a point held 3-4 DIP above the bar's top, then onto the chip (CHK-1's band): moved 1
#   T2    two selected tabs: moved 2, at Canary's top in their order;  T3  a favorite: nothing moved, not lit
#   T4    a group by its header: moved whole, at the top;  T5  a split: moved 2, one row at the top
#   T6    the Work chip (the workspace on screen): nothing, the tab LAST of Work's list (DRAG-1)
#   T7    Escape over a chip: nothing, Work's order as before;  T8a/b  on Archive, on +: nothing, no menu
#   P3    Example A (Work's FIRST root) onto the Work chip: no move, the saved roots unchanged
#   P1h   Example D held 1.5 s over a chip with the list longer than it shows: the list does not auto-scroll
#   P1    Example A, open, onto Canary's chip: the row and its page move, last in Canary;  P2  Smoke folder the same
#   R1-R4 a chip before / after its neighbour, to the first, to the last: "rail reorder: gap G -> offset K", "moved
#         workspace ... by K", the drawn order;  R5  Escape during a chip drag: nothing;  R6  dropped where it was
#   W1    a tab of a second window (--new-window) dragged through the main window's page onto its Canary chip: the
#         tear-off D3 keeps (3 windows), nothing moved, the main window still on Work;  W2  window 2's chip dropped on
#         the main window's bar: reordered, both bars drawn in the new order
#   C1    the collapsed column: a tab onto a chip (C1a), a chip reorder on the y axis (C1b); then expanded again
#   S1    quit: Preferences holds the order drawn; relaunched in ZEN MODE, the sidebar floating: drawn in that order
#   Z1    in that launch, the cursor kept at the window's left edge (the sidebar slid in): a tab onto Canary's chip
#         through a point held 3-4 DIP above the bar's top -- a short list (Z1a) and one longer than it shows (Z1b)
#   Z     0 crash markers in both logs (case-sensitive, DanglingPtr too), no "move: not placed" warning
# NEGATIVE CONTROL -- the same script on a build of patches 00-79 (the probe says WITHOUT 80 and 81): T1, T1b, T2, T4,
# T5, M1, M2-M4, P1, P2, P1h, R1-R4, R6, W2, C1a, C1b, Z1a, Z1b fail their own grade; T3, T6, T8a, T8b fail only their
# one-window grade (a tear-off); T1h, T7, R5, W1, P3, M5 and S1 pass on both (T1h's lit line and M5's "none placed"
# are graded only WITH their patch). M1 passing there makes the run VOID.
# A pass needs all 67 verdicts ($total below).
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
# -BinDir: a copy of an older build's runtime files, for the negative control (e.g. out\Dcheck-c4ctl, 00-79).
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$logs    = if ($Build -eq "Dcheck") { @("$ws\$Tag-dcheck-exercise.log", "$ws\$Tag-dcheck-exercise-zen.log") } else { @("$ws\$Tag-run.log", "$ws\$Tag-run-zen.log") }
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$private = "c9990cf0-c141-42fd-bb39-de33171ad078"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
$wsNames = @("Home", "Work", "Canary", "Private", "Unpin")
$guidOf  = @{ "Home" = "default"; "Work" = $work; "Canary" = $canary; "Private" = $private; "Unpin" = $unpin }
$nameOf  = @{ "default" = "Home"; $work = "Work"; $canary = "Canary"; $private = "Private"; $unpin = "Unpin" }
$mPages  = @("c4six", "c4m2", "c4m3a", "c4m3b", "c4m4a", "c4m4b", "c4m5a", "c4m5b")
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = 67
# The contract's lines (c4-progress.md, "Exact log lines"), graded case-sensitively.
$active    = "\[workspaces\] active workspace -> '([^']*)'"
$overNone  = "\[workspaces\] rail drop: over none"
$overAny   = "\[workspaces\] rail drop: over (none|'[^']*')"
$dropAny   = "\[workspaces\] rail drop: \d+ tab\(s\) -> "
$movedAny  = "\[workspaces\] moved \d+ tab\(s\) -> workspace "
$notPlaced = "\[workspaces\] move: not placed, index \d+ is inside a collection"
function Over([string]$g) { "\[workspaces\] rail drop: over '$g'" }
function DropN([string]$g) { "\[workspaces\] rail drop: (\d+) tab\(s\) -> '$g'" }
# Groups: 1 moved, 2 left their group, 3 units to the top, 4 from above, 5 from below, 6 "none placed", 7 splits left.
function MovedRe([string]$g) { "\[workspaces\] moved (\d+) tab\(s\) -> workspace '$g', (\d+) left their group(?:, (?:(\d+) unit\(s\) to the top \((\d+) from above, (\d+) from below\)|(none placed): no Today tab there))?(?:, (\d+) split\(s\) with a pinned page left in place)?" }
function Reordered([string]$g) { "\[workspaces\] rail reorder: '$g' gap (\d+) -> offset (-?\d+)" }
function WhereItWas([string]$g) { "\[workspaces\] rail reorder: '$g' dropped where it was" }
function MovedWs([string]$g) { "\[workspaces\] moved workspace '$g' by (-?\d+)" }
function PinsMoved([string]$id, [string]$g) { "pins: moved '$id' to workspace '$g', (\d+) open page\(s\) with it" }
function Retagged([string]$g) { "\[workspaces\] retagged (\d+) pinned page\(s\) -> workspace '$g'" }
function Drew([string]$g) { "pins: drew \d+ row\(s\) of '$g'" }
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:port = 0; $script:main = [IntPtr]::Zero
$script:w2 = [IntPtr]::Zero; $script:log = $logs[0]; $script:srv = $null; $script:zen = $false; $script:scale = 1.0
$script:m1Top = $false; $script:drawn = @()
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
# The `i`-th line (from 0) matching `re`, or the last: the whole match, then its groups, as strings (empty when none).
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Grp([string]$re) { $l = @(Lines $re); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function ActiveWs { $g = @(Grp $active); if ($g.Count) { $g[1] } else { "" } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }
# A move line (MovedRe's groups): N moved, K left their group, then `top` -- "U A B" (U units to the top, A from
# above, B from below), "none" (none placed), or "" (any ending: the build without patch 80 logs none).
function IsMove($m, [int]$n, [int]$k, [string]$top) {
    if (-not $m.Count -or $m[1] -ne "$n" -or $m[2] -ne "$k" -or $m[7]) { return $false }
    if ($top -eq "") { return $true }
    if ($top -eq "none") { return $m[6] -eq "none placed" }
    "$($m[3]) $($m[4]) $($m[5])" -eq $top
}
function Said($m) { if ($m.Count) { "'$($m[0] -replace '^\[workspaces\] ', '')'" } else { "no move line" } }

# ---- MSAA (msaa-press.ps1) -----------------------------------------------------------------------------------------
# Zen mode, the sidebar floating: its views are INVISIBLE to MSAA unless the cursor keeps it slid in (check-e16-auto) --
# so in that launch every read and press first parks the cursor at the window's left edge.
function Reveal {
    $cl = [E18Input]::Client($script:main)
    $null = [C4Input]::Park($script:main, $cl[0] + 2, $cl[1] + [int]($cl[3] / 2))
    Start-Sleep (1 * $slow)
}
function Msaa([IntPtr]$h, [object[]]$a) {
    if ($script:zen) { Reveal }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a
}
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
# Queries on one snapshot of Nodes. Named nodes are taken bottom-most: the bar's chip "Home", not a toolbar's button.
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function ChipIn($nodes, [string]$name) { NodeIn $nodes $name 0x2B }
function ArchiveIn($nodes) { NodeIn $nodes "Archive" 0x2B }
# By its name alone: the + opens a menu, and MSAA gives a menu button its own role (not 0x2B).
function PlusIn($nodes) { @($nodes | Where-Object { $_.shown -and $_.name -eq "New tab, workspace or search" } | Sort-Object t) | Select-Object -Last 1 }
# A Today tab by its title: in a group or a split MSAA adds " - <where>".
function TabIn($nodes, [string]$title) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq $title -or $_.name.StartsWith("$title - ")) }) | Select-Object -First 1 }
# The list's tabs as drawn, top first (a split's halves left to right); favorites (" - Pinned") sit above it.
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
# The bar's chips as drawn: by left in the row, by top in the collapsed column.
function Order($nodes, [switch]$Column) {
    $chips = @($wsNames | ForEach-Object { ChipIn $nodes $_ } | Where-Object { $_ })
    @($chips | Sort-Object { if ($Column) { $_.t } else { $_.l } } | ForEach-Object { $_.name })
}
# The main window draws Work's pinned header (a heading, 0x14: the chip "Work" is a push button).
function OnWork([IntPtr]$h) { [bool](NodeIn (Nodes $h) "Work" 0x14) }
# Node `x` drawn inside window `h`'s list: its middle inside the client area and above the bar -- a box scrolled out
# of view still reads as shown (CHK-2).
function InView([IntPtr]$h, $nodes, $x) {
    $bar = ArchiveIn $nodes
    if (-not $x -or -not $bar) { return $false }
    $cl = [E18Input]::Client($h)
    $y = $x.t + [int]($x.h / 2)
    $y -gt $cl[1] -and $y -lt $bar.t
}
# A point at fractions of node `n`'s box.
function At($n, [double]$fx = 0.5, [double]$fy = 0.5) { @(($n.l + [int]($n.w * $fx)), ($n.t + [int]($n.h * $fy))) }

# ---- windows and menus ---------------------------------------------------------------------------------------------
# A menu or a bubble: the browser's other visible windows that are not browser windows.
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
# Every browser window but the main one (and window 2 while W2 needs it) closed as its X does, waited for -- a tab torn
# off by one row is that row's failure only (CHK-3) -- then any menu or bubble left open closed with Escape.
function Recover {
    if (-not (Running)) { return }
    foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { if ($h -ne $script:main -and $h -ne $script:w2) { [E18Input]::CloseWindow($h) } }
    $want = if ($script:w2 -ne [IntPtr]::Zero) { 2 } else { 1 }
    $t0 = Get-Date
    while ((Running) -and @([E18Input]::Windows([uint32]$script:bpid)).Count -gt $want -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 500 }
    NoPopups
    # Back on Work when a row left the window elsewhere (a click where a drag was meant), so one slip stays one
    # row's failure; by the log's last switch, which the collapsed column draws no header for.
    if ((Running) -and (ActiveWs) -ne $work) { $null = Go "Work" $work }
}
# What the log and the windows held as a row began.
function Mark { [pscustomobject]@{ act = Count $active; wins = @([E18Input]::Windows([uint32]$script:bpid)).Count } }
# A row's guard, read once its drop settled: the browser still runs (else the run stops), no window was added, and no
# switch -- no new "active workspace ->" line since Mark and the main window still on Work (in the collapsed column,
# which may not draw the header: the last switch logged). Then the extra windows closed. True when no window was added.
function Still([string]$row, $b, [switch]$Collapsed) {
    if (-not (Running)) { Verdict "${row}: the browser is still running" $false; throw "the browser is gone after $row -- a crash? See $($script:log)" }
    $wins = @([E18Input]::Windows([uint32]$script:bpid)).Count
    $acts = (Count $active) - $b.act
    # By the log's last switch in the collapsed column (no header drawn) and in zen mode (the floating sidebar's
    # header is not read as 'Work' there: Z1a/Z1b, 10-19).
    $on = if ($Collapsed -or $script:zen) { (ActiveWs) -eq $work } else { OnWork $script:main }
    Verdict "${row}: no window added (windows $($b.wins) -> $wins), no switch (+$acts 'active workspace' line(s); the window on Work: $on)" ($wins -eq $b.wins -and $acts -eq 0 -and $on)
    Recover
    $wins -eq $b.wins
}
# One row: an error in it is its own FAIL and the next row runs -- unless the browser is gone.
function Row([string]$row, [scriptblock]$body) {
    # -Rows C1,T1: only those rows (and the setup) -- a quick look at one; the RESULT then counts fewer verdicts.
    if ($Rows.Count -and $row -ne "setup" -and $Rows -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    Recover
}
# Workspace `name` shown by its chip pressed through MSAA (Shift+Alt+N follows the list's order, which the R rows
# change): true once its pinned header is drawn.
function Go([string]$name, [string]$guid) {
    if (NodeIn (Nodes $script:main) $name 0x14) { return $true }
    $c = Count $active; $cd = Count (Drew $guid)
    $null = Press $script:main $name 0x2B
    $ok = (WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid
    $null = WaitLog (Drew $guid) ($cd + 1) 10
    Start-Sleep (1 * $slow)
    $ok
}
# The Today tabs workspace `name` draws, top first: its chip pressed, the list read, Work pressed again -- after a row's
# own grades, as each press logs a switch.
function TopOf([string]$name, [string]$guid) {
    $went = Go $name $guid
    $list = if ($went) { @(Today (Nodes $script:main)) } else { @() }
    $back = Go "Work" $work
    [pscustomobject]@{ tabs = $list; names = "$(Names $list)$(if (-not $went) { ' (not shown)' })$(if (-not $back) { ' (Work not shown again)' })" }
}
# The first `k` of `tabs` are all -like `like`.
function TopIs($tabs, [string]$like, [int]$k = 1) { $tabs.Count -ge $k -and @($tabs | Select-Object -First $k | Where-Object { $_.name -like $like }).Count -eq $k }
# A split's two halves (-like `like`) at the top of `tabs`: one row (the same top, 2 px), two lefts, nothing above.
function SplitOnTop($tabs, [string]$like) {
    $s = @($tabs | Where-Object { $_.name -like $like })
    $o = @($tabs | Where-Object { $_.name -notlike $like })
    $s.Count -eq 2 -and [Math]::Abs($s[0].t - $s[1].t) -le 2 -and $s[0].l -ne $s[1].l -and -not @($o | Where-Object { $_.t -le $s[0].t }).Count
}
# A guarded right-click on `node` of window `h`, then the shown nodes of the menu that opened (check-c35's).
function OpenMenu([IntPtr]$h, $node) {
    if (-not $node) { return [pscustomobject]@{ result = "nothing to right-click"; items = @() } }
    $c = [E18Input]::Click($h, $node.l + [int]($node.w / 3), $node.t + [int]($node.h / 2), $true)
    $items = @(); $t0 = Get-Date
    do {
        Start-Sleep -Milliseconds 500
        $items = @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } })
    } while (-not $items.Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    [pscustomobject]@{ result = $c; items = $items }
}
# The first shown node matching `re` in an open menu, pressed via MSAA -- or by a guarded click at its middle when its
# name did not survive MSAA's text round trip (check-c35's).
function OtherPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) {
                $r = Press $w $n.name $n.role
                if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
                return "'$($n.name)' $r"
            }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re'"
}
# Today tab `title`'s menu (a guarded right-click), then its items matching each of `res` pressed in turn (a submenu's
# after its parent's); the menu closed when one is missing. What happened.
function TabMenu([string]$title, [string[]]$res) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no Today tab '$title' drawn" }
    $r = [E18Input]::Click($script:main, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    foreach ($re in $res) {
        $p = OtherPress $re
        $r += "; $p"
        if ($p -like "nothing matching*") { NoPopups; break }
        Start-Sleep -Milliseconds (500 * $slow)
    }
    $r
}
function ClickTab([string]$title, [switch]$Ctrl) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no Today tab '$title' drawn" }
    $x = $n.l + [int]($n.w / 2); $y = $n.t + [int]($n.h / 2)
    if ($Ctrl) { [C4Input]::CtrlClick($script:main, $x, $y) } else { [E18Input]::Click($script:main, $x, $y, $false) }
}

# ---- the drags -----------------------------------------------------------------------------------------------------
# A guarded real drag through screen points `xy` (x, y pairs): pressed at the first in window `from`, on through the
# rest in window `to`, held `hold` ms at each point but the last; Escape first when asked; let go. What happened.
function DragPath([IntPtr]$from, [IntPtr]$to, [int[]]$xy, [int]$hold = 0, [switch]$Escape) {
    if ($script:zen) { Reveal }
    $h = [C4Input]::Hold($from, $to, $xy, $hold)
    if ($h -ne "held") { return $h }
    "held; $([C4Input]::Release([int[]]@(), $Escape.IsPresent, 600 * $slow))"
}
# Node `src` of snapshot `nodes` (pressed at `fx` of its width) dragged onto node `dst`'s middle in the main window,
# through `via` first: what happened, or why nothing was dragged.
function DragOnto($nodes, $src, $dst, [int[]]$via = @(), [int]$hold = 0, [double]$fx = 0.5, [switch]$Escape) {
    if (-not (InView $script:main $nodes $src)) { return "not dragged: the source is not drawn in the list ($(if ($src) { "@$($src.l),$($src.t)" } else { 'none' }))" }
    if (-not $dst) { return "not dragged: no target" }
    DragPath $script:main $script:main ([int[]]((At $src $fx) + $via + (At $dst))) $hold -Escape:$Escape
}
# A point 3-4 DIP above the bar's top over chip `chip` (4 DIP above the Archive button's box, inside the bar's 1 px
# edge): in zen mode the band CHK-1 found nobody claimed; in the default layout the list's last pixels.
function Band($nodes, $chip) { $bar = ArchiveIn $nodes; if (-not $bar -or -not $chip) { return @() }; @(($chip.l + [int]($chip.w / 2)), ($bar.t - [int][Math]::Round(4 * $script:scale))) }
# Z1: Today tab `title` dragged in zen mode, the sidebar floating, onto Canary's chip through the band above
# the bar -- no Escape and no click on the page in that launch: the cursor stays at the edge, the sidebar slid in.
function ZenDrop([string]$row, [string]$title, [string]$how, [switch]$Full) {
    $n = Nodes $script:main
    $src = TabIn $n $title; $dst = ChipIn $n "Canary"; $band = @(Band $n $dst)
    $tabs = @(Today $n)
    $out = @($tabs | Where-Object { -not (InView $script:main $n $_) }).Count
    $b = Mark; $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
    $r = if ($band.Count -eq 2) { DragOnto $n $src $dst $band (500 * $slow) } else { "not dragged: no bar" }
    $null = WaitLog (MovedRe $canary) ($cm + 1) 5
    Start-Sleep (1 * $slow)
    $null = Still $row $b
    $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
    Verdict "$row zen, the sidebar floating, $how, $($tabs.Count) Today tab(s), $out out of view$(if ($Full) { ' (want 1+)' }): '$title' through a point held 3-4 DIP above the bar ($($band -join ',')) onto Canary's chip ($r): 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m)" ($d.Count -and $d[1] -eq "1" -and (IsMove $m 1 0 "") -and (-not $Full -or $out -gt 0))
}
# Chip `drag` before (`after`: after) the chip `onto` -- a name, or <first>, <last>, <before> / <after> (its own
# neighbours) -- in order `cur`: the gap (the chips whose middle is before the pointer), D15's offset, the new order.
function Plan([string[]]$cur, [string]$drag, [string]$onto, [bool]$after) {
    $from = [array]::IndexOf($cur, $drag); $to = [array]::IndexOf($cur, $onto)
    if ($from -lt 0 -or $to -lt 0) { return [pscustomobject]@{ gap = -1; off = 0; order = $cur } }
    $gap = $to + [int]$after
    $off = $(if ($gap -gt $from) { $gap - 1 } else { $gap }) - $from
    $list = [System.Collections.Generic.List[string]]::new([string[]]$cur); $list.RemoveAt($from); $list.Insert($from + $off, $drag)
    [pscustomobject]@{ gap = $gap; off = $off; order = @($list) }
}
# Chip `drag` of window `from`'s bar (W2: another window's) dragged onto the left (`after`: right) quarter of chip
# `onto` on the main window's bar -- its top or bottom quarter in the collapsed column -- Escape first when asked.
# Graded: the reorder line with Plan's gap and offset ("dropped where it was" at offset 0; nothing after an Escape),
# the move line, and the order drawn (both bars for W2).
function Reorder([string]$row, [string]$drag, [string]$onto, [bool]$after, [IntPtr]$from = [IntPtr]::Zero, [switch]$Column, [switch]$Escape) {
    $to = $script:main
    if ($from -eq [IntPtr]::Zero) { $from = $to }
    $n = Nodes $to
    $nf = if ($from -eq $to) { $n } else { Nodes $from }
    $cur = @(Order $n -Column:$Column)
    $i = [array]::IndexOf($cur, $drag)
    $onto = switch ($onto) { "<first>" { $cur[0] } "<last>" { $cur[-1] } "<before>" { $cur[[Math]::Max(0, $i - 1)] } "<after>" { $cur[[Math]::Min($cur.Count - 1, $i + 1)] } default { $onto } }
    $p = Plan $cur $drag $onto $after
    $src = ChipIn $nf $drag; $dst = ChipIn $n $onto
    $g = $guidOf[$drag]
    $b = Mark; $cr = Count (Reordered $g); $cw = Count (WhereItWas $g); $cm = Count (MovedWs $g)
    $q = if ($after) { 0.75 } else { 0.25 }
    $r = if ($src -and $dst -and $p.gap -ge 0) {
        $end = if ($Column) { At $dst 0.5 $q } else { At $dst $q }
        DragPath $from $to ([int[]]((At $src) + $end)) -Escape:$Escape
    } else { "not dragged: chip '$drag' $([bool]$src), chip '$onto' $([bool]$dst), order $($cur -join ', ')" }
    if ($Escape -or $p.off -eq 0) { Start-Sleep (2 * $slow) } else { $null = WaitLog (MovedWs $g) ($cm + 1) 5 }
    Start-Sleep (1 * $slow)
    $null = Still $row $b -Collapsed:$Column
    $now = @(Order (Nodes $to) -Column:$Column)
    $there = if ($from -eq $to) { $now } else { @(Order (Nodes $from)) }
    $rl = @(Nth (Reordered $g) $cr); $ml = @(Nth (MovedWs $g) $cm); $wi = (Count (WhereItWas $g)) - $cw
    $said = "the reorder line $(if ($rl.Count) { "gap $($rl[1]) -> offset $($rl[2])" } else { 'none' }), 'where it was' +$wi, the move line $(if ($ml.Count) { "by $($ml[1])" } else { 'none' })"
    if ($Escape) {
        $want = "nothing"
        $ok = -not $rl.Count -and $wi -eq 0 -and -not $ml.Count -and ($now -join ',') -eq ($cur -join ',')
    } elseif ($p.off -eq 0) {
        $want = "'dropped where it was', no move"
        $ok = $wi -eq 1 -and -not $rl.Count -and -not $ml.Count -and ($now -join ',') -eq ($cur -join ',')
    } else {
        $want = "gap $($p.gap) -> offset $($p.off), by $($p.off), drawn $($p.order -join ', ')"
        $ok = $rl.Count -and $rl[1] -eq "$($p.gap)" -and $rl[2] -eq "$($p.off)" -and $ml.Count -and $ml[1] -eq "$($p.off)" -and ($now -join ',') -eq ($p.order -join ',') -and ($there -join ',') -eq ($p.order -join ',')
    }
    Verdict "$row '$drag' onto the $(if ($Column) { if ($after) { 'bottom' } else { 'top' } } elseif ($after) { 'right' } else { 'left' }) quarter of '$onto'$(if ($Escape) { ', Escape' }) ($r): $said; drawn $($now -join ', ')$(if ($from -ne $to) { "; window 2 draws $($there -join ', ')" }) (was $($cur -join ', '); want $want)" $ok
}

# ---- the pages and DevTools (check-c35's) --------------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array to the pipeline as ONE object.
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
function Tag([string]$u) { if ($u -match '/(c4\w+)\.html$') { $Matches[1] } else { "" } }
# Page `path` opened in front (/json/new), once loaded with title `title`: its target.
function NewTab([string]$path, [string]$title) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $path)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$path'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne $title -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
function TargetOf([string]$tag) { @(Targets | Where-Object { (Tag $_.url) -eq $tag }) | Select-Object -First 1 }
# A page brought in front (/json/activate, as a click on its tab): the list scrolls to it.
function Show($t) { if ($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {} }; Start-Sleep -Milliseconds (500 * $slow) }
# Filler pages (c4f01, ...) opened in Work until its Today list holds `extra` more tabs than fit between the list's
# first tab and the bar; -Top: the list wheeled back to its top after. What it did.
function Fill([int]$extra, [switch]$Top) {
    $n = Nodes $script:main; $tabs = @(Today $n); $bar = ArchiveIn $n
    if (-not $tabs.Count -or -not $bar) { return "nothing measured (Today tabs $($tabs.Count), the bar $([bool]$bar))" }
    # The spacing between the first and the last tab, not the tallest box: in zen mode one taller box made 36 tabs
    # read as more than fit (Z1b on the control, 10-19). A split row counts twice, so this errs towards more pages.
    $pitch = if ($tabs.Count -gt 1) { [Math]::Max(1, ($tabs[-1].t - $tabs[0].t) / ($tabs.Count - 1)) } else { [Math]::Max(1, $tabs[0].h) }
    $want = [Math]::Min(60, [Math]::Max(0, [int][Math]::Floor(($bar.t - $tabs[0].t) / $pitch) + $extra - $tabs.Count))
    for ($i = 1; $i -le $want; $i++) { $nm = "c4f{0:d2}" -f $i; $null = NewTab "$nm.html" "E18 $nm" }
    # Then, while fewer than `extra` tabs lie out of view, 5 more at a time (60 in all): the estimate fell short in zen
    # mode, where the floating sidebar holds about 40 rows (Z1b, 10-19).
    while ($want -lt 60) {
        $m = Nodes $script:main
        if (@(Today $m | Where-Object { -not (InView $script:main $m $_) }).Count -ge $extra) { break }
        foreach ($k in 1..5) { $want++; $nm = "c4f{0:d2}" -f $want; $null = NewTab "$nm.html" "E18 $nm" }
    }
    $w = ""
    if ($Top) { $w = ", the list wheeled to its top ($([E18Input]::Wheel($script:main, $tabs[0].l + [int]($tabs[0].w / 2), $bar.t - 2 * $pitch, [int[]](@(120) * 30), 30)))" }
    "$want filler page(s) opened$w"
}
function CloseFillers {
    foreach ($t in @(Targets | Where-Object { (Tag $_.url) -match '^c4f\d\d$' })) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/close/$($t.id)" } catch {} }
    Start-Sleep (2 * $slow)
}
# Workspace `guid`'s top-level pinned rows as saved (written 2.5 s after a change): id, children's ids.
function Roots([string]$guid) {
    Start-Sleep (4 * $slow)
    try { $d = Get-Content -Raw -Encoding UTF8 -LiteralPath "$prof\Default\Workspace Pins" | ConvertFrom-Json } catch { return @() }
    @($d.workspaces.$guid | Where-Object { $_ } | ForEach-Object { [pscustomobject]@{ id = $_.id; kids = (@($_.children | ForEach-Object { $_.id }) -join ",") } })
}
function Ids($roots) { @($roots | ForEach-Object { $_.id }) -join "," }

# ---- one start of the browser, and its quit (check-c35's) ----------------------------------------------------------
function Launch([string[]]$extra) {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check") + $extra
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
    $script:scale = [E18Input]::Dpi($script:main) / 96.0
    Say "browser $($script:bpid) $($extra -join ' '), DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log); session '$env:SESSIONNAME', screen $([E18Input]::Screen() -join 'x'), window $($script:box -join ',') dpi $([E18Input]::Dpi($script:main))"
}
function Quit {
    if (-not (Running)) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Running)
    $secs = [int]((Get-Date) - $t0).TotalSeconds; $t1 = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) -and ((Get-Date) - $t1).TotalSeconds -lt 10) { Start-Sleep 1 }
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' }) in $secs s$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
$probe = foreach ($s in @("unit(s) to the top", "rail drop: over")) {
    & python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -eq 0) { "WITH" } else { "WITHOUT" }
}
$with80 = $probe[0] -eq "WITH"; $with81 = $probe[1] -eq "WITH"
Say "build: $Build\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $($probe[0]) patch 80, $($probe[1]) patch 81"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
# What e18-lib's E18Input has not: a ctrl+click, a cursor left where it was sent, and a drag held between calls (read
# while held, P1h) with check-e15d3's jiggle and Escape before the release. A name of its own: two scripts in one
# process share the first one's type.
if (-not ("C4Input" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class C4Input {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr ctx);
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);

  static bool down = false;
  static POINT saved;
  static IntPtr onto = IntPtr.Zero;

  // Physical pixels, as MSAA gives the fork's boxes.
  static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); }
  static void Send(INPUT i) { SendInput(1, new INPUT[] { i }, Marshal.SizeOf(typeof(INPUT))); }
  static void Move(int x, int y) {
    int vx = GetSystemMetrics(76), vy = GetSystemMetrics(77), vw = GetSystemMetrics(78), vh = GetSystemMetrics(79);
    INPUT i = new INPUT(); i.type = 0;
    i.u.mi.dx = (int)(((long)(x - vx) * 65535) / (vw - 1));
    i.u.mi.dy = (int)(((long)(y - vy) * 65535) / (vh - 1));
    i.u.mi.flags = 0x0001 | 0x8000 | 0x4000;  // MOVE | ABSOLUTE | VIRTUALDESK
    Send(i);
  }
  static void Button(uint flags) { INPUT i = new INPUT(); i.type = 0; i.u.mi.flags = flags; Send(i); }
  static void Key(ushort vk, bool up) { INPUT i = new INPUT(); i.type = 1; i.u.ki.vk = vk; i.u.ki.flags = up ? 2u : 0u; Send(i); }
  // Null when input may be sent at (x, y): the user's desktop, `hwnd` the window there; else why not.
  static string Guard(IntPtr hwnd, int x, int y) {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);  // UOI_NAME
    CloseDesktop(d);
    if (name.ToString() != "Default") return "the input desktop is '" + name + "' (the screen is locked?)";
    POINT p; p.x = x; p.y = y;
    if (GetAncestor(WindowFromPoint(p), 2) != hwnd) return "not sent: another window is at " + x + "," + y;  // GA_ROOT
    return null;
  }
  static string MoveTo(int x, int y) {
    Move(x, y); Thread.Sleep(150);
    POINT p; GetCursorPos(out p);
    if (Math.Abs(p.x - x) > 2 || Math.Abs(p.y - y) > 2) return "not sent: the cursor went to " + p.x + "," + p.y + ", not " + x + "," + y;
    return null;
  }
  // e18-lib's drag steps: 30 of them, 25 ms apart.
  static void Steps(int x0, int y0, int x1, int y1) {
    for (int s = 1; s <= 30; s++) { Move(x0 + (x1 - x0) * s / 30, y0 + (y1 - y0) * s / 30); Thread.Sleep(25); }
  }

  public static string CtrlClick(IntPtr hwnd, int x, int y) {
    Aware();
    string e = Guard(hwnd, x, y); if (e != null) return e;
    POINT back; GetCursorPos(out back);
    try {
      e = MoveTo(x, y); if (e != null) return e;
      Key(0x11, false); Button(0x0002); Thread.Sleep(60); Button(0x0004); Key(0x11, true); Thread.Sleep(600);
    } finally { SetCursorPos(back.x, back.y); }
    return "ctrl-clicked";
  }
  // The cursor moved to (x, y), guarded, and LEFT there: zen mode's floating sidebar stays slid in while it is at
  // the window's left edge (check-e16-auto's E16Mouse.MoveTo).
  public static string Park(IntPtr hwnd, int x, int y) {
    Aware();
    return Guard(hwnd, x, y) ?? MoveTo(x, y) ?? "parked";
  }
  // Pressed at (xy[0], xy[1]), guarded against `from`; then through each further point in steps, guarded against
  // `to`, held `holdMs` at each but the last. The button stays DOWN until Release.
  public static string Hold(IntPtr from, IntPtr to, int[] xy, int holdMs) {
    Aware();
    if (down) return "not sent: a drag is already held";
    string e = Guard(from, xy[0], xy[1]);
    for (int i = 2; e == null && i + 1 < xy.Length; i += 2) e = Guard(to, xy[i], xy[i + 1]);
    if (e != null) return e;
    GetCursorPos(out saved);
    e = MoveTo(xy[0], xy[1]);
    if (e != null) { SetCursorPos(saved.x, saved.y); return e; }
    Button(0x0002); down = true; onto = to; Thread.Sleep(150);  // LEFTDOWN
    for (int i = 2; i + 1 < xy.Length; i += 2) {
      Steps(xy[i - 2], xy[i - 1], xy[i], xy[i + 1]);
      if (i + 3 < xy.Length) Thread.Sleep(holdMs);
    }
    Thread.Sleep(300);
    return "held";
  }
  // The held drag on through `xy` (a point refused by the guard ends it there), a 1-px jiggle so the last point
  // counts, `settleMs`, Escape when asked, then let go; the cursor put back where Hold found it.
  public static string Release(int[] xy, bool escape, int settleMs) {
    if (!down) return "nothing held";
    Aware();
    string e = null;
    try {
      POINT p; GetCursorPos(out p);
      for (int i = 0; e == null && i + 1 < xy.Length; i += 2) {
        e = Guard(onto, xy[i], xy[i + 1]);
        if (e == null) { Steps(p.x, p.y, xy[i], xy[i + 1]); p.x = xy[i]; p.y = xy[i + 1]; }
      }
      Move(p.x, p.y + 1); Thread.Sleep(200); Move(p.x, p.y); Thread.Sleep(settleMs);
      if (escape) { Key(0x1B, false); Key(0x1B, true); Thread.Sleep(400); }
    } finally {
      Button(0x0004); down = false; Thread.Sleep(300);  // LEFTUP
      SetCursorPos(saved.x, saved.y);
    }
    return e == null ? (escape ? "Escape, let go" : "let go") : e + ", let go where it was";
  }
}
"@
}
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $logs -EA SilentlyContinue
# 280 wide: the five 32 px chips fit between Archive and + with no scroll arrow -- at the smoke profile's 200 the bar
# shows 3 and a real-mouse drop lands on an arrow (CHK-2). The toolbar's own New Tab off: "New Tab" is the sidebar's.
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$names = @("c4c1", "c4c2", "c4p1", "c4p2") + $mPages + @("c4one", "c4two", "c4bnd", "c4three", "c4four", "c4fav", "c4g1", "c4g2", "c4s1", "c4s2",
         "c4five", "c4esc", "c4arc", "c4plus", "c4w1", "c4w2", "c4seven", "c4z1", "c4z2") + @(1..60 | ForEach-Object { "c4f{0:d2}" -f $_ })
$script:srv = ServePages $pages $names
if (-not $script:srv.ok) { Abort "the local pages were not served" }

# ---- the first start ----------------------------------------------------------------------------------------------
try {
    Launch @()

    Row "setup" {
        $n = Nodes $script:main
        $arrows = @($n | Where-Object { $_.shown -and $_.name -in @("Previous workspaces", "More workspaces") })
        $chips = @(Order $n)
        Verdict "setup: every chip drawn, no scroll arrow shown (the sidebar 280 wide): chips $($chips -join ', '), arrows shown $($arrows.Count)" ($chips.Count -eq 5 -and -not $arrows.Count)
        # Canary FIRST, before Work has any tab: whatever DevTools' placement, Canary's tabs then sit before every Work
        # tab in the strip, so a retag alone lands a Work tab at Canary's BOTTOM (CHK-4). The M rows' pages next, then
        # Private's: those sit after them, so the M rows to Private run the "from above" branch (F3).
        $s = "Canary $(Go 'Canary' $canary)"
        foreach ($nm in "c4c1", "c4c2") { $null = NewTab "$nm.html" "E18 $nm" }
        $can = @(Today (Nodes $script:main))
        $s += ", Work $(Go 'Work' $work)"
        foreach ($nm in $mPages) { $null = NewTab "$nm.html" "E18 $nm" }
        $wk = @(Today (Nodes $script:main))
        $s += ", Private $(Go 'Private' $private)"
        foreach ($nm in "c4p1", "c4p2") { $null = NewTab "$nm.html" "E18 $nm" }
        $pv = @(Today (Nodes $script:main))
        $s += ", Work again $(Go 'Work' $work)"
        $ok = (TabIn $can "E18 c4c1") -and (TabIn $can "E18 c4c2") -and (TabIn $pv "E18 c4p1") -and (TabIn $pv "E18 c4p2") -and
              @($mPages | Where-Object { TabIn $wk "E18 $_" }).Count -eq $mPages.Count -and (OnWork $script:main)
        Verdict "setup: seeded ($s): Canary $(Names $can); Work $(Names $wk); Private $(Names $pv)" $ok
    }

    # ---- M: the menus' moves land at the top too ----------------------------------------------------------------
    Row "M1" {
        $r = ClickTab "E18 c4six"
        $b = Mark; $cm = Count (MovedRe $canary)
        $menu = OpenMenu $script:main (ChipIn (Nodes $script:main) "Canary")
        $r += "; $($menu.result); $(OtherPress '^Move (tab|\d+ tabs) here$')"
        $null = WaitLog (MovedRe $canary) ($cm + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "M1" $b
        $m = @(Nth (MovedRe $canary) $cm)
        $top = TopOf "Canary" $canary
        $script:m1Top = TopIs $top.tabs "E18 c4six"
        Verdict "M1 'Move tab here' on Canary's chip ($r): $(Said $m) (want 1 moved, 1 unit to the top, from below); Canary's top: $($top.names) (want E18 c4six first)" ((IsMove $m 1 0 "1 0 1") -and $script:m1Top)
    }
    Row "M2" {
        $b = Mark; $cm = Count (MovedRe $private)
        $r = TabMenu "E18 c4m2" @('^Move tabs? to workspace', '^Private$')
        $null = WaitLog (MovedRe $private) ($cm + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "M2" $b
        $m = @(Nth (MovedRe $private) $cm)
        $top = TopOf "Private" $private
        Verdict "M2 a tab by the tab menu to Private ($r): $(Said $m) (want 1 moved, 1 unit to the top, from above); Private's top: $($top.names)" ((IsMove $m 1 0 "1 1 0") -and (TopIs $top.tabs "E18 c4m2"))
    }
    Row "M3" {
        $r = "$(ClickTab 'E18 c4m3a'); $(ClickTab 'E18 c4m3b' -Ctrl); $(TabMenu 'E18 c4m3a' @('^Add tabs? to (new )?group$', '^New group$'))"
        # The new group's name bubble, closed.
        Start-Sleep (2 * $slow); NoPopups
        $grouped = @(Today (Nodes $script:main) | Where-Object { $_.name -like "E18 c4m3[ab] - Part of*" }).Count
        $b = Mark; $cm = Count (MovedRe $private)
        $r += "; $(ClickTab 'E18 c4m3a'); $(ClickTab 'E18 c4m3b' -Ctrl); $(TabMenu 'E18 c4m3a' @('^Move tabs? to workspace', '^Private$'))"
        $null = WaitLog (MovedRe $private) ($cm + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "M3" $b
        $m = @(Nth (MovedRe $private) $cm)
        $top = TopOf "Private" $private
        Verdict "M3 a 2-tab group (grouped: $grouped of 2), both selected, by the tab menu to Private ($r): $(Said $m) (want 2 moved, 0 left, 1 unit, from above); Private's top: $($top.names)" ($grouped -eq 2 -and (IsMove $m 2 0 "1 1 0") -and (TopIs $top.tabs "E18 c4m3[ab]*" 2))
    }
    Row "M4" {
        # "New split view with current tab" on c4m4a, c4m4b in front: the two make one split.
        Show (TargetOf "c4m4b")
        $r = TabMenu "E18 c4m4a" @('^New split view with current tab')
        Start-Sleep (2 * $slow)
        $b = Mark; $cm = Count (MovedRe $private)
        $r += "; $(TabMenu 'E18 c4m4a' @('^Move tabs? to workspace', '^Private$'))"
        $null = WaitLog (MovedRe $private) ($cm + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "M4" $b
        $m = @(Nth (MovedRe $private) $cm)
        $top = TopOf "Private" $private
        Verdict "M4 a split (one half's menu) to Private ($r): $(Said $m) (want 2 moved, 1 unit, from above); Private's top: $($top.names) (want the two halves, one row)" ((IsMove $m 2 0 "1 1 0") -and (SplitOnTop $top.tabs "E18 c4m4[ab]*"))
    }
    Row "M5" {
        $r = "$(ClickTab 'E18 c4m5a'); $(ClickTab 'E18 c4m5b' -Ctrl); $(TabMenu 'E18 c4m5a' @('^Add tabs? to (new )?group$', '^New group$'))"
        Start-Sleep (2 * $slow); NoPopups
        $b = Mark; $cm = Count (MovedRe $unpin)
        $r += "; $(ClickTab 'E18 c4m5a'); $(ClickTab 'E18 c4m5b' -Ctrl); $(TabMenu 'E18 c4m5a' @('^Move tabs? to workspace', '^Unpin$'))"
        $null = WaitLog (MovedRe $unpin) ($cm + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "M5" $b
        $m = @(Nth (MovedRe $unpin) $cm)
        Verdict "M5 a 2-tab group to Unpin, which has no Today tab ($r): $(Said $m) (want 2 moved$(if ($with80) { ', none placed' } else { '; the ending not graded: WITHOUT patch 80' })), the browser runs: $(Running)" ((IsMove $m 2 0 $(if ($with80) { "none" } else { "" })) -and (Running))
    }

    # ---- T: Today tabs dropped on the bar ----------------------------------------------------------------------
    Row "T1" {
        $null = NewTab "c4one.html" "E18 c4one"
        $n = Nodes $script:main
        $b = Mark; $co = Count (Over $canary); $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
        $r = DragOnto $n (TabIn $n "E18 c4one") (ChipIn $n "Canary")
        $null = WaitLog (MovedRe $canary) ($cm + 1) 5
        Start-Sleep (1 * $slow)
        $null = Still "T1" $b
        $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
        $gone = -not (TabIn (Nodes $script:main) "E18 c4one")
        $top = TopOf "Canary" $canary
        Verdict "T1 a Today tab onto Canary's chip ($r): lit +$((Count (Over $canary)) - $co), 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m) (want 1, from below); gone from Work: $gone; Canary's top: $($top.names)" ((Count (Over $canary)) -gt $co -and $d.Count -and $d[1] -eq "1" -and (IsMove $m 1 0 "1 0 1") -and $gone -and (TopIs $top.tabs "E18 c4one"))
    }
    Row "T1h" {
        $null = NewTab "c4two.html" "E18 c4two"
        $n = Nodes $script:main; $src = TabIn $n "E18 c4two"; $dst = ChipIn $n "Canary"
        $b = Mark; $co = Count (Over $canary); $cn = Count $overNone; $cd = Count $dropAny; $cm = Count $movedAny
        $r = "not dragged: the tab drawn in the list $(InView $script:main $n $src), the chip $([bool]$dst)"
        if ((InView $script:main $n $src) -and $dst) {
            $start = At $src
            $r = [C4Input]::Hold($script:main, $script:main, [int[]]($start + (At $dst)), 0)
            if ($r -eq "held") { Start-Sleep -Milliseconds (2000 * $slow); $r = "held 2 s over the chip, carried back; $([C4Input]::Release([int[]]$start, $false, 600 * $slow))" }
        }
        Start-Sleep (2 * $slow)
        $null = Still "T1h" $b
        $last = @(Grp $overAny)
        $lit = (Count (Over $canary)) -gt $co -and (Count $overNone) -gt $cn -and $last.Count -and $last[1] -eq "none"
        $kept = [bool](TabIn (Nodes $script:main) "E18 c4two")
        Verdict "T1h held over Canary's chip, then back in the list ($r): lit +$((Count (Over $canary)) - $co), 'over none' +$((Count $overNone) - $cn)$(if (-not $with81) { ' (not graded: WITHOUT patch 81)' }); drops +$((Count $dropAny) - $cd), moves +$((Count $movedAny) - $cm); still a Work tab: $kept" ((-not $with81 -or $lit) -and (Count $dropAny) -eq $cd -and (Count $movedAny) -eq $cm -and $kept)
    }
    Row "T1b" {
        $null = NewTab "c4bnd.html" "E18 c4bnd"
        $n = Nodes $script:main; $dst = ChipIn $n "Canary"; $band = @(Band $n $dst)
        $b = Mark; $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
        $r = if ($band.Count -eq 2) { DragOnto $n (TabIn $n "E18 c4bnd") $dst $band (500 * $slow) } else { "not dragged: no bar" }
        $null = WaitLog (MovedRe $canary) ($cm + 1) 5
        Start-Sleep (1 * $slow)
        $null = Still "T1b" $b
        $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
        Verdict "T1b through a point held 3-4 DIP above the bar ($($band -join ',')), then onto Canary's chip ($r): 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m)" ($d.Count -and $d[1] -eq "1" -and (IsMove $m 1 0 "1 0 1"))
    }
    Row "T2" {
        $null = NewTab "c4three.html" "E18 c4three"; $null = NewTab "c4four.html" "E18 c4four"
        $sel = "$(ClickTab 'E18 c4three'); $(ClickTab 'E18 c4four' -Ctrl)"
        $n = Nodes $script:main
        $order = @(Today $n | Where-Object { $_.name -in @("E18 c4three", "E18 c4four") } | ForEach-Object { $_.name })
        $b = Mark; $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
        $r = DragOnto $n (TabIn $n "E18 c4three") (ChipIn $n "Canary")
        $null = WaitLog (MovedRe $canary) ($cm + 1) 5
        Start-Sleep (1 * $slow)
        $null = Still "T2" $b
        $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
        $top = TopOf "Canary" $canary
        $first = @($top.tabs | Select-Object -First 2 | ForEach-Object { $_.name })
        Verdict "T2 two selected ($sel; Work's order $($order -join ', ')) onto Canary's chip ($r): 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m) (want 2, 2 units from below); Canary's top: $($top.names)" ($order.Count -eq 2 -and $d.Count -and $d[1] -eq "2" -and (IsMove $m 2 0 "2 0 2") -and ($first -join '|') -eq ($order -join '|'))
    }
    Row "T3" {
        $null = NewTab "c4fav.html" "E18 c4fav"
        $pin = TabMenu "E18 c4fav" @('^Add to Favorites')
        Start-Sleep (1 * $slow)
        $n = Nodes $script:main
        $b = Mark; $co = Count (Over $canary); $cd = Count $dropAny; $cm = Count $movedAny
        $r = DragOnto $n (NodeIn $n "E18 c4fav - Pinned" 0x25) (ChipIn $n "Canary")
        Start-Sleep (2 * $slow)
        $one = Still "T3" $b
        # Torn off (the build without 81), the favorite is in the closed window: only the log can be read.
        $kept = if ($one) { [bool](NodeIn (Nodes $script:main) "E18 c4fav - Pinned" 0x25) } else { $true }
        Verdict "T3 a favorite ($pin) onto Canary's chip ($r): lit +$((Count (Over $canary)) - $co), drops +$((Count $dropAny) - $cd), moves +$((Count $movedAny) - $cm); still a favorite here: $kept" ((Count (Over $canary)) -eq $co -and (Count $dropAny) -eq $cd -and (Count $movedAny) -eq $cm -and $kept)
    }
    Row "T4" {
        $null = NewTab "c4g1.html" "E18 c4g1"; $null = NewTab "c4g2.html" "E18 c4g2"
        $r = "$(ClickTab 'E18 c4g1'); $(ClickTab 'E18 c4g2' -Ctrl); $(TabMenu 'E18 c4g1' @('^Add tabs? to (new )?group$', '^New group$'))"
        Start-Sleep (2 * $slow); NoPopups
        $n = Nodes $script:main
        # The vertical strip names an unnamed group's header "unnamed group - 2 tabs, ... <titles> - Expanded".
        $hdr = @($n | Where-Object { $_.shown -and $_.name -match '^ ?unnamed group - .*E18 c4g' }) | Select-Object -First 1
        $b = Mark; $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
        $r += "; $(DragOnto $n $hdr (ChipIn $n 'Canary'))"
        $null = WaitLog (MovedRe $canary) ($cm + 1) 5
        Start-Sleep (1 * $slow)
        $null = Still "T4" $b
        $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
        $top = TopOf "Canary" $canary
        Verdict "T4 a group by its header ('$(if ($hdr) { $hdr.name } else { 'none drawn' })') onto Canary's chip ($r): 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m) (want 2 moved whole, 1 unit from below); Canary's top: $($top.names)" ($d.Count -and $d[1] -eq "2" -and (IsMove $m 2 0 "1 0 1") -and (TopIs $top.tabs "E18 c4g[12]*" 2))
    }
    Row "T5" {
        $null = NewTab "c4s1.html" "E18 c4s1"; $null = NewTab "c4s2.html" "E18 c4s2"
        $r = TabMenu "E18 c4s1" @('^New split view with current tab')
        Start-Sleep (2 * $slow)
        $n = Nodes $script:main
        $b = Mark; $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
        $r += "; $(DragOnto $n (TabIn $n 'E18 c4s1') (ChipIn $n 'Canary'))"
        $null = WaitLog (MovedRe $canary) ($cm + 1) 5
        Start-Sleep (1 * $slow)
        $null = Still "T5" $b
        $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
        $top = TopOf "Canary" $canary
        Verdict "T5 a split by one half onto Canary's chip ($r): 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m) (want 2, 1 unit from below); Canary's top: $($top.names) (want the two halves, one row)" ($d.Count -and (IsMove $m 2 0 "1 0 1") -and (SplitOnTop $top.tabs "E18 c4s[12]*"))
    }
    Row "T6" {
        $null = NewTab "c4five.html" "E18 c4five"
        $n = Nodes $script:main
        $b = Mark; $co = Count (Over $work); $cd = Count $dropAny; $cm = Count $movedAny
        $r = DragOnto $n (TabIn $n "E18 c4five") (ChipIn $n "Work")
        Start-Sleep (2 * $slow)
        $one = Still "T6" $b
        # A claimed drop that is not droppable ends where the pass over the list left the tab: its end (DRAG-1). Torn
        # off (without 81), the tab is in the closed window.
        $list = @(Today (Nodes $script:main))
        $last = if ($one) { $list.Count -and $list[-1].name -eq "E18 c4five" } else { $true }
        Verdict "T6 a Today tab onto the Work chip, the workspace on screen ($r): lit +$((Count (Over $work)) - $co), drops +$((Count $dropAny) - $cd), moves +$((Count $movedAny) - $cm); Work's list $(Names $list) (want E18 c4five last)" ((Count (Over $work)) -eq $co -and (Count $dropAny) -eq $cd -and (Count $movedAny) -eq $cm -and $last)
    }
    Row "T7" {
        $null = NewTab "c4esc.html" "E18 c4esc"
        $n = Nodes $script:main; $before = Names (Today $n)
        $b = Mark; $cd = Count $dropAny; $cm = Count $movedAny
        $r = DragOnto $n (TabIn $n "E18 c4esc") (ChipIn $n "Canary") -Escape
        Start-Sleep (2 * $slow)
        $one = Still "T7" $b
        $after = Names (Today (Nodes $script:main))
        Verdict "T7 Escape over Canary's chip ($r): drops +$((Count $dropAny) - $cd), moves +$((Count $movedAny) - $cm); Work's list $after (before: $before)" ((Count $dropAny) -eq $cd -and (Count $movedAny) -eq $cm -and $one -and $after -eq $before)
    }
    foreach ($t8 in @(@("T8a", "c4arc", "Archive", "\[workspaces\] rail: archive"), @("T8b", "c4plus", "+", "\[workspaces\] rail \+ menu opened"))) {
        Row $t8[0] {
            $null = NewTab "$($t8[1]).html" "E18 $($t8[1])"
            $n = Nodes $script:main
            $dst = if ($t8[2] -eq "Archive") { ArchiveIn $n } else { PlusIn $n }
            $b = Mark; $cd = Count $dropAny; $cm = Count $movedAny; $cp = Count $t8[3]
            $r = DragOnto $n (TabIn $n "E18 $($t8[1])") $dst
            Start-Sleep (2 * $slow)
            $menus = @(Popups).Count
            $null = Still $t8[0] $b
            Verdict "$($t8[0]) a Today tab onto $($t8[2]) ($r): drops +$((Count $dropAny) - $cd), moves +$((Count $movedAny) - $cm), $($t8[2]) pressed +$((Count $t8[3]) - $cp), menus or bubbles open: $menus" ((Count $dropAny) -eq $cd -and (Count $movedAny) -eq $cm -and (Count $t8[3]) -eq $cp -and $menus -eq 0)
        }
    }

    # ---- P: pinned rows dropped on the bar ---------------------------------------------------------------------
    Row "P3" {
        $n = Nodes $script:main
        $b = Mark; $co = Count (Over $work); $cp = Count "pins: moved 'a1'"
        $r = DragOnto $n (NodeIn $n "Example A" 0x24) (ChipIn $n "Work") -fx 0.33
        Start-Sleep (2 * $slow)
        $null = Still "P3" $b
        $roots = Ids (Roots $work)
        Verdict "P3 'Example A', Work's first row, onto the Work chip ($r): lit +$((Count (Over $work)) - $co), 'pins: moved a1' +$((Count "pins: moved 'a1'") - $cp); Work's saved rows $roots (want a1,f1,g1,d1)" ((Count (Over $work)) -eq $co -and (Count "pins: moved 'a1'") -eq $cp -and $roots -eq "a1,f1,g1,d1")
    }
    Row "P1h" {
        try {
            # The list longer than it shows, at its top: a list that auto-scrolls under a row held over a chip moves.
            $f = Fill 3 -Top
            Start-Sleep (1 * $slow)
            $n = Nodes $script:main; $dRow = NodeIn $n "Example D" 0x24; $dst = ChipIn $n "Canary"; $first = @(Today $n)[0]
            $b = Mark; $co = Count (Over $canary); $cp = Count "pins: moved 'd1'"
            $r = "not dragged: the row drawn $(InView $script:main $n $dRow), the chip $([bool]$dst), a Today tab $([bool]$first)"
            $t1 = $null; $t2 = $null
            if ((InView $script:main $n $dRow) -and $dst -and $first) {
                $start = At $dRow 0.33
                $r = [C4Input]::Hold($script:main, $script:main, [int[]]($start + (At $dst)), 0)
                if ($r -eq "held") {
                    try {
                        $x = TabIn (Nodes $script:main) $first.name; if ($x) { $t1 = $x.t }
                        Start-Sleep -Milliseconds (1500 * $slow)
                        $x = TabIn (Nodes $script:main) $first.name; if ($x) { $t2 = $x.t }
                    } finally { $r = "held over the chip, carried back; $([C4Input]::Release([int[]]$start, $false, 600 * $slow))" }
                }
            }
            Start-Sleep (2 * $slow)
            $null = Still "P1h" $b
            # On the way, the list's bottom edge may scroll it a step; held on the chip, never again.
            $ok = $null -ne $t1 -and $null -ne $t2 -and [Math]::Abs($t1 - $first.t) -lt $first.h -and [Math]::Abs($t2 - $t1) -le 2
            Verdict "P1h 'Example D' held 1.5 s over Canary's chip ($f; $r): '$(if ($first) { $first.name })' top $(if ($first) { $first.t }) before, $t1 on the chip, $t2 1.5 s later (want no scroll); lit +$((Count (Over $canary)) - $co)$(if (-not $with81) { ' (not graded: WITHOUT patch 81)' }), 'pins: moved d1' +$((Count "pins: moved 'd1'") - $cp)" ($ok -and (-not $with81 -or (Count (Over $canary)) -gt $co) -and (Count "pins: moved 'd1'") -eq $cp)
        } finally { CloseFillers }
    }
    Row "P1" {
        $c = Count "pins: opened item 'a1'"
        $pr = Press $script:main "Example A" 0x24
        $opened = WaitLog "pins: opened item 'a1'" ($c + 1) 10
        Start-Sleep (2 * $slow)
        $n = Nodes $script:main
        $b = Mark; $co = Count (Over $canary); $cp = Count (PinsMoved "a1" $canary); $ct = Count (Retagged $canary)
        $r = DragOnto $n (NodeIn $n "Example A" 0x24) (ChipIn $n "Canary") -fx 0.33
        $null = WaitLog (PinsMoved "a1" $canary) ($cp + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "P1" $b
        $pm = @(Nth (PinsMoved "a1" $canary) $cp); $rt = @(Nth (Retagged $canary) $ct)
        $wk = Ids (Roots $work); $cn = @(Roots $canary)
        Verdict "P1 'Example A', open ($pr; opened: $opened), onto Canary's chip ($r): lit +$((Count (Over $canary)) - $co), moved with $(if ($pm.Count) { $pm[1] } else { '-' }) open page(s), retagged $(if ($rt.Count) { $rt[1] } else { '-' }); saved: Work $wk, Canary $(Ids $cn) (want a1 gone from Work, last in Canary)" ($opened -and (Count (Over $canary)) -gt $co -and $pm.Count -and $pm[1] -eq "1" -and $rt.Count -and $rt[1] -eq "1" -and ",$wk," -notlike "*,a1,*" -and $cn.Count -and $cn[-1].id -eq "a1")
    }
    Row "P2" {
        $n = Nodes $script:main
        $b = Mark; $cp = Count (PinsMoved "f1" $canary)
        $r = DragOnto $n (NodeIn $n "Smoke folder" 0x24) (ChipIn $n "Canary") -fx 0.33
        $null = WaitLog (PinsMoved "f1" $canary) ($cp + 1) 10
        Start-Sleep (1 * $slow)
        $null = Still "P2" $b
        $pm = @(Nth (PinsMoved "f1" $canary) $cp)
        $wk = Ids (Roots $work); $f1 = @(Roots $canary | Where-Object { $_.id -eq "f1" }) | Select-Object -First 1
        Verdict "P2 'Smoke folder' onto Canary's chip ($r): moved with $(if ($pm.Count) { $pm[1] } else { '-' }) open page(s); saved: Work $wk, Canary's f1 holds $(if ($f1) { $f1.kids } else { 'nothing: no f1' }) (want b1,c1)" ($pm.Count -and $pm[1] -eq "0" -and ",$wk," -notlike "*,f1,*" -and $f1 -and $f1.kids -eq "b1,c1")
    }

    # ---- R: chips reordered ------------------------------------------------------------------------------------
    Row "R1" { Reorder "R1" "Canary" "<before>" $false }
    Row "R2" { Reorder "R2" "Canary" "<after>" $true }
    Row "R3" { Reorder "R3" "Unpin" "<first>" $false }
    Row "R4" { Reorder "R4" "Unpin" "<last>" $true }
    Row "R5" { Reorder "R5" "Private" "Home" $false -Escape }
    Row "R6" { Reorder "R6" "Canary" "<before>" $true }

    # ---- W: across windows -------------------------------------------------------------------------------------
    Row "W1" {
        $cd = Count $dropAny; $cm = Count $movedAny
        Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "c4w1.html"), (Url "c4w2.html")) | Out-Null
        $t0 = Get-Date
        do {
            Start-Sleep 1
            $o = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main })
            if ($o.Count) { $script:w2 = $o[0] }
        } while ($script:w2 -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow)
        if ($script:w2 -eq [IntPtr]::Zero) { Verdict "W1 a second window opened" $false; return }
        $half = [int]($scr[0] / 2)
        [E18Input]::Place($script:main, 0, 0, $half, $scr[1] - 80); [E18Input]::Place($script:w2, $half, 0, $half, $scr[1] - 80)
        $opened = WaitLog "a window opens on workspace '$work'" 1 15
        # Polled: the forwarded launch is a second process of the profile until it exits, which msaa-press refuses.
        $t0 = Get-Date
        do { Start-Sleep 1; $n2 = Nodes $script:w2; $src = TabIn $n2 "E18 c4w1" } while (-not $src -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow)
        $n1 = Nodes $script:main; $dst = ChipIn $n1 "Canary"; $cl = [E18Input]::Client($script:main)
        # Through the main window's PAGE at the bar's height, then straight onto the chip: never over its list, where
        # Chromium's own merge would attach the tab first.
        $r = if ($src -and $dst -and (InView $script:w2 $n2 $src)) {
            DragPath $script:w2 $script:main ([int[]]((At $src) + @(($cl[0] + [int]($cl[2] * 0.6)), ($dst.t + [int]($dst.h / 2))) + (At $dst))) (300 * $slow)
        } else { "not dragged: window 2's tab $([bool]$src), the chip $([bool]$dst)" }
        Start-Sleep (2 * $slow)
        $wins = @([E18Input]::Windows([uint32]$script:bpid)).Count
        $on = OnWork $script:main
        Verdict "W1 window 2 (on Work: $opened)'s tab dragged through the main window's page onto its Canary chip ($r): windows $wins (want 3: the tear-off kept), drops +$((Count $dropAny) - $cd), moves +$((Count $movedAny) - $cm), the main window on Work: $on" ((Running) -and $wins -eq 3 -and (Count $dropAny) -eq $cd -and (Count $movedAny) -eq $cm -and $on)
    }
    Row "W2" {
        try {
            if ($script:w2 -eq [IntPtr]::Zero) { Verdict "W2: no second window" $false; Verdict "W2 window 2's chip onto the main window's bar: no second window" $false; return }
            Reorder "W2" "Private" "<first>" $false -From $script:w2
        } finally {
            if ($script:w2 -ne [IntPtr]::Zero) {
                [E18Input]::CloseWindow($script:w2)
                $t0 = Get-Date
                while ((Running) -and @([E18Input]::Windows([uint32]$script:bpid)).Count -gt 1 -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 500 }
                $script:w2 = [IntPtr]::Zero
            }
            [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
            Start-Sleep (1 * $slow)
        }
    }

    # ---- C: the collapsed column -------------------------------------------------------------------------------
    Row "C1" {
        $null = NewTab "c4seven.html" "E18 c4seven"
        $pc = Press $script:main "Collapse tabs" 0x2B
        Start-Sleep (2 * $slow)
        try {
            $n = Nodes $script:main
            $col = [bool](NodeIn $n "Expand tabs" 0x2B)
            # Another tab in front first: in the icon column the tab in front shows its close button over its icon,
            # and a press there is the button's, not a drag (C1a failed on it three times, 10-19).
            $other = @(Today $n | Where-Object { -not $_.name.StartsWith("E18 c4seven") }) | Select-Object -First 1
            if ($other) { $null = [E18Input]::Click($script:main, $other.l + [int]($other.w / 2), $other.t + [int]($other.h / 2), $false); Start-Sleep (1 * $slow); $n = Nodes $script:main }
            $b = Mark; $cd = Count (DropN $canary); $cm = Count (MovedRe $canary)
            $r = DragOnto $n (TabIn $n "E18 c4seven") (ChipIn $n "Canary")
            $null = WaitLog (MovedRe $canary) ($cm + 1) 5
            Start-Sleep (1 * $slow)
            $null = Still "C1a" $b -Collapsed
            $d = @(Nth (DropN $canary) $cd); $m = @(Nth (MovedRe $canary) $cm)
            Verdict "C1a collapsed ($pc; drawn as a column: $col): a Today tab onto Canary's chip ($r): 'rail drop: $(if ($d.Count) { $d[1] } else { '-' }) tab(s)', $(Said $m)" ($col -and $d.Count -and $d[1] -eq "1" -and (IsMove $m 1 0 "1 0 1"))
            Reorder "C1b" "Unpin" "Work" $false -Column
        } finally {
            # Expanded again before the quit: the collapse is saved (vertical_tabs.collapsed_state).
            $null = Press $script:main "Expand tabs" 0x2B
            Start-Sleep (2 * $slow)
        }
    }
    $script:drawn = @(Order (Nodes $script:main))
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q1 = Quit
}

# ---- the second start: zen mode, the sidebar floating (the owner's daily layout) ---------------------------------
$pref = @(try { (& python -I "$here\prefs.py" "$prof\Default\Preferences" "helium.workspaces.list" | ConvertFrom-Json).items | ForEach-Object { $nameOf[$_.guid] } } catch { })
& python -I "$here\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false"
$zenSeeded = $LASTEXITCODE -eq 0
$script:log = $logs[1]
try {
    if (-not $zenSeeded) { throw "zen mode was not seeded" }
    Launch @()
    $script:zen = $true

    Row "S1" {
        $after = @(Order (Nodes $script:main))
        Verdict "S1 the quit ($q1): Preferences holds $($pref -join ', '); the bar drew $($script:drawn -join ', ') before it; after the restart in zen mode $($after -join ', ')" ($pref.Count -eq 5 -and ($pref -join ',') -eq ($script:drawn -join ',') -and ($after -join ',') -eq ($pref -join ','))
    }
    Row "Z1a" {
        $go = Go "Work" $work
        $null = NewTab "c4z1.html" "E18 c4z1"
        ZenDrop "Z1a" "E18 c4z1" "a short list (Work shown: $go)"
    }
    Row "Z1b" {
        $null = NewTab "c4z2.html" "E18 c4z2"
        $f = Fill 3
        Show (TargetOf "c4z2")
        ZenDrop "Z1b" "E18 c4z2" "a list longer than it shows ($f)" -Full
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q2 = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
# Case-sensitive, as LOCAL.md grades: a Dcheck exit can dump the histogram
# "Commerce.PriceTracking.DanglingUserSubscriptionCountAtStartup", no crash (LOCAL.md 86); the dangling-raw_ptr
# detector's own reports say DanglingPtr.
$markers = 0; $warned = 0
foreach ($l in $logs) {
    if (Test-Path -LiteralPath $l) {
        $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count
        $warned += @(Select-String -LiteralPath $l -CaseSensitive -Pattern $notPlaced).Count
    }
}
Verdict "Z crash markers in $($logs -join ', ') (the last quit: $q2): $markers; 'move: not placed' warnings: $warned" ($markers -eq 0 -and $warned -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
# The negative control: without patch 80 a retag alone must leave M1's tab at Canary's BOTTOM. At the top, the seed
# put Work's tabs before Canary's and no "top" grade of this run decides anything.
if (-not $with80 -and $script:m1Top) { $verdict = "VOID"; Say "VOID: M1's tab is at Canary's top on a build WITHOUT patch 80 -- the seed did not put Canary's tabs first (CHK-4)" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
