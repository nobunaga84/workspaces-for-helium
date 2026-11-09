param([switch]$GradeOnly, [string]$ProfileDir = "<local-path>\Helium-workspace\testprofile", [string]$Prefix = "r4")
# R4 CHECK (LOCAL.md 36): the two behaviours Helium 0.17.2 brought in, on top of check-smoke.ps1.
#  A. Back-to-opener is ON in 0.17.2: Back on a tab opened from a link CLOSES it, with no
#     Recently Closed entry. Patch 33 makes an ANCHORED tab refuse. Child A is the control
#     (it must close, or the test proves nothing); child B is anchored and must stay.
#  B. Lazy session restore: after a restart only the selected tab loads. A local server with
#     caching OFF logs every page fetch, so "Home's tabs were not fetched until Home was
#     clicked" is read from its log, not from how dim a favicon looks.
# Two launches against testprofile: run 1 fresh, run 2 with --restore-last-session.
$exe    = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
# -ProfileDir / -Prefix: R5 reran this on a fresh profile (testprofile now restores ~445 tabs) without
# overwriting R4's evidence logs (LOCAL.md 59).
$prof   = $ProfileDir
$pdir   = "<local-path>\Helium-workspace\helium\patches\local\workspaces"
$page   = "<local-path>\Helium-workspace\$Prefix-page"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$log1   = "<local-path>\Helium-workspace\$Prefix-check-run1.log"
$log2   = "<local-path>\Helium-workspace\$Prefix-check-run2.log"
$srvlog = "<local-path>\Helium-workspace\$Prefix-check-server.log"
$flags  = @("--user-data-dir=$prof","--enable-logging","--v=0", "--helium-workspaces-log-addresses","--no-first-run","--no-default-browser-check")
Write-Host "R4 CHECK: back-to-opener on anchors + lazy restore" -ForegroundColor Cyan

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
function Hms($s) { [int]($s -replace ':','') }   # "04:30:12" or "043012" -> 43012

if (-not $GradeOnly) {
  if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running - close it (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
  $newest = Get-ChildItem "$pdir\*.patch" | Sort-Object LastWriteTime | Select-Object -Last 1
  if ((Get-Item $exe).LastWriteTime -lt $newest.LastWriteTime) { Write-Host "ABORT: chrome.exe older than $($newest.Name)" -ForegroundColor Red; exit 1 }
  $ver = (Get-Item $exe.Replace('chrome.exe','chrome.dll')).VersionInfo.ProductVersion
  $want = (Get-Content <local-path>\Helium-workspace\helium\chromium_version.txt -TotalCount 1).Trim()   # the version the rebase pinned
  if ($ver -ne $want) { Write-Host "ABORT: chrome.dll is $ver, not $want" -ForegroundColor Red; exit 1 }
  & python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
  if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }

  New-Item -ItemType Directory -Force $page | Out-Null
  foreach ($p in @(@('childa','R4 CHILD A'), @('childb','R4 CHILD B'), @('home1','R4 HOME 1'), @('home2','R4 HOME 2'))) {
    Set-Content "$page\$($p[0]).html" -Encoding utf8 "<title>$($p[1])</title><h1>$($p[1])</h1>"
  }
  Set-Content "$page\opener.html" -Encoding utf8 '<title>R4 OPENER</title><h1>R4 OPENER</h1><p><a href="childa.html" target="_blank">child A (control)</a></p><p><a href="childb.html" target="_blank">child B (will be anchored)</a></p>'
  # http.server with caching off, so a restored tab that loads MUST fetch (and so be logged).
  Set-Content "$page\serve.py" -Encoding utf8 @'
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
'@
  Remove-Item $log1, $log2, $srvlog -EA SilentlyContinue
  $server = Start-Process -FilePath python -ArgumentList @("$page\serve.py", "$port", $page) -PassThru -WindowStyle Hidden -RedirectStandardError $srvlog
  Start-Sleep 2
  $probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$port/opener.html").Content } catch { "" }
  if ($probe -notmatch 'R4 OPENER' -or $server.HasExited) { Write-Host "ABORT: test page not served on port $port" -ForegroundColor Red; exit 1 }

  Write-Host @"

RUN 1 (fresh window). Every step says which workspace you are IN.
 0. [Home]  PINNED TABS FIRST: if small pinned tabs sit at the top of the strip, right-click each -> Remove from Favorites.
            (A fresh start reopens the last session's pins, and a pinned tab shows in EVERY workspace,
            so Work would not be empty and step 1 could not spawn anything. LOCAL.md 34.)
 1. [Home]  click WORK in the rail. EXPECT: ONE new tab appears at once (Work was empty).
            Then Ctrl+T, go to  http://127.0.0.1:$port/opener.html  ("R4 OPENER").
 2. [Work]  CTRL+CLICK "child A (control)". Click the new "R4 CHILD A" tab.
            Its Back arrow must be ACTIVE. Press Alt+Left.
            EXPECT: CHILD A CLOSES and you are back on R4 OPENER.   (if it does NOT close, say so - the test is void)
 3. [Work]  on R4 OPENER, CTRL+CLICK "child B (will be anchored)". Click the new "R4 CHILD B" tab.
            Right-click the tab -> Anchor -> Anchor to this page.
            Press Alt+Left. EXPECT: CHILD B STAYS. (The arrow may still LOOK active: anchoring does
            not refresh it.) Click R4 OPENER, click CHILD B again: now the Back arrow must be GREYED.
 4. [Work]  click HOME in the rail. Ctrl+T -> http://127.0.0.1:$port/home1.html , Ctrl+T -> http://127.0.0.1:$port/home2.html
            Then click the "R4 HOME 1" tab.
 5. [Home]  click WORK in the rail, click the "R4 CHILD B" tab. Close the browser window (X).
"@ -ForegroundColor Yellow
  Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=`"$log1`"")) -Wait
  Start-Sleep 3
  Write-Host @"

