param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "", [int]$BigTabs = 1500,
      [ValidateSet("A", "B", "C", "D", "E", "F")][string[]]$Cases = @("A", "B", "C", "D", "E", "F"))
# Patch 98 (chunk C2, LOCAL.md 128): "Import from Arc" knows Arc's spaces and tabs by Arc's own ids, not by a title or
# a date (the negative review's arc-import F1 F2 F3 F5 F6 F7). Each case on a new scratch profile (Local State and
# Preferences copied from testprofile-e15b-smoke: vertical, Workspaces on, On startup the New Tab page; its workspace
# list replaced by the case's), HELIUM_ARC_SIDEBAR pointing at the case's made-up Arc file. The rail's + and "Import
# from Arc..." are pressed through MSAA (msaa-press.ps1), the bubble is read (MSAA too), and the browser is closed by
# WM_CLOSE (what its X sends), so its Preferences and pinned pages are written. No mouse, no keys -- but menus and
# bubbles show for a few seconds per run: run it with the PC free (the owner's word).
#   pwsh -NoProfile -File local\check-98.ps1 [-Build Dcheck] [-BinDir <dir>] [-BigTabs 1500] [-Cases D,E]
# -BigTabs (E): with MSAA connected Chromium's accessibility is on, and an import slows as the strip grows: on Dcheck
# 309 tabs took 8 s, 2,076 took 185 s, 8,000 took 46 minutes (the red run, 11-03); 1,500 keeps E's second import inside
# its wait. An MSAA call into the browser waits out a running import, so D does not read a second window during one:
# its first import waits on its READ instead, of a file on 192.0.2.1 (TEST-NET-1, no such host), which Windows gives up
# on after about 40 s -- the window answers meanwhile.
#   A   your own "Work" (with a pinned page) and Arc's "Work": Arc's goes to a workspace of its own, yours untouched
#   B   two Arc spaces named "Personal": two workspaces, each with its own pinned tab
#   C   import, rename the workspace "Job", import again after Arc gained a pinned tab and two Today tabs, one of them
#       dated before the first import: no second "Work"; both tabs come; the pinned tab goes into "New from Arc" below
#       the first; "0 tabs were skipped" (the non-web tab was counted the first time)
#   D   a second window while the first import runs (reads): its "Import from Arc..." is greyed and starts nothing
#   E   the window closed mid-import, the browser started again with --restore-last-session, import again: the tabs
#       that came back are not added twice (every tab once)
#   F   (patch 109, R2-7) E, with 5 of the restored tabs loaded and put to sleep (the Home chip's "Hibernate other
#       workspaces", one REAL right-click) before the second import: each restored tab is still known by its Arc id
#       ("already here" = the tabs that came back), so none is added twice. E's sum cannot see this: a tab imported
#       twice still adds up to every tab.
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$smoke   = "$ws\testprofile-e15b-smoke"
$scratch = "$env:TEMP\check-98-$(Get-Date -Format yyyyMMdd-HHmmss)"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$script:passed = 0; $script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Write-Host "ABORT: $why"; exit 1 }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath "$bin\chrome.exe")) { Abort "no $bin\chrome.exe" }
E18InputType
$plus   = "New tab, workspace or search"
$import = "Import from Arc$([char]0x2026)"

function Msaa([string]$prof, [string[]]$a) { "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof @a)" }
function Until([int]$s, [scriptblock]$ok) { $t = Get-Date; do { if (& $ok) { return $true }; Start-Sleep -Milliseconds 300 } while (((Get-Date) - $t).TotalSeconds -lt $s); $false }
function ReadShared([string]$file) {
    if (-not (Test-Path -LiteralPath $file)) { return "" }
    $fs = [IO.File]::Open($file, "Open", "Read", "ReadWrite, Delete")
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
function Bubble([string]$prof) { $t = Msaa $prof @("-List", "-Popup"); if ($t -match "Arc") { $t } else { "" } }

# The profile's JSON edits, in Python: a PowerShell round trip of Preferences would retype some of its values.
$null = New-Item -ItemType Directory "$scratch\files"
$helper = "$scratch\files\prefs.py"
Set-Content -LiteralPath $helper -Encoding utf8 -Value @'
import json, sys
op, path = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))
lst = d.setdefault("helium", {}).setdefault("workspaces", {}).setdefault("list", {"schema_version": 1, "items": []})
if op == "set-list":
    lst["schema_version"] = 1
    lst["items"] = json.load(open(sys.argv[3], encoding="utf-8"))
