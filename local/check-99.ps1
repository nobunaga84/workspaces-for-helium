param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "", [string]$Tag = "",
      [string[]]$Cases = @("X1", "X2", "X3", "X4", "X5", "X6"))
# Patch 99 (the polish batch, LOCAL.md 129): the export/import fixes (the negative review's transfer F1 F3 F5 F10), the
# + menu while an Arc import runs (review #52), and a link from another app with no main window (data-files F9). Each
# case on a new scratch profile (Local State and Preferences copied from testprofile-e15b-smoke: vertical, Workspaces
# on), the rail's + and its items pressed through MSAA (msaa-press.ps1). --helium-workspaces-transfer-auto=<file>
# makes Export / Import skip their dialogs and bubbles and use that file; the log has the result. The browser is
# closed by WM_CLOSE (what its X sends). No mouse, no keys -- but menus show for a few seconds per case: run it with
# the PC free (the owner's word).
#   pwsh -NoProfile -Command "& '<local-path>\Helium-workspace\helium\local\check-99.ps1' -Build Dcheck -Cases X1,X2"
#   red, on a build without patch 99: ... -Build Dcheck -BinDir <out\Dcheck-p99ctl> -Tag -red
#   X1  F1   the pins file is from a newer version (read-only, empty): Export is refused, no file written
#   X2  F3   "Workspace Backups" cannot be made (a FILE of that name): Import is refused, nothing replaced
#   X3  F5   a file without an Archive (the Python tool leaves out a store file it does not find): the Archive is
#            emptied, as the confirm's 0 said, and the log's "import: now" line says 0
#   X4  F10  a 129 MB file: refused as too large, not "could not be read"
#   X5  #52  while an Arc import reads (a file on 192.0.2.1, TEST-NET-1: Windows gives up after ~40 s), the + menu's
#            Export workspaces and Import workspaces are greyed
#   X6  F9   a little window open, the main window closed, then a link from another app to a site with a rule: no
#            second little window; a main window opens and the tab joins the rule's workspace
#   Z        0 crash markers in the case logs (case-sensitive, DanglingPtr too)
. "$PSScriptRoot\e18-lib.ps1"
$Cases   = @($Cases | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$smoke   = "$ws\testprofile-e15b-smoke"
$tool    = "$PSScriptRoot\workspaces-transfer.py"
$scratch = "$env:TEMP\check-99-$(Get-Date -Format yyyyMMdd-HHmmss)"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$script:passed = 0; $script:failed = 0; $script:logs = @()
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Write-Host "ABORT: $why"; exit 1 }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath "$bin\chrome.exe")) { Abort "no $bin\chrome.exe" }
E18InputType
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$UIA    = [System.Windows.Automation.AutomationElement]
$dots   = [char]0x2026
$plus   = "New tab, workspace or search"
$export = "Export workspaces$dots"
$import = "Import workspaces$dots"
$arc    = "Import from Arc$dots"

