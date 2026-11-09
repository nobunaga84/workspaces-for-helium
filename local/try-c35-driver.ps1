param([double]$IdleMinutes = 15)
# Rehearsal of the OWNER's try (try-c35.ps1, C35 + C31 + C32) with no one at the keyboard -- check-e18-driver.ps1's
# pattern. The owner script runs UNMODIFIED in its own pwsh process; its answers are PIPED FROM A FILE (Get-Content
# -Wait <feed> | ...), its output goes through cmd straight into a file the driver watches. Every answer is 'y', appended
# only AFTER the driver has done that step in the browser: the owner script marks its log at each answer, so its own
# grading then proves each step end to end. What the driver could not confirm goes in the closing comment ("driver saw
# NOT OK: ..."). It is run with no switch: -Zen (the sidebar shown only at the window's left edge) is not rehearsed.
# How each owner action is done (check-c35.ps1's helpers, copied below):
#   keys (Shift+Alt+N, Esc)   SendKeys to the browser's MAIN window in front -- a guarded click on the page first when
#                             it is not (this PC's Claude window holds the foreground)
#   click a pinned page       an MSAA press by its name (accDoDefaultAction)
#   right-click               a guarded real right-click (OpenMenu); a menu item pressed through MSAA by its name, a
#                             guarded click when the name did not survive MSAA (OtherPress)
#   follow a link             a trusted click through DevTools (Input.dispatchMouseEvent on the page)
#   close the browser         WM_CLOSE to each window (what its X sends)
#   1  Shift+Alt+2, "Example A" pressed, Shift+Alt+5: Work shown, item 'a1' opened, Unpin draws no pinned page. THE
#      CARD's look is not measured here (check-c35 C35a/C35c are its check).
#   2  Shift+Alt+2, "C35 home" pressed, its menu read: Close page, no "Use current page"; Esc
#   3  the link clicked: c35away loads, the back arrow shows; the menu has the item right above Unpin; pressed:
#      "takes the page in front" logged, the pins file holds c35away.html titled "C35 away", the arrow goes, the row
#      reads "C35 away", its menu no longer offers the item; Esc
#   4  Shift+Alt+3; try-c35 opens the tabs; the drawn order of its TODAY TABS read off MSAA and recorded (tabs opened
#      through /json/new land BELOW the one before on this build, 10-18); the workspace menu: "Close duplicate
#      tabs..." enabled, right above "Close all tabs", "duplicates: 3"; the box: 3, the three titles, "They stay in
#      the Archive."; Close tabs: "closing 3 of 3", the tabs left, the Archive file +3; the bar's Archive button: the
#      screen lists the three; closed with a click outside it (Esc when the click is refused)
#   5  the workspace menu: "duplicates: 0", the item greyed; Esc
#   6  try-c35 opens and groups the V tabs; the group's name box closed (Esc); the menu: 1; the box: only V loose copy;
#      closing 1 of 1; V in a group stays, in its group
#   -  the browser closed; try-c35 restarts it LIGHT
#   7  Shift+Alt+2: Work shown with its pinned pages, the profile's scheme light (1); the browser closed; the comment
# Real input moves the mouse: the run starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. Started by
# hand: add -IdleMinutes 0 and let go of the mouse. Run it in its own process, one line:
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c35-driver.ps1
# Output: try-c35-rehearsal-driver.txt (what the driver did and saw, then the owner script's RESULT lines),
# try-c35-rehearsal.txt (the owner script's own output); the owner script's files are its usual c35-owner-*.
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$check   = "$here\try-c35.ps1"
$prof    = "$ws\testprofile-c35-owner"   # the owner script's (no -Zen)
$bin     = "$ws\helium-windows\build\src\out\Default"
$logs    = @("$ws\c35-owner-run.log", "$ws\c35-owner-run2.log")
$feed    = "$ws\try-c35-rehearsal-feed.txt"
$out     = "$ws\try-c35-rehearsal.txt"
$drv     = "$ws\try-c35-rehearsal-driver.txt"
$runner  = "$ws\try-c35-rehearsal-run.ps1"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
$active  = "\[workspaces\] active workspace -> '([^']*)'"
$menuDup  = "\[workspaces\] duplicates: (\d+) of workspace '$canary' \(menu\)"
$askedDup = "\[workspaces\] duplicates: asked to close (\d+)"
$closeDup = "\[workspaces\] duplicates: closing (\d+) of (\d+) listed in workspace '$canary'"
$took     = "pins: 'c35p' takes the page in front as its address"
# The owner script stopped early (its own messages), or finished.
$stopRe  = 'STOPPED: |A test browser is already open|This build has no C31|could not be served|Could not seed'
$doneRe  = 'RESULT c35-owner'
$replace = "Use current page"
$script:main = [IntPtr]::Zero; $script:bpid = 0; $script:port = 0; $script:log = $logs[0]
$script:bad = [Collections.Generic.List[string]]::new()

