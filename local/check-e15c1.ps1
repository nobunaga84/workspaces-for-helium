param([switch]$GradeOnly,
      [switch]$Reuse,                 # keep the copy from the last run instead of copying testprofile again
      [string]$OutDir = "Default",
      [string]$Tag = "e15c1")
# E15c.1: where a new tab opens, as Arc places it (LOCAL.md 47) -- "+ New Tab" at the top of the Today tabs,
# a new tab right under it, Ctrl+T the same; a link from a pinned page at the top too (after the earlier
# links from that page); a link from a Today tab just below that tab. Runs on a THROWAWAY COPY of
# testprofile (its Recently Closed emptied first, LOCAL.md 42); testprofile is never touched.
# The log proves where each new tab was placed and how long the window was busy; where it APPEARED is
# your y/n.
#
#   check-e15c1.ps1              copy testprofile, one run, answer, grade
#   check-e15c1.ps1 -GradeOnly   grade the saved log and answers again
$ws      = "<local-path>\Helium-workspace"
$src     = "$ws\testprofile"
$prof    = "$ws\testprofile-$Tag"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$service = "$ws\helium-windows\build\src\chrome\browser\ui\tabs\workspaces\workspace_service.cc"
$log     = "$ws\$Tag-run.log"
$answers = "$ws\$Tag-run-answers.json"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item $exe).LastWriteTime -lt (Get-Item $service).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.exe is older than the service's source (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'the window was busy')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 42" -ForegroundColor Red; exit 1 }
    if (-not $Reuse -or -not (Test-Path $prof)) {
        if ((Test-Path $prof) -and $prof.EndsWith("-$Tag")) { Remove-Item -Recurse -Force $prof }
        Write-Host "copying $src -> $prof (a throwaway copy; testprofile is not touched) ..." -ForegroundColor Green
        robocopy $src $prof /E /NFL /NDL /NJH /NP /R:1 /W:1 /XD "Cache" "Code Cache" "GPUCache" "GrShaderCache" "ShaderCache" | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Host "ABORT: the copy failed (robocopy $LASTEXITCODE)" -ForegroundColor Red; exit 1 }
        Get-ChildItem "$prof\Default\Sessions" -Filter "Tabs_*" -EA SilentlyContinue | Remove-Item -Force
    }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    # The last run's log and answers are kept as .prev, not deleted: a re-run of a few steps must not
    # erase the evidence of the rest (E15c.1: a steps-9-11 re-run did).
    foreach ($f in $log, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window:
  PINNED PAGE  an entry ABOVE the thin line: a page name with a small icon. It is not a tab.
  + NEW TAB    the entry with a "+" and the words "New Tab", right UNDER the thin line.
  TODAY TAB    an ordinary tab below "+ New Tab".
Use the LEFT mouse button unless a step says otherwise.
"@ -ForegroundColor Magenta
    Write-Host @"
 1. [any workspace]  LEFT-click "Canary" in the rail at the bottom.
            EXPECT: right under the thin line, "+ New Tab"; the Today tabs below it.
            Note which TODAY TAB is highlighted (the one showing).
 2. LEFT-click "+ New Tab".
            EXPECT: a new Today tab appears right under "+ New Tab" -- the TOP of the Today tabs -- and it
            is the one showing. Now press Ctrl+W.
            EXPECT: you are back on the Today tab you noted in step 1 -- not on the tab that was below
            the new one.
 3. Press Ctrl+T.   EXPECT: the same -- a new Today tab at the top, right under "+ New Tab".
            Type  example.com  and press Enter. When the page has loaded, press Ctrl+W.
            EXPECT: again you are back on the Today tab you noted in step 1.
 4. LEFT-click a PINNED PAGE (not a folder) whose page has links. In that page, hold Ctrl and LEFT-click a
            link; then hold Ctrl and LEFT-click a DIFFERENT link.
            EXPECT: two new Today tabs appear at the TOP, right under "+ New Tab", the first link's tab
            above the second's.
 5. LEFT-click one of those two new Today tabs so its page shows; in it, hold Ctrl and LEFT-click a link.
            EXPECT: the new Today tab appears right BELOW the tab you are on -- not at the top.
 6. Scroll the Today tabs to the very bottom and LEFT-click the LAST Today tab. Press Ctrl+T.
            EXPECT: the list shows the new tab at the TOP, right under "+ New Tab". Watch for a pause or a
            stutter as it appears.
 7. RIGHT-click a PINNED PAGE that has NO X -> "Unpin".
            EXPECT: it leaves the pinned section, and its page opens as a Today tab at the TOP, right under
            "+ New Tab".
 8. RIGHT-click "+ New Tab".   EXPECT: a small menu (New tab, ...). Press Esc to close it.
 9. LEFT-click "+ New Tab" (a new Today tab opens at the top). Click the address bar, then press F6 until
            a focus ring is on that new Today tab -- the bookmarks bar, when shown, comes first. Then stop
            pressing F6 (it moves on to other parts of the window) and use the arrow keys.
            Press Up: the ring moves onto "+ New Tab". Press Up again: onto the last PINNED PAGE.
            Now press Down once.   EXPECT: the ring moves back onto "+ New Tab".
10. LEFT-click "Home" in the rail.
            EXPECT: "+ New Tab" is at the top of the list there too (with no pinned pages there is no
            thin line; "+ New Tab" is then the first entry).
11. Close the browser window (its X, top right).
"@ -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = [ordered]@{
    top      = "2. + New Tab opened a new Today tab at the TOP, right under + New Tab (y/n)"
    back     = "2. Ctrl+W on it took you back to the Today tab you noted in step 1 (y/n)"
    ctrlt    = "3. Ctrl+T opened the new Today tab at the top too (y/n)"
    typed    = "3. after typing example.com in it, Ctrl+W still took you back to the tab from step 1 (y/n)"
    pinlinks = "4. the two links from the pinned page opened at the TOP, the first above the second (y/n)"
    below    = "5. the link from a Today tab opened right BELOW that Today tab (y/n)"
    instant  = "6. no noticeable pause when the new tab appeared from the bottom of the list (y/n)"
    unpin    = "7. Unpin: the page opened as a Today tab at the TOP, under + New Tab (y/n)"
    menu     = "8. right-clicking + New Tab showed a menu (y/n)"
    down     = "9. Down from the last pinned page moved the ring onto + New Tab (y/n)"
    home     = "10. + New Tab was at the top of the list in Home too (y/n)"
}
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
$w = @(Get-Content $log | Where-Object { $_ -match '\[workspaces\] new tab at index' })
$top = @($w | Where-Object { $_ -match '\(the top of the list\)' })
$pin = @($w | Where-Object { $_ -match '\(a link from a pinned page\)' })
foreach ($l in $w) { Write-Host ("      " + ($l -replace '^.*\] new tab', 'new tab')) }
Verdict "new tabs placed at the top of the list (steps 2, 3, 6)"            ($top.Count -ge 3)
# Step 3's way back after typing is the owner's y/n: nothing logs an opener.
Verdict "links from a pinned page placed at the top (step 4)"               ($pin.Count -ge 2)
Verdict "Unpin opened its page as a Today tab (step 7)"                     (@(Get-Content $log | Where-Object { $_ -match 'pins: unpinned item' }).Count -ge 1)  # E15d: opened still linked, then unlinked -- no "as a Today tab" line
$ms = @($w | ForEach-Object { if ($_ -match 'busy (\d+) ms') { [int]$Matches[1] } } | Sort-Object)
if ($ms.Count) { Write-Host ("      the window was busy {0}-{1} ms per placed tab (median {2})" -f $ms[0], $ms[-1], $ms[[int]($ms.Count / 2)]) }
$markers = (Get-Content $log | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLog: $log   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