elif op == "rename":
    for item in lst["items"]:
        if item.get("title") == sys.argv[3]:
            item["title"] = sys.argv[4]
json.dump(d, open(path, "w", encoding="utf-8"))
'@

# Arc's file, made up. createdAt in Arc's seconds (since 2001); `kids` are item ids.
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 978307200
function ArcTab([string]$id, [long]$created, [string]$url = "https://example.com/c98/$id") { '{"id":"' + $id + '","createdAt":' + $created + ',"data":{"tab":{"savedURL":"' + $url + '","savedTitle":"' + $id + '"}}}' }
function ArcBox([string]$id, [string[]]$kids) { '{"id":"' + $id + '","childrenIds":[' + ((@($kids) | ForEach-Object { '"' + $_ + '"' }) -join ',') + '],"data":{"itemContainer":{}}}' }
function ArcSpace([string]$id, [string]$title) { '{"id":"' + $id + '","title":"' + $title + '","containerIDs":["pinned","' + $id + 'p","unpinned","' + $id + 'u"]}' }
function ArcFile([string]$name, [string[]]$items, [string[]]$spaces) {
    $path = "$scratch\files\$name.json"
    [IO.File]::WriteAllText($path, '{"sidebar":{"containers":[{"global":{}},{"items":[' + ($items -join ',') + '],"spaces":[' + ($spaces -join ',') + '],"topAppsContainerIDs":[]}]}}')
    $path
}

# A new scratch profile with `items` (JSON) as its workspace list and, when given, `pins` (JSON) as its pinned pages.
function NewProfile([string]$name, [string]$items, [string]$pins = "") {
    $prof = "$scratch\$name"
    $null = New-Item -ItemType Directory "$prof\Default"
    Copy-Item -LiteralPath "$smoke\Local State" "$prof\Local State"
    Copy-Item -LiteralPath "$smoke\Default\Preferences" "$prof\Default\Preferences"
    [IO.File]::WriteAllText("$scratch\files\$name-list.json", $items)
    & python -I $helper set-list "$prof\Default\Preferences" "$scratch\files\$name-list.json"
    if ($pins) { [IO.File]::WriteAllText("$prof\Default\Workspace Pins", $pins) }
    $prof
}
function LogOf([string]$name) { "$ws\e98-$name$(if ($Build -eq 'Dcheck') { '-dcheck' }).log" }
function Launch([string]$prof, [string]$sidebar, [string]$log, [string[]]$more = @()) {
    $env:HELIUM_ARC_SIDEBAR = $sidebar
    $p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList (@("--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check") + $more)
    Remove-Item Env:HELIUM_ARC_SIDEBAR
    $null = Until (20 * $slow) { $script:h = (Get-Process -Id $p.Id -EA SilentlyContinue).MainWindowHandle; $script:h -and $script:h -ne [IntPtr]::Zero }
    $p | Add-Member -NotePropertyName main -NotePropertyValue $script:h -PassThru
}
# + then "Import from Arc..." in `window` (0: the main one); the MSAA replies.
function PressImport([string]$prof, [long]$window = 0) {
    $w = if ($window) { @("-Window", $window) } else { @() }
    $null = Until (30 * $slow) { ($script:o = Msaa $prof ($w + @("-Name", $plus, "-Role", "57"))) -match "pressed" }
    $out = $script:o
    $null = Until (5 * $slow) { ($script:o = Msaa $prof ($w + @("-Popup", "-Name", $import))) -match "pressed" }
    "$out; $script:o"
}
$endRe = '\[workspaces\] arc import: (nothing imported \([a-z ]+\)|done: .*)'
function Ends([string]$log) { @([regex]::Matches((ReadShared $log), $endRe)).Count }
function Close($p) {
    if ($p.main -ne [IntPtr]::Zero) { [E18Input]::CloseWindow($p.main) }
    if (-not (Until (120 * $slow) { $p.HasExited })) { Write-Host "      did not close by its X: stopped"; Stop-Process -Id $p.Id -EA SilentlyContinue }
    Wait-Process -Id $p.Id -Timeout 30 -EA SilentlyContinue
}
# One import: launched, pressed, the end line and the bubble waited for, closed. The bubble's text is returned.
function ImportOnce([string]$prof, [string]$sidebar, [string]$log, [string[]]$more = @()) {
    $p = Launch $prof $sidebar $log $more
    try {
        Write-Host "      pressed: $(PressImport $prof)"
        $null = Until (60 * $slow) { (Ends $log) -ge 1 }
        $null = Until (10 * $slow) { ($script:b = Bubble $prof) }
        $b = "$script:b"
    } finally { Close $p }
    Write-Host "      log: $(if ((ReadShared $log) -match $endRe) { $Matches[1] } else { '(no end line)' })"
    Write-Host "      bubble: $(if ($b) { $b } else { '(none)' })"
    $b
}
function Prefs([string]$prof) { ReadShared "$prof\Default\Preferences" | ConvertFrom-Json -AsHashtable }
function List([string]$prof) { @((Prefs $prof).helium.workspaces.list.items) }
function Pins([string]$prof) { $t = ReadShared "$prof\Default\Workspace Pins"; if ($t) { ($t | ConvertFrom-Json -AsHashtable).workspaces } else { @{} } }
# "p1 New from Arc{p2}": rows by id (an Arc row's id is Arc's), a folder by its title.
function Shape($rows) { (@($rows) | Where-Object { $_ } | ForEach-Object { if ($_.type -eq "folder") { "$($_.title){$(Shape $_.children)}" } else { $_.id } }) -join " " }
# The last progress line's count: "arc import: N of M tab(s)".
function Progress([string]$log) { $m = [regex]::Matches((ReadShared $log), 'arc import: (\d+) of \d+ tab'); if ($m.Count) { [int]$m[$m.Count - 1].Groups[1].Value } else { 0 } }
function Done([string]$log) { if ((ReadShared $log) -match 'arc import: done: (\d+) tab') { [int]$Matches[1] } else { -1 } }

