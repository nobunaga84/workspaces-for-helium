param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [ValidateSet("C2", "C1", "Scale", "All")][string]$Part = "All",
      [double]$IdleMinutes = 15)
# C2 + C1 (patches 63, 64): Ctrl+Tab reaches open pinned pages; the quick search box (Shift+Alt+F). Real keys, so it
# starts only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (a person starting it passes -IdleMinutes 0 and lets
# go of the mouse). Each part starts its own browser on its own fresh profile copy, with
# helium.browser.mru_tab_cycling written before the start (prefs.py): true for the MRU rows, false for the default
# order. Which page shows is read from DevTools (document.visibilityState), the box from MSAA, the rest from the log.
#   C2, MRU on (the smoke profile, in Work; only A, B, C, D left open)
#     a  A-D opened (appended), shown C, D, B, A (MRU A, B, D, C): Ctrl HELD, Tab -> B; W closes B; Tab -> the next
#        of A, D, C after the page the close showed (D17), the browser alive. Brave's raw indices CHECK-crash here.
#     b  P shown, then A; a background tab BG made through DevTools: one Ctrl+Tab -> P (not BG, not A).
#     c  Q pinned with Shift+Alt+D; A, Q, A shown in turn: one Ctrl+Tab -> Q, the open pinned page.
#     c2 a page X left last in Canary: from Work one Ctrl+Tab -> X, the window in Canary (MRU crosses
#        workspaces, the owner's answer).
#   C2, MRU off (a new start, in Work)
#     d  t1..t3 opened, then "Example A" from its pinned page (its tab is the strip's last): Ctrl+9 (the last Today
#        tab), then one Ctrl+Tab -> Example A's page.
#     e  Ctrl+9, then Ctrl+PgDn -> Example A's page.
#     f  Ctrl+9 never landed on it; "Close other tabs" on Today tab t1 closes t2, t3 and leaves it open.
#   C1 (the smoke profile; in Canary a Today tab "lcanary" and a pinned page "qcanary" left open; in Work a
#      tab "karch" closed into the Archive, a pinned page "rp" left open, then "w1" in front)
#     g  Shift+Alt+F: a box with its "Find tabs and pages" field, centred over the page.
#     h  the empty box: rp under "Recent tabs"; not w1 (in front); not Example A (a closed pinned page).
#     i  "qcanary" -> its row under "Pinned pages"; Enter opens it in Canary. i3: its page closed (Ctrl+W),
#        from Work Enter opens it again in Canary (ShowItem's closed-page branch).
#     j  "closed folder" (a folder's name) lists Hidden, the page inside it.   m  Escape closes the box.
#     k  "karch" -> under "Archived"; Enter restores it into Work, and the box then finds it only as an open tab.
#     l  from Work, "lcanary" -> under "Open tabs"; Enter shows it in Canary.
#     n  Shift+Alt+F twice: "toggled closed", no box.
#   Scale (a copy of testprofile, 1,750 archived tabs written by make-archive-fixture.py, Recently Closed emptied):
#     the box opens with A = 1750, P >= 3400 in <= 1000 ms; one letter filters in <= 300 ms. Graded on Default
#     only; Dcheck reports the numbers.
# A pass needs every row and 0 crash markers in each part's log. Run it in its own process (pwsh -File): it compiles
# C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$active = "\[workspaces\] active workspace -> '([^']*)'"
$pinned = "pins: pinned a tab as item '([^']+)'"
$opened = "quick search: opened, (\d+) tab\(s\) (\d+) pinned (\d+) archived in (\d+) ms"
$heads  = @("Recent tabs", "Open tabs", "Pinned pages", "Archived")
$script:failed = 0; $script:passed = 0; $script:bpid = 0; $script:port = 0; $script:prof = ""; $script:log = ""
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $script:log)) { return 0 }; @(Select-String -LiteralPath $script:log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Last([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Matches[0] }) } }
# The last line matching `re`: the whole match, then its groups, as strings (empty when none).
function Grp([string]$re) { $m = @(Last $re); if ($m.Count) { @($m[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function ActiveWs { $g = Grp $active; if ($g.Count) { $g[1] } else { "" } }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $script:prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Names([IntPtr]$h) { @(Msaa $h @("-List") | ForEach-Object { if ($_ -match '^\s*(.*?)\|0x') { $Matches[1] } }) }
# Every MSAA node of window `h`: name, role, box (physical pixels), shown (not INVISIBLE, a box with size), selected
# (msaa-press -States: the box's highlighted row).
function Nodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Rect", "-States") | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)(\|SELECTED)?(\|UNAVAILABLE)?$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); l = [int]$Matches[4]; t = [int]$Matches[5]
                               w = [int]$Matches[6]; h = [int]$Matches[7]; selected = [bool]$Matches[8]
                               shown = (-not $Matches[3]) -and [int]$Matches[6] -gt 0 -and [int]$Matches[7] -gt 0 }
        }
    })
}
# The box's shown rows (role 0x22, list item) named `nm`: "<rail mark>  <name>", or the name alone (a favorite).
function RowNamed($nodes, [string]$nm) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x22 -and ($_.name -eq $nm -or $_.name.EndsWith("  $nm")) }) }
# The heading a row is drawn under: the lowest shown group heading above it.
function HeadingOf($nodes, $row) { "$(@($nodes | Where-Object { $_.shown -and $heads -contains $_.name -and $_.t -le $row.t } | Sort-Object t | Select-Object -Last 1 | ForEach-Object { $_.name }))" }
function RowList($nodes) { (@($nodes | Where-Object { $_.shown -and $_.role -eq 0x22 } | Sort-Object t | ForEach-Object { "$($_.name)$(if ($_.selected) { ' [highlighted]' })" }) -join " | ") }
# Where row `nm` of `nodes` sits: "under '<heading>'", or "no row".
function RowPlace($nodes, [string]$nm) { $r = @(RowNamed $nodes $nm) | Select-Object -First 1; if ($r) { "under '$(HeadingOf $nodes $r)'" } else { "no row" } }
# Keys to the browser's window in front, through SendKeys ("%+f" is Shift+Alt+F) -- never to another window.
function Keys([string]$k) {
    if ([C2Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
# The browser's other window (a bubble) whose MSAA names include `name`, polled.
function Bubble([IntPtr]$main, [string]$name) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) { if ((Names $w) -contains $name) { return $w } }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    [IntPtr]::Zero
}
# The first shown node matching `re` in the browser's other windows (a menu), pressed via MSAA.
function OtherPress([IntPtr]$main, [string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    "nothing matching '$re'"
}
# Where bubble `b`'s centre sits in the main window's client area, as fractions of its width and height (check-c13).
function Centre([IntPtr]$main, [IntPtr]$b) {
    $m = [E18Input]::Client($main); $c = [E18Input]::Client($b)
    [pscustomobject]@{ x = ($c[0] + $c[2] / 2 - $m[0]) / $m[2]; y = ($c[1] + $c[3] / 2 - $m[1]) / $m[3] }
}
function IsCentred($f) { $f.x -gt 0.35 -and $f.x -lt 0.8 -and $f.y -gt 0.3 -and $f.y -lt 0.75 }
function Shot([IntPtr]$h, [string]$path) {
    Add-Type -AssemblyName System.Drawing
    $c = [E18Input]::Client($h)
    $bmp = New-Object System.Drawing.Bitmap ([int]$c[2]), ([int]$c[3])
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen([int]$c[0], [int]$c[1], 0, 0, $bmp.Size); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $g.Dispose(); $bmp.Dispose() }
    $path
}
# A workspace by its shortcut; the setup stops when it does not show.
function Go([string]$k, [string]$guid) {
    $c = Count $active; $r = Keys $k
    if (-not ((WaitLog $active ($c + 1) 10) -and (ActiveWs) -eq $guid)) { throw "$k did not show workspace '$guid' ($r)" }
    Start-Sleep (1 * $slow)
}

# ---- DevTools: the pages, which one is visible, new ones --------------------------------------------------------
function Url([string]$n) { "http://127.0.0.1:$($script:srv.port)/$n.html" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# In brackets: pwsh 7's Invoke-RestMethod writes a JSON array to the pipeline as ONE object, so piped straight into
# Where-Object every page came through as one lump (the first run: 'shown: none' in 11 rows, 2026-10-13).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_.type -eq "page" }) } catch { @() } }
function Has([string]$n) { @(Targets | Where-Object { $_.url -like "*/$n.html*" }).Count }
# A page by its short name: "a" for .../a.html, else its address.
function Short([string]$u) { if ($u -match '/([\w-]+)\.html') { $Matches[1] } else { $u } }
# The page that shows: the one whose document is visible, by its short name ("none", or "a+b" when two say so).
function Visible {
    Start-Sleep -Milliseconds (300 * $slow)
    $v = @(Targets | Where-Object { (Evaluate $_.webSocketDebuggerUrl "document.visibilityState") -eq "visible" } | ForEach-Object { Short $_.url })
    if ($v.Count) { $v -join "+" } else { "none" }
}
# Served page `n` opened in front (/json/new), once its title is in: its target (id, url, webSocketDebuggerUrl).
function NewTab([string]$n) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$(Url $n)" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$n'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.title") -ne "E18 $n" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A page brought in front (/json/activate: the tab activated, as a click on it).
function Show($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
function CloseTarget($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/close/$($t.id)" } catch {} }
# One call on the browser's own DevTools endpoint (/json/version): the reply ({id, result} or {id, error}), or $null.
function BrowserCall([string]$method, [hashtable]$params) {
    $ver = try { Invoke-RestMethod -TimeoutSec 10 "$(Base)/version" } catch { $null }
    if (-not $ver) { return $null }
    $sock = [Net.WebSockets.ClientWebSocket]::new(); $none = [Threading.CancellationToken]::None
    try {
        if (-not $sock.ConnectAsync([Uri]$ver.webSocketDebuggerUrl, $none).Wait(10000)) { return $null }
        $o = [Text.Encoding]::UTF8.GetBytes((@{ id = 1; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 4))
        if (-not $sock.SendAsync([ArraySegment[byte]]::new($o), [Net.WebSockets.WebSocketMessageType]::Text, $true, $none).Wait(10000)) { return $null }
        $buf = [byte[]]::new(65536); $got = 0
        do {
            $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf, $got, $buf.Length - $got), $none)
            if (-not $r.Wait(15000)) { return $null }
            $got += $r.Result.Count
        } until ($r.Result.EndOfMessage)
        [Text.Encoding]::UTF8.GetString($buf, 0, $got) | ConvertFrom-Json
    } catch { $null } finally { $sock.Dispose() }
}

# ---- the quick search box ---------------------------------------------------------------------------------------
# Shift+Alt+F, then the box's window ([IntPtr]::Zero when none came).
function OpenBox([IntPtr]$main) { $null = Keys "%+f"; Bubble $main "Find tabs and pages" }
# `text` typed into the open box, and its filter line: t/p/a (the rows shown per group) and ms; -1 when no line came.
function Search([string]$text) {
    $re = "quick search: filter of $($text.Length) char\(s\) -> (\d+)/(\d+)/(\d+) shown in (\d+) ms"
    $c = Count $re; $r = Keys $text
    if (-not (WaitLog $re ($c + 1) 5)) { return [pscustomobject]@{ t = -1; p = -1; a = -1; ms = -1; line = "'$text' $r, no 'filter of $($text.Length) char(s)' line" } }
    Start-Sleep -Milliseconds (500 * $slow)
    $g = Grp $re
    [pscustomobject]@{ t = [int]$g[1]; p = [int]$g[2]; a = [int]$g[3]; ms = [int]$g[4]; line = "'$text' -> $($g[1])/$($g[2])/$($g[3]) shown in $($g[4]) ms" }
}
# Enter on row `nm` of the box: Down until MSAA says it is the highlighted one, then Enter. When no row says SELECTED
# at all, Enter as it is (reported).
function EnterOn([IntPtr]$box, [string]$nm) {
    for ($i = 0; $i -lt 25; $i++) {
        $rows = @(Nodes $box | Where-Object { $_.shown -and $_.role -eq 0x22 })
        $r = @(RowNamed $rows $nm) | Select-Object -First 1
        if (-not $r) { return "no row '$nm'" }
        if ($r.selected -or -not @($rows | Where-Object { $_.selected }).Count) {
            return "Down x$i$(if (-not $r.selected) { ' (no row says SELECTED)' }), Enter $(Keys '{ENTER}')"
        }
        $null = Keys "{DOWN}"
    }
    "row '$nm' never highlighted"
}

# ---- a part's browser -------------------------------------------------------------------------------------------
# A fresh copy of `src` as this part's profile, MRU cycling written. The smoke profile's Sessions are emptied (no
# restore); the big profile keeps its session and loses only Recently Closed (Tabs_*: a 3,864-tab window, LOCAL.md 42).
function Fresh([string]$name, [string]$src, [bool]$mru) {
    $script:prof = "$ws\testprofile-c2-$name$suffix"
    $script:log = if ($OutDir -eq "Dcheck") { "$ws\c2-$name-dcheck-exercise.log" } else { "$ws\c2-$name-run.log" }
    if (Test-Path -LiteralPath $script:prof) { Remove-Item -LiteralPath $script:prof -Recurse -Force }
    $null = robocopy $src $script:prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if ($LASTEXITCODE -ge 8 -or -not (Test-Path -LiteralPath "$($script:prof)\Default\Preferences")) { throw "the copy of $src failed (robocopy $LASTEXITCODE)" }
    Get-ChildItem -LiteralPath "$($script:prof)\Default\Sessions" -File -EA SilentlyContinue | Where-Object { $src -eq $smoke -or $_.Name -like "Tabs_*" } | Remove-Item -Force
    Remove-Item -LiteralPath "$($script:prof)\DevToolsActivePort", $script:log -EA SilentlyContinue
    & python "$here\prefs.py" "$($script:prof)\Default\Preferences" "helium.browser.mru_tab_cycling=$(if ($mru) { 'true' } else { 'false' })" | Out-Null
    Say "profile $($script:prof), helium.browser.mru_tab_cycling=$mru"
}
# The browser on the part's profile, with a log and DevTools; its main window, placed.
function Launch([int]$s = 30) {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$($script:prof)", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check")).Id
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of" 1 $s
    [E18Input]::Place($main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $script:port = [int](Get-Content -LiteralPath "$($script:prof)\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port), log $($script:log)"
    $main
}
# Closed as the X closes it; whatever of the build still runs then (a renderer too) is stopped: the next part's copy
# and the fixture want none running.
function Quit {
    if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    }
    Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    $t0 = Get-Date; while ((Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) -and ((Get-Date) - $t0).TotalSeconds -lt 15) { Start-Sleep 1 }
    $script:bpid = 0
}
function RunPart([string]$title, [scriptblock]$body) {
    Say "==== $title"
    $script:log = ""
    try { $null = & $body } catch { Say "ERROR: $_"; $script:failed++ } finally { Quit }
    # Case-sensitive (LOCAL.md 86): "dangling" matched the exit histogram Commerce.PriceTracking.DanglingUserSubscription...
    if ($script:log) { $m = @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|DanglingPtr").Count; Verdict "z crash markers in $($script:log): $m" ($m -eq 0) }
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'quick search: toggled closed')>=0 else 1)" "$bin\chrome.dll"
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 64"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real keys ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C2Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }'
$script:srv = ServePages "$ws\c2-pages" @("a", "b", "c", "d", "p", "bg", "x", "q", "t1", "t2", "t3", "lcanary", "qcanary", "karch", "rp", "w1")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
try {
    if ($Part -in @("C2", "All")) {
        RunPart "C2, most recently used order (helium.browser.mru_tab_cycling true)" {
            Fresh "mru" $smoke $true
            $main = Launch
            Go "%+2" $work
            $pa = NewTab "a"; $pb = NewTab "b"; $pc = NewTab "c"; $pd = NewTab "d"
            # Only A-D left open (Home's and Work's New Tab closed). /json/new APPENDS, so the model is A, B, C, D.
            foreach ($t in @(Targets | Where-Object { $_.id -notin @($pa.id, $pb.id, $pc.id, $pd.id) })) { CloseTarget $t }
            # Shown C, D, B, A: the MRU order is A, B, D, C (review, code-review side note). Built so BOTH old bugs
            # fail a3: Brave's raw indices [0,1,3,2] activate index 3 of a 3-tab strip after W closes B (the CHECK
            # crash); and without D17 the press after W re-activates C, the tab the close showed (a dead press).
            Show $pc; Show $pd; Show $pb; Show $pa
            Start-Sleep (2 * $slow)
            $v0 = Visible
            $bp = [uint32]$script:bpid
            $hold = [E18Input]::KeyDown($bp, 0x11)
            try {
                $r1 = [E18Input]::Tap($bp, 0x09); $v1 = Visible
                $r2 = [E18Input]::Tap($bp, 0x57); Start-Sleep (1 * $slow); $v2 = Visible
                $r3 = [E18Input]::Tap($bp, 0x09); $v3 = Visible
            } finally { $up = [E18Input]::KeyUp($bp, 0x11) }
            $alive = [bool](Get-Process -Id $script:bpid -EA SilentlyContinue)
            Verdict "a1 Ctrl held, Tab: B shows (A in front first: $v0; Ctrl $hold; Tab $r1; shown: $v1)" ($v0 -eq "a" -and $v1 -eq "b")
            Verdict "a2 W closes B (W $r2; B open: $(Has 'b'); shown: $v2)" ((Has "b") -eq 0 -and $v2 -in @("a", "c", "d"))
            # The MRU order without B is A, D, C: the next after the page the close showed (D17), wrapping.
            $order = @("a", "d", "c"); $i = [array]::IndexOf($order, $v2)
            $want = if ($i -ge 0) { $order[($i + 1) % 3] } else { "?" }
            Verdict "a3 Tab again: the next of the MRU order A, D, C after '$v2' shows (Tab $r3; Ctrl let go: $up; expected: $want; shown: $v3; browser alive: $alive)" ($alive -and $v3 -eq $want)

            $null = NewTab "p"; Show $pa
            $bg = BrowserCall "Target.createTarget" @{ url = (Url "bg"); background = $true }
            Start-Sleep (2 * $slow)
            $v4 = Visible
            $r = Keys "^{TAB}"; $v5 = Visible
            Verdict "b P, then A shown, a background tab BG made: one Ctrl+Tab -> P (BG made: $([bool]$bg.result.targetId), open: $(Has 'bg'); before: $v4; Ctrl+Tab $r; shown: $v5)" ($v4 -eq "a" -and (Has "bg") -eq 1 -and $v5 -eq "p")

            $pq = NewTab "q"
            $c = Count $pinned; $r = Keys "%+d"
            $ok = WaitLog $pinned ($c + 1) 5
            Start-Sleep (1 * $slow)
            Show $pa; Show $pq; Show $pa
            $v6 = Visible
            $r2 = Keys "^{TAB}"; $v7 = Visible
            Verdict "c one Ctrl+Tab reaches the open pinned page Q (Shift+Alt+D $r, pinned: $ok; A, Q, A shown, then: $v6; Ctrl+Tab $r2; shown: $v7; workspace: $(if ((ActiveWs) -eq $work) { 'Work' } else { "'$(ActiveWs)'" }))" ($ok -and $v6 -eq "a" -and $v7 -eq "q" -and (ActiveWs) -eq $work)

            # c2 (code review T5): MRU Ctrl+Tab still CROSSES workspaces (the owner's answer, design 3.6): a page
            # left last in Canary is the first Ctrl+Tab's landing from Work, and the window follows it.
            Go "%+3" $canary
            $null = NewTab "x"
            Go "%+2" $work
            $v8 = Visible
            $ca = Count $active; $r = Keys "^{TAB}"; $v9 = Visible
            $sw = (WaitLog $active ($ca + 1) 5) -and (ActiveWs) -eq $canary
            Verdict "c2 Ctrl+Tab crosses workspaces: from Work ($v8) one Ctrl+Tab -> X in Canary (Ctrl+Tab $r; shown: $v9; the window shows Canary: $sw)" ($v9 -eq "x" -and $sw)
        }
        RunPart "C2, the default order (helium.browser.mru_tab_cycling false)" {
            Fresh "order" $smoke $false
            $main = Launch
            Go "%+2" $work
            $null = NewTab "t1"; $null = NewTab "t2"; $null = NewTab "t3"
            # Example A's page opened from its pinned page: appended (OpenItem), so its tab is the strip's last.
            $openedItem = "pins: opened item '([^']+)'"
            $c = Count $openedItem; $r = Press $main "Example A"
            if (-not (WaitLog $openedItem ($c + 1) 10)) { throw "Example A's page did not open ($r)" }
            Start-Sleep (2 * $slow)
            $ex = "*example.com*"
            $r9 = Keys "^9"; $v9 = Visible
            $rt = Keys "^{TAB}"; $vt = Visible
            Verdict "d from the last Today tab (Ctrl+9 $r9 -> $v9) one Ctrl+Tab lands on the open pinned page Example A ($rt; shown: $vt)" ($v9 -ne "none" -and $v9 -notlike $ex -and $vt -like $ex)
            $r9b = Keys "^9"; $v9b = Visible
            $rd = Keys "^{PGDN}"; $vd = Visible
            Verdict "e from the last Today tab (Ctrl+9 $r9b -> $v9b) Ctrl+PgDn lands on it too ($rd; shown: $vd)" ($v9b -ne "none" -and $v9b -notlike $ex -and $vd -like $ex)
            $tab = @(Nodes $main | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -eq "E18 t1" }) | Select-Object -First 1
            $m = if ($tab) { [E18Input]::Click($main, $tab.l + [int]($tab.w / 3), $tab.t + [int]($tab.h / 2), $true) } else { "no Today tab 'E18 t1' drawn" }
            Start-Sleep -Milliseconds (800 * $slow)
            $r = if ($tab) { OtherPress $main '^Close other tabs' } else { "no menu" }
            Start-Sleep (3 * $slow)
            $kept = @(Targets | Where-Object { $_.url -like $ex }).Count
            Verdict "f Ctrl+9 never landed on the pinned page ($v9, $v9b); 'Close other tabs' on Today tab t1 ($m; $r) closed t2, t3 (open: $(Has 't2'), $(Has 't3')), kept t1 ($(Has 't1')) and the pinned page's page ($kept)" ($v9 -notlike $ex -and $v9b -notlike $ex -and (Has "t2") -eq 0 -and (Has "t3") -eq 0 -and (Has "t1") -eq 1 -and $kept -eq 1)
        }
    }
    if ($Part -in @("C1", "All")) {
        RunPart "C1, the quick search box (Shift+Alt+F)" {
            Fresh "c1" $smoke $true
            $main = Launch
            # Canary: a Today tab, and a page pinned there and left open.
            Go "%+3" $canary
            $null = NewTab "lcanary"; $null = NewTab "qcanary"
            $c = Count $pinned; $r = Keys "%+d"
            if (-not (WaitLog $pinned ($c + 1) 5)) { throw "qcanary was not pinned ($r)" }
            # Work: a tab closed into the Archive, a page pinned and left open, then w1 in front.
            Go "%+2" $work
            $null = NewTab "karch"
            $archived = "archived a manual close in '$work'"
            $c = Count $archived; $r = Keys "^w"
            if (-not (WaitLog $archived ($c + 1) 5)) { throw "karch was not closed into the Archive ($r)" }
            $null = NewTab "rp"
            $c = Count $pinned; $r = Keys "%+d"
            if (-not (WaitLog $pinned ($c + 1) 5)) { throw "rp was not pinned ($r)" }
            $null = NewTab "w1"

            # g: the box, centred over the page.
            $c = Count "shortcut: quick search"; $co = Count $opened; $cr = Count "quick search: recent, (\d+) shown"
            $box = OpenBox $main
            $ok = (WaitLog "shortcut: quick search" ($c + 1) 5) -and (WaitLog $opened ($co + 1) 5)
            $nodes = if ($box -ne [IntPtr]::Zero) { @(Nodes $box) } else { @() }
            $field = @($nodes | Where-Object { $_.shown -and $_.name -eq "Find tabs and pages" -and $_.role -eq 0x2A }).Count
            $f = if ($box -ne [IntPtr]::Zero) { Centre $main $box } else { $null }
            $shot = Shot $main "$ws\c2-c1$suffix-box.png"
            Verdict "g1 Shift+Alt+F opens the box with its 'Find tabs and pages' field (logged: $ok, $((Grp $opened)[0]); field shown: $field)" ($ok -and $field -ge 1)
            Verdict "g2 the box is centred over the page ($(if ($f) { 'at {0:N2}, {1:N2}' -f $f.x, $f.y } else { 'no box' }); $shot)" ($f -and (IsCentred $f))

            # h: the empty box's recent tabs.
            $recent = (WaitLog "quick search: recent, (\d+) shown" ($cr + 1) 5)
            $nodes = if ($box -ne [IntPtr]::Zero) { @(Nodes $box) } else { @() }
            $under = RowPlace $nodes "E18 rp"
            Verdict "h the empty box lists recent tabs: the open pinned page rp $under, not w1 (in front), not the closed pinned page Example A ($((Grp 'quick search: recent, (\d+) shown')[0]); rows: $(RowList $nodes))" ($recent -and $under -eq "under 'Recent tabs'" -and @(RowNamed $nodes "E18 w1").Count -eq 0 -and @(RowNamed $nodes "Example A").Count -eq 0)

            # i: another workspace's pinned page, by its name.
            $s = Search "qcanary"
            $nodes = @(Nodes $box)
            $under = RowPlace $nodes "E18 qcanary"
            Verdict "i1 Canary's pinned page qcanary is found $under ($($s.line); rows: $(RowList $nodes))" ($s.p -ge 1 -and $under -eq "under 'Pinned pages'")
            $op = "quick search: opened a pinned page in '([^']*)'"
            $c = Count $op; $ca = Count $active
            $e = EnterOn $box "E18 qcanary"
            $ok = (WaitLog $op ($c + 1) 5) -and (Grp $op)[1] -eq $canary
            $sw = (WaitLog $active ($ca + 1) 5) -and (ActiveWs) -eq $canary
            $v = Visible
            Verdict "i2 Enter opens it in Canary ($e; 'opened a pinned page in' Canary: $ok; the window shows Canary: $sw; shown: $v)" ($ok -and $sw -and $v -eq "qcanary")

            # i3 (code review T2): the same pinned page with its page CLOSED, opened from Work -- ShowItem's new
            # branch (EnterWorkspaceForInsert, then OpenItem with the workspace in the extra data). i2 only took
            # the linked branch, the road a row click already had.
            $cw = "closed the page of pinned item .*\(Ctrl\+W\)"
            $cc = Count $cw; $r = Keys "^w"
            if (-not (WaitLog $cw ($cc + 1) 5)) { throw "qcanary's page did not close ($r)" }
            Go "%+2" $work
            $box = OpenBox $main
            $s = Search "qcanary"
            $oi = "pins: opened item '([^']+)'"
            $c = Count $op; $ci = Count $oi; $ca = Count $active
            $e = EnterOn $box "E18 qcanary"
            $ok = (WaitLog $oi ($ci + 1) 5) -and (WaitLog $op ($c + 1) 5) -and (Grp $op)[1] -eq $canary
            $sw = (WaitLog $active ($ca + 1) 5) -and (ActiveWs) -eq $canary
            $v = Visible
            Verdict "i3 its page closed, Enter from Work opens it again in Canary ($e; opened: $ok; the window shows Canary: $sw; shown: $v; open: $(Has 'qcanary'))" ($ok -and $sw -and $v -eq "qcanary" -and (Has "qcanary") -eq 1)

            # j: a folder's name lists the page inside it; m: Escape.
            $box = OpenBox $main
            $s = Search "closed folder"
            $nodes = if ($box -ne [IntPtr]::Zero) { @(Nodes $box) } else { @() }
            $under = RowPlace $nodes "Hidden"
            Verdict "j 'closed folder' (a folder's name) lists Hidden, the page inside it, $under ($($s.line))" ($s.p -ge 1 -and $under -eq "under 'Pinned pages'")
            $r = Keys "{ESC}"; Start-Sleep (2 * $slow)
            Verdict "m Escape closes the box (box was open: $($box -ne [IntPtr]::Zero); Escape $r)" ($box -ne [IntPtr]::Zero -and (Bubble $main "Find tabs and pages") -eq [IntPtr]::Zero)

            # k: the archived tab, restored; the box then finds it only as an open tab.
            $box = OpenBox $main
            $s = Search "karch"
            $nodes = if ($box -ne [IntPtr]::Zero) { @(Nodes $box) } else { @() }
            $under = RowPlace $nodes "E18 karch"
            Verdict "k1 the archived tab karch is found $under ($($s.line))" ($s.a -ge 1 -and $under -eq "under 'Archived'")
            $op = "quick search: opened an archived tab in '([^']*)'"
            $c = Count $op; $cx = Count "archive: restored an entry into '$work'"
            $e = EnterOn $box "E18 karch"
            $ok = (WaitLog $op ($c + 1) 5) -and (Grp $op)[1] -eq $work
            $rest = WaitLog "archive: restored an entry into '$work'" ($cx + 1) 5
            Start-Sleep (2 * $slow)
            $box = OpenBox $main
            $s2 = Search "karch"
            $null = Keys "{ESC}"; Start-Sleep (2 * $slow)
            Verdict "k2 Enter restores it into Work, and it left the Archive ($e; 'opened an archived tab in' Work: $ok; restored: $rest; open: $(Has 'karch'); searched again: $($s2.line))" ($ok -and $rest -and (Has "karch") -eq 1 -and $s2.a -eq 0 -and $s2.t -ge 1)

            # l: another workspace's open tab, from Work.
            if ((ActiveWs) -ne $work) { Go "%+2" $work }
            $box = OpenBox $main
            $s = Search "lcanary"
            $nodes = if ($box -ne [IntPtr]::Zero) { @(Nodes $box) } else { @() }
            $under = RowPlace $nodes "E18 lcanary"
            Verdict "l1 from Work, Canary's Today tab lcanary is found $under ($($s.line))" ($s.t -ge 1 -and $under -eq "under 'Open tabs'")
            $op = "quick search: opened a tab in '([^']*)'"
            $c = Count $op; $ca = Count $active
            $e = EnterOn $box "E18 lcanary"
            $ok = (WaitLog $op ($c + 1) 5) -and (Grp $op)[1] -eq $canary
            $sw = (WaitLog $active ($ca + 1) 5) -and (ActiveWs) -eq $canary
            $v = Visible
            Verdict "l2 Enter shows it in Canary ($e; 'opened a tab in' Canary: $ok; the window shows Canary: $sw; shown: $v)" ($ok -and $sw -and $v -eq "lcanary")

            # n: the key again closes the box.
            $c = Count "quick search: toggled closed"
            $box = OpenBox $main
            $r = Keys "%+f"
            $ok = WaitLog "quick search: toggled closed" ($c + 1) 5
            Start-Sleep (2 * $slow)
            Verdict "n Shift+Alt+F twice: 'toggled closed' and no box (box opened: $($box -ne [IntPtr]::Zero); second press $r; logged: $ok)" ($box -ne [IntPtr]::Zero -and $ok -and (Bubble $main "Find tabs and pages") -eq [IntPtr]::Zero)
        }
    }
    if ($Part -in @("Scale", "All")) {
        RunPart "Scale, testprofile with 1,750 archived tabs" {
            Fresh "scale" "$ws\testprofile" $true
            # Its Archive: 1,750 entries over 59 days, Arc's split (design 5). It refuses while a fork chrome.exe runs.
            $fx = @(& python "$here\make-archive-fixture.py" $script:prof --count 1750 --days 59 2>&1)
            $code = $LASTEXITCODE
            $fx | ForEach-Object { Say "      $_" }
            if ($code -ne 0) { throw "make-archive-fixture.py refused (exit $code)" }
            $main = Launch 60
            $loaded = WaitLog "archive: loaded 1750 entr\(ies\)" 1 60
            Start-Sleep (5 * $slow)
            $c = Count $opened
            $box = OpenBox $main
            $ok = WaitLog $opened ($c + 1) 30
            $g = Grp $opened
            $say = if ($g.Count) { "$($g[1]) tab(s) $($g[2]) pinned $($g[3]) archived in $($g[4]) ms" } else { "no 'quick search: opened' line (box: $($box -ne [IntPtr]::Zero))" }
            $s = Search "p"
            $null = Keys "{ESC}"
            Verdict "S1 the store loaded the fixture ('archive: loaded 1750 entr(ies)')" $loaded
            if ($OutDir -eq "Default") {
                Verdict "S2 Shift+Alt+F opens with 1750 archived, >= 3400 pinned, in <= 1000 ms ($say)" ($ok -and [int]$g[3] -eq 1750 -and [int]$g[2] -ge 3400 -and [int]$g[4] -le 1000)
                Verdict "S3 one letter filters in <= 300 ms ($($s.line))" ($s.ms -ge 0 -and $s.ms -le 300)
            } else {
                Say "      S2/S3 on Dcheck, reported, not graded: opened, $say; one letter: $($s.line)"
            }
        }
    }
} finally {
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
Say "RESULT c2-$Part$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