function Msaa([string]$prof, [object[]]$a) { "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof @a)" }
function Until([int]$s, [scriptblock]$ok) { $t = Get-Date; do { if (& $ok) { return $true }; Start-Sleep -Milliseconds 300 } while (((Get-Date) - $t).TotalSeconds -lt $s * $slow); $false }
function ReadShared([string]$file) {
    if (-not (Test-Path -LiteralPath $file)) { return "" }
    $fs = [IO.File]::Open($file, "Open", "Read", "ReadWrite, Delete")
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
function Has([string]$log, [string]$re) { [regex]::IsMatch((ReadShared $log), $re) }

$null = New-Item -ItemType Directory "$scratch\files"
# A scratch profile: the smoke profile's Local State and Preferences, its workspace list replaced by `items` (JSON),
# and `files` (name -> text) written into Default.
$helper = "$scratch\files\prefs.py"
Set-Content -LiteralPath $helper -Encoding utf8 -Value @'
import json, sys
path, items = sys.argv[1], json.load(open(sys.argv[2], encoding="utf-8"))
d = json.load(open(path, encoding="utf-8"))
d.setdefault("helium", {}).setdefault("workspaces", {})["list"] = {"schema_version": 1, "items": items}
json.dump(d, open(path, "w", encoding="utf-8"))
'@
function NewProfile([string]$name, [string]$items = '[{"guid":"default","title":"Home"}]', [hashtable]$files = @{}) {
    $prof = "$scratch\$name"
    $null = New-Item -ItemType Directory "$prof\Default"
    Copy-Item -LiteralPath "$smoke\Local State" "$prof\Local State"
    Copy-Item -LiteralPath "$smoke\Default\Preferences" "$prof\Default\Preferences"
    [IO.File]::WriteAllText("$scratch\files\$name-list.json", $items)
    & python -I $helper "$prof\Default\Preferences" "$scratch\files\$name-list.json"
    foreach ($f in $files.Keys) { [IO.File]::WriteAllText("$prof\Default\$f", $files[$f]) }
    $prof
}
# -Tag keeps a run's logs apart from another's (a red run on an older build: -Tag -red).
function LogOf([string]$name) { $l = "$ws\p99-$name$(if ($Build -eq 'Dcheck') { '-dcheck' })$Tag.log"; $script:logs += $l; $l }
function Launch([string]$prof, [string]$log, [string[]]$more = @()) {
    $p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList (@("--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check") + $more)
    $null = Until 20 { $script:h = (Get-Process -Id $p.Id -EA SilentlyContinue).MainWindowHandle; $script:h -and $script:h -ne [IntPtr]::Zero }
    $p | Add-Member -NotePropertyName main -NotePropertyValue $script:h -PassThru
}
function Close($p) {
    foreach ($h in @([E18Input]::Windows([uint32]$p.Id))) { [E18Input]::CloseWindow($h) }
    if (-not (Until 120 { $p.HasExited })) { Write-Host "      did not close by its X: stopped"; Stop-Process -Id $p.Id -EA SilentlyContinue }
    Wait-Process -Id $p.Id -Timeout 30 -EA SilentlyContinue
}
# + in the main window, then `item` in its menu.
function PressMenu([string]$prof, [string]$item) {
    $null = Until 30 { ($script:o = Msaa $prof @("-Name", $plus, "-Role", "57")) -match "pressed" }
    $out = $script:o
    $null = Until 5 { ($script:o = Msaa $prof @("-Popup", "-Name", $item)) -match "pressed" }
    "$out; $script:o"
}
# The browser's "Profile error occurred" boxes (chunk B), closed: a read-only store shows one at start-up.
function CloseBoxes([int]$bpid) {
    $cond = New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $bpid)
    @($UIA::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond) |
        Where-Object { $_.Current.Name -eq "Profile error occurred" } |
        ForEach-Object { [E18Input]::CloseWindow([IntPtr]$_.Current.NativeWindowHandle); 1 }).Count
}
# Chromium's time (microseconds since 1601) for now, as the store files keep it.
function ChromeNow { [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000 + 11644473600000000) }
$pins1 = '{"version":2,"workspaces":{"default":[{"type":"item","id":"c99p","title":"C99","url":"https://c99.example/p"}]}}'
function Archive1 { '{"version":1,"entries":[{"id":"c99e","url":"https://c99.example/e","title":"E","workspace":"default","reason":"manual","archived_at":"' + (ChromeNow) + '","last_active":"' + (ChromeNow) + '"}]}' }
# An export of a scratch profile, made by the Python tool (the browser's own format).
function ExportOf([string]$name, [hashtable]$files) {
    $src = NewProfile "$name-src" '[{"guid":"default","title":"Home"},{"guid":"c99w","title":"Work"}]' $files
    $out = "$scratch\files\$name.json"
    & python -I $tool export $src $out | Out-Null
    $out
}