# --- A: your own Work --------------------------------------------------------------------------------------------
if ($Cases -contains "A") {
    Write-Host "A: your own 'Work' and Arc's 'Work'"
    $profA = NewProfile "own" '[{"guid":"default","title":"Home"},{"guid":"mine","title":"Work"}]' '{"version":2,"workspaces":{"mine":[{"id":"user-row","title":"Mine","type":"item","url":"https://example.com/c98/mine"}]}}'
    $fileA = ArcFile "own" @((ArcBox "S1p" @("p1")), (ArcTab "p1" ($now - 3600)), (ArcBox "S1u" @("t1")), (ArcTab "t1" ($now - 3600))) @((ArcSpace "S1" "Work"))
    $null = ImportOnce $profA $fileA (LogOf "own")
    $listA = List $profA; $pinsA = Pins $profA
    $arcA = @($listA | Where-Object { $_.arc_space -eq "S1" })
    $mineA = @($listA | Where-Object { $_.guid -eq "mine" })
    Write-Host "      list: $(($listA | ForEach-Object { "$($_.title)[$($_.arc_space)]" }) -join ', ')"
    Verdict "A your own Work keeps only its own pinned page ($(Shape $pinsA['mine'])), Arc's Work is a workspace of its own ($(if ($arcA.Count) { Shape $pinsA[$arcA[0].guid] } else { 'none' }))" (
        $arcA.Count -eq 1 -and $arcA[0].guid -ne "mine" -and $mineA.Count -eq 1 -and -not $mineA[0].arc_space -and
        (Shape $pinsA["mine"]) -eq "user-row" -and (Shape $pinsA[$arcA[0].guid]) -eq "p1")
}

# --- B: two spaces of one name -----------------------------------------------------------------------------------
if ($Cases -contains "B") {
    Write-Host "B: two Arc spaces named 'Personal'"
    $profB = NewProfile "twins" '[{"guid":"default","title":"Home"}]'
    $fileB = ArcFile "twins" @((ArcBox "S1p" @("p1")), (ArcTab "p1" ($now - 3600)), (ArcBox "S2p" @("p2")), (ArcTab "p2" ($now - 3600))) @((ArcSpace "S1" "Personal"), (ArcSpace "S2" "Personal"))
    $null = ImportOnce $profB $fileB (LogOf "twins")
    $listB = List $profB; $pinsB = Pins $profB
    $b1 = @($listB | Where-Object { $_.arc_space -eq "S1" }); $b2 = @($listB | Where-Object { $_.arc_space -eq "S2" })
    Write-Host "      list: $(($listB | ForEach-Object { "$($_.title)[$($_.arc_space)]" }) -join ', ')"
    Verdict "B two workspaces named Personal, one pinned tab each" (
        $b1.Count -eq 1 -and $b2.Count -eq 1 -and (Shape $pinsB[$b1[0].guid]) -eq "p1" -and (Shape $pinsB[$b2[0].guid]) -eq "p2")
}

