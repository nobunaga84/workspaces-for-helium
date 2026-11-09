param([string]$OutDir = "Default", [string]$Tag = "e15c1-auto", [switch]$SkipBig)
# E15c.1 without a person (LOCAL.md 47): where a new tab opens, as Arc places it (read from the owner's own
# Arc sidebar file) -- a new tab ("+ New Tab", Ctrl+T) at the TOP of the list; a link from a pinned page at
# the top too, after the earlier links from that page. (A link from a Today tab stays just below it --
# Chromium's own rule, unchanged -- in the owner's check-e15c1.ps1.) Pressed through MSAA (msaa-press.ps1:
# what a screen reader does, nothing sent to the window in front), graded from the log and from the order
# the list DRAWS its tabs in (by position: the tree's order is the order they were added).
#   S  a copy of the smoke profile plus a pinned page that opens two links itself (e15c1-page.html)
#   O  the same copy with Workspaces off: a new tab opens at the end, as stock Chromium
#   T  a copy of testprofile (444 tabs, 5 workspaces): the top of each workspace's list, and how long the
#      window was busy -- every tab below a top insert is written to the session again (-SkipBig skips it)
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof  = "$ws\testprofile-$Tag"
$exe   = "$ws\helium-windows\build\src\out\$OutDir\chrome.exe"
$page  = "file:///" + ("$here\e15c1-page.html" -replace '\\', '/')
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { "PASS  $name" } else { "FAIL  $name"; $script:failed++ } }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Msaa([string[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof @a }
function Press([string]$name, [int]$role = 0x24) { Msaa @("-Name", $name, "-Role", $role) }
# The list's tabs as DRAWN, top to bottom, with where each is: hidden ones are marked INVISIBLE, favorites
# ("<title> - Pinned") sit above the list -- both left out. Sorted by position, not tree order: a tab
# inserted mid-list is the LAST child in the tree and placed by the layout (msaa-press.ps1 -Where).
function ListTabs {
    @(Msaa @("-List", "-Where") | ForEach-Object {
        # A favorite may carry a state after " - Pinned": testprofile's made-up ones never load, so the one in
        # front reads "<title> - Pinned - Network error" (LOCAL.md 133).
        if ($_ -match '^\s*(.*)\|0x25\|@(-?\d+),(\d+)$' -and $Matches[1] -notmatch ' - Pinned( - .+)?$') {
            [pscustomobject]@{ name = $Matches[1]; top = [int]$Matches[2]; height = [int]$Matches[3] }
        }
    } | Sort-Object top)
}
function ShownTabs { @(ListTabs | ForEach-Object { $_.name }) }
# The list is exactly `before` with one "New Tab" put at `at` (0 = the top, -1 = the end).
function Inserted($before, $after, [int]$at) {
    # -ne $null: an empty list comes back from a function as $null, and @($null) is ONE item.
    $expect = [System.Collections.ArrayList]@(@($before) -ne $null)
    if ($at -lt 0) { $null = $expect.Add('New Tab') } else { $expect.Insert($at, 'New Tab') }
    return (($after -join '|') -eq ($expect -join '|'))
}
# The close button of the list's FIRST drawn tab: the shown "Close" whose top lies within that tab (the
# window's own "Close" is first in the tree). -Nth counts shown "Close" buttons in tree order, as Press does.
function PressFirstTabClose {
    $first = @(ListTabs)[0]
    if (-not $first) { return "no list tab" }
    $closes = @(Msaa @("-List", "-Where") | Where-Object { $_ -match '^\s*Close\|0x2B\|@-?\d+,\d+$' })
    for ($i = 0; $i -lt $closes.Count; $i++) {
        $y = [int](($closes[$i] -split '@')[1] -split ',')[0]
        if ($y -ge $first.top -and $y -lt $first.top + $first.height) { return (Msaa @("-Name", "Close", "-Role", 0x2B, "-Nth", $i)) }
    }
    return "no close button on the first list tab"
}
function NewTabButtons { @(Msaa @("-List") | Where-Object { $_ -match '^\s*New Tab\|0x2B$' }).Count }
function Title { (Get-Process -Id (Pids)[0]).MainWindowTitle }
function Placed([string]$log) { @(Select-String -Path $log -Pattern "\[workspaces\] new tab at index") }
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
    Start-Process $exe -ArgumentList "--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session" | Out-Null
}
function Close {
    foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    $t = Get-Date
    while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
    if ((Pids).Count) { "      (force-stopped: a throwaway profile)"; Pids | ForEach-Object { Stop-Process -Id $_ -Force }; Start-Sleep 2 }
}
function Markers([string]$log) { @(Select-String -Path $log -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }
function Show([string]$what, $tabs) { "      $what" + ": " + (($tabs | Select-Object -First 6) -join ', ') + $(if ($tabs.Count -gt 6) { ", ... ($($tabs.Count))" }) }

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { "ABORT: a fork browser is running"; exit 1 }
"binary: $OutDir, $((Get-Item $exe).LastWriteTime)"

# ---- S: the smoke profile plus a pinned page with two links -------------------------------------------
if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path "$prof\Default\Workspace Pins")) { "ABORT: copy failed"; exit 1 }
& python -c @"
import json
p = r'$prof\Default\Workspace Pins'
d = json.load(open(p, encoding='utf-8'))
d['workspaces']['default'].append({'type': 'item', 'id': 'lk', 'title': 'Links page', 'url': r'$page'})
json.dump(d, open(p, 'w', encoding='utf-8'))
print('      added the pinned page Links page to the pins file')
# A press through MSAA is not a user click, so the popup blocker stops a new-tab link: allow popups here.
q = r'$prof\Default\Preferences'
e = json.load(open(q, encoding='utf-8'))
e.setdefault('profile', {}).setdefault('default_content_setting_values', {})['popups'] = 1
# Since patch 70 (wish 6c.1) the toolbar draws its own New Tab button while this switch is on (the default): the
# checks here count the sidebar's buttons named New Tab, so the toolbar's is switched off in the copy (LOCAL.md 84).
e.setdefault('helium', {}).setdefault('browser', {})['show_dynamic_new_tab_button'] = False
json.dump(e, open(q, 'w', encoding='utf-8'))
print('      allowed popups in the copy; the toolbar New Tab button off')
"@
# No double quote in that Python: Windows PowerShell 5.1 cuts a native argument at one.
$logS = "$ws\$Tag-S.log"; Launch $logS
Verdict "S: the section drew its 7 rows" (WaitLog $logS "pins: drew 7 row\(s\) of 'default'" 30)
Start-Sleep 3
Verdict "S: '+ New Tab' is shown once -- the section's; the bottom one is hidden" ((NewTabButtons) -eq 1)
$t0 = ShownTabs; Show "list before" $t0
# The page opens '#one' itself when first shown (e15c1-page.html): a link from the pinned page.
Press "Links page"
Verdict "S: the pinned page opened" (WaitLog $logS "pins: opened item 'lk'$" 10)
Verdict "S: a link from the pinned page was placed by the fork (log)" (WaitLog $logS "new tab at index \d+ \(a link from a pinned page\)" 15)
Start-Sleep 3
$t1 = ShownTabs; Show "list" $t1
Verdict "S: ...at the top of the list" (($t1 -join '|') -eq ((@('E15c1 one') + $t0) -join '|'))
# Shown again, it opens '#two'.
Press "Links page"
Verdict "S: a second link from it (log)" (WaitCount $logS "\(a link from a pinned page\)" 2 15)
Start-Sleep 3
$t2 = ShownTabs; Show "list" $t2
Verdict "S: ...after the first, as Arc does (one, two)" (($t2 -join '|') -eq ((@('E15c1 one', 'E15c1 two') + $t0) -join '|'))
"      window: $(Title)"
Press "New Tab" 0x2B
Verdict "S: '+ New Tab' was placed at the top of the list (log)" (WaitLog $logS "new tab at index \d+ \(the top of the list\): the window was busy \d+ ms" 10)
Start-Sleep 3
$t3 = ShownTabs; Show "list" $t3
Verdict "S: ...and is drawn first, above the links' tabs" (Inserted $t2 $t3 0)
# Chromium's quick look-up: a new tab remembers the tab it was opened from, so closing it goes back
# there ('E15c1 two', active before) and not to the tab below it ('E15c1 one').
"      " + (PressFirstTabClose)
Start-Sleep 3
$t4 = ShownTabs; Show "list" $t4; "      window: $(Title)"
Verdict "S: closing the new tab went back to where the user was, not to the tab below it" (((Title) -match '^E15c1 two') -and (($t4 -join '|') -eq ($t2 -join '|')))
# A link from a TODAY tab stays just below it -- Chromium's own rule, which the fork leaves alone -- is the
# owner's step 5 (check-e15c1.ps1): an MSAA press on a link opens nothing, and the page trick is its own.
Close
Verdict "S: 0 markers" ((Markers $logS) -eq 0)

