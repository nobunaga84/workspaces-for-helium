# historical (pre-E17): E17a moved Archive to the bar's own button, E17c moved Clear... into the search row's menu and renamed the empty text; check-e14d3-auto.ps1 is the current test.
param([switch]$GradeOnly,
      [string]$OutDir = "Default",
      [string]$Tag = "e14d3")
# E14d.3, the auto-archive by hand (design 5, "Auto-archive (E14d.3)"). The log lines graded here are the contract
# in workspace_service.h (UpdateAutoArchiveTimer, SweepForAutoArchive, ArchiveClosingTab) and the Archive screen's
# in workspace_archive_view.cc. Runs on a fresh throwaway copy of testprofile-e15b-smoke; testprofile is never
# touched. Before the launch the script writes helium.workspaces.archive_after_minutes = 2 into the copy's
# Preferences (the timer then sweeps every 60 s: half the setting) and seeds two old archive entries, 5 hours and
# 3 days old (make-archive-fixture.py), for the Clear ranges. It opens the test pages itself from a local server
# (no MSAA): E14d3 one and E14d3 two once the window is on Work, E14d3 form at step 3. The steps come one at a
# time, each answered y/n here. The log, the archive file ("Workspace Archive", read after each answer) and the
# server's request log are graded; what you saw is your y/n. What each graded row proves:
#   start      the first auto-archive line is the 2-minute timer's
#   step 1     E14d3 two, left alone, archived by the timer (auto, Work); E14d3 one, the tab you are on, not
#   step 2     restored from the Archive into Work, fetched again, and out of the file
#   step 3     a sweep after the pinned page and the typed-into page were due keeps both ('pinned item',
#              'unsaved work'); E14d3 one, left at the restore, is the only page of this test archived
#   step 4     Never stops the timer ('auto-archive: off'): no sweep and no auto close after it
#   steps 5-7  Clear...: Last hour takes this test's entries (the count right) and is then greyed out; Last 7
#              days asks about the two old entries and Cancel keeps them; All time empties the file
#   step 8     the last window's close archives nothing; 0 crash markers; no title, address or typed text in a
#              [workspaces] line (47's rule)
# Run it in its own process, one line:
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-e14d3.ps1 -OutDir Dcheck
#   (PowerShell 7.6.6, the owner's; rehearsed so. Without -OutDir it runs out\Default. Add -GradeOnly to grade
#   the saved log, files and answers again)
$ws      = "<local-path>\Helium-workspace"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$prof    = "$ws\testprofile-$Tag"
$src     = "$ws\helium-windows\build\src"
$bin     = "$src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$patch   = "$ws\helium-windows\patches\local\workspaces\49-auto-archive.patch"
$log     = "$ws\$Tag-run.log"
$answers = "$ws\$Tag-run-answers.json"
$afile   = "$prof\Default\Workspace Archive"
$prefs   = "$prof\Default\Preferences"
$pages   = "$ws\$Tag-pages"
$srvlog  = "$ws\$Tag-requests.log"
# Asked of Windows, not fixed: on 2026-10-13 Windows reserved 8702-8801 (netsh excludedportrange; WinError 10013
# on bind), the way Logi Options+ took 8765 at R5 (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
# Typed into the form page: it must never reach a log (47's rule).
$token   = "zqxdraft"
# The screen's "Clear" button ends in U+2026; built here so this file stays ASCII.
$clear   = "Clear$([char]0x2026)"
$flags   = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--restore-last-session", "--log-file=`"$log`"")
# The contract's log lines.
$timer2    = "\[workspaces\] auto-archive: after 2 min, sweeping every 60 s"
$off       = "\[workspaces\] auto-archive: off"
$sweepAny  = "\[workspaces\] auto-archive sweep"
$sweep     = "\[workspaces\] auto-archive sweep: \d+ tab\(s\), \d+ due, \d+ archived"
$autoWork  = "\[workspaces\] archived a auto close in '$work'"
$autoAny   = "\[workspaces\] archived a auto close in '"
$archived  = "\[workspaces\] archived a "
$refused   = "\[workspaces\] archived a .*\(refused\)"
$restored  = "\[workspaces\] archive: restored an entry into '$work'"
$asked     = "\[workspaces\] archive screen: clear asked, ([a-z0-9 ]+) \((\d+)\)"
$cancelled = "\[workspaces\] archive screen: clear cancelled"
$cleared   = "\[workspaces\] archive: cleared (\d+) entr\(ies\)"
$lastWin   = "\[workspaces\] not archived: the session keeps the last window's tabs"
$questions = [ordered]@{
    s1 = "1. E14d3 two left the Today tabs by itself; E14d3 one, the tab you were on, stayed (y/n)"
    s2 = "2. the Archive listed E14d3 two first under Today; clicking it brought it back as the first Today tab, its page showing (y/n)"
    s3 = "3. after the wait E14d3 form is still a Today tab, and the pinned page Example A is still open (its X shows) (y/n)"
    s4 = "4. 'Archive tabs after' sat under the Workspaces switch showing Custom; its list offered Never, 1 day, 7 days, 30 days; it now shows Never (y/n)"
    s5 = "5. $clear listed Last hour, Last 24 hours, Last 7 days, All time; after Last hour > Delete, the next $clear showed Last hour greyed out, the other three not (y/n)"
    s6 = "6. Last 7 days asked to delete 2 archived tabs; Cancel left both Fixture page entries listed (y/n)"
    s7 = "7. All time asked about 2; Delete left 'No archived tabs' (y/n)"
}
function Url([string]$n) { "http://127.0.0.1:$port/$n.html" }
function BrowserPids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Fail([string]$why) { Write-Host "ABORT: $why" -ForegroundColor Red; exit 1 }
function WaitLog([string]$re, [int]$s) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $log) -and (Select-String -Path $log -Pattern $re -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function Quit([string]$why) {
    foreach ($id in BrowserPids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }
    Stop-Process -Id $server.Id -EA SilentlyContinue
    Fail "$why -- the browser was closed; run the script again"
}
# A line matching `re` in the log after line `after`.
function Seen([string]$re, [int]$after) { (Test-Path $log) -and @(Select-String -Path $log -Pattern $re | Where-Object { $_.LineNumber -gt $after }).Count -gt 0 }
function LogCount { if (Test-Path $log) { @(Get-Content $log).Count } else { 0 } }
# Up to `s` seconds until `re` shows in the log after line `after` (none: the whole time), the time told every 30 s.
function WaitSeen([string]$re, [int]$after, [int]$s) {
    $t = Get-Date; $next = 30
    while (($el = ((Get-Date) - $t).TotalSeconds) -lt $s) {
        if ($re -and (Seen $re $after)) { return $true }
        if (-not (BrowserPids).Count) { return $false }
        if ($el -ge $next) { Write-Host "      ... $next s" -ForegroundColor DarkGray; $next += 30 }
        Start-Sleep 2
    }
    return $false
}
# The page `n` requested from the test server (its request log, one line a request), polled.
function Served([string]$n, [int]$s = 30) {
    $t = Get-Date
    while (((Get-Date) - $t).TotalSeconds -lt $s) { if ((Test-Path $srvlog) -and (Select-String -Path $srvlog -Pattern "GET /$n.html " -SimpleMatch -Quiet)) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
# The archive file's text, read past its 2.5 s write delay; "" when there is none.
function Raw {
    Start-Sleep 5
    foreach ($i in 1..3) { try { return [IO.File]::ReadAllText($afile, [Text.Encoding]::UTF8) } catch { Start-Sleep 1 } }
    return ""
}
function Save { $F | ConvertTo-Json -Depth 6 | Set-Content $answers -Encoding utf8 }
# The y/n for step `k`, then the log's length and the archive file at that moment, all saved at once.
function Ask([string]$k) {
    do { $r = "$(Read-Host $questions[$k])".Trim().ToLower() } while ($r -notin @('y', 'n'))
    $F.answers[$k] = $r
    $F.marks[$k] = LogCount
    $F.times[$k] = (Get-Date).ToString("o")
    Write-Host "      (reading the archive file)" -ForegroundColor DarkGray
    $F.files[$k] = Raw
    Save
}
function Step([string]$text) { Write-Host $text -ForegroundColor Yellow }
# The browser, its stdout and stderr in files of their own: with --enable-logging, Chrome attaches to the console
# that started it and always prints ERROR lines there (base::RouteStdioToConsole), which landed in the middle of
# the steps in the owner's first run. Handles already redirected are left alone, so nothing reaches this window.
function Browser([string[]]$argv, [string]$what) {
    Start-Process -FilePath $exe -ArgumentList $argv -RedirectStandardOutput "$ws\$Tag-chrome-$what-out.txt" -RedirectStandardError "$ws\$Tag-chrome-$what-err.txt" | Out-Null
}

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Fail "a fork browser is already running -- close it first (forwarded-launch trap)." }
    # Against the newest SOURCE of patch 49 that goes into chrome.dll, not the patch file: a quilt refresh after the
    # build rewrites the patch from the same sources (LOCAL.md 52). check-e14d3-auto.ps1's list.
    $sources = @("chrome\browser\ui\browser_tab_strip_model_delegate.cc", "chrome\browser\ui\tabs\workspaces\BUILD.gn",
                 "chrome\browser\ui\tabs\workspaces\workspace_archive.h", "chrome\browser\ui\tabs\workspaces\workspace_archive.cc",
                 "chrome\browser\ui\tabs\workspaces\workspace_prefs.h", "chrome\browser\ui\tabs\workspaces\workspace_prefs.cc",
                 "chrome\browser\ui\tabs\workspaces\workspace_service.h", "chrome\browser\ui\tabs\workspaces\workspace_service.cc",
                 "chrome\browser\ui\tabs\workspaces\workspace_tab_data.h", "chrome\browser\ui\tabs\workspaces\workspace_tab_data.cc",
                 "chrome\browser\ui\views\tabs\vertical\BUILD.gn", "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.h",
                 "chrome\browser\ui\views\tabs\vertical\workspace_archive_view.cc", "chrome\browser\ui\views\tabs\vertical\workspace_arc_importer.cc",
                 "chrome\browser\extensions\api\settings_private\prefs_util.cc", "chrome\browser\ui\webui\settings\settings_localized_strings_provider.cc")
    if (Test-Path $patch) { $sources += @(Select-String -Path $patch -Pattern '^\+\+\+ b/(\S+\.(cc|h|gn))$' | ForEach-Object { $_.Matches[0].Groups[1].Value }) }
    $missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
    if ($missing.Count) { Fail "missing source(s) of patch 49: $($missing -join ', ')" }
    $newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Fail "$OutDir chrome.dll is older than a source file of patch 49 (stale binary)" }
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'auto-archive: ')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Fail "$OutDir\chrome.dll does not contain patch 49 ('auto-archive: ')" }
    if (Test-Path $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    # An empty Recently Closed: the copy's own held a whole window (LOCAL.md 52).
    Remove-Item "$prof\Default\Sessions\Tabs_*" -Force -EA SilentlyContinue
    & python "$here\set-workspaces-pref.py" $prof --show | Select-Object -Last 2
    if ($LASTEXITCODE -ne 0) { Fail "preconditions not met (vertical layout, a non-default workspace, enabled)" }
    if (Test-Path -LiteralPath $afile) { Fail "the copied profile already has an archive file" }
    # The test's 2 minutes, written before the launch (profile_write.py, as check-e14d3-auto.ps1's setpref.py), and
    # read back: the last line (the first write prints "backup written: ..." before it).
    $setpref = "import json,pathlib,sys; sys.path.insert(0, sys.argv[3]); from profile_write import write_json_atomically; p = pathlib.Path(sys.argv[1]); d = json.loads(p.read_text(encoding='utf-8')); d.setdefault('helium', {}).setdefault('workspaces', {})['archive_after_minutes'] = int(sys.argv[2]); write_json_atomically([(p, d)], '.e14d3'); print(json.loads(p.read_text(encoding='utf-8'))['helium']['workspaces']['archive_after_minutes'])"
    $v = "$(@(& python -c $setpref $prefs 2 $here)[-1])".Trim()
    if ($v -ne "2") { Fail "archive_after_minutes is not 2 in the copy's Preferences (read back: '$v')" }
    # Two old entries in Work (fixture-0001 5 h, fixture-0002 3 days old), so Last hour holds only this run's closes.
    # The ages one quoted string: bare, Windows PowerShell reads 3d as the decimal 3.
    & python "$here\make-archive-fixture.py" $prof --ages "5h,3d" --merge | ForEach-Object { "      $_" }
    if ($LASTEXITCODE -ne 0) { Fail "make-archive-fixture.py --ages 5h,3d --merge failed" }
    foreach ($f in $log, $answers, $srvlog) { if (Test-Path $f) { Move-Item $f "$f.prev" -Force } }

    # The pages, and a server that answers no-store (a restore fetches the page again) and writes one line per
    # request to its own log, the file closed after each.
    $null = New-Item -ItemType Directory -Force $pages
    $body = @{ one = ""; two = ""; form = "<form><input aria-label=notes style='position:fixed;left:0;top:0;width:100%;height:100%;font-size:40px'></form>" }
    foreach ($k in $body.Keys) { Set-Content -Encoding UTF8 -Path "$pages\$k.html" -Value "<!doctype html><title>E14d3 $k</title><h1>E14d3 $k</h1>$($body[$k])" }
    Set-Content "$pages\serve.py" -Encoding ascii @'
import functools, http.server, sys
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, fmt, *args):
        with open(sys.argv[3], "a", encoding="utf-8") as f:
            f.write(self.requestline + "\n")
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), functools.partial(H, directory=sys.argv[2])).serve_forever()
'@
    $server = Start-Process -FilePath python -ArgumentList @("-u", "$pages\serve.py", "$port", $pages, $srvlog) -PassThru -WindowStyle Hidden
    Start-Sleep 2
    # This folder's page, not merely a 200: a server left on the port by another check serves another folder.
    $probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 (Url "one")).Content } catch { "" }
    if ($probe -notmatch 'E14d3 one') { Stop-Process -Id $server.Id -EA SilentlyContinue; Fail "the test pages are not served on port $port" }
    Start-Sleep 1
    Remove-Item -LiteralPath $srvlog -EA SilentlyContinue

    $F = [ordered]@{ binary = "$OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime.ToString('o'))"; answers = [ordered]@{}; marks = [ordered]@{}; times = [ordered]@{}; files = [ordered]@{}; comment = "" }
    Browser $flags "start"
    if (-not (WaitLog "pins: drew \d+ row\(s\) of '" 30)) { Quit "the browser did not draw its sidebar" }

    Write-Host @"