# --- C: a second import after a rename ---------------------------------------------------------------------------
if ($Cases -contains "C") {
    Write-Host "C: import, rename to 'Job', import again"
    $profC = NewProfile "again" '[{"guid":"default","title":"Home"}]'
    $fileC1 = ArcFile "again1" @((ArcBox "S1p" @("p1")), (ArcTab "p1" ($now - 3600)), (ArcBox "S1u" @("t1", "x")), (ArcTab "t1" ($now - 3600)), (ArcTab "x" ($now - 3600) "arc://boost")) @((ArcSpace "S1" "Work"))
    $null = ImportOnce $profC $fileC1 (LogOf "again1")
    & python -I $helper rename "$profC\Default\Preferences" "Work" "Job"
    # Arc gained p2 (pinned), t3 (new) and t2 -- dated 2001, before any import: what a tab restored from Arc's archive keeps.
    $later = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 978307200 + 60
    $fileC2 = ArcFile "again2" @((ArcBox "S1p" @("p1", "p2")), (ArcTab "p1" ($now - 3600)), (ArcTab "p2" $later), (ArcBox "S1u" @("t1", "x", "t2", "t3")), (ArcTab "t1" ($now - 3600)), (ArcTab "x" ($now - 3600) "arc://boost"), (ArcTab "t2" 10), (ArcTab "t3" $later)) @((ArcSpace "S1" "Work"))
    $bubbleC = ImportOnce $profC $fileC2 (LogOf "again2")
    $listC = List $profC; $pinsC = Pins $profC
    $job = @($listC | Where-Object { $_.title -eq "Job" })
    Write-Host "      list: $(($listC | ForEach-Object { "$($_.title)[$($_.arc_space)]" }) -join ', ')"
    Verdict "C1 no second 'Work' after the rename" (@($listC | Where-Object { $_.title -eq "Work" }).Count -eq 0 -and $job.Count -eq 1)
    Verdict "C2 both new Today tabs came, the 2001 one too ($(Done (LogOf 'again2')) tab(s))" ((Done (LogOf "again2")) -eq 2)
    Verdict "C3 the new pinned tab is in 'New from Arc' below the first ($(if ($job.Count) { Shape $pinsC[$job[0].guid] }))" ($job.Count -eq 1 -and (Shape $pinsC[$job[0].guid]) -eq "p1 New from Arc{p2}")
    Verdict "C4 '0 tabs were skipped' the second time" ($bubbleC -match "\b0 tabs were skipped")
}

