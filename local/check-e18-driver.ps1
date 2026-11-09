param([string]$OutDir = "Default", [double]$IdleMinutes = 15)
# Rehearsal of the OWNER's check (check-e18.ps1) with no one at the keyboard. The owner script runs UNMODIFIED in its
# own pwsh process; its answers are PIPED FROM A FILE (local\installer\p2-driver.ps1's pattern: Get-Content -Wait
# <feed> | ...), its output goes through cmd straight into a file the driver watches (the E14d3 rehearsal's). Every
# answer is 'y' (plus a feel and a comment), appended only AFTER the driver has done that step in the browser: the owner
# script marks its log at each answer, so its own grading then proves each step end to end. What the driver saw goes in
# the comment ("driver saw NOT OK: ..."), so a 'y' it could not back shows in the owner script's grade. How each step is
# done (check-e18-auto.ps1's helpers, copied below; the input type and the DevTools calls from e18-lib.ps1):
#   1  nothing pressed; THE HEADER's and the folders' MSAA descriptions read (5 pinned pages / 60 Today tabs; 2; 1)
#   2  the Settings page opened through the DevTools port (the owner script's -DevToolsPort; the owner types the
#      address); the five Settings controls' order read from the page, the three prefs' defaults by settingsPrivate
#   3  tab_row_height set 42, then 30, by chrome.settingsPrivate.setPref; the heights MSAA shows read each time
#   4  a Today tab clicked, the list rolled to its top, then a guarded wheel -40, -40, -40, -120; smooth_scrolling set
#      false, one -120 step (no glide line may follow), set true again
#   5  a guarded drag of THE SIDEBAR'S EDGE +400 DIP; the window closed with WM_CLOSE (what its X sends); after the
#      owner script's restart the edge's place compared; closed again
# Real input (steps 4 and 5) moves the mouse: the run starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE,
# and each click, wheel or drag is sent only on the unlocked desktop with the browser's window under the point.
# Started by hand: add -IdleMinutes 0 and let go of the mouse. Run it in its own process, one line:
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-e18-driver.ps1
# Output: e18-owner-rehearsal-driver.txt (what the driver did and saw, then the owner script's PASS/FAIL lines),
# e18-owner-rehearsal.txt (the owner script's own output); the owner script's files are its usual e18-owner-*.
. "$PSScriptRoot\e18-lib.ps1"
$ws       = "<local-path>\Helium-workspace"
$here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$check    = "$here\check-e18.ps1"
$prof     = "$ws\testprofile-e18-owner"   # the owner script's (its -Tag e18-owner)
$bin      = "$ws\helium-windows\build\src\out\$OutDir"
$log      = "$ws\e18-owner-run.log"
$feed     = "$ws\e18-owner-rehearsal-feed.txt"
$out      = "$ws\e18-owner-rehearsal.txt"
$drv      = "$ws\e18-owner-rehearsal-driver.txt"
$runner   = "$ws\e18-owner-rehearsal-run.ps1"
$edgeName = "Vertical Tab Strip Resize Handle (Draggable)"
$reStyle  = '\[workspaces\] tab style: row height (\d+) -> (\d+)'
$reGlide  = '\[workspaces\] glide: (-?[\d.]+) -> (-?[\d.]+) \((\d+) ms\)'
$reWidth  = '\[workspaces\] sidebar: width (\d+) \(max (\d+)\)'
$script:win = [IntPtr]::Zero
$script:bpid = 0
$script:client = @(0, 0, 0, 0)
$script:scale = 1.0
$script:dev = $null
$script:bad = [Collections.Generic.List[string]]::new()

function Note([string]$s) { $line = "$((Get-Date).ToString('HH:mm:ss')) $s"; Write-Host $line; Add-Content -LiteralPath $drv -Value $line -Encoding utf8 }
function Saw([string]$what, $ok) { Note ($(if ($ok) { "ok      " } else { "NOT OK  " }) + $what); if (-not $ok) { $script:bad.Add($what) } }