function Note([string]$s) { $line = "$((Get-Date).ToString('HH:mm:ss')) $s"; Write-Host $line; Add-Content -LiteralPath $drv -Value $line -Encoding utf8 }
function Saw([string]$what, $ok) { Note ($(if ($ok) { "ok      " } else { "NOT OK  " }) + $what); if (-not $ok) { $script:bad.Add($what) } }

# ---- the owner script: answers from the feed, output into $out (check-e18-driver's) ------------------------------
function OutText { try { $fs = [IO.File]::Open($out, 'Open', 'Read', 'ReadWrite'); try { [IO.StreamReader]::new($fs).ReadToEnd() } finally { $fs.Close() } } catch { "" } }
function Answer([string]$a, [string]$why) { Add-Content -LiteralPath $feed -Value $a -Encoding utf8; Note "ANSWER '$a' -- $why"; Start-Sleep 2 }
# The runner, the cmd under it and the owner script's pwsh (the runner's Get-Content -Wait never ends by itself).
function StopOwner {
    Stop-Process -Id $child.Id -EA SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='cmd.exe'" | Where-Object { $_.CommandLine -like "*\try-c35.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
}
# Every browser of this build closed (forced after 45 s: a throwaway profile), the owner script and its page server stopped.
function Finish {
    if ($script:bpid) { foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) } }
    $t = Get-Date
    while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*") -and ((Get-Date) - $t).TotalSeconds -lt 45) { Start-Sleep 1 }
    Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*" | Stop-Process -Force -EA SilentlyContinue
    StopOwner
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like "*c35-owner-pages*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
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
        if ($o -match $stopRe) { Bail "the owner script stopped before '$text'" }
        if ($o -match $doneRe) { Bail "the owner script finished before '$text'" }
        if ($child.HasExited) { Bail "the owner script's runner exited before '$text'" }
        Start-Sleep 1
    }
    Bail "no '$text' from the owner script in $s s"
}