# --- D: a second window while the first imports ------------------------------------------------------------------
if ($Cases -contains "D") {
    Write-Host "D: a second window while the first import reads"
    $profD = NewProfile "twowin" '[{"guid":"default","title":"Home"}]'
    $logD = LogOf "twowin"
    $p = Launch $profD "\\192.0.2.1\c98\StorableSidebar.json" $logD
    try {
        $launcher = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList "--user-data-dir=`"$profD`""
        $null = Until (20 * $slow) { $launcher.HasExited -and @([E18Input]::Windows([uint32]$p.Id)).Count -eq 2 }
        $second = @([E18Input]::Windows([uint32]$p.Id) | Where-Object { $_ -ne $p.main })
        if ($second.Count -ne 1) { Write-Host "      no second window" }
        else {
            # Every press names its window: with two open, msaa-press's own "main window" is whichever Windows says
            # (the newer one, in the first try of this case -- both presses went to the second window).
            # + in `window`, then its menu by handle: a shown window of the process that is neither browser window
            # (-Popup takes the top window other than the one named, which may be the other browser window).
            function OpenMenu([long]$window) {
                $null = Until (30 * $slow) { ($script:o = Msaa $profD @("-Window", $window, "-Name", $plus, "-Role", "57")) -match "pressed" }
                $null = Until (5 * $slow) { ($script:m = @([E18Input]::Others([uint32]$p.Id, [IntPtr]::Zero) | Where-Object { @([E18Input]::Windows([uint32]$p.Id)) -notcontains $_ })).Count -ge 1 }
                if ($script:m.Count) { [long]$script:m[0] } else { 0 }
            }
            $menuA = OpenMenu ([long]$p.main)
            Write-Host "      first window ($([long]$p.main)): menu $menuA, $(Msaa $profD @('-Window', $menuA, '-Name', $import))"
            $null = Until (20 * $slow) { (ReadShared $logD) -match 'arc import: reading' }
            $menuWin = OpenMenu ([long]$second[0])
            $menuD = Msaa $profD @("-Window", $menuWin, "-List", "-States")
            $stillD = (Ends $logD) -eq 0
            $pressD = Msaa $profD @("-Window", $menuWin, "-Name", $import)
            Write-Host "      second window ($([long]$second[0])): menu $menuWin, item: $(if ($menuD -match 'Import from Arc[^|]*\|[^ ]*') { $Matches[0] } else { '(not listed)' })"
            Write-Host "      second window's press: $pressD; the first still importing then: $stillD"
            $null = Until (180 * $slow) { (Ends $logD) -ge 1 }
            Start-Sleep -Seconds (3 * $slow)
        }
    } finally { Close $p }
    $readsD = @([regex]::Matches((ReadShared $logD), 'arc import: reading')).Count
    Write-Host "      'reading' lines: $readsD, end lines: $(Ends $logD)"
    Verdict "D the second window's Import from Arc is greyed and starts nothing (decided while the first still ran: $stillD)" (
        $second.Count -eq 1 -and $stillD -and $menuD -match "Import from Arc[^|]*\|[^ ]*UNAVAILABLE" -and $readsD -eq 1)
}

# --- E: closed mid-import, restored, imported again --------------------------------------------------------------
if ($Cases -contains "E") {
    Write-Host "E: the window closed mid-import, restored, imported again"
    $ids = 1..$BigTabs | ForEach-Object { "b$_" }
    $fileBig = ArcFile "big" (@(ArcBox "SBu" $ids) + @($ids | ForEach-Object { ArcTab $_ ($now - 3600) })) @((ArcSpace "SB" "Big"))
    $profE = NewProfile "cutoff" '[{"guid":"default","title":"Home"}]'
    $logE1 = LogOf "cutoff1"; $logE2 = LogOf "cutoff2"
    $p = Launch $profE $fileBig $logE1
    try {
        Write-Host "      pressed: $(PressImport $profE)"
        $null = Until (60 * $slow) { (Progress $logE1) -ge 300 }
        $atClose = Progress $logE1
    } finally { Close $p }
    Write-Host "      closed at about $atClose of $BigTabs; first log ends: $(if ((ReadShared $logE1) -match $endRe) { $Matches[1] } else { '(no end line: the importer went with its window)' })"
    $null = ImportOnce $profE $fileBig $logE2 @("--restore-last-session")
    $onTabs = if ((ReadShared $logE2) -match 'already here, (\d+) on open tabs') { [int]$Matches[1] } else { 0 }
    $doneE = Done $logE2
    # Decisive only when the first import was cut off: no "done:" line, or one that says "aborted".
    $cutE = -not ((ReadShared $logE1) -match 'arc import: done: .*' -and $Matches[0] -notmatch 'aborted')
    Write-Host "      second import: $onTabs already on open tabs, $doneE imported"
    Verdict "E every tab once: $onTabs restored + $doneE imported = $BigTabs (the first import cut off: $cutE)" ($cutE -and $onTabs -gt 0 -and $onTabs + $doneE -eq $BigTabs)
}

# --- F: E, with restored tabs put to sleep before the second import (patch 109, R2-7) ---------------------------
if ($Cases -contains "F") {
    Write-Host "F: closed mid-import, restored, 5 restored tabs loaded and put to sleep, imported again"
    $ids = 1..$BigTabs | ForEach-Object { "b$_" }
    $fileF = ArcFile "asleep" (@(ArcBox "SBu" $ids) + @($ids | ForEach-Object { ArcTab $_ ($now - 3600) })) @((ArcSpace "SB" "Big"))
    $profF = NewProfile "asleep" '[{"guid":"default","title":"Home"}]'
    $logF1 = LogOf "asleep1"; $logF2 = LogOf "asleep2"
    $p = Launch $profF $fileF $logF1
    try {
        Write-Host "      pressed: $(PressImport $profF)"
        $null = Until (60 * $slow) { (Progress $logF1) -ge 300 }
        $atClose = Progress $logF1
    } finally { Close $p }
    $cutF = -not ((ReadShared $logF1) -match 'arc import: done: .*' -and $Matches[0] -notmatch 'aborted')
    Write-Host "      closed at about $atClose of $BigTabs (cut off: $cutF)"
    $restoredN = 0; $asleep = 0; $onTabsF = 0; $doneF = -1
    $p = Launch $profF $fileF $logF2 @("--restore-last-session", "--remote-debugging-port=0")
    try {
        $null = Until (20 * $slow) { Test-Path -LiteralPath "$profF\DevToolsActivePort" }
        $base = "http://127.0.0.1:$([int](Get-Content -LiteralPath "$profF\DevToolsActivePort" -TotalCount 1))/json"
        function BigPages { try { @((Invoke-RestMethod -TimeoutSec 20 "$base/list") | Where-Object { $_.type -eq "page" -and $_.url -like "*/c98/b*" }) } catch { @() } }
        # The restore done: the same count twice, 3 s apart.
        $script:last = -1
        $null = Until (90 * $slow) { $n = @(BigPages).Count; $same = $n -gt 0 -and $n -eq $script:last; $script:last = $n; Start-Sleep 3; $same }
        $restoredN = @(BigPages).Count
        # Loaded first: a restored tab never shown has no page to put to sleep (discard_eligibility_policy.cc,
        # kNoMainFrame). /json/activate shows each, which takes the window to Big.
        foreach ($t in @(BigPages | Select-Object -First 5)) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$base/activate/$($t.id)" } catch {}; Start-Sleep (3 * $slow) }
        # Home's chip is the bottom-most "Home" push button (a toolbar Home button may come first in the tree).
        # Line by line: Msaa above joins its reply into one string.
        function HomeChip { @(ParseMsaaNodes @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $profF -Window ([long]$p.main) -List -Rect) | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq "Home" } | Sort-Object t) | Select-Object -Last 1 }
        $chip = HomeChip
        $toHome = if ($chip) { [E18Input]::Click($p.main, $chip.l + [int]($chip.w / 2), $chip.t + [int]($chip.h / 2), $false) } else { "no Home chip" }
        $onHome = Until (10 * $slow) { (ReadShared $logF2) -match "active workspace -> 'default'" }
        Start-Sleep (2 * $slow)
        $chip = HomeChip
        $rc = if ($chip) { [E18Input]::Click($p.main, $chip.l + [int]($chip.w / 3), $chip.t + [int]($chip.h / 2), $true) } else { "no Home chip" }
        Start-Sleep -Milliseconds (800 * $slow)
        $null = Until (5 * $slow) { ($script:o = Msaa $profF @("-Popup", "-Name", "Hibernate other workspaces")) -match "pressed" }
        $null = Until (15 * $slow) { (ReadShared $logF2) -match "unload all but 'default': asking \d+" }
        Start-Sleep (3 * $slow)
        $asleep = [regex]::Matches((ReadShared $logF2), "tab contents replaced at index \d+ -> carried workspace '(?!default')").Count
        Write-Host "      restored $restoredN; to Home ($toHome) $onHome; Home's menu ($rc) > Hibernate other workspaces ($script:o): $asleep put to sleep"
        Write-Host "      pressed: $(PressImport $profF)"
        $null = Until (120 * $slow) { (Ends $logF2) -ge 1 }
        $onTabsF = if ((ReadShared $logF2) -match 'already here, (\d+) on open tabs') { [int]$Matches[1] } else { 0 }
        $doneF = Done $logF2
    } finally { Close $p }
    Write-Host "      second import: $onTabsF already on open tabs, $doneF imported"
    Verdict "F every restored tab known after a sleep: $onTabsF already here = $restoredN restored, $onTabsF + $doneF imported = $BigTabs; $asleep put to sleep (want 1+), the first import cut off $cutF" ($cutF -and $asleep -ge 1 -and $restoredN -gt 0 -and $onTabsF -eq $restoredN -and $onTabsF + $doneF -eq $BigTabs)
}

Write-Host "$script:passed passed, $script:failed failed (scratch folder $scratch)"
exit [int]($script:failed -gt 0)
