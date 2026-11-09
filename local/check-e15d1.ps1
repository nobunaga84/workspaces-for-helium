param([switch]$GradeOnly,
      [switch]$Recheck,               # only the two fixes after the owner's first run: the title, a still list
      [switch]$Folder,                # only the re-check's step 6: New folder keeps the list still
      [switch]$Reuse,                 # keep the copy from the last run instead of copying testprofile again
      [string]$OutDir = "Default",
      [string]$Tag = "e15d1")
# E15d.1: Rename, New folder, "Pin to this workspace" and where an unpinned OPEN page lands (LOCAL.md 48).
# Runs on a THROWAWAY COPY of testprofile (its Recently Closed emptied first, LOCAL.md 42); testprofile is
# never touched. The log proves each action ran; the pins file the copy leaves behind proves it was SAVED;
# what you saw is your y/n.
#
#   check-e15d1.ps1              copy testprofile, one run, answer, grade
#   check-e15d1.ps1 -GradeOnly   grade the saved log, answers and pins file again
#   check-e15d1.ps1 -Recheck     the owner's two findings, fixed: the box says "Rename", the list keeps still
$run     = if ($Folder) { "folder" } elseif ($Recheck) { "recheck" } else { "run" }
$ws      = "<local-path>\Helium-workspace"
$src     = "$ws\testprofile"
$prof    = "$ws\testprofile-$Tag"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\43-pinned-edit.patch"
$pins    = "$prof\Default\Workspace Pins"
$log     = "$ws\$Tag-$run.log"
$answers = "$ws\$Tag-$run-answers.json"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    # Against patch 43 itself, not the section's source: patch 44 edits that file too (E15d.2).
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt (Get-Item $patch).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.dll is older than patch 43 (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'pinned a tab as item')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 43" -ForegroundColor Red; exit 1 }
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
Use the LEFT mouse button unless a step says otherwise. Every step is done in "Work".
"@ -ForegroundColor Magenta
    $recheckSteps = @"
 1. LEFT-click "Work" in the rail at the bottom. LEFT-click the FIRST PINNED PAGE (its page opens; it gets an X).
 2. RIGHT-click that same PINNED PAGE.
            EXPECT: the menu item reads "Rename" -- not "Rename workspace". LEFT-click it.
            EXPECT: the box's title reads "Rename". Press Esc.
 3. Scroll the list DOWN until the Today tabs fill the window and the pinned pages are out of sight above.
            Note which TODAY TAB is at the very top of the window. LEFT-click a TODAY TAB (a web page) in view,
            then RIGHT-click it -> "Pin to this workspace".
            EXPECT: that tab leaves the Today tabs, and the list does NOT scroll: the TODAY TAB you noted is
            still at the top of the window (its new pinned page is out of sight above -- that is right).
 4. Scroll the list UP to the very top, so the FIRST PINNED PAGE (from step 1, with an X) is in view.
            If "+ New Tab" is also in view, make the window shorter until it is not.
            LEFT-click the FIRST PINNED PAGE (its page shows), then RIGHT-click it -> "Unpin".
            EXPECT: it leaves the pinned pages, and the list does NOT scroll: the pinned pages below it move up
            one line, nothing else moves (its page is now the top Today tab, out of sight below).
 5. Still at the top of the list, with "+ New Tab" out of sight below: RIGHT-click a PINNED PAGE that has NO X
            (its page is not open) -> "Unpin".
            EXPECT: it leaves the pinned pages and the list does NOT scroll (its page opens as the top Today tab,
            out of sight below).
 6. Scroll the list down a little, so the first pinned pages are out of sight ABOVE. RIGHT-click a PINNED PAGE
            in view -> "New folder".
            EXPECT: "New folder" appears right below it and the Rename box opens on it -- and the list does
            NOT jump to the top. Press Esc.
 7. Close the browser window (its X, top right).
"@
    $folderSteps = @"
 1. LEFT-click "Work" in the rail at the bottom.
 2. Scroll the list DOWN a little -- about 5 turns of the mouse wheel -- so the first PINNED PAGES are out of
            sight ABOVE, and the window still shows PINNED PAGES (the thin line is further down).
 3. RIGHT-click a PINNED PAGE in view. CHECK THE MENU FIRST: it must be SHORT -- Unpin, Rename, New folder,
            Delete. A LONG menu with "New tab below" and "Pin to this workspace" means you right-clicked a TODAY TAB:
            press Esc, scroll up, and right-click an entry above the thin line.
            In the short menu, LEFT-click "New folder".
            EXPECT: "New folder" appears right below that pinned page, the Rename box opens on it, and the list
            does NOT jump to the top. Press Esc.
 4. Close the browser window (its X, top right).
