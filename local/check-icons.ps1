param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "icons", [double]$IdleMinutes = 15)
# Patches 78-79 -- a pinned page's icon -- on a throwaway copy of the smoke profile (Sessions emptied), seeded by
# icons-seed.py before the start: at the top of Home, "Icon red" (a local page whose own icon is solid red, never
# visited: no icon is known for it) and "Icon site" (https://icons.test/never, never opened; the icon database holds
# the made-up site twice -- an old BLUE icon for http://icons.test/old, mapped first, and a newer GREEN one for
# https://icons.test/new). The owner's report, 10-19: an open pinned page kept the globe it was drawn with, and many
# pages of one site showed its 2010s logo. Colors are read off the screen in the row's icon box (MSAA's box, the ring's
# edges left out), with --force-color-profile=srgb (this PC's display has HDR on, LOCAL.md 90).
#   I0  before anything opens: "Icon red" draws no red (the globe) -- the precondition.
#   I4  "Icon site" draws GREEN, not blue: the host fallback's tie goes to the page mapped last (79).
#   I1  "Icon red" pressed: its page loads and the row turns RED -- the open page lends its icon (78).
#   I3  the page follows its link to iconblue.html (a BLUE icon): the back arrow shows and the row stays RED -- a page
#       gone elsewhere leaves the item's icon.
#   I2  "Close page": the page closes and the row stays RED -- the icon is kept while it sleeps.
#   Z   0 crash markers (case-sensitive, DanglingPtr too).
# MSAA presses and DevTools clicks only, no keys; the window is placed topmost. It starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (-IdleMinutes 0 when the owner is away). Run it in its own process:
#   pwsh -File local\check-icons.ps1 [-Build Dcheck] [-IdleMinutes 0]
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$Build"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = "$ws\$Tag$suffix-run.log"
$pages  = "$ws\$Tag-pages"
$slow   = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total  = 6
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:port = 0; $script:main = [IntPtr]::Zero
$script:srv = $null
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Msaa([object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$script:main) @a }
function Press([string]$name, [int]$role) { "$(Msaa @('-Name', $name, '-Role', $role))" }
function Nodes { @(ParseMsaaNodes @(Msaa @("-List", "-Rect"))) }
function RowNode([string]$name) { @(Nodes | Where-Object { $_.shown -and $_.role -eq 0x24 -and $_.name -eq $name }) | Select-Object -Last 1 }
function WaitNode([string]$name, [int]$role) {
    $t0 = Get-Date
    do {
        if (@(Nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name }).Count) { return $true }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $false
}

# ---- DevTools (the pages) ------------------------------------------------------------------------------------------
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "http://127.0.0.1:$($script:port)/json/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
# The open page iconred.html / iconblue.html once loaded, or $null.
function WaitTarget([string]$name) {
    $t0 = Get-Date
    do {
        $t = @(Targets | Where-Object { $_.url -like "*/$name.html" }) | Select-Object -First 1
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState") -eq "complete") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
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
# A plain click on link `id` of page `t` through DevTools (trusted input, a real click's road: check-c35's ClickLink).
function ClickLink($t, [string]$id) {
    $xy = @(Evaluate $t.webSocketDebuggerUrl "(() => { const r = document.getElementById('$id').getBoundingClientRect(); return [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)]; })()")
    if ($xy.Count -ne 2) { return "no link '$id' ($xy)" }
    foreach ($e in @(@{ type = "mousePressed"; buttons = 1 }, @{ type = "mouseReleased"; buttons = 0 })) {
        $r = Cdp $t "Input.dispatchMouseEvent" @{ type = $e.type; x = $xy[0]; y = $xy[1]; button = "left"; buttons = $e.buttons; clickCount = 1 }
        if (-not $r -or $r.error) { return "$($e.type) refused ($(if ($r) { $r.error.message } else { 'no reply' }))" }
    }
    "clicked at $($xy[0]),$($xy[1])"
}

# ---- pixels --------------------------------------------------------------------------------------------------------
# The colour row `name` draws its icon in: "red", "green", "blue" (over 40 pixels of it in the icon box), else "none"
# -- the globe, drawn in the text's grey, or nothing. The box: the row's left 60 px less 4 px all round (the page in
# front's ring is drawn on the row's edge, in its workspace's colour). With the counts, the box and a capture.
function IconColor([string]$name, [string]$png) {
    $res = [pscustomobject]@{ color = "unread"; text = "" }
    $row = RowNode $name
    if (-not $row) { $res.text = "no row '$name' shown"; return $res }
    $x0 = $row.l + 4; $y0 = $row.t + 4; $w = [Math]::Min(56, $row.w - 8); $h = $row.h - 8
    if ($w -le 0 -or $h -le 0) { $res.text = "row '$name' too small: $($row.w)x$($row.h)"; return $res }
    [IconsFg]::Aware()
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $g.CopyFromScreen($x0, $y0, 0, 0, $bmp.Size) } finally { $g.Dispose() }
        $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $red = 0; $green = 0; $blue = 0
        for ($y = 0; $y -lt $h; $y++) {
            for ($x = 0; $x -lt $w; $x++) {
                $c = $bmp.GetPixel($x, $y)
                if ($c.R -ge 200 -and $c.G -le 70 -and $c.B -le 70) { $red++ }
                elseif ($c.G -ge 150 -and $c.R -le 70 -and $c.B -le 70) { $green++ }
                elseif ($c.B -ge 200 -and $c.R -le 70 -and $c.G -le 70) { $blue++ }
            }
        }
    } finally { $bmp.Dispose() }
    $best = @(@{ n = "red"; c = $red }, @{ n = "green"; c = $green }, @{ n = "blue"; c = $blue } | Sort-Object { $_.c } -Descending)[0]
    $res.color = if ($best.c -gt 40) { $best.n } else { "none" }
    $res.text = "'$name' draws $($res.color) (red $red, green $green, blue $blue pixels in ${w}x$h at $x0,$y0; the window in front: $([IconsFg]::Front() -eq $script:main); capture $png)"
    $res
}
# The row's colour, polled until it is `want` (the icon arrives after the load): the last reading.
function WaitColor([string]$name, [string]$want, [string]$png, [int]$s = 10) {
    $t0 = Get-Date
    do { $c = IconColor $name $png; if ($c.color -eq $want) { break }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow)
    $c
}