# ---- the owner script: answers from the feed, output into $out ------------------------------------------------
function OutText { try { $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite'); try { [IO.StreamReader]::new($fs).ReadToEnd() } finally { $fs.Close() } } catch { "" } }
function Answer([string]$a, [string]$why) { Add-Content -LiteralPath $feed -Value $a -Encoding utf8; Note "ANSWER '$a' -- $why"; Start-Sleep 2 }
# The runner, the cmd under it and the owner script's pwsh (the runner's Get-Content -Wait never ends by itself).
function StopOwner {
    Stop-Process -Id $child.Id -EA SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='cmd.exe'" | Where-Object { $_.CommandLine -like "*\check-e18.ps1 *" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
}
# Every browser of this build closed (forced after 45 s: a throwaway profile), the owner script and its page server stopped.
function Finish {
    if ($script:bpid) { foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) } }
    $t = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*") -and ((Get-Date) - $t).TotalSeconds -lt 45) { Start-Sleep 1 }
    Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*" | Stop-Process -Force -EA SilentlyContinue
    StopOwner
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like "*e18-owner-pages*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
}
function Bail([string]$why) {
    Note "DRIVER STOPPED: $why"
    Finish
    Note "--- the owner script's output, last lines ---"
    (OutText) -split "`r?`n" | Select-Object -Last 25 | ForEach-Object { Note "  | $_" }
    exit 1
}
# Until the owner script has printed `text` (its steps are Write-Host; Read-Host's prompts are not echoed to a file).
function WaitOut([string]$text, [int]$s) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) {
        $o = OutText
        if ($o.Contains($text)) { return }
        if ($o.Contains("ABORT:")) { Bail "the owner script aborted" }
        if ($o -match 'ALL PASS|check\(s\) FAILED') { Bail "the owner script finished before '$text'" }
        if ($child.HasExited) { Bail "the owner script's runner exited before '$text'" }
        Start-Sleep 1
    }
    Bail "no '$text' from the owner script in $s s"
}

# ---- check-e18-auto.ps1's helpers ---------------------------------------------------------------------------------
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitCount([string]$re, [int]$n, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# The leading comma keeps a one-number list a list (check-e18.ps1's Nums: "680"[0] would be "6").
function LastNums([string]$re) { $m = @(Select-String -LiteralPath $log -Pattern $re); if ($m.Count) { , @($m[-1].Matches[0].Groups | Select-Object -Skip 1 | ForEach-Object { $_.Value }) } }
# The build's browser window (a new one after the restart), polled.
function FindWindow([int]$s = 30) {
    $t0 = Get-Date
    do {
        $p = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" -and $_.MainWindowHandle -ne [IntPtr]::Zero }) | Select-Object -First 1
        if ($p) { $script:bpid = $p.Id; $script:win = $p.MainWindowHandle; $script:client = [E18Input]::Client($script:win); return $true }
        Start-Sleep 1
    } while (((Get-Date) - $t0).TotalSeconds -lt $s)
    return $false
}
# The window restored, placed top-left `w` x `h` DIP (at most the screen) and topmost, not activated.
function Place([int]$w, [int]$h) {
    $s = [E18Input]::Dpi($script:win) / 96.0
    $scr = [E18Input]::Screen()
    [E18Input]::Place($script:win, 0, 0, [math]::Min($scr[0], [int]($w * $s)), [math]::Min($scr[1] - 80, [int]($h * $s)))
    Start-Sleep 2
    $script:scale = [E18Input]::Dpi($script:win) / 96.0
    $script:client = [E18Input]::Client($script:win)
    Note "window: scale $($script:scale), client $($script:client -join ',') px"
}
function Msaa([string[]]$a) {
    if ($script:win -ne [IntPtr]::Zero) { $a += @("-Window", [string][long]$script:win) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof @a
}
function Nodes([switch]$Desc) {
    $a = @("-List", "-Rect"); if ($Desc) { $a += "-Desc" }
    @(Msaa $a | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)(?:\|desc=(.*))?$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                               l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7]; desc = [string]$Matches[8] }
        }
    })
}
function Shown($n) { (-not $n.hidden) -and $n.h -gt 0 -and $n.w -gt 0 }
function Named($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.name -eq $name -and $_.role -eq $role -and (Shown $_) }) | Select-Object -First 1 }
function TodayTabs($nodes) { @($nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and $_.name -notmatch ' - Pinned$' }) }
function ClickNode($n) { if (-not $n) { return "nothing to click" }; [E18Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false) }
# Heights in DIPs of a Today tab, the pinned page "Example A", the folder "Smoke folder" and "+ New Tab".
function Heights {
    $n = @(Nodes)
    $dip = { param($x) if ($x) { [math]::Round($x.h / $script:scale, 1) } else { -1 } }
    [ordered]@{ today = & $dip (@(TodayTabs $n | Where-Object { $_.name -match '^E18 g\d\d' }) | Select-Object -First 1); pinned = & $dip (Named $n "Example A" 0x24); folder = & $dip (Named $n "Smoke folder" 0x24); newtab = & $dip (Named $n "New Tab" 0x2B) }
}
function Edge { @(Nodes | Where-Object { $_.name -eq $edgeName -and (Shown $_) }) | Select-Object -First 1 }
function EdgeX($e) { if ($e) { $e.l + $e.w - $script:client[0] } else { -1 } }
# The Settings page's socket (e18-lib.ps1's OpenSettings) once chrome.settingsPrivate is there, else $null.
function SettingsPage { $s = OpenSettings $prof; if ($s.ready) { $s.page.webSocketDebuggerUrl } }
function SetPref([string]$name, $value) { "$(Evaluate $script:dev "chrome.settingsPrivate.setPref('$name', $($value | ConvertTo-Json -Compress), '')")" }

