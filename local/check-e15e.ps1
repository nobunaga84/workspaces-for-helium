param([switch]$GradeOnly,
      [string]$OutDir = "Default",
      [string]$Tag = "e15e")
# E15e: a new window opens on the workspace of the window you were in, not on Home (design 1, LOCAL.md 50).
# Runs on the throwaway copy check-e15d3.ps1 made (testprofile-e15d3); testprofile is never touched. The log
# says which workspace each window opened on ("a window opens on workspace '<guid>'"); what you saw is your y/n.
#
#   check-e15e.ps1              one run, answer, grade
#   check-e15e.ps1 -GradeOnly   grade the saved log and answers again
$ws      = "<local-path>\Helium-workspace"
$prof    = "$ws\testprofile-e15d3"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\46-new-window-workspace.patch"
$log     = "$ws\$Tag-run.log"
$answers = "$ws\$Tag-run-answers.json"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt (Get-Item $patch).LastWriteTime) { Write-Host "ABORT: $OutDir chrome.dll is older than patch 46 (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'a window opens on workspace')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 46" -ForegroundColor Red; exit 1 }
    if (-not (Test-Path "$prof\Default\Preferences")) { Write-Host "ABORT: $prof is missing -- run check-e15d3.ps1 once to make the copy" -ForegroundColor Red; exit 1 }
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    foreach ($f in $log, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window:
  RAIL         the row of workspace buttons at the bottom; the one you are in is highlighted.
  PINNED PAGE  an entry ABOVE the thin line: a page name with a small icon.
"@ -ForegroundColor Magenta
    Write-Host @"
 1. In the window that opens, LEFT-click "Work" in the RAIL.
 2. Press Ctrl+N.
            EXPECT: a NEW window opens on Work -- "Work" is highlighted in ITS rail, and it shows Work's
            PINNED PAGES (not Home's).
 3. In that new window, LEFT-click "Home" in its RAIL, then press Ctrl+N again.
            EXPECT: the newest window opens on Home -- "Home" highlighted in its rail.
 4. Close all three windows (each one's X, top right), the first one last.
"@ -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 5
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = [ordered]@{
    work = "2. the new window opened on Work: Work highlighted in its rail, Work's pinned pages (y/n)"
    home = "3. the newest window opened on Home (y/n)"
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
$lines  = @(Get-Content $log)
# One line per window, in the order they opened: the first (at startup), then step 2's, then step 3's.
$opened = @($lines | ForEach-Object { if ($_ -match "a window opens on workspace '([^']+)'") { $Matches[1] } })
Write-Host ("      windows opened on: " + (($opened | ForEach-Object { if ($_ -eq $work) { 'Work' } elseif ($_ -eq 'default') { 'Home' } else { $_ } }) -join ', '))
Verdict "3 windows opened ($($opened.Count) seen)"         ($opened.Count -eq 3)
Verdict "step 2's window opened on Work (log)"               ($opened.Count -ge 2 -and $opened[1] -eq $work)
Verdict "step 3's window opened on Home (log)"               ($opened.Count -ge 3 -and $opened[2] -eq 'default')
$markers = ($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLog: $log   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
