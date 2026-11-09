# historical (pre-E17): E17a moved Archive from the "+" menu to the bar's own button (log 'rail: archive'); check-e14d2-auto.ps1 is the current test.
param([switch]$GradeOnly,
      [string]$OutDir = "Default",
      [string]$Tag = "e14d2")
# E14d.2, the Archive screen by hand (design 5, "The Archive screen" and "Restore"): close pages, find them on the
# screen, search, restore (into its own workspace, from another one too), Ctrl+Shift+T after a restore, Delete,
# Clear... > All time with its Cancel, and how it looks. Runs on a fresh throwaway copy of testprofile-e15b-smoke;
# testprofile is never touched. The script opens E14d2 fig in Home, switches the window to Work and opens the
# four other pages there itself, and checks all of it before you start. Each page has its own coloured icon
# (apple red, banana yellow, cherry purple, date blue, fig green), so a row that shows the globe instead is
# something you can see. The log and the archive file ("Workspace Archive") are graded here, what you saw is
# your y/n. What each graded row proves:
#   steps 1, 5b, 7 / 6  six manual closes archived in Work, one in Home; none refused
#   step 2              the + button's Archive opens the screen on Work's two entries
#   step 3              the search filters to one entry (that the search box stays still while typing is
#                       check-e14d2-auto.ps1's row C: in this window the screen opens below the rail, where
#                       its top edge is fixed and the box cannot move either way)
#   steps 4, 6          two restores into Work, each taking its Recently Closed tab with it ("left too")
#   step 5              Ctrl+Shift+T after a restore reopens the close before it ("leaves the archive"), never
#                       the restored page again ("was not in the archive")
#   step 6              done from Home (a switch to Home between the restores; "opened, 2 entr(ies), 1 shown":
#                       Home's fig alone); All workspaces shows both; the window's switch to Work is logged
#                       just BEFORE the restore line, never after it (a bare switch logs the same: that coming
#                       back to Home by the rail lands on the tab you left is check-e14d2-auto.ps1's row E)
#   step 7              "opened, 4 entr(ies), 3 shown" (Home's fig not listed); one Delete
#   steps 8, 9          Clear... > All time asks about 3 -- Home's fig with Work's two shown -- and clears 3, so the file
#                       ends with 0 entries: it empties EVERY workspace, not the rows shown
#   step 10             the last window's close archives nothing; 0 crash markers; no title, address or typed
#                       text in a [workspaces] line (47's rule)
#
#   check-e14d2.ps1              one run, answer, grade
#   check-e14d2.ps1 -GradeOnly   grade the saved log, file and answers again
$ws      = "<local-path>\Helium-workspace"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof    = "$ws\testprofile-$Tag"
$src     = "$ws\helium-windows\build\src"
$bin     = "$src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\48-archive-screen.patch"
$log     = "$ws\$Tag-run.log"
$answers = "$ws\$Tag-run-answers.json"
$afile   = "$prof\Default\Workspace Archive"
$pages   = "$ws\$Tag-pages"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
# Work's four pages; fig is Home's.
$names   = @("apple", "banana", "cherry", "date")
$colours = [ordered]@{ apple = "Red"; banana = "Gold"; cherry = "Purple"; date = "RoyalBlue"; fig = "Green" }
# The screen's "Clear" button ends in U+2026; built here so this file stays ASCII.
$clear   = "Clear$([char]0x2026)"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }
function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Fail([string]$why) { Write-Host "ABORT: $why" -ForegroundColor Red; exit 1 }
function WaitLog([string]$re, [int]$s) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and (Select-String -Path $log -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# The test pages that are Today tabs of the window, shown (a tab of another workspace is INVISIBLE).
function ShownPages { @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -List | ForEach-Object { if ($_ -match '^\s*E14d2 (\w+)\|0x25$') { $Matches[1] } }) }
function Quit([string]$why) {
    foreach ($id in BrowserPids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    Stop-Process -Id $server.Id -EA SilentlyContinue
    Fail "$why -- the browser was closed; run the script again"
}

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Fail "a fork browser is already running -- close it first (forwarded-launch trap)." }
    # Against the newest SOURCE file of patch 48, not the patch file: a quilt refresh after the build rewrites the
    # patch from the same sources (LOCAL.md 52).
    $sources = @("chrome\browser\ui\tabs\workspaces\workspace_archive.h", "chrome\browser\ui\tabs\workspaces\workspace_archive.cc",
                 "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.h", "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.cc",
                 "chrome\browser\ui\views\tabs\vertical\workspace_rail_view.h", "chrome\browser\ui\views\tabs\vertical\workspace_rail_view.cc")
    if (Test-Path $patch) { $sources += @(Select-String -Path $patch -Pattern '^\+\+\+ b/(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
    $missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
    if ($missing.Count) { Fail "missing source(s) of patch 48: $($missing -join ', ')" }
    $newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Fail "$OutDir chrome.dll is older than a source file of patch 48 (stale binary)" }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'archive screen:')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Fail "$OutDir\chrome.dll does not contain patch 48" }
    if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    # An empty Recently Closed: the copy's own held a whole window (LOCAL.md 52).
    Remove-Item "$prof\Default\Sessions\Tabs_*" -Force -EA SilentlyContinue
    & python "$here\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Fail "preconditions not met (vertical layout, a non-default workspace, enabled)" }
    if (Test-Path -LiteralPath $afile) { Fail "the copied profile already has an archive file" }
    foreach ($f in $log, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    # Each page with its own icon, a solid square of its colour: a loaded page leaves it in history, where the
    # Archive screen's row looks it up (a row without one shows the globe).
    $null = New-Item -ItemType Directory -Force $pages
    Add-Type -AssemblyName System.Drawing
    foreach ($n in $colours.Keys) {
        $bmp = New-Object System.Drawing.Bitmap 32, 32
        $gfx = [System.Drawing.Graphics]::FromImage($bmp); $gfx.Clear([System.Drawing.Color]::FromName($colours[$n])); $gfx.Dispose()
        $bmp.Save("$pages\$n.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
        Set-Content -Encoding UTF8 -Path "$pages\$n.html" -Value "<!doctype html><link rel=icon href=$n.png><title>E14d2 $n</title><h1>E14d2 $n</h1>"
    }
    $server = Start-Process -FilePath python -ArgumentList @("-m", "http.server", "$port", "--bind", "127.0.0.1", "--directory", $pages) -PassThru -WindowStyle Hidden
    Start-Sleep 2
    $probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 (Url "apple")).StatusCode } catch { 0 }
    if ($probe -ne 200) { Stop-Process -Id $server.Id -EA SilentlyContinue; Fail "the test pages are not served on port $port" }

    # Set-up done here and checked, not described: fig opens in Home (the window starts there), the window
    # switches to Work, then the four pages open in it.
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    if (-not (WaitLog "pins: drew \d+ row\(s\) of 'default'" 30)) { Quit "the browser did not draw its sidebar" }
    Start-Sleep 2
    Start-Process -FilePath $exe -ArgumentList @("--user-data-dir=$prof", (Url "fig")) | Out-Null
    $t = Get-Date
    do { Start-Sleep 2; $shown = @(ShownPages) } while (((Get-Date) - $t).TotalSeconds -lt 30 -and $shown -notcontains "fig")
    if ($shown -notcontains "fig") { Quit "E14d2 fig is not a Today tab of Home (seen: $($shown -join ', '))" }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Name "Work" -Role 0x2B | Out-Null
    if (-not (WaitLog "pins: drew \d+ row\(s\) of '$work'" 15)) { Quit "the window did not switch to Work" }
    Start-Process -FilePath $exe -ArgumentList (@("--user-data-dir=$prof") + @($names | ForEach-Object { Url $_ })) | Out-Null
    $t = Get-Date
    do { Start-Sleep 2; $shown = @(ShownPages) } while (((Get-Date) - $t).TotalSeconds -lt 30 -and @($names | Where-Object { $shown -contains $_ }).Count -lt 4)
    if (@($names | Where-Object { $shown -contains $_ }).Count -lt 4 -or $shown -contains "fig") { Quit "the four pages are not all Today tabs of Work, or fig is not Home's alone (seen: $($shown -join ', '))" }

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window, the SIDEBAR:
  RAIL            the row of workspace buttons at the bottom of the sidebar; the one you are in is highlighted.
  + BUTTON        the "+" at the bottom of the sidebar, at the end of the rail.
  TODAY TAB       a page listed BELOW the thin line in the sidebar, e.g. "E14d2 apple".
  ARCHIVE SCREEN  what the + button's "Archive" opens: a search box, an "All workspaces" tick box, then the
                  tabs you closed, newest first, under a heading per day ("Today"), and "$clear" at the bottom.
  ENTRY           one closed page listed on the Archive screen.
