param()
# C4 (patches 80-81): the owner's own try. Opens the built browser (out\Default) on a FRESH copy of the smoke profile
# -- never the daily browser's profile -- twice: first as it starts by default for steps 1-6, then, after you close it,
# in ZEN MODE with the sidebar unpinned (as the daily browser runs) for step 7, the tabs of the first start restored.
# Seeded before the first start: the sidebar 280 wide (all five CHIPs drawn), the toolbar's own New Tab button off, and
# the pinned page "C4 pinned" at the end of Work. At step 0 the script opens the Today tabs itself through DevTools
# (--remote-debugging-port=0, this PC only); the pages are served on this PC only, on a port Windows gives, until the
# script ends. Each step is answered y/n here; the answers and the log's length at each answer go to
# c4-owner-answers.json, and the end grades the logs (c4-owner-run.log, -run2.log), the pins file and the order of the
# workspaces in Preferences, and prints a summary for Claude.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c4.ps1
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$bin     = "$ws\helium-windows\build\src\out\Default"
$exe     = "$bin\chrome.exe"
$prof    = "$ws\testprofile-c4-owner"
$log     = "$ws\c4-owner-run.log"
$log2    = "$ws\c4-owner-run2.log"
$answers = "$ws\c4-owner-answers.json"
$pages   = "$ws\c4-owner-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
foreach ($s in @("unit(s) to the top", "rail drop: over")) {
    & python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -ne 0) { Write-Host "This build has no C4 yet (no '$s' in out\Default\chrome.dll): tell Claude."; exit 1 }
}
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $log, $log2, $answers -EA SilentlyContinue
$names = @("c4pin", "c4c1", "c4c2", "c4alpha", "c4beta", "c4gamma", "c4delta", "c4epsilon", "c4zeta")
$srv = ServePages $pages $names
if (-not $srv.ok) { Write-Host "The test pages could not be served: tell Claude."; exit 1 }
$base = "http://127.0.0.1:$($srv.port)"
# A page's title is "C4 <name>": "C4 alpha", "C4 c1" shown as "C4 canary one" (below).
$titles = @{ c4pin = "C4 pinned"; c4c1 = "C4 canary one"; c4c2 = "C4 canary two"; c4alpha = "C4 alpha"; c4beta = "C4 beta"; c4gamma = "C4 gamma"; c4delta = "C4 delta"; c4epsilon = "C4 epsilon"; c4zeta = "C4 zeta" }
foreach ($nm in $names) {
    Set-Content -Encoding ASCII -LiteralPath "$pages\$nm.html" -Value "<!doctype html><title>$($titles[$nm])</title><h1>$($titles[$nm])</h1>"
}
& python -I -c "import json,sys; p,port,work=sys.argv[1:4]; d=json.load(open(p,encoding='utf-8')); d['workspaces'][work].append({'type':'item','id':'c4p','title':'C4 pinned','url':'http://127.0.0.1:%s/c4pin.html' % port}); open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins" $srv.port $work
$ok1 = $LASTEXITCODE -eq 0
& python -I "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null
if (-not $ok1 -or $LASTEXITCODE -ne 0) { Stop-Process -Id $srv.server.Id -EA SilentlyContinue; Write-Host "Could not seed the copy of the profile: tell Claude."; exit 1 }