# ---- check-c35.ps1's helpers (the log is the owner script's run log) -----------------------------------------------
function Count([string]$re) { if (-not (Test-Path -LiteralPath $script:log)) { return 0 }; @(Select-String -LiteralPath $script:log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Last([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Matches[0] }) } }
function Grp([string]$re) { $m = @(Last $re); if ($m.Count) { @($m[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function ActiveWs { $g = Grp $active; if ($g.Count) { $g[1] } else { "" } }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Rect", "-States") | ForEach-Object {
        $n = @(ParseMsaaNodes @("$_"))
        if ($n.Count) { $n[0] | Add-Member -NotePropertyName unavailable -NotePropertyValue ("$_" -match '\|UNAVAILABLE$') -PassThru }
    })
}
function RowNode([string]$name) { @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x24 -and $_.name -eq $name }) | Select-Object -Last 1 }
function WaitNode([string]$name, [int]$role, [bool]$want) {
    $t0 = Get-Date
    do {
        if ([bool]@(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name }).Count -eq $want) { return $true }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    $false
}
# Keys through SendKeys ("%+2" is Shift+Alt+2) to the browser's MAIN window in front (a dialog of the browser's own
# process passes a pid guard and swallows the key, LOCAL.md 88); when it is not in front, a real click on the bottom
# middle of the page first (the window is placed at 40,40 1400x900 in Found). -Any: to whatever browser window is in front.
function Keys([string]$k, [switch]$Any) {
    if (-not $Any) {
        $t0 = Get-Date
        while ([C35Fg]::Front() -ne $script:main -and ((Get-Date) - $t0).TotalSeconds -lt 5) { Start-Sleep -Milliseconds 200 }
        if ([C35Fg]::Front() -ne $script:main) {
            $c = [E18Input]::Click($script:main, 740, 900, $false)
            $t0 = Get-Date
            while ([C35Fg]::Front() -ne $script:main -and ((Get-Date) - $t0).TotalSeconds -lt 3) { Start-Sleep -Milliseconds 200 }
            if ([C35Fg]::Front() -ne $script:main) { return "not sent: the browser's main window is not in front (a click: $c)" }
        }
    }
    if ([C35Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds 500; "sent"
}
# A workspace by its shortcut, its section drawn: true when it shows.
function Go([string]$k, [string]$guid) {
    if ((ActiveWs) -eq $guid) { return $true }
    $c = Count $active; $ch = Count "pins: header '$guid'"; $r = Keys $k
    $ok = (WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid
    if (-not $ok) { Note "  ${k}: $r" }
    $null = WaitLog "pins: header '$guid'" ($ch + 1) 10
    Start-Sleep 1
    $ok
}
function OpenMenu([IntPtr]$h, $node) {
    if (-not $node) { return [pscustomobject]@{ result = "nothing to right-click"; items = @() } }
    $c = [E18Input]::Click($h, $node.l + [int]($node.w / 3), $node.t + [int]($node.h / 2), $true)
    $items = @(); $t0 = Get-Date
    do {
        Start-Sleep -Milliseconds 500
        $items = @(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $h)) { Nodes $w | Where-Object { $_.shown } })
    } while (-not $items.Count -and ((Get-Date) - $t0).TotalSeconds -lt 10)
    [pscustomobject]@{ result = $c; items = $items }
}
function Names($items) { @($items | ForEach-Object { "$($_.name)$(if ($_.unavailable) { ' (greyed)' })" }) -join ", " }
# Item matching `re` in `items` (a menu's, MSAA order) directly followed by item `next` (empty-named nodes skipped).
function Before($items, [string]$re, [string]$next) {
    $nm = @($items | Where-Object { $_.name } | ForEach-Object { $_.name })
    for ($i = 0; $i -lt $nm.Count - 1; $i++) { if ($nm[$i] -match $re) { return $nm[$i + 1] -eq $next } }
    $false
}
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
    } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    "nothing matching '$re'"
}
function OtherText([IntPtr]$main) { (@(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) { Msaa $w @("-List") | ForEach-Object { "$_".Trim() } }) | Where-Object { $_ }) -join " / " }
# Today tab `title`'s menu (a guarded right-click), its item matching `re` pressed; Escape when there is none -- what the
# owner is told to do when try-c35 could not do it itself.
function TabMenu([string]$title, [string]$re) {
    $n = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "$title*" }) | Select-Object -First 1
    if (-not $n) { return "no Today tab '$title' drawn" }
    $m = [E18Input]::Click($script:main, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds 800
    $r = OtherPress $script:main $re
    if ($r -like "nothing matching*") { $null = Keys "{ESC}" -Any }
    "$m; $r"
}
# Canary's menu from its header: the count it logged, its "Close duplicate tabs..." item, every item -- left open.
function DupMenu {
    $c = Count $menuDup
    $hdr = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x14 -and $_.name -eq "Canary" }) | Select-Object -First 1
    $m = OpenMenu $script:main $hdr
    $logged = WaitLog $menuDup ($c + 1) 10
    $g = Grp $menuDup
    [pscustomobject]@{ result = $m.result; logged = $logged; n = $(if ($logged -and $g.Count) { [int]$g[1] } else { -1 }); items = $m.items
                       item = (@($m.items | Where-Object { $_.name -match '^Close duplicate tabs' }) | Select-Object -First 1); names = (Names $m.items) }
}
function CloseDuplicates($d) {
    if (-not $d.item -or $d.item.unavailable) { $null = Keys "{ESC}" -Any; return [pscustomobject]@{ result = "not pressed"; asked = -1; text = ""; closing = "none" } }
    $ca = Count $askedDup; $cc = Count $closeDup
    $r = OtherPress $script:main '^Close duplicate tabs'
    $asked = WaitLog $askedDup ($ca + 1) 10
    $text = ""; $t0 = Get-Date
    do { Start-Sleep -Milliseconds 500; $text = OtherText $script:main } while ($text -notmatch 'duplicate tab' -and ((Get-Date) - $t0).TotalSeconds -lt 10)
    $ok = OtherPress $script:main '^Close tabs$'
    if ($ok -like "nothing matching*") { $null = Keys "{ESC}" -Any }
    $closing = WaitLog $closeDup ($cc + 1) 10
    $g = Grp $closeDup
    [pscustomobject]@{ result = "$r; $ok"; asked = $(if ($asked) { [int](Grp $askedDup)[1] } else { -1 }); text = $text
                       closing = $(if ($closing -and $g.Count) { "$($g[1]) of $($g[2])" } else { "none" }) }
}

