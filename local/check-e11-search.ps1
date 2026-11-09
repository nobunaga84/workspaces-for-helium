param([string]$Log = "<local-path>\Helium-workspace\e11-search-run.log")
# E11 patch 24 (LOCAL.md 31): tab search lists only the tabs the window is showing. One
# launch. The evidence is the page handler's own "listed X of Y tab(s)" line, one per
# listing, read inside two windows bounded by the toggle's "enabled pref ->" lines: a
# listing that withheld >= 2 while the feature was on, and a listing that withheld NONE
# while it was off. The second half needs a line, not silence: silence is also what "never
# re-listed while off" looks like (LOCAL.md 24, the check that passed over nothing).
# Ctrl+Shift+A is not usable on this machine -- Arc registers it as a global hotkey -- so
# the page route below is the one the steps rely on.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\24-tab-search-scope.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no 24-tab-search-scope.patch" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
foreach ($f in 'tab_search_page_handler\.cc','tab_search/BUILD\.gn') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
Remove-Item $Log -EA SilentlyContinue

Write-Host @"

E11 TAB SEARCH -- every step says which workspace you are IN.

 1. [Home]  make sure Home has at least TWO tabs with real pages (example.com, wikipedia.org).
 2. [Home]  click WORK in the rail; make sure Work has at least ONE real page (example.org).
 3. [Work]  open tab search: Ctrl+Shift+A, or the tab-search button in the toolbar, or --
            the route that always works -- a new tab at  helium://tab-search.top-chrome/
            (the same page the bubble shows, so the same filter runs).
            EXPECT: the "Open tabs" list shows ONLY Work's tab(s) -- no example.com, no
            wikipedia. Leave that tab open.
 4. [Work]  open a new tab, type  helium://settings  and go to Appearance; turn Workspaces
            OFF. The strip now shows every tab.
 5. [off]   open tab search again the same way (reload the tab-search tab if you used it).
            EXPECT: the list shows EVERY tab, including the Home ones.
 6. [off]   go back to the settings tab and turn Workspaces back ON.
 7. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""

$off = @(0..([Math]::Max($w.Count - 1, 0)) | Where-Object { $w[$_] -match 'enabled pref -> false' })
$on  = @(0..([Math]::Max($w.Count - 1, 0)) | Where-Object { $w[$_] -match 'enabled pref -> true' })
if ($off.Count -eq 0 -or $on.Count -eq 0) { Write-Host "FAIL  the toggle never flipped both ways -- steps 4 and 6 did not happen" -ForegroundColor Red; exit 1 }
$offAt = $off[-1]
$onAfter = @($on | Where-Object { $_ -gt $offAt })
if ($onAfter.Count -eq 0) { Write-Host "FAIL  Workspaces was never switched back on (step 6)" -ForegroundColor Red; exit 1 }
$onAt = $onAfter[0]
$before = if ($offAt -gt 0) { $w[0..($offAt - 1)] } else { @() }
$window = if ($onAt - $offAt -gt 1) { $w[($offAt + 1)..($onAt - 1)] } else { @() }
$parse = { param($lines) @($lines | ForEach-Object { $m = [regex]::Match($_, 'listed (\d+) of (\d+)'); if ($m.Success) { [pscustomobject]@{ listed = [int]$m.Groups[1].Value; of = [int]$m.Groups[2].Value } } }) }
$onLists  = & $parse $before
$offLists = & $parse $window
Write-Host "listings while ON: $(($onLists | ForEach-Object { "$($_.listed)/$($_.of)" }) -join ' ')"
Write-Host "listings while OFF: $(($offLists | ForEach-Object { "$($_.listed)/$($_.of)" }) -join ' ')"
Verdict "step 3: with the feature ON, a listing withheld >= 2 tabs" (@($onLists | Where-Object { $_.of - $_.listed -ge 2 }).Count -gt 0)
Verdict "step 5: with the feature OFF, a listing happened and withheld nothing (negative control)" (($offLists.Count -gt 0) -and (@($offLists | Where-Object { $_.listed -ne $_.of }).Count -eq 0))
$crash = @(Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED').Count
Verdict "no Check failed / FATAL / NOTREACHED in the log ($crash)" ($crash -eq 0)