$F = [ordered]@{ binary = (Get-Item "$bin\chrome.dll").LastWriteTime.ToString("o"); answers = [ordered]@{}; marks = [ordered]@{ s0 = 0 }; seed = [ordered]@{}; comment = "" }
function Save { $F | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath $answers }
function LogLines([string]$l) { if (Test-Path -LiteralPath $l) { @(Get-Content -LiteralPath $l).Count } else { 0 } }
function Step([string]$text) { Write-Host $text -ForegroundColor Yellow }
# The y/n for step `k`, and the first log's length at that moment, saved at once.
function Ask([string]$k, [string]$q) {
    do { $r = "$(Read-Host $q)".Trim().ToLower() } while ($r -notin @("y", "n"))
    $F.answers[$k] = $r; $F.marks[$k] = LogLines $log; Save
}
# The browser, its stdout and stderr in files of their own (try-c35's). Its pid.
function Launch([string]$logFile, [string[]]$more) {
    Remove-Item -LiteralPath $logFile, "$prof\DevToolsActivePort" -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$logFile`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0") + $more
    (Start-Process $exe -PassThru -ArgumentList $a -RedirectStandardOutput "$logFile.out.txt" -RedirectStandardError "$logFile.err.txt").Id
}
function WaitClosed {
    $t0 = Get-Date; $told = $false
    while (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) {
        if (-not $told -and ((Get-Date) - $t0).TotalSeconds -gt 60) { Write-Host "    (still waiting for the test browser to close: is a window of it still open?)"; $told = $true }
        Start-Sleep -Milliseconds 500
    }
}
# Until the log's last "active workspace" line is `guid` (you pressed its shortcut); false when the browser closed.
function WaitWorkspace([string]$guid, [string]$keys) {
    $t0 = Get-Date; $told = $false
    while (Get-Process -Id $script:bpid -EA SilentlyContinue) {
        $m = @(Select-String -LiteralPath $script:cur -Pattern "\[workspaces\] active workspace -> '([^']*)'" -EA SilentlyContinue) | Select-Object -Last 1
        if ($m -and $m.Matches[0].Groups[1].Value -eq $guid) { Start-Sleep 1; return $true }
        if (-not $told -and ((Get-Date) - $t0).TotalSeconds -gt 30) { Write-Host "    (still waiting: click the test browser's window, then press $keys)"; $told = $true }
        Start-Sleep -Milliseconds 500
    }
    $false
}
# Page `nm` opened through DevTools (below the tab opened before it), waited for until its title shows: its target, or
# $null. In brackets: pwsh 7's Invoke-RestMethod writes a JSON array to the pipeline as ONE object.
function OpenTab([string]$nm) {
    $port = Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1 -EA SilentlyContinue
    $dev = "http://127.0.0.1:$port/json"
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$dev/new?$([uri]::EscapeDataString("$base/$nm.html"))" } catch { $null }
    if (-not $t) { return $null }
    $t0 = Get-Date
    do {
        Start-Sleep -Milliseconds 300
        $n = @(try { (Invoke-RestMethod -TimeoutSec 10 "$dev/list") | Where-Object { $_.id -eq $t.id -and $_.title -eq $titles[$nm] } } catch { }).Count
    } while (-not $n -and ((Get-Date) - $t0).TotalSeconds -lt 10)
    Start-Sleep -Milliseconds 500
    $t
}
$hands = "Keep your hands off the browser until this window says Done."

try {
    $script:cur = $log
    $script:bpid = Launch $log @()
    Write-Host @"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched).
WORDS USED BELOW (the sidebar is the strip on the left of the window):
  TODAY TAB     a tab in the list under "+ New Tab"
  PINNED PAGE   a page in the pinned card at the top of the sidebar, e.g. "Example A"
  CHIP          a workspace's square button in the bar at the BOTTOM of the sidebar; rest the mouse on one to see
                its name. From the left: Archive, then the CHIPs Home, Work, Canary, Private, Unpin, then +.
                The CHIP of the workspace on screen is filled.
  DRAG          press the left mouse button on it, keep it pressed, move, let go where it says
Answer each question HERE, in this window: y or n, then Enter.
"@
    Step @"

 0. Press Shift+Alt+3 (Canary). This window opens two TODAY TABS there ("C4 canary one", "C4 canary two"),
    then asks you for Work. $hands
"@
    if (-not (WaitWorkspace $canary "Shift+Alt+3")) { throw "the browser closed before Canary showed" }
    $c = @("c4c1", "c4c2" | ForEach-Object { OpenTab $_ } | Where-Object { $_ }).Count
    Step "    Done. Now press Shift+Alt+2 (Work). This window opens five TODAY TABS there. $hands"
    if (-not (WaitWorkspace $work "Shift+Alt+2")) { throw "the browser closed before Work showed" }
    $w = @("c4alpha", "c4beta", "c4gamma", "c4delta", "c4epsilon" | ForEach-Object { OpenTab $_ } | Where-Object { $_ }).Count
    $F.seed["s0"] = "$c of 2 Canary tabs, $w of 5 Work tabs opened"; Save
    if ($c -lt 2 -or $w -lt 5) { Step "    The script opened only $c of 2 and $w of 5 tabs: answer n at step 1, and tell Claude." }
    Step @"
    Done. Work now shows the TODAY TABS "C4 alpha", "C4 beta", "C4 gamma", "C4 delta", "C4 epsilon" (and maybe an
    empty New Tab: leave it), and the PINNED PAGE "C4 pinned" last in the pinned card.

 1. DRAG the TODAY TAB "C4 alpha" down onto the CHIP "Canary" (the third CHIP) and HOLD it there about a
    second before you let go.
    PASS while you hold it: a ring in Canary's own colour round its CHIP, and no other CHIP ringed.
    PASS after you let go: "C4 alpha" has left Work's list; the window still shows Work (its CHIP still filled); no
    new window opened.
    Press Shift+Alt+3 (Canary).
    PASS: "C4 alpha" is the FIRST TODAY TAB there, above "C4 canary one" and "C4 canary two".
    Press Shift+Alt+2 (back to Work).
"@
    Ask "s1" "1. the ring while held; C4 alpha left Work, no new window; in Canary it is the first TODAY TAB (y/n)"
    Step @"

 2. Click the TODAY TAB "C4 beta", then hold Ctrl and click "C4 gamma" (both now selected). DRAG "C4 beta" onto the
    CHIP "Canary" and let go.
    PASS: both have left Work's list. Press Shift+Alt+3.
    PASS: "C4 beta" and "C4 gamma" are the first two TODAY TABS, in that order, above "C4 alpha".
    Press Shift+Alt+2.
"@
    Ask "s2" "2. both left Work; in Canary: C4 beta, C4 gamma, then C4 alpha (y/n)"
    Step @"

 3. Where a drop moves nothing. DRAG the TODAY TAB "C4 delta" onto the CHIP "Work" (the filled one: you are in it)
    and let go. Then DRAG "C4 delta" onto the Archive button (the left end of the bar) and let go.
    PASS: no ring on the Work CHIP or on Archive while you hold it; "C4 delta" stays in Work's list (it may now be
    at the BOTTOM of the list: a drop that ends below the list puts it there); no new window; nothing opens.
"@
    Ask "s3" "3. no ring; C4 delta stayed in Work; no new window, nothing opened (y/n)"
    Step @"

 4. DRAG the PINNED PAGE "C4 pinned" (the last in the pinned card) onto the CHIP "Canary" and HOLD it about
    a second before you let go.
    PASS while you hold it: the ring round the Canary CHIP; the list under it does not scroll.
    PASS after you let go: "C4 pinned" has left Work's pinned card. Press Shift+Alt+3.
    PASS: "C4 pinned" is the LAST PINNED PAGE of Canary (pinned pages keep C3's rule: they go last).
    Press Shift+Alt+2.
"@
    Ask "s4" "4. the ring while held, the list still; C4 pinned left Work; it is the last PINNED PAGE of Canary (y/n)"
    Step @"

 5. The menu does the same now. Click the TODAY TAB "C4 epsilon". RIGHT-click the CHIP "Canary" and click
    "Move tab here".
    PASS: "C4 epsilon" has left Work's list. Press Shift+Alt+3.
    PASS: "C4 epsilon" is the FIRST TODAY TAB there, above "C4 beta". Press Shift+Alt+2.
"@
    Ask "s5" "5. Move tab here: C4 epsilon is the first TODAY TAB of Canary (y/n)"
    Step @"

 6. The order of the workspaces. DRAG the CHIP "Unpin" (the last CHIP) to the LEFT and let go between "Home" and
    "Work".
    PASS while you drag: a thin line between two CHIPs shows where it would go.
    PASS after: the CHIPs read Home, Unpin, Work, Canary, Private (rest the mouse on each to see its name),
    and the window still shows Work.
"@
    Ask "s6" "6. the line while dragging; the CHIPs now Home, Unpin, Work, Canary, Private (y/n)"
    Step @"

 Now close the test browser (the X at its top right). This window waits for it, then opens it again in ZEN MODE with
 the sidebar unpinned, as your daily browser runs, with your tabs back.
"@
    WaitClosed
    $pinText = try { [IO.File]::ReadAllText("$prof\Default\Workspace Pins", [Text.Encoding]::UTF8) } catch { "" }
    $order = @(try { (& python -I "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.workspaces.list" | ConvertFrom-Json).items | ForEach-Object { $_.guid } } catch { })
    & python -I "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null
    if ($LASTEXITCODE -ne 0) { Step "    Could not switch the copy to zen mode: answer step 7 n, and tell Claude." }
    $script:cur = $log2
    $script:bpid = Launch $log2 @("--restore-last-session")
    Start-Sleep 8
    $z = OpenTab "c4zeta"
    $F.seed["s7"] = "C4 zeta opened: $([bool]$z)"; Save
    Step @"

 7. ZEN MODE: the sidebar is hidden; rest the mouse at the window's LEFT edge and it slides out.
    PASS: the CHIPs still read Home, Unpin, Work, Canary, Private (the order was kept).
    With the sidebar out, DRAG the TODAY TAB "C4 zeta" onto the CHIP "Canary" (now the FOURTH CHIP) and
    HOLD it about a second before you let go.
    PASS: the ring while you hold it; "C4 zeta" has left the list after you let go; no new window opened.
"@
    Ask "s7" "7. zen: the order kept; the ring while held; C4 zeta left the list, no new window (y/n)"
    Step "`n Close the test browser. This window then grades the run."
    WaitClosed
    $F.comment = "$(Read-Host "Anything that looked wrong or odd? (Enter for nothing)")".Trim(); Save
} catch {
    Write-Host "STOPPED: $_" -ForegroundColor Red
} finally {
    Stop-Process -Id $srv.server.Id -EA SilentlyContinue
}

