param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "")
# Patch 97 (chunk C, LOCAL.md 126): "Import from Arc" says WHY nothing was imported (the review's arc-import F4), and it
# changes "On startup" and saves its import time only when tabs arrived (F8, F5's first half). One launch per case, each
# on a new scratch profile (Local State and Preferences copied from testprofile-e15b-smoke: vertical, Workspaces on, On
# startup the New Tab page), HELIUM_ARC_SIDEBAR pointing at the case's file. The rail's + and "Import from Arc..." are
# pressed through MSAA (msaa-press.ps1), the result bubble is read (MSAA too), and the browser is closed by WM_CLOSE
# (what its X sends), so its Preferences are written. No mouse, no keys -- but a menu and a bubble show for a few
# seconds per run: run it with the PC free (the owner's word).
#   pwsh -NoProfile -File local\check-97.ps1 [-Build Dcheck] [-BinDir <dir>]
#   R1  no file there: "Arc's data was not found on this computer" (the control: the same before and after 97)
#   R2  a 65 MB file: "too large", not "not found"
#   R3  a file cut off mid-way (Arc saving it): "could not be read", not "not found"
#   R4  JSON with no main sidebar (only a Little Arc window): "a format Helium can't read", not "not found"
#   S1  an empty sidebar: "Imported 0 tabs", and after the browser closed On startup is still the New Tab page and no
#       import time is saved
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$smoke   = "$ws\testprofile-e15b-smoke"
$scratch = "$env:TEMP\check-97-$(Get-Date -Format yyyyMMdd-HHmmss)"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$script:passed = 0; $script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Write-Host "ABORT: $why"; exit 1 }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath "$bin\chrome.exe")) { Abort "no $bin\chrome.exe" }
E18InputType
$plus   = "New tab, workspace or search"
$import = "Import from Arc$([char]0x2026)"

# msaa-press.ps1 runs in Windows PowerShell 5.1 (its COM cast); -Profile finds this run's browser.
function Msaa([string]$prof, [string[]]$a) { "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof @a)" }
function Until([int]$s, [scriptblock]$ok) { $t = Get-Date; do { if (& $ok) { return $true }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t).TotalSeconds -lt $s); $false }
function ReadShared([string]$file) {
    if (-not (Test-Path -LiteralPath $file)) { return "" }
    $fs = [IO.File]::Open($file, "Open", "Read", "ReadWrite, Delete")
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
# The result bubble's names, joined: the browser's top shown window other than its main one (msaa-press -Popup;
# an owned window, which UI Automation lists under the browser window, not at the top).
function Bubble([string]$prof) { $t = Msaa $prof @("-List", "-Popup"); if ($t -match "Arc") { $t } else { "" } }

# One case: the profile copied, the browser started on `sidebar`, + > Import from Arc pressed, the bubble read once the
# log says the import ended, the browser closed by its window's X.
function Run([string]$name, [string]$sidebar) {
    $prof = "$scratch\$name"
    $null = New-Item -ItemType Directory "$prof\Default"
    Copy-Item -LiteralPath "$smoke\Local State" "$prof\Local State"
    Copy-Item -LiteralPath "$smoke\Default\Preferences" "$prof\Default\Preferences"
    $log = "$ws\e97-$name$(if ($Build -eq 'Dcheck') { '-dcheck' }).log"
    $env:HELIUM_ARC_SIDEBAR = $sidebar
    $p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList "--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check"
    Remove-Item Env:HELIUM_ARC_SIDEBAR
    $r = [pscustomobject]@{ prof = "$prof\Default"; pressed = ""; ended = ""; bubbles = @() }
    try {
        $null = Until (20 * $slow) { $script:h = (Get-Process -Id $p.Id -EA SilentlyContinue).MainWindowHandle; $script:h -and $script:h -ne [IntPtr]::Zero }
        $main = $script:h
        $null = Until (30 * $slow) { ($script:o = Msaa $prof @("-Name", $plus, "-Role", "57")) -match "pressed" }
        $r.pressed = $script:o
        $null = Until (5 * $slow) { ($script:o = Msaa $prof @("-Popup", "-Name", $import)) -match "pressed" }
        $r.pressed += "; " + $script:o
        $endRe = '\[workspaces\] arc import: (nothing imported \([a-z ]+\)|done: .*)'
        $null = Until (20 * $slow) { (ReadShared $log) -match $endRe }
        $r.ended = if ((ReadShared $log) -match $endRe) { $Matches[1] } else { "(no end line)" }
        $null = Until (10 * $slow) { ($script:b = Bubble $prof) }
        $r.bubbles = @($script:b | Where-Object { $_ })
        if ($main -ne [IntPtr]::Zero) { [E18Input]::CloseWindow($main) }
        if (-not (Until (20 * $slow) { $p.HasExited })) { Write-Host "      $name did not close by its X: stopped" }
    } finally { Stop-Process -Id $p.Id -EA SilentlyContinue; Wait-Process -Id $p.Id -Timeout 15 -EA SilentlyContinue }
    Write-Host "      $name pressed: $($r.pressed)"
    Write-Host "      $name log: $($r.ended)"
    $r.bubbles | ForEach-Object { Write-Host "      $name bubble: $_" }
    if (-not $r.bubbles.Count) { Write-Host "      $name bubble: (none)" }
    $r
}
function Said($r, [string]$re) { @($r.bubbles -match $re).Count -eq 1 -and @($r.bubbles -match "not found").Count -eq 0 }

$null = New-Item -ItemType Directory "$scratch\files"
$big = [IO.File]::Create("$scratch\files\big.json"); $big.SetLength(65MB); $big.Dispose()
[IO.File]::WriteAllText("$scratch\files\cut.json", '{"sidebar":{"containers":[{"global":{}},{"items":[{"id":"t1","data":{"tab":')
[IO.File]::WriteAllText("$scratch\files\little.json", '{"sidebar":{"containers":[{"littleBrowser":{}},{"items":[],"spaces":[]}]}}')
[IO.File]::WriteAllText("$scratch\files\empty.json", '{"sidebar":{"containers":[{"global":{}},{"items":[],"spaces":[]}]}}')

$r1 = Run "missing" "$scratch\files\missing.json"
$r2 = Run "big" "$scratch\files\big.json"
$r3 = Run "cut" "$scratch\files\cut.json"
$r4 = Run "little" "$scratch\files\little.json"
$s1 = Run "empty" "$scratch\files\empty.json"

Verdict "R1 no file: not found (the control)" (@($r1.bubbles -match "Arc's data was not found on this computer").Count -eq 1)
Verdict "R2 a 65 MB file: too large" (Said $r2 "too large")
Verdict "R3 a cut-off file: could not be read" (Said $r3 "could not be read")
Verdict "R4 no main sidebar: a format it can't read" (Said $r4 "format")
# On startup is a protected setting: Windows builds keep it in Secure Preferences.
$startup = (ReadShared "$($s1.prof)\Secure Preferences" | ConvertFrom-Json -AsHashtable).session.restore_on_startup
$stamp = (ReadShared "$($s1.prof)\Preferences" | ConvertFrom-Json -AsHashtable).helium.workspaces.arc_imported_at
Verdict "S1 an empty sidebar: 'Imported 0 tabs', On startup unchanged ($($startup ?? 'not set')), no import time ($($stamp ?? 'not set'))" (@($s1.bubbles -match "Imported 0 tabs from Arc").Count -eq 1 -and $startup -ne 1 -and -not $stamp)
Write-Host "$script:passed passed, $script:failed failed (scratch folder $scratch)"
exit [int]($script:failed -gt 0)
