param([switch]$WorkspacesOff,
      [ValidateSet("Default", "Dcheck")][string]$OutDir = "Default",
      [switch]$GradeOnly,
      [string]$Log = "")
# E14c.2's patch 38 (LOCAL.md 42; the hook shrink moved its two hooks, 119), tested with nobody at the keyboard. Its
# first fixture -- testprofile's Recently Closed holding the E14c rehearsal's 3,864-tab window, its 22 saved groups
# open again in the restored one -- had aged out of testprofile by October, and this check then waited on a 31 GB
# Dcheck log all night (119). local\e14c2-ext now builds a small one, as Chromium's own
# TabRestoreTest.RestoreTabGroupFromClosedWindow does, on a throwaway copy of the smoke profile: W1 holds "E18 g1"..
# "E18 g4" (a saved group, "E38 group", g2 and g3 split) and "E18 loose"; W2 opened, W1 closed; the group opened again
# in W2 from the app menu (Tab groups > E38 group > Open group, pressed through MSAA; the menu opened by its button,
# else by a real Alt+F to the browser's window in front) and split again; then W1 reopened by id -- what History >
# Recently closed does, and what Ctrl+Shift+T does when it is the newest entry (both end in the same
# BrowserLiveTabContext::AddRestoredTab).
#  default:        Workspaces on. The open saved group is LEFT where it is (one "left there" per grouped tab: 4), it
#                  is not moved, only the loose tabs are reopened, and nothing crashes.
#  -WorkspacesOff: the E10b dormancy check. Chromium's stock move of the group into the reopened window; it arrives
#                  split, so the split rebuild meets the guard instead of AddToSplitImpl's CHECK; nothing crashes.
# Run it in its own process (pwsh -File): it compiles a C# type that a second script in one session would reuse.
# -GradeOnly re-grades a log. The grader reads events in log order (LOCAL.md 30), from the extension's "restoring"
# line on. A script that does not parse leaves $LASTEXITCODE untouched: read the ALL PASS / FAILED line, not the code.
. "$PSScriptRoot\e18-lib.ps1"
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$off   = $(if ($WorkspacesOff) { "-off" } else { "" })
$tag   = "e14c2-restore" + $off + $(if ($OutDir -eq "Dcheck") { "-dcheck" } else { "" })
$prof  = "$ws\testprofile-$tag"
$smoke = "$ws\testprofile-e15b-smoke"
if (-not $Log) { $Log = if ($OutDir -eq "Dcheck") { "$ws\e14c2-dcheck-exercise$off.log" } else { "$ws\$tag-run.log" } }
$bin   = "$ws\helium-windows\build\src\out\$OutDir"
$exe   = "$bin\chrome.exe"
$patch = "$ws\helium-windows\patches\local\workspaces\38-reopen-leaves-groups.patch"
$pages = @("g1", "g2", "g3", "g4", "loose")
$slow  = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$script:bpid = 0; $script:w2 = [IntPtr]::Zero
# Each pattern's count so far and how far into the log it has read: a poll reads only what the browser wrote since,
# whole lines only (a half-written one waits for the next poll). A Dcheck log can reach GBs (119).
# ponytail: a single line over 4 MB stalls its pattern; no Chromium log line comes near it.
$script:seen = @{}
function Count([string]$re) {
    if (-not (Test-Path -LiteralPath $Log)) { return 0 }
    if (-not $script:seen[$re]) { $script:seen[$re] = @{ pos = 0L; n = 0 } }
    $c = $script:seen[$re]; $buf = [byte[]]::new(4MB)
    $fs = [IO.FileStream]::new($Log, 'Open', 'Read', 'ReadWrite, Delete')
    try {
        while ($true) {
            $null = $fs.Seek($c.pos, 'Begin'); $got = $fs.Read($buf, 0, $buf.Length)
            $end = if ($got) { [Array]::LastIndexOf($buf, [byte]10, $got - 1) } else { -1 }
            if ($end -lt 0) { break }
            $c.n += @(([Text.Encoding]::UTF8.GetString($buf, 0, $end + 1) -split "`n") -match $re).Count
            $c.pos += $end + 1
        }
    } finally { $fs.Dispose() }
    $c.n
}
# Every wait is wall-clock: counting 3 s rounds let a slow Select-String over a huge log stretch "600 s" into hours.
function WaitLog([string]$re, [int]$n = 1, [int]$s = 30) {
    $t0 = Get-Date
    while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    $false
}
function Running { [bool]($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
# The browser's menus: its visible windows that are no browser window.
function Popups { PopupWindows ([uint32]$script:bpid) $script:w2 }
# The first shown node matching `re` in a menu, pressed through MSAA; polled, menus take a moment.
function MenuPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name.Trim())' $(Msaa $w @('-Name', $n.name, '-Role', $n.role))" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re' in a menu"
}
# Tab groups > " E38 group group - Closed" (IDS_GROUP_AX_LABEL_GROUP_MENU_ITEM_FORMAT) > Open group, from W2's app menu.
function OpenFromMenu([IntPtr]$h) {
    $p = [uint32]$script:bpid
    $btn = @(Nodes $h | Where-Object { $_.shown -and $_.role -in 0x2B, 0x39 -and $_.name -match '^(Helium|Chromium)$' }) | Select-Object -First 1
    $r = if ($btn) { "menu button '$($btn.name)' $(Msaa $h @('-Name', $btn.name, '-Role', $btn.role))" } else { "no menu button" }
    Start-Sleep -Milliseconds (800 * $slow)
    if (-not @(Popups).Count) { $r += "; Alt+F $([E18Input]::KeyDown($p, 0x12)) $([E18Input]::Tap($p, 0x46)) $([E18Input]::KeyUp($p, 0x12))"; Start-Sleep -Milliseconds (800 * $slow) }
    $r += "; $(MenuPress '^Tab groups$')"
    foreach ($re in 'E38 group group - Closed$', '^Open group$') { Start-Sleep -Milliseconds (800 * $slow); $r += "; $(MenuPress $re)" }
    $r
}

