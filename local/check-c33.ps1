param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c33", [double]$IdleMinutes = 15,
      [string[]]$Rows = @())
# C33 (patch 86, <local-path>\Helium-workspace\c33-progress.md): "Snooze tab" on a Today tab's menu files it in the Archive with a
# wake time and closes it; the window used last wakes it at the top of its workspace's Today, unselected; a chip dots
# while a tab woke there unseen; the Archive lists the snoozed under "Snoozed", which Clear... leaves; Ctrl+Shift+T
# undoes a snooze. On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin), the sidebar
# 280 wide. The right-clicks and keys are REAL input (SendInput, guarded): it starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE.
#   pwsh -NoProfile -File local\check-c33.ps1 [-Build Dcheck] [-IdleMinutes 0]
# Launch 1 runs with --helium-workspaces-snooze-test-seconds=30 (every snooze wakes 30 s after it is made):
#   setup  Work: E18 c33a..c33e; Canary: E18 c33c1
#   M1     c33a's menu > "Snooze tab": In 2 / 3 / 5 / 7 / 11 hours (each with its clock time) and Custom; "In 2 hours"
#          pressed: "snooze: 1 of 1 tab(s), waking in 28-30 s", "archived a manual close in Work (snoozed)", c33a gone
#   F1     the archive file: c33a's entry, reason "manual", a wake_at, workspace Work
#   W1     within 60 s: "woke an entry into Work", "woke 1 of 1 due tab(s)"; c33a FIRST in Work's Today; no switch; the
#          entry gone from the file
#   W2     c33c1 snoozed in Canary, then Work shown: it wakes into Canary with no switch, Canary's chip
#          "-> woken"; Canary shown: c33c1 first, the chip "-> none"
#   U1     c33b snoozed, Ctrl+Shift+T at once: c33b back, "a reopened close leaves the archive", no wake in 45 s
#   C1     c33c's menu > Snooze tab > Custom: the box ("custom box for 1 tab(s)"); emptied + Enter: refused, the box
#          still open; "2" + Enter (Minutes): "custom 120 s", "snooze: 1 of 1", c33c gone
# Launch 2 (the switch at 3600 s):
#   A1     C1's snooze, overdue since quit 1, wakes at the start; c33e closed (an ordinary entry); c33d snoozed; the
#          Archive screen: a "Snoozed" heading above the rest, c33d under it; Clear... > All time > Delete: "clear
#          asked, all time (N)" with N the unsnoozed entries, and the file keeps c33d alone
# Between the launches the file's wake_at for c33d is set a minute in the PAST (the browser closed meanwhile).
# Launch 3 (no switch):
#   P1     within 30 s of the start: "woke 1 of 1 due tab(s)", "woke an entry into Work", c33d first in Work's Today
#   Z      0 crash markers in the three logs (case-sensitive, DanglingPtr too)
# A pass needs all 10 verdicts ($total below).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows C1,A1` passes ONE string "C1,A1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = "$ws\helium-windows\build\src\out\$Build"
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$archive = "$prof\Default\Workspace Archive"
$logs    = @(1..3 | ForEach-Object { if ($Build -eq "Dcheck") { "$ws\$Tag-dcheck-exercise$_.log" } else { "$ws\$Tag-run$_.log" } })
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = 10
$switch  = "--helium-workspaces-snooze-test-seconds"
# The contract's lines (c33-progress.md), graded case-sensitively.
$active   = "\[workspaces\] active workspace -> '([^']*)'"
$snoozed  = "\[workspaces\] snooze: (\d+) of (\d+) tab\(s\), waking in (-?\d+) s"
$woke     = "\[workspaces\] snooze: woke (\d+) of (\d+) due tab\(s\)"
function WokeInto([string]$g) { "\[workspaces\] archive: woke an entry into '$g'" }
function Filed([string]$g) { "\[workspaces\] archived a manual close in '$g' \(snoozed\)" }
function Badge([string]$g, [string]$what) { "\[workspaces\] rail badge '$g' -> $what" }
$reopened = "\[workspaces\] archive: a reopened close leaves the archive"
$boxRe    = "\[workspaces\] snooze: custom box for (\d+) tab\(s\)"
$refused  = "\[workspaces\] snooze: custom amount refused"
$custom   = "\[workspaces\] snooze: custom (\d+) s"
$cleared  = "\[workspaces\] archive screen: clear asked, all time \((\d+)\)"

$script:passed = 0; $script:failed = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Grp([string]$re) { $l = @(Lines $re); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }

