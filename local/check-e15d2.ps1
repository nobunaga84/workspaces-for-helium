param([switch]$GradeOnly,
      [switch]$Moves,                 # only the two moves the release run's log did not show (steps 2 and 6)
      [switch]$Reuse,                 # keep the copy from the last run instead of copying testprofile again
      [string]$OutDir = "Default",
      [string]$Tag = "e15d2")
# E15d.2: the pinned section's own drag (LOCAL.md 48) -- a pinned page or a folder moves among the rows,
# before a row or into a folder; a pinned page dragged into the tab list becomes a Today tab where it is
# dropped. Runs on a THROWAWAY COPY of testprofile (its Recently Closed emptied first, LOCAL.md 42);
# testprofile is never touched. The log proves each drop ran; the pins file the copy leaves behind proves it
# was SAVED; what you saw is your y/n.
#
#   check-e15d2.ps1              copy testprofile, one run, answer, grade
#   check-e15d2.ps1 -GradeOnly   grade the saved log, answers and pins file again
$ws      = "<local-path>\Helium-workspace"
$src     = "$ws\testprofile"
$prof    = "$ws\testprofile-$Tag"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\44-pinned-drag.patch"
$pins    = "$prof\Default\Workspace Pins"
$run     = if ($Moves) { "moves" } else { "run" }
$log     = "$ws\$Tag-$run.log"
$answers = "$ws\$Tag-$run-answers.json"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt (Get-Item $patch).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.dll is older than patch 44 (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'dropped in the list')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 44" -ForegroundColor Red; exit 1 }
    if (-not $Reuse -or -not (Test-Path $prof)) {
        if ((Test-Path $prof) -and $prof.EndsWith("-$Tag")) { Remove-Item -Recurse -Force $prof }
        Write-Host "copying $src -> $prof (a throwaway copy; testprofile is not touched) ..." -ForegroundColor Green
        robocopy $src $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 /XD "Cache" "Code Cache" "GPUCache" "GrShaderCache" "ShaderCache" | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
        Get-ChildItem "$prof\Default\Sessions" -Filter "Tabs_*" -EA SilentlyContinue | Remove-Item -Force
    }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    # Kept as .prev, not deleted: a re-run of a few steps must not erase the evidence of the rest.
    foreach ($f in $log, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window:
  PINNED PAGE  an entry ABOVE the thin line: a page name with a small icon. It is not a tab.
  FOLDER       an entry above the thin line with a folder icon.
  + NEW TAB    the entry with a "+" and the words "New Tab", right UNDER the thin line.
  TODAY TAB    an ordinary tab below "+ New Tab".
  DRAG         press the LEFT mouse button on it, keep it held down, move the mouse, let go to DROP.
               While you drag, a coloured LINE shows where it would go -- or a coloured FRAME round a
               folder it would go into. No line and no frame: dropping there does nothing.
Every step is done in "Work".
"@ -ForegroundColor Magenta
    if ($Moves) { Write-Host @"
 1. LEFT-click "Work" in the rail at the bottom. RIGHT-click the THIRD PINNED PAGE -> "New folder".
            Press Ctrl+A, type  Box  and press Enter.   EXPECT: a FOLDER "Box" below the third pinned page.
 2. Note the name of the FIRST PINNED PAGE. DRAG it down; a LINE follows the mouse. DROP it when the line is
            between the 6th and 7th rows.   EXPECT: the page you noted is now the 6th row.
 3. DRAG the FOLDER "Box" up; DROP it when the line is between the 1st and 2nd rows.
            EXPECT: "Box" is now the 2nd row.
 4. Close the browser window (its X, top right).
"@ -ForegroundColor Yellow } else {
    Write-Host @"
 1. LEFT-click "Work" in the rail at the bottom. RIGHT-click the THIRD PINNED PAGE -> "New folder".
            Press Ctrl+A, type  Box  and press Enter.   EXPECT: a FOLDER "Box" below the third pinned page.
 2. DRAG the FIRST PINNED PAGE down and DROP it on the line between the 6th and 7th rows.
            EXPECT: while dragging, a line between rows follows the mouse; after the drop the page sits there.
 3. DRAG the LAST PINNED PAGE (just above the thin line) up and DROP it on the TOP edge of the first row.
            EXPECT: it is now the first row. (Hold it near the top edge of the list if it needs to scroll.)
 4. DRAG the SECOND PINNED PAGE onto the MIDDLE of the FOLDER "Box" (a FRAME appears round "Box") and DROP.
            EXPECT: the page leaves the list (it is inside the closed folder). LEFT-click "Box": it opens and
            the page is inside, indented.
 5. With "Box" open, DRAG that indented page up and DROP it on the line just ABOVE "Box".
            EXPECT: it is out of the folder, above "Box", not indented; "Box" is empty.
 6. DRAG the FOLDER "Box" up and DROP it on the line just below the FIRST row.   EXPECT: "Box" moves there.
 7. Find a PINNED PAGE with NO X (its page is not open). DRAG it down into the TODAY TABS and DROP it on the
            line between two Today tabs.
            EXPECT: it leaves the pinned pages and opens as a TODAY TAB exactly where the line was, showing
            its page.
 8. LEFT-click another PINNED PAGE (its page opens; it gets an X). DRAG it into the TODAY TABS and DROP it on
            the line between two Today tabs.
            EXPECT: it becomes a TODAY TAB at that place, its page still showing (not reloaded).
 9. DRAG any PINNED PAGE over to the web page on the right and DROP it there.   EXPECT: nothing changes.
10. DRAG the FOLDER "Box" down over the TODAY TABS.   EXPECT: no line shows there; DROP: nothing changes.
11. Close the browser window (its X, top right).
"@ -ForegroundColor Yellow }
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = if ($Moves) { [ordered]@{
    down    = "2. the first pinned page is now the 6th row (y/n)"
    folder  = "3. the folder Box is now the 2nd row (y/n)"
} } else { [ordered]@{
    line    = "2. while dragging, a line showed where the page would go (y/n)"
    down    = "2. the first pinned page moved down to where you dropped it (y/n)"
    up      = "3. the last pinned page moved up to the top (y/n)"
    into    = "4. a frame showed round Box, and the page ended up inside Box (y/n)"
    outof   = "5. the page came out of Box, above it, not indented (y/n)"
    folder  = "6. the folder Box moved up (y/n)"
    sleep   = "7. the pinned page with no X opened as a Today tab where you dropped it (y/n)"
    open    = "8. the open pinned page became a Today tab where you dropped it, not reloaded (y/n)"
    cancel  = "9. dropping on the web page changed nothing (y/n)"
    nofold  = "10. the folder showed no line over the Today tabs, and dropping there changed nothing (y/n)"
} }
$a = if (Test-Path $answers) { Get-Content $answers -Raw | ConvertFrom-Json } else { $null }
if (-not $a) {
    Write-Host "`nAnswer each with y or n, then Enter:" -ForegroundColor Cyan
    $h = [ordered]@{}
    foreach ($k in $questions.Keys) {
        do { $r = (Read-Host $questions[$k]).Trim().ToLower() } while ($r -notin @('y', 'n'))
        $h[$k] = $r
    }
    [pscustomobject]$h | ConvertTo-Json | Set-Content $answers -Encoding utf8
    $a = [pscustomobject]$h
}

# ---- grading -----------------------------------------------------------------------------------
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
if (-not (Test-Path $log) -or (Get-Item $log).Length -eq 0) { Write-Host "FAIL: $log missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $pins)) { Write-Host "FAIL: $pins missing -- nothing to grade" -ForegroundColor Red; exit 1 }
$lines   = @(Get-Content $log)
$file    = Get-Content $pins -Raw
$rowMoves   = @($lines | Where-Object { $_ -match "pins: moved '" })
$dropped = @($lines | ForEach-Object { if ($_ -match "pins: unpinned item '([^']+)' \(dropped in the list\)") { $Matches[1] } })
foreach ($l in $rowMoves) { Write-Host ("      " + ($l -replace '^.*\] pins: ', '')) }
if ($Moves) {
$box = @($lines | ForEach-Object { if ($_ -match "pins: new folder '([^']+)'") { $Matches[1] } }) | Select-Object -Last 1
Verdict "a page moved (step 2)"                                            (@($rowMoves | Where-Object { $box -and $_ -notmatch "moved '$box'" }).Count -ge 1)
Verdict "the folder Box moved (step 3)"                                    ($box -and @($rowMoves | Where-Object { $_ -match "moved '$box'" }).Count -ge 1)
} else {
Verdict "5 or more moves among the rows (steps 2-6)"                      ($rowMoves.Count -ge 5)
Verdict "a move INTO a folder (step 4)"                                    (@($rowMoves | Where-Object { $_ -match "' into '" }).Count -ge 1)
Verdict "2 pinned pages dropped in the list (steps 7, 8)"                  ($dropped.Count -ge 2)
Verdict "saved: the folder 'Box'"                                          ($file -match '"title": "Box"')
Verdict "saved: the pages dropped in the list are no longer pinned"        ($dropped.Count -ge 2 -and @($dropped | Where-Object { $file.Contains("`"$_`"") }).Count -eq 0)
}
$markers = ($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLog: $log   Answers: $answers   Pins: $pins. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