if (-not $GradeOnly) {
    if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running" -ForegroundColor Red; exit 1 }
    if ((Get-Item "$bin\chrome.exe").LastWriteTime -lt (Get-Item $patch).LastWriteTime) { Write-Host "ABORT: $OutDir\chrome.exe is older than patch 38 (stale binary)" -ForegroundColor Red; exit 1 }
    # siso can skip a relink and leave the old binary in place (LOCAL.md 41): look for patch 38's own string.
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'another window, left there')>=0 else 1)" "$bin\chrome.dll"
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: $OutDir\chrome.dll does not contain patch 38" -ForegroundColor Red; exit 1 }
    E18InputType
    if (Test-Path $prof) { [IO.Directory]::Delete($prof, $true) }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Write-Host "ABORT: the copy of $smoke failed" -ForegroundColor Red; exit 1 }
    Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    & python "$ws\helium\local\set-workspaces-pref.py" $prof --show | Select-Object -Last 1 | Write-Host
    if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }
    if ($WorkspacesOff) {
        & python "$ws\helium\local\set-workspaces-pref.py" $prof false | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: could not switch Workspaces off in the copy" -ForegroundColor Red; exit 1 }
        Write-Host "Workspaces switched OFF in the copy"
    }
    $srv = ServePages "$ws\e14c2-pages" $pages
    if (-not $srv.ok) { Write-Host "ABORT: the local pages were not served" -ForegroundColor Red; exit 1 }
    if (Test-Path $Log) { [IO.File]::Delete($Log) }
    try {
        $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check", "--log-file=`"$Log`"", "--load-extension=$here\e14c2-ext")).Id
        $t0 = Get-Date
        while (-not @([E18Input]::Windows([uint32]$script:bpid)).Count -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        if (-not @([E18Input]::Windows([uint32]$script:bpid)).Count) { throw "no browser window" }
        Start-Sleep (3 * $slow)
        Start-Process $exe -ArgumentList (@("--user-data-dir=$prof") + @($pages | ForEach-Object { "http://127.0.0.1:$($srv.port)/$_.html" })) | Out-Null
        if (-not (WaitLog 'E14C2-EXT (closed window|FAIL)' 1 60) -or (Count 'E14C2-EXT FAIL')) { throw "the extension did not get W1 closed (its lines below)" }
        $t0 = Get-Date
        while (@([E18Input]::Windows([uint32]$script:bpid)).Count -ne 1 -and ((Get-Date) - $t0).TotalSeconds -lt 15 * $slow) { Start-Sleep 1 }
        $wins = @([E18Input]::Windows([uint32]$script:bpid))
        if ($wins.Count -ne 1) { throw "$($wins.Count) browser windows, not W2 alone: W1 did not close" }
        $script:w2 = $wins[0]
        Start-Sleep (2 * $slow)
        Write-Host "W2's app menu: $(OpenFromMenu $script:w2)"
        $null = WaitLog 'E14C2-EXT (restore returned|restore failed|FAIL)' 1 60
        # The window list the extension logs 5 s after the reopen; then the inserts hold still for 10 s.
        $null = WaitLog 'E14C2-EXT window \d+:' 1 30
        $n0 = -1; $t0 = Get-Date
        while (((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { $n = Count 'tab inserted at index'; if ($n -eq $n0) { break }; $n0 = $n; Start-Sleep 10 }
    } catch {
        Write-Host "ERROR: $_"
    } finally {
        # A throwaway profile: every window closed as its X does, then the force stop.
        if (Running) {
            foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) }
            $t0 = Get-Date
            while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { Start-Sleep 1 }
            Write-Host "closed: $(if (Running) { 'NO' } else { 'yes' })"
            if (Running) { Stop-Process -Id $script:bpid -Force; Write-Host "force-stopped" }
        }
        $t0 = Get-Date
        while ((Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 }
        Stop-Process -Id $srv.server.Id -EA SilentlyContinue
    }
}

# ---- grading -------------------------------------------------------------------------------
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$script:failed = 0; $script:inconclusive = $false
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: $Log missing or EMPTY -- nothing to grade" -ForegroundColor Red; exit 1 }
$ev = New-Object System.Collections.Generic.List[object]
# One streamed pass for the events and the crash markers (case-sensitive).
$markers = 0
foreach ($line in [IO.File]::ReadLines($Log)) {
    if ($line -cmatch 'Check failed|FATAL|ReentrancyCheck|dangling|DanglingPtr|NOTREACHED') { $markers++ }
    if     ($line -match "\[workspaces\] removed (\d+) tab\(s\)") { $ev.Add([pscustomobject]@{ K = 'R'; N = [int]$Matches[1] }) }
    elseif ($line -match "\[workspaces\] tab inserted at index") { $ev.Add([pscustomobject]@{ K = 'I' }) }
    elseif ($line -match "\[workspaces\] restore: saved group already open in another window, left there") { $ev.Add([pscustomobject]@{ K = 'L' }) }
    elseif ($line -match "\[workspaces\] restore: split at \d+ and \d+ already in place") { $ev.Add([pscustomobject]@{ K = 'G' }) }
    elseif ($line -match "E14C2-EXT (.*?)(`"|$)") { $ev.Add([pscustomobject]@{ K = 'X'; Text = $Matches[1] }) }
}
Write-Host "`n--- $OutDir, Workspaces $(if ($WorkspacesOff) { 'OFF' } else { 'on' })"
@($ev | Where-Object K -eq 'X') | ForEach-Object { Write-Host "      extension: $($_.Text)" }
# The reopen begins at the extension's "restoring" line: W1's close and the menu's reopen before it are the fixture.
$start = -1; for ($n = 0; $n -lt $ev.Count; $n++) { if ($ev[$n].K -eq 'X' -and $ev[$n].Text -like 'restoring a closed window*') { $start = $n; break } }
if ($start -lt 0) { Write-Host "INCONCLUSIVE: the fixture was not built, the window never reopened (the extension's lines above)" -ForegroundColor DarkYellow; exit 2 }
# .ToArray(): @() around a generic List throws "Argument types do not match" here (found by running this).
$post = if ($start -lt $ev.Count - 1) { @($ev.ToArray()[($start + 1)..($ev.Count - 1)]) } else { @() }
# A removal something is inserted AFTER is a move (the saved group pulled into the reopened window); the final window
# close removes and inserts nothing, so it is never counted.
$lastIns = -1; for ($n = 0; $n -lt $post.Count; $n++) { if ($post[$n].K -eq 'I') { $lastIns = $n } }
$moves = @(for ($n = 0; $n -lt $lastIns; $n++) { if ($post[$n].K -eq 'R') { $post[$n] } })
$left  = @($post | Where-Object K -eq 'L').Count
$guard = @($post | Where-Object K -eq 'G').Count
$ins   = @($post | Where-Object K -eq 'I').Count
$split = [bool](@($ev | Where-Object { $_.K -eq 'X' -and $_.Text -like 'split again: split *' }).Count)
Write-Host "      reopened: $ins tabs inserted; $left grouped tab(s) left in place, $($moves.Count) group(s) moved, split guard $guard time(s)"
Verdict "the closed window was reopened by id ($ins tabs inserted)" ($ins -ge 1)
if ($WorkspacesOff) {
    Verdict "dormant with Workspaces off: no group left in place ($left)" ($left -eq 0)
    Verdict "stock: the open saved group was moved over ($($moves.Count))" ($moves.Count -ge 1)
    if ($split) { Verdict "the split guard fired ($guard) instead of AddToSplitImpl's CHECK" ($guard -ge 1) }
    else { Write-Host "INCONCLUSIVE: the split guard -- the group was not split again in W2 (the extension's lines above)" -ForegroundColor DarkYellow; $script:inconclusive = $true }
} else {
    Verdict "the open saved group was left where it is ($left of 4 grouped tabs left, $($moves.Count) groups moved)" ($left -eq 4 -and $moves.Count -eq 0)
    # Patch 100 (the polish batch, LOCAL.md 129; 119's "loose | New Tab | New Tab"): the reopened window holds its own
    # tabs, the closed window's less the grouped ones left in place -- no stand-in New Tab, which 38 added the moment
    # the window was empty, before its own tabs arrived (Chromium restores a saved group's first tab first).
    $x = @($ev | Where-Object K -eq 'X' | ForEach-Object { $_.Text })
    $closedN = if (($x -join "`n") -match 'restoring a closed window of (\d+) tab') { [int]$Matches[1] } else { -1 }
    $backId  = if (($x -join "`n") -match 'restore returned: window (\d+)') { $Matches[1] } else { "" }
    $strip   = @($x | Where-Object { $_ -like "window ${backId}: *" } | Select-Object -Last 1)
    $own     = if ($strip.Count) { @(($strip[0] -replace '^window \d+: ', '') -split ' \| ').Count } else { -1 }
    Verdict "the reopened window holds its own $($closedN - $left) tab(s), no stand-in New Tab (${own}: $($strip -join ''))" ($closedN -gt 0 -and $own -eq $closedN - $left)
}
Verdict "0 crash markers ($markers)" ($markers -eq 0)
if ($script:failed) { Write-Host "$($script:failed) check(s) FAILED" -ForegroundColor Red; exit 1 }
elseif ($script:inconclusive) { Write-Host "INCONCLUSIVE" -ForegroundColor DarkYellow; exit 2 }
else { Write-Host "ALL PASS" -ForegroundColor Green; exit 0 }
