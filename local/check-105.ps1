param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "p105", [double]$IdleMinutes = 15,
      [string]$BinDir = "", [string[]]$Rows = @())
# Patch 105 (review 2's chunk 3, <local-path>\Helium-workspace\patch-review-2-findings.md R2-1): a close of every tab of the
# window keeps the window, with a New Tab in the workspace on screen. check-104's shape: a throwaway copy of the smoke
# profile (Home, Work, Canary, Private, Unpin; no pinned page open), the sidebar 280 wide, ServePages' plain
# "E18 <name>" pages opened through DevTools (/json/new: in front, in the workspace on screen). Clicks, right-clicks and
# keys are REAL input (SendInput, guarded); menu items are pressed through MSAA (msaa-press.ps1). It starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. One launch and one log per row: before 105, C1 and C2 end the browser.
#   pwsh -NoProfile -File local\check-105.ps1 [-Build Dcheck] [-BinDir <dir>] [-IdleMinutes 0] [-Rows C1,D1]
#   red: the build before 105 (out\Default before the build, 104 on top): ... -Tag p105-red
#   each row first makes the window hold Work's Today tabs only: h105 opened in Home and every other page closed,
#   Work entered (the switch spawns its New Tab), h105 closed, then the row's two pages opened in Work
#   C1 R2-1  Shift+Alt+K (Clear Today): all 3 closed, "a New Tab opened first", one tab inserted, stamped Work; the
#            browser still running, Work still on screen, drawing one tab (the old: the window closed, the browser exited)
#   C2 R2-1  the Work chip's "Close all tabs": the same
#   D1       the Work chip's "Delete workspace" still behaves: the switch to Home spawns Home's New Tab first, so no
#            "a New Tab opened first"; Home on screen, drawing that one tab, Work's pages gone (passes before 105 too)
#   Z        0 crash markers in the logs (case-sensitive, DanglingPtr too)
# -Rows C1,D1: only those rows (and Z). A pass needs every verdict run ($total).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows C1,D1` passes ONE string "C1,D1": split it.
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
$every   = @("C1", "C2", "D1")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 1   # + Z
# The lines graded, case-sensitively.
$closing  = "\[workspaces\] closing (\d+) tab\(s\) of workspace '([^']*)' in this window"
$kept     = "\[workspaces\] close: the window's last tabs, a New Tab opened first"
$inserted = "\[workspaces\] tab inserted at index \d+ -> workspace '([^']*)'"
$deleting = "\[workspaces\] deleting workspace '([^']*)'"
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
# The first group of every line matching `re` after the first `skip`.
function After([string]$re, [int]$skip) { @(Lines $re | Select-Object -Skip $skip | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA and the menus, as check-104's -------------------------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $script:prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { if (-not (Running)) { return }; foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
function PressNode([IntPtr]$w, $n) {
    $r = Press $w $n.name $n.role
    if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
    "'$($n.name)' $r"
}
# The first shown node matching `re` in a menu, pressed.
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
# The Work chip's menu (a guarded right-click), then its item matching `re` pressed.
function WorkMenu([string]$re) {
    NoPopups
    $n = NodeIn (Nodes $script:main) "Work" 0x2B
    if (-not $n) { return "no Work chip drawn" }
    $r = [E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    if ($r -ne "right-clicked") { return $r }
    "$r; $(OtherPress $re)"
}
# A guarded click low in the page, so the keys go to the browser (check-92's).
function Front { $b = [E18Input]::Client($script:main); [E18Input]::Click($script:main, $b[0] + [int]($b[2] * 0.6), $b[1] + $b[3] - 40, $false) }
# The workspace shown by its chip: true once "active workspace -> <guid>" is logged (or it is already shown).
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

# ---- the pages and DevTools, as check-104's ---------------------------------------------------------------------------
function Url([string]$name) { "http://127.0.0.1:$($script:srv.port)/$name.html" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array as ONE object (check-c35's).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_ -and $_.type -eq "page" }) } catch { @() } }
function PageOf([string]$name) { @(Targets | Where-Object { $_.url -like "*/$name.html*" }) | Select-Object -First 1 }
function CloseTarget($t) { if (-not $t) { return "no target" }; try { "$(Invoke-RestMethod -TimeoutSec 10 -Uri "$(Base)/close/$($t.id)")" } catch { "error: $_" } }
# True once page `name` is no longer open.
function Gone([string]$name) { $t0 = Get-Date; do { if (-not (PageOf $name)) { return $true }; Start-Sleep -Milliseconds 400 } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow); $false }
# Page `name` opened in front in the workspace on screen (/json/new), once titled: its target.
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $name)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
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
# A fresh profile and launch for `row`, then the window made to hold Work's Today tabs only: h105 opened in Home and
# every other page closed (the window is never empty), Work entered (the switch spawns its New Tab), h105 closed, then
# `names` opened in Work. Whether that held: the pages DevTools lists = Work's drawn Today = `names` + its New Tab.
function WorkOnly([string]$row, [string[]]$names) {
    $prof = "$ws\testprofile-$Tag-$row$suffix"
    NewProfile $prof
    Launch $prof "$ws\$Tag-$row$suffix-run.log"
    $h = Go "Home" "default"
    $null = NewTab "h105"
    foreach ($t in @(Targets | Where-Object { $_.url -notlike "*/h105.html*" })) { $null = CloseTarget $t }
    Start-Sleep (1 * $slow)
    $w = Go "Work" $work
    $null = CloseTarget (PageOf "h105")
    $g = Gone "h105"
    foreach ($n in $names) { $null = NewTab $n }
    $open = @(Targets).Count
    $drawn = @(Today (Nodes $script:main))
    [pscustomobject]@{
        ok   = $h -and $w -and $g -and $open -eq $names.Count + 1 -and $drawn.Count -eq $open
        said = "Home $h, Work $w, h105 gone $g; $open page(s) open, Work draws [$(Names $drawn)] (want $($names.Count + 1) both)"
    }
}
# After a close of every tab of the window: what is left, read from the log since the counts `c` and the screen.
function Left($c, [string[]]$names) {
    Start-Sleep (3 * $slow)
    $alive = (Running) -and @([E18Input]::Windows([uint32]$script:bpid)).Count -ge 1
    $drawn = if ($alive) { @(Today (Nodes $script:main)) } else { @() }
    [pscustomobject]@{
        alive    = $alive
        closing  = @(Nth $closing $c.closing)
        kept     = (Count $kept) - $c.kept
        stamps   = @(After $inserted $c.inserted)
        switches = @(After $active $c.active)
        drawn    = $drawn
        gone     = $alive -and -not @($names | Where-Object { -not (Gone $_) }).Count
    }
}
function Counts { @{ closing = (Count $closing); kept = (Count $kept); inserted = (Count $inserted); active = (Count $active) } }
function Said($l) {
    "browser running $($l.alive); $(if ($l.closing.Count) { "'$($l.closing[0])'" } else { 'no closing line' }); 'a New Tab opened first' x$($l.kept); " +
    "inserted [$($l.stamps -join ', ')]; switches [$($l.switches -join ', ')]; draws [$(Names $l.drawn)]; the row's pages gone $($l.gone)"
}
# C1 and C2: the window kept, one tab stamped Work, Work still on screen drawing it.
function KeptOk($l) {
    $l.alive -and $l.closing.Count -and $l.closing[1] -eq "3" -and $l.closing[2] -eq $work -and $l.kept -eq 1 -and
        "$($l.stamps)" -eq $work -and -not $l.switches.Count -and $l.drawn.Count -eq 1 -and $l.gone
}
function Row([string]$row, [scriptblock]$body) {
    if ($want -notcontains $row) { return }
    try { & $body } catch { Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ }
    NoPopups
    Say "$row quit: $(Quit)"
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
# Which build this is, for the record only: the red run is the build without 105.
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "a New Tab opened first"
Say "build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 105; rows: $($want -join ', ')"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
$script:srv = ServePages $pages @("h105", "c105a", "c105b", "c105c", "c105d", "d105a", "d105b")
if (-not $script:srv.ok) { Abort "the local pages were not served" }

try {
    Row "C1" {
        $s = WorkOnly "C1" @("c105a", "c105b")
        $c = Counts
        $f = Front
        $p = [uint32]$script:bpid
        $k = "$([E18Input]::KeyDown($p, 0x10)) $([E18Input]::KeyDown($p, 0x12)) $([E18Input]::Tap($p, 0x4B)) $([E18Input]::KeyUp($p, 0x12)) $([E18Input]::KeyUp($p, 0x10))"
        $l = Left $c @("c105a", "c105b")
        Verdict "C1 R2-1 $($s.said); Shift+Alt+K ($f; $k): $(Said $l) (want running, 3 of Work's closed, the line x1, one inserted for Work, no switch, one tab drawn)" (
            $s.ok -and (KeptOk $l))
    }
    Row "C2" {
        $s = WorkOnly "C2" @("c105c", "c105d")
        $c = Counts
        $r = WorkMenu '^Close all tabs$'
        $l = Left $c @("c105c", "c105d")
        Verdict "C2 R2-1 $($s.said); Close all tabs ($r): $(Said $l) (want as C1)" ($s.ok -and (KeptOk $l))
    }
    Row "D1" {
        $s = WorkOnly "D1" @("d105a", "d105b")
        $c = Counts
        $d = Count $deleting
        $r = WorkMenu '^Delete workspace$'
        $l = Left $c @("d105a", "d105b")
        $del = @(After $deleting $d)
        Verdict "D1 $($s.said); Delete workspace ($r): deleting [$($del -join ', ')]; $(Said $l) (want running, Work deleted, 3 closed, no 'a New Tab opened first', one inserted for Home, a switch to Home, one tab drawn)" (
            $s.ok -and $l.alive -and "$del" -eq $work -and $l.closing.Count -and $l.closing[1] -eq "3" -and $l.kept -eq 0 -and
            "$($l.stamps)" -eq "default" -and "$($l.switches)" -eq "default" -and $l.drawn.Count -eq 1 -and $l.gone)
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = 0
foreach ($l in $script:logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($script:logs.Count) log(s) (the last quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
