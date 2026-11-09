param([switch]$GradeOnly,
      [switch]$Folder,                # only step 3 (a drop INTO a closed folder), on the same copy
      [switch]$Reuse,                 # keep the copy from the last run instead of copying testprofile again
      [string]$OutDir = "Default",
      [string]$Tag = "e15d3")
# E15d.3: a Today tab dragged INTO the pinned section becomes a pinned page where it is dropped (LOCAL.md 49)
# -- between two pinned pages, or first inside a folder; several selected tabs in their order; "+ New Tab"
# and Esc pin nothing. Runs on a THROWAWAY COPY of testprofile (its Recently Closed emptied first, LOCAL.md
# 42); testprofile is never touched. The log proves each pin ran and where it went; the pins file the copy
# leaves behind proves it was SAVED; what you saw is your y/n.
#
#   check-e15d3.ps1              copy testprofile, one run, answer, grade
#   check-e15d3.ps1 -GradeOnly   grade the saved log, answers and pins file again
#   check-e15d3.ps1 -Folder      redo only step 3 on the same copy; its own log and answers (the run's are kept)
$ws      = "<local-path>\Helium-workspace"
$src     = "$ws\testprofile"
$prof    = "$ws\testprofile-$Tag"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\45-pin-by-drag.patch"
$pins    = "$prof\Default\Workspace Pins"
$run     = if ($Folder) { "folder" } else { "run" }
$log     = "$ws\$Tag-$run.log"
$answers = "$ws\$Tag-$run-answers.json"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt (Get-Item $patch).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.dll is older than patch 45 (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'dropped on the rows')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 45" -ForegroundColor Red; exit 1 }
    if (-not ($Reuse -or $Folder) -or -not (Test-Path $prof)) {
        if ((Test-Path $prof) -and $prof.EndsWith("-$Tag")) { Remove-Item -Recurse -Force $prof }
        Write-Host "copying $src -> $prof (a throwaway copy; testprofile is not touched) ..." -ForegroundColor Green
        robocopy $src $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 /XD "Cache" "Code Cache" "GPUCache" "GrShaderCache" "ShaderCache" | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
        Get-ChildItem "$prof\Default\Sessions" -Filter "Tabs_*" -EA SilentlyContinue | Remove-Item -Force
    }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    # Kept as .prev, not deleted: a re-run must not erase the evidence of the last one.
    foreach ($f in $log, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window:
  PINNED PAGE  an entry ABOVE the thin line: a page name with a small icon. It is not a tab.
  FOLDER       an entry above the thin line with a folder icon.
  + NEW TAB    the entry with a "+" and the words "New Tab", right UNDER the thin line.
  TODAY TAB    an ordinary tab below "+ New Tab".
  DRAG         press the LEFT mouse button on it, keep it held down, move the mouse, let go to DROP.
               While you drag a TODAY TAB over the PINNED PAGES, a coloured LINE shows where it would go --
               or a coloured FRAME round a folder it would go into. No line and no frame: it is not pinned.
Every step is done in "Work".
"@ -ForegroundColor Magenta
    if ($Folder) { Write-Host @"
 1. LEFT-click "Work" in the rail at the bottom.
 2. Find a CLOSED FOLDER among the PINNED PAGES (its contents not shown under it). DRAG a TODAY TAB onto the
            MIDDLE of that folder -- a FRAME appears round the folder -- and DROP.
            EXPECT: it leaves the Today tabs; the folder OPENS and the page is the FIRST one inside,
            highlighted (it is the page showing).
 3. Close the browser window (its X, top right).
"@ -ForegroundColor Yellow } else {
    Write-Host @"
 1. LEFT-click "Work" in the rail at the bottom.
 2. Note the name of the FIRST TODAY TAB. DRAG it up over the PINNED PAGES and DROP it on the line between
            the 1st and 2nd PINNED PAGES.
            EXPECT: while dragging, a line between the pinned pages follows the mouse; after the drop the tab
            is gone from the Today tabs and is the 2nd PINNED PAGE, with an X (its page is open).
 3. DRAG another TODAY TAB onto the MIDDLE of a CLOSED FOLDER (a FRAME appears round it) and DROP.
            EXPECT: it leaves the Today tabs; the folder OPENS and the page is the FIRST one inside,
            highlighted (it is the page showing).
 4. DRAG a TODAY TAB up only as far as "+ NEW TAB" and DROP it there.
            EXPECT: no line among the pinned pages; it stays a TODAY TAB (at the top of the Today tabs).
            Then do the same with a tab named "New Tab", but drag it higher, over the PINNED PAGES.
            EXPECT: no line; the tab keeps following the mouse at the top of the Today tabs, and stays a
            TODAY TAB when dropped.
 5. LEFT-click one TODAY TAB, then hold Ctrl and LEFT-click another TODAY TAB (both look selected). DRAG one
            of the two up and DROP it on the line between two PINNED PAGES.
            EXPECT: BOTH leave the Today tabs and are pinned pages there, next to each other.
 6. DRAG a TODAY TAB over the PINNED PAGES until the line shows, press Esc while still holding the mouse
            button, then let go.   EXPECT: nothing is pinned; it stays a TODAY TAB.
 7. Close the browser window (its X, top right).
"@ -ForegroundColor Yellow }
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = if ($Folder) { [ordered]@{
    into    = "2. a frame showed round the folder; it opened, the page FIRST inside and highlighted (y/n)"
} } else { [ordered]@{
    line    ="2. while dragging over the pinned pages, a line showed where the tab would go (y/n)"
    first   = "2. the tab became the 2nd pinned page, with an X (y/n)"
    still   = "2-5. the Today tabs stayed still after each drop -- no jump, no scroll (y/n)"
    into    = "3. a frame showed round the folder; it opened, the page FIRST inside and highlighted (y/n)"
    newtab  = "4. both stayed Today tabs; the New Tab page did not jump back while over the pinned pages (y/n)"
    two     = "5. both selected tabs became pinned pages, next to each other (y/n)"
    escape  = "6. after Esc, nothing was pinned (y/n)"
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
$lines = @(Get-Content $log)
$file  = Get-Content $pins -Raw
# "pins: <n> tab(s) dropped on the rows", then per tab "pins: pinned a tab as item '<id>' before|after|into '<row>'"
$drops = @($lines | Where-Object { $_ -match "pins: \d+ tab\(s\) dropped on the rows" })
$pinned = @($lines | Where-Object { $_ -match "pins: pinned a tab as item '[^']+' \w+ '[^']*'" })
foreach ($l in @($drops) + @($pinned)) { Write-Host ("      " + ($l -replace '^.*\] pins: ', '')) }
$ids = @($pinned | ForEach-Object { if ($_ -match "as item '([^']+)'") { $Matches[1] } })
if ($Folder) {
Verdict "1 drop on the rows ($($drops.Count) seen)"                           ($drops.Count -eq 1)
Verdict "1 tab pinned, INTO a folder ($($pinned.Count) seen)"                 ($pinned.Count -eq 1 -and $pinned[0] -match "' into '")
} else {
Verdict "3 drops on the rows (steps 2, 3, 5); none by steps 4 and 6 ($($drops.Count) seen)" ($drops.Count -eq 3)
Verdict "4 tabs pinned: 1 + 1 + the 2 selected ($($pinned.Count) seen)"      ($pinned.Count -eq 4)
Verdict "one of them INTO a folder (step 3)"                                 (@($pinned | Where-Object { $_ -match "' into '" }).Count -ge 1)
}
Verdict "saved: every pinned tab is in the pins file"                         ($ids.Count -ge 1 -and @($ids | Where-Object { -not $file.Contains("`"$_`"") }).Count -eq 0)
$markers = ($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLog: $log   Answers: $answers   Pins: $pins. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
