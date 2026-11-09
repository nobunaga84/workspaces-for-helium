param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "e181", [string]$GradeLog = "",
      [switch]$Group, [double]$IdleMinutes = 15)
# E18.1 (LOCAL.md 66): a saved tab group reopened from Recently Closed keeps the workspace it was closed from.
# The owner's case, 2026-10-04: a 600-tab window was closed and reopened from Recently Closed, and its three saved
# groups (Home) came back in the workspace on screen (Canary). Chromium rebuilds a saved group from its
# saved-group model, which holds no workspace (BrowserLiveTabContext::AddRestoredTab -> OpenSavedTabGroup).
# Nobody at the keyboard and no real input: MSAA presses the rail's buttons (msaa-press.ps1) and local\e181-ext does
# the rest, on a throwaway copy of the smoke profile (Home + Work), its Sessions emptied:
#   1. the first window (W1) switched to Work; "E18 g1".."E18 g3" opened there; the extension groups them
#      ("E18.1 group", saved by Chromium)
#   2. W1 switched back to Home; "E18 go" opened (the extension's signal): it opens W2 -- on Home, the workspace of
#      the window used last -- closes W1, and reopens W1 from Recently Closed by id: W3, on Home
# A pass: every window opened on Home; the reopen rebuilt the group from Chromium's saved-group model (its
# "OpenTabGroup" line, logged with --vmodule) and stamped at least 3 tabs Work, the FIRST of them while W3 showed
# Home (before the fix: 'default'). The rebuild goes first into the empty W3, so that tab is active and W3 follows it
# to Work for a moment; restoring W1's selected Home tab brings W3 back (design review, LOCAL.md 66). Then W3 on Home
# shows none of g1..g3 and, after "Work" is pressed on W3, all three; after the quit the session file's
# "E18.1 group" holds 3 tabs, all tagged Work; 0 crash markers. -GradeLog <log> grades a saved log's rows only.
# -Group adds the everyday path, Close group then Ctrl+Shift+T (a GROUP entry, the same rebuild), with REAL keys --
# so only when <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE before the launch (a person starting it passes
# -IdleMinutes 0 and lets go of the mouse); else it is SKIPPED. On W3, back on Work: "E18 g4".."E18 g6" opened there
# and grouped by the extension ("E18.1 second" -- a group of its own, so this path fails or passes on its own merits
# whatever the window path did to the first), "E18 g4" clicked (guarded, as check-e15d3-auto.ps1), Alt+Shift+W
# closes the group, "Home" pressed, Ctrl+Shift+T. A pass: the reopen stamped at least 3 tabs Work, the first while W3
# showed Home, and the session file keeps them in Work. Recorded, not graded: whether W3 followed the group to Work
# (Chromium focuses a reopened group of 2+ tabs). E18.2 (LOCAL.md 68) adds, in the same phase: before the close, "E18
# g5" renamed "E18.2 NAMED" (tab menu > Rename tab, typed) and "E18 g6" anchored (tab menu > Anchor > Anchor to this page)
# -- after the reopen the name is restored onto the rebuilt tab ("restored custom title"; MSAA cannot show it: a
# tab's accessible name is its page's title), and after the quit the session file keeps
# the group's 1 anchor and the name; the same group then closed and reopened WITHOUT leaving Work -- a pass: it comes
# back in the order it was drawn in before the close (patch 42 inserts each new tab at the top of the list, so a group
# reopened into the workspace on screen may come back reversed); then "E18 g7" alone as a ONE-tab group ("E18.2 single"), closed and reopened from
# Home -- a pass: W3 follows it to Work (g7 drawn), its tab tagged Work after the quit.
# Run it in its own process (pwsh -File): it compiles a C# type that a second script in one session would reuse.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$prof   = "$ws\testprofile-$Tag$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$log    = if ($GradeLog) { $GradeLog } elseif ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise.log" } else { "$ws\$Tag-run.log" }
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$grouped = @("g1", "g2", "g3")
$second = @("g4", "g5", "g6")
$named  = "E18.2 NAMED"
$ins    = "tab inserted at index \d+ -> workspace '([^']*)' \(active '([^']*)'\)"
$seen   = [ordered]@{}
$script:failed = 0
$script:bpid = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name" } else { Say "FAIL  $name"; $script:failed++ } }
function Skip([string]$name) { Say "SKIP  $name (-GradeLog: seen only during a run)" }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 30) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    $false
}
function Running { [bool]($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name) { "$(Msaa $h @('-Name', $name, '-Role', 0x2B))" }
# Every MSAA node of window `h`, one walk: name, role, box (physical pixels), and whether it is shown (not INVISIBLE,
# a box with size).
function Nodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Rect") | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); l = [int]$Matches[4]; t = [int]$Matches[5]
                               w = [int]$Matches[6]; h = [int]$Matches[7]; shown = (-not $Matches[3]) -and [int]$Matches[6] -gt 0 -and [int]$Matches[7] -gt 0 }
        }
    })
}
# The tabs drawn in window `h`: shown MSAA page tabs.
function DrawnTabs([IntPtr]$h) { @(Nodes $h | Where-Object { $_.role -eq 0x25 -and $_.shown }) }
# Whether drawn tab `t` is page "E18 <name>": MSAA may add a state ("<title> - Pinned"), and a tab that never loaded
# is named by its address.
function IsPage($t, [string]$name) { $t.name -eq "E18 $name" -or $t.name.StartsWith("E18 $name - ") -or $t.name -like "*/$name.html*" }
# The pages among `names` drawn as tabs of window `h`.
function ShownPages([IntPtr]$h, [string[]]$names) { $tabs = DrawnTabs $h; @($names | Where-Object { $nm = $_; @($tabs | Where-Object { IsPage $_ $nm }).Count }) }
function Url([string]$n) { "http://127.0.0.1:$($script:srv.port)/$n.html" }
# -Group's real input, guarded: a click only with W3 under the point on the user's unlocked desktop (E18Input), keys
# only to the browser's window in front.
function ClickPage([IntPtr]$h, [string]$name, [switch]$Right) {
    $b = @(DrawnTabs $h | Where-Object { IsPage $_ $name }) | Select-Object -First 1
    if (-not $b) { return "no 'E18 $name' tab drawn" }
    [E18Input]::Click($h, $b.l + [int]($b.w / 2), $b.t + [int]($b.h / 2), $Right.IsPresent)
}
function Keys([string]$k) { if ([E181Fg]::Pid() -eq $script:bpid) { [System.Windows.Forms.SendKeys]::SendWait($k); "sent" } else { "not sent: the window in front is not the browser's" } }
# The first shown node matching `re` in the browser's other windows (a context menu, its submenu), pressed through MSAA;
# polled, menus take a moment.
function MenuPress([IntPtr]$main, [string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    "nothing matching '$re' in a menu"
}
# Close the group of page `page` (clicked, then Alt+Shift+W -- Close group, IDC_CLOSE_TAB_GROUP in accelerator_table.cc),
# switch W3 to Home, Ctrl+Shift+T; waits for `n` inserts. Facts under "<k>.closed" and "<k>.home".
function CloseAndReopen([IntPtr]$h, [string]$page, [int]$n, [string]$k) {
    $r = ClickPage $h $page
    $c = Count '\[workspaces\] removed \d+ tab'
    Say "$k. W3 'E18 $page': $r; Alt+Shift+W: $(if ($r -eq 'clicked') { Keys '%+w' } else { 'not sent' })"
    $seen["$k.closed"] = WaitLog '\[workspaces\] removed \d+ tab' ($c + 1) 15
    $c = Count "pins: drew \d+ row\(s\) of 'default'"
    Say "   W3 'Home': $(Press $h 'Home')"
    $seen["$k.home"] = WaitLog "pins: drew \d+ row\(s\) of 'default'" ($c + 1) 15
    $c = Count $ins
    Say "   Ctrl+Shift+T: $([E18Input]::Keys([uint32]$script:bpid, $true, 0x54))"
    $null = WaitLog $ins ($c + $n) 30
    Start-Sleep (3 * $slow)
}
# A PNG of window `h`'s client area: the names the list DRAWS, which MSAA cannot report (a tab's accessible name is
# its page's title, renamed or not) -- read by eye. E18Input.Client also makes this thread DPI-aware (physical pixels).
function Shot([IntPtr]$h, [string]$path) {
    Add-Type -AssemblyName System.Drawing
    $c = [E18Input]::Client($h)
    $bmp = New-Object System.Drawing.Bitmap ([int]$c[2]), ([int]$c[3])
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen([int]$c[0], [int]$c[1], 0, 0, $bmp.Size); $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $g.Dispose(); $bmp.Dispose() }
    $path
}
# The second group's tabs as drawn in window `h`, top to bottom (MSAA names a tab by its page's title, renamed or not).
function SecondOrder([IntPtr]$h) {
    @(DrawnTabs $h | ForEach-Object {
        $t = $_
        $label = @($second | Where-Object { IsPage $t $_ }) | Select-Object -First 1
        if ($label) { [pscustomobject]@{ label = $label; top = $t.t } }
    } | Sort-Object top | ForEach-Object { $_.label }) -join ","
}
function GroupPhase([IntPtr]$h) {
    if (-not ("E181Fg" -as [type])) {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class E181Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }'
    }
    # A group of its own, so this path is graded whatever the window path did to the first one.
    $c = Count "-> workspace '$work' \(active '$work'\)"
    Start-Process $exe -ArgumentList (@("--user-data-dir=$prof") + @($second | ForEach-Object { Url $_ })) | Out-Null
    $seen.second = WaitLog "E181-EXT grouped second 3 tab" 1 60
    $seen.secondInWork = (Count "-> workspace '$work' \(active '$work'\)") - $c
    # E18.2: one tab renamed, another anchored, from the tab menu -- both must come back with the group.
    $r = ClickPage $h "g5" -Right
    $r += "; " + (MenuPress $h '^Rename tab')
    Start-Sleep -Milliseconds (800 * $slow)
    $r += "; " + (Keys "^a") + ", " + (Keys "$named{ENTER}")
    Say "4. W3 'E18 g5' renamed '$named': $r"
    $seen.renamed = WaitLog "custom title at index \d+ -> '$([regex]::Escape($named))'" 1 10
    $r = (ClickPage $h "g6" -Right) + "; " + (MenuPress $h '^Anchor$') + "; " + (MenuPress $h '^Anchor to this page(?! instead)')
    Say "5. W3 'E18 g6' anchored: $r"
    $seen.anchored = WaitLog "anchor at index \d+ -> 'http[^']*/g6\.html'" 1 10
    CloseAndReopen $h "g4" 3 "6"
    $seen.followed = @(ShownPages $h @("g4", "g6"))
    $seen.shot = Shot $h "$ws\$Tag$(if ($OutDir -eq 'Dcheck') { '-dcheck' })-reopened.png"
    # The same group closed and reopened again WITHOUT leaving Work: a group reopened into the workspace on screen
    # (patch 42 puts each new tab at the top of the list -- reversed?). Its order as drawn, before and after.
    $seen.order0 = SecondOrder $h
    $c = Count '\[workspaces\] removed \d+ tab'
    $r = ClickPage $h "g4"
    Say "6b. W3 'E18 g4' (W3 on Work): $r; Alt+Shift+W: $(if ($r -eq 'clicked') { Keys '%+w' } else { 'not sent' })"
    $seen['6b.closed'] = WaitLog '\[workspaces\] removed \d+ tab' ($c + 1) 15
    $c = Count $ins
    Say "    Ctrl+Shift+T: $([E18Input]::Keys([uint32]$script:bpid, $true, 0x54))"
    $null = WaitLog $ins ($c + 3) 30
    Start-Sleep (3 * $slow)
    $seen.order1 = SecondOrder $h
    # E18.2: a group of ONE tab -- no second tab whose reopen call would pull the window after it.
    $c = Count "-> workspace '$work' \(active '$work'\)"
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "g7")) | Out-Null
    $seen.single = WaitLog "E181-EXT grouped single 1 tab" 1 60
    $seen.singleInWork = (Count "-> workspace '$work' \(active '$work'\)") - $c
    CloseAndReopen $h "g7" 1 "7"
    $seen.singleFollowed = @(ShownPages $h @("g7"))
}

