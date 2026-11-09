param([string]$OutDir = "Default", [string]$Tag = "e15c-auto")
# E15c without a person (LOCAL.md 46; run it after every build that touches the pinned section): a throwaway copy of the smoke profile (6 rows in 'default': Example A, Smoke folder
# (open) > Wikipedia, Renamed C, Closed folder, Example D), four launches, rows pressed through MSAA
# (msaa-press.ps1: accDoDefaultAction, what a screen reader does -- nothing is sent to the window in front),
# graded from the log and from which page tabs the accessibility tree shows (a hidden tab view is there,
# marked INVISIBLE).
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$seed  = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-$Tag"
$exe   = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$script:failed = 0
# The IANA page's tab: its own title once loaded, the item's ("Example D") when it was saved mid-load.
$iana = 'Internet Assigned Numbers|^Example D$'
function Verdict($name, $ok) { if ($ok) { "PASS  $name" } else { "FAIL  $name"; $script:failed++ } }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Msaa([string[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof @a }
function Press([string]$name, [int]$role = 0x24) { Msaa @("-Name", $name, "-Role", $role) }
# The page tabs the list DRAWS, and the pinned rows, by name.
function ShownTabs { @(Msaa @("-List") | Where-Object { $_ -match '\|0x25$' } | ForEach-Object { ($_.Trim() -split '\|')[0] }) }
function ShownRows { @(Msaa @("-List") | Where-Object { $_ -match '\|0x24$' } | ForEach-Object { ($_.Trim() -split '\|')[0] }) }
function WaitLog([string]$log, [string]$re, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and (Select-String -Path $log -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function WaitCount([string]$log, [string]$re, [int]$n, [int]$s = 20) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and @(Select-String -Path $log -Pattern $re).Count -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function Launch([string]$log) {
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    Start-Process $exe -ArgumentList "--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--restore-last-session" | Out-Null
}
function Close {
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
}
function Markers([string]$log) { @(Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running"; exit 1 }
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $seed $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path "$prof\Default\Workspace Pins")) { "ABORT: copy failed"; exit 1 }
"binary: $OutDir, $((Get-Item $exe).LastWriteTime)"

# ---- A: open (hidden, drawn as its row), close with the row's X, open two, close the window ----------
$logA = "$ws\$Tag-A.log"; Launch $logA
Verdict "A: the section drew its 6 rows" (WaitLog $logA "pins: drew 6 row\(s\) of 'default'" 30)
Start-Sleep 3
$rows = ShownRows
"      rows: $($rows -join ', ')"
Verdict "A: the accessibility tree has the 6 rows" ($rows.Count -eq 6)
$before = ShownTabs
"      list before: $($before -join ', ')"
Press "Example A"
Verdict "A: pressing 'Example A' opened its item" (WaitLog $logA "pins: opened item 'a0'$" 10)
Verdict "A: the section counts 1 open page" (WaitLog $logA "pins: 1 item page\(s\) open in this window" 10)
Start-Sleep 4
$after = ShownTabs
"      list after:  $($after -join ', ')"
Verdict "A: the item's page is NOT drawn in the list (same tabs as before)" ((Compare-Object $before $after | Measure-Object).Count -eq 0)
Press "Example A"
Start-Sleep 2
Verdict "A: pressing the open row again did not open a second page" (@(Select-String -Path $logA -Pattern "pins: opened item 'a0'$").Count -eq 1)
Press "Close page" 0x2B
Verdict "A: the row's X closed the page" (WaitLog $logA "closed the page of pinned item 'a0' \(the row's close button\)" 10)
Verdict "A: ...for real (a removal, no Recently Closed)" (WaitLog $logA "removed 1 tab\(s\), 1 anchored" 10)
Verdict "A: back to 0 open pages" (WaitLog $logA "pins: 0 item page\(s\) open in this window" 10)
Press "Wikipedia"; Start-Sleep 3
Press "Example D"
Verdict "A: two items open" (WaitLog $logA "pins: 2 item page\(s\) open in this window" 15)
Start-Sleep 4
# The owner's Amazon link: an item's address that REDIRECTS (Wikipedia's "/" -> "/wiki/Main_Page") lands
# somewhere else on its first load; that is its home, so no back arrow may show before any link is followed.
Verdict "A: a redirecting item's landing page became its home" (WaitLog $logA "anchor at index \d+ -> 'https://en\.wikipedia\.org/wiki/" 10)
Verdict "A: no back arrow shows on pages that only redirected" (@(Msaa @("-List") | Where-Object { $_ -match 'Back to the pinned page\|0x2B$' }).Count -eq 0)
# Review #3: close the ACTIVE page when its model neighbour is another open pinned page. Since C34 (patch 73,
# D14) a close lands on the tab LEFT last, and stays there even when it is a pinned page: here Example D's,
# left when Example A was pressed -- no longer the list's tab (New Tab), review #3's rule before C34. Example
# A's row is first, so its X is.
Press "Example A"
Verdict "A: a third item open" (WaitLog $logA "pins: 3 item page\(s\) open in this window" 15)
Start-Sleep 3
Press "Close page" 0x2B
Verdict "A: its X closed it" (WaitCount $logA "closed the page of pinned item 'a0' \(the row's close button\)" 2 10)
Start-Sleep 3
$title = (Get-Process -Id (Pids)[0]).MainWindowTitle
"      window title after the close: $title"
Verdict "A: the close landed on the tab left last, Example D's page (C34, D14; was review #3's list tab)" ($title -match '^Internet Assigned Numbers Authority')
# Review #4 (E15c) drew the open pages as tabs while the strip was collapsed, because the section hid there.
# Since E17b the section stays as a column of icons, so an open page must NOT also be a tab (it would show twice).
Press "Collapse tabs" 0x2B; Start-Sleep 3
$tabsCol = ShownTabs
$rowsCol = @(ShownRows)
"      collapsed list: $($tabsCol -join ', '); the section's icons: $($rowsCol -join ', ')"
Verdict "A: collapsed, the section stays as icons and the open pages are not tabs too (E17b; was review #4)" ((-not ($tabsCol -match "Wikipedia|$iana")) -and $rowsCol.Count -ge 1)
Press "Expand tabs" 0x2B; Start-Sleep 3
$tabsExp = ShownTabs
Verdict "A: expanded again, they are rows again" (-not ($tabsExp -match "Wikipedia|$iana") -and (ShownRows).Count -eq 6)
Start-Sleep 3
Close
Verdict "A: 0 markers" ((Markers $logA) -eq 0)

# ---- B: a restart brings both back, hidden --------------------------------------------------------
$logB = "$ws\$Tag-B.log"; Launch $logB
Verdict "B: both pages came back linked" (WaitLog $logB "pins: 2 item page\(s\) open in this window" 30)
Start-Sleep 3
$tabsB = ShownTabs
"      list: $($tabsB -join ', ')"
Verdict "B: neither page is drawn in the list" (-not ($tabsB -match "Wikipedia|$iana"))
Verdict "B: no page lost its item" (-not (Select-String -Path $logB -Pattern "a page's item is gone" -Quiet))
Close
Verdict "B: 0 markers" ((Markers $logB) -eq 0)

# ---- C: the Wikipedia item deleted from the file: its page becomes an ordinary tab ---------------
& python -c @"
import json
p = r'$prof\Default\Workspace Pins'
d = json.load(open(p, encoding='utf-8'))
def drop(rows):
    out = []
    for r in rows:
        if r.get('id') == 'b0':
            continue
        if r.get('type') == 'folder':
            r['children'] = drop(r.get('children', []))
        out.append(r)
    return out
d['workspaces']['default'] = drop(d['workspaces']['default'])
json.dump(d, open(p, 'w', encoding='utf-8'))
print('      removed item b0 (Wikipedia) from the pins file')
"@
$logC = "$ws\$Tag-C.log"; Launch $logC
Verdict "C: the page lost its item and became an ordinary tab" (WaitLog $logC "a page's item is gone or already open" 30)
Verdict "C: ...and lost its anchor too: Ctrl+W will close it (review #2)" (WaitLog $logC "anchor at index \d+ -> ''" 10)
Verdict "C: the other page is still linked" (WaitLog $logC "pins: 1 item page\(s\) open in this window" 10)
Start-Sleep 3
$tabsC = ShownTabs
"      list: $($tabsC -join ', ')"
Verdict "C: Wikipedia is drawn in the list now; the other page is not" (($tabsC -match 'Wikipedia') -and -not ($tabsC -match $iana))
Close
Verdict "C: 0 markers" ((Markers $logC) -eq 0)

# ---- D: Workspaces off: the section hides, the linked page is an ordinary tab -----------------------
& python "$ws\helium\local\set-workspaces-pref.py" $prof false | Out-Null
$logD = "$ws\$Tag-D.log"; Launch $logD
$null = WaitLog $logD "tab inserted at index" 30
Start-Sleep 8
$tabsD = ShownTabs
$rowsD = ShownRows
"      list: $($tabsD -join ', ')"
Verdict "D: with Workspaces off the linked page is drawn in the list" ($tabsD -match $iana)
Verdict "D: ...and no pinned row is shown" ($rowsD.Count -eq 0)
Close
Verdict "D: 0 markers" ((Markers $logD) -eq 0)
& python "$ws\helium\local\set-workspaces-pref.py" $prof true | Out-Null

# ---- E: on again: hidden again, drawn as its row ---------------------------------------------------
$logE = "$ws\$Tag-E.log"; Launch $logE
Verdict "E: on again, the page is linked again" (WaitLog $logE "pins: 1 item page\(s\) open in this window" 30)
Start-Sleep 3
$tabsE = ShownTabs
"      list: $($tabsE -join ', ')"
Verdict "E: ...and not drawn in the list" (-not ($tabsE -match $iana))
Close
Verdict "E: 0 markers" ((Markers $logE) -eq 0)

if ($script:failed) { "$($script:failed) check(s) FAILED" } else { "ALL PASS" }
