param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c29", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [ValidateSet(1, 2)][int]$Part = 1)
# C29 stage 1 (patch 83): several pinned pages selected at once -- Ctrl+click toggles a row, Shift+click selects the rows
# from the last click, Esc / a plain click / another workspace lets go; a right-click on a selection is the menu of the
# whole selection (Close, Unpin, Move to workspace, Delete); -Part 2 (stage 2): a drag of a selected row is the whole
# selection's -- see the end of this header. On a throwaway copy of the smoke profile (Sessions emptied):
# every workspace has the rows  Example A, Smoke folder (open: Wikipedia, a github page), Closed folder (Hidden),
# Example D  -- six rows drawn. The clicks are REAL mouse input (SendInput) with the modifier held, each point guarded
# (the user's desktop, the fork's window under it): it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE.
# No network: every host resolves to nothing. Graded by the log and the saved pins file.
#   pwsh -NoProfile -File local\check-c29.ps1 [-Build Dcheck] [-IdleMinutes 0]
#   P0  the window opened on Home with its 6 rows
#   S1  Ctrl+click Example A: "selected 1 row(s)", the page NOT opened
#   S2  Ctrl+click Example D: 2;  S3  Ctrl+click Example D again: 1 (a toggle), then again: 2
#   S4  Shift+click Closed folder (the anchor is Example D): the range alone, 2 (A is let go)
#   S5  Shift+click Example A: the range A..D is six rows, but Wikipedia and the github page sit inside the selected
#       Smoke folder: 4 (A, Smoke folder, Closed folder, D)
#   S6  right-click Example D: "menu for 4 selected row(s)"; the menu has Unpin, Move to workspace, Delete and NOT Rename
#   S7  Escape: "selection cleared"
#   S8  Ctrl+click A and D, then a plain click on A: the selection is let go AND the page opens
#   S8b (A's page is open from S8) Ctrl+click A, D: the menu has Close; pressed: "closed the open pages of 2 selected
#       row(s)" and A's page is closed; Escape lets the selection go
#   S9  Ctrl+click A, D: the menu's Unpin: "unpinned 2 selected row(s)"; Home's saved rows lose a0 and d0
#   S10 Ctrl+click the two folders: Move to workspace > Private: "moved 2 selected row(s)", saved: last in Private, in
#       drawn order (f0 then g0), gone from Home
#   S11 on Work: Ctrl+click A and D, the menu's Delete: the confirm is asked ("confirm asked: delete 2 selected"), its
#       Delete pressed: "deleted 2 selected row(s)", Work's saved rows f1,g1
#   S12 (on Work, rows f1 Smoke folder, g1 Closed folder) Ctrl+click Closed folder (selected, focused), then Shift+Right:
#       the arrow key OPENS the folder (its page "Hidden" is drawn) and selects nothing more -- the review's fix; a
#       plain press of a row must also not crash (a click read event.AsKeyEvent(), which CHECKs, 2026-10-21)
#   Z   0 crash markers (case-sensitive, DanglingPtr too)
# -Part 2 (patch 83, stage 2; Tag c29b), on Home's rows a0, f0[b0 Wikipedia, c0], g0[h0 Hidden], d0 -- the drags are
# REAL mouse (E18Input.Drag), each end guarded; a group is Ctrl+clicked first:
#   D1  Example A + Example D dragged into Closed folder: Home f0,g0, g0 holds a0,d0,h0 (the group's order, first inside)
#   D2  the same two (the folder open) dragged before Smoke folder: Home a0,d0,f0,g0; g0 holds h0
#   D3  Wikipedia + Hidden dragged onto a Today tab: both unpinned (+2 "unpinned item"), f0 holds c0, g0 none
#   D4  Closed folder (NOT selected) dragged before Example A with A + D selected: only it moves (g0,a0,d0,f0), the
#       selection is let go, no "dragging N selected" line
#   D5  A + D selected, A dragged onto D (a member of the group): nowhere to drop, nothing moves
#   D6  (A + D still selected) A dragged onto the Canary chip on the bar, which lights ("rail drop: over"): both
#       move there, last, in order -- Canary a2,f2,g2,d2,a0,d0, Home g0,f0. The sidebar is seeded 280 wide for this part
#       so the five chips are drawn
. "$PSScriptRoot\e18-lib.ps1"
if ($Part -eq 2 -and $Tag -eq "c29") { $Tag = "c29b" }
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })$(if ($BinDir) { '-ctl' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$log     = "$ws\$Tag$suffix-run.log"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = if ($Part -eq 2) { 8 } else { 15 }
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$private = "c9990cf0-c141-42fd-bb39-de33171ad078"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 10) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A saved workspace's top-level rows, as ids: the pins file is written 2.5 s after a change.
function Roots([string]$guid) {
    Start-Sleep (4 * $slow)
    try { $d = Get-Content -Raw -Encoding UTF8 -LiteralPath "$prof\Default\Workspace Pins" | ConvertFrom-Json } catch { return "" }
    @($d.workspaces.$guid | Where-Object { $_ } | ForEach-Object { $_.id }) -join ","
}
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
# A window that takes no input (WS_EX_TRANSPARENT, Chromium's accept_events = false) is no menu -- the link-address
# bubble shown while the pointer rests on a link is one: an Escape "for" it reached the focused row and let go of the
# selection before S7 and S8b asked for that (LOCAL.md 131).
Add-Type -Namespace C29 -Name Ex -MemberDefinition '[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);'
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups | Where-Object { ([C29.Ex]::GetWindowLong([IntPtr]$_, -20) -band 0x20) -eq 0 }).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
# The names of the open menu's items (the browser's other visible window).
function MenuNames { $out = @(); foreach ($w in Popups) { $out += @(Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name }) }; $out }
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
# A guarded real click on pinned row `title`, with Ctrl or Shift held ("" for none); right-click when asked. What happened.
function ClickRow([string]$title, [string]$mod = "", [switch]$Right) {
    $n = NodeIn (Nodes $script:main) $title 0x24
    if (-not $n) { return "no row '$title' drawn" }
    $vk = @{ ctrl = 0x11; shift = 0x10 }[$mod]
    $pid32 = [uint32]$script:bpid
    if ($vk) { $d = [E18Input]::KeyDown($pid32, $vk); if ($d -ne "sent") { return "key not held: $d" } }
    try { [E18Input]::Click($script:main, $n.l + [int]($n.w * 0.4), $n.t + [int]($n.h / 2), $Right.IsPresent) }
    finally { if ($vk) { $null = [E18Input]::KeyUp($pid32, $vk) } }
}
# The N of the last "pins: selected N row(s)" line, and how many such lines there are.
function SelectedN { $l = @(Lines "pins: selected (\d+) row\(s\)"); if ($l.Count) { $l[-1].Matches[0].Groups[1].Value } else { "-" } }
# Runs `act`, waits for one more "selected" line; the N it says.
function SelectBy([scriptblock]$act) {
    $c = Count "pins: selected \d+ row\(s\)"
    $r = & $act
    $null = WaitLog "pins: selected \d+ row\(s\)" ($c + 1) 6
    "$r; selected $(SelectedN) (lines +$((Count 'pins: selected \d+ row\(s\)') - $c))"
}
# Folder `folder`'s saved children (ids) in workspace `guid`.
function Kids([string]$guid, [string]$folder) {
    Start-Sleep (4 * $slow)
    try { $d = Get-Content -Raw -Encoding UTF8 -LiteralPath "$prof\Default\Workspace Pins" | ConvertFrom-Json } catch { return "" }
    $f = @($d.workspaces.$guid | Where-Object { $_.id -eq $folder }) | Select-Object -First 1
    @($f.children | Where-Object { $_ } | ForEach-Object { $_.id }) -join ","
}
# A guarded real drag of pinned row `from` (pressed at 40% of its width) to row `to`, `fy` of its height -- or to the
# first Today tab. What happened.
function DragRow([string]$from, [string]$to, [double]$fy = 0.5, [switch]$ToTab, [int]$Role = 0x24) {
    $nodes = Nodes $script:main
    $src = NodeIn $nodes $from 0x24
    $dst = if ($ToTab) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t) | Select-Object -First 1 } else { NodeIn $nodes $to $Role }
    if (-not $src) { return "no row '$from' drawn" }
    if (-not $dst) { return "no target '$to' drawn" }
    [E18Input]::Drag($script:main, $src.l + [int]($src.w * 0.4), $src.t + [int]($src.h / 2), $dst.l + [int]($dst.w * 0.4), $dst.t + [int]($dst.h * $fy))
}
function Go([string]$name, [string]$guid) {
    $c = Count "active workspace -> '$guid'"
    $null = Press $script:main $name 0x2B
    $ok = WaitLog "active workspace -> '$guid'" ($c + 1) 10
    $null = WaitLog "pins: drew \d+ row\(s\) of '$guid'" 1 10
    Start-Sleep (1 * $slow)
    $ok
}

