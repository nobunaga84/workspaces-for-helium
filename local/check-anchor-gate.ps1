param([string]$Log = "<local-path>\Helium-workspace\e10b-gate-run.log")
# Anchor pref gate (E10b follow-up, LOCAL.md 30). One launch. Proves that every anchor
# behaviour goes quiet while Workspaces is switched OFF and comes back when it is switched on
# -- the finding that an anchored tab used to keep refusing Ctrl+W and diverting typed
# addresses after its own menu had disappeared with the pref.
#
# The whole verdict rests on ONE ordering marker: "[workspaces] enabled pref -> true|false" is
# logged on every flip, so the disabled stretch of the run is a window in the log, and the
# assertion is that NOTHING anchor-shaped happens inside it. That is a window bounded by the
# events that define it, not by a line count (LOCAL.md 30).
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\22-anchor-drift.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no 22-anchor-drift.patch" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
if (-not (Select-String -Path $live -Pattern 'ShouldDivertTypedNavigation' -Quiet)) { Write-Host "ABORT: the live patch does not contain the gate" -ForegroundColor Red; exit 1 }
# A symbol count proves the symbol is in the patch, not which files it came from. The gate's
# header was once edited without `quilt add`: it compiled from the tree and vanished from the
# patch, and the symbol grep above still passed on the call + the definition (LOCAL.md 30).
if (-not (Select-String -Path $live -Pattern '^\+\+\+ b/chrome/browser/ui/tabs/workspaces/workspace_service\.h' -Quiet)) { Write-Host "ABORT: the live patch does not touch workspace_service.h -- the header edit was not quilt-added" -ForegroundColor Red; exit 1 }
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
Remove-Item $Log -EA SilentlyContinue

Write-Host @"

ANCHOR PREF GATE -- every step says which workspace you are IN.

 1. [Home]  click WORK in the rail. In the tab that appears, go to  https://example.com
            Right-click the tab -> Anchor -> "Anchor to this page".   << call this tab A
 2. [Work]  with A active, type  wikipedia.org  in the address bar, Enter.
            EXPECT: a new tab opens (the rule working while the feature is ON).
            Close that new tab with its X.
 3. [Work]  open a SECOND tab, go to  https://example.com , and anchor it the same way.
            << call this tab B. It has to be anchored NOW, because the Anchor menu
            disappears once the feature is off.
 4. [Work]  open a new tab and go to  helium://settings  (type it -- a helium:// URL passed
            on the command line is silently dropped). Appearance -> turn Workspaces OFF.
            The strip now shows every tab; nothing is hidden.
 5. [off]   click tab A (example.com). Type  wikipedia.org  in the address bar, Enter.
            EXPECT: it navigates IN PLACE. No new tab. The anchor is dormant.
 6. [off]   with tab A still active, press Ctrl+W.
            EXPECT: it CLOSES for real -- it does not grey out and stay.
 7. [off]   go back to the settings tab and turn Workspaces back ON.
            NOTE: the settings tab lives in a workspace, so switching back on can hide the
            page you just clicked. That is the feature working, not a fault.
 8. [Work]  find tab B (example.com, anchored in step 3). Press Ctrl+W.
            EXPECT: it does NOT close -- it greys out (asleep). The anchor survived being
            dormant, which is why the tag is kept rather than cleared.
 9. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }

$off = @(0..([Math]::Max($w.Count - 1, 0)) | Where-Object { $w[$_] -match 'enabled pref -> false' })
$on  = @(0..([Math]::Max($w.Count - 1, 0)) | Where-Object { $w[$_] -match 'enabled pref -> true' })
Write-Host ""
if ($off.Count -eq 0 -or $on.Count -eq 0) {
    Write-Host "FAIL  the toggle never flipped both ways -- steps 4 and 7 did not happen, so this run proves nothing" -ForegroundColor Red
    exit 1
}
$offAt   = $off[-1]
$onAfter = @($on | Where-Object { $_ -gt $offAt })
if ($onAfter.Count -eq 0) { Write-Host "FAIL  Workspaces was never switched back on (step 7)" -ForegroundColor Red; exit 1 }
$onAt   = $onAfter[0]
$window = if ($onAt - $offAt -gt 1) { $w[($offAt + 1)..($onAt - 1)] } else { @() }

Write-Host "--- the disabled window: lines $($offAt + 1)..$($onAt - 1) ($($window.Count) lines) ---"
$window | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""
Verdict "steps 5+6: NO anchor behaviour at all while Workspaces was off" (-not (($window -join "`n") -match 'typed url diverted|hibernated anchored tab'))
Verdict "step 2: the rule DID fire before the toggle (the run tested something)" (@($w[0..$offAt] | Where-Object { $_ -match 'typed url diverted' }).Count -ge 1)
Verdict "step 8: Ctrl+W hibernates again after switching back on" (@($w[$onAt..($w.Count - 1)] | Where-Object { $_ -match 'hibernated anchored tab' }).Count -ge 1)
Write-Host "`nOwner-observed, and none of it is in the log: step 5 no new tab appeared; step 6 tab A really closed."
Write-Host "`nCheck-failures in this run:"; (Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED' | Measure-Object).Count