E18InputType

# ---- guards -------------------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $check)) { Write-Host "ABORT: no $check"; exit 1 }
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is running -- close it first"; exit 1 }
$gate = "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes)"
if ($gate -notmatch '^FREE') {
    Write-Host "VOID: the rehearsal moves the real mouse and needs the PC to itself -- the gate says: $gate. Nothing was run."
    Write-Host "      Leave the screen UNLOCKED and hands off and run it again; started by hand, add -IdleMinutes 0 and let go of the mouse."
    exit 2
}

Remove-Item -LiteralPath $feed, $out, "$out.err", $drv -EA SilentlyContinue
$null = New-Item -ItemType File -Path $feed
# The runner: the feed piped into cmd, whose pwsh (the owner script, unmodified) writes straight into $out.
Set-Content -LiteralPath $runner -Encoding utf8 -Value "Get-Content -Wait -LiteralPath '$feed' | cmd /d /c `"pwsh -NoProfile -File $check -OutDir $OutDir -DevToolsPort 1>$out 2>$out.err`""
$child = Start-Process pwsh -ArgumentList @("-NoProfile", "-File", $runner) -WindowStyle Hidden -PassThru
Note "PC: $gate"
Note "owner script started (runner pid $($child.Id)): $(Get-Content -LiteralPath $runner -Raw)"

WaitOut "WORDS USED BELOW" 600
if (-not (FindWindow)) { Bail "no browser window" }
Place 1400 800

# ---- 1 ------------------------------------------------------------------------------------------------------------
WaitOut " 1. LOOK at THE HEADER." 60
$n = @(Nodes -Desc)
$hd = [string](@($n | Where-Object { $_.name -eq "Home" -and (Shown $_) -and $_.desc -match 'pinned page' }) | Select-Object -First 1).desc
$sd = [string](Named $n "Smoke folder" 0x24).desc
$cd = [string](Named $n "Closed folder" 0x24).desc
Saw "1: THE HEADER 'Home' spells '$hd' (5 pinned pages / 60 Today tabs)" ($hd -eq '5 pinned pages / 60 Today tabs')
Saw "1: Smoke folder '$sd' (2 pinned pages), Closed folder '$cd' (1 pinned page)" ($sd -match '\b2 pinned pages$' -and $cd -match '\b1 pinned page$')
Answer "y" "s1"

# ---- 2 ------------------------------------------------------------------------------------------------------------
WaitOut " 2. Click the browser window, press Ctrl+T" 60
$script:dev = SettingsPage
if (-not $script:dev) { Bail "no Settings page through the DevTools port" }
# The appearance page's controls in document order (into every shadow root), by their labels; polled while it renders.
$js = @'
(() => { const out = []; const walk = r => { for (const e of r.querySelectorAll('*')) { if (e.matches('settings-toggle-button, settings-dropdown-menu') && !e.hidden) out.push(e.getAttribute('label') || ''); if (e.shadowRoot) walk(e.shadowRoot); } }; walk(document); return out.join('|'); })()
'@
$want = 'Show vertical tabs on right side|Tab style|Smooth scrolling in the tab list|Allow a wider sidebar|Workspaces'
$t = Get-Date
do { Start-Sleep 1; $order = "$(Evaluate $script:dev $js)" } while (-not $order.Contains($want) -and ((Get-Date) - $t).TotalSeconds -lt 15)
Saw "2: the controls in order hold '$want' (page: '$order')" ($order.Contains($want))
$was = "$(Evaluate $script:dev "Promise.all(['helium.workspaces.tab_row_height', 'helium.workspaces.smooth_scrolling', 'helium.workspaces.wide_sidebar'].map(k => chrome.settingsPrivate.getPref(k).then(p => String(p.value)))).then(a => a.join(','))")"
Saw "2: Tab style, Smooth scrolling, wider sidebar at their defaults: '$was' (30,true,true)" ($was -eq '30,true,true')
Answer "y" "s2"

# ---- 3 ------------------------------------------------------------------------------------------------------------
WaitOut " 3. On the Settings page" 60
$k = Count $reStyle
$set = SetPref "helium.workspaces.tab_row_height" 42
$ok = WaitCount $reStyle ($k + 1) 15; Start-Sleep 2
$h = Heights
Saw "3: Spacious: setPref $set, 'row height' line $ok ($((LastNums $reStyle) -join ' -> ')); heights $(@($h.Values) -join '/') (42 each, +-1)" ($ok -and -not @($h.Values | Where-Object { [math]::Abs($_ - 42) -gt 1 }).Count)
$set = SetPref "helium.workspaces.tab_row_height" 30
$ok = WaitCount $reStyle ($k + 2) 15; Start-Sleep 2
$h = Heights
Saw "3: Compact: setPref $set, 'row height' line $ok ($((LastNums $reStyle) -join ' -> ')); heights $(@($h.Values) -join '/') (30 each, +-1)" ($ok -and -not @($h.Values | Where-Object { [math]::Abs($_ - 30) -gt 1 }).Count)
Answer "y" "s3"

# ---- 4 ------------------------------------------------------------------------------------------------------------
WaitOut " 4. Put the mouse over the TODAY TABS" 60
$c = $script:client
# The wheel's point: the middle of a Today tab drawn 40-80 % down the client area -- over the list's scroll view.
$at = @(TodayTabs @(Nodes) | Where-Object { ($_.t + $_.h / 2) -gt ($c[1] + 0.4 * $c[3]) -and ($_.t + $_.h / 2) -lt ($c[1] + 0.8 * $c[3]) } | Sort-Object t) | Select-Object -First 1
if (-not $at) { Bail "no Today tab 40-80 % down the window to roll the wheel over" }
$x = $at.l + [int]($at.w / 2); $y = $at.t + [int]($at.h / 2)
# That tab clicked first (the window in front, the active tab one already shown), the list rolled to its top.
Note ("4: '$($at.name)' " + (ClickNode $at) + "; to the top: " + [E18Input]::Wheel($script:win, $x, $y, [int[]](@(120) * 15), 60))
Start-Sleep 2
$g = Count $reGlide
Note ("4: down: " + [E18Input]::Wheel($script:win, $x, $y, [int[]]@(-40, -40, -40, -120), 600))
$ok = WaitCount $reGlide ($g + 1) 5; Start-Sleep 1
Saw "4: on: $((Count $reGlide) - $g) 'glide:' line(s) (the last: $((LastNums $reGlide) -join ' / '))" $ok
Answer "y" "s4"
WaitOut "How did the glide feel?" 30
Answer "right (rehearsal driver, not the owner)" "the feel"
WaitOut 'switch "Smooth scrolling in the tab list" OFF' 30
$set = SetPref "helium.workspaces.smooth_scrolling" $false
Start-Sleep 1
$g = Count $reGlide
Note ("4: off (setPref $set): " + [E18Input]::Wheel($script:win, $x, $y, [int[]]@(-120), 600))
Start-Sleep 2
Saw "4: off: no 'glide:' line after the step ($((Count $reGlide) - $g))" ((Count $reGlide) -eq $g)
$set = SetPref "helium.workspaces.smooth_scrolling" $true
Note "4: back on: setPref $set"
Answer "y" "s4off"

# ---- 5 ------------------------------------------------------------------------------------------------------------
WaitOut " 5. If the window does not fill the screen" 60
$e = Edge
if (-not $e) { Bail "THE SIDEBAR'S EDGE is not shown" }
$k = Count $reWidth
$ey = $e.t + [int]($e.h / 2); $ex = $e.l + [int]($e.w / 2)
Note ("5: the edge at $(EdgeX $e) px, dragged +400 DIP: " + [E18Input]::Drag($script:win, $ex, $ey, $ex + [int](400 * $script:scale), $ey))
$ok = WaitCount $reWidth ($k + 1) 10; Start-Sleep 1
$wm = LastNums $reWidth
Saw "5: a 'sidebar: width W (max M)' line ${ok}: W $($wm[0]), M $($wm[1]) (W above 400)" ($ok -and [int]$wm[0] -gt 400)
Answer "y" "s5"
WaitOut "Look where THE SIDEBAR'S EDGE is now" 30
$e5 = EdgeX (Edge)
Note "5: the edge at $e5 px; the window closed (WM_CLOSE)"
foreach ($hw in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($hw) }
WaitOut "The browser is open again." 240
if (-not (FindWindow)) { Bail "no browser window after the restart" }
Start-Sleep 3
$e6 = EdgeX (Edge)
Saw "5: after the restart the edge is at $e6 px, before the close $e5 px (+-2)" ($e5 -ge 0 -and $e6 -ge 0 -and [math]::Abs($e6 - $e5) -le 2)
Answer "y" "s5r"

# ---- 6 ------------------------------------------------------------------------------------------------------------
WaitOut " 6. Close the browser with its X" 30
foreach ($hw in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($hw) }
Note "6: the window closed (WM_CLOSE)"
WaitOut "Browser closed." 120
Answer $(if ($script:bad.Count) { "driver saw NOT OK: " + ($script:bad -join ' / ') } else { "rehearsal driver, not the owner: every step seen" }) "the comment"

$t = Get-Date
while (-not ((OutText) -match 'ALL PASS|check\(s\) FAILED') -and ((Get-Date) - $t).TotalSeconds -lt 120) { Start-Sleep 1 }
$said = (OutText) -split "`r?`n"
Note "--- the owner script said ---"
$said | Where-Object { $_ -match '^(PASS|FAIL|ALL PASS|ABORT|\d+ check)|binary:|feel:|comment:' } | ForEach-Object { Note "  | $_" }
if ((Test-Path "$out.err") -and (Get-Item "$out.err").Length) { Note "--- its stderr ---"; Get-Content "$out.err" | Select-Object -First 15 | ForEach-Object { Note "  ! $_" } }
Finish
$pass = [bool]@($said | Where-Object { $_ -match '^ALL PASS' }).Count
Note "REHEARSAL: the owner script $(if ($pass) { 'ALL PASS' } else { 'did NOT pass' }); the driver saw $($script:bad.Count) thing(s) NOT OK"
if ($pass -and -not $script:bad.Count) { exit 0 } else { exit 1 }
