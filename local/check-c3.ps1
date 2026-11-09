param([ValidateSet("Default", "Dcheck")][string]$OutDir = "Default", [string]$Tag = "c3", [double]$IdleMinutes = 15)
# C3 + C17 + C15 + C8 (patch 71), on a throwaway copy of the smoke profile (Work holds Example A, "Smoke folder" (open:
# Wikipedia, Renamed C), "Closed folder" (Hidden), Example D; Sessions emptied), with a closed "Big folder" of 16 pages
# added to Work before the start. Real clicks, two real drags and keys -- so it starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (a person starting it passes -IdleMinutes 0 and lets go of the mouse).
# Every step runs in Work (Shift+Alt+2) unless it says otherwise.
#   C17  "Smoke folder"'s menu: Copy links puts its two addresses on the clipboard (the clipboard's text is saved
#        first and put back at the end); Sort by name logs; Undo sort is offered then and logs; Open all opens both
#        pages with no confirm; Close all closes both. "Big folder"'s Open all asks first (16 > 15): Cancel opens
#        none, "Open all" opens the 16.
#   C3   "Example D" pressed (open, in front), its menu's Move to workspace > Canary: the row and its page go;
#        Canary (Shift+Alt+3) then shows two "Example D" rows (its own and the moved one).
#   C15  the section's header "Work" (a heading, MSAA 0x14 -- the bar's chip of that name is a push button) pressed
#        folds the card: no "Example A" row; with Example A open and in front the folded card still shows its row;
#        pressed again it unfolds.
#   C8   "Example A" dragged and held over "Closed folder": the folder opens mid-drag, the drop lands in it and it
#        stays open; "Wikipedia" held over "Big folder" and let go where it started: that folder closes again.
# A pass needs every row and 0 crash markers. Run it in its own process (pwsh -File): it compiles C# types.
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$OutDir"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$suffix = "$(if ($OutDir -eq 'Dcheck') { '-dcheck' })"
$prof   = "$ws\testprofile-$Tag$suffix"
$log    = if ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise.log" } else { "$ws\$Tag-run.log" }
$work   = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$slow   = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$script:failed = 0; $script:passed = 0; $script:bpid = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $log)) { return 0 }; @(Select-String -LiteralPath $log -Pattern $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
function Last([string]$re) { if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -Pattern $re | Select-Object -Last 1 | ForEach-Object { $_.Matches[0] }) } }
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role = 0x24) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
# Every MSAA node of window `h`: name, role, box (physical pixels), shown (not INVISIBLE, a box with size).
function Nodes([IntPtr]$h) {
    @(Msaa $h @("-List", "-Rect") | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); l = [int]$Matches[4]; t = [int]$Matches[5]
                               w = [int]$Matches[6]; h = [int]$Matches[7]; shown = (-not $Matches[3]) -and [int]$Matches[6] -gt 0 -and [int]$Matches[7] -gt 0 }
        }
    })
}
function Shown([IntPtr]$h, [string]$name, [int]$role) { @(Nodes $h | Where-Object { $_.shown -and $_.name -eq $name -and $_.role -eq $role }) }
# The pinned rows drawn, top to bottom (MSAA lists views in the order they were added, not drawn).
function Rows([IntPtr]$h) { @(Nodes $h | Where-Object { $_.shown -and $_.role -eq 0x24 } | Sort-Object t) }
# Keys to the browser's window in front, through SendKeys ("%+2" is Shift+Alt+2) -- never to another window.
function Keys([string]$k) {
    if ([C3Fg]::Pid() -ne $script:bpid) { return "not sent: the window in front is not the browser's" }
    [System.Windows.Forms.SendKeys]::SendWait($k); Start-Sleep -Milliseconds (500 * $slow); "sent"
}
# A right click on row `name` (guarded), then the names of the menu that opened.
function RowMenu([IntPtr]$h, [string]$name) {
    $r = @(Shown $h $name 0x24) | Select-Object -Last 1
    if (-not $r) { return [pscustomobject]@{ result = "no '$name' row drawn"; items = @() } }
    $c = [E18Input]::Click($h, $r.l + [int]($r.w / 3), $r.t + [int]($r.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $items = @(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $h)) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } })
    [pscustomobject]@{ result = $c; items = $items }
}
# The first shown node matching `re` in the browser's other windows (a menu, a submenu, a dialog), pressed via MSAA.
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
function OtherNames([IntPtr]$main) { @(foreach ($w in [E18Input]::Others([uint32]$script:bpid, $main)) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
# Row `name`'s menu, then its item matching `re` pressed; a menu left open (no such item) is closed with Escape.
function MenuPress([IntPtr]$h, [string]$name, [string]$re) {
    $m = RowMenu $h $name
    $r = OtherPress $h $re
    if ($r -like "nothing matching*") { $null = Keys "{ESC}" }
    "$($m.result); $r"
}
# Folder `id`'s row ids in Work as saved -- the file is written 2.5 s after a change.
function SavedOrder([string]$id) {
    Start-Sleep (4 * $slow)
    $d = Get-Content -Raw -Encoding UTF8 -LiteralPath "$prof\Default\Workspace Pins" | ConvertFrom-Json
    @(@($d.workspaces.$work | Where-Object { $_.id -eq $id }).children | ForEach-Object { $_.id }) -join ","
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
& python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(b'the drag goes on over the rebuilt rows')>=0 else 1)" "$bin\chrome.dll"
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 71"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class C3Fg { [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid); public static uint Pid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; } }'
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
# "Big folder" (big1, closed) of 16 pages at the end of Work: above Open all's ask (15). Written as UTF-8, its version
# (1) kept: a pre-E19 file, whose splits the browser repairs once from Arc's file, harmlessly.
& python -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); d['workspaces'][sys.argv[2]].append({'type':'folder','id':'big1','title':'Big folder','open':False,'children':[{'type':'item','id':'big1-%d'%i,'title':'Big %d'%i,'url':'https://example.com/?big=%d'%i} for i in range(1,17)]}); open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins" $work
if ($LASTEXITCODE -ne 0) { Abort "Big folder was not added to $prof's pins" }
# ponytail: the clipboard's text only -- a picture on it is not put back.
$script:clip = Get-Clipboard -Raw
Remove-Item -LiteralPath $log -EA SilentlyContinue
try {
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check")).Id
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $main = $p.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of 'default'" 1 30
    [E18Input]::Place($main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $drew = "pins: drew \d+ row\(s\) of '$work'"
    $c = Count $drew
    Say "Shift+Alt+2 (Work): $(Keys '%+2')"
    if (-not (WaitLog $drew ($c + 1) 10)) { throw "Work was not shown" }
    Start-Sleep (2 * $slow)

    # C17: the folder menu's four actions (and Undo sort).
    $r = MenuPress $main "Smoke folder" '^Copy links$'
    $ok = WaitLog "pins: copied 2 link\(s\) of folder 'f1'" 1 10
    $links = @("$(Get-Clipboard -Raw)" -split "\r?\n" | Where-Object { $_ })
    Verdict "C17a Copy links on 'Smoke folder' puts its 2 addresses on the clipboard ($r; logged: $ok; clipboard: $($links -join ' | '))" ($ok -and ($links -join " ") -eq "https://en.wikipedia.org/ https://github.com/")
    $r = MenuPress $main "Smoke folder" '^Sort by name$'
    $ok = WaitLog "pins: sorted folder 'f1' \(2 row\(s\)\)" 1 10
    # The drawn names: "Renamed C" (c1, its own name) before "Wikipedia" (b1); the seed has them the other way.
    $order = SavedOrder "f1"
    Verdict "C17b Sort by name on 'Smoke folder' puts 'Renamed C' first ($r; logged: $ok; saved: $order, want c1,b1)" ($ok -and $order -eq "c1,b1")
    $m = RowMenu $main "Smoke folder"
    $offered = $m.items -contains "Undo sort"
    if ($offered) {
        $r = OtherPress $main '^Undo sort$'
        $ok = WaitLog "pins: undid the sort of folder 'f1'" 1 10
    } else {
        $null = Keys "{ESC}"; $ok = $false
    }
    $back = SavedOrder "f1"
    Verdict "C17c Undo sort is on the folder's menu after the sort and puts the old order back (offered: $offered; $r; logged: $ok; saved: $back, want b1,c1)" ($offered -and $ok -and $back -eq "b1,c1")
    $c = Count $drew
    $r = MenuPress $main "Smoke folder" '^Open all$'
    $ok = WaitLog "pins: opened 2 page\(s\) of folder 'f1'" 1 15
    $null = WaitLog $drew ($c + 1) 10
    Start-Sleep (1 * $slow)
    $asked = Count "confirm asked: open all of folder 'f1'"
    $x = @(Nodes $main | Where-Object { $_.shown -and $_.name -eq "Close page" -and $_.role -eq 0x2B }).Count
    Verdict "C17d Open all on 'Smoke folder' opens both pages, no confirm ($r; logged: $ok; asked: $asked; 'Close page' drawn: $x)" ($ok -and $asked -eq 0 -and $x -eq 2)
    # Asked to close, then each page's own close (a page with an unload handler answers later; these never loaded).
    $closedPage = "closed the page of pinned item '(b1|c1)'"
    $c = Count $closedPage
    $r = MenuPress $main "Smoke folder" '^Close all$'
    $ok = WaitLog "pins: closing 2 page\(s\) of folder 'f1'" 1 15
    $both = WaitLog $closedPage ($c + 2) 15
    Verdict "C17e Close all on 'Smoke folder' closes both pages ($r; asked: $ok; each closed: $both)" ($ok -and $both)
    $big = "pins: opened \d+ page\(s\) of folder 'big1'"
    $ask = "confirm asked: open all of folder 'big1', 16 page\(s\)"
    $r = MenuPress $main "Big folder" '^Open all$'
    $asked = WaitLog $ask 1 10
    Start-Sleep (1 * $slow)
    $title = @(OtherNames $main | Where-Object { $_ -like "*Open 16 pages*" }).Count -gt 0
    $c = Count "\[workspaces\] confirm cancelled"
    $r += "; $(OtherPress $main '^Cancel$')"
    $cancelled = WaitLog "\[workspaces\] confirm cancelled" ($c + 1) 10
    Start-Sleep (2 * $slow)
    $none = (Count $big) -eq 0
    $r += "; again: $(MenuPress $main 'Big folder' '^Open all$')"
    $null = WaitLog $ask 2 10
    Start-Sleep (1 * $slow)
    # The confirm's button reads "Open all" too.
    $r += "; confirm: $(OtherPress $main '^Open all$')"
    $ok = WaitLog "pins: opened 16 page\(s\) of folder 'big1'" 1 60
    $d = Last "pins: opened \d+ page\(s\) of folder 'big1' in \d+ ms"
    Verdict "C17f Open all on 'Big folder' asks first (asked: $asked, 'Open 16 pages?': $title), Cancel opens none ($cancelled, none: $none), 'Open all' opens 16 ($r; $(if ($d) { $d.Value } else { 'no opened line' }))" ($asked -and $title -and $cancelled -and $none -and $ok)

    # C3: a row and its open page move to another workspace.
    $r = Press $main "Example D"
    $opened = WaitLog "pins: opened item 'd1'" 1 10
    Start-Sleep (2 * $slow)
    $c = Count $drew
    $m = RowMenu $main "Example D"
    $r += "; $($m.result); $(OtherPress $main '^Move to workspace')"
    Start-Sleep (1 * $slow)
    $r += "; $(OtherPress $main '^Canary$')"
    $moved = WaitLog "pins: moved 'd1' to workspace '$canary', 1 open page\(s\) with it" 1 10
    $retag = WaitLog "\[workspaces\] retagged 1 pinned page\(s\) -> workspace '$canary'" 1 5
    $null = WaitLog $drew ($c + 1) 10
    Start-Sleep (1 * $slow)
    $left = @(Shown $main "Example D" 0x24).Count
    $cd = "pins: drew \d+ row\(s\) of '$canary'"
    $c = Count $cd; $k = Keys '%+3'; $null = WaitLog $cd ($c + 1) 10
    Start-Sleep (2 * $slow)
    $there = @(Shown $main "Example D" 0x24).Count
    $c = Count $drew; $k += "; back: $(Keys '%+2')"; $back = WaitLog $drew ($c + 1) 10
    Start-Sleep (2 * $slow)
    Verdict "C3a 'Example D' (open: $opened) moved to Canary with its page ($r; moved: $moved; retagged: $retag; rows left in Work: $left; in Canary: $there; Shift+Alt+3 $k, Work again: $back)" ($opened -and $moved -and $retag -and $left -eq 0 -and $there -eq 2 -and $back)

    # C15: the header folds the card. Pressed by role: the bar's chip "Work" is a push button (0x2B).
    $fold = "pins: folded '$work'"; $unfold = "pins: unfolded '$work'"
    $c = Count $drew
    $r = Press $main "Work" 0x14
    $ok = WaitLog $fold 1 10
    $null = WaitLog $drew ($c + 1) 10
    Start-Sleep (1 * $slow)
    $a = @(Shown $main "Example A" 0x24).Count
    Verdict "C15a the header 'Work' pressed folds the card ($r; logged: $ok; 'Example A' rows drawn: $a)" ($ok -and $a -eq 0)
    # Folded, Example A has no row to press: unfold, open it (in front), fold again.
    $r = "unfold: $(Press $main 'Work' 0x14)"; $null = WaitLog $unfold 1 10
    Start-Sleep (1 * $slow)
    $r += "; Example A: $(Press $main 'Example A')"; $opened = WaitLog "pins: opened item 'a1'" 1 10
    Start-Sleep (2 * $slow)
    $c = Count $drew
    $r += "; fold: $(Press $main 'Work' 0x14)"; $ok = WaitLog $fold 2 10
    $null = WaitLog $drew ($c + 1) 10
    Start-Sleep (1 * $slow)
    $a = @(Shown $main "Example A" 0x24).Count; $s = @(Shown $main "Smoke folder" 0x24).Count
    Verdict "C15b folded with 'Example A' open and in front: its row alone is drawn, the folded peek ($r; opened: $opened; folded: $ok; 'Example A' rows: $a, 'Smoke folder' rows: $s)" ($opened -and $ok -and $a -eq 1 -and $s -eq 0)
    $c = Count $drew
    $r = Press $main "Work" 0x14
    $ok = WaitLog $unfold 2 10
    $null = WaitLog $drew ($c + 1) 10
    Start-Sleep (1 * $slow)
    $s = @(Shown $main "Smoke folder" 0x24).Count
    Verdict "C15c pressed again the header unfolds the card ($r; logged: $ok; 'Smoke folder' rows: $s)" ($ok -and $s -eq 1)

    # C8: a drag held over a closed folder opens it; dropped elsewhere, it closes again.
    $again = "pins: closed \d+ folder\(s\) a drag had opened"
    $rows = Rows $main
    $a = $rows | Where-Object { $_.name -eq "Example A" } | Select-Object -First 1
    $g = $rows | Where-Object { $_.name -eq "Closed folder" } | Select-Object -First 1
    # The row under "Closed folder" ("Big folder"): where "Hidden" is drawn once the folder opens.
    $n = if ($g) { $rows | Where-Object { $_.t -gt $g.t } | Select-Object -First 1 }
    if ($a -and $g -and $n) {
        $c = Count $again
        $x = $a.l + [int]($a.w / 3)
        $dr = [E18Input]::DragHold($main, $x, $a.t + [int]($a.h / 2), $g.l + [int]($g.w / 3), $g.t + [int]($g.h / 2), 900 * $slow, $x, $n.t + [int]($n.h / 4))
        $opened = WaitLog "pins: a drag opened folder 'g1'" 1 5
        $moved = WaitLog "pins: moved 'a1' before 'h1'" 1 10
        Start-Sleep (2 * $slow)
        $h = @(Shown $main "Hidden" 0x24).Count
        $resumed = Count "pins: the drag goes on over the rebuilt rows"
        Verdict "C8a 'Example A' held over 'Closed folder' opens it, the drop lands in it and it stays open ($dr; opened: $opened; drag resumed: $resumed; moved before 'h1': $moved; 'Hidden' rows: $h; closed again: $((Count $again) - $c))" ($opened -and $moved -and $h -eq 1 -and (Count $again) -eq $c)
    } else {
        Verdict "C8a 'Example A' held over 'Closed folder' opens it (rows: Example A $([bool]$a), Closed folder $([bool]$g), one under it $([bool]$n))" $false
    }
    $rows = Rows $main
    $w = $rows | Where-Object { $_.name -eq "Wikipedia" } | Select-Object -First 1
    $b = $rows | Where-Object { $_.name -eq "Big folder" } | Select-Object -First 1
    if ($w -and $b) {
        $x = $w.l + [int]($w.w / 3); $y = $w.t + [int]($w.h / 2)
        # Let go where it started: over itself, no place -- nothing moves, nothing kept open.
        $dr = [E18Input]::DragHold($main, $x, $y, $b.l + [int]($b.w / 3), $b.t + [int]($b.h / 2), 900 * $slow, $x, $y)
        $opened = WaitLog "pins: a drag opened folder 'big1'" 1 5
        $closed = WaitLog "pins: closed 1 folder\(s\) a drag had opened" 1 10
        Start-Sleep (2 * $slow)
        $kids = @(Shown $main "Big 1" 0x24).Count
        $still = (Count "pins: moved 'b1'") -eq 0
        Verdict "C8b 'Wikipedia' held over 'Big folder' and let go where it started closes the folder again ($dr; opened: $opened; closed again: $closed; 'Big 1' rows: $kids; not moved: $still)" ($opened -and $closed -and $kids -eq 0 -and $still)
    } else {
        Verdict "C8b 'Wikipedia' held over 'Big folder' closes it again (rows: Wikipedia $([bool]$w), Big folder $([bool]$b))" $false
    }
} catch {
    Say "ERROR: $_"; $script:failed++
} finally {
    if ($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) {
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date; while ((Get-Process -Id $script:bpid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
        Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
    }
    if ($null -ne $script:clip) { Set-Clipboard -Value $script:clip }
}
# Case-sensitive, as LOCAL.md grades: a Dcheck exit can dump the histogram
# "Commerce.PriceTracking.DanglingUserSubscriptionCountAtStartup", no crash (LOCAL.md 3968, 7372).
$markers = if (Test-Path -LiteralPath $log) { @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling").Count } else { 0 }
Verdict "Z crash markers in $log : $markers" ($markers -eq 0)
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) verdict=$(if ($script:failed) { 'FAIL' } else { 'PASS' })"
exit [int]($script:failed -gt 0)
