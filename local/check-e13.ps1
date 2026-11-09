param([string]$Log = "<local-path>\Helium-workspace\e13-run.log", [switch]$GradeOnly, [switch]$OnlyClear)
# E13 patch 28 (LOCAL.md 34): the three HIGH bugs from the 2026-09-18 review.
#   - Close all tabs on Home no longer closes pinned tabs.
#   - Moving a tab out of a group takes it out of the group; a split moves whole; a whole
#     group selected moves as a group; a shift-click range never moves a tab this window hides.
#   - A custom tab title survives a plain restart (no Ctrl+Shift+T in between), and so does
#     clearing it.
# Three launches, owner-driven, graded from the logs. Every page has a DISTINCT title, so each
# tab can be told apart in the strip (LOCAL.md 23). -GradeOnly re-grades existing logs.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")
$Log2 = $Log -replace '\.log$','-restart.log'
$Log3 = $Log -replace '\.log$','-restart2.log'

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\28-e13-fixes.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no $live" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
foreach ($f in 'workspace_service\.cc','workspace_service\.h','workspace_session_data\.cc') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f -- an edit was not quilt-added (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
$items = (Get-Content "$prof\Default\Preferences" -Raw | ConvertFrom-Json).helium.workspaces.list.items
$work = @($items | Where-Object { $_.guid -ne 'default' })[0]
if (-not $work) { Write-Host "ABORT: no non-default workspace" -ForegroundColor Red; exit 1 }
$guid = $work.guid; $Ws = $work.title.ToUpper()  # not $W: PowerShell names ignore case, and $w is the log
Write-Host "the workspace the tabs move to is '$($work.title)' = $guid"

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }

if ($OnlyClear) {
    $LogA = "<local-path>\Helium-workspace\e13-clear-run.log"; $LogB = "<local-path>\Helium-workspace\e13-clear-run-restart.log"
    if (-not $GradeOnly) {
        Remove-Item $LogA, $LogB -EA SilentlyContinue
        Write-Host @"

E13 CLEAR LEG, launch 1 of 2 -- the last session is restored.

  1. [any]   click $Ws in the rail, then LEFT-click the renamed tab (it reads GAMMA-something).
  2. [$Ws]  right-click it -> "Rename tab...", DELETE everything in the field so it is empty, OK.
             EXPECT: the tab reads "Wikipedia" again.
  3. Close the browser window.

"@ -ForegroundColor Yellow
        Start-Process -FilePath $exe -ArgumentList ($flags + @("--restore-last-session","--log-file=$LogA")) -Wait
        Start-Sleep 2
        Write-Host @"

E13 CLEAR LEG, launch 2 of 2 -- restored again.

  4. [any]   click $Ws in the rail.  EXPECT: the tab still reads "Wikipedia".
  5. Close the browser window.

"@ -ForegroundColor Yellow
        Start-Process -FilePath $exe -ArgumentList ($flags + @("--restore-last-session","--log-file=$LogB")) -Wait
        Start-Sleep 2
    }
    foreach ($l in $LogA, $LogB) { if (-not (Test-Path $l) -or (Get-Item $l).Length -eq 0) { Write-Host "FAIL: $l missing or EMPTY" -ForegroundColor Red; exit 1 } }
    $ta = (@(Get-Content $LogA | Where-Object { $_ -match '\[workspaces\]' })) -join "`n"
    $tb = (@(Get-Content $LogB | Where-Object { $_ -match '\[workspaces\]' })) -join "`n"
    Verdict "launch 1: a title was restored (the thing about to be cleared)" ($ta -match "restored custom title '.+'")
    Verdict "step 2: the title was cleared to empty"                           ($ta -match "custom title at index \d+ -> ''")
    $n = ([regex]::Matches($tb, "tab inserted at index \d+ -> workspace '$guid'")).Count
    Verdict "step 4: $n tab(s) restored into $Ws and no title came back"       (($n -gt 0) -and -not ($tb -match "restored custom title"))
    $crash = @(Select-String -Path $LogA, $LogB -Pattern 'Check failed|FATAL|NOTREACHED').Count
    Verdict "no Check failed / FATAL / NOTREACHED ($crash)" ($crash -eq 0)
    exit 0
}