# ---- grading: the logs and files (what you saw is your y/n) -----------------------------------------------------
$script:passed = 0; $script:failed = 0
function Row($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green; $script:passed++ } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$lines  = if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) } else { @() }
$lines2 = if (Test-Path -LiteralPath $log2) { @(Get-Content -LiteralPath $log2) } else { @() }
# The groups of each line of the first log matching `re` logged during step `k` (after the previous answer, up to this
# one) -- one array of groups per line, returned as ONE object (the leading comma): PowerShell unwraps a function's
# output, and a single match came back as its groups' characters ("dropped w, tab(s)": the rehearsal, 10-19).
function During([string]$k, [string]$re) {
    $a = $F.marks["s$([int]$k.Substring(1) - 1)"]; $b = $F.marks[$k]
    if ($null -eq $a -or $null -eq $b) { return , @() }
    , @($lines | Select-String -Pattern $re -CaseSensitive | Where-Object { $_.LineNumber -gt $a -and $_.LineNumber -le $b } | ForEach-Object { , @($_.Matches[0].Groups | ForEach-Object { $_.Value }) })
}
function Moved([string]$g) { "\[workspaces\] moved (\d+) tab\(s\) -> workspace '$g', \d+ left their group, (\d+) unit\(s\) to the top" }
$lit   = "\[workspaces\] rail drop: over '$canary'"
$drop  = "\[workspaces\] rail drop: (\d+) tab\(s\) -> '$canary'"
$anyDrop = "\[workspaces\] rail drop: \d+ tab\(s\) -> "
$anyMove = "\[workspaces\] moved \d+ tab\(s\) -> workspace "
$lines + $lines2 | Select-String -CaseSensitive -Pattern "\[workspaces\] (rail drop: \d|rail reorder|moved |pins: moved)" | ForEach-Object { Write-Host ("      log: " + ($_.Line -replace '^.*?\[workspaces\] ', '')) }

