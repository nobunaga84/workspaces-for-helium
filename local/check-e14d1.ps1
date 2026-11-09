param([switch]$GradeOnly,
      [string]$OutDir = "Default",
      [string]$Tag = "e14d1")
# E14d.1, the closes no script drives (LOCAL.md 52): the tab menu's Close, a Today tab's X, "Close group" and its
# Ctrl+Shift+T (a saved group reopens from its own model -- the path the review found never left the archive), a
# pinned page's X, and the last window. Runs on a fresh throwaway copy of testprofile-e15b-smoke; testprofile is
# never touched. The script switches the window to Work and opens the five pages itself; the log and the archive
# file ("Workspace Archive") are graded here, what you saw is your y/n.
#
#   check-e14d1.ps1              one run, answer, grade
#   check-e14d1.ps1 -GradeOnly   grade the saved log, file and answers again
$ws      = "<local-path>\Helium-workspace"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof    = "$ws\testprofile-$Tag"
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\47-archive.patch"
$log     = "$ws\$Tag-run.log"
$answers = "$ws\$Tag-run-answers.json"
$afile   = "$prof\Default\Workspace Archive"
$pages   = "$ws\$Tag-pages"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }

function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running -- close it first (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
    # Against the newest SOURCE file patch 47 touches, not the patch file: a quilt refresh after the build
    # rewrites the patch from the same sources (LOCAL.md 52).
    $src = "$ws\helium-windows\build\src"
    $newest = @(Select-String -Path $patch -Pattern '^\+\+\+ b/(\S+)' | ForEach-Object { (Get-Item "$src\$($_.Matches[0].Groups[1].Value)").LastWriteTime } | Sort-Object)[-1]
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Write-Host "ABORT: $OutDir chrome.dll is older than a source file of patch 47 (stale binary)" -ForegroundColor Red; exit 1 }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'not archived: a pinned item')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 47" -ForegroundColor Red; exit 1 }
    if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    # An empty Recently Closed: the copy's own held a whole window, which a Ctrl+Shift+T before step 4 reopened
    # (the rehearsal, LOCAL.md 52) -- step 5 must reopen YOUR group and nothing else.
    Remove-Item "$prof\Default\Sessions\Tabs_*" -Force -EA SilentlyContinue
    & python "$here\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met (vertical layout, a non-default workspace, enabled)" -ForegroundColor Red; exit 1 }
    if (Test-Path -LiteralPath $afile) { Write-Host "ABORT: the copied profile already has an archive file" -ForegroundColor Red; exit 1 }
    foreach ($f in $log, $answers) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    $null = New-Item -ItemType Directory -Force $pages
    foreach ($n in "p1", "p2", "p3", "p4", "p5") {
        Set-Content -Encoding UTF8 -Path "$pages\$n.html" -Value "<!doctype html><title>E14d1 $n</title><h1>E14d1 $n</h1>"
    }
    $server = Start-Process -FilePath python -ArgumentList @("-m", "http.server", "$port", "--bind", "127.0.0.1", "--directory", $pages) -PassThru -WindowStyle Hidden
    Start-Sleep 2

    Start-Process -FilePath $exe -ArgumentList $flags | Out-Null
    Start-Sleep 8
    # Set-up done here, not described: the window switches to Work, then the five pages open in it.
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Name "Work" -Role 0x2B | Out-Null
    Start-Sleep 2
    Start-Process -FilePath $exe -ArgumentList (@("--user-data-dir=$prof") + @("p1", "p2", "p3", "p4", "p5" | ForEach-Object { Url $_ })) | Out-Null
    Start-Sleep 3

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window:
  RAIL          the row of workspace buttons at the bottom; "Work" should be highlighted (the script pressed it).
  TODAY TAB     an entry BELOW the thin line, e.g. "E14d1 p1".
  PINNED PAGE   an entry ABOVE the thin line, e.g. "Example A".
  GROUP HEADER  the coloured label a group of Today tabs sits under.
"@ -ForegroundColor Magenta
    Write-Host @"
 0. CHECK FIRST: "Work" is highlighted in the RAIL, and the Today tabs E14d1 p1 ... p5 are listed.
 1. RIGHT-click the Today tab "E14d1 p1" -> "Close".            EXPECT: p1 is gone.
 2. Hover the Today tab "E14d1 p2" and click its X.              EXPECT: p2 is gone.
 3. LEFT-click "E14d1 p3", then Ctrl+LEFT-click "E14d1 p4" (both selected). RIGHT-click p4 ->
    "Add tabs to new group". A small panel opens: press Esc.     EXPECT: p3 and p4 sit under a GROUP HEADER.
 4. RIGHT-click that GROUP HEADER -> a panel whose list ends in "Close group", "Ungroup", "Delete group".
    Click "Close group" -- NOT "Delete group".                   EXPECT: the header, p3 and p4 are gone.
 5. Press Ctrl+Shift+T.                                          EXPECT: the group comes back with p3 and p4.
 6. LEFT-click the PINNED PAGE "Example A" (it opens), then click the X on its row.
                                                                 EXPECT: its row STAYS in the pinned section.
 7. Close the window with its X (top right).
"@ -ForegroundColor Yellow
    Write-Host "Nothing to press here while you test: this window waits for the browser to close." -ForegroundColor Cyan
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Stop-Process -Id $server.Id -EA SilentlyContinue
    Write-Host "Browser closed." -ForegroundColor Green
}

# ---- your answers ----------------------------------------------------------------------------
$questions = [ordered]@{
    setup  = "0. Work highlighted, p1 ... p5 listed (y/n)"
    group  = "4. 'Close group' took the header, p3 and p4 away (y/n)"
    reopen = "5. Ctrl+Shift+T brought the group back with p3 and p4 (y/n)"
    pinned = "6. the pinned page's row stayed in the pinned section (y/n)"
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
function N([string]$re) { @($lines | Select-String -Pattern $re).Count }
$e = if (Test-Path -LiteralPath $afile) { @((Get-Content -Raw -LiteralPath $afile | ConvertFrom-Json).entries) } else { @() }
Write-Host ("      file: " + (($e | ForEach-Object { "$($_.reason) $($_.url)" }) -join ' | '))
Verdict "steps 1-4: four 'archived a manual close' in Work (p1, p2, then p3 and p4 by Close group)" ((N "archived a manual close in '$work'") -eq 4)
Verdict "nothing refused" ((N "archived a .*\(refused\)") -eq 0)
Verdict "step 5: two 'a reopened close leaves the archive' -- the saved group's pages left the archive" ((N "a reopened close leaves the archive") -eq 2)
Verdict "step 7: the last window archived nothing ('the session keeps the last window's tabs')" ((N "not archived: the session keeps the last window's tabs") -ge 1 -and (N "archived a window close") -eq 0)
Verdict "the file: exactly p1 and p2, manual, Work -- not p3/p4 (reopened), not the pinned page" ($e.Count -eq 2 -and @($e | Where-Object { $_.reason -eq 'manual' -and $_.workspace -eq $work }).Count -eq 2 -and @($e.url) -contains (Url "p1") -and @($e.url) -contains (Url "p2"))
$markers = ($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling' | Measure-Object).Count
Verdict "0 crash markers in the log" ($markers -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($a.$k -eq 'y') }
Write-Host "`nLog: $log   File: $afile   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
