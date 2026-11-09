param([switch]$GradeOnly,
      [switch]$Recheck,               # only the steps a first run left unproven: back arrow, Ctrl+W, the X, Cancel
      [switch]$Arrow,                 # only the back arrow (after the redirect fix)
      [switch]$Reuse,                 # keep the copy from the last run instead of copying testprofile again
      [string]$OutDir = "Default",
      [string]$Tag = "e15c")
# E15c: a pinned page opens as ONE real tab, hidden from the Today list and shown by its entry in the pinned
# section (LOCAL.md 46, design 5 "E15 spec", Open and close). Runs on a THROWAWAY COPY of testprofile --
# Unpin and Delete change the pins file, and the copy's Recently Closed is emptied first (testprofile's
# holds a 3,864-tab window a stray Ctrl+Shift+T would reopen, LOCAL.md 42). testprofile is never touched.
#   full:     run 1 = open, back arrow, Ctrl+W, the X, Ctrl+Tab, a shift-click close, the menus;
#             run 2 = a restart brings the open page back hidden
#   -Recheck: one run, only the back arrow, Ctrl+W, the X, and Cancel on "Delete folder"
# Nothing on screen logs "highlighted" or "not in the list", so those are your y/n answers; the log proves
# what opened, what closed and by which door, and that nothing crashed.
#
#   check-e15c.ps1              copy testprofile, two runs, answer, grade
#   check-e15c.ps1 -Recheck     copy testprofile, one short run, answer, grade
#   check-e15c.ps1 -GradeOnly   grade the saved logs again (add -Recheck for the short run's)
$ws      = "<local-path>\Helium-workspace"
$src     = "$ws\testprofile"
$prof    = "$ws\testprofile-$Tag"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$section = "$ws\helium-windows\build\src\chrome\browser\ui\views\tabs\vertical\workspace_pinned_section_view.cc"
if ($Arrow) { $Recheck = $true }
$run     = if ($Arrow) { "arrow" } elseif ($Recheck) { "recheck" } else { "run" }
$log1    = "$ws\$Tag-${run}1.log"; $log2 = "$ws\$Tag-run2.log"
$answers = "$ws\$Tag-$run-answers.json"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--restore-last-session")

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function RunLeg([string]$title, [string]$log, [string]$steps) {
    Write-Host "`n==================== $title ====================" -ForegroundColor Cyan
    Write-Host $steps -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList @($flags; "--log-file=`"$log`"") | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

$words = @"

WORDS USED BELOW -- look at the left side of the window:
  PINNED PAGE  an entry ABOVE the thin line: a page name with a small icon. It is not a tab.
  FOLDER       an entry above the thin line with a folder icon; clicking it opens or closes it.
  TODAY TAB    an ordinary tab BELOW the thin line.
  When a pinned page is OPEN it gets a small X at its right end; when its page is the one showing,
  the pinned page is also highlighted, like the active tab.
Use the LEFT mouse button unless a step says RIGHT.
"@

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $section).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.exe is older than the section's source (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'pins: opened item')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 41" -ForegroundColor Red; exit 1 }
    if (-not $Reuse -or -not (Test-Path $prof)) {
        if ((Test-Path $prof) -and $prof.EndsWith("-$Tag")) { Remove-Item -Recurse -Force $prof }
        Write-Host "copying $src -> $prof (a throwaway copy; testprofile is not touched) ..." -ForegroundColor Green
        robocopy $src $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
        # The Recently Closed file (Tabs_*): testprofile's holds a 3,864-tab window (LOCAL.md 42).
        Get-ChildItem "$prof\Default\Sessions" -Filter "Tabs_*" -EA SilentlyContinue | Remove-Item -Force
    }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    if (-not (Test-Path "$prof\Default\Workspace Pins")) { Write-Host "ABORT: the copy has no pins file" -ForegroundColor Red; exit 1 }
    Remove-Item $log1, $answers -EA SilentlyContinue
    if (-not $Recheck) { Remove-Item $log2 -EA SilentlyContinue }

    Write-Host $words -ForegroundColor Magenta
    if ($Arrow) {
        $steps1 = @"
 1. [any workspace]  LEFT-click "Canary" in the rail at the bottom.
 2. LEFT-click the PINNED PAGE you used for the back arrow last time (the Amazon one), or any pinned
            page. EXPECT: its page shows; the pinned page is highlighted with an X -- and NO back arrow
            yet, even though that address sends you on to another one.
 3. In that page, LEFT-click a link that opens in the SAME tab.
            EXPECT: a small back arrow appears on the pinned page, just left of its X.
            LEFT-click that arrow. EXPECT: the page goes back to where it started, and the arrow
            DISAPPEARS.
 4. Close the browser window (its X, top right).
"@
        RunLeg "THE BACK ARROW (one run)" $log1 $steps1
    } elseif ($Recheck) {
        $steps1 = @"
 1. [any workspace]  LEFT-click "Canary" in the rail at the bottom.
 2. LEFT-click a PINNED PAGE near the top (not a folder).
            EXPECT: its page shows on the right; that pinned page is highlighted and has a small X.
 3. THE BACK ARROW. In that page, LEFT-click a link that opens in the SAME tab.
            EXPECT: a small back arrow appears on the pinned page, just left of its X.
            LEFT-click that arrow. EXPECT: the page goes back to where it started; the arrow disappears.
 4. CTRL+W. With that page still showing (its pinned page highlighted), press Ctrl+W.
            EXPECT: the page closes. The pinned page is STILL ABOVE the line, now without highlight or X.
 5. THE X. LEFT-click one pinned page, then a second one (both now have an X). Put the mouse on the
            small X at the right end of the FIRST pinned page and LEFT-click the X itself.
            EXPECT: that page closes, and the X on the first pinned page DISAPPEARS -- a pinned page whose
            page is closed has no X, so there is nothing to click again: that is the pass. The first
            pinned page stays; the second keeps its X.
 6. DELETE FOLDER -- THEN CANCEL. RIGHT-click a FOLDER -> "Delete folder".
            EXPECT: a question "Delete this folder and the N pinned pages in it?".
            Click CANCEL (not Delete folder). EXPECT: the folder is still there.
 7. Close the browser window (its X, top right).
"@
        RunLeg "THE RECHECK (one run)" $log1 $steps1
    } else {
        $steps1 = @"
 1. [any workspace]  LEFT-click "Canary" in the rail at the bottom.
 2. LEFT-click a PINNED PAGE near the top (not a folder).
            EXPECT: its page shows on the right; that pinned page is highlighted and has a small X at its
            right end; NO new Today tab appears below the line.
 3. LEFT-click any TODAY TAB, then LEFT-click the same PINNED PAGE again.
            EXPECT: the pinned page loses its highlight but keeps its X; the second click brings the SAME
            page back -- no reload, still scrolled where you left it.
 4. THE BACK ARROW. In that page, LEFT-click a link that opens in the SAME tab.
            EXPECT: a small back arrow appears on the pinned page, just left of its X.
            LEFT-click that arrow. EXPECT: the page goes back to where it started; the arrow disappears.
 5. CTRL+W. With that page still showing (its pinned page highlighted), press Ctrl+W.
            EXPECT: the page closes. The pinned page is STILL ABOVE the line, without highlight or X.
            A Today tab shows instead.
 6. THE X. LEFT-click one pinned page, then a second one (both now have an X). Put the mouse on the
            small X at the right end of the FIRST pinned page and LEFT-click the X itself.
            EXPECT: that page closes, and the X on the first pinned page DISAPPEARS -- a pinned page whose
            page is closed has no X, so there is nothing to click again: that is the pass. The first
            pinned page stays; the second keeps its X.
 7. With the second page showing, press Ctrl+Shift+Tab ONCE (another tab is highlighted), then
            Ctrl+Tab ONCE. EXPECT: the second pinned page is highlighted again and its page shows.
 8. LEFT-click that second PINNED PAGE again (highlighted). Then SHIFT+LEFT-click a TODAY TAB two or
            three tabs below the line: some Today tabs are highlighted. Press Ctrl+W.
            EXPECT: only the highlighted TODAY TABS close; the pinned page keeps its X (its page is open).
 9. RIGHT-click a PINNED PAGE that has NO X -> "Unpin".
            EXPECT: it leaves the pinned section; its page opens as a Today tab at the end of the list.
10. RIGHT-click another PINNED PAGE -> "Delete".      EXPECT: it leaves the pinned section.
11. DELETE FOLDER -- THEN CANCEL. RIGHT-click a FOLDER -> "Delete folder".
            EXPECT: a question "Delete this folder and the N pinned pages in it?".
            Click CANCEL (not Delete folder). EXPECT: the folder is still there.
12. LEFT-click one PINNED PAGE so its page is open, then close the browser window (its X, top right).
"@
        $steps2 = @"
13. [wait] the window restores by itself. LEFT-click "Canary" if it is not showing.
            EXPECT: the pinned page you opened in step 12 has its X (its page came back), and that page is
            NOT a Today tab below the line. LEFT-click the pinned page: its page shows.
14. Close the browser window.
"@
        RunLeg "RUN 1 of 2" $log1 $steps1
        Start-Sleep 3
        RunLeg "RUN 2 of 2: THE RESTART" $log2 $steps2
    }
}

# ---- your answers ----------------------------------------------------------------------------
$questions = if ($Arrow) { [ordered]@{
    noarrow = "2. NO back arrow showed when the pinned page's page first opened (y/n)"
    arrow   = "3. the arrow appeared after the link, took the page back, and then disappeared (y/n)"
} } elseif ($Recheck) { [ordered]@{
    arrow   = "3. the back arrow appeared on the pinned page after the link, and took the page back (y/n)"
    ctrlw   = "4. Ctrl+W closed the page and the pinned page stayed, without X (y/n)"
    x       = "5. clicking the X closed only that page; the pinned page stayed (y/n)"
    confirm = "6. Delete folder asked first, you clicked Cancel, and the folder is still there (y/n)"
} } else { [ordered]@{
    open      = "2. the page showed, its pinned page highlighted with an X, and NO new Today tab (y/n)"
    reshow    = "3. the pinned page kept its X; clicking it again brought the SAME page back, not reloaded (y/n)"
    arrow     = "4. the back arrow appeared on the pinned page after the link, and took the page back (y/n)"
    ctrlw     = "5. Ctrl+W closed the page and the pinned page stayed, without X (y/n)"
    x         = "6. clicking the X closed only that page; the pinned page stayed (y/n)"
    ctrltab   = "7. Ctrl+Shift+Tab then Ctrl+Tab came back onto the pinned page's page (y/n)"
    shift     = "8. Ctrl+W closed only the highlighted TODAY tabs; the pinned page kept its X (y/n)"
    unpin     = "9. Unpin: it left the pinned section and its page became a Today tab (y/n)"
    delete    = "10. Delete: it left the pinned section (y/n)"
    confirm   = "11. Delete folder asked first, you clicked Cancel, and the folder is still there (y/n)"
    restart   = "13. after the restart the pinned page had its X, its page was not a Today tab, and a click showed it (y/n)"
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
function Note($text) { Write-Host "      $text" }
function Count($lines, $re) { @($lines | Where-Object { $_ -match $re }).Count }

$logs = if ($Recheck) { @($log1) } else { @($log1, $log2) }
foreach ($l in $logs) {
    if (-not (Test-Path $l) -or (Get-Item $l).Length -eq 0) { Write-Host "FAIL: $l missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
}
$w1 = @(Get-Content $log1 | Where-Object { $_ -match '\[workspaces\]' })
Note ("run 1: {0} opened, {1} closed by Ctrl+W, {2} by the X, {3} back arrow, {4} unpinned, {5} deleted" -f `
    (Count $w1 "pins: opened item '[^']+'$"), (Count $w1 "closed the page of pinned item .*\(Ctrl\+W\)"), `
    (Count $w1 "closed the page of pinned item .*\(the row's close button\)"), (Count $w1 'reset to anchor'), `
    (Count $w1 'pins: unpinned item'), (Count $w1 'pins: deleted '))
Verdict "pinned pages opened"                                            ((Count $w1 "pins: opened item '[^']+'$") -ge $(if ($Arrow) { 1 } elseif ($Recheck) { 2 } else { 3 }))
Verdict "the back arrow went back to the pinned address"                ((Count $w1 'reset to anchor') -ge 1)
if (-not $Arrow) {
Verdict "Ctrl+W closed a pinned page for real"                          ((Count $w1 "closed the page of pinned item .*\(Ctrl\+W\)") -ge 1)
Verdict "the X closed a pinned page"                                    ((Count $w1 "closed the page of pinned item .*\(the row's close button\)") -ge 1)
Verdict "Delete folder asked, and was cancelled"                        ((Count $w1 'confirm asked: delete folder') -ge 1 -and (Count $w1 'confirm cancelled') -ge 1)
}
if (-not $Recheck) {
    $w2 = @(Get-Content $log2 | Where-Object { $_ -match '\[workspaces\]' })
    Verdict "Unpin"                                                     ((Count $w1 'pins: unpinned item') -ge 1)
    Verdict "Delete"                                                    ((Count $w1 'pins: deleted ') -ge 1)
    Verdict "run 2: the pins file loaded"                               ((Count $w2 'pins: loaded [1-9]\d* row\(s\)') -ge 1)
    Verdict "run 2: a pinned page's page came back open after the restart" ((Count $w2 'pins: [1-9]\d* item page\(s\) open in this window') -ge 1)
    Verdict "run 2: no page lost its pinned page at the restart"         ((Count $w2 "a page's item is gone") -eq 0)
}
$markers = (Get-Content $logs | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the logs" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLogs: $($logs -join ', ')   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
