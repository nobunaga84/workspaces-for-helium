param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "c13", [switch]$Zen,
      [double]$IdleMinutes = 15)
# C13 + C22 a-c (patch 61): the new shortcuts, pressed for real on a throwaway copy of the smoke profile (Home, Work,
# Canary, Private, Unpin; Sessions emptied). Real keys need the browser in front and the screen unlocked, so it
# starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (a person starting it passes -IdleMinutes 0 and lets
# go of the mouse). -Zen first turns on zen mode with the sidebar unpinned -- the daily browser's setting.
#   A. Shift+Alt+2 shows Work, +1 Home, +0 Work again (back), +0 Home again, +6 nothing (5 workspaces), +3 Canary,
#      +2 Work for the rest.
#   B. "E18 p1" opened: Shift+Alt+D pins it, again unpins it (the same item), again pins it; Ctrl+T then Shift+Alt+D
#      on the New Tab page: refused.
#   C. "E18 c1".."c3" opened: Shift+Alt+K closes the Today tabs and keeps the open pinned page (DevTools' page list).
#   D. 27 pages opened: Shift+Alt+K asks first, the confirm centred over the page; Escape cancels and nothing closes;
#      again + Enter closes them, and the pinned page stays open.
#   E. Shift+Alt+H opens the Archive centred over the page; Escape closes it.
#   F. chrome://settings/system/shortcuts lists all 19 of the fork's command names (hook shrink part 3 moved them to
#      workspace_command_hooks.cc; DevTools' page text; a screenshot too, read by eye).
# A pass needs every row, and 0 crash markers in the log. Run it in its own process (pwsh -File): it compiles C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($Zen) { '-zen' })$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = if ($OutDir -eq "Dcheck") { "$ws\$Tag$(if ($Zen) { '-zen' })-dcheck-exercise.log" } else { "$ws\$Tag$(if ($Zen) { '-zen' })-run.log" }
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$names  = @("Next workspace", "Previous workspace", "New workspace", "Move workspace up", "Move workspace down") +
          @(1..9 | ForEach-Object { "Workspace $_" }) +
          @("Back to the last workspace", "Pin or unpin this page", "Clear Today", "Open the Archive", "Find tabs and pages")