"@ -ForegroundColor Magenta
    Write-Host @"
 0. CHECK FIRST: "Work" is highlighted in the RAIL, and the TODAY TABS E14d2 apple, banana, cherry and date
    are listed. (E14d2 fig is a TODAY TAB of Home; you meet it in step 6.)
 1. FROM Work: close the TODAY TAB "E14d2 apple", then "E14d2 banana" (hover each, click its X).
                                                   EXPECT: both are gone from the sidebar.
 2. FROM Work: click the + BUTTON -> "Archive".    EXPECT: the ARCHIVE SCREEN opens; under "Today" it lists
                                                   "E14d2 banana" first, then "E14d2 apple", each with its
                                                   own square: banana yellow, apple red.
 3. STILL in Work: click in its search box and type: bana
                                                   EXPECT: only the ENTRY "E14d2 banana" is listed.
 4. STILL in Work: click the ENTRY "E14d2 banana". EXPECT: the ARCHIVE SCREEN closes; "E14d2 banana" is open
                                                   again, the FIRST TODAY TAB of Work.
 5. STILL in Work: press Ctrl+Shift+T (it reopens the last closed tab).
                                                   EXPECT: no second copy of the page you just brought back:
                                                   "E14d2 banana" is listed ONCE, and "E14d2 apple" (closed
                                                   before it) is open again instead.
