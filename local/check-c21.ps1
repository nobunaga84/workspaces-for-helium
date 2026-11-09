param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c21", [double]$IdleMinutes = 15,
      [string[]]$Rows = @())
# C21 (patch 88 `88-favorite-tiles.patch`, <local-path>\Helium-workspace\c21-progress.md; this check's design is "Q6 CHECKS" in
# <local-path>\Helium-workspace\c21-understand.md): favorites (Chromium pinned tabs) are 44 DIP Arc tiles with a faint rounded
# card at ANY Tab style; the collapsed column keeps them 30x30; the tab in front has no card (Helium's active fill
# instead). Patch 88 logs nothing: every row is graded from view bounds (ui-tree.py through Chromium's UI DevTools,
# --enable-ui-devtools=0), MSAA boxes and screen pixels (--force-color-profile=srgb: this PC's HDR display reads every
# colour ~4.6x too bright unforced, LOCAL.md Traps). Two runs, each on a fresh throwaway copy of the smoke profile
# (Sessions emptied, the sidebar 280 wide and expanded), all in Home ('default', on screen at the start) and its one
# window, placed 1000x800 DIP and topmost:
#   run "dark":  browser.theme.color_scheme2=2, helium.workspaces.tab_row_height=42 (Spacious)
#   run "light": browser.theme.color_scheme2=1, helium.workspaces.tab_row_height=30 (Compact)
# The pins are REAL right-clicks (SendInput, guarded): it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE.
#   pwsh -NoProfile -File local\check-c21.ps1 [-Build Dcheck] [-IdleMinutes 0] [-Rows C21c,C21d]
# Start it from a shell, never a detached Start-Process (the Claude window holds the foreground); clicks answering
# "another window is at" are the PC's (a Snipping Tool overlay), not C21's. In each run, from Home in window 1:
#   setup  "E18 c21a", "E18 c21b", "E18 c21e" opened (DevTools /json/new); c21a, then c21b: its tab menu > "Add to
#          Favorites" ('^Add to Favorites', never "Pin to this workspace"); c21e brought in front (/json/activate). PASS: Home's
#          rows drawn ("[workspaces] pins: drew N row(s) of 'default'"), both favorites drawn ("E18 c21x - Pinned"),
#          only c21e's document visible
#   C21a   ui-tree --root PinnedTabContainerView: exactly 2 shown TabViews, each 44 tall (+-1), one Y, each
#          floor((Wc - 10) / 2) wide (+-1; Wc the container's width: 2 per row); MSAA: both favorites' boxes / the
#          window's DPI are 44 (+-1)
#   C21b   MSAA "Collapse tabs": ui-tree: both 30x30 (+-1), one above the other; "Expand tabs": both 44 tall again, one Y
#   C21c   c21e in front, the mouse parked over the page: each favorite's pixel 4 DIP in from its left edge at mid-height
#          (left of the centred icon) against the strip in the 4 DIP gap between the two tiles: dark 4..10 levels
#          lighter, light 2..5 darker (half the pinned card's alpha, the owner's try: ~6.7 and ~2.8)
#   C21d   the Today tab c21e's active fill sampled at the same place in its row; c21a brought in front: its pixel within
#          2 levels of that fill (no card on the tile in front); c21b still in C21c's band; and the owner's point: the
#          tile in front at least 14 levels (largest channel) from a carded one -- 12 light / 9 dark with the full card
# After both runs:
#   C21e   the setups' ui-tree heights: 44 (+-1) at Spacious 42 (run "dark", its Today tab 42 tall) AND at 30 (run "light")
#   Z      0 crash markers in both logs (case-sensitive, DanglingPtr too)
# A pass needs all 12 verdicts ($total below). Captures: <local-path>\Helium-workspace\c21[-dcheck]-c21c-<run>.png and
# -c21d-<run>-before.png / -after.png.
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows C21c,C21d` passes ONE string "C21c,C21d": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = "$ws\helium-windows\build\src\out\$Build"
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$logs    = @(1..2 | ForEach-Object { if ($Build -eq "Dcheck") { "$ws\$Tag-dcheck-exercise$_.log" } else { "$ws\$Tag-run$_.log" } })
$pages   = "$ws\$Tag-pages"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = 14
# lo..hi: the card's fill over the strip, mean levels (check-c35's C35a / C35b band).
$runs    = @([pscustomobject]@{ name = "dark"; scheme = 2; row = 42; lo = 4; hi = 10 },
             [pscustomobject]@{ name = "light"; scheme = 1; row = 30; lo = -5; hi = -2 })
# 62-pinned-polish.patch:144 (first 40-pinned-section.patch:1468): "[workspaces] pins: drew N row(s) of '<guid>' in M ms".
$homeDrawn = "\[workspaces\] pins: drew \d+ row\(s\) of 'default'"

$script:passed = 0; $script:failed = 0; $script:seen = @{}; $script:tg = @{}; $script:homeRows = $false
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
function Near($a, [double]$b, [double]$tol = 1) { [bool]($null -ne $a -and [double]$a -ge 0 -and [math]::Abs([double]$a - $b) -le $tol) }

# ---- MSAA (msaa-press.ps1) and the menus, as check-c33's ----------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function TabIn($nodes, [string]$title) {
    $page = if ($title -like "E18 *") { "*/$($title.Substring(4)).html" } else { $null }
    @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq $title -or $_.name.StartsWith("$title - ") -or ($page -and $_.name -like $page)) }) | Select-Object -First 1
}
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
# Favorite `nm` (a Chromium pinned tab: MSAA names it "E18 <nm> - Pinned").
function Fav($nodes, [string]$nm) { NodeIn $nodes "E18 $nm - Pinned" 0x25 }
function WaitFav([string]$nm) {
    $t0 = Get-Date
    do { if (Fav (Nodes $script:main) $nm) { return $true }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $false
}
# A box's height in DIP (the MSAA box / the window's DPI); -1 for none.
function Dip($n) { if ($n) { [math]::Round($n.h / ([E18Input]::Dpi($script:main) / 96.0), 1) } else { -1 } }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
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
    "nothing matching '$re' (shown: $((@(PopupNames) | Select-Object -First 40) -join ' | '))"
}
# Today tab `title`'s menu (a guarded right-click), then its items matching each of `res` pressed in turn.
function TabMenu([string]$title, [string[]]$res) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no Today tab '$title' drawn" }
    $r = [E18Input]::Click($script:main, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    for ($i = 0; $i -lt $res.Count; $i++) {
        $p = OtherPress $res[$i]
        $r += "; $p"
        if ($p -like "nothing matching*") { NoPopups; break }
        Start-Sleep -Milliseconds (500 * $slow)
    }
    $r
}
function Row([string]$row, [scriptblock]$body) {
    # -Rows C21c,C21d: only those rows (and the setup); the RESULT then counts fewer verdicts.
    if ($Rows.Count -and $row -ne "setup" -and $Rows -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the pages, DevTools ------------------------------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# Page `name` opened in front (/json/new), once loaded with its title "E18 <name>": its target (id, webSocketDebuggerUrl).
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url "$name.html")))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A page brought in front (/json/activate: the tab activated, as a click on it) -- check-c35's Show.
function Show($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# The three pages' documents, "c21a: hidden, c21b: hidden, c21e: visible": only the tab in front is visible.
function Visibility { (@("c21a", "c21b", "c21e" | ForEach-Object { "${_}: $(if ($script:tg[$_]) { Evaluate $script:tg[$_].webSocketDebuggerUrl 'document.visibilityState' } else { 'no page' })" })) -join ", " }
function Want([string]$nm) { (@("c21a", "c21b", "c21e" | ForEach-Object { "${_}: $(if ($_ -eq $nm) { 'visible' } else { 'hidden' })" })) -join ", " }
# Page `nm` brought in front, polled until it alone is visible: what the three said last.
function ShowTab([string]$nm) {
    Show $script:tg[$nm]
    $t0 = Get-Date
    do { $v = Visibility; if ($v -eq (Want $nm)) { break }; Start-Sleep -Milliseconds 300 } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    $v
}

# ---- the grid's bounds (ui-tree.py) -------------------------------------------------------------------------------
# The favorites' grid through Chromium's UI DevTools: the first PinnedTabContainerView that holds tiles, its box and
# its shown TabViews (DIP, the tiles relative to the container) with their titles -- and all ui-tree printed, for a FAIL.
function Grid {
    $out = @(& python -I "$here\ui-tree.py" $prof --root PinnedTabContainerView 2>&1 | ForEach-Object { "$_" })
    $root = $null; $tiles = @()
    foreach ($l in $out) {
        if ($l -match '^PinnedTabContainerView @(-?[\d.]+),(-?[\d.]+) ([\d.]+)x([\d.]+)') {
            if ($root -and $tiles.Count) { break }
            $root = [pscustomobject]@{ x = [double]$Matches[1]; y = [double]$Matches[2]; w = [double]$Matches[3]; h = [double]$Matches[4] }
            $tiles = @()
        } elseif ($root -and $l -match '^  TabView @(-?[\d.]+),(-?[\d.]+) ([\d.]+)x([\d.]+)(.*)$' -and $Matches[5] -notmatch ' INVISIBLE') {
            $x = [double]$Matches[1]; $y = [double]$Matches[2]; $w = [double]$Matches[3]; $h = [double]$Matches[4]
            $title = if ($Matches[5] -match '"(.*)"') { $Matches[1] } else { "?" }
            $tiles += [pscustomobject]@{ x = $x; y = $y; w = $w; h = $h; title = $title }
        }
    }
    [pscustomobject]@{ root = $root; tiles = $tiles; raw = (@($out | ForEach-Object { $_.Trim() }) -join " / ") }
}
function Boxes($tiles) { @($tiles | ForEach-Object { "'$($_.title)' @$($_.x),$($_.y) $($_.w)x$($_.h)" }) -join ", " }

# ---- pixels (check-c35's) -----------------------------------------------------------------------------------------
# Colors are 0xRRGGBB; a channel k = 0 red, 1 green, 2 blue; the distance is the largest channel's.
function Ch([int]$c, [int]$k) { ($c -shr (16 - 8 * $k)) -band 255 }
function Dist([int]$a, [int]$b) { $m = 0; foreach ($k in 0..2) { $d = [Math]::Abs((Ch $a $k) - (Ch $b $k)); if ($d -gt $m) { $m = $d } }; $m }
function Hex([int]$c) { if ($c -lt 0) { "none" } else { '#{0:x6}' -f $c } }
function Grab([int]$x, [int]$y, [int]$w, [int]$h) {
    [C35Fg]::Aware()
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size) } finally { $g.Dispose() }
    $bmp
}
function At($bmp, [int]$x, [int]$y) { $bmp.GetPixel($x - $script:gx, $y - $script:gy).ToArgb() -band 0xFFFFFF }
# The mean shift of `a` over `b` in levels (+ lighter); $null when either was not read.
function Shift([int]$a, [int]$b) { if ($a -lt 0 -or $b -lt 0) { return $null }; $d = 0.0; foreach ($k in 0..2) { $d += ((Ch $a $k) - (Ch $b $k)) / 3.0 }; [math]::Round($d, 1) }
function Band($d, $run) { $null -ne $d -and $d -ge $run.lo -and $d -le $run.hi }
# ONE capture of both favorites (and Today tab `today`, when named), boxes from MSAA, saved as `png`, the mouse first
# parked over the page (a hovered tile paints its hover fill): each favorite's pixel 4 DIP in from its left edge at
# mid-height (left of the centred icon), the strip in the gap between the two tiles at that height, and the Today tab's
# pixel at the same place in its row. row: the two tiles on one row with a gap between.
function Snap([string]$png, [string]$today = "") {
    $res = [pscustomobject]@{ ok = $false; row = $false; a = -1; b = -1; strip = -1; today = -1; text = "" }
    $bmp = $null
    try {
        $cl = [E18Input]::Client($script:main)
        $moved = [C35Fg]::Hover($script:main, $cl[0] + [int]($cl[2] * 0.7), $cl[1] + [int]($cl[3] * 0.5))
        Start-Sleep -Milliseconds (600 * $slow)
        $front = [C35Fg]::Front() -eq $script:main
        $n = @(Nodes $script:main)
        $fa = Fav $n "c21a"; $fb = Fav $n "c21b"
        $td = if ($today) { TabIn @(Today $n) $today } else { $null }
        if (-not $fa -or -not $fb -or ($today -and -not $td)) { $res.text = "not measured: favorites c21a $([bool]$fa), c21b $([bool]$fb)$(if ($today) { ", the Today tab '$today' $([bool]$td)" }) (mouse $moved)"; return $res }
        $L, $R = @($fa, $fb | Sort-Object l)
        $res.row = [Math]::Abs($L.t - $R.t) -le 1 -and $R.l - ($L.l + $L.w) -ge 2
        $dpi = [E18Input]::Dpi($script:main); $in = [int][Math]::Round(4 * $dpi / 96.0)
        $box = @($fa, $fb, $td | Where-Object { $_ })
        $x0 = [int](@($box | ForEach-Object { $_.l }) | Measure-Object -Minimum).Minimum - 4
        $y0 = [int](@($box | ForEach-Object { $_.t }) | Measure-Object -Minimum).Minimum - 4
        $x1 = [int](@($box | ForEach-Object { $_.l + $_.w }) | Measure-Object -Maximum).Maximum + 4
        $y1 = [int](@($box | ForEach-Object { $_.t + $_.h }) | Measure-Object -Maximum).Maximum + 4
        $script:gx = $x0; $script:gy = $y0
        $bmp = Grab $x0 $y0 ($x1 - $x0) ($y1 - $y0)
        $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $y = $L.t + [int]($L.h / 2); $gap = [int](($L.l + $L.w + $R.l) / 2)
        $res.a = At $bmp ($fa.l + $in) ($fa.t + [int]($fa.h / 2))
        $res.b = At $bmp ($fb.l + $in) ($fb.t + [int]($fb.h / 2))
        $res.strip = At $bmp $gap $y
        if ($td) { $res.today = At $bmp ($td.l + $in) ($td.t + [int]($td.h / 2)) }
        $res.ok = $true
        $res.text = "dpi $dpi, the main window in front $front (mouse $moved); c21a $(Hex $res.a) at $($fa.l + $in),$($fa.t + [int]($fa.h / 2)), c21b $(Hex $res.b) at $($fb.l + $in),$($fb.t + [int]($fb.h / 2)), the strip in the gap $(Hex $res.strip) at $gap,$y$(if ($td) { ", the Today tab '$today' $(Hex $res.today) at $($td.l + $in),$($td.t + [int]($td.h / 2))" }); one row with a gap $($res.row); capture $png"
    } catch {
        $res.text = "not measured: $_ (line $($_.InvocationInfo.ScriptLineNumber))"
    } finally {
        if ($bmp) { $bmp.Dispose() }
    }
    $res
}

# ---- one start of the browser, and its quit ----------------------------------------------------------------------
function Fresh($run) {
    # The run before's force-stopped processes let go of its files first.
    if (Test-Path -LiteralPath $prof) { Start-Sleep (2 * $slow); Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { throw "the copy of $smoke failed" }
    Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    & python -I "$here\prefs.py" "$prof\Default\Preferences" "browser.theme.color_scheme2=$($run.scheme)" "helium.workspaces.tab_row_height=$($run.row)" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false"
    if ($LASTEXITCODE -ne 0) { throw "the preferences were not seeded into $prof" }
}
function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", "$prof\UIDevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0", "--enable-ui-devtools=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $script:homeRows = WaitLog $homeDrawn 1 30
    $s = [E18Input]::Dpi($script:main) / 96.0; $scr = [E18Input]::Screen()
    [E18Input]::Place($script:main, 40, 40, [Math]::Min($scr[0] - 80, [int](1000 * $s)), [Math]::Min($scr[1] - 120, [int](800 * $s)))
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log); screen $($scr -join 'x'), window dpi $([E18Input]::Dpi($script:main))"
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
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
# Patch 88 has no string to grep chrome.dll for: its file time only (a refresh after the build reads OLDER too).
$dll = Get-Item -LiteralPath "$bin\chrome.dll"
$p88 = Get-Item -LiteralPath "$ws\helium-windows\patches\local\workspaces\88-favorite-tiles.patch"
Say "build: $Build\chrome.dll of $($dll.LastWriteTime), $(if ($dll.LastWriteTime -gt $p88.LastWriteTime) { 'NEWER' } else { 'OLDER' }) than patch 88 ($($p88.LastWriteTime))"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C35Fg { [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; } [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c); [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(P p); [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } public static IntPtr Front() { return GetForegroundWindow(); } public static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); } public static string Hover(IntPtr h, int x, int y) { Aware(); P p; p.x = x; p.y = y; if (GetAncestor(WindowFromPoint(p), 2) != h) return "not moved: another window is at " + x + "," + y; SetCursorPos(x, y); System.Threading.Thread.Sleep(400); return "moved"; } }'
Remove-Item -LiteralPath $logs -EA SilentlyContinue
$script:srv = ServePages $pages @("c21a", "c21b", "c21e")
if (-not $script:srv.ok) { Abort "the local pages were not served" }

$quits = @()
try {
    foreach ($i in 0, 1) {
        $run = $runs[$i]; $script:log = $logs[$i]; $script:tg = @{}
        try {
            Fresh $run
            Launch
            Row "setup" {
                foreach ($nm in "c21a", "c21b", "c21e") { $script:tg[$nm] = NewTab $nm }
                $pin = @(foreach ($nm in "c21a", "c21b") { "${nm}: $(TabMenu "E18 $nm" @('^Add to Favorites')), a favorite $(WaitFav $nm)" }) -join "; "
                $v = ShowTab "c21e"
                $n = @(Nodes $script:main)
                $favs = @("c21a", "c21b" | Where-Object { Fav $n $_ })
                $g = Grid
                $script:seen[$run.name] = [pscustomobject]@{ tiles = @($g.tiles | ForEach-Object { $_.h }); today = Dip (TabIn @(Today $n) "E18 c21e") }
                Verdict "setup $($run.name) (Home, window 1; scheme $($run.scheme), Tab style $($run.row)): Home's rows drawn $($script:homeRows); pinned through the tab menu ($pin); favorites drawn: $($favs -join ', ') (want c21a, c21b); 'E18 c21e' in front ($v)" ($script:homeRows -and $favs.Count -eq 2 -and $v -eq (Want "c21e"))
            }
            Row "C21a" {
                $g = Grid; $t = @($g.tiles); $n = @(Nodes $script:main)
                $msaa = @("c21a", "c21b" | ForEach-Object { Dip (Fav $n $_) })
                $want = if ($g.root) { [Math]::Floor(($g.root.w - 10) / 2) } else { -1 }
                $ok = $t.Count -eq 2 -and $t[0].y -eq $t[1].y -and -not @($t | Where-Object { -not (Near $_.h 44) -or -not (Near $_.w $want) }).Count -and -not @($msaa | Where-Object { -not (Near $_ 44) }).Count
                Verdict "C21a $($run.name) (Home, window 1, Tab style $($run.row)): ui-tree: PinnedTabContainerView $(if ($g.root) { "$($g.root.w)x$($g.root.h)" } else { 'not found' }) holds $($t.Count) TabView(s) $(Boxes $t) (want 2, each 44 tall, one Y, $want wide +-1); MSAA: c21a, c21b $($msaa -join ', ') DIP tall (want 44 +-1)$(if (-not $t.Count) { "; ui-tree: $($g.raw)" })" $ok
            }
            Row "C21b" {
                $p = Press $script:main "Collapse tabs" 0x2B
                Start-Sleep (2 * $slow)
                $c = @((Grid).tiles)
                # The collapsed column's views (the owner's try-c21 step 4: the pinned card drawn empty and too wide).
                $cb = [E18Input]::Client($script:main); $shot = Grab $cb[0] $cb[1] 160 520
                $shot.Save("$ws\$Tag$suffix-c21b-$($run.name)-collapsed.png", [System.Drawing.Imaging.ImageFormat]::Png); $shot.Dispose()
                $script:sect = @()
                foreach ($root in "PinnedTabContainerView", "WorkspacePinnedSectionView", "PinRow") {
                    $tl = @(& python -I "$here\ui-tree.py" $prof --root $root 2>&1 | ForEach-Object { "$_" }) | Select-Object -First 30
                    $tl | ForEach-Object { Say "      tree $root | $_" }
                    if ($root -eq "WorkspacePinnedSectionView") { $script:sect = $tl }
                }
                # C21f (the owner's try): collapsed, the pinned card is as wide as a favorite's tile and starts where it does.
                $card = @($script:sect | Where-Object { $_ -match "^\s+View @([\d.]+),([\d.]+) ([\d.]+)x([\d.]+)" } | Select-Object -First 1)
                $cm = if ($card.Count) { [regex]::Match($card[0], "View @([\d.]+),([\d.]+) ([\d.]+)x([\d.]+)") } else { $null }
                $cx = if ($cm) { [double]$cm.Groups[1].Value } else { -1 }; $cw = if ($cm) { [double]$cm.Groups[3].Value } else { -1 }
                $tw = if ($c.Count) { $c[0].w } else { -1 }
                Verdict "C21f $($run.name) (Home, window 1; collapsed): the pinned card x $cx width $cw, a favorite tile width $tw (want x 6 +-1 -- the strip's padding, as the tiles and Today tabs -- and the tile's width +-1)" ($cm -and [Math]::Abs($cx - 6) -le 1 -and $tw -gt 0 -and [Math]::Abs($cw - $tw) -le 1)
                # The owner's state: a FAVORITE in front while collapsed.
                $fv = ShowTab "c21a"; Start-Sleep (2 * $slow)
                $cb = [E18Input]::Client($script:main); $shot = Grab $cb[0] $cb[1] 160 520
                $shot.Save("$ws\$Tag$suffix-c21b-$($run.name)-collapsed-fav.png", [System.Drawing.Imaging.ImageFormat]::Png); $shot.Dispose()
                Say "      favorite in front: $fv"
                foreach ($root in "WorkspacePinnedSectionView", "PinRow") {
                    @(& python -I "$here\ui-tree.py" $prof --root $root 2>&1 | ForEach-Object { "$_" }) | Select-Object -First 30 | ForEach-Object { Say "      fav-tree $root | $_" }
                }
                $null = ShowTab "c21e"; Start-Sleep (1 * $slow)
                $e = Press $script:main "Expand tabs" 0x2B
                Start-Sleep (2 * $slow)
                $x = @((Grid).tiles)
                $col = $c.Count -eq 2 -and [Math]::Abs($c[0].y - $c[1].y) -ge 30 -and -not @($c | Where-Object { -not (Near $_.h 30) -or -not (Near $_.w 30) }).Count
                $exp = $x.Count -eq 2 -and $x[0].y -eq $x[1].y -and -not @($x | Where-Object { -not (Near $_.h 44) }).Count
                Verdict "C21b $($run.name) (Home, window 1): 'Collapse tabs' ($p): $(Boxes $c) (want two 30x30 +-1, one above the other); 'Expand tabs' ($e): $(Boxes $x) (want both 44 tall again, one Y)" ($p -match '^MSAA: pressed' -and $e -match '^MSAA: pressed' -and $col -and $exp)
            }
            Row "C21c" {
                $v = ShowTab "c21e"
                $m = Snap "$ws\$Tag$suffix-c21c-$($run.name).png"
                $da = Shift $m.a $m.strip; $db = Shift $m.b $m.strip
                Verdict "C21c $($run.name) (Home, window 1; c21e in front: $v): $($m.text); over the strip c21a $da, c21b $db levels (want $($run.lo)..$($run.hi) each: the card)" ($v -eq (Want "c21e") -and $m.ok -and $m.row -and (Band $da $run) -and (Band $db $run))
            }
            Row "C21d" {
                $v0 = ShowTab "c21e"
                $m0 = Snap "$ws\$Tag$suffix-c21d-$($run.name)-before.png" "E18 c21e"
                $v1 = ShowTab "c21a"
                $m1 = Snap "$ws\$Tag$suffix-c21d-$($run.name)-after.png"
                $d = if ($m0.ok -and $m1.ok) { Dist $m1.a $m0.today } else { -1 }
                $db = Shift $m1.b $m1.strip
                $gap = if ($m1.ok) { Dist $m1.a $m1.b } else { -1 }
                Verdict "C21d $($run.name) (Home, window 1): before ($v0): $($m0.text); c21a brought in front ($v1): $($m1.text); c21a's pixel $d level(s) from the Today tab's active fill (want 0..2: no card on the tile in front); c21b $db over the strip (want $($run.lo)..$($run.hi): still carded); the tile in front $gap levels from the carded c21b (want 14+: told apart)" ($v0 -eq (Want "c21e") -and $v1 -eq (Want "c21a") -and $m0.ok -and $m1.ok -and $m1.row -and $d -ge 0 -and $d -le 2 -and (Band $db $run) -and $gap -ge 14)
            }
        } catch {
            Say "ERROR $($run.name) (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        } finally {
            $quits += "$($run.name) $(Quit)"
        }
    }
    Row "C21e" {
        $ok = { param($x, $row) $x -and (Near $x.today $row) -and @($x.tiles).Count -eq 2 -and -not @($x.tiles | Where-Object { -not (Near $_ 44) }).Count }
        $d = $script:seen["dark"]; $l = $script:seen["light"]
        Verdict "C21e a favorite is 44 at any Tab style (the setups' ui-tree): dark, Spacious $($runs[0].row) (its Today tab $($d.today) DIP, want $($runs[0].row)): $(@($d.tiles) -join ', '); light, $($runs[1].row) (its Today tab $($l.today), want $($runs[1].row)): $(@($l.tiles) -join ', ') -- each 44 (+-1)" ((& $ok $d $runs[0].row) -and (& $ok $l $runs[1].row))
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($logs -join ', ') (the quits: $($quits -join '; ')): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