$script:failed = 0; $script:passed = 0; $script:bpid = 0
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
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Names([IntPtr]$h) { @(Msaa $h @("-List") | ForEach-Object { if ($_ -match '^\s*(.*?)\|0x') { $Matches[1] } }) }
# Keys to the browser's window in front, through SendKeys ("%+2" is Shift+Alt+2) -- never to another window.
function Keys([string]$k) {
    if ([C13Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
function Url([string]$n) { "http://127.0.0.1:$($script:srv.port)/$n" }
function Open([string[]]$urls) { Start-Process $exe -ArgumentList (@("--user-data-dir=$prof") + $urls) | Out-Null }
# The pages the browser holds, from DevTools' list: their addresses.
function Pages { try { @(Invoke-RestMethod -TimeoutSec 10 "http://127.0.0.1:$($script:port)/json/list" | Where-Object { $_.type -eq "page" } | ForEach-Object { $_.url }) } catch { @() } }
function Has([string]$page) { @(Pages | Where-Object { $_ -like "*/$page*" }).Count }
# The browser's other window (a bubble) whose MSAA names include `name`, polled.
function Bubble([IntPtr]$main, [string]$name) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) { if ((Names $w) -contains $name) { return $w } }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    [IntPtr]::Zero
}
# Where bubble `b`'s centre sits in the main window's client area, as fractions of its width and height. Centred over
# the page means right of the middle (the sidebar is on the left) and well inside; the bar's Archive button is low left.
function Centre([IntPtr]$main, [IntPtr]$b) {
    $m = [E18Input]::Client($main); $c = [E18Input]::Client($b)
    [pscustomobject]@{ x = ($c[0] + $c[2] / 2 - $m[0]) / $m[2]; y = ($c[1] + $c[3] / 2 - $m[1]) / $m[3] }
}
function IsCentred($f) { $f.x -gt 0.35 -and $f.x -lt 0.8 -and $f.y -gt 0.3 -and $f.y -lt 0.75 }
function Shot([IntPtr]$h, [string]$path) {
    Add-Type -AssemblyName System.Drawing
    $c = [E18Input]::Client($h)
    $bmp = New-Object System.Drawing.Bitmap ([int]$c[2]), ([int]$c[3])
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen([int]$c[0], [int]$c[1], 0, 0, $bmp.Size); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $g.Dispose(); $bmp.Dispose() }
    $path
}
$active = "\[workspaces\] active workspace -> '([^']*)'"
function Jump([string]$k, [string]$guid, [string]$row) {
    $c = Count $active
    $r = Keys $k
    $ok = (WaitLog $active ($c + 1) 5) -and (Last $active).Groups[1].Value -eq $guid
    Verdict "$row ($k -> '$guid'; $r)" $ok
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'shortcut: clear Today')>=0 else 1)" "$bin\chrome.dll"
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 61"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real keys ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C13Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
if ($Zen) { & python "$here\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
$many = @(1..27 | ForEach-Object { "many.html?i=$_" })
$script:srv = ServePages "$ws\$Tag-pages" @("p1", "c1", "c2", "c3", "many")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
Remove-Item -LiteralPath $log -EA SilentlyContinue
try {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check")).Id
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port)$(if ($Zen) { ', zen mode, sidebar unpinned' })"

    # A. C13: workspace N, and back.
    Jump "%+2" $work "A1 Shift+Alt+2 shows Work"
    Jump "%+1" "default" "A2 Shift+Alt+1 shows Home"
    Jump "%+0" $work "A3 Shift+Alt+0 goes back to Work"
    Jump "%+0" "default" "A4 Shift+Alt+0 again goes back to Home"
    $c = Count $active; $r = Keys "%+6"; Start-Sleep 3
    Verdict "A5 Shift+Alt+6 does nothing with 5 workspaces ($r)" ((Count $active) -eq $c)
    Jump "%+3" $canary "A6 Shift+Alt+3 shows Canary"
    Jump "%+2" $work "A7 Shift+Alt+2 shows Work again"

    # B. C22 (a): pin, unpin, pin; a New Tab page is refused.
    $ins = "tab inserted at index \d+ -> workspace '$work'"
    $c = Count $ins; Open @(Url "p1.html"); $null = WaitLog $ins ($c + 1); Start-Sleep (2 * $slow)
    $pinned = "pins: pinned a tab as item '([^']+)'"
    $c = Count $pinned; $r = Keys "%+d"
    $ok = WaitLog $pinned ($c + 1) 5; $id = if ($ok) { (Last $pinned).Groups[1].Value } else { "" }
    Verdict "B1 Shift+Alt+D pins the Today tab 'E18 p1' (item '$id'; $r)" $ok
    $c = Count "pins: unpinned item '$id'"; $r = Keys "%+d"
    Verdict "B2 Shift+Alt+D again unpins it ($r)" (WaitLog "pins: unpinned item '$id'" ($c + 1) 5)
    $c = Count $pinned; $r = Keys "%+d"
    Verdict "B3 Shift+Alt+D pins it again ($r)" (WaitLog $pinned ($c + 1) 5)
    $refused = "shortcut: pin -- the page in front cannot be pinned"
    $c = Count $refused; $r = "Ctrl+T $(Keys '^t'); Shift+Alt+D $(Keys '%+d')"
    Verdict "B4 a New Tab page is not pinned ($r)" (WaitLog $refused ($c + 1) 5)

    # C. C22 (b): Clear Today keeps the open pinned page.
    $c = Count $ins; Open @((Url "c1.html"), (Url "c2.html"), (Url "c3.html")); $null = WaitLog $ins ($c + 3); Start-Sleep (2 * $slow)
    $before = "c1=$(Has 'c1.html') c2=$(Has 'c2.html') c3=$(Has 'c3.html') p1=$(Has 'p1.html')"
    $closing = "closing (\d+) tab\(s\) of workspace '$work' in this window, \d+ pinned kept, pinned pages kept \(Clear Today\)"
    $c = Count $closing; $r = Keys "%+k"
    $ok = WaitLog $closing ($c + 1) 5; Start-Sleep (2 * $slow)
    $after = "c1=$(Has 'c1.html') c2=$(Has 'c2.html') c3=$(Has 'c3.html') p1=$(Has 'p1.html')"
    Verdict "C1 Shift+Alt+K closes c1..c3 and keeps the pinned page open ($r; before $before; after $after)" ($ok -and $before -eq "c1=1 c2=1 c3=1 p1=1" -and $after -eq "c1=0 c2=0 c3=0 p1=1")

    # D. Above 25 tabs it asks first, centred over the page.
    $c = Count $ins; Open @($many | ForEach-Object { Url $_ }); $null = WaitLog $ins ($c + 27) 60; Start-Sleep (3 * $slow)
    $asked = "confirm asked: clear Today of workspace '$work', (\d+) tab\(s\)"
    $c = Count $asked; $r = Keys "%+k"
    $ok = WaitLog $asked ($c + 1) 5; $n = if ($ok) { [int](Last $asked).Groups[1].Value } else { 0 }
    $b = Bubble $main "Close all tabs"
    $f = if ($b -ne [IntPtr]::Zero) { Centre $main $b } else { $null }
    Verdict "D1 Shift+Alt+K with $(Has 'many.html') of 27 pages asks first ($n tabs; $r)" ($ok -and $n -gt 25)
    Verdict "D2 the confirm is centred over the page ($(if ($f) { 'at {0:N2}, {1:N2}' -f $f.x, $f.y } else { 'no confirm window' }))" ($f -and (IsCentred $f))
    # Only the Cancel button logs "confirm cancelled"; Escape closes the bubble without it.
    $r = Keys "{ESC}"; Start-Sleep (2 * $slow)
    $gone = (Bubble $main "Close all tabs") -eq [IntPtr]::Zero
    Verdict "D3 Escape closes the confirm and closes nothing ($r; confirm gone: $gone; $(Has 'many.html') pages)" ($gone -and (Has 'many.html') -eq 27)
    $c = Count $closing; $r = "Shift+Alt+K $(Keys '%+k'); Enter $(if ((Bubble $main 'Close all tabs') -ne [IntPtr]::Zero) { Keys '{ENTER}' } else { 'no confirm' })"
    $ok = WaitLog $closing ($c + 1) 10; Start-Sleep (3 * $slow)
    Verdict "D4 again + Enter closes them and keeps the pinned page ($r; many=$(Has 'many.html') p1=$(Has 'p1.html'))" ($ok -and (Has 'many.html') -eq 0 -and (Has 'p1.html') -eq 1)

    # E. C22 (c): the Archive, centred over the page.
    $c = Count "shortcut: archive"; $r = Keys "%+h"
    $ok = WaitLog "shortcut: archive" ($c + 1) 5
    $b = Bubble $main "Archive"
    $f = if ($b -ne [IntPtr]::Zero) { Centre $main $b } else { $null }
    $shot = Shot $main "$ws\$Tag$suffix-archive.png"
    Verdict "E1 Shift+Alt+H opens the Archive ($r)" ($ok -and $b -ne [IntPtr]::Zero)
    Verdict "E2 the Archive is centred over the page ($(if ($f) { 'at {0:N2}, {1:N2}' -f $f.x, $f.y } else { 'no Archive window' }); $shot)" ($f -and (IsCentred $f))
    $r = Keys "{ESC}"; Start-Sleep (2 * $slow)
    Verdict "E3 Escape closes it ($r)" ((Bubble $main "Archive") -eq [IntPtr]::Zero)

    # F. The names on the shortcuts page: its text, read through DevTools into every shadow root (MSAA does not reach
    # into the page).
    $page = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "http://127.0.0.1:$($script:port)/json/new?chrome://settings/system/shortcuts" } catch { $null }
    Start-Sleep (6 * $slow)
    $deep = "(() => { const out = []; const walk = n => { if (n.shadowRoot) walk(n.shadowRoot); for (const c of n.children || []) walk(c); if (n.children && !n.children.length && n.textContent) out.push(n.textContent.trim()); }; walk(document.documentElement); return out.join('|'); })()"
    $text = if ($page) { "$(Evaluate $page.webSocketDebuggerUrl $deep)" } else { "" }
    $found = @($names | Where-Object { $text.Contains($_) })
    $shot = Shot $main "$ws\$Tag$suffix-shortcuts.png"
    Verdict "F1 the shortcuts page names $($found.Count) of $($names.Count): $($found -join ', ') ($shot)" ($found.Count -eq $names.Count)
} catch {
    Say "ERROR: $_"; $script:failed++
} finally {
    if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    }
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = Count "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling"
Verdict "Z crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
