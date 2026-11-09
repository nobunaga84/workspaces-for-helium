param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$Tag = "c19")
# C19 (local/workspaces-transfer.py): the whole chain on real data, no clicks and no keys. It
#   1. exports the DAILY profile (read-only) to backups\exports\c19-check.zip,
#   2. imports that file into a FRESH copy of the smoke profile (the dry run first: it must write nothing),
#   3. starts the built browser on the copy and reads what the BROWSER says about the files it was handed, and the
#      workspace chips it draws (MSAA), then quits it.
# A window opens on the screen for about half a minute; nothing is sent to it.
#   pwsh -NoProfile -File local\check-c19.ps1 [-Build Dcheck]
#   E1  the export has the daily counts (workspaces, pinned pages, folders, archive entries) read from the daily files
#   I1  the dry run writes nothing (the copy's pins file is byte for byte as it was)
#   I2  the import ran; the copy's pins, archive and helium.workspaces equal the daily ones (parsed)
#   B1  the browser logs "pins: loaded" with the rows of the file, and "archive: loaded" with its entries
#   B2  neither file was set aside: no "Workspace Pins.bad" / "Workspace Archive.bad" beside them
#   B3  the window draws Home's pinned rows ("pins: drew N row(s) of 'default'", N as counted from the file)
#   B4  the bar draws the daily workspaces' chips by name
#   Z   0 crash markers (case-sensitive, DanglingPtr too)
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$Build"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$prof   = "$ws\testprofile-$Tag$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$log    = "$ws\$Tag$(if ($Build -eq 'Dcheck') { '-dcheck' })-run.log"
$zip    = "$ws\backups\exports\$Tag-check.zip"
$daily  = Join-Path $env:LOCALAPPDATA "Helium Workspaces\User Data"
$tool   = "$here\workspaces-transfer.py"
$slow   = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total  = 8
$script:failed = 0; $script:passed = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern $re) } else { @() } }
function WaitLog([string]$re, [int]$s = 60) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Lines $re).Count) { return $true }; Start-Sleep -Milliseconds 500 }; $false }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
if (-not (Test-Path -LiteralPath "$daily\Default\Workspace Pins")) { Abort "no daily pins file" }
E18InputType

# ---- E1: the export, and the counts read independently from the daily files
New-Item -ItemType Directory -Force "$ws\backups\exports" | Out-Null
$exp = & python $tool export $daily $zip 2>&1
$py = @'
import json, sys
d = sys.argv[1]
pins = json.load(open(d + "/Default/Workspace Pins", encoding="utf-8"))
arch = json.load(open(d + "/Default/Workspace Archive", encoding="utf-8"))
prefs = json.load(open(d + "/Default/Preferences", encoding="utf-8"))["helium"]["workspaces"]
def count(rows):
    p = f = 0
    for n in rows:
        p += n["type"] == "item"; f += n["type"] == "folder"
        a, b = count(n.get("children", [])); p += a; f += b
    return p, f
def drawn(rows):
    # AddRow: a row, then (an open folder) its children
    c = 0
    for n in rows:
        c += 1
        if n["type"] == "folder" and n.get("open"):
            c += drawn(n.get("children", []))
    return c
pages = folders = 0
for rows in pins["workspaces"].values():
    p, f = count(rows); pages += p; folders += f
items = prefs["list"]["items"]
titles = [i.get("title", "") for i in items if i.get("title")]
# The Archive keeps 60 days and drops older entries when the browser loads it: those are not a loss.
import time
cutoff = (time.time() + 11644473600 - 60 * 86400) * 1e6
aged = sum(1 for e in arch["entries"] if int(e["archived_at"]) < cutoff)
print(len(items), pages, folders, len(arch["entries"]), drawn(pins["workspaces"].get("default", [])), aged, "|".join(titles))
'@
$want = ("$($py | & python - $daily)").Trim() -split ' ', 7
$wsN, $pagesN, $foldersN, $archN, $homeRows, $aged = [int]$want[0], [int]$want[1], [int]$want[2], [int]$want[3], [int]$want[4], [int]$want[5]
$chipTitles = @($want[6] -split '\|' | Where-Object { $_ })
$haveCounts = "$exp" -match "workspaces: $wsN" -and "$exp" -match "pinned_pages: $pagesN" -and "$exp" -match "folders: $foldersN" -and "$exp" -match "archive_entries: $archN"
Verdict "E1 the export of the daily profile: $wsN workspaces, $pagesN pinned pages, $foldersN folders, $archN archive entries (read from the daily files); the tool said: $(("$exp" -replace '\s+', ' ').Substring(0, [Math]::Min(150, ("$exp" -replace '\s+', ' ').Length)))" ($haveCounts -and (Test-Path -LiteralPath $zip))