WORDS USED BELOW -- look at the left side of the window, the SIDEBAR:
  THE RAIL      the row of workspace buttons at the bottom of the sidebar; the one you are in is highlighted.
  + BUTTON      the "+" at the end of THE RAIL.
  TODAY TAB     a normal tab, listed BELOW the thin line in the sidebar, e.g. "E14d3 one".
  PINNED PAGE   an item of the pinned section ABOVE the thin line, opened, e.g. "Example A". An open one shows an
                X at its right end; a closed one shows none.
  THE ARCHIVE   what the + BUTTON's "Archive" opens: a search box, then the tabs closed, newest first, under a
                heading per day ("Today"), and "$clear" at the bottom. It closes when you click outside it.
  ENTRY         one closed page listed in THE ARCHIVE.
The test setting is 2 minutes: a tab you have not looked at for 2 minutes goes to THE ARCHIVE by itself.
Answer each question HERE, in this window: y or n, then Enter.
"@ -ForegroundColor Magenta

    # ---- step 1 ----------------------------------------------------------------------------------
    Step @"

 1. Click "Work" in THE RAIL (hover a button to see its name; click it even if it is already highlighted).
    The script then opens two TODAY TABS in Work by itself: "E14d3 one" and "E14d3 two".
"@
    if (-not (WaitLog "pins: drew \d+ row\(s\) of '$work'" 300)) { Quit "the window did not go to Work within 5 minutes" }
    Browser @("--user-data-dir=$prof", (Url "one"), (Url "two")) "open-one-two"
    if (-not ((Served "one") -and (Served "two"))) { Quit "E14d3 one and E14d3 two did not both load" }
    Start-Sleep 2
    $F.marks['m0'] = LogCount
    Step @"
    Done: they are open. FROM Work: click the TODAY TAB "E14d3 one" (its page shows the big heading "E14d3 one").
    Do NOT click "E14d3 two". Then come back to THIS window and press Enter.
