param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "", [string]$Tag = "",
      [string[]]$Cases = @("L1", "L2"))
# Patch 103 (review 2's chunk 1, <local-path>\Helium-workspace\patch-review-2-findings.md R2-15 + R2-2): the layout switched
# from classic to vertical while the browser runs. Each case on a new scratch profile (the smoke profile's Local State
# and Preferences; Home + Work), the layout switched through chrome://settings' settingsPrivate on the DevTools port
# (--remote-debugging-port=0, e18-lib's OpenSettings / Evaluate), chips pressed and the bar read through MSAA
# (msaa-press.ps1). No mouse, no keys -- but the window shows: run it with the PC free (the owner's word).
#   pwsh -NoProfile -Command "& '<local-path>\Helium-workspace\helium\local\check-103.ps1'"
#   red, on a build without patch 103 (156 has the same code): ... -BinDir <local-path>\Helium-workspace\src-156\out\Default -Tag -red
#   L1  R2-15  started in the classic layout, then vertical: the bar shows -- its + and the Work chip on screen
#   L2  R2-2   vertical: Work pressed, a page opened there, Home pressed; classic; Work's page brought to the front;
#              vertical: the window follows the page into Work (a second "active workspace -> 'p103w'")
#   Z          0 crash markers in the case logs (case-sensitive, DanglingPtr too)
. "$PSScriptRoot\e18-lib.ps1"
$Cases   = @($Cases | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$smoke   = "$ws\testprofile-e15b-smoke"
$scratch = "$env:TEMP\check-103-$(Get-Date -Format yyyyMMdd-HHmmss)"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$plus    = "New tab, workspace or search"
$items   = '[{"guid":"default","title":"Home"},{"guid":"p103w","title":"Work"}]'
$script:passed = 0; $script:failed = 0; $script:logs = @()
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Write-Host "ABORT: $why"; exit 1 }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath "$bin\chrome.exe")) { Abort "no $bin\chrome.exe" }
E18InputType