RUN 2 (restart with --restore-last-session). Do NOT click anything for 5 seconds.
 6. [Work]  the rail must come up on WORK, showing R4 CHILD B. Right-click CHILD B's tab -> Anchor:
            it must offer "Remove anchor" (still anchored). Wait 5 seconds.
 7. [Work]  click HOME in the rail ONCE. Whichever Home tab comes up, loads.
 8. [Home]  click the "R4 HOME 1" tab, then the "R4 HOME 2" tab. Close the browser window (X).
"@ -ForegroundColor Yellow
  Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=`"$log2`"", "--restore-last-session")) -Wait
  Start-Sleep 2
  $server.Kill()
}

# ---- grading ----
foreach ($l in @($log1, $log2)) { if (-not (Test-Path $l) -or (Get-Item $l).Length -eq 0) { Write-Host "FAIL: $l missing or EMPTY - nothing ran" -ForegroundColor Red; exit 1 } }
$w1 = @(Get-Content $log1 | Where-Object { $_ -match '\[workspaces\]' })
$w2 = @(Get-Content $log2 | Where-Object { $_ -match '\[workspaces\]' })
# Milliseconds since midnight from a log line's "/HHMMSS.mmm".
function Ms($line) { $m = [regex]::Match($line, '/(\d\d)(\d\d)(\d\d)\.(\d{3})'); (([int]$m.Groups[1].Value * 60 + [int]$m.Groups[2].Value) * 60 + [int]$m.Groups[3].Value) * 1000 + [int]$m.Groups[4].Value }
# First line matching $pattern AFTER $after (a line from the same array), or $null.
function NextLine($lines, $after, $pattern) { $lines | Select-Object -Skip ([array]::IndexOf($lines, $after) + 1) | Where-Object { $_ -match $pattern } | Select-Object -First 1 }
$fetch = Get-Content $srvlog | ForEach-Object {
  $m = [regex]::Match($_, '\[\d+/\w+/\d+ (\d\d:\d\d:\d\d)\] "GET /(\w+)\.html')
  if ($m.Success) { [pscustomobject]@{ t = Hms $m.Groups[1].Value; page = $m.Groups[2].Value } }
}
$run2start = Hms ([regex]::Match(($w2 | Select-Object -First 1), '/(\d{6})\.').Groups[1].Value)
$f2 = $fetch | Where-Object { $_.t -ge $run2start }
Write-Host "`n--- run 2 [workspaces] lines ---"; $w2 | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host "--- run 2 page fetches (HHMMSS page) ---"; $f2 | ForEach-Object { "  $($_.t) $($_.page)" }

# Step 1's spawn (E9f; the smoke test could not answer it with pinned tabs in the strip): the FIRST
# switch off Home, and the very next insert -- into that workspace, within a second of the switch.
$toWork = $w1 | Where-Object { $_ -match "active workspace -> '(?!default')" } | Select-Object -First 1
$spawn = if ($toWork) { NextLine $w1 $toWork 'tab inserted at index' } else { $null }
Verdict "run 1: entering empty Work spawned a tab within 1 s" ($spawn -and $spawn -notmatch "-> workspace 'default'" -and ((Ms $spawn) - (Ms $toWork)) -le 1000)
Verdict "run 1: child B was anchored (log)" (@($w1 | Where-Object { $_ -match 'anchor at index' }).Count -ge 1)
# The FIRST click on Home after the restore settled on Work -- a later Home click must not move the line.
$restored = $w2 | Where-Object { $_ -match "active workspace -> '(?!default')" } | Select-Object -First 1
$homeLine = if ($restored) { NextLine $w2 $restored "active workspace -> 'default'" } else { $w2 | Where-Object { $_ -match "active workspace -> 'default'" } | Select-Object -First 1 }
$tHome = if ($homeLine) { Hms ([regex]::Match($homeLine, '/(\d{6})\.').Groups[1].Value) } else { -1 }
Verdict "run 2: CHILD B (the selected tab) was fetched on restore" (@($f2 | Where-Object page -eq 'childb').Count -ge 1)
Verdict "run 2: the click on Home was logged" ($tHome -ge 0)
Verdict "run 2: NO Home page fetched before Home was clicked (lazy)" ($tHome -ge 0 -and -not ($f2 | Where-Object { $_.page -like 'home*' -and $_.t -lt $tHome }))
Verdict "run 2: a Home page fetched after the click (loads on activation)" (@($f2 | Where-Object { $_.page -like 'home*' -and $_.t -ge $tHome }).Count -ge 1)
Verdict "run 2: R4 OPENER (a background tab) never fetched" (-not ($f2 | Where-Object page -eq 'opener'))
Write-Host "`nOwner-observed: step 2 (control closed), step 3 (CHILD B stayed; Back greyed after re-selecting it), step 6 (rail on Work, CHILD B still anchored)."
