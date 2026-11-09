param([string]$Log1 = "<local-path>\Helium-workspace\anchors-run1.log", [string]$Log2 = "<local-path>\Helium-workspace\anchors-run2.log")
# Anchors smoke test (written for E10a, LOCAL.md 29). Two launches against testprofile with logging: the
# exercise, then a restart with --restore-last-session to prove the anchor
# persists. Grades e10a-run1.log and e10a-run2.log itself.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$pdir = "<local-path>\Helium-workspace\helium\patches\local\workspaces"
$log1 = $Log1; $log2 = $Log2
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\21-anchors.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no 21-anchors.patch" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than 21-anchors.patch" -ForegroundColor Red; exit 1 }
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
Remove-Item $log1,$log2 -EA SilentlyContinue

Write-Host @"

RUN 1 -- steps (each says which workspace you are IN):
 1. [Home]  click WORK in the rail (a tab appears). [Work] open ONE more tab, any page.
 2. [Work]  on that second tab go to https://example.com. Right-click it -> Anchor -> "Anchor to this page".
            Then navigate the same tab to https://example.org (it has drifted).
 3. [Work]  with the drifted tab ACTIVE, press Ctrl+W. Expected: it is NOT closed; the other Work
            tab becomes active; the anchored tab stays in the strip, greyed (asleep).
 4. [Work]  click the greyed tab. Expected: it reloads example.COM (the anchor), not example.org.
 5. [Work]  close the OTHER Work tab (X button) so the anchored tab is the only tab in Work.
            Press Ctrl+W on the anchored tab. Expected: a NEW tab appears in Work, anchored tab sleeps.
 6. [Work]  right-click the anchored tab -> Anchor -> "Remove anchor". Press Ctrl+W: it closes for real.
 7. [Work]  open a tab, go to https://example.com, Anchor it (this one stays for the restart test).
 8. Close the browser window (File > Exit or close the window). Do not close tabs first.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$log1")) -Wait
Start-Sleep 2
if (-not (Test-Path $log1) -or (Get-Item $log1).Length -eq 0) { Write-Host "FAIL: run-1 log missing or EMPTY" -ForegroundColor Red; exit 1 }

Write-Host @"

RUN 2 -- restart with session restore:
 9. The window restores. [Work] find the anchored tab from step 7 (it may be asleep), click it so it
    loads, then press Ctrl+W on it. Expected: it hibernates again (not closed) -> proves the anchor
    survived the restart. Then close the browser.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$log2","--restore-last-session")) -Wait
Start-Sleep 2

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w1 = Get-Content $log1 | Where-Object { $_ -match '\[workspaces\]' }
$w2 = if (Test-Path $log2) { Get-Content $log2 | Where-Object { $_ -match '\[workspaces\]' } } else { @() }
Write-Host "`n--- run 1 [workspaces] lines: $($w1.Count) ---"; $w1 | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host "--- run 2 [workspaces] lines: $($w2.Count) ---"; $w2 | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""
Verdict "step 2: anchor set at example.com"            (($w1 -join "`n") -match "anchor at index \d+ -> 'https://example\.com/'")
Verdict "step 3: Ctrl+W hibernated the anchored tab"  (($w1 -join "`n") -match "hibernated anchored tab at index \d+ -> 'https://example\.com/'")
Verdict "step 3: replacement carried the anchor"       (($w1 -join "`n") -match "tab contents replaced at index \d+ -> carried workspace '[^']*', anchor 'https://example\.com/'")
Verdict "step 5: no fallback -> spawned a tab then hibernated" ((($w1 -join "`n") -match "tab inserted at index \d+[\s\S]*hibernated anchored tab") -and (@($w1 | Where-Object { $_ -match 'hibernated anchored tab' }).Count -ge 2))
Verdict "step 6: unanchored (empty anchor written)"    (($w1 -join "`n") -match "anchor at index \d+ -> ''")
Verdict "step 9: anchor survived restart (hibernated again)" (($w2 -join "`n") -match "hibernated anchored tab")
Write-Host "`nOwner-observed: step 4 reloads example.COM; step 3/5 the tab stays in the strip greyed; step 6 Ctrl+W closes for real."
Write-Host "Errors worth a look:"; (Get-Content $log1,$log2 | Select-String -Pattern 'Check failed|FATAL|NOTREACHED' | Measure-Object).Count