"@
    $null = Read-Host "Press Enter once you are on E14d3 one"
    Write-Host "    Hands off the browser now. 'E14d3 two' should leave the list by itself within about 3 minutes; this window says when to look." -ForegroundColor Cyan
    $null = WaitSeen $autoWork $F.marks.m0 300
    Start-Sleep 3
    Step @"
    LOOK NOW at the sidebar.                     EXPECT: "E14d3 two" has left the TODAY TABS by itself;
                                                 "E14d3 one", the tab you are on, is still there.
"@
    Ask "s1"

    # ---- step 2 ----------------------------------------------------------------------------------
    Step @"

 2. FROM Work: click the + BUTTON -> "Archive".  EXPECT: THE ARCHIVE opens; the first ENTRY under "Today" is
                                                 "E14d3 two". (The two "Fixture page" ENTRIES further down are
                                                 the script's, 5 hours and 3 days old.)
    Click the ENTRY "E14d3 two".                 EXPECT: THE ARCHIVE closes; "E14d3 two" is back as the FIRST
                                                 TODAY TAB and shows its page (the big heading "E14d3 two").
"@
    Ask "s2"

    # ---- step 3 ----------------------------------------------------------------------------------
    Browser @("--user-data-dir=$prof", (Url "form")) "open-form"
    if (-not (Served "form")) { Quit "E14d3 form did not load" }
    Step @"

 3. The script has just opened a third TODAY TAB in Work, "E14d3 form": its page is one big white box.
    a) Click anywhere in that big box, type  $token  and press the Tab key once.
    b) Click the PINNED PAGE "Example A" in the pinned section, ABOVE the thin line: it opens.
    c) Click the TODAY TAB "E14d3 two".
    Then come back to THIS window and press Enter.
