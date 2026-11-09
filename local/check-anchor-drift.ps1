param([string]$Log = "<local-path>\Helium-workspace\e10b-run1.log")
# Anchor drift smoke test (written for E10b, LOCAL.md 30). One launch against testprofile with
# logging. Grades the three things E10b adds: the omnibox rule, the pinned fallback, and the
# label on a sleeping anchor. Preconditions are CHECKED, not assumed (LOCAL.md 24, 25, 29).
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")

if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\22-anchor-drift.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no 22-anchor-drift.patch" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than 22-anchor-drift.patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
if (-not (Select-String -Path $live -Pattern 'HasDriftedFrom' -Quiet)) { Write-Host "ABORT: the live patch does not contain this chunk's edit" -ForegroundColor Red; exit 1 }
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout / a non-default workspace / the enabled pref)" -ForegroundColor Red; exit 1 }
Remove-Item $Log -EA SilentlyContinue

Write-Host @"

E10b SMOKE -- every step says which workspace you are IN. Do them in order.

 1. [Home]  click WORK in the rail. A tab appears; you are now in Work.
 2. [Work]  in that tab go to  https://example.com
            Right-click the tab -> Anchor -> "Anchor to this page".
 3. [Work]  THE OMNIBOX RULE. With the anchored tab active, click the address bar,
            type  wikipedia.org  and press Enter.
            EXPECT: a NEW tab opens on Wikipedia, and the anchored tab is untouched,
                    still showing example.com. (Before E10b the anchored tab itself
                    would have gone to Wikipedia.)
 4. [Work]  NEGATIVE CONTROL -- link clicks are NOT diverted. Close the Wikipedia tab (X).
            On the anchored tab, click the "More information..." link inside the page.
            EXPECT: it navigates IN PLACE, no new tab. The tab has now drifted to iana.org.
 5. [Work]  THE LABEL. With the drifted anchored tab active, press Ctrl+W.
            EXPECT: it does not close -- it goes grey (asleep), AND its label now reads
                    example.com, NOT the IANA page title it drifted to.
 6. [Work]  click the greyed tab. EXPECT: it reloads example.com (the anchor).
 7. [Work]  THE PINNED FALLBACK. There should be one other tab in Work (the one Ctrl+W
            spawned in step 5). Right-click it -> Pin. Then click the anchored tab and
            press Ctrl+W.
            EXPECT: you land on the PINNED tab, and NO blank new tab appears.
                    (Before E10b the pinned tab was invisible to the search and a blank
                    tab was spawned beside it.)
 8. [Work]  NEGATIVE CONTROL -- an ordinary tab is unaffected. Click the pinned tab,
            type  example.org  in the address bar, Enter.
            EXPECT: it navigates in place. No new tab.
 9. Close the browser window.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=$Log")) -Wait
Start-Sleep 2
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
$all = $w -join "`n"
$divert = @($w | Where-Object { $_ -match 'typed url diverted' })
$hib    = @($w | Where-Object { $_ -match 'hibernated anchored tab' })

# Step 7 is the only hibernate that must NOT be preceded by a spawn: a fallback that finds
# nothing logs "tab inserted", because HibernateAnchoredTab spawns before it discards.
#
# The window is everything BETWEEN step 5's hibernate and step 7's, not a fixed number of
# lines. A fixed window is the kind of check that passes by luck: at N=3 the step 5 spawn
# landed exactly on the boundary, so one extra log line anywhere on that path would have let
# a regressed fallback through as a PASS.
$hibIdx = @(0..($w.Count - 1) | Where-Object { $w[$_] -match 'hibernated anchored tab' })
$before = if ($hibIdx.Count -ge 2) { $w[($hibIdx[-2] + 1)..($hibIdx[-1] - 1)] -join "`n" } else { "NO SECOND HIBERNATE" }

Write-Host ""
Verdict "step 3: the typed url was diverted to a new tab"        ($all -match "typed url diverted off anchored tab -> new tab: https?://[^ ]*wikipedia")
Verdict "steps 4+8: NOTHING else was diverted (exactly 1 divert)" ($divert.Count -eq 1)
Verdict "step 5: Ctrl+W hibernated at the anchor"                ($all -match "hibernated anchored tab at index \d+ -> 'https://example\.com/'")
Verdict "step 5: the sleeping tab's label is the anchor, not the drifted page" (($all -match "hibernated anchored tab[^`n]*label now '[^']*example\.com") -and ($all -notmatch "label now '[^']*(?i)iana"))
Verdict "step 7: two hibernates happened (5 and 7)"              ($hib.Count -ge 2)
Verdict "step 7: the pinned tab was used, no tab spawned first"  ($before -notmatch 'tab inserted')
Write-Host "`nOwner-observed, and none of it is in the log: step 3 the anchored tab still shows example.com;"
Write-Host "step 4 no new tab; step 5 the greyed tab READS example.com; step 7 no blank tab appeared."
Write-Host "`nCheck-failures in this run:"; (Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED' | Measure-Object).Count