5b. FROM Work: close the TODAY TAB "E14d2 apple" again (its X).
                                                   EXPECT: "E14d2 apple" leaves the sidebar.
 6. Click "Home" in the RAIL (hover a button to see its name). FROM Home: close the TODAY TAB "E14d2 fig".
    Then + BUTTON -> "Archive".                    EXPECT: the ARCHIVE SCREEN lists only the ENTRY
                                                   "E14d2 fig" (a green square); Work's apple is not listed.
    Tick "All workspaces".                         EXPECT: the ENTRY "E14d2 apple" appears too, Work's rail
                                                   icon in front of it (and Home's in front of fig).
    Click "E14d2 apple".                           EXPECT: the screen closes, the window goes to Work ("Work"
                                                   highlighted), "E14d2 apple" is the FIRST TODAY TAB.
 7. FROM Work: close the TODAY TABS "E14d2 apple", "E14d2 banana" and "E14d2 cherry" (their X); keep
    "E14d2 date". Then + BUTTON -> "Archive".      EXPECT: three ENTRIES, "All workspaces" NOT ticked, and
                                                   no rail icon in front of the entries.
    RIGHT-click the ENTRY "E14d2 cherry" -> "Delete".
                                                   EXPECT: cherry is gone, apple and banana stay, and the
                                                   ARCHIVE SCREEN stays open.
 8. STILL in Work, the same ARCHIVE SCREEN: click "$clear" at its bottom, then "All time" in its list. It asks
    to delete 3 archived tabs -- apple, banana and Home's fig: All time empties every workspace -- click "Cancel".
                                                   EXPECT: apple and banana are still listed.
 9. STILL in Work: "$clear" > "All time" again, then "Delete".
                                                   EXPECT: the ARCHIVE SCREEN says "No archived tabs".
10. Close the window with its X (top right).
    Keep in mind for the last question: whenever the ARCHIVE SCREEN listed ENTRIES (steps 2, 6, 7), did it look
    right -- ENTRIES under a day heading, each with ITS OWN coloured square in front, not a globe (apple red,
    banana yellow, cherry purple, fig green), the screen inside the window, nothing cut off?
"@ -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Stop-Process -Id $server.Id -EA SilentlyContinue
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = [ordered]@{
    setup   = "0. Work highlighted, apple, banana, cherry and date listed as Today tabs (y/n)"
    closed  = "1. apple and banana left the sidebar (y/n)"
    opened  = "2. the Archive screen listed banana, then apple, under 'Today' (y/n)"
    search  = "3. typing 'bana' left only banana listed (y/n)"
    restore = "4. the screen closed and banana came back as the first Today tab of Work (y/n)"
    reopen  = "5. Ctrl+Shift+T brought apple back, and banana was still listed only once; 5b. closing apple again took it off the sidebar (y/n)"
    allws   = "6. from Home only fig was listed; All workspaces added apple with Work's icon in front; clicking it took the window to Work, apple first (y/n)"
    delete  = "7. three entries, All workspaces not ticked; Delete took cherry off the Archive screen, which stayed open (y/n)"
    cancel  = "8. $clear > All time asked about 3 archived tabs; Cancel left apple and banana listed (y/n)"
    clear   = "9. $clear > All time, then Delete, left 'No archived tabs' (y/n)"
    look    = "10. it looked right: entries under a day heading, each with its own coloured square (not a globe), inside the window, nothing cut off (y/n)"
}
$a = if (Test-Path $answers) { Get-Content $answers -Raw | ConvertFrom-Json } else { $null }
if (-not $a) {
    Write-Host "`nAnswer each with y or n, then Enter:" -ForegroundColor Cyan
    $h = [ordered]@{}
    foreach ($k in $questions.Keys) {
        do { $r = (Read-Host $questions[$k]).Trim().ToLower() } while ($r -notin @('y', 'n'))
        $h[$k] = $r
    }
    $h['comment'] = "$(Read-Host "Anything that looked wrong or odd? (Enter for nothing)")".Trim()
    [pscustomobject]$h | ConvertTo-Json | Set-Content $answers -Encoding utf8
    $a = [pscustomobject]$h
}

# ---- grading -----------------------------------------------------------------------------------
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
if (-not (Test-Path $log) -or (Get-Item $log).Length -eq 0) { Write-Host "FAIL: $log missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
$lines = @(Get-Content $log)
function N([string]$re) { @($lines | Select-String -Pattern $re).Count }
# The line numbers of the log lines matching `re`, in order.
function At([string]$re) { @($lines | Select-String -Pattern $re | ForEach-Object { $_.LineNumber }) }
$e = if (Test-Path -LiteralPath $afile) { @((Get-Content -Raw -Encoding UTF8 -LiteralPath $afile | ConvertFrom-Json).entries) } else { @() }
Write-Host ("      file: " + $(if (Test-Path -LiteralPath $afile) { "$($e.Count) entr(ies)" } else { "none" }))
$restored = @(At "archive: restored an entry into '$work'")
$toWork   = @(At "active workspace -> '$work'")
$toHome   = @(At "active workspace -> 'default'")
$reopen   = @(At "archive: a reopened close leaves the archive")
# The last switch to Home before the second restore: step 6's move there.
$home6    = if ($restored.Count -eq 2) { @($toHome | Where-Object { $_ -lt $restored[1] })[-1] } else { $null }
Verdict "steps 1, 5b and 7: six 'archived a manual close' in Work (apple, banana; apple again; apple, banana, cherry)" ((N "archived a manual close in '$work'") -eq 6)
Verdict "step 6: one 'archived a manual close' in Home (fig)" ((N "archived a manual close in 'default'") -eq 1)
Verdict "nothing refused" ((N "archived a .*\(refused\)") -eq 0)
Verdict "step 2: the + button's 'Archive' ('rail + menu: archive'), 'opened, 2 entr(ies), 2 shown'" ((N "rail \+ menu: archive") -ge 1 -and (N "archive screen: opened, 2 entr\(ies\), 2 shown") -ge 1)
Verdict "step 3: the search left one entry ('filter of L char(s) -> 1 shown')" ((N "archive screen: filter of \d+ char\(s\) -> 1 shown") -ge 1)
Verdict "steps 4 and 6: two 'restored an entry into' Work, each with 'its Recently Closed entry left too'" ($restored.Count -eq 2 -and (N "archive: its Recently Closed entry left too") -eq 2 -and (N "archive: no Recently Closed tab of its own to remove") -eq 0)
Verdict "step 5: Ctrl+Shift+T between the restores reopened a close still archived ('a reopened close leaves the archive'), not the restored page ('was not in the archive')" ($restored.Count -eq 2 -and $reopen.Count -eq 1 -and $reopen[0] -gt $restored[0] -and $reopen[0] -lt $restored[1] -and (N "archive: a reopened close was not in the archive") -eq 0)
Verdict "step 6: done FROM Home -- a switch to Home between the two restores, the screen 'opened, 2 entr(ies), 1 shown'" ($restored.Count -eq 2 -and @($toHome | Where-Object { $_ -gt $restored[0] -and $_ -lt $restored[1] }).Count -ge 1 -and (N "archive screen: opened, 2 entr\(ies\), 1 shown") -ge 1)
# The restore switches the window to the entry's workspace BEFORE it inserts the page, so the switch to Work is
# logged between the move to Home and the restore line, never after it. The log cannot tell
# EnterWorkspaceForInsert from a bare switch; check-e14d2-auto.ps1's row E can (back in Home by the rail).
Verdict "step 6: 'all workspaces on -> 2 shown', and the window entered Work for the restore (logged just before it)" ((N "archive screen: all workspaces on -> 2 shown") -ge 1 -and $home6 -and @($toWork | Where-Object { $_ -gt $home6 -and $_ -lt $restored[1] }).Count -ge 1)
Verdict "step 7: 'opened, 4 entr(ies), 3 shown' (Home's fig not listed); one 'deleted an entry', not refused" ((N "archive screen: opened, 4 entr\(ies\), 3 shown") -ge 1 -and (N "archive: deleted an entry") -eq 1 -and (N "archive: deleted an entry \(refused\)") -eq 0)
Verdict "step 8: 'clear asked, all time (3)' -- Home's fig counted -- and 'clear cancelled'" ((N "archive screen: clear asked, all time \(3\)") -ge 1 -and (N "archive screen: clear cancelled") -ge 1)
Verdict "step 9: 'archive: cleared 3 entr(ies)', once" ((N "archive: cleared 3 entr\(ies\)") -eq 1 -and (N "archive: cleared \d+ entr") -eq 1)
Verdict "step 10: the last window archived nothing ('the session keeps the last window's tabs')" ((N "not archived: the session keeps the last window's tabs") -ge 1 -and (N "archived a window close") -eq 0)
Verdict "the file: there, with 0 entries -- Home's fig went too" ((Test-Path -LiteralPath $afile) -and $e.Count -eq 0)
$markers = ($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
Verdict "no [workspaces] line holds a page's title or address, or what you typed" (@($lines | Select-String -CaseSensitive -Pattern '\[workspaces\].*(E14d2 |bana|127\.0\.0\.1)').Count -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
if ($a.comment) { Write-Host "      your comment: $($a.comment)" -ForegroundColor Cyan }
Write-Host "`nLog: $log   File: $afile   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
