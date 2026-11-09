param([string]$Log = "<local-path>\Helium-workspace\e13-hard-run.log", [switch]$GradeOnly)
# E13 patch 31 (LOCAL.md 34): three fixes from the review's leftovers.
#   1. The rail buttons' keyboard focus ring is drawn inside the button, so the scroller
#      cannot cut it off. Owner-observed only: a ring is not in any log.
#   2. Clicking "+" while its menu is open closes the menu instead of reopening it. Graded by
#      counting "rail + menu opened" lines: 2 opens for the 3 clicks below, not 3.
#   3. An anchor must be an http(s) page: "Anchor to this page" is greyed on helium://settings,
#      and still works on a web page.
# (Fix 4, the all-or-nothing profile writes in local/*.py, is tested without a browser:
#  python local\profile_write.py.)  -GradeOnly re-grades an existing log.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\31-e13-hardening.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no $live" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
foreach ($f in 'workspace_rail_view\.cc','workspace_rail_view\.h','workspace_tab_data\.cc','workspace_tab_data\.h','workspace_anchor_sub_menu_model\.cc','workspace_service\.cc') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f -- an edit was not quilt-added (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }

if (-not $GradeOnly) {
Remove-Item $Log -EA SilentlyContinue
Write-Host @"

E13 HARDENING -- every step says which workspace you are IN.

 A. THE FOCUS RING
  1. [Home]  click the H (Home) button in the rail, then press Tab a few times.
             (If no rail button lights up, press F6 until the tab strip area is
             highlighted, then Tab.)
             EXPECT: a rail button with keyboard focus shows its ring as a FULL
             rectangle -- top and bottom edges too, not just two side bars.

 B. CLICKING + AGAIN CLOSES ITS MENU  (exactly three clicks on +, nothing else on it)
  2. [Home]  click  +  once.        EXPECT: the menu opens; + looks pressed.
  3. [Home]  click  +  again.       EXPECT: the menu closes and STAYS closed.
  4. [Home]  click  +  once more, then press Esc.   EXPECT: it opened; Esc closed it.

 C. ANCHORS ONLY ON WEB PAGES
  5. [Home]  Ctrl+T, go to  helium://settings . Right-click that tab -> "Anchor".
             EXPECT: "Anchor to this page" is GREYED OUT. Press Esc.
  6. [Home]  Ctrl+T, go to  https://example.com . Right-click that tab -> "Anchor"
             -> "Anchor to this page".   EXPECT: it is allowed.
  7. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
}
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""

# B: every open before the anchor (step 6) belongs to steps 2-4. Before the fix, step 3's click
# reopened the menu: 3 opens. With it: 2.
$anchorAt = @(0..([Math]::Max($w.Count - 1, 0)) | Where-Object { $w[$_] -match "anchor at index \d+ -> 'https?://" } | Select-Object -First 1)
$end = if ($anchorAt.Count) { $anchorAt[0] } else { $w.Count }
$opens = if ($end -gt 0) { @($w[0..($end - 1)] | Where-Object { $_ -match "rail \+ menu opened" }).Count } else { 0 }
Write-Host "B: '+' menu opened $opens time(s) for three clicks"
Verdict "steps 2-4: the click that closed the menu did not reopen it (2 opens, not 3)" ($opens -eq 2)
Verdict "step 6: a web page was anchored" ($anchorAt.Count -gt 0)
# No log verdict for step 5: "no anchor refused" is also true when the step is skipped, and a
# refusal can come from session restore before any step (E13 review). The greyed item is the check.

$crash = @(Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED').Count
Verdict "no Check failed / FATAL / NOTREACHED in the log ($crash)" ($crash -eq 0)
Write-Host "`nSteps 1 (the full ring) and 5 (the greyed item) are yours to grade by eye." -ForegroundColor Yellow