"@
    $steps = if ($Folder) { $folderSteps } elseif ($Recheck) { $recheckSteps } else { @"
 1. LEFT-click "Work" in the rail at the bottom.
            EXPECT: pinned pages above the thin line, "+ New Tab" under it, Today tabs below.
 2. RIGHT-click the FIRST PINNED PAGE -> "Rename".
            EXPECT: a small box titled "Rename" with a "Name" field holding the page's name.
            Press Ctrl+A, type  Renamed page  and press Enter.
            EXPECT: that pinned page now reads "Renamed page".
 3. RIGHT-click the SECOND PINNED PAGE -> "New folder".
            EXPECT: a FOLDER named "New folder" appears right BELOW that pinned page, and the "Rename" box
            opens on it by itself. Press Ctrl+A, type  My folder  and press Enter.
            EXPECT: the new FOLDER reads "My folder".
 4. RIGHT-click the FOLDER "My folder" -> "Rename". Press Ctrl+A, type  Renamed folder  and press Enter.
            EXPECT: the FOLDER reads "Renamed folder".
 5. LEFT-click a TODAY TAB whose page is a web page (its address starts with http), so it shows.
            RIGHT-click that same TODAY TAB -> "Pin to this workspace".
            EXPECT: it leaves the Today tabs and becomes the LAST PINNED PAGE (just above the thin line),
            highlighted, with an X -- its page still showing, not reloaded. Remember its name.
 6. LEFT-click one TODAY TAB, then hold Ctrl and LEFT-click another TODAY TAB further down (both web
            pages). RIGHT-click one of the two -> "Pin to this workspace".
            EXPECT: both leave the Today tabs and become the last two PINNED PAGES, in the same order they
            had in the Today tabs.
 7. RIGHT-click the PINNED PAGE from step 5 (it has an X: its page is open) -> "Unpin".
            EXPECT: it leaves the pinned section and becomes the TOP TODAY TAB, right under "+ New Tab",
            its page still showing, not reloaded.
 8. LEFT-click "+ New Tab" (a New Tab page opens at the top of the Today tabs). RIGHT-click that new TODAY TAB.
            EXPECT: "Pin to this workspace" is in the menu but GREYED OUT (a New Tab page is not a web page).
            Press Esc.
 9. Close the browser window (its X, top right).
"@ }
    Write-Host $steps -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = if ($Folder) { [ordered]@{
    shortmenu   = "3. the menu was the SHORT one (Unpin, Rename, New folder, Delete) (y/n)"
    folderstill = "3. after New folder the list did NOT jump to the top (y/n)"
} } elseif ($Recheck) { [ordered]@{
    menu    = "2. the menu item read 'Rename', not 'Rename workspace' (y/n)"
    title   = "2. the box's title read 'Rename' (y/n)"
    pinstill   = "3. after Pin to this workspace the list did NOT scroll (the noted Today tab stayed at the top) (y/n)"
    unpinstill = "4. after Unpin the list did NOT scroll (y/n)"
    sleepstill = "5. after Unpin of a pinned page with no X the list did NOT scroll (y/n)"
    folderstill = "6. after New folder the list did NOT jump to the top (y/n)"
} } else { [ordered]@{
    title   = "2. the box's title read 'Rename' (y/n)"
    rename  = "2. the pinned page was renamed to 'Renamed page' (y/n)"
    folder  = "3. 'New folder' appeared right below the pinned page and the Rename box opened by itself (y/n)"
    fname   = "3. the folder then read 'My folder' (y/n)"
    frename = "4. the folder was renamed to 'Renamed folder' (y/n)"
    pin1    = "5. the Today tab became the LAST pinned page, still showing its page (y/n)"
    pin2    = "6. both Today tabs became the last two pinned pages, in their Today order (y/n)"
    unpin   = "7. Unpin: the open pinned page became the TOP Today tab, not reloaded (y/n)"
    grey    = "8. 'Pin to this workspace' was greyed out on the New Tab page (y/n)"
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
$lines  = @(Get-Content $log)
$file   = Get-Content $pins -Raw
$pinned = @($lines | ForEach-Object { if ($_ -match "pins: pinned a tab as item '([^']+)'") { $Matches[1] } })
$gone   = @($lines | ForEach-Object { if ($_ -match "pins: unpinned item '([^']+)'") { $Matches[1] } })
if ($Folder) {
Verdict "a folder was made (step 3)"                                               (@($lines | Where-Object { $_ -match "pins: new folder '" }).Count -ge 1)
} elseif ($Recheck) {
Verdict "a Today tab pinned (step 3)"                                               ($pinned.Count -ge 1)
Verdict "two pinned pages unpinned, one open, one not (steps 4, 5)"                 ($gone.Count -ge 2)
Verdict "a folder was made (step 6)"                                               (@($lines | Where-Object { $_ -match "pins: new folder '" }).Count -ge 1)
} else {
Verdict "Rename ran 3 times: a page, the new folder, the folder again (steps 2-4)"  (@($lines | Where-Object { $_ -match "pins: renamed '" }).Count -ge 3)
Verdict "a folder was made (step 3)"                                               (@($lines | Where-Object { $_ -match "pins: new folder '" }).Count -ge 1)
Verdict "3 Today tabs pinned (steps 5, 6)"                                         ($pinned.Count -ge 3)
Verdict "an open pinned page was unpinned (step 7)"                                ($gone.Count -ge 1)
# What was SAVED: the copy's pins file after the browser closed (the store flushes as the profile goes).
Verdict "saved: the page's own name 'Renamed page'"                                ($file -match '"custom_title": "Renamed page"')
Verdict "saved: the folder's name 'Renamed folder', and no 'My folder' left"       (($file -match '"title": "Renamed folder"') -and ($file -notmatch '"title": "My folder"'))
$kept = @($pinned | Where-Object { $_ -notin $gone -and $file.Contains("`"$_`"") })
Verdict "saved: every pinned tab still pinned but the unpinned one ($($kept.Count) of $($pinned.Count - $gone.Count))" ($pinned.Count -ge 3 -and $kept.Count -eq ($pinned.Count - @($gone | Where-Object { $_ -in $pinned }).Count))
Verdict "saved: the unpinned page is gone from the pinned section"                 ($gone.Count -ge 1 -and @($gone | Where-Object { $file.Contains("`"$_`"") }).Count -eq 0)
}
$markers = ($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLog: $log   Answers: $answers   Pins: $pins. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