function Msaa([string]$prof, [object[]]$a) { @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof @a) }
function Until([int]$s, [scriptblock]$ok) { $t = Get-Date; do { if (& $ok) { return $true }; Start-Sleep -Milliseconds 300 } while (((Get-Date) - $t).TotalSeconds -lt $s * $slow); $false }
function ReadShared([string]$file) {
    if (-not (Test-Path -LiteralPath $file)) { return "" }
    $fs = [IO.File]::Open($file, "Open", "Read", "ReadWrite, Delete")
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
function Count([string]$log, [string]$re) { [regex]::Matches((ReadShared $log), $re).Count }
# Whether a node named `name` of role `role` is drawn (not INVISIBLE, a box with size).
function Shown([string]$prof, [string]$name, [int]$role) {
    [bool](@(ParseMsaaNodes (Msaa $prof @("-List", "-Rect"))) | Where-Object { $_.name -eq $name -and $_.role -eq $role -and $_.shown })
}

$null = New-Item -ItemType Directory "$scratch\files"
# A scratch profile: the smoke profile's Local State and Preferences, Home + Work, the given Helium layout
# (0 classic, 2 vertical; HeliumLayoutType).
$helper = "$scratch\files\prefs.py"
Set-Content -LiteralPath $helper -Encoding utf8 -Value @'
import json, sys
path, items, layout = sys.argv[1], json.loads(sys.argv[2]), int(sys.argv[3])
d = json.load(open(path, encoding="utf-8"))
h = d.setdefault("helium", {})
h.setdefault("workspaces", {})["list"] = {"schema_version": 1, "items": items}
h["workspaces"]["enabled"] = True
h.setdefault("browser", {})["layout"] = layout
json.dump(d, open(path, "w", encoding="utf-8"))
'@
function NewProfile([string]$name, [int]$layout) {
    $prof = "$scratch\$name"
    $null = New-Item -ItemType Directory "$prof\Default"
    Copy-Item -LiteralPath "$smoke\Local State" "$prof\Local State"
    Copy-Item -LiteralPath "$smoke\Default\Preferences" "$prof\Default\Preferences"
    & python -I $helper "$prof\Default\Preferences" $items $layout
    $prof
}
function LogOf([string]$name) { $l = "$ws\p103-$name$(if ($Build -eq 'Dcheck') { '-dcheck' })$Tag.log"; $script:logs += $l; $l }
function Launch([string]$prof, [string]$log, [string]$url) {
    $p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList @("--user-data-dir=`"$prof`"", "--enable-logging",
        "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0", $url)
    $null = Until 20 { $h = (Get-Process -Id $p.Id -EA SilentlyContinue).MainWindowHandle; $h -and $h -ne [IntPtr]::Zero }
    $p
}
function Close($p) {
    foreach ($h in @([E18Input]::Windows([uint32]$p.Id))) { [E18Input]::CloseWindow($h) }
    if (-not (Until 120 { $p.HasExited })) { Write-Host "      did not close by its X: stopped"; Stop-Process -Id $p.Id -EA SilentlyContinue }
    Wait-Process -Id $p.Id -Timeout 30 -EA SilentlyContinue
}
function SetLayout($set, [int]$layout) { Evaluate $set.page.webSocketDebuggerUrl "chrome.settingsPrivate.setPref('helium.browser.layout', $layout, '')" }

$pages = ServePages "$scratch\pages" @("p103a", "p103b")
if (-not $pages.ok) { Abort "the local test pages were not served" }
$page = "http://127.0.0.1:$($pages.port)"
try {
    if ($Cases -contains "L1") {
        $prof = NewProfile "l1" 0; $log = LogOf "l1"
        $p = Launch $prof $log "$page/p103a.html"
        $before = Until 10 { Shown $prof "Work" 0x2B }
        $set = OpenSettings $prof
        $switched = if ($set.ready) { SetLayout $set 2 }
        $bar = Until 10 { (Shown $prof "Work" 0x2B) -and (Shown $prof $plus 57) }
        Write-Host "      classic: Work chip shown $before; settings $($set.note); setPref layout 2 -> $switched"
        Verdict "L1 R2-15 classic -> vertical: the bar shows, its + and the Work chip on screen (shown $bar; before, in classic, $before)" (
            -not $before -and "$switched" -eq "True" -and $bar)
        Close $p
    }
    if ($Cases -contains "L2") {
        $prof = NewProfile "l2" 2; $log = LogOf "l2"
        $p = Launch $prof $log "$page/p103a.html"
        $toWork = "active workspace -> 'p103w'"
        $null = Until 20 { Shown $prof "Work" 0x2B }
        $null = Msaa $prof @("-Name", "Work", "-Role", 0x2B)
        $inWork = Until 10 { (Count $log ([regex]::Escape($toWork))) -ge 1 }
        $set = OpenSettings $prof
        $b = if ($set.base) { try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$($set.base)/new?$page/p103b.html" } catch { $null } }
        $toHome = [regex]::Escape("active workspace -> 'default'")
        $homeBefore = Count $log $toHome
        $null = Msaa $prof @("-Name", "Home", "-Role", 0x2B)
        $inHome = Until 10 { (Count $log $toHome) -gt $homeBefore }
        $classic = if ($set.ready) { SetLayout $set 0 }
        Start-Sleep -Seconds (2 * $slow)
        $front = if ($b) { try { Invoke-RestMethod -TimeoutSec 10 -Uri "$($set.base)/activate/$($b.id)" } catch { "error: $_" } }
        Start-Sleep -Seconds (2 * $slow)
        $already = Count $log ([regex]::Escape($toWork))
        $vertical = if ($set.ready) { SetLayout $set 2 }
        $followed = Until 10 { (Count $log ([regex]::Escape($toWork))) -gt $already }
        $said = (Count $log "layout: back to vertical, following the page in front") -ge 1
        Write-Host "      Work pressed $inWork; Work's page $(if ($b) { $b.id } else { 'not opened' }); Home pressed $inHome; classic $classic; brought to the front: $front; vertical $vertical"
        Verdict "L2 R2-2 back to vertical the window follows the page into Work (a new '$toWork' $followed, the log line $said)" (
            $inWork -and $b -and $inHome -and "$classic" -eq "True" -and "$vertical" -eq "True" -and $followed -and $said)
        Close $p
    }
} finally {
    Stop-Process -Id $pages.server.Id -EA SilentlyContinue
}
$marks = 0
foreach ($l in $script:logs) { $marks += Count $l 'Check failed|FATAL|DanglingPtr|ReentrancyCheck|NOTREACHED' }
Verdict "Z 0 crash markers in $($script:logs.Count) log(s) ($marks)" ($marks -eq 0)
Write-Host "RESULT: $script:passed passed, $script:failed failed (scratch: $scratch)"
