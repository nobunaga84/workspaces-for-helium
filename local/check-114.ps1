param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "c114", [double]$IdleMinutes = 15)
# Patch 114 (R9: Helium 0.22's Favorites re-fit, LOCAL.md 148), on a throwaway copy of the smoke profile (Home, Work,
# Canary...; Sessions emptied) whose Local State asks for Helium's "Spacious" density (helium.browser.ui_density 1).
# Real keys -- the workspace shortcuts, Ctrl+W -- so it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE
# (a person starting it passes -IdleMinutes 0 and lets go of the mouse and keyboard). The pages are check-c14's
# (local\c14-pages\page.html, a plain page for any ?name), opened through DevTools; which page shows is read from
# DevTools (document.visibilityState), the workspace from the log, the rows from MSAA.
#   F1  in Canary a page made a favorite (its menu's Add to Favorites), p2 and p1 opened, the favorite shown; Ctrl+W
#       on it puts it to sleep (Helium) and shows p1; Ctrl+W on p1 -> p2 in front, NOT the favorite woken (it was
#       left last: before 114 patch 73's "tab left last" rule picked it).
#   F2  in Home h opened and a page made a favorite; in Work w opened, the favorite shown; back in Home (the
#       favorite in front, w used more recently than h). Ctrl+W on the favorite -> h in front and the window still
#       in Home -- before 114 Helium's replacement was the window's most recent tab, w, and the window followed it
#       into Work.
#   F3  under Spacious a tab of the list (Compact, the base's Tab style) is as tall as Helium's own tab, 32 DIP --
#       before 114 it stayed 30 (MSAA rect / the window's DPI); so is "+ New Tab" (added after the red run: its
#       old height is unmeasured).
#   Z   0 crash markers in the log (case-sensitive).
# A pass needs every row. Run it in its own process -- pwsh -File local\check-114.ps1 [-OutDir Dcheck]
# [-IdleMinutes 0] -- it compiles C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = if ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise.log" } else { "$ws\$Tag-run.log" }
$homeWs = "default"
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$active = "\[workspaces\] active workspace -> '([^']*)'"
$last   = "\[workspaces\] last used tab -> index (\d+)"
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:port = 0; $script:pagePort = 0; $script:server = $null
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Last([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Matches[0] }) } }
function Grp([string]$re) { $m = @(Last $re); if ($m.Count) { @($m[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function ActiveWs { $g = Grp $active; if ($g.Count) { $g[1] } else { "" } }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
# The first shown node matching `re` in the browser's other windows (a menu), pressed via MSAA (check-c14's).
function OtherPress([IntPtr]$main, [string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    "nothing matching '$re'"
}
# Keys to the browser's window in front, through SendKeys ("%+2" is Shift+Alt+2) -- never to another window.
function Keys([string]$k) {
    if ([C114Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
# A workspace by its shortcut; the run stops when it does not show.
function Go([string]$k, [string]$guid) {
    $c = Count $active; $r = Keys $k
    if (-not ((WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid)) { throw "$k did not show workspace '$guid' ($r)" }
    Start-Sleep (1 * $slow)
}
function Serve([string]$dir) {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $script:pagePort = $l.LocalEndpoint.Port; $l.Stop()
    $p = Start-Process python -ArgumentList "-m", "http.server", $script:pagePort, "--bind", "127.0.0.1", "--directory", $dir -WindowStyle Hidden -PassThru
    foreach ($i in 1..20) {
        Start-Sleep -Milliseconds 500
        try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$($script:pagePort)/page.html").StatusCode -eq 200) { return $p } } catch {}
    }
    Stop-Process -Id $p.Id -EA SilentlyContinue
    $null
}
function Url([string]$n) { "http://127.0.0.1:$($script:pagePort)/page.html?$n" }
function Base { "http://127.0.0.1:$($script:port)/json" }
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
function Short([string]$u) { if ($u -match '/page\.html\?([\w-]+)') { $Matches[1] } else { $u } }
function Has([string]$n) { @(Targets | Where-Object { (Short $_.url) -eq $n }).Count }
# The page that shows: the one whose document is visible, by its short name ("none", or "a+b" when two say so).
function Visible {
    Start-Sleep -Milliseconds (300 * $slow)
    $v = @(Targets | Where-Object { (Evaluate $_.webSocketDebuggerUrl "document.visibilityState") -eq "visible" } | ForEach-Object { Short $_.url })
    if ($v.Count) { $v -join "+" } else { "none" }
}
function NewTab([string]$n) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url $n)))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$n'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.title") -ne ($n -replace "-", " ") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
function Show($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# Page `n`'s row made a favorite, as C34f does: a right-click on its Today row, the menu's Add to Favorites. What was
# done, and whether a row named "<title>...Pinned..." is there now.
function Favorite([IntPtr]$main, [string]$n) {
    $title = $n -replace "-", " "
    $row = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "$title*" }) | Select-Object -First 1
    $m = if ($row) { [E18Input]::Click($main, $row.l + [int]($row.w / 3), $row.t + [int]($row.h / 2), $true) } else { "no Today tab '$title' drawn" }
    Start-Sleep -Milliseconds (800 * $slow)
    $m += "; $(OtherPress $main '^Add to Favorites$')"
    Start-Sleep (1 * $slow)
    @($m, [bool]@(Nodes $main | Where-Object { $_.role -eq 0x25 -and $_.name -like "$title*Pinned*" }).Count)
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime)"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real keys ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C114Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath "$prof\DevToolsActivePort", $log -EA SilentlyContinue
# Helium's density is read once from Local State at startup (layout_constants.cc GetHeliumUiDensity): Spacious = 1.
& python -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); d.setdefault('helium',{}).setdefault('browser',{})['ui_density']=1; json.dump(d,open(p,'w',encoding='utf-8'))" "$prof\Local State"
if ($LASTEXITCODE -ne 0) { Abort "could not set Spacious in the copy's Local State" }
$script:server = Serve "$here\c14-pages"
if (-not $script:server) { Abort "the local pages were not served" }
try {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--helium-workspaces-log-addresses", "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check")).Id
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port), pages on port $($script:pagePort), log $log"

    # F1: a sleeping favorite is not woken by the next close (patch 73's pick skips it).
    Go "%+3" $canary
    $g = NewTab "c114-g"
    $fg = Favorite $main "c114-g"
    $null = NewTab "c114-p2"; $null = NewTab "c114-p1"
    Show $g
    $k1 = Keys "^w"
    Start-Sleep (3 * $slow)
    $v1 = Visible
    $c = Count $last; $k2 = Keys "^w"
    $null = WaitLog $last ($c + 1) 10
    Start-Sleep (2 * $slow)
    $v2 = Visible
    $pick = Grp $last
    Verdict "F1 'c114 g' a favorite ($($fg[0]); pinned: $($fg[1])), p2 and p1 opened, the favorite shown; Ctrl+W ($k1) on it: p1 in front (shown: $v1); Ctrl+W ($k2) on p1 (open: $(Has 'c114-p1')): p2 in front, not the favorite woken (shown: $v2; last pick: index $(if ($pick.Count) { $pick[1] } else { 'none' }))" ($fg[1] -and $v1 -eq "c114-p1" -and (Has "c114-p1") -eq 0 -and $v2 -eq "c114-p2")

    # F2: Helium's replacement for a sleeping favorite stays in the workspace on screen.
    Go "%+1" $homeWs
    $null = NewTab "c114-h"
    $f = NewTab "c114-fav"
    $ff = Favorite $main "c114-fav"
    Go "%+2" $work
    $null = NewTab "c114-w"
    Show $f
    Go "%+1" $homeWs
    $v0 = Visible
    $c = Count $active; $k = Keys "^w"
    Start-Sleep (3 * $slow)
    $moved = (Count $active) -gt $c
    $now = ActiveWs
    $v = Visible
    Verdict "F2 'c114 fav' a favorite in Home ($($ff[0]); pinned: $($ff[1])), w opened in Work, back in Home on the favorite (shown: $v0); Ctrl+W ($k): h in front (shown: $v), the window still in Home (switched: $moved, now '$now')" ($ff[1] -and $v0 -eq "c114-fav" -and $v -eq "c114-h" -and -not $moved -and $now -eq $homeWs)

    # F3: under Spacious a Compact tab of the list is as tall as Helium's own (32 DIP), measured on the window's DPI;
    # so is "+ New Tab", the list's first row (114's ListRowHeight, which the pinned pages and the drag probe share):
    # the sidebar's button by a tab's left edge, not the toolbar's (check-c12's).
    $dpi = [E18Input]::Dpi($main)
    $nodes = @(Nodes $main)
    $rows = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "c114 *" -and $_.name -notlike "*Pinned*" })
    $dip = @($rows | ForEach-Object { [math]::Round($_.h * 96 / $dpi, 1) })
    $plus = if ($rows) { @($nodes | Where-Object { $_.shown -and $_.name -eq "New Tab" -and $_.role -eq 0x2B -and [Math]::Abs($_.l - $rows[0].l) -lt 60 }) | Sort-Object t | Select-Object -First 1 }
    $pd = if ($plus) { [math]::Round($plus.h * 96 / $dpi, 1) } else { 0 }
    Verdict "F3 Spacious, Tab style Compact: the list's tab rows ($(@($rows | ForEach-Object { $_.name.Split(' - ')[0] }) -join ', ')) are $($dip -join ', ') DIP tall at DPI $dpi, + New Tab $(if ($plus) { "$pd DIP" } else { 'not found' }) -- Helium's Spacious tab is 32, before 114 the tabs stayed 30" ($dip.Count -ge 1 -and @($dip | Where-Object { $_ -lt 31.5 }).Count -eq 0 -and $pd -ge 31.5)
} catch {
    Say "ERROR: $_"; $script:failed++
} finally {
    if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    }
    if ($script:server) { Stop-Process -Id $script:server.Id -EA SilentlyContinue }
}
# Case-sensitive, as LOCAL.md grades (LOCAL.md 3968, 7372).
$markers = if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling").Count } else { 0 }
Verdict "Z crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