if (-not $GradeLog) {
    # ==== the run =================================================================================================
    if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
    if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
    # Patch 58's own log text: in this build or not. Before the fix it is not, and this check is expected to FAIL.
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'saved group reopened into workspace')>=0 else 1)" "$bin\chrome.dll"
    $has58 = $LASTEXITCODE -eq 0
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'rebuilt tab took its closed tab')>=0 else 1)" "$bin\chrome.dll"
    Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($has58) { 'WITH' } else { 'WITHOUT' }) patch 58, $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 59"
    E18InputType
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
    Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    # The gate before the launch: once the fork browser runs, e17-pc-free.ps1 answers BUSY by design.
    if ($Group) { $seen.free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"; Say "-Group gate: $($seen.free)" }
    $script:srv = ServePages "$ws\$Tag-pages" ($grouped + "go" + $second + "g7")
    if (-not $script:srv.ok) { Abort "the local pages were not served" }
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    try {
        # --vmodule: TabGroupSyncServiceImpl's VLOG(2) lines (AddGroup, OpenTabGroup), the saved-group branch's proof.
        $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--vmodule=tab_group_sync_service_impl=2", "--helium-workspaces-log-addresses", "--no-first-run", "--no-default-browser-check", "--load-extension=$here\e181-ext")).Id
        $w1 = [IntPtr]::Zero; $t0 = Get-Date
        while ($w1 -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $w1 = $p.MainWindowHandle } }
        if ($w1 -eq [IntPtr]::Zero) { throw "no browser window" }
        $null = WaitLog "pins: drew \d+ row\(s\) of 'default'"
        Say "1. W1 'Work': $(Press $w1 'Work')"
        $seen.work = WaitLog "pins: drew \d+ row\(s\) of '$work'" 1 15
        $c = Count "-> workspace '$work' \(active '$work'\)"
        Start-Process $exe -ArgumentList (@("--user-data-dir=$prof") + @($grouped | ForEach-Object { Url $_ })) | Out-Null
        $seen.grouped = WaitLog "E181-EXT (grouped 3 tab|FAIL)" 1 60
        $seen.inWork = (Count "-> workspace '$work' \(active '$work'\)") - $c
        $c = Count "pins: drew \d+ row\(s\) of 'default'"
        Say "2. W1 'Home': $(Press $w1 'Home')"
        $seen.home = WaitLog "pins: drew \d+ row\(s\) of 'default'" ($c + 1) 15
        # Opened only once W1 shows Home: the extension opens W2 on seeing it, so W2 and W3 start on Home.
        Start-Process $exe -ArgumentList @("--user-data-dir=$prof", (Url "go")) | Out-Null
        $null = WaitLog "E181-EXT (restored window|FAIL)" 1 120
        # The rebuilt tabs load in the background; then the inserts hold still.
        $n0 = -1; $t0 = Get-Date
        while (((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { Start-Sleep 3; $n = Count $ins; if ($n -eq $n0) { break }; $n0 = $n }
        Start-Sleep (5 * $slow)
        # W3 is the window drawing "E18 go" (W1's selected Home tab); W2 holds a New Tab page only.
        $w3 = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { (ShownPages $_ @("go")).Count }) | Select-Object -First 1
        $seen.w3 = [bool]$w3
        if ($w3) {
            $seen.onHome = @(ShownPages $w3 $grouped)
            $c = Count "pins: drew \d+ row\(s\) of '$work'"
            Say "3. W3 'Work': $(Press $w3 'Work')"
            $seen.w3work = WaitLog "pins: drew \d+ row\(s\) of '$work'" ($c + 1) 15
            Start-Sleep (2 * $slow)
            $seen.onWork = @(ShownPages $w3 $grouped)
            if ($Group -and $seen.free -like "FREE*") { GroupPhase $w3 }
        }
    } catch {
        Say "ERROR: $_"
    } finally {
        # W3 closed LAST: a window closed while another is open goes to Recently Closed, not into the session file.
        if (Running) {
            foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { if ($h -ne $w3) { [E18Input]::CloseWindow($h) } }
            $t0 = Get-Date
            while ((Running) -and @([E18Input]::Windows([uint32]$script:bpid)).Count -gt 1 -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1 }
            foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) }
            $t0 = Get-Date
            while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { Start-Sleep 1 }
            if (Running) { Say "(force-stopped: a throwaway profile)"; Stop-Process -Id $script:bpid -Force }
        }
        $t0 = Get-Date
        while (@(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }).Count -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1 }
        Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue
    }
}