# ---- one start of the browser, and its quit ------------------------------------------------------------------------
function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($script:main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port), pages on port $($script:srv.port), log $log; session '$env:SESSIONNAME', screen $([E18Input]::Screen() -join 'x'), window dpi $([E18Input]::Dpi($script:main))"
}
function Quit {
    if (-not ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue))) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Get-Process -Id $script:bpid -EA SilentlyContinue)
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' })$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

# ==== the run =======================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "icon_mapping.id DESC"
$with = if ($LASTEXITCODE -eq 0) { "WITH" } else { "WITHOUT" }
Say "build: $Build\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $with patch 79's tie-break (78 logs nothing: I1-I2 are its check)"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class IconsFg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c); public static IntPtr Front() { return GetForegroundWindow(); } public static void Aware() { SetThreadDpiAwarenessContext(new IntPtr(-4)); } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$script:srv = ServePages $pages @("iconred", "iconblue")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
# Over ServePages' plain pages: each its own icon; iconred links to iconblue.
Set-Content -Encoding ASCII -LiteralPath "$pages\iconred.html" -Value "<!doctype html><title>E18 iconred</title><link rel=icon href=red.png><h1>E18 iconred</h1><p><a id='next' href='iconblue.html'>next</a>"
Set-Content -Encoding ASCII -LiteralPath "$pages\iconblue.html" -Value "<!doctype html><title>E18 iconblue</title><link rel=icon href=blue.png><h1>E18 iconblue</h1>"
& python -I "$here\icons-seed.py" $prof $pages $script:srv.port | ForEach-Object { Say "seed: $_" }
if ($LASTEXITCODE -ne 0) { Abort "the profile was not seeded" }
$shot = "$ws\$Tag$suffix"

try {
    Launch
    $i0 = WaitColor "Icon red" "none" "$shot-i0.png" 3
    Verdict "I0 before anything opens: $($i0.text) (want none: the globe)" ($i0.color -eq "none")

    $i4 = WaitColor "Icon site" "green" "$shot-i4.png" 5
    Verdict "I4 a page never opened, its icon by the host fallback: $($i4.text) (want green, the page mapped last; blue = the old icon)" ($i4.color -eq "green")

    $c = Count "pins: opened item 'icr'"
    $r = Press "Icon red" 0x24
    $opened = WaitLog "pins: opened item 'icr'" ($c + 1) 10
    $page = WaitTarget "iconred"
    $i1 = WaitColor "Icon red" "red" "$shot-i1.png" 10
    Verdict "I1 'Icon red' pressed ($r; opened: $opened; its page loaded: $([bool]$page)): $($i1.text) (want red: the open page's own icon)" ($opened -and $page -and $i1.color -eq "red")

    $link = if ($page) { ClickLink $page "next" } else { "no page to click in" }
    $away = WaitTarget "iconblue"
    $back = WaitNode "Back to the pinned page" 0x2B
    # The blue icon's own time to arrive, then the row read: it must not have followed.
    Start-Sleep (3 * $slow)
    $i3 = IconColor "Icon red" "$shot-i3.png"
    Verdict "I3 its link ($link; the page now: $(if ($away) { $away.url } else { 'not iconblue' })), the back arrow showed: ${back}: $($i3.text) (want red: a page gone elsewhere leaves the item's icon)" ($away -and $back -and $i3.color -eq "red")

    $p = Press "Close page" 0x2B
    $t0 = Get-Date
    do { Start-Sleep -Milliseconds 500; $open = @(Targets | Where-Object { $_.url -like "*/icon*.html" }).Count } while ($open -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    Start-Sleep (1 * $slow)
    $i2 = IconColor "Icon red" "$shot-i2.png"
    Verdict "I2 'Close page' pressed ($p; its pages still open: $open): $($i2.text) (want red: kept while it sleeps)" ($open -eq 0 -and $i2.color -eq "red")
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
# Case-sensitive, as LOCAL.md grades (LOCAL.md 86, 90).
$markers = 0
if (Test-Path -LiteralPath $log) { $markers = @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count }
Verdict "Z crash markers in $log (the quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$verdict"
Say "check-icons ${Build}: $($script:passed)/$total, crash markers $markers"
exit [int]($verdict -eq "FAIL")