$l1 = During "s1" $lit; $d1 = During "s1" $drop; $m1 = During "s1" (Moved $canary)
Row "step 1: lit $($l1.Count) time(s); dropped $(($d1 | ForEach-Object { $_[1] }) -join ',') tab(s); moved $(($m1 | ForEach-Object { "$($_[1]) tab(s), $($_[2]) unit(s) to the top" }) -join '; ') (want lit, 1, '1 tab(s), 1 unit(s)')" ($l1.Count -ge 1 -and $d1.Count -eq 1 -and $d1[0][1] -eq "1" -and $m1.Count -eq 1 -and $m1[0][1] -eq "1" -and $m1[0][2] -eq "1")
$d2 = During "s2" $drop; $m2 = During "s2" (Moved $canary)
Row "step 2: dropped $(($d2 | ForEach-Object { $_[1] }) -join ',') tab(s); moved $(($m2 | ForEach-Object { "$($_[1]) tab(s), $($_[2]) unit(s)" }) -join '; ') (want 2, '2 tab(s), 2 unit(s)')" ($d2.Count -eq 1 -and $d2[0][1] -eq "2" -and $m2.Count -eq 1 -and $m2[0][1] -eq "2" -and $m2[0][2] -eq "2")
$n3 = (During "s3" $anyDrop).Count + (During "s3" $anyMove).Count
Row "step 3: $n3 drop / move line(s) (want 0)" ($n3 -eq 0)
$p4 = During "s4" "pins: moved 'c4p' to workspace '$canary', (\d+) open page\(s\) with it"
$pin = try { $j = $pinText | ConvertFrom-Json; [ordered]@{ inWork = @($j.workspaces.$work | Where-Object { $_.id -eq "c4p" }).Count; last = "$(@($j.workspaces.$canary)[-1].id)" } } catch { $null }
Row "step 4: 'pins: moved c4p' $($p4.Count) time(s); the pins file: in Work $($pin.inWork), Canary's last '$($pin.last)' (want 1, 0, c4p)" ($p4.Count -eq 1 -and $pin -and $pin.inWork -eq 0 -and $pin.last -eq "c4p")
$m5 = During "s5" (Moved $canary); $d5 = (During "s5" $anyDrop).Count
Row "step 5: moved $(($m5 | ForEach-Object { "$($_[1]) tab(s), $($_[2]) unit(s)" }) -join '; ') by the menu, $d5 drop line(s) (want '1 tab(s), 1 unit(s)', 0)" ($m5.Count -eq 1 -and $m5[0][1] -eq "1" -and $m5[0][2] -eq "1" -and $d5 -eq 0)
$r6 = During "s6" "\[workspaces\] rail reorder: '$unpin' gap (\d+) -> offset (-?\d+)"; $w6 = During "s6" "\[workspaces\] moved workspace '$unpin' by (-?\d+)"
$want = @("default", $unpin, $work, $canary)
Row "step 6: reorder $(($r6 | ForEach-Object { "gap $($_[1]) offset $($_[2])" }) -join '; '), moved by $(($w6 | ForEach-Object { $_[1] }) -join ','); Preferences: $($order -join ', ') (want gap 1 offset -3, -3, Home, Unpin, Work, Canary first)" ($r6.Count -eq 1 -and $r6[0][1] -eq "1" -and $r6[0][2] -eq "-3" -and $w6.Count -eq 1 -and $w6[0][1] -eq "-3" -and ($order.Count -ge 4 -and (($order[0..3] -join ' ') -eq ($want -join ' '))))
$l7 = @($lines2 | Select-String -CaseSensitive -Pattern $lit).Count
$d7 = @($lines2 | Select-String -CaseSensitive -Pattern $drop | Where-Object { $_.Matches[0].Groups[1].Value -eq "1" }).Count
$m7 = @($lines2 | Select-String -CaseSensitive -Pattern (Moved $canary)).Count
Row "step 7 (zen): lit $l7 time(s), dropped 1 tab $d7 time(s), moved $m7 time(s) (want >=1, 1, 1)" ($l7 -ge 1 -and $d7 -eq 1 -and $m7 -eq 1)
# Case-sensitive, as LOCAL.md grades (check-c35's markers).
$markers = 0
foreach ($l in @($log, $log2)) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Row "crash markers in both logs: $markers (want 0)" ($markers -eq 0)

$yes = @($F.answers.Values | Where-Object { $_ -eq "y" }).Count
Write-Host "your answers: $(@($F.answers.Keys | ForEach-Object { "$_ $($F.answers[$_])" }) -join ', ')$(if ($F.comment) { "; comment: $($F.comment)" })"
Write-Host "seeding: step 0 $($F.seed['s0']); step 7 $($F.seed['s7'])"
$verdict = if ($yes -eq 7 -and $script:failed -eq 0) { "PASS" } else { "FAIL" }
Write-Host "RESULT c4-owner you said y to $yes of 7; log checks pass=$($script:passed) fail=$($script:failed); crash markers $markers; verdict=$verdict"
Write-Host "Tell Claude the RESULT line (or copy this whole window). Logs: $log, $log2; answers: $answers."