"@
    $null = Read-Host "Press Enter once you are on E14d3 two"
    Write-Host "    Hands off the browser for about 3 minutes: the pinned page and E14d3 form are old enough to go in 2, but neither may. ('E14d3 one' may leave the list meanwhile: right -- you left it when E14d3 two came back.)" -ForegroundColor Cyan
    # Both were left before the Enter, so every sweep logged after this mark judged them due -- and kept them.
    $null = WaitSeen "" 0 122
    $F.marks['s3due'] = LogCount
    $null = WaitSeen $sweep $F.marks.s3due 150
    Start-Sleep 2
    Step @"
    LOOK NOW at the sidebar.                     EXPECT: "E14d3 form" is still a TODAY TAB, and the PINNED PAGE
                                                 "Example A" is still open (the X at its right end).
"@
    Ask "s3"

    # ---- step 4 ----------------------------------------------------------------------------------
    Step @"

 4. FROM Work: press Ctrl+T (a new TODAY TAB opens at the top), type  chrome://settings/appearance  and press
    Enter. Find "Archive tabs after", just under the "Workspaces" switch.
                                                 EXPECT: it shows "Custom" (the test's 2 minutes).
    Click it.                                    EXPECT: its list offers Never, 1 day, 7 days and 30 days
                                                 (and Custom).
    Choose "Never".                              EXPECT: it now shows "Never".
"@
    Ask "s4"

    # ---- steps 5-7 -------------------------------------------------------------------------------
    Step @"

 5. FROM Work: click the + BUTTON -> "Archive", then "$clear" at the bottom of THE ARCHIVE.
                                                 EXPECT: a list: Last hour, Last 24 hours, Last 7 days, All time.
    Click "Last hour".                           EXPECT: it asks to delete the tabs archived in this test
                                                 ("Delete 1 archived tab from the last hour..." or 2).
    Click "Delete".                              EXPECT: those ENTRIES go; the two "Fixture page" ENTRIES stay.
    Click "$clear" again.                        EXPECT: "Last hour" is greyed out now (nothing is left in it);
                                                 the other three are not. Press Esc to close that list.
"@
    Ask "s5"
    Step @"

 6. FROM Work, THE ARCHIVE again (+ BUTTON -> "Archive" if it closed): "$clear" -> "Last 7 days".
                                                 EXPECT: it asks "Delete 2 archived tabs from the last 7 days,
                                                 from every workspace?"
    Click "Cancel".                              EXPECT: both "Fixture page" ENTRIES are still listed.
"@
    Ask "s6"
    Step @"

 7. STILL on THE ARCHIVE (open it again if it closed): "$clear" -> "All time".
                                                 EXPECT: it asks "Delete 2 archived tabs, from every workspace?"
    Click "Delete".                              EXPECT: THE ARCHIVE says "No archived tabs".
"@
    Ask "s7"

    # ---- step 8 ----------------------------------------------------------------------------------
    Step @"

 8. Close the window with its X (top right).
"@
    Write-Host "Nothing to press here: this window waits for the browser to close." -ForegroundColor Cyan
    while ((BrowserPids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Stop-Process -Id $server.Id -EA SilentlyContinue
    Write-Host "Browser closed." -ForegroundColor Green
    $F['comment'] = "$(Read-Host "Anything that looked wrong or odd? (Enter for nothing)")".Trim()
    Save
}

# ---- grading (also -GradeOnly) -----------------------------------------------------------------
if (-not (Test-Path $answers)) { Fail "no $answers -- run without -GradeOnly first" }
$F = Get-Content -Raw -Encoding UTF8 $answers | ConvertFrom-Json
if (-not (Test-Path $log) -or (Get-Item $log).Length -eq 0) { Fail "$log missing or EMPTY -- nothing to grade" }
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$lines = @(Get-Content $log)
# The log's length after step `k`'s answer (a missing mark: past the end, so a range from it is empty).
function M([string]$k) { if ($null -ne $F.marks.$k) { [int]$F.marks.$k } else { [int]::MaxValue } }
# The log lines matching `re` after line `a`, up to line `b`.
function In([string]$re, [int]$a, [int]$b = [int]::MaxValue) { @($lines | Select-String -Pattern $re | Where-Object { $_.LineNumber -gt $a -and $_.LineNumber -le $b }) }
function Entries([string]$json) { if (-not $json) { return @() }; try { @(($json | ConvertFrom-Json).entries) } catch { @() } }
# This run's entries: not the fixture's.
function Own($es) { @($es | Where-Object { $_.id -notlike 'fixture-*' }) }
function Ids([string]$json) { (@(Entries $json | ForEach-Object { $_.id } | Sort-Object) -join ',') }
# An entry's archived_at (base::Time: microseconds since 1601 UTC, a string) as local time; a FILETIME is 100 ns.
function At($e) { [DateTime]::FromFileTimeUtc([long]$e.archived_at * 10).ToLocalTime() }
function T($s) { if ($s -is [datetime]) { $s } elseif ($s) { [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } }
# N of the one 'clear asked, <range> (N)' among `hits`, else -1; N of the one 'cleared N entr(ies)', else -1. A
# function's array comes back unrolled (one match: a bare MatchInfo), hence @().
function AskedN($hits, [string]$range) { $h = @($hits); if ($h.Count -eq 1 -and $h[0].Line -match $asked -and $Matches[1] -eq $range) { [int]$Matches[2] } else { -1 } }
function ClearedN($hits) { $h = @($hits); if ($h.Count -eq 1 -and $h[0].Line -match $cleared) { [int]$Matches[1] } else { -1 } }
Write-Host "      binary: $($F.binary)"

$first = @($lines | Select-String -Pattern "\[workspaces\] auto-archive(:| sweep)") | Select-Object -First 1
Verdict "start: the first auto-archive line is the timer's, 'after 2 min, sweeping every 60 s'" ($first -and $first.Line -match $timer2)

$e1 = Entries $F.files.s1
$two1 = @($e1 | Where-Object { $_.url -eq (Url "two") })
Verdict "step 1: an 'archived a auto close' in Work while you waited ($(@(In $autoWork (M m0) (M s1)).Count))" (@(In $autoWork (M m0) (M s1)).Count -ge 1)
Verdict "step 1: the file then holds E14d3 two once, auto, Work, and no other page of this test (E14d3 one not archived)" ($two1.Count -eq 1 -and $two1[0].reason -eq 'auto' -and $two1[0].workspace -eq $work -and @(Own $e1).Count -eq 1)
Verdict "nothing refused" (@(In $refused 0).Count -eq 0)

$gets = if (Test-Path $srvlog) { @(Select-String -Path $srvlog -Pattern "GET /two.html " -SimpleMatch).Count } else { 0 }
Verdict "step 2: the Archive opened and one 'archive: restored an entry into' Work" (@(In "\[workspaces\] archive screen: opened" (M s1) (M s2)).Count -ge 1 -and @(In $restored (M s1) (M s2)).Count -eq 1)
Verdict "step 2: the file then holds no E14d3 two" ($F.files.s2 -and @(Entries $F.files.s2 | Where-Object { $_.url -eq (Url "two") }).Count -eq 0)
Verdict "step 2: two.html fetched again by the restore ($gets requests, 2 or more)" ($gets -ge 2)

$sw = @(In $sweep (M s3due) (M s3))
$sw | ForEach-Object { Write-Host ("      log: " + ($_.Line -replace '^.*?\] \[workspaces\] ', '')) }
Verdict "step 3: the pinned page opened ('pins: opened item')" (@(In "\[workspaces\] pins: opened item '" (M s2) (M s3due)).Count -ge 1)
Verdict "step 3: $($sw.Count) sweep(s) after both were due, each keeping 'pinned item' and 'unsaved work'" ($sw.Count -ge 1 -and @($sw | Where-Object { $_.Line -notmatch 'kept: .*\bpinned item \d+' -or $_.Line -notmatch 'kept: .*\bunsaved work \d+' }).Count -eq 0)
$o3 = @(Own (Entries $F.files.s3))
Verdict "step 3: the file then holds E14d3 one (auto, Work) and no other page of this test -- not E14d3 form, E14d3 two or the pinned page" ($o3.Count -eq 1 -and $o3[0].url -eq (Url "one") -and $o3[0].reason -eq 'auto' -and $o3[0].workspace -eq $work)

$offL = @(In $off 0)
$offAt = if ($offL.Count -eq 1) { $offL[0].LineNumber } else { [int]::MaxValue }
Verdict "step 4: exactly one 'auto-archive: off' ($($offL.Count)), logged during step 4" ($offL.Count -eq 1 -and $offAt -gt (M s3) -and $offAt -le (M s4))
Verdict "step 4: after it no sweep ($(@(In $sweepAny $offAt).Count)) and no 'archived a auto close' ($(@(In $autoAny $offAt).Count))" ($offL.Count -eq 1 -and @(In $sweepAny $offAt).Count -eq 0 -and @(In $autoAny $offAt).Count -eq 0)

$n1 = @(Own (Entries $F.files.s4)).Count
$k5 = AskedN (In $asked (M s4) (M s5)) "last hour"
$d5 = ClearedN (In $cleared (M s4) (M s5))
Verdict "step 5: 'clear asked, last hour ($k5)' -- this test's entries in the file then: $n1" ($n1 -ge 1 -and $k5 -eq $n1)
Verdict "step 5: 'archive: cleared $d5 entr(ies)', the same $n1" ($n1 -ge 1 -and $d5 -eq $n1)
$ids5 = Ids $F.files.s5
Verdict "step 5: the file then holds only the script's two old entries ('$ids5')" ($ids5 -eq 'fixture-0001,fixture-0002')

$since = if ($F.times.s5) { (T $F.times.s5).AddDays(-7) } else { [datetime]::MaxValue }
$n2 = @(Entries $F.files.s5 | Where-Object { (At $_) -ge $since }).Count
$k6 = AskedN (In $asked (M s5) (M s6)) "last 7 days"
Verdict "step 6: 'clear asked, last 7 days ($k6)' -- the file's entries of the last 7 days then: $n2" ($n2 -ge 1 -and $k6 -eq $n2)
Verdict "step 6: 'clear cancelled', nothing cleared, the file unchanged" (@(In $cancelled (M s5) (M s6)).Count -eq 1 -and @(In $cleared (M s5) (M s6)).Count -eq 0 -and $F.files.s6 -and (Ids $F.files.s6) -eq $ids5)

$n3 = @(Entries $F.files.s6).Count
$k7 = AskedN (In $asked (M s6) (M s7)) "all time"
$d7 = ClearedN (In $cleared (M s6) (M s7))
Verdict "step 7: 'clear asked, all time ($k7)' and 'cleared $d7 entr(ies)' -- the file's entries then: $n3" ($n3 -ge 1 -and $k7 -eq $n3 -and $d7 -eq $n3)
Verdict "step 7: the file then holds 0 entries" ($F.files.s7 -and @(Entries $F.files.s7).Count -eq 0)

$final = if (Test-Path -LiteralPath $afile) { [IO.File]::ReadAllText($afile, [Text.Encoding]::UTF8) } else { "" }
Verdict "step 8: the last window archived nothing ('the session keeps the last window's tabs'; no 'archived a' line after step 7)" (@(In $lastWin (M s7)).Count -ge 1 -and @(In $archived (M s7)).Count -eq 0)
Verdict "step 8: the file after the close: there, 0 entries" ($final -and @(Entries $final).Count -eq 0)

$markers = @($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count
Verdict "0 crash markers in the log ($markers)" ($markers -eq 0)
# 21's 'anchor at index N -> <address>' line is older than 47's rule: left out, and counted.
$hits = @($lines | Select-String -CaseSensitive -Pattern ('\[workspaces\].*(E14d3 |127\.0\.0\.1|' + $token + '|Fixture page|example\.com)') | ForEach-Object { $_.Line })
$old = @($hits | Where-Object { $_ -match "\[workspaces\] anchor at index \d+ -> '" })
$leak = @($hits | Where-Object { $_ -notmatch "\[workspaces\] anchor at index \d+ -> '" })
Write-Host "      $($old.Count) 'anchor at index N -> <address>' line(s) left out (21's own, older than 47's rule)"
Verdict "no [workspaces] line holds a page's title or address, or what you typed ($($leak.Count))" ($leak.Count -eq 0)
foreach ($k in $questions.Keys) { Verdict $questions[$k] ($F.answers.$k -eq 'y') }
if ($F.comment) { Write-Host "      your comment: $($F.comment)" -ForegroundColor Cyan }
Write-Host "`nLog: $log   File: $afile   Answers: $answers. Send the PASS/FAIL lines above." -ForegroundColor Cyan
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 } else { Write-Host "ALL PASS" -ForegroundColor Green }
