# historical (pre-E17): E17a replaced the "Change icon" presets submenu with "Edit workspace..." (its Icon grid).
param([string]$Log = "<local-path>\Helium-workspace\e11-rename-run.log")
# E11 patches 25 + 26 (LOCAL.md 31): "Rename tab..." on the tab menu's Workspace submenu, and the
# icon presets submenu on the rail (graded from the icon written to Preferences). Two launches:
# the rename itself (plus a Ctrl+Shift+T leg and a clear-to-empty leg), then a restart with
# --restore-last-session (testprofile has no restore_on_startup, LOCAL.md 16). Evidence is the
# service's "custom title at index" line on set, and "restored custom title" for each of the
# two ways a tab comes back.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")
$Log2 = $Log -replace '\.log$','-restart.log'

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\25-rename-tab.patch"
$live26 = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\26-icon-presets.patch"
foreach ($p in $live, $live26) {
    if (-not (Test-Path $p)) { Write-Host "ABORT: no $p" -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $p).LastWriteTime) { Write-Host "ABORT: chrome.exe older than $p (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
}
if (-not (Select-String -Path $live26 -Pattern 'kIconPresets' -Quiet)) { Write-Host "ABORT: 26 does not contain the presets" -ForegroundColor Red; exit 1 }
foreach ($f in 'workspace_tab_data\.h','workspace_session_data\.h','workspace_session_data\.cc','workspace_service\.h','workspace_service\.cc','tab_ui_helper\.cc','workspace_anchor_sub_menu_model\.h','workspace_anchor_sub_menu_model\.cc','ui/tabs/BUILD\.gn','generated_resources\.grd') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f -- an edit was not quilt-added (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
Remove-Item $Log, $Log2 -EA SilentlyContinue

Write-Host @"

E11 RENAME TAB, launch 1 of 2 -- every step says which workspace you are IN.

 0. [any]   LOOK at the toolbar (top right, near the address bar): a TAB SEARCH button (a
            magnifier) should be there -- Chromium's own, pinned through the
            toolbar.pinned_actions pref because Arc eats Ctrl+Shift+A on this PC (LOCAL.md 31).
            Click it: the tab search panel opens. Press Esc.
 1. [Home]  click WORK in the rail. In a Work tab go to  https://example.com
 2. [Work]  right-click that tab -> "Rename tab..." (a plain item, under "Move tab to
            workspace"). Type  ALPHA  and OK.
            EXPECT: the tab in the strip now reads ALPHA, not "Example Domain".
 3. [Work]  hover the tab: the hover card also says ALPHA. Press Ctrl+Shift+A: the tab
            search list says ALPHA too. Esc.
 4. [Work]  press Ctrl+W on ALPHA, then Ctrl+Shift+T.
            EXPECT: it comes back still named ALPHA, and in Work.
 5. [Work]  open a second tab, go to  https://www.wikipedia.org , rename it  BETA  the
            same way. Then rename BETA again with an EMPTY field and OK.
            EXPECT: the tab goes back to reading "Wikipedia".
 6. [Work]  right-click WORK in the rail -> Change icon -> pick ANY of the six rows (each is
            an emoji plus a word; the last row, "Custom$([char]0x2026)", opens the text field instead).
            EXPECT: the WORK button in the rail now shows that emoji.
 7. Close the browser window (leave ALPHA open -- launch 2 checks it survives a restart).

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

Write-Host @"

E11 RENAME TAB, launch 2 of 2 -- the browser restarts with the last session restored.

 8. [any]   find the restored example.com tab (click WORK in the rail if needed).
            EXPECT: it still reads ALPHA.
 9. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--restore-last-session","--log-file=$Log2")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log2) -or (Get-Item $Log2).Length -eq 0) { Write-Host "FAIL: restart log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w  = @(Get-Content $Log  | Where-Object { $_ -match '\[workspaces\]' })
$w2 = @(Get-Content $Log2 | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- launch 1 [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host "`n--- launch 2 [workspaces] lines: $($w2.Count) ---"; $w2 | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""

$set = @($w | Where-Object { $_ -match "custom title at index \d+ -> '" })
Verdict "step 2: ALPHA was set"                      (($w -join "`n") -match "custom title at index \d+ -> 'ALPHA'")
Verdict "step 4: Ctrl+Shift+T restored the title"    (($w -join "`n") -match "restored custom title 'ALPHA'")
Verdict "step 5: BETA was set, then cleared to empty" ((($w -join "`n") -match "-> 'BETA'") -and (($w -join "`n") -match "custom title at index \d+ -> ''"))
Verdict "step 8: the restart restored ALPHA"         (($w2 -join "`n") -match "restored custom title 'ALPHA'")
$items = (Get-Content "$prof\Default\Preferences" -Raw | ConvertFrom-Json).helium.workspaces.list.items
$work = @($items | Where-Object { $_.guid -ne 'default' })[0]
Write-Host "step 6: stored icon for '$($work.title)' = '$($work.icon)'"
$presets = @(0x1F3E0, 0x1F4BC, 0x1F4DA, 0x1F3AE, 0x1F6D2, 0x1F3B5 | ForEach-Object { [char]::ConvertFromUtf32($_) })
Verdict "step 6: the presets submenu wrote one of the six preset emoji to the Work entry" ($presets -contains $work.icon)
$crash = @(Select-String -Path $Log, $Log2 -Pattern 'Check failed|FATAL|NOTREACHED').Count
Verdict "no Check failed / FATAL / NOTREACHED in either log ($crash)" ($crash -eq 0)