# ---- MSAA (msaa-press.ps1) and the menus, as check-c4's ------------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A restored page never loaded since is named by its address ("127.0.0.1:<port>/c33e.html") when its title did not
# reach the session file before the quit (a short launch): "E18 c33e" matches that too.
function TabIn($nodes, [string]$title) {
    $page = if ($title -like "E18 *") { "*/$($title.Substring(4)).html" } else { $null }
    @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq $title -or $_.name.StartsWith("$title - ") -or ($page -and $_.name -like $page)) }) | Select-Object -First 1
}
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
function FirstToday { $t = @(Today (Nodes $script:main)); if ($t.Count) { $t[0].name } else { "(none)" } }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
function OtherPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) {
                $r = Press $w $n.name $n.role
                if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
                return "'$($n.name)' $r"
            }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re' (shown: $((@(PopupNames) | Select-Object -First 40) -join ' | '))"
}
# Today tab `title`'s menu (a guarded right-click), then its items matching each of `res` pressed in turn.
function TabMenu([string]$title, [string[]]$res) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no Today tab '$title' drawn" }
    $r = [E18Input]::Click($script:main, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    for ($i = 0; $i -lt $res.Count; $i++) {
        $p = OtherPress $res[$i]
        $r += "; $p"
        if ($p -like "nothing matching*") { NoPopups; break }
        Start-Sleep -Milliseconds (500 * $slow)
    }
    $r
}
# `title` snoozed by its menu's item matching `item` ("In 2 hours"): what happened, and the snooze line's groups.
function Snooze([string]$title, [string]$item = '^In 2 hours \(') {
    $c = Count $snoozed
    $r = TabMenu $title @('^Snooze tab$', $item)
    $null = WaitLog $snoozed ($c + 1) 10
    [pscustomobject]@{ said = $r; line = @(Nth $snoozed $c) }
}
function Go([string]$name, [string]$guid) {
    if (NodeIn (Nodes $script:main) $name 0x14) { return $true }
    $c = Count $active
    $null = Press $script:main $name 0x2B
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Grp $active)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}
function Row([string]$row, [scriptblock]$body) {
    # -Rows C1,A1: only those rows (and the setup); the RESULT then counts fewer verdicts.
    if ($Rows.Count -and $row -ne "setup" -and $Rows -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
}

# ---- the pages, DevTools, the archive file -------------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url "$name.html")))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
}
# The archive file's entries as saved (written 2.5 s after a change).
function Entries { Start-Sleep (4 * $slow); try { @((Get-Content -Raw -Encoding UTF8 -LiteralPath $archive | ConvertFrom-Json).entries) } catch { @() } }
function EntryOf([string]$name) { @(Entries | Where-Object { $_.url -like "*/$name.html" }) | Select-Object -First 1 }