if (-not $GradeOnly) {
Remove-Item $Log, $Log2, $Log3 -EA SilentlyContinue
Write-Host @"

E13, launch 1 of 3 -- every step says which workspace you are IN. The rail is at the
bottom of the tab strip. Do NOT press Ctrl+Shift+T anywhere in this launch.

 A. CLOSE ALL KEEPS PINNED TABS
  1. [Home]  in the tab that is open, go to  https://example.com
  2. [Home]  Ctrl+T, go to  https://www.iana.org , right-click that tab -> Pin.
  3. [Home]  Ctrl+T, go to  https://www.wikipedia.org
  4. [Home]  right-click HOME in the rail -> "Close all tabs".
             EXPECT: Example Domain and Wikipedia close. The pinned IANA tab STAYS.

 B. A TAB MOVED OUT OF A GROUP LEAVES THE GROUP
  5. [Home]  open three tabs, in this order:  https://example.com ,
             https://www.wikipedia.org ,  https://duckduckgo.com
  6. [Home]  click Example Domain, Shift+click DuckDuckGo (all three selected),
             right-click one of them -> "Add tabs to new group".
  7. [Home]  click the pinned IANA tab (so only it is selected). Then right-click
             WIKIPEDIA (the middle one) -> "Move tab to workspace" -> $Ws.
             EXPECT: Wikipedia leaves Home. The group stays here with the other two.
  8. [Home]  click Example Domain, Ctrl+click DuckDuckGo (both group tabs selected),
             right-click either -> "Move tab to workspace" -> $Ws.
             EXPECT: the whole group leaves Home.

 C. A SPLIT MOVES WHOLE
  9. [Home]  Ctrl+T  https://example.net , Ctrl+T  https://en.wikipedia.org/wiki/Arc_(web_browser)
             Click the example.net tab, Ctrl+click the Arc tab, right-click one ->
             the item that makes a SPLIT VIEW (it has "split" in its name).
             EXPECT: the two pages side by side.
 10. [Home]  click the pinned IANA tab. Then right-click ONE half of the split ->
             "Move tab to workspace" -> $Ws.
             EXPECT: BOTH halves leave Home.

 E. A SHIFT-CLICK RANGE NEVER TAKES A HIDDEN TAB
 E1. [Home]  open three tabs, in this order:  https://example.com ,
             https://www.rfc-editor.org ,  https://www.w3.org
 E2. [Home]  click + in the rail -> New workspace, type  EMPTY , press Enter. The window shows
             EMPTY, the pinned IANA tab in front (EMPTY has no tab of its own). Click HOME in the
             rail. Then right-click RFC EDITOR (the middle one) -> "Move tab to workspace" -> EMPTY.
             EXPECT: it leaves Home. (EMPTY has no tab, so it stays where it was -- between the
             other two, just hidden. Into $Ws it would land at the top of $Ws's tabs: C4.)
 E3. [Home]  click Example Domain, then Shift+click W3C -- a range over the hidden tab.
             Right-click $Ws in the rail.  EXPECT: the first item reads "Move 2 tabs
             here" -- NOT 3. Click it.  EXPECT: Example Domain and W3C leave Home.

 D. THE RENAME, THEN A PLAIN RESTART
 11. [Home]  click $Ws in the rail.
             EXPECT, top first: W3C and Example Domain (in the order Home drew them), the
             split, the group of two, Wikipedia on its own (NOT in a group) -- each move put
             its tabs at the TOP of $Ws (C4).
 12. [$Ws]  right-click Wikipedia -> "Rename tab...", type  GAMMA , OK.
             EXPECT: the tab reads GAMMA.
 13. Close the browser window. Nothing else in between.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

Write-Host @"

E13, launch 2 of 3 -- the last session is restored.

 14. [any]   click $Ws in the rail.
             EXPECT: the tab still reads GAMMA (the fix). Group and split are back too.
 15. [$Ws]  right-click GAMMA -> "Rename tab...", CLEAR the field, OK.
             EXPECT: it reads "Wikipedia" again.
 16. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--restore-last-session","--log-file=$Log2")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log2) -or (Get-Item $Log2).Length -eq 0) { Write-Host "FAIL: launch 2 log missing or EMPTY" -ForegroundColor Red; exit 1 }

Write-Host @"

E13, launch 3 of 3 -- restored again.

 17. [any]   click $Ws in the rail.
             EXPECT: the tab reads "Wikipedia" -- the cleared name stayed cleared.
 18. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--restore-last-session","--log-file=$Log3")) -Wait
Start-Sleep 2
}
foreach ($l in $Log, $Log2, $Log3) { if (-not (Test-Path $l) -or (Get-Item $l).Length -eq 0) { Write-Host "FAIL: $l missing or EMPTY" -ForegroundColor Red; exit 1 } }

$w  = @(Get-Content $Log  | Where-Object { $_ -match '\[workspaces\]' })
$w2 = @(Get-Content $Log2 | Where-Object { $_ -match '\[workspaces\]' })
$w3 = @(Get-Content $Log3 | Where-Object { $_ -match '\[workspaces\]' })
foreach ($pair in @(@('launch 1', $w), @('launch 2', $w2), @('launch 3', $w3))) {
    Write-Host "`n--- $($pair[0]) [workspaces] lines: $($pair[1].Count) ---"; $pair[1] | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
}
Write-Host ""
$j = $w -join "`n"; $j2 = $w2 -join "`n"; $j3 = $w3 -join "`n"

# A: Home holds the pinned IANA tab plus Example Domain and Wikipedia; before E13 it said 3.
$close = @($w | Where-Object { $_ -match "closing \d+ tab\(s\) of workspace 'default'" })
$kept = if ($close.Count) { [regex]::Match($close[0], '(\d+) pinned kept').Groups[1].Value } else { '' }
Write-Host "step 4: $(if ($close.Count) { $close[0] -replace '^.*\] ','' } else { 'no close line' })"
Verdict "step 4: 'Close all tabs' on Home kept the pinned tab(s) ($kept kept)" ($kept -ne '' -and [int]$kept -ge 1)

# B + C + E3 into $Ws, in the order the owner did them; E2 into EMPTY, the workspace made just before it.
$moves = @($w | Where-Object { $_ -match "moved \d+ tab\(s\) -> workspace '$guid'" } | ForEach-Object { [regex]::Match($_, 'moved (\d+) tab\(s\).*, (\d+) left their group').Groups | Select-Object -Skip 1 | ForEach-Object { $_.Value } } )
$pairs = @(for ($i = 0; $i -lt $moves.Count; $i += 2) { "$($moves[$i])/$($moves[$i+1])" })
Write-Host "moves (moved/left their group), in order: $($pairs -join ', ')"
# Matched by position, so the count must be exact: a missing or repeated move shifts every later
# pair onto the wrong step, and would pass one step on another step's line (E13 review).
$four = $pairs.Count -eq 4
if (-not $four) { Write-Host "expected exactly 4 moves into $Ws (steps 7, 8, 10, E3), got $($pairs.Count) -- every move verdict but E2's fails" -ForegroundColor Red }
$fresh = @($w | ForEach-Object { if ($_ -match "created workspace '([^']+)'") { $Matches[1] } }) | Select-Object -Last 1
$intoFresh = @($w | Where-Object { $fresh -and $_ -match "moved \d+ tab\(s\) -> workspace '$fresh'" })
Verdict "step 7: the middle tab moved alone and LEFT its group (1/1)"   ($four -and $pairs[0] -eq '1/1')
Verdict "step 8: the whole group moved as a group (2/0)"              ($four -and $pairs[1] -eq '2/0')
Verdict "step 10: one half of a split picked, both moved (2/0)"        ($four -and $pairs[2] -eq '2/0')
# Placed nowhere: EMPTY had no tab, so RFC stays between the other two, the hidden tab E3's range needs.
Verdict "step E2: the middle tab moved alone into EMPTY and stayed in place (1/0, none placed)" ($intoFresh.Count -eq 1 -and $intoFresh[0] -match "moved 1 tab\(s\) -> workspace '[^']+', 0 left their group, none placed")
Verdict "step E3: a range over a hidden tab moved only the 2 on screen" ($four -and $pairs[3] -eq '2/0')

# D: the path under test is the plain restart, so launch 1 must NOT have restored the title
# itself -- a Ctrl+Shift+T there forces the full session rewrite E11's test passed through.
Verdict "step 12: GAMMA was set"                                        ($j -match "custom title at index \d+ -> 'GAMMA'")
Verdict "step 13 (control): no title restore in launch 1"               (-not ($j -match "restored custom title"))
Verdict "step 14: the plain restart restored GAMMA"                     ($j2 -match "restored custom title 'GAMMA'")
Verdict "step 15: GAMMA was cleared to empty"                           ($j2 -match "custom title at index \d+ -> ''")
$restored3 = @($w3 | Where-Object { $_ -match "tab inserted at index \d+ -> workspace '$guid'" }).Count
Verdict "step 17: launch 3 restored $restored3 tab(s) into $Ws, and after the step-15 clear no title came back" (($j2 -match "custom title at index \d+ -> ''") -and ($restored3 -gt 0) -and -not ($j3 -match "restored custom title"))

$crash = @(Select-String -Path $Log, $Log2, $Log3 -Pattern 'Check failed|FATAL|NOTREACHED').Count
Verdict "no Check failed / FATAL / NOTREACHED in the three logs ($crash)" ($crash -eq 0)
