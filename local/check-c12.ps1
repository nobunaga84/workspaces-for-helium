param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "c12", [double]$IdleMinutes = 15)
# C12 + C30 + C24 + C26 (patch 62), on a throwaway copy of the smoke profile (every workspace holds Example A, "Smoke
# folder" (open: Wikipedia + one more), "Closed folder" (Hidden), Example D; Sessions emptied). Real clicks, a drag and
# keys -- so it starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (a person starting it passes
# -IdleMinutes 0 and lets go of the mouse). Everything happens in Work (Shift+Alt+2), never Home.
#   C12  "Closed folder" opened, "Hidden" pressed (its page opens, in front), the folder closed again: a peek row
#        "Hidden" is drawn under it; its menu has "Close page" and no "New folder"; Close page closes the page and the
#        peek row goes.
#   C26  "Example A" pressed (its page opens): the pixels of its x's place differ between the mouse away and the
#        mouse over the row, and are the same again once away; MSAA still names "Close page" on the open row.
#   C30  "Example D" deleted from its menu: 1 archived; the Archive (Shift+Alt+H) lists it; "Smoke folder" deleted
#        (its confirm, its new text): 2 archived.
#   C24  Shift+Alt+S makes an empty workspace; a web page opened there is dragged onto its header: pinned.
# A pass needs every row and 0 crash markers. Run it in its own process (pwsh -File): it compiles C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = if ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise.log" } else { "$ws\$Tag-run.log" }
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
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
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
# Every MSAA node of window `h`: name, role, box (physical pixels), shown (not INVISIBLE, a box with size).
function Nodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Rect") | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); l = [int]$Matches[4]; t = [int]$Matches[5]
                               w = [int]$Matches[6]; h = [int]$Matches[7]; shown = (-not $Matches[3]) -and [int]$Matches[6] -gt 0 -and [int]$Matches[7] -gt 0 }
        }
    })
}
function Shown([IntPtr]$h, [string]$name, [int]$role) { @(Nodes $h | Where-Object { $_.shown -and $_.name -eq $name -and $_.role -eq $role }) }
# Keys to the browser's window in front, through SendKeys ("%+2" is Shift+Alt+2) -- never to another window.
function Keys([string]$k) {
    if ([C12Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
# A right click on row `name` (guarded), then the names of the menu that opened.
function RowMenu([IntPtr]$h, [string]$name) {
    $r = @(Shown $h $name 0x24) | Select-Object -Last 1
    if (-not $r) { return [pscustomobject]@{ result = "no '$name' row drawn"; items = @() } }
    $c = [E18Input]::Click($h, $r.l + [int]($r.w / 3), $r.t + [int]($r.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $items = @(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $h)) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } })
    [pscustomobject]@{ result = $c; items = $items }
}
# The first shown node matching `re` in the browser's other windows (a menu, a dialog, the Archive), pressed via MSAA.
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
function OtherNames([IntPtr]$main) { @(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
# The pixels of a small screen box, as one string (to compare two moments).
function Pixels([int[]]$box) {
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap $box[2], $box[3]
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($box[0], $box[1], 0, 0, $bmp.Size)
        $sb = [Text.StringBuilder]::new()
        for ($y = 0; $y -lt $box[3]; $y++) { for ($x = 0; $x -lt $box[2]; $x++) { [void]$sb.Append($bmp.GetPixel($x, $y).ToArgb().ToString('x')) } }
        $sb.ToString()
    } finally { $g.Dispose(); $bmp.Dispose() }
}
function Url([string]$n) { "http://127.0.0.1:$($script:srv.port)/$n.html" }
function Pages { try { @(Invoke-RestMethod -TimeoutSec 10 "http://127.0.0.1:$($script:port)/json/list" | Where-Object { $_.type -eq "page" } | ForEach-Object { $_.url }) } catch { @() } }

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'a closed folder shows its page in front')>=0 else 1)" "$bin\chrome.dll"
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 62"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C12Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y); [StructLayout(LayoutKind.Sequential)] public struct P { public int x, y; } [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(P p); [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint f); [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } public static IntPtr Front() { return GetForegroundWindow(); } public static string Hover(IntPtr h, int x, int y) { SetThreadDpiAwarenessContext(new IntPtr(-4)); P p; p.x = x; p.y = y; if (GetAncestor(WindowFromPoint(p), 2) != h) return "not moved: another window is at " + x + "," + y; SetCursorPos(x, y); System.Threading.Thread.Sleep(400); return "moved"; } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$script:srv = ServePages "$ws\$Tag-pages" @("c24")
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
    $c = Count "pins: drew \d+ row\(s\) of '$work'"
    Say "Shift+Alt+2 (Work): $(Keys '%+2')"
    if (-not (WaitLog "pins: drew \d+ row\(s\) of '$work'" ($c + 1) 10)) { throw "Work was not shown" }
    Start-Sleep (2 * $slow)

    # C12: the page in front under its closed folder.
    $drew = "pins: drew \d+ row\(s\) of '$work'"
    $c = Count $drew; $r = Press $main "Closed folder"; $null = WaitLog $drew ($c + 1) 10
    $opened = "pins: opened item '([^']+)'"
    $c = Count $opened; $r += "; Hidden: $(Press $main 'Hidden')"; $ok = WaitLog $opened ($c + 1) 10
    $hid = if ($ok) { (Last $opened).Groups[1].Value } else { "" }
    Start-Sleep (2 * $slow)
    $peek = "pins: a closed folder shows its page in front '$hid'"
    $c = Count $drew; $r += "; Closed folder: $(Press $main 'Closed folder')"; $null = WaitLog $drew ($c + 1) 10
    $ok = $hid -and (WaitLog $peek 1 10)
    Start-Sleep (1 * $slow)
    $rows = @(Shown $main "Hidden" 0x24)
    Verdict "C12a the folder closed again, its open page in front still has a row under it ($r; peek logged: $ok; 'Hidden' rows drawn: $($rows.Count))" ($ok -and $rows.Count -eq 1)
    $m = RowMenu $main "Hidden"
    Verdict "C12b the peek row's menu has 'Close page', no 'New folder' ($($m.result): $($m.items -join ', '))" (($m.items -contains "Close page") -and -not ($m.items -contains "New folder"))
    $c = Count "pins: no peek row"
    $r = OtherPress $main '^Close page$'
    $ok = WaitLog "pins: no peek row" ($c + 1) 10
    Start-Sleep (1 * $slow)
    Verdict "C12c its menu's Close page closed the page and the peek row went ($r; rows now: $(@(Shown $main 'Hidden' 0x24).Count))" ($ok -and (WaitLog "closed the page of pinned item '$hid'" 1 5) -and @(Shown $main "Hidden" 0x24).Count -eq 0)

    # C26: the x painted only while the mouse is over the row.
    $c = Count $opened; $r = Press $main "Example A"; $null = WaitLog $opened ($c + 1) 10
    Start-Sleep (3 * $slow)
    $row = @(Shown $main "Example A" 0x24) | Select-Object -First 1
    $x = @(Nodes $main | Where-Object { $_.name -eq "Close page" -and $_.role -eq 0x2B -and $_.shown }) | Select-Object -First 1
    if ($row -and $x) {
        $box = @($x.l, $x.t, $x.w, $x.h)
        # The mouse first over the page, well away from the rows: wherever it was is not known.
        $cl = [E18Input]::Client($main)
        $away = [C12Fg]::Hover($main, $cl[0] + [int]($cl[2] * 0.7), $cl[1] + [int]($cl[3] * 0.5)); Start-Sleep -Milliseconds (600 * $slow)
        $away1 = Pixels $box
        $hover = [C12Fg]::Hover($main, $row.l + [int]($row.w / 3), $row.t + [int]($row.h / 2)); Start-Sleep -Milliseconds (600 * $slow)
        $over = Pixels $box
        $moved = [C12Fg]::Hover($main, $cl[0] + [int]($cl[2] * 0.7), $cl[1] + [int]($cl[3] * 0.5)); Start-Sleep -Milliseconds (600 * $slow)
        $away2 = Pixels $box
        Verdict "C26a the open row's x is still named for MSAA ('Close page' shown at $($x.l),$($x.t))" $true
        Verdict "C26b the x is painted only with the mouse over the row (away: $away; over: $hover, differs: $($over -ne $away1); away again: $moved, same as before: $($away2 -eq $away1))" (($over -ne $away1) -and ($away2 -eq $away1))
    } else {
        Verdict "C26a the open row's x is still named for MSAA ($r; row: $([bool]$row), 'Close page' shown: $([bool]$x))" $false
        Verdict "C26b the x is painted only with the mouse over the row (not measured)" $false
    }

    # C30: Delete keeps the pages in the Archive.
    $deleted = "pins: deleted '[^']+' \((\d+) item\(s\), (\d+) open page\(s\) closed, (\d+) archived\)"
    $m = RowMenu $main "Example D"
    $c = Count $deleted; $r = OtherPress $main '^Delete$'
    $ok = WaitLog $deleted ($c + 1) 10; $d = if ($ok) { Last $deleted } else { $null }
    Verdict "C30a Delete on 'Example D' archived it ($($m.result); $r; $(if ($d) { $d.Value } else { 'no deleted line' }))" ($d -and $d.Groups[1].Value -eq "1" -and $d.Groups[3].Value -eq "1")
    $c = Count "shortcut: archive"; $r = Keys "%+h"; $null = WaitLog "shortcut: archive" ($c + 1) 5
    Start-Sleep (2 * $slow)
    $names = OtherNames $main
    Verdict "C30b the Archive lists 'Example D' (Shift+Alt+H $r)" (@($names | Where-Object { $_ -like "*Example D*" }).Count -gt 0)
    $null = Keys "{ESC}"; Start-Sleep (1 * $slow)
    $m = RowMenu $main "Smoke folder"
    $r = OtherPress $main '^Delete folder$'
    Start-Sleep (1 * $slow)
    $body = OtherNames $main
    # The confirm's button reads "Delete folder" too (IDS_HELIUM_PINNED_FOLDER_DELETE).
    $c = Count $deleted; $r += "; confirm: $(OtherPress $main '^Delete folder$')"
    $ok = WaitLog $deleted ($c + 1) 10; $d = if ($ok) { Last $deleted } else { $null }
    Verdict "C30c the folder's confirm says its pages go to the Archive ($(@($body | Where-Object { $_ -like '*Archive*' }) -join ' | '))" (@($body | Where-Object { $_ -like "*go to the Archive*" }).Count -gt 0)
    Verdict "C30d Delete folder on 'Smoke folder' archived both pages ($($m.result); $r; $(if ($d) { $d.Value } else { 'no deleted line' }))" ($d -and $d.Groups[1].Value -eq "2" -and $d.Groups[3].Value -eq "2")

    # C24: an empty workspace's header takes a dragged tab.
    $active = "\[workspaces\] active workspace -> '([^']*)'"
    # The folder's confirm is still closing: its window is the browser's, so Keys' guard passes while the dialog,
    # not the main window, has the key -- Shift+Alt+S was swallowed (c14 regression, 4 runs of 4). Wait for it.
    $t0 = Get-Date
    while ([C12Fg]::Front() -ne $main -and ((Get-Date) - $t0).TotalSeconds -lt 5 * $slow) { Start-Sleep -Milliseconds 200 }
    $front = "main window in front after $([int]((Get-Date) - $t0).TotalMilliseconds) ms: $([C12Fg]::Front() -eq $main)"
    $c = Count $active; $r = Keys "%+s"; $ok = WaitLog $active ($c + 1) 10
    $r += " ($front)"
    $new = if ($ok) { (Last $active).Groups[1].Value } else { "" }
    Start-Sleep (2 * $slow)
    $ins = "tab inserted at index \d+ -> workspace '$new'"
    $c = Count $ins; Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "c24")) | Out-Null; $null = WaitLog $ins ($c + 1) 10
    Start-Sleep (3 * $slow)
    $tab = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq "E18 c24" -or $_.name -like "*c24.html*") }) | Select-Object -First 1
    # The sidebar's "+ New Tab" under the section: the "New Tab" button in the tab's column, the top-most one.
    $plus = if ($tab) { @(Nodes $main | Where-Object { $_.shown -and $_.name -eq "New Tab" -and $_.role -eq 0x2B -and [Math]::Abs($_.l - $tab.l) -lt 60 }) | Sort-Object t | Select-Object -First 1 }
    $pinned = "pins: pinned a tab as item '[^']+'"
    if ($tab -and $plus) {
        $c = Count $pinned
        $dr = [E18Input]::Drag($main, $tab.l + [int]($tab.w / 3), $tab.t + [int]($tab.h / 2), $plus.l + [int]($plus.w / 3), $plus.t - 14)
        $ok = WaitLog $pinned ($c + 1) 10
        Verdict "C24 a web page dragged onto the empty workspace's header is pinned there (Shift+Alt+S: $r; workspace '$new'; $dr; dropped: $(Count 'tab\(s\) dropped on the rows'))" ($ok -and (WaitLog "pins: drew 1 row\(s\) of '$new'" 1 10))
    } else {
        Verdict "C24 a web page dragged onto the empty workspace's header is pinned there (workspace '$new'; tab: $([bool]$tab), New Tab button: $([bool]$plus))" $false
    }
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
# Case-sensitive, as LOCAL.md grades (Count is Select-String, case-INSENSITIVE): an exit can dump the histogram
# "Commerce.PriceTracking.DanglingUserSubscriptionCountAtStartup", no crash (LOCAL.md 86; tripped in c14's re-runs).
$markers = if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling").Count } else { 0 }
Verdict "Z crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