# ---- O: Workspaces off: stock Chromium, a new tab at the end ------------------------------------------
& python "$ws\helium\local\set-workspaces-pref.py" $prof false | Out-Null
$logO = "$ws\$Tag-O.log"; Launch $logO
$null = WaitLog $logO "tab inserted at index" 30
Start-Sleep 8
Verdict "O: one New Tab button, the bottom one (the section is hidden)" ((NewTabButtons) -eq 1)
$before = ShownTabs; Show "list before" $before
Press "New Tab" 0x2B
Start-Sleep 4
$after = ShownTabs; Show "list after" $after
Verdict "O: the new tab opened at the END of the list" (Inserted $before $after -1)
Verdict "O: ...and the fork did not place it" ((Placed $logO).Count -eq 0)
Close
Verdict "O: 0 markers" ((Markers $logO) -eq 0)
& python "$ws\helium\local\set-workspaces-pref.py" $prof true | Out-Null

# ---- T: testprofile, every workspace: the top of its list, and the time ------------------------------
if (-not $SkipBig) {
    $prof = "$ws\testprofile-$Tag-big"
    if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy "$ws\testprofile" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 /XD "Cache" "Code Cache" "GPUCache" "GrShaderCache" "GraphiteDawnCache" "ShaderCache" "DawnWebGPUCache" "DawnGraphiteCache" "Service Worker"
    if (-not (Test-Path "$prof\Default\Preferences")) { "ABORT: copy failed"; exit 1 }
    $logT = "$ws\$Tag-T.log"; Launch $logT
    $null = WaitLog $logT "pins: drew" 60
    # Restored when the inserts stop coming.
    $n = -1; $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt 120) { Start-Sleep 5; $m = @(Select-String -Path $logT -Pattern "tab inserted at index").Count; if ($m -eq $n) { break }; $n = $m }
    "      restored: $n tab insert(s)"
    foreach ($w in "Home", "Work", "Canary", "Private", "Unpin") {
        $r = Press $w 0x2B
        if ($r -notmatch 'pressed') { "      (no rail button '$w')"; continue }
        Start-Sleep 3
        $before = ShownTabs
        $k = (Placed $logT).Count
        $null = Press "New Tab" 0x2B
        if (WaitCount $logT "\[workspaces\] new tab at index" ($k + 1) 15) {
            "MEASURE  ${w}: " + ((Placed $logT)[-1].Line -replace '^.*\] new tab', 'new tab')
        } else { "MEASURE  ${w}: not placed by the fork (an empty list goes to the end)" }
        Start-Sleep 3
        $after = ShownTabs
        if (-not (Inserted $before $after 0)) { Show "before" $before; Show "after" $after }
        Verdict "T: '$w': the new tab is drawn first, the other $($before.Count) in their order" (Inserted $before $after 0)
    }
    Close
    Verdict "T: 0 markers" ((Markers $logT) -eq 0)
}

if ($script:failed) { "$($script:failed) check(s) FAILED" } else { "ALL PASS" }