# --- X1 (F1): an export from a read-only store ------------------------------------------------------------------
if ($Cases -contains "X1") {
    Write-Host "X1: Export with the pins file from a newer version"
    $prof = NewProfile "x1" -files @{ "Workspace Pins" = '{"version":99,"workspaces":{}}' }
    $out = "$scratch\files\x1-out.json"; $log = LogOf "x1"
    $p = Launch $prof $log @("--helium-workspaces-transfer-auto=`"$out`"")
    try {
        $null = Until 20 { (CloseBoxes $p.Id) -ge 1 }
        Write-Host "      pressed: $(PressMenu $prof $export)"
        $null = Until 20 { Has $log '\[workspaces\] export: (refused|wrote|could not)' }
    } finally { Close $p }
    $refused = Has $log '\[workspaces\] export: refused, a store is read-only'
    Write-Host "      log: refused $refused, wrote $(Has $log '\[workspaces\] export: wrote'); file: $(Test-Path -LiteralPath $out)"
    Verdict "X1 F1 an export from a read-only pins store is refused and writes no file" ($refused -and -not (Test-Path -LiteralPath $out))
}

# --- X2 (F3): the copy cannot be written --------------------------------------------------------------------------
if ($Cases -contains "X2") {
    Write-Host "X2: Import when Workspace Backups cannot be made"
    $file = ExportOf "x2" @{ "Workspace Pins" = '{"version":2,"workspaces":{"c99w":[{"type":"item","id":"c99n","title":"N","url":"https://c99.example/n"}]}}' }
    $prof = NewProfile "x2" -files @{ "Workspace Pins" = $pins1; "Workspace Backups" = "a file, not a folder" }
    $log = LogOf "x2"
    $p = Launch $prof $log @("--helium-workspaces-transfer-auto=`"$file`"")
    try {
        Write-Host "      pressed: $(PressMenu $prof $import)"
        $null = Until 20 { Has $log '\[workspaces\] import: (refused|applied)' }
    } finally { Close $p }
    $pinsAfter = ReadShared "$prof\Default\Workspace Pins"
    $copyLine = Has $log '\[workspaces\] import: could not write the copy'
    $applied = Has $log '\[workspaces\] import: applied'
    Write-Host "      log: copy failed $copyLine, applied $applied; pins still the old row: $($pinsAfter -match 'c99p')"
    Verdict "X2 F3 no copy, no import: refused, the old pinned page kept" ($copyLine -and -not $applied -and $pinsAfter -match 'c99p' -and $pinsAfter -notmatch 'c99n')
}

# --- X3 (F5): a file without an Archive ---------------------------------------------------------------------------
if ($Cases -contains "X3") {
    Write-Host "X3: Import a file without an Archive into a profile with one"
    $file = ExportOf "x3" @{ "Workspace Pins" = $pins1 }
    $members = (ReadShared $file | ConvertFrom-Json -AsHashtable).files.Keys -join ", "
    $prof = NewProfile "x3" -files @{ "Workspace Archive" = (Archive1) }
    $log = LogOf "x3"
    $p = Launch $prof $log @("--helium-workspaces-transfer-auto=`"$file`"")
    try {
        Write-Host "      the file's members: $members"
        Write-Host "      pressed: $(PressMenu $prof $import)"
        $null = Until 20 { Has $log '\[workspaces\] import: (refused|applied)' }
        Start-Sleep -Seconds (2 * $slow)
    } finally { Close $p }
    $entries = @((ReadShared "$prof\Default\Workspace Archive" | ConvertFrom-Json -AsHashtable).entries).Count
    $now = if ((ReadShared $log) -match '\[workspaces\] import: now [^\r\n]*') { $Matches[0] } else { "(no 'import: now' line)" }
    Write-Host "      archive entries after: $entries; $now"
    Verdict "X3 F5 a file without an Archive empties it, and the log says 0 ($members)" (
        $members -notmatch 'Archive' -and $entries -eq 0 -and $now -match ' 0 archive entr')
}

# --- X4 (F10): a file over 128 MB ---------------------------------------------------------------------------------
if ($Cases -contains "X4") {
    Write-Host "X4: Import a 129 MB file"
    $file = "$scratch\files\x4-big.json"
    $fs = [IO.File]::Create($file); $fs.SetLength(129MB); $fs.Dispose()
    $prof = NewProfile "x4"; $log = LogOf "x4"
    $p = Launch $prof $log @("--helium-workspaces-transfer-auto=`"$file`"")
    try {
        Write-Host "      pressed: $(PressMenu $prof $import)"
        $null = Until 30 { Has $log '\[workspaces\] import: refused' }
    } finally { Close $p }
    $line = if ((ReadShared $log) -match '\[workspaces\] import: refused: [^\r\n]*') { $Matches[0] } else { "(no refused line)" }
    Write-Host "      log: $line"
    Verdict "X4 F10 a 129 MB file is refused as too large" ($line -match 'too large')
    Remove-Item -LiteralPath $file -EA SilentlyContinue
}

# --- X5 (#52): the + menu while an Arc import reads --------------------------------------------------------------
if ($Cases -contains "X5") {
    Write-Host "X5: Export and Import while an Arc import reads"
    $prof = NewProfile "x5"; $log = LogOf "x5"
    $env:HELIUM_ARC_SIDEBAR = "\\192.0.2.1\c99\StorableSidebar.json"
    $p = Launch $prof $log
    Remove-Item Env:HELIUM_ARC_SIDEBAR
    try {
        Write-Host "      pressed: $(PressMenu $prof $arc)"
        $null = Until 20 { Has $log 'arc import: reading' }
        # The menu by its handle: the import's progress box is a window of the process too, and -Popup may take it
        # (check-98's case D does the same).
        $wins = @([E18Input]::Windows([uint32]$p.Id))
        $before = @([E18Input]::Others([uint32]$p.Id, [IntPtr]::Zero) | Where-Object { $wins -notcontains $_ })
        $null = Until 30 { ($script:o = Msaa $prof @("-Window", [long]$p.main, "-Name", $plus, "-Role", "57")) -match "pressed" }
        $null = Until 5 { ($script:mw = @([E18Input]::Others([uint32]$p.Id, [IntPtr]::Zero) | Where-Object { $wins -notcontains $_ -and $before -notcontains $_ })).Count -ge 1 }
        $menuWin = if ($script:mw.Count) { [long]$script:mw[0] } else { 0 }
        $menu = if ($menuWin) { Msaa $prof @("-Window", $menuWin, "-List", "-States") } else { "" }
        $still = -not (Has $log 'arc import: (nothing imported|done:)')
        if ($menuWin) { $null = Msaa $prof @("-Window", $menuWin, "-Name", "New tab") }
        $states = @([regex]::Matches($menu, '(Export|Import) workspaces[^|]*\|[^ ]*') | ForEach-Object { $_.Value })
        Write-Host "      menu window ${menuWin}: $($states -join '; '); the import still reading then: $still"
        $null = Until 180 { Has $log 'arc import: (nothing imported|done:)' }
    } finally { Close $p }
    Verdict "X5 #52 Export and Import are greyed while an Arc import runs (decided while it read: $still)" (
        $still -and $menu -match "Export workspaces[^|]*\|[^ ]*UNAVAILABLE" -and $menu -match "Import workspaces[^|]*\|[^ ]*UNAVAILABLE")
}

# --- X6 (F9): a ruled link with no main window -------------------------------------------------------------------
if ($Cases -contains "X6") {
    Write-Host "X6: a link from another app, a site rule, no main window"
    $prof = NewProfile "x6" '[{"guid":"default","title":"Home"},{"guid":"c99w","title":"Work","sites":["c99rule.example"]}]'
    $log = LogOf "x6"
    $opened = '\[workspaces\] little window: opened window'
    function Link([string]$url) { Start-Process "$bin\chrome.exe" -ArgumentList "--user-data-dir=`"$prof`"", "--single-argument", $url -Wait }
    $p = Launch $prof $log @("--helium-workspaces-log-addresses")
    try {
        Link "https://c99free.example/"
        $one = Until 20 { @([regex]::Matches((ReadShared $log), $opened)).Count -ge 1 }
        [E18Input]::CloseWindow($p.main)
        $alone = Until 20 { -not @([E18Input]::Windows([uint32]$p.Id) | Where-Object { $_ -eq $p.main }).Count }
        Write-Host "      little window opened: $one; the main window closed, the browser still running: $alone $(-not $p.HasExited)"
        Link "https://c99rule.example/"
        $skipped = Until 20 { Has $log "little window: skipped, site rule for 'c99rule.example'" }
        $stamped = Until 20 { Has $log "tab inserted at index \d+ -> workspace 'c99w'" }
        Start-Sleep -Seconds (2 * $slow)
        $little = @([regex]::Matches((ReadShared $log), $opened)).Count
        Write-Host "      skipped: $skipped; the tab stamped for Work: $stamped; little windows opened: $little"
    } finally { Close $p }
    Verdict "X6 F9 with no main window a ruled link opens no little window and lands in its workspace" (
        $one -and $alone -and $skipped -and $stamped -and $little -eq 1)
}

# --- Z: crash markers ---------------------------------------------------------------------------------------------
$marks = 0
foreach ($l in $script:logs) { if (Test-Path -LiteralPath $l) { $marks += @(Select-String -LiteralPath $l -CaseSensitive -Pattern 'Check failed|FATAL|DanglingPtr|ReentrancyCheck|NOTREACHED').Count } }
Verdict "Z 0 crash markers in $($script:logs.Count) log(s) ($marks)" ($marks -eq 0)
Write-Host "RESULT: $script:passed passed, $script:failed failed (scratch: $scratch)"
exit $(if ($script:failed) { 1 } else { 0 })