function Launch {
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--force-color-profile=srgb",
           "--host-resolver-rules=`"MAP * ~NOTFOUND`"", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($script:main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    Say "browser $($script:bpid) from $exe, log $log; session '$env:SESSIONNAME', window dpi $([E18Input]::Dpi($script:main))"
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

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime)"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
# Part 2's chip drop (D6) needs the five chips drawn: the sidebar 280 wide, as check-c4 seeds it.
if ($Part -eq 2) { & python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null }

try {
    Launch
    $drew = Count "pins: drew 6 row\(s\) of 'default'"
    Verdict "P0 the window opened on Home with its 6 rows: $drew line(s)" ($drew -ge 1)

    if ($Part -eq 1) {
    $o0 = Count "pins: opened item"
    $r = SelectBy { ClickRow "Example A" "ctrl" }
    Verdict "S1 Ctrl+click Example A ($r): want 1, and no page opened (opened lines +$((Count 'pins: opened item') - $o0))" ((SelectedN) -eq "1" -and (Count "pins: opened item") -eq $o0)

    $r = SelectBy { ClickRow "Example D" "ctrl" }
    Verdict "S2 Ctrl+click Example D ($r): want 2" ((SelectedN) -eq "2")

    $r1 = SelectBy { ClickRow "Example D" "ctrl" }; $n1 = SelectedN
    $r2 = SelectBy { ClickRow "Example D" "ctrl" }; $n2 = SelectedN
    Verdict "S3 Ctrl+click Example D off, then on again ($r1 | $r2): want 1 then 2, got $n1 then $n2" ($n1 -eq "1" -and $n2 -eq "2")

    $r = SelectBy { ClickRow "Closed folder" "shift" }
    Verdict "S4 Shift+click Closed folder, anchor Example D ($r): the range alone, want 2" ((SelectedN) -eq "2")

    $r = SelectBy { ClickRow "Example A" "shift" }
    Verdict "S5 Shift+click Example A ($r): the range is six rows, two sit in the selected folder, want 4" ((SelectedN) -eq "4")

    $m0 = Count "pins: menu for 4 selected row\(s\)"
    $r = ClickRow "Example D" "" -Right
    $okm = WaitLog "pins: menu for 4 selected row\(s\)" ($m0 + 1) 6
    $names = (MenuNames) -join ", "
    NoPopups
    Verdict "S6 right-click Example D ($r): the selection's menu $okm, items [$names] (want Unpin, Move to workspace, Delete; no Rename)" ($okm -and $names -match "Unpin" -and $names -match "Move to workspace" -and $names -match "Delete" -and $names -notmatch "Rename")

    $c0 = Count "pins: selection cleared"
    $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
    $okc = WaitLog "pins: selection cleared" ($c0 + 1) 4
    Verdict "S7 Escape on a row: the selection is let go: $okc" $okc

    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $c0 = Count "pins: selection cleared"; $o0 = Count "pins: opened item 'a0'"
    $r = ClickRow "Example A"
    $okc = WaitLog "pins: selection cleared" ($c0 + 1) 4
    $oko = WaitLog "pins: opened item 'a0'" ($o0 + 1) 10
    Verdict "S8 a plain click on Example A ($r): the selection let go $okc AND its page opened $oko" ($okc -and $oko)

    # S8b: Close on the selection (A's page is open since S8; no check pressed it before).
    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $r = ClickRow "Example D" "" -Right
    $namesC = (MenuNames) -join ", "
    $k0 = Count "closed the page of pinned item 'a0'"
    $pc = OtherPress "^Close"
    $okcl = WaitLog "pins: closed the open pages of 2 selected row\(s\)" 1 6
    $okpg = WaitLog "closed the page of pinned item 'a0'" ($k0 + 1) 6
    NoPopups
    $c0 = Count "pins: selection cleared"
    $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
    $null = WaitLog "pins: selection cleared" ($c0 + 1) 4
    Verdict "S8b A and D selected, A's page open, the menu's Close ($r; items [$namesC]; $pc): $okcl; A's page closed: $okpg; selection let go after Escape: $((Count 'pins: selection cleared') -gt $c0)" ($okcl -and $okpg -and $namesC -match "Close" -and (Count "pins: selection cleared") -gt $c0)

    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $r = ClickRow "Example D" "" -Right
    $p = OtherPress "^Unpin$"
    $oku = WaitLog "pins: unpinned 2 selected row\(s\)" 1 6
    $roots = Roots "default"
    NoPopups
    Verdict "S9 A and D selected, the menu's Unpin ($r; $p): $oku; Home's saved rows $roots (want f0,g0)" ($oku -and $roots -eq "f0,g0")

    $null = SelectBy { ClickRow "Smoke folder" "ctrl" }; $null = SelectBy { ClickRow "Closed folder" "ctrl" }
    $r = ClickRow "Closed folder" "" -Right
    $p1 = OtherPress "^Move to workspace"
    $p2 = OtherPress "^Private$"
    $okmv = WaitLog "pins: moved 2 selected row\(s\) to workspace '$private'" 1 8
    $homeRows = Roots "default"; $pr = Roots $private
    NoPopups
    Verdict "S10 the two folders, Move to workspace > Private ($r; $p1; $p2): $okmv; Home $(if ($homeRows) { $homeRows } else { 'none' }), Private $pr (want none, a3,f3,g3,d3,f0,g0)" ($okmv -and $homeRows -eq "" -and $pr -eq "a3,f3,g3,d3,f0,g0")

    $wentWork = Go "Work" $work
    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $r = ClickRow "Example D" "" -Right
    $p = OtherPress "^Delete$"
    $oka = WaitLog "confirm asked: delete 2 selected row\(s\)" 1 6
    $q = OtherPress "^Delete$"
    $okd = WaitLog "pins: deleted 2 selected row\(s\)" 1 10
    $wk = Roots $work
    Verdict "S11 on Work ($wentWork), A and D, the menu's Delete ($r; $p): confirm asked $oka; pressed ($q): deleted $okd; Work's saved rows $wk (want f1,g1)" ($wentWork -and $oka -and $okd -and $wk -eq "f1,g1")

    $s0 = Count "pins: selected \d+ row\(s\)"
    $r = SelectBy { ClickRow "Closed folder" "ctrl" }
    $s1 = Count "pins: selected \d+ row\(s\)"
    $pid32 = [uint32]$script:bpid
    $k1 = [E18Input]::KeyDown($pid32, 0x10)
    $k2 = [E18Input]::Tap($pid32, 0x27)
    $k3 = [E18Input]::KeyUp($pid32, 0x10)
    Start-Sleep (2 * $slow)
    $opened = [bool](NodeIn (Nodes $script:main) "Hidden" 0x24)
    Verdict "S12 Ctrl+click Closed folder ($r), then Shift+Right ($k1; $k2; $k3): the folder opened (Hidden drawn: $opened), 'selected' lines +$((Count 'pins: selected \d+ row\(s\)') - $s1) after the arrow (want 0), $(Count 'pins: selected \d+ row\(s\)') - $s0 total from the click (want 1)" ($opened -and (Count "pins: selected \d+ row\(s\)") -eq $s1 -and $s1 -eq $s0 + 1)
    } else {
    # ---- Part 2: the group drag
    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $g0 = Count "pins: dragging 2 selected row\(s\)"
    $r = DragRow "Example A" "Closed folder" 0.5
    $okg = WaitLog "pins: dragging 2 selected row\(s\)" ($g0 + 1) 6
    $roots = Roots "default"; $kids = Kids "default" "g0"
    Verdict "D1 A + D dragged into Closed folder ($r): the group's drag $okg; Home $roots (want f0,g0), g0 holds $kids (want a0,d0,h0)" ($okg -and $roots -eq "f0,g0" -and $kids -eq "a0,d0,h0")

    # The folder may be open (a hover opened it and the drop kept it) or closed.
    if (-not (NodeIn (Nodes $script:main) "Example A" 0x24)) { $null = ClickRow "Closed folder"; Start-Sleep (2 * $slow) }
    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $g0 = Count "pins: dragging 2 selected row\(s\)"
    $r = DragRow "Example A" "Smoke folder" 0.1
    $okg = WaitLog "pins: dragging 2 selected row\(s\)" ($g0 + 1) 6
    $roots = Roots "default"; $kids = Kids "default" "g0"
    Verdict "D2 A + D dragged before Smoke folder ($r): $okg; Home $roots (want a0,d0,f0,g0), g0 holds $kids (want h0)" ($okg -and $roots -eq "a0,d0,f0,g0" -and $kids -eq "h0")

    # A and D are still selected from D2 (a move among the rows keeps the selection): let them go with a Ctrl+click each.
    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $null = SelectBy { ClickRow "Wikipedia" "ctrl" }; $null = SelectBy { ClickRow "Hidden" "ctrl" }
    $u0 = Count "pins: unpinned item"
    $r = DragRow "Wikipedia" "" 0.9 -ToTab
    $oku = WaitLog "pins: unpinned item" ($u0 + 2) 10
    Start-Sleep (1 * $slow)
    # The two new Today tabs by their titles (the pages do not load): Wikipedia's above Hidden's, as the rows were.
    $tabs = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { $_.name })
    $iw = [array]::FindIndex($tabs, [Predicate[string]]{ param($n) $n -match "(?i)wikipedia" })
    $ih = [array]::FindIndex($tabs, [Predicate[string]]{ param($n) $n -match "(?i)hidden" })
    $ordered = $iw -ge 0 -and $ih -ge 0 -and $iw -lt $ih
    $roots = Roots "default"; $f0 = Kids "default" "f0"; $g1 = Kids "default" "g0"
    Verdict "D3 Wikipedia + Hidden dragged onto a Today tab ($r): unpinned +$((Count 'pins: unpinned item') - $u0) (want 2); Home $roots (want a0,d0,f0,g0), f0 holds $f0 (want c0), g0 holds '$g1' (want none); Today tabs [$($tabs -join ' | ')]: Wikipedia above Hidden $ordered" ($oku -and (Count "pins: unpinned item") -eq $u0 + 2 -and $roots -eq "a0,d0,f0,g0" -and $f0 -eq "c0" -and $g1 -eq "" -and $ordered)

    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $g0 = Count "pins: dragging"; $c0 = Count "pins: selection cleared"
    $r = DragRow "Closed folder" "Example A" 0.1
    $okc = WaitLog "pins: selection cleared" ($c0 + 1) 6
    $roots = Roots "default"
    Verdict "D4 Closed folder, NOT selected, dragged before Example A ($r): only it moves, Home $roots (want g0,a0,d0,f0); selection let go $okc; 'dragging' lines +$((Count 'pins: dragging') - $g0) (want 0)" ($okc -and $roots -eq "g0,a0,d0,f0" -and (Count "pins: dragging") -eq $g0)

    $null = SelectBy { ClickRow "Example A" "ctrl" }; $null = SelectBy { ClickRow "Example D" "ctrl" }
    $m0 = Count "pins: moved '"
    $r = DragRow "Example A" "Example D" 0.1
    Start-Sleep (1 * $slow)
    $roots = Roots "default"
    Verdict "D5 A + D, A dragged onto D (a member of the group) ($r): nowhere to drop, Home $roots (want g0,a0,d0,f0), 'moved' lines +$((Count "pins: moved '") - $m0) (want 0)" ($roots -eq "g0,a0,d0,f0" -and (Count "pins: moved '") -eq $m0)

    # D6: A + D are still selected (a refused drop keeps the selection).
    $o0 = Count "rail drop: over '$canary'"; $g0 = Count "pins: dragging 2 selected row\(s\)"
    $r = DragRow "Example A" "Canary" 0.5 -Role 0x2B
    $okd = WaitLog "pins: moved 'd0' to workspace '$canary'" 1 8
    $okl = (Count "rail drop: over '$canary'") -gt $o0
    $homeRows = Roots "default"; $cn = Roots $canary
    Verdict "D6 A + D dragged onto the Canary chip ($r): the group's drag +$((Count 'pins: dragging 2 selected row\(s\)') - $g0) (want 1), the chip lit $okl, both moved $okd; Home $homeRows (want g0,f0), Canary $cn (want a2,f2,g2,d2,a0,d0)" ($okl -and $okd -and (Count "pins: dragging 2 selected row\(s\)") -eq $g0 + 1 -and $homeRows -eq "g0,f0" -and $cn -eq "a2,f2,g2,d2,a0,d0")
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    NoPopups
    $q = Quit
}
$markers = 0
if (Test-Path -LiteralPath $log) { $markers = @(Get-Content -LiteralPath $log | Select-String -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count }
Verdict "Z crash markers in $log (the quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$verdict"
exit [int]($verdict -eq "FAIL")