function Launch([string[]]$extra) {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check", "--restore-last-session") + $extra
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
    [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid) $($extra -join ' '), DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log)"
}
function Quit {
    if (-not (Running)) { return "the browser was not running" }
    foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    $closed = -not (Running)
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$(if ($closed) { 'closed' } else { 'NOT closed' })$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "snooze: woke "
Say "build: $Build\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 86"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath (@($archive) + $logs) -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
$script:srv = ServePages $pages @("c33a", "c33b", "c33c", "c33d", "c33e", "c33c1")
if (-not $script:srv.ok) { Abort "the local pages were not served" }

try {
    # ---- launch 1: every snooze wakes 30 s after it is made ----------------------------------------------------
    $script:log = $logs[0]
    Launch @("$switch=30")
    Row "setup" {
        $s = "Canary $(Go 'Canary' $canary)"
        NewTab "c33c1"
        $s += ", Work $(Go 'Work' $work)"
        foreach ($nm in "c33e", "c33d", "c33c", "c33b", "c33a") { NewTab $nm }
        $t = @(Today (Nodes $script:main))
        Verdict "setup ($s): Work's Today $(Names $t)" (@("c33a", "c33b", "c33c", "c33d", "c33e" | Where-Object { TabIn $t "E18 $_" }).Count -eq 5)
    }
    Row "M1" {
        $c = Count $snoozed; $cf = Count (Filed $work)
        $r = TabMenu "E18 c33a" @('^Snooze tab$')
        Start-Sleep -Milliseconds (800 * $slow)
        $items = @(PopupNames)
        $hours = @(2, 3, 5, 7, 11 | Where-Object { $h = $_; @($items | Where-Object { $_ -match "^In $h hours? \(.+\)$" }).Count })
        $p = OtherPress '^In 2 hours \('
        $r += "; $p"
        $null = WaitLog $snoozed ($c + 1) 10; $null = WaitLog (Filed $work) ($cf + 1) 10
        Start-Sleep (1 * $slow)
        $l = @(Nth $snoozed $c)
        $gone = -not (TabIn (Nodes $script:main) "E18 c33a")
        Verdict "M1 c33a's Snooze tab submenu ($r): hours offered $($hours -join ',') (want 2,3,5,7,11), Custom $(@($items -match '^Custom').Count -eq 1); $(if ($l.Count) { "'$($l[0])'" } else { 'no snooze line' }) (want 1 of 1, 28-30 s); filed snoozed +$((Count (Filed $work)) - $cf); c33a gone $gone" (($hours -join ',') -eq "2,3,5,7,11" -and (@($items -match '^Custom').Count -eq 1) -and $l.Count -and $l[1] -eq "1" -and $l[2] -eq "1" -and [int]$l[3] -ge 28 -and [int]$l[3] -le 30 -and (Count (Filed $work)) -eq $cf + 1 -and $gone)
    }
    Row "F1" {
        $e = EntryOf "c33a"
        Verdict "F1 the archive file: c33a's entry $(if ($e) { "reason $($e.reason), wake_at '$($e.wake_at)', workspace $($e.workspace)" } else { 'missing' })" ($e -and $e.reason -eq "manual" -and $e.wake_at -and $e.workspace -eq $work)
    }
    Row "W1" {
        $ca = Count $active
        $ok = (WaitLog (WokeInto $work) 1 60) -and (WaitLog $woke 1 5)
        Start-Sleep (1 * $slow)
        $w = @(Grp $woke); $first = FirstToday; $e = EntryOf "c33a"
        Verdict "W1 the wake on screen: woke into Work $ok, $(if ($w.Count) { "'$($w[0])'" } else { 'no woke line' }); Work's first Today tab '$first' (want E18 c33a); switches +$((Count $active) - $ca); the entry $(if ($e) { 'STILL in the file' } else { 'gone' })" ($ok -and $w.Count -and $w[1] -eq "1" -and $first -eq "E18 c33a" -and (Count $active) -eq $ca -and -not $e)
    }
    Row "W2" {
        $went = Go "Canary" $canary
        $s = Snooze "E18 c33c1"
        $back = Go "Work" $work
        $ca = Count $active; $cw = Count (WokeInto $canary)
        $ok = WaitLog (WokeInto $canary) ($cw + 1) 60
        $dot = WaitLog (Badge $canary "woken") 1 10
        $acts = (Count $active) - $ca
        $shown = Go "Canary" $canary
        $first = FirstToday
        $none = WaitLog (Badge $canary "none") 1 10
        $null = Go "Work" $work
        Verdict "W2 c33c1 snoozed in Canary ($went, $($s.said)), Work shown ($back): woke into Canary $ok with +$acts switch(es); Canary's chip woken $dot; Canary shown ($shown): first '$first' (want E18 c33c1), the chip back to none $none" ($went -and $s.line.Count -and $back -and $ok -and $acts -eq 0 -and $dot -and $shown -and $first -eq "E18 c33c1" -and $none)
    }
    Row "U1" {
        $cr = Count $reopened; $cw = Count $woke
        $s = Snooze "E18 c33b"
        $k = [E18Input]::Keys([uint32]$script:bpid, $true, 0x54)
        $re = WaitLog $reopened ($cr + 1) 10
        Start-Sleep (2 * $slow)
        $back = [bool](TabIn (Nodes $script:main) "E18 c33b")
        Start-Sleep 45
        $later = (Count $woke) - $cw
        Verdict "U1 c33b snoozed ($($s.said)), Ctrl+Shift+T ($k): 'a reopened close leaves the archive' $re, c33b back $back; woke lines in the 45 s after: $later (want 0)" ($s.line.Count -and $re -and $back -and $later -eq 0)
    }
    Row "C1" {
        $cb = Count $boxRe; $cr = Count $refused; $cc = Count $custom; $cs = Count $snoozed
        $r = TabMenu "E18 c33c" @('^Snooze tab$', '^Custom')
        $opened = WaitLog $boxRe ($cb + 1) 10
        Start-Sleep (1 * $slow)
        # The amount's text selected and deleted, then Enter: refused, the box stays.
        $k = "$([E18Input]::Keys([uint32]$script:bpid, $false, 0x41)), $([E18Input]::Tap([uint32]$script:bpid, 0x2E)), $([E18Input]::Tap([uint32]$script:bpid, 0x0D))"
        $ref = WaitLog $refused ($cr + 1) 5
        # "2" and Enter, the unit left at Minutes.
        $k += "; $([E18Input]::Tap([uint32]$script:bpid, 0x32)), $([E18Input]::Tap([uint32]$script:bpid, 0x0D))"
        $ok = (WaitLog $custom ($cc + 1) 5) -and (WaitLog $snoozed ($cs + 1) 10)
        Start-Sleep (1 * $slow)
        $cu = @(Nth $custom $cc); $sl = @(Nth $snoozed $cs)
        $gone = -not (TabIn (Nodes $script:main) "E18 c33c")
        Verdict "C1 Custom ($r): the box $opened; emptied + Enter ($k): refused $ref (the box stayed: the next Enter reached it); '2' Minutes: custom $(if ($cu.Count) { $cu[1] } else { '-' }) s (want 120), $(if ($sl.Count) { "'$($sl[0])'" } else { 'no snooze line' }); c33c gone $gone" ($opened -and $ref -and $ok -and $cu.Count -and $cu[1] -eq "120" -and $sl.Count -and $sl[1] -eq "1" -and $gone)
    }
    Say "quit 1: $(Quit)"

    # ---- launch 2: a snooze that waits an hour, the Archive screen, Clear... -------------------------------------
    $script:log = $logs[1]
    Launch @("$switch=3600")
    Row "A1" {
        # C1's snooze was still waiting at quit 1: overdue now, it wakes at the first look. Waited for, so it cannot
        # change the counts below; and one ordinary close, so Clear... has an unsnoozed entry to count.
        $pre = (WaitLog (WokeInto $work) 1 30) -and (WaitLog $woke 1 5)
        $null = Go "Work" $work
        $t0 = Get-Date
        while (-not (TabIn (Nodes $script:main) "E18 c33d") -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        $drawn = Names (Today (Nodes $script:main))
        $closed = TabMenu "E18 c33e" @('^Close( Ctrl\+W)?$')
        $s = Snooze "E18 c33d"
        $all = @(Entries); $plain = @($all | Where-Object { -not $_.wake_at }).Count
        $p = Press $script:main "Archive" 0x2B
        Start-Sleep (2 * $slow)
        $n = @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } })
        $heads = @($n | Where-Object { $_.role -eq 0x14 -and $_.name -ne "Archive" } | Sort-Object t)
        $sn = @($heads | Where-Object { $_.name -eq "Snoozed" }) | Select-Object -First 1
        $row = @($n | Where-Object { $_.name -like "E18 c33d*" -or $_.name -like "*/c33d.html*" }) | Select-Object -First 1
        $top = $heads.Count -and $heads[0].name -eq "Snoozed"
        $under = $sn -and $row -and $row.t -gt $sn.t -and -not @($heads | Where-Object { $_.t -gt $sn.t -and $_.t -lt $row.t }).Count
        $cc = Count $cleared
        # "Clear" + an ellipsis character: matched by its start. The confirm's question starts with "Delete" too, so
        # its button is matched whole.
        $r = "$(OtherPress '^Clear'); $(OtherPress '^All time$'); $(OtherPress '^Delete$')"
        $null = WaitLog $cleared ($cc + 1) 10
        $c = @(Nth $cleared $cc)
        $left = @(Entries)
        Verdict "A1 C1's overdue snooze woke at the start $pre; Work's Today drawn: $drawn; c33e closed ($closed), c33d snoozed ($($s.said)); the Archive ($p): headings $(Names $heads), Snoozed first $top, c33d under it $under; Clear > All time > Delete ($r): asked for $(if ($c.Count) { $c[1] } else { '-' }) (want $plain, the unsnoozed, 1+); the file keeps $(@($left | ForEach-Object { ($_.url -split '/')[-1] }) -join ', ') (want c33d.html alone)" ($pre -and $s.line.Count -and $plain -ge 1 -and $top -and $under -and $c.Count -and $c[1] -eq "$plain" -and $left.Count -eq 1 -and $left[0].url -like "*/c33d.html" -and $left[0].wake_at)
    }
    Say "quit 2: $(Quit)"

    # ---- between: c33d's wake a minute in the past, the browser closed ---------------------------------------
    $script:log = $logs[2]
    & python -I -c @"