# ---- DevTools (try-c35 starts the dark browser with --remote-debugging-port=0) -------------------------------------
function Base { "http://127.0.0.1:$($script:port)/json" }
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
# A page's short name: "c35x#X-top-copy" for .../c35x.html#X-top-copy (try-c35's #parts hold dashes), "c35home".
function Tag([string]$u) { if ($u -match '/(c35\w+)\.html(?:\?\w+)?(?:#([\w-]+))?$') { "$($Matches[1])$(if ($Matches[2]) { '#' + $Matches[2] })" } else { "" } }
function Tabs([string]$re) { (@(Targets | ForEach-Object { Tag $_.url } | Where-Object { $_ -and $_ -match $re }) | Sort-Object) -join " " }
function WaitTabs([string]$re, [string]$want) {
    $t0 = Get-Date
    do { $now = Tabs $re; if ($now -eq $want) { break }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    $now
}
function WaitTarget([string]$tag) {
    $t0 = Get-Date
    do {
        $t = @(Targets | Where-Object { (Tag $_.url) -eq $tag }) | Select-Object -First 1
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState") -eq "complete") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    $null
}
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
# A plain trusted click on page `t`'s first link (try-c35's C35 home has one, with no id): it navigates in its own tab.
function ClickLink($t) {
    $xy = @(Evaluate $t.webSocketDebuggerUrl "(() => { const r = document.querySelector('a').getBoundingClientRect(); return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]; })()")
    if ($xy.Count -ne 2) { return "no link ($xy)" }
    foreach ($e in @(@{ type = "mousePressed"; buttons = 1 }, @{ type = "mouseReleased"; buttons = 0 })) {
        $r = Cdp $t "Input.dispatchMouseEvent" @{ type = $e.type; x = $xy[0]; y = $xy[1]; button = "left"; buttons = $e.buttons; clickCount = 1 }
        if (-not $r -or $r.error) { return "$($e.type) refused ($(if ($r) { $r.error.message } else { 'no reply' }))" }
    }
    "clicked at $($xy[0]),$($xy[1])"
}

# ---- the files -----------------------------------------------------------------------------------------------------
function PinItem([string]$guid, [string]$id) {
    try { $d = Get-Content -Raw -Encoding UTF8 -LiteralPath "$prof\Default\Workspace Pins" | ConvertFrom-Json } catch { return $null }
    @($d.workspaces.$guid | Where-Object { $_ -and $_.id -eq $id }) | Select-Object -First 1
}
function WaitPin([string]$guid, [string]$id, [string]$url) {
    $t0 = Get-Date
    do { Start-Sleep 1; $i = PinItem $guid $id; if ($i -and $i.url -eq $url) { break } } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    $i
}
function ArchiveEntries {
    $f = "$prof\Default\Workspace Archive"
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    try { @((Get-Content -Raw -Encoding UTF8 -LiteralPath $f | ConvertFrom-Json).entries | Where-Object { $_ }) } catch { @() }
}
function WaitArchive([int]$n) {
    $t0 = Get-Date
    do { Start-Sleep 1; $e = @(ArchiveEntries) } while ($e.Count -lt $n -and ((Get-Date) - $t0).TotalSeconds -lt 15)
    $e
}
# The profile's color_scheme2 as written in its Preferences (a regex: the file is big and the browser rewrites it).
function Scheme { try { $m = [regex]::Match([IO.File]::ReadAllText("$prof\Default\Preferences"), '"color_scheme2":\s*(\d)'); if ($m.Success) { $m.Groups[1].Value } else { "none" } } catch { "unread" } }

# ---- the browser's window ------------------------------------------------------------------------------------------
# The build's browser window (a new one after the restart), polled, then placed 40,40 1400x900 topmost (check-c35's
# Launch): its process and the log it writes ready.
function Found([string]$ready, [int]$s = 60) {
    $t0 = Get-Date
    do {
        $p = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" -and $_.MainWindowHandle -ne [IntPtr]::Zero }) | Select-Object -First 1
        if ($p) { break }
        Start-Sleep 1
    } while (((Get-Date) - $t0).TotalSeconds -lt $s)
    if (-not $p) { return $false }
    $script:bpid = $p.Id; $script:main = $p.MainWindowHandle
    $null = WaitLog $ready 1 30
    [E18Input]::Place($script:main, 40, 40, 1400, 900)
    Start-Sleep 2
    Note "browser $($script:bpid), log $($script:log); session '$env:SESSIONNAME', screen $([E18Input]::Screen() -join 'x'), window dpi $([E18Input]::Dpi($script:main))"
    $true
}
function CloseBrowser { foreach ($hw in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($hw) } }

E18InputType
Add-Type -AssemblyName System.Windows.Forms
if (-not ("C35Fg" -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C35Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } public static IntPtr Front() { return GetForegroundWindow(); } }' }

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
# The runner: the feed piped into cmd, whose pwsh (the owner script, unmodified, no switch) writes straight into $out.
Set-Content -LiteralPath $runner -Encoding utf8 -Value "Get-Content -Wait -LiteralPath '$feed' | cmd /d /c `"pwsh -NoProfile -File $check 1>$out 2>$out.err`""
$child = Start-Process pwsh -ArgumentList @("-NoProfile", "-File", $runner) -WindowStyle Hidden -PassThru
Note "PC: $gate"
Note "owner script started (runner pid $($child.Id)): $(Get-Content -LiteralPath $runner -Raw)"

WaitOut "WORDS USED BELOW" 600
if (-not (Found "pins: drew \d+ row\(s\) of '")) { Bail "no browser window" }

# ---- 1 ------------------------------------------------------------------------------------------------------------
WaitOut " 1. C35 (dark) -- press Shift+Alt+2" 60
Saw "1: the profile's scheme '$(Scheme)' (2: dark)" ((Scheme) -eq "2")
Saw "1: Shift+Alt+2 shows Work" (Go "%+2" $work)
$c = Count "pins: opened item 'a1'"
$r = Press $script:main "Example A"
Saw "1: 'Example A' pressed ($r): 'opened item a1' logged" (WaitLog "pins: opened item 'a1'" ($c + 1) 10)
Saw "1: Shift+Alt+5 shows Unpin" (Go "%+5" $unpin)
# "+ New Tab" read too: an MSAA read that came back empty would also count 0 pinned pages.
$n1 = @(Nodes $script:main)
$rows = @($n1 | Where-Object { $_.shown -and $_.role -eq 0x24 }).Count
$nt1 = @($n1 | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq "New Tab" }).Count
Saw "1: Unpin draws $rows pinned page(s) (want 0; '+ New Tab' read: $($nt1 -gt 0)); THE CARD's look is not measured here (check-c35 C35a/C35c)" ($rows -eq 0 -and $nt1 -gt 0)
Answer "y" "s1"

# ---- 2 ------------------------------------------------------------------------------------------------------------
WaitOut " 2. C31 -- press Shift+Alt+2" 60
$t0 = Get-Date
while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10) { Start-Sleep 1 }
$script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1 -EA SilentlyContinue)
Note "2: DevTools port $($script:port)"
Saw "2: Shift+Alt+2 shows Work" (Go "%+2" $work)
$c = Count "pins: opened item 'c35p'"
$r = Press $script:main "C35 home"
$opened = WaitLog "pins: opened item 'c35p'" ($c + 1) 10
$homePage = WaitTarget "c35home"
Start-Sleep 1
$m = OpenMenu $script:main (RowNode "C35 home")
$null = Keys "{ESC}" -Any
$items = @($m.items | ForEach-Object { $_.name })
Saw "2: 'C35 home' pressed ($r; opened: $opened; its page loaded: $([bool]$homePage)); its menu ($($m.result)): $(Names $m.items) -- Close page, no '$replace'" ($opened -and $homePage -and ($items -contains "Close page") -and -not ($items -contains $replace))
Answer "y" "s2"

# ---- 3 ------------------------------------------------------------------------------------------------------------
WaitOut ' 3. On the "C35 home" page, click the link' 60
$awayUrl = "$((Targets | Where-Object { (Tag $_.url) -eq 'c35home' } | Select-Object -First 1).url)" -replace 'c35home\.html$', 'c35away.html'
$link = if ($homePage) { ClickLink $homePage } else { "no page to click in" }
$away = WaitTarget "c35away"
$back = WaitNode "Back to the pinned page" 0x2B $true
Saw "3: the link ($link): the page now $(if ($away) { $away.url } else { 'not c35away' }); the back arrow shows: $back" ($away -and $back)
$m = OpenMenu $script:main (RowNode "C35 home")
$offered = @($m.items | Where-Object { $_.name -eq $replace }).Count -gt 0
Saw "3: the menu ($($m.result)): $(Names $m.items) -- '$replace' right above 'Unpin'" ($offered -and (Before $m.items "^$replace$" 'Unpin'))
$ct = Count $took
$p = if ($offered) { OtherPress $script:main "^$replace$" } else { $null = Keys "{ESC}" -Any; "not offered" }
$logged = WaitLog $took ($ct + 1) 10
$item = WaitPin $work "c35p" $awayUrl
$gone = WaitNode "Back to the pinned page" 0x2B $false
$renamed = WaitNode "C35 away" 0x24 $true
Saw "3: pressed ($p): '$took' logged: $logged; the pins file: url '$($item.url)' title '$($item.title)' (want '$awayUrl', 'C35 away'); the back arrow gone: $gone; the pinned page reads 'C35 away': $renamed" ($logged -and $item -and $item.url -eq $awayUrl -and $item.title -eq "C35 away" -and $gone -and $renamed)
$m2 = OpenMenu $script:main (RowNode "C35 away")
$null = Keys "{ESC}" -Any
$again = @($m2.items | Where-Object { $_.name -eq $replace }).Count -gt 0
Saw "3: its menu again ($($m2.result)): $(Names $m2.items) -- no '$replace'" ($m2.items.Count -and -not $again)
Answer "y" "s3"

# ---- 4 ------------------------------------------------------------------------------------------------------------
WaitOut " 4. C32 -- press Shift+Alt+3" 60
Saw "4: Shift+Alt+3 shows Canary" (Go "%+3" $canary)
WaitOut "Done. Canary now has" 120
$o = OutText
Saw "4: try-c35 opened all 6 tabs" (-not $o.Contains("The script opened only"))
if ($o.Contains("could not make 'F favorite' a FAVORITE")) {
    Saw "4: try-c35 could not make 'F favorite' a FAVORITE itself; by hand: $(TabMenu 'F favorite' '^Add to Favorites')" $false
}
Start-Sleep 1
$titles = '^(X top copy|X used last|Y copy of pinned|F copy of favorite|Z only one|F favorite)'
$tabNodes = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x25 })
# The favorite's name ends " - Pinned" (case-sensitive: -notmatch 'Pinned' would also drop "Y copy of pinned").
$order = (@($tabNodes | Where-Object { $_.name -match $titles -and $_.name -cnotmatch ' - Pinned$' } | Sort-Object t | ForEach-Object { if ($_.name -match $titles) { $Matches[1] } }) -join " / ")
$fav = @($tabNodes | Where-Object { $_.name -clike "F favorite*Pinned*" }).Count -gt 0
Saw "4: the TODAY TABS drawn top to bottom: $order (try-c35 says: X top copy / X used last / Y copy of pinned / F copy of favorite / Z only one)" ($order -eq "X top copy / X used last / Y copy of pinned / F copy of favorite / Z only one")
Saw "4: 'F favorite' is a FAVORITE (a page tab named 'F favorite ... Pinned')" $fav
$ae = @(ArchiveEntries).Count
$d = DupMenu
Saw "4: the workspace menu ($($d.result)) logged $($d.n) (want 3): $($d.names) -- 'Close duplicate tabs...' enabled, right above 'Close all tabs'" ($d.n -eq 3 -and $d.item -and -not $d.item.unavailable -and (Before $d.items '^Close duplicate tabs' "Close all tabs"))
$x = CloseDuplicates $d
$listed = @("F copy of favorite", "Y copy of pinned", "X top copy" | Where-Object { $x.text.Contains($_) }).Count
Saw "4: pressed ($($x.result)): asked $($x.asked), the box '$($x.text)' ($listed of the 3 titles), closing $($x.closing)" ($x.asked -eq 3 -and $x.text.Contains("Close 3 duplicate tabs?") -and $listed -eq 3 -and -not $x.text.Contains("X used last") -and $x.text.Contains("They stay in the Archive.") -and $x.closing -eq "3 of 3")
$left = WaitTabs '^c35[xyfz]' "c35f#F-favorite c35x#X-used-last c35z#Z-only-one"
Saw "4: open now $left (want c35f#F-favorite c35x#X-used-last c35z#Z-only-one)" ($left -eq "c35f#F-favorite c35x#X-used-last c35z#Z-only-one")
$arch = @(WaitArchive ($ae + 3))
$archTags = (@($arch | Where-Object { $_.workspace -eq $canary } | ForEach-Object { Tag $_.url } | Where-Object { $_ }) | Sort-Object) -join " "
Saw "4: the Archive file $ae -> $($arch.Count) entries, Canary's: $archTags (want c35f#F-copy-of-favorite c35x#X-top-copy c35y#Y-copy-of-pinned)" ($arch.Count -eq $ae + 3 -and $archTags -eq "c35f#F-copy-of-favorite c35x#X-top-copy c35y#Y-copy-of-pinned")
# The bar's Archive button (the lowest "Archive" push button), the screen: the window with "Search archive".
$ab = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq "Archive" } | Sort-Object t) | Select-Object -Last 1
$r = if ($ab) { Press $script:main "Archive" 0x2B } else { "no Archive button drawn" }
$screen = [IntPtr]::Zero; $sn = @(); $t0 = Get-Date
do {
    Start-Sleep -Milliseconds 500
    foreach ($w in [E18Input]::Others([uint32]$script:bpid, $script:main)) { $n = @(Nodes $w | Where-Object { $_.shown }); if (@($n | Where-Object { $_.name -eq "Search archive" }).Count) { $screen = $w; $sn = $n } }
} while ($screen -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 10)
$tops = @($sn | Where-Object { $_.name -match '^(F copy of favorite|Y copy of pinned|X top copy|X used last|Z only one|F favorite|V )' } | Sort-Object t | Select-Object -First 3 | ForEach-Object { $_.name })
$three = @("F copy of favorite", "Y copy of pinned", "X top copy" | Where-Object { $n3 = $_; @($tops | Where-Object { $_ -like "$n3*" }).Count }).Count
Saw "4: the Archive button ($r): the screen opened: $($screen -ne [IntPtr]::Zero); its top test rows: $($tops -join ' / ') ($three of the 3)" ($screen -ne [IntPtr]::Zero -and $three -eq 3)
if ($screen -ne [IntPtr]::Zero) {
    # A click outside it: the bottom middle of the page; Esc when something else is at that point.
    $r = [E18Input]::Click($script:main, 740, 900, $false)
    Start-Sleep 1
    if (@([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $_ -eq $screen }).Count) { $r += "; Esc: $(Keys '{ESC}' -Any)"; Start-Sleep 1 }
    Saw "4: the screen closed ($r)" (-not @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $_ -eq $screen }).Count)
}
Answer "y" "s4"

# ---- 5 ------------------------------------------------------------------------------------------------------------
WaitOut " 5. Open THE WORKSPACE MENU again" 60
$d = DupMenu
$null = Keys "{ESC}" -Any
Saw "5: the menu ($($d.result)) logged $($d.n) (want 0), its item $(if ($d.item) { if ($d.item.unavailable) { 'greyed' } else { 'NOT greyed' } } else { 'missing' }): $($d.names)" ($d.logged -and $d.n -eq 0 -and $d.item -and $d.item.unavailable)
Answer "y" "s5"

# ---- 6 ------------------------------------------------------------------------------------------------------------
WaitOut " 6. A tab in a tab group is never closed as a copy" 60
Saw "6: Canary still shown" (Go "%+3" $canary)
WaitOut "If a small box to name the group is open, press Esc." 120
if ((OutText).Contains("could not put 'V in a group' in a group")) {
    Saw "6: try-c35 could not group 'V in a group' itself; by hand: $(TabMenu 'V in a group' '^Add tab to new group$')" $false
    Start-Sleep 2
}
# The group's name box, closed: Esc to it -- or, when no browser window is in front, a click outside it on the page.
# Checked again after the Esc: a box left open (the Esc went to the page) would answer DupMenu's right-click in its place.
if (@([E18Input]::Others([uint32]$script:bpid, $script:main)).Count) {
    $r = Keys "{ESC}" -Any
    Start-Sleep 1
    if (@([E18Input]::Others([uint32]$script:bpid, $script:main)).Count) { $r += "; still open, a click on the page: $([E18Input]::Click($script:main, 740, 900, $false))"; Start-Sleep 1 }
    Note "6: the group's name box: $r; browser windows still open besides the main one: $(@([E18Input]::Others([uint32]$script:bpid, $script:main)).Count)"
}
$grouped = @(Nodes $script:main | Where-Object { $_.shown -and $_.name -match '^ ?unnamed group - .*V in a group' }).Count
Saw "6: 'V in a group' is in a tab group ($grouped header(s) naming it)" ($grouped -gt 0)
$d = DupMenu
Saw "6: the menu ($($d.result)) logged $($d.n) (want 1): $($d.names)" ($d.n -eq 1 -and $d.item -and -not $d.item.unavailable)
$x = CloseDuplicates $d
Saw "6: pressed ($($x.result)): asked $($x.asked), the box '$($x.text)', closing $($x.closing)" ($x.asked -eq 1 -and $x.text.Contains("Close 1 duplicate tab?") -and $x.text.Contains("V loose copy") -and -not $x.text.Contains("V in a group") -and $x.closing -eq "1 of 1")
$v = WaitTabs '^c35v' "c35v#V-in-a-group"
$still = @(Nodes $script:main | Where-Object { $_.shown -and $_.name -match '^ ?unnamed group - .*V in a group' }).Count
Saw "6: open now $v (want c35v#V-in-a-group), still in its group: $($still -gt 0)" ($v -eq "c35v#V-in-a-group" -and $still -gt 0)
Answer "y" "s6"

# ---- the light restart, 7 -----------------------------------------------------------------------------------------
WaitOut "Now close the test browser" 60
CloseBrowser
Note "-: the window(s) closed (WM_CLOSE)"
WaitOut " 7. C35 (light) -- press Shift+Alt+2" 180
$o = OutText
if ($o.Contains("Could not switch the copy to light mode")) { Saw "7: try-c35 switched the copy to light mode" $false }
$script:log = $logs[1]
if (-not (Found "pins: drew \d+ row\(s\) of '")) { Bail "no browser window after the restart" }
Saw "7: the profile's scheme '$(Scheme)' (1: light)" ((Scheme) -eq "1")
Saw "7: Shift+Alt+2 shows Work" (Go "%+2" $work)
$rows = @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x24 }).Count
Saw "7: Work draws $rows pinned page(s) (want some); THE CARD's look is not measured here (check-c35 C35b)" ($rows -gt 0)
Answer "y" "s7"
WaitOut "Close the test browser. This window then grades the run." 30
CloseBrowser
Note "-: the window(s) closed (WM_CLOSE)"
$t0 = Get-Date
while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*") -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 }
# try-c35 reads the comment only once every process of the build has ended (WaitClosed).
Saw "-: the test browser closed" (-not (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like "$bin\*"))
# One line: a line break in it would be read as a second answer.
Answer ($(if ($script:bad.Count) { "driver saw NOT OK: " + ($script:bad -join ' / ') } else { "rehearsal driver, not the owner: every step seen" }) -replace '[\r\n]+', ' ') "the comment"

$t = Get-Date
while (-not ((OutText) -match $doneRe) -and ((Get-Date) - $t).TotalSeconds -lt 120) { Start-Sleep 1 }
$said = (OutText) -split "`r?`n"
Note "--- the owner script said ---"
$said | Where-Object { $_ -match '^(PASS|FAIL|RESULT|STOPPED)|your answers:|seeding:|^\s+log: |opened only|could not' } | ForEach-Object { Note "  | $_" }
if ((Test-Path "$out.err") -and (Get-Item "$out.err").Length) { Note "--- its stderr ---"; Get-Content "$out.err" | Select-Object -First 15 | ForEach-Object { Note "  ! $_" } }
Finish
$pass = [bool]@($said | Where-Object { $_ -match "^$doneRe .*verdict=PASS" }).Count
Note "REHEARSAL: the owner script $(if ($pass) { 'PASSED' } else { 'did NOT pass' }); the driver saw $($script:bad.Count) thing(s) NOT OK"
if ($pass -and -not $script:bad.Count) { exit 0 } else { exit 1 }
