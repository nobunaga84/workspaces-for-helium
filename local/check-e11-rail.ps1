# historical (pre-E17): E17a replaced "Change icon" with "Edit workspace..." (its "Custom emoji..." writes the icon).
param([string]$Log = "<local-path>\Helium-workspace\e11-rail-run.log", [switch]$GradeOnly)
# E11 patch 23 (LOCAL.md 31): the four rail-menu items -- Change icon, Hibernate this workspace,
# Hibernate other workspaces, Close all tabs. One launch, owner-driven, graded from the log and
# from the Preferences file the browser writes on exit.
#
# Every window in this script is bounded by an event the browser logged, never by a line
# count (LOCAL.md 30): "the replaced lines AFTER the unload line and BEFORE the next thing the
# owner did" is the question, not "the next 2". -GradeOnly re-grades an existing log.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$prefs = "$prof\Default\Preferences"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\23-icon-unload-close.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no 23-icon-unload-close.patch" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
foreach ($f in 'workspace_prefs\.h','workspace_service\.h','workspace_rail_view\.h','generated_resources\.grd') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f -- an edit was not quilt-added (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
$items = (Get-Content $prefs -Raw | ConvertFrom-Json).helium.workspaces.list.items
$work = @($items | Where-Object { $_.guid -ne 'default' })[0]
if (-not $work) { Write-Host "ABORT: no non-default workspace" -ForegroundColor Red; exit 1 }
$guid = $work.guid
Write-Host "the non-default workspace is '$($work.title)' = $guid"
if (-not $GradeOnly) {
Remove-Item $Log -EA SilentlyContinue

Write-Host @"

E11 RAIL MENU -- every step says which workspace you are IN. The rail is at the bottom
of the tab strip; right-click a workspace button to get its menu.

 1. [Home]  make sure Home has TWO ordinary tabs with real pages, e.g.
            https://example.com  and  https://www.wikipedia.org  (open them if not).
 2. [Home]  click WORK in the rail. In the tab that appears go to  https://example.org ,
            then open a second tab and go to  https://www.iana.org
 3. [Work]  right-click WORK in the rail -> "Hibernate other workspaces".
            EXPECT: nothing visible changes here (Home's tabs are the ones that sleep).
 4. [Work]  click HOME in the rail.
            EXPECT: both Home tabs look asleep (greyed / discarded). Click ONE of them:
            it reloads. Leave the other asleep.
 5. [Home]  right-click WORK in the rail -> "Change icon". Press Win+. and pick any emoji
            so it lands in the field (or paste one), then OK.
            EXPECT: the WORK button in the rail now shows that emoji instead of "W".
 6. [Home]  right-click WORK in the rail -> "Close all tabs".
            EXPECT: nothing visible changes here.
 7. [Home]  click WORK in the rail.
            EXPECT: Work is empty except for ONE fresh New Tab that was just spawned.
 8. [Work]  press Ctrl+Shift+T.
            EXPECT: the iana.org tab comes back INTO Work (not into Home).
 9. [Work]  right-click WORK in the rail -> "Hibernate this workspace".
            EXPECT: the tab you are looking at stays awake; the other Work tab sleeps.
10. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
}
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""

$idx = { param($pattern) @(0..([Math]::Max($w.Count - 1, 0)) | Where-Object { $w[$_] -match $pattern }) }
$unloadOthers = & $idx "unload all but '$guid': asking (\d+)"
$closing      = & $idx "closing (\d+) tab\(s\) of workspace '$guid'"
$unloadSelf   = & $idx "unload workspace '$guid': asking (\d+)"

# step 3: the unload line, and the discards that landed between it and the next owner action
# (the closing line), bounded by events, not by a count. The unload line is written BEFORE the
# discards on purpose (LOCAL.md 31): the first run had it after, and the two replacements sat
# above it, which graded a working feature as a FAIL.
$ok3 = $false
if ($unloadOthers.Count -gt 0 -and $closing.Count -gt 0) {
    $a = $unloadOthers[0]; $b = $closing[0]
    $asked = [int]([regex]::Match($w[$a], 'asking (\d+)').Groups[1].Value)
    $between = if ($b - $a -gt 1) { $w[($a + 1)..($b - 1)] } else { @() }
    $replaced = @($between | Where-Object { $_ -match 'tab contents replaced at index' }).Count
    Write-Host "step 3: asking $asked, replaced $replaced between the unload line and the close line"
    $ok3 = ($asked -ge 2) -and ($replaced -ge 2)
}
Verdict "step 3: 'Hibernate other workspaces' asking >= 2 tabs and >= 2 went to sleep (replaced)" $ok3

$after = (Get-Content $prefs -Raw | ConvertFrom-Json).helium.workspaces.list.items | Where-Object { $_.guid -eq $guid }
Write-Host "step 5: stored icon for '$($after.title)' = '$($after.icon)'"
Verdict "step 5: 'Change icon' persisted a non-empty icon on the Work entry" ([bool]$after.icon)

$ok6 = $false; $ok78 = $false
if ($closing.Count -gt 0) {
    $c = $closing[0]
    $closed = [int]([regex]::Match($w[$c], 'closing (\d+)').Groups[1].Value)
    $ok6 = $closed -ge 2
    $end = if ($unloadSelf.Count -gt 0) { $unloadSelf[0] } else { $w.Count }
    $win = if ($end - $c -gt 1) { $w[($c + 1)..($end - 1)] } else { @() }
    $inserted = @($win | Where-Object { $_ -match "tab inserted at index \d+ -> workspace '$guid'" }).Count
    Write-Host "step 6-8: closed $closed; tabs inserted into Work before the final unload: $inserted (1 spawn + 1 restore expected)"
    $ok78 = $inserted -ge 2
}
Verdict "step 6: 'Close all tabs' closed >= 2 tabs of Work" $ok6
Verdict "steps 7+8: a tab was spawned into Work and Ctrl+Shift+T restored one into Work" $ok78

$ok9 = $false
if ($unloadSelf.Count -gt 0) {
    $askedSelf = [int]([regex]::Match($w[$unloadSelf[0]], 'asking (\d+)').Groups[1].Value)
    Write-Host "step 9: asking $askedSelf (the foreground tab is skipped, so 1 of the 2)"
    $ok9 = $askedSelf -eq 1
}
Verdict "step 9: 'Hibernate this workspace' asking exactly 1 tab (skipped the one on screen)" $ok9

$crash = @(Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED').Count
Verdict "no Check failed / FATAL / NOTREACHED in the log ($crash)" ($crash -eq 0)
