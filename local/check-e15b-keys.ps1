param([switch]$GradeOnly,
      [string]$OutDir = "Default")
# E15b's review fixes, never yet seen by the owner (LOCAL.md 45 "Still open"): the pinned rows answer the
# keyboard (Up/Down move, Right opens a closed folder, Left closes an open one, Space toggles, the focus
# ring stays on the folder across the redraw), and the rows dim with the tabs in an inactive window.
# Nothing on screen writes a log line for focus or colour, so those are your y/n answers; the log proves
# the folders really toggled and nothing crashed.
#
# Two keyboard routes into the strip, because they behave differently: F6 gives the strip "pane focus",
# and a pane registers the arrow keys as its own shortcuts, which views runs BEFORE the focused row sees
# the key (AccessiblePaneView::SetPaneFocus, FocusManager::OnKeyEvent). Tab from the address bar does not.
#
#   check-e15b-keys.ps1              launch on testprofile, do the steps, answer, grade
#   check-e15b-keys.ps1 -GradeOnly   grade e15b-keys.log again (asks the questions if never answered)
$ws      = "<local-path>\Helium-workspace"
$prof    = "$ws\testprofile"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$section = "$ws\helium-windows\build\src\chrome\browser\ui\views\tabs\vertical\workspace_pinned_section_view.cc"
$log     = "$ws\e15b-keys.log"
$answers = "$ws\e15b-keys.json"

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $section).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.exe is older than the section's source (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'pins: drew ')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 40" -ForegroundColor Red; exit 1 }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    if (-not (Test-Path "$prof\Default\Workspace Pins")) { Write-Host "ABORT: testprofile has no pins file (run check-e15b.ps1 -Reset first)" -ForegroundColor Red; exit 1 }
    Remove-Item $log, $answers -EA SilentlyContinue

    Write-Host @"

E15b KEYBOARD AND COLOUR CHECK -- testprofile, the normal build. Use the LEFT mouse button.
 1. [any workspace]  LEFT-click "Canary" in the rail.
            EXPECT: its pinned section at the top (folder rows, page rows), a thin line, then its tabs.
 2. [Canary]  LEFT-click once inside the web page. Press F6 (again if needed) until a focus
            ring -- a coloured outline -- shows in the tab strip (on a tab, a row or the rail).
            Press Up / Down until the ring is on a pinned ROW.
            EXPECT: Down and Up move the ring one row at a time.
 3. With Up/Down put the ring on a CLOSED folder -- NOT the ~1,159-page one. Press Right.
            EXPECT: the folder OPENS and the ring stays ON THAT FOLDER.
            (Suspected: after F6 the strip takes the arrow keys itself, so Right may just move the ring
            to the next row. If so, answer n: that is what this check is here to find.)
 4. Press Left.   EXPECT: the folder closes; the ring is still on it.
 5. With Up/Down put the ring on a CLOSED folder again, then press Space.
            EXPECT: it opens; Space again closes it; the ring stays on it.
 6. Press Escape. LEFT-click the address bar, then press Tab up to about 20 times.
            Does the ring ever land on a pinned ROW? If it does, try Right / Left / Space there.
 7. Press Windows+Left: the browser takes the LEFT half of the screen. LEFT-click anywhere in the
            RIGHT half (the desktop or another window), so the browser is still visible but not active.
            EXPECT: the rows' text and icons turn greyer, together with the tab titles under the line.
            LEFT-click back on the browser: rows and tabs brighten together.
 8. Close the browser window (its X, top right).
"@ -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run",
        "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"") | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = [ordered]@{
    f6_updown   = "2. after F6: Down/Up moved the ring between pinned rows (y/n)"
    f6_right    = "3. after F6: Right OPENED the closed folder and the ring stayed on it (y/n)"
    f6_left     = "4. after F6: Left CLOSED it and the ring stayed on it (y/n)"
    f6_space    = "5. after F6: Space toggled it and the ring stayed on it (y/n)"
    tab_reaches = "6. Tab from the address bar reached a pinned row (y/n -- either answer is information)"
    tab_keys    = "6. there, Right/Left/Space worked (y/n, or s if Tab never reached a row)"
    dim         = "7. rows dimmed and brightened together with the tabs (y/n)"
}
$a = if (Test-Path $answers) { Get-Content $answers -Raw | ConvertFrom-Json } else { $null }
if (-not $a) {
    Write-Host "`nAnswer each with y, n (or s where offered), then Enter:" -ForegroundColor Cyan
    $h = [ordered]@{}
    foreach ($k in $questions.Keys) {
        if ($k -eq 'tab_keys' -and $h['tab_reaches'] -eq 'n') { $h[$k] = 's'; continue }
        do { $r = (Read-Host $questions[$k]).Trim().ToLower() } while ($r -notin @('y', 'n', 's') -or ($r -eq 's' -and $k -ne 'tab_keys'))
        $h[$k] = $r
    }
    [pscustomobject]$h | ConvertTo-Json | Set-Content $answers -Encoding utf8
    $a = [pscustomobject]$h
}

# ---- grading -----------------------------------------------------------------------------------
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
function Note($text) { Write-Host "      $text" }

if (-not (Test-Path $log) -or (Get-Item $log).Length -eq 0) { Write-Host "FAIL: $log missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
$w = @(Get-Content $log | Where-Object { $_ -match '\[workspaces\]' })
Verdict "the pins file loaded" (@($w | Where-Object { $_ -match 'pins: loaded [1-9]\d* row\(s\)' }).Count -ge 1)
# A folder opened or closed = a draw of the same workspace with a different row count than its last one.
$last = @{}; $toggles = 0; $draws = 0
foreach ($l in $w) {
    if ($l -match "pins: drew (\d+) row\(s\) of '([^']*)' in (\d+) ms") {
        $draws++
        $rows = [int]$Matches[1]; $guid = $Matches[2]
        if ($last.ContainsKey($guid) -and $last[$guid] -ne $rows) { $toggles++ }
        $last[$guid] = $rows
    }
}
Note "$draws draws, $toggles of them a folder opening or closing"
Verdict "folders really toggled (steps 3-5: at least 2 open/close redraws)" ($toggles -ge 2)
$markers = (Get-Content $log | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
Verdict $questions.f6_updown ($a.f6_updown -eq 'y')
Verdict $questions.f6_right  ($a.f6_right -eq 'y')
Verdict $questions.f6_left   ($a.f6_left -eq 'y')
Verdict $questions.f6_space  ($a.f6_space -eq 'y')
Note ("{0} -> {1}" -f $questions.tab_reaches, $a.tab_reaches)
Verdict $questions.tab_keys  ($a.tab_keys -in @('y', 's'))
Verdict $questions.dim       ($a.dim -eq 'y')
Write-Host "`nLog: $log   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
