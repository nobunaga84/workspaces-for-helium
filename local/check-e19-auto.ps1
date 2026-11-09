param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "e19")
# E19 (patch 65), hands-free, MSAA presses only (no real mouse, no keys: nothing is sent to the window in front, so
# the PC need not be free -- but a browser window does open). A throwaway copy of the smoke profile gets the owner's
# 3 Arc pinned splits seeded into Home as the old import left them -- 6 plain items, a version-1 pins file
# (e19-seed-splits.py, from the made-up Arc file and testprofile, LOCAL.md 133). Then:
#   R1  the one-time repair: "re-paired 3 of 3 Arc pinned split(s)"
#   R2  Home draws 3 split rows, each named "<left> | <right>"
#   R3  a split row pressed: both its pages open ("opened item" x2) and become one split view ("joined")
#   R4  pressed again: nothing opens a second time
#   R6  the left page's x pressed: only that page closes; a screenshot of the window ($Tag-dim[-dcheck].png) shows
#       the closed page fainter beside the open one (for Claude's eyes; not graded)
#   R5  the pins file is version 2 with 3 split rows in Home (after the window closes)
#   Z   0 crash markers in the log (Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling)
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-e19-auto.ps1 [-OutDir Dcheck]
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag-auto$suffix"
$log    = if ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise.log" } else { "$ws\$Tag-auto-run.log" }
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
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime)"
E18InputType
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the profile copy failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Say "seed: $((& python "$here\e19-seed-splits.py" $prof --workspace default) -join ' / ')"
if ($LASTEXITCODE -ne 0) { Abort "seeding failed" }
$env:HELIUM_ARC_SIDEBAR = "$ws\arc-made-up\StorableSidebar.json"  # the repair reads Arc's file: the made-up one (LOCAL.md 133)
Remove-Item -LiteralPath $log -EA SilentlyContinue
try {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")).Id
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    # Topmost and not activated: the screenshot of R6 sees it, nothing takes the owner's focus.
    [E18Input]::Place($main, 40, 40, 1100, 800)

    $ok = WaitLog "pins: re-paired \d+ of \d+ Arc pinned split" 1 30
    $line = @(Select-String -LiteralPath $log -Pattern "pins: re-paired (\d+) of (\d+)" | Select-Object -Last 1)
    Verdict "R1 the repair: $(if ($line) { $line[0].Matches[0].Value } else { 'no repair line' })" ($ok -and $line -and $line[0].Matches[0].Groups[1].Value -eq "3" -and $line[0].Matches[0].Groups[2].Value -eq "3")
    Start-Sleep (2 * $slow)

    $rows = @(Msaa $main @("-List") | ForEach-Object { if ($_ -match '^\s*(.+ \| .+)\|0x24') { $Matches[1] } })
    Verdict "R2 split rows drawn in Home: $($rows.Count) ($(@($rows | ForEach-Object { $_.Length }) -join ', ') chars)" ($rows.Count -eq 3)

    if ($rows.Count -ge 1) {
        $opened = "pins: opened item '"; $joined = "pins: a split's pages joined as one split view"
        $c = Count $opened; $j = Count $joined
        $r = "$(Msaa $main @('-Name', $rows[0], '-Role', 0x24))"
        $ok = (WaitLog $opened ($c + 2) 10) -and (WaitLog $joined ($j + 1) 10)
        Verdict "R3 a split row pressed ($r): opened $((Count $opened) - $c), joined $((Count $joined) - $j)" $ok
        Start-Sleep (2 * $slow)
        $c = Count $opened
        $r = "$(Msaa $main @('-Name', $rows[0], '-Role', 0x24))"
        Start-Sleep (3 * $slow)
        Verdict "R4 pressed again ($r): nothing opened a second time (opened $((Count $opened) - $c))" ((Count $opened) -eq $c)

        # The open split's two x buttons are its only "Close page" nodes, the left page's made first.
        $closed = "closed the page of pinned item '([^']+)' \(the row's close button\)"
        $c = Count $closed
        $r = "$(Msaa $main @('-Name', 'Close page', '-Role', 0x2B, '-Nth', 0))"
        $ok = WaitLog $closed ($c + 1) 10
        Start-Sleep (2 * $slow)
        $png = "$ws\$Tag-dim$suffix.png"
        Add-Type -AssemblyName System.Drawing
        $cl = [E18Input]::Client($main)
        $bmp = New-Object System.Drawing.Bitmap $cl[2], $cl[3]
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try { $g.CopyFromScreen($cl[0], $cl[1], 0, 0, $bmp.Size); $bmp.Save($png) } finally { $g.Dispose(); $bmp.Dispose() }
        Start-Sleep (1 * $slow)
        Verdict "R6 the left page's x ($r): closed $((Count $closed) - $c) page, still open in this window: $(@(Select-String -LiteralPath $log -Pattern 'pins: (\d+) item page\(s\) open' | Select-Object -Last 1 | ForEach-Object { $_.Matches[0].Groups[1].Value })); screenshot $png" ($ok -and ((Count $closed) - $c) -eq 1)
    }
} catch {
    Say "ERROR: $_"; $script:failed++
} finally {
    if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    }
}
$file = "$(& python -I -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); print(d['version'], sum(1 for r in d['workspaces'].get('default',[]) if r['type']=='split'))" "$prof\Default\Workspace Pins")"
Verdict "R5 the pins file after closing: version, split rows in Home = $file" ($file -eq "2 3")
$markers = Count "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling"
Verdict "Z crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