import json, sys, time
p = sys.argv[1]
d = json.load(open(p, encoding='utf-8'))
past = int((time.time() + 11644473600 - 60) * 1000000)
n = 0
for e in d['entries']:
    if e['url'].endswith('/c33d.html'):
        e['wake_at'] = str(past); n += 1
json.dump(d, open(p, 'w', encoding='utf-8'), separators=(',', ':'))
sys.exit(0 if n == 1 else 1)
"@ $archive
    $moved = $LASTEXITCODE -eq 0

    # ---- launch 3: no switch; the wake missed while closed comes at the start -----------------------------------
    Launch @()
    Row "P1" {
        $ok = (WaitLog $woke 1 30) -and (WaitLog (WokeInto $work) 1 5)
        $null = Go "Work" $work
        $w = @(Grp $woke); $first = FirstToday
        Verdict "P1 the wake time put in the past while closed ($moved): $(if ($w.Count) { "'$($w[0])'" } else { 'no woke line' }), into Work $ok; Work's first Today tab '$first' (want E18 c33d)" ($moved -and $ok -and $w.Count -and $w[1] -eq "1" -and $first -eq "E18 c33d")
    }
} catch {
    Say "ERROR (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    $q = Quit
    if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($logs -join ', ') (the last quit: $q): $markers" ($markers -eq 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
exit [int]($verdict -ne "PASS")