# ---- the fresh copy, and I1/I2
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$before = (Get-FileHash "$prof\Default\Workspace Pins").Hash
$dry = & python $tool import $zip $prof --dry-run 2>&1
Verdict "I1 the dry run writes nothing (pins file hash unchanged, no .transfer.bak): $("$dry".Length) chars of plan" ((Get-FileHash "$prof\Default\Workspace Pins").Hash -eq $before -and -not (Test-Path -LiteralPath "$prof\Default\Workspace Pins.transfer.bak"))
$imp = & python $tool import $zip $prof --yes 2>&1
$cmp = & python -I -c "
import json, sys
D, T = sys.argv[1] + '/Default/', sys.argv[2] + '/Default/'
ok = all(json.load(open(D + n, encoding='utf-8')) == json.load(open(T + n, encoding='utf-8')) for n in ('Workspace Pins', 'Workspace Archive'))
a = json.load(open(D + 'Preferences', encoding='utf-8'))['helium']['workspaces']; b = json.load(open(T + 'Preferences', encoding='utf-8'))['helium']['workspaces']
# An import keeps the profile's own state flags (C19.1): the rest must be equal.
for k in ('enabled', 'arc_imported_at'):
    a.pop(k, None); b.pop(k, None)
print('EQUAL' if ok and a == b else 'DIFFERENT')
" ($daily -replace '\\', '/') ($prof -replace '\\', '/')
Verdict "I2 the import ran and the copy equals the daily profile's pins, archive and workspace prefs: $cmp ($((("$imp" -split "`n") | Select-Object -Last 1)))" ("$cmp" -eq "EQUAL")
# Chips need the sidebar wide enough (as check-c4 seeds it); the toolbar's own New Tab button off.
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null

# ---- the browser's own word
Remove-Item -LiteralPath $log -EA SilentlyContinue
$a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
$bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
$main = [IntPtr]::Zero; $t0 = Get-Date
while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
if ($main -eq [IntPtr]::Zero) { Abort "no browser window" }
$okPins = WaitLog "pins: loaded \d+" 90
$okArch = WaitLog "archive: loaded \d+" 30
# A Home with no pinned rows draws no card and logs no "drew" line (only its header).
$okDraw = if ($homeRows -gt 0) { WaitLog "pins: drew \d+ row\(s\) of 'default'" 60 } else { WaitLog "pins: header 'default'" 60 }
[E18Input]::Place($main, 40, 40, 1400, 900)
Start-Sleep (3 * $slow)
$loaded = (Lines "pins: loaded (\d+)" | Select-Object -Last 1)
$archL = (Lines "archive: loaded (\d+)" | Select-Object -Last 1)
$drawL = (Lines "pins: drew (\d+) row\(s\) of 'default'" | Select-Object -Last 1)
$nPins = if ($loaded) { [int]$loaded.Matches[0].Groups[1].Value } else { -1 }
$nArch = if ($archL) { [int]$archL.Matches[0].Groups[1].Value } else { -1 }
$nDraw = if ($drawL) { [int]$drawL.Matches[0].Groups[1].Value } else { 0 }
Verdict "B1 the browser loaded the pins (${okPins}: $(if ($loaded) { $loaded.Line.Trim().Substring($loaded.Line.IndexOf('[workspaces]')) } else { 'no line' })) and the archive (${okArch}: $nArch, want $archN less the $aged entries past the 60 days)" ($okPins -and $okArch -and $nPins -ge $pagesN -and $nArch -le $archN -and $nArch -ge $archN - $aged)
Verdict "B2 neither file was set aside as .bad: pins .bad $(@(Get-ChildItem "$prof\Default" -Filter 'Workspace Pins*.bad' -EA SilentlyContinue).Count), archive .bad $(@(Get-ChildItem "$prof\Default" -Filter 'Workspace Archive*.bad' -EA SilentlyContinue).Count) (want 0, 0)" (-not @(Get-ChildItem "$prof\Default" -Filter 'Workspace *.bad' -EA SilentlyContinue).Count)
Verdict "B3 the window drew Home's pinned rows: $nDraw (counted from the file: $homeRows$(if ($homeRows -eq 0) { '; none, so only the header is logged' }))" ($okDraw -and $nDraw -eq $homeRows)
$nodes = ParseMsaaNodes @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$main) -List -Rect)
$missing = @($chipTitles | Where-Object { $t = $_; -not @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq $t }).Count })
Verdict "B4 the bar draws the daily workspaces' chips by name ($($chipTitles -join ', ')); missing: $(if ($missing.Count) { $missing -join ', ' } else { 'none' })" ($chipTitles.Count -ge 1 -and -not $missing.Count)

foreach ($w in [E18Input]::Windows([uint32]$bpid)) { [E18Input]::CloseWindow($w) }
$t0 = Get-Date
while ((Get-Process -Id $bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { Start-Sleep 1 }
$left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }); $left | Stop-Process -Force -EA SilentlyContinue
$markers = @(Get-Content -LiteralPath $log | Select-String -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count
Verdict "Z crash markers in $log ($((Get-Item $log).Length) bytes; stragglers force-stopped: $($left.Count)): $markers" ($markers -eq 0 -and (Get-Item $log).Length -gt 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag pass=$($script:passed) fail=$($script:failed) verdict=$verdict"
exit [int]($verdict -eq "FAIL")