# ---- grading ----------------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $log) -or (Get-Item -LiteralPath $log).Length -eq 0) { Abort "$log missing or EMPTY -- nothing to grade" }
Say ""
$lines = @(Get-Content -LiteralPath $log)
$lines | Select-String 'E181-EXT (.*?)("|$)' | ForEach-Object { Say "      extension: $($_.Matches[0].Groups[1].Value)" }
if ($GradeLog) { Skip "setup: W1 on Work, the three pages opened there and grouped" }
else { Verdict "setup: W1 on Work, the three pages opened there ($($seen.inWork) stamped Work) and grouped" ($seen.work -and $seen.inWork -ge 3 -and $seen.grouped -and (Count "E181-EXT grouped 3 tab") -eq 1) }
Verdict "setup: W1 closed and reopened from Recently Closed" ((Count "E181-EXT restored window") -eq 1)
$opens = @($lines | Select-String "\[workspaces\] a window opens on workspace '([^']*)'" | ForEach-Object { $_.Matches[0].Groups[1].Value })
Verdict "setup: W1, W2 and W3 each opened on Home (opened on: $($opens -join ', '))" ($opens.Count -eq 3 -and @($opens | Where-Object { $_ -ne 'default' }).Count -eq 0)
# "workspace|on screen" for each insert line of `seg`, in order.
function Inserts($seg) { @($seg | Select-String $ins | ForEach-Object { "$($_.Matches[0].Groups[1].Value)|$($_.Matches[0].Groups[2].Value)" }) }
function Pretty($pairs) { (@($pairs) | ForEach-Object { $_ -replace [regex]::Escape($work), 'Work' -replace 'default', 'Home' }) -join ', ' }
$reOpen = 'tab_group_sync_service_impl\.cc[(:]\d+\)?\] OpenTabGroup'
# The rebuild's first tab: the first insert after the segment's "OpenTabGroup" line (where Chromium's rebuild starts,
# whatever else the restore puts first); a log without --vmodule falls back to the segment's first insert.
function FirstRebuilt($seg) {
    $at = -1; for ($i = 0; $i -lt $seg.Count; $i++) { if ($seg[$i] -match $reOpen) { $at = $i; break } }
    @(Inserts $(if ($at -ge 0) { $seg[$at..($seg.Count - 1)] } else { $seg })) | Select-Object -First 1
}
# The window reopen: from W1's close -- the browser's first "removed" line -- to the extension's "restored window"
# line, logged after the restore returned and before step 3 (else to the next removal). The extension's lines bound
# it only from above: a console message reaches the log late, after the inserts it announces.
$cuts = @(for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '\[workspaces\] removed \d+ tab') { $i } })
$end = if ($cuts.Count -gt 1) { $cuts[1] } else { $lines.Count - 1 }
if ($cuts.Count) { for ($i = $cuts[0]; $i -lt $end; $i++) { if ($lines[$i] -match 'E181-EXT restored window') { $end = $i; break } } }
$seg = @(if ($cuts.Count) { $lines[$cuts[0]..$end] })
$back = Inserts $seg
Say "      reopen: $($back.Count) tab(s) inserted, in order: $(Pretty $back) (workspace|on screen)"
Say "      $(@($seg | Select-String 'saved group reopened into workspace').Count) line(s) of patch 58 ('saved group reopened into workspace')"
$rebuilt = @($seg | Select-String $reOpen).Count
if ($GradeLog -and -not @($lines | Select-String 'tab_group_sync_service_impl\.cc').Count) { Skip "the reopen rebuilt the group from Chromium's saved-group model (a log without --vmodule)" }
else { Verdict "the reopen rebuilt the group from Chromium's saved-group model ($rebuilt 'OpenTabGroup' line(s))" ($rebuilt -ge 1) }
$inWork = @($back | Where-Object { $_ -like "$work|*" }).Count
Verdict "the reopen stamped at least 3 tabs Work (got $inWork)" ($inWork -ge 3)
$first = FirstRebuilt $seg
Verdict "the rebuilt group's first tab was stamped Work while W3 showed Home (got $(if ($first) { Pretty $first } else { 'nothing' }))" ($first -eq "$work|default")
if ($GradeLog) { Skip "W3 on Home draws none of the group's tabs"; Skip "W3 on Work draws all three"; Skip "after the quit the session file's 'E18.1 group' holds 3 tabs, all tagged Work" }
else {
    Verdict "W3 on Home draws none of the group's tabs (drew: $(@($seen.onHome) -join ', '))" ($seen.w3 -and @($seen.onHome).Count -eq 0)
    Verdict "W3 on Work draws all three (drew: $(@($seen.onWork) -join ', '))" ($seen.w3 -and $seen.w3work -and @($seen.onWork).Count -eq 3)
    $sess = @(Get-ChildItem -LiteralPath "$prof\Default\Sessions" -Filter "Session_*" -EA SilentlyContinue | Sort-Object LastWriteTime) | Select-Object -Last 1
    $tags = if ($sess) { & python "$here\session-tags.py" $sess.FullName | ConvertFrom-Json }
    $g = if ($tags) { $tags.groups.'E18.1 group' }
    Say "      session file: $(if ($tags) { $tags.groups | ConvertTo-Json -Compress } else { 'none' })"
    Verdict "after the quit the session file's 'E18.1 group' holds 3 tabs, all tagged Work" ($g -and [int]$g.$work -eq 3 -and @($g.PSObject.Properties).Count -eq 1)
}
if ($Group -and ($GradeLog -or $seen.free -notlike "FREE*" -or -not $seen.w3)) { Say "SKIP  -Group: Close group, then Ctrl+Shift+T from Home (gate: $(if ($GradeLog) { '-GradeLog' } else { $seen.free }))" }
elseif ($Group) {
    # Removal k is a group's close (1: the 3-tab group from Home, 2: the same group again from Work, 3: the 1-tab
    # group); its reopen runs to the next removal.
    function Seg([int]$k) { @(if ($cuts.Count -gt $k) { $lines[$cuts[$k]..$(if ($cuts.Count -gt $k + 1) { $cuts[$k + 1] } else { $lines.Count - 1 })] }) }
    $seg2 = Seg 1
    $back2 = Inserts $seg2
    $first2 = FirstRebuilt $seg2
    Say "      Close group reopen: $(Pretty $back2) (workspace|on screen)"
    Verdict "Close group setup: 'E18 g4'..'E18 g6' opened in W3 on Work ($($seen.secondInWork) stamped Work) and grouped" ($seen.second -and $seen.secondInWork -ge 3)
    Verdict "Close group setup: 'E18 g5' renamed '$named' and 'E18 g6' anchored, from the tab menu" ($seen.renamed -and $seen.anchored)
    Verdict "Close group: Alt+Shift+W closed the 3-tab group, W3 then showed Home" ($seen['6.closed'] -and $cuts.Count -gt 1 -and $lines[$cuts[1]] -match 'removed 3 tab' -and $seen['6.home'])
    Verdict "Close group: Ctrl+Shift+T stamped at least 3 tabs Work, the first while W3 showed Home" (@($back2 | Where-Object { $_ -like "$work|*" }).Count -ge 3 -and $first2 -eq "$work|default")
    Say "      after it W3 draws: $(@($seen.followed) -join ', ') -- $(if (@($seen.followed).Count -eq 2) { 'it followed the group to Work' } else { 'it stayed on Home' }) (recorded, not graded)"
    # Logged, not read through MSAA: a tab's accessible name is the PAGE's title (WindowMetadataController::
    # GetTitleForTab, contents->GetTitle()) and never shows a rename -- what the list draws comes from
    # TabUIHelper::GetTitle, the custom title first. The drawn name is the owner's look (LOCAL.md 68).
    Verdict "Close group (E18.2): the renamed tab came back named '$named' (restored onto the rebuilt tab: logged)" (@($seg2 | Select-String "restored custom title '$([regex]::Escape($named))'").Count -ge 1)
    Say "      the window right after that reopen, for the eye (the renamed tab must read '$named'): $($seen.shot)"
    $g2 = if ($tags) { $tags.groups.'E18.1 second' }
    Verdict "Close group: after the quit the session file's 'E18.1 second' holds 3 tabs, all tagged Work" ($g2 -and [int]$g2.$work -eq 3 -and @($g2.PSObject.Properties).Count -eq 1)
    Say "      session file: anchored $(if ($tags) { $tags.anchored | ConvertTo-Json -Compress }), named $(if ($tags) { $tags.named | ConvertTo-Json -Compress })"
    Verdict "Close group (E18.2): after the quit 'E18.1 second' keeps 1 anchored tab and the name '$named'" ($tags -and [int]$tags.anchored.'E18.1 second' -eq 1 -and @($tags.named.'E18.1 second') -contains $named)
    Say "      same-workspace reopen (W3 stays on Work): $(Pretty (Inserts (Seg 2))) (workspace|on screen); drawn before the close: $($seen.order0); after the reopen: $($seen.order1)"
    Verdict "same-workspace reopen setup: the group closed again from Work (3 tabs removed)" ($seen['6b.closed'] -and $cuts.Count -gt 2 -and $lines[$cuts[2]] -match 'removed 3 tab' -and @($seen.order0 -split ',').Count -eq 3)
    Verdict "same-workspace reopen: the group came back in the order it was closed in ($($seen.order0) -> $($seen.order1))" ($seen.order0 -and $seen.order1 -eq $seen.order0)
    $seg3 = Seg 3
    Say "      1-tab group reopen: $(Pretty (Inserts $seg3)) (workspace|on screen)"
    Verdict "1-tab group setup: 'E18 g7' opened in W3 on Work, grouped alone; Alt+Shift+W closed it, W3 then showed Home" ($seen.single -and $seen.singleInWork -ge 1 -and $seen['7.closed'] -and $cuts.Count -gt 3 -and $lines[$cuts[3]] -match 'removed 1 tab' -and $seen['7.home'])
    Verdict "1-tab group (E18.2): Ctrl+Shift+T from Home pulled W3 to Work -- 'E18 g7' drawn (drew: $(@($seen.singleFollowed) -join ', '))" (@($seen.singleFollowed).Count -eq 1)
    $g3 = if ($tags) { $tags.groups.'E18.2 single' }
    Verdict "1-tab group: after the quit 'E18.2 single' holds 1 tab, tagged Work" ($g3 -and [int]$g3.$work -eq 1 -and @($g3.PSObject.Properties).Count -eq 1)
}
$markers = @($lines | Select-String -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|dangling|NOTREACHED').Count
Verdict "0 crash markers ($markers)" ($markers -eq 0)
if ($script:failed) { Say "$($script:failed) check(s) FAILED"; exit 1 } else { Say "ALL PASS"; exit 0 }
