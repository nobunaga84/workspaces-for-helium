param([string]$OutDir = "Default", [string]$Tag = "e18-auto", [ValidateSet("", "54", "55", "56", "57")][string]$Only = "",
      [switch]$GradeOnly, [double]$IdleMinutes = 15)
# E18 without a person (design 5, "E18 spec"): the four patches' contracts -- their log lines and what MSAA shows --
# graded patch by patch, so a FAIL names its patch; -Only 54|55|56|57 runs one group. Each group starts a throwaway
# copy of the smoke profile (testprofile-e15b-smoke: Home and Work each hold Example A, Smoke folder (open:
# Wikipedia, Renamed C), Closed folder (Hidden), Example D), its Sessions emptied, prefs written beside
# helium.workspaces.enabled while the browser is CLOSED. Rows and buttons are pressed through MSAA (msaa-press.ps1);
# menus, Ctrl+W, the wheel and the drags are REAL input (SendInput), guarded as in check-e15d3-auto.ps1 -- sent only
# on the user's unlocked desktop, with the fork's window under the point (a PickerHost overlay or any other window
# refuses it) or in front, the cursor put back -- and only after <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE
# (every group: 55 too, its favorite pinned from a tab menu; its pref is set through the DevTools port). A person
# starting it by hand passes -IdleMinutes 0 and then lets go of the mouse. The run keeps what it saw in
# <Tag>-facts.json; -GradeOnly grades that and the logs again. Run it in its OWN process (pwsh -File): a second
# check script in one session reuses the first's C# type. What each step does, and what a pass looks like:
#   54 counts ("[workspaces] pins: header counts P/T/A" when a number changes; the header, named after its workspace,
#      spells them out in its accessible description; a folder row's description holds its pages, its name unchanged).
#      From Work, after three local pages ("E18 one/two/three") open there:
#      base  P 5 (two pages + Smoke folder's 2 + Closed folder's 1: inside folders too, D2), A 0, T the Today tabs
#            MSAA shows; the description says the same; Smoke folder's says 2, Closed folder's 1
#      54a "+ New Tab" pressed -> T+1                      54b that tab clicked, Ctrl+W -> T-1
#      54c "E18 one": tab menu > Anchor > Anchor to this page -> A+1
#      54d the row "Example A" pressed (its page opens, hidden) -> P, T, A unchanged
#      54e "E18 two": tab menu > Pin (Chromium's) -> T-1
#      54f "E18 three": tab menu > Move tab to workspace > Home -> T-1
#      54g the row "Example A": its menu > Unpin -> P-1, T+1 (A reported)
#      after each, the header's description says the log's numbers
#   55 tab style (helium.workspaces.tab_row_height seeded 42): first, in window 1, "E18 g03"
#      made a favorite (tab menu > Pin, as 54e) is a 44 DIP Arc tile in the grid above the list (C21); two windows on
#      Home; in each a Today tab, the pinned page "Example A", the folder "Smoke folder" and "+ New Tab" are 42 DIP
#      tall (the MSAA box / the window's DPI); window 1's "+" > "Workspace settings..." > Tab style > Default (patch
#      93's box) -> one "settings: helium.workspaces.tab_row_height -> 30"; exactly two "tab style: row height 42 -> 30" and
#      two "tab style: N tab view(s) invalidated in M ms" lines (one per window); every box 30 tall; collapsed, a tab
#      is as tall at 42 as at 30 (the column stays compact); after the quit Preferences holds 30
#   56 glide (sixty local pages in Home, the window 1000x800 DIP): Windows' animation effects on (precondition);
#      wheel steps -40, -40, -40, -120, 600 ms apart, over the list -> exactly 4 "glide: A -> B (N ms)" lines, each
#      B != A and N 100..200, and the list scrolled (a tab's MSAA top moved); smooth_scrolling seeded false: a -120
#      step -> no glide line, and the list still scrolled (the wheel reached it)
#   57 wide sidebar (the window 1400x800 DIP or the screen's width; uncollapsed_width 240; wide_sidebar not seeded:
#      the default): the edge dragged +400 DIP -> "sidebar: width W (max M)", W 640 (past 400), M the window's client
#      width - 200, the drawn edge moved W - 240; dragged to the window's right side -> wider, W <= M; after the quit
#      Preferences holds that W; restarted with --restore-last-session the edge is where it was (the saved width, not
#      200); wide_sidebar seeded false (width 240 again), dragged +600 DIP -> W 400, M 400, the edge moved 160
#   every log has bytes and 0 markers (Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling)
. "$PSScriptRoot\e18-lib.ps1"
$ws    = "<local-path>\Helium-workspace"
$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$src   = "$ws\helium-windows\build\src"
$bin   = "$src\out\$OutDir"
$exe   = "$bin\chrome.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$pages = "$ws\$Tag-pages"
$factsFile = "$ws\$Tag-facts.json"
$work  = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$edgeName = "Vertical Tab Strip Resize Handle (Draggable)"
$groups = if ($Only) { @($Only) } else { @("54", "55", "56", "57") }
$patchName = @{ "54" = "54-pinned-counts"; "55" = "55-tab-style"; "56" = "56-smooth-scroll"; "57" = "57-wide-sidebar" }
# The contract's log lines (design 5, E18 spec), and a literal each patch's code holds whole (the stale-binary guard).
$reCounts = '\[workspaces\] pins: header counts ([\d,]+)/([\d,]+)(?:/([\d,]+))?'
$reStyle  = '\[workspaces\] tab style: row height (\d+) -> (\d+)'
$reInval  = '\[workspaces\] tab style: (\d+) tab view\(s\) invalidated in (\d+) ms'
$reGlide  = '\[workspaces\] glide: (-?[\d.]+) -> (-?[\d.]+) \((\d+) ms\)'
$reWidth  = '\[workspaces\] sidebar: width (\d+) \(max (\d+)\)'
$needle   = @{ "54" = "header counts"; "55" = "tab style:"; "56" = "glide:"; "57" = "sidebar: width" }
$script:failed = 0
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name" } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Markers([string]$l) { @(Select-String -LiteralPath $l -CaseSensitive -Pattern 'Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling').Count }

if (-not $GradeOnly) {
# ==== the runs ====================================================================================================
$script:win = [IntPtr]::Zero
$script:bpid = 0
$script:log = ""
$script:client = @(0, 0, 0, 0)
$script:scale = 1.0
# An observation the log cannot give (a set-up step, a precondition), kept for the grading; "<group> ..." names it.
function Obs([string]$name, $ok, [string]$note = "") {
    $script:F.obs += @([ordered]@{ n = $name; ok = [bool]$ok; note = $note })
    Say ("      " + $(if ($ok) { "ok      " } else { "NOT OK  " }) + $name + $(if ($note) { " -- $note" }))
}
function Save { $script:F | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $factsFile }
# A mark: the log and how many lines it had -- the grading reads the lines between two marks.
function LineNo { if (Test-Path -LiteralPath $script:log) { @(Get-Content -LiteralPath $script:log).Count } else { 0 } }
function Mark([string]$k) { $script:F.marks[$k] = [ordered]@{ log = $script:log; line = (LineNo) } }
function Count([string]$re) { if (-not (Test-Path -LiteralPath $script:log)) { return 0 }; @(Select-String -LiteralPath $script:log -Pattern $re).Count }
function WaitCount([string]$re, [int]$n, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 500 }
    return $false
}
function WaitLog([string]$re, [int]$s = 20) { WaitCount $re 1 $s }
function Url([string]$n) { "http://127.0.0.1:$script:port/$n.html" }
# Reads ("a.b") or writes ("a.b=<json>") dotted prefs of the throwaway profile; the browser must be closed.
function Prefs([string[]]$a) { & python "$here\prefs.py" "$script:prof\Default\Preferences" @a }
function EmptySessions { Get-ChildItem -LiteralPath "$script:prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force }
# The group's throwaway copy of the smoke profile, made fresh: only ever this script's own folder.
function NewProfile([string]$g, [string[]]$sets = @()) {
    $script:prof = "$ws\testprofile-$Tag-$g"
    if (Test-Path -LiteralPath $script:prof) { Remove-Item -LiteralPath $script:prof -Recurse -Force }
    $null = robocopy $smoke $script:prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    if (-not (Test-Path -LiteralPath "$script:prof\Default\Preferences")) { throw "the copy of $smoke failed" }
    EmptySessions
    # Patch 70's toolbar "New Tab" button (on by default) would be the first "New Tab" node: 55 measured it, 28 DIP.
    $null = Prefs (@("helium.browser.show_dynamic_new_tab_button=false") + $sets)
}
function Running { [bool]($script:bpid -and (Get-Process -Id $script:bpid -EA SilentlyContinue)) }
function Alive([string]$step) { if (-not (Running)) { throw "${step}: the browser is gone -- a crash? See $script:log" } }
function Launch([string]$name, [string[]]$more = @()) {
    $script:log = "$ws\$Tag-$name.log"
    $script:F.logs += @([ordered]@{ g = $script:group; log = $script:log })
    Remove-Item -LiteralPath $script:log -EA SilentlyContinue
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList (@("--user-data-dir=$script:prof", "--enable-logging", "--log-file=`"$script:log`"", "--v=0", "--no-first-run", "--no-default-browser-check") + $more)).Id
    $script:win = [IntPtr]::Zero
    $t0 = Get-Date
    while ($script:win -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) {
        Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:win = $p.MainWindowHandle }
    }
    if ($script:win -eq [IntPtr]::Zero) { throw "no browser window in 30 s ($name)" }
    Start-Sleep 3
}
# Every window closed, then every process of the build gone (Preferences and Sessions are read after).
function Close {
    if (-not $script:bpid) { return }
    if (Running) {
        foreach ($h in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($h) }
        $t0 = Get-Date
        while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 }
        if (Running) { Say "      (force-stopped: a throwaway profile)"; Stop-Process -Id $script:bpid -Force; Start-Sleep 2 }
    }
    $t0 = Get-Date
    while (@(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }).Count -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1 }
    $script:bpid = 0; $script:win = [IntPtr]::Zero
}
# The window restored, placed top-left `w` x `h` DIP (at most the screen) and topmost, not activated.
function Place([int]$w, [int]$h) {
    $s = [E18Input]::Dpi($script:win) / 96.0
    $scr = [E18Input]::Screen()
    [E18Input]::Place($script:win, 0, 0, [math]::Min($scr[0], [int]($w * $s)), [math]::Min($scr[1] - 80, [int]($h * $s)))
    Start-Sleep 2
    $script:scale = [E18Input]::Dpi($script:win) / 96.0
    $script:client = [E18Input]::Client($script:win)
    Say "      window: scale $($script:scale), client $($script:client -join ',') px"
}
# msaa-press.ps1 on window `h` (the browser's window by default).
function Msaa([string[]]$a, [IntPtr]$h = [IntPtr]::Zero) {
    if ($h -eq [IntPtr]::Zero) { $h = $script:win }
    if ($h -ne [IntPtr]::Zero) { $a += @("-Window", [string][long]$h) }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $script:prof @a
}
function Press([string]$name, [int]$role = 0, [IntPtr]$h = [IntPtr]::Zero) { "$(Msaa @("-Name", $name, "-Role", $role) $h)" }
# Every node of window `h` with its box (physical pixels): name, role, hidden (INVISIBLE), left, top, width, height,
# and with -Desc its accessible description.
function Nodes([IntPtr]$h = [IntPtr]::Zero, [switch]$Desc) {
    $a = @("-List", "-Rect"); if ($Desc) { $a += "-Desc" }
    @(Msaa $a $h | ForEach-Object {
        if ($_ -match '^\s*(.*?)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)(?:\|desc=(.*))?$') {
            [pscustomobject]@{ name = $Matches[1]; role = [Convert]::ToInt32($Matches[2], 16); hidden = [bool]$Matches[3]
                               l = [int]$Matches[4]; t = [int]$Matches[5]; w = [int]$Matches[6]; h = [int]$Matches[7]; desc = [string]$Matches[8] }
        }
    })
}
function Shown($n) { (-not $n.hidden) -and $n.h -gt 0 -and $n.w -gt 0 }
# The tab titled `title`, shown: MSAA may add a state to the name ("<title> - Pinned").
function TabNode($nodes, [string]$title) { @($nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and ($_.name -eq $title -or $_.name.StartsWith("$title - ")) }) | Select-Object -First 1 }
function Named($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.name -eq $name -and $_.role -eq $role -and (Shown $_) }) | Select-Object -First 1 }
# The list's Today tabs; favorites ("<title> - Pinned") sit above it and are left out.
function TodayTabs($nodes) { @($nodes | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and $_.name -notmatch ' - Pinned$' }) }
# The titles in `titles` that are not (yet) a shown tab of window `h`, polled.
function WaitTabs([string[]]$titles, [int]$s = 30, [IntPtr]$h = [IntPtr]::Zero) {
    $t0 = Get-Date
    do { Start-Sleep 2; $n = @(Nodes $h); $miss = @($titles | Where-Object { -not (TabNode $n $_) }) } while ($miss.Count -and ((Get-Date) - $t0).TotalSeconds -lt $s)
    $miss
}
# A guarded left (or right, for its menu) click at the middle of node `n` of the browser's window.
function ClickNode($n, [switch]$Right) {
    if (-not $n) { return "nothing to click" }
    [E18Input]::Click($script:win, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $Right.IsPresent)
}
# A menu: the first of the browser's other windows with a shown node matching `re`, polled; then that node pressed.
function WindowWith([string]$re, [int]$s = 5) {
    $t0 = Get-Date
    do {
        foreach ($h in [E18Input]::Others([uint32]$script:bpid, $script:win)) { if (@(Nodes $h | Where-Object { (Shown $_) -and $_.name -match $re }).Count) { return $h } }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt $s)
    return [IntPtr]::Zero
}
function PressIn([string]$re) {
    $h = WindowWith $re
    $n = if ($h -ne [IntPtr]::Zero) { @(Nodes $h | Where-Object { (Shown $_) -and $_.name -match $re }) | Select-Object -First 1 }
    if (-not $n) { return "nothing matching '$re' in a menu" }
    "'$($n.name)' " + (Press $n.name $n.role $h)
}
# A menu left open by a step that went wrong: Escape, only to the browser's window in front.
function NoMenus { foreach ($i in 1..3) { if (-not @([E18Input]::Others([uint32]$script:bpid, $script:win)).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }

E18InputType

# ---- 54: the counts ------------------------------------------------------------------------------------------
# The header's description now -- the node named after the workspace whose description holds the counts -- and a mark.
function Remember([string]$k) {
    $script:F.v["$k.desc"] = [string](@(Nodes -Desc | Where-Object { $_.name -eq "Work" -and (Shown $_) -and $_.desc -match 'pinned page' }) | Select-Object -First 1).desc
    Mark $k
}
# After a step: a new counts line waited for (`s` s: a step that must change nothing waits it out), then settled.
function Settle([string]$k, [int]$before, [int]$s = 10) {
    $null = WaitCount $reCounts ($before + 1) $s
    Start-Sleep -Milliseconds 1500
    NoMenus
    Alive $k
    Remember $k
}
function Run54 {
    NewProfile "54"
    Launch "54"
    Obs "54 setup: the section drew Home's rows" (WaitLog "pins: drew \d+ row\(s\) of 'default'" 30)
    Place 1000 800
    Say ("      54 setup: 'Work' " + (Press "Work" 0x2B))
    Obs "54 setup: switched to Work" (WaitLog "pins: drew \d+ row\(s\) of '$work'" 15)
    # Opened in the running browser, in the workspace it shows: Work (as check-e15d3-auto.ps1).
    Start-Process $exe -ArgumentList (@("--user-data-dir=$script:prof") + @("one", "two", "three" | ForEach-Object { Url $_ })) | Out-Null
    $miss = @(WaitTabs @("E18 one", "E18 two", "E18 three") 30)
    Obs "54 setup: 'E18 one', 'E18 two' and 'E18 three' are loaded Today tabs of Work" ($miss.Count -eq 0) $(if ($miss.Count) { "missing: $($miss -join ', ')" })
    Obs "54 setup: a counts line was logged" (WaitLog $reCounts 10)
    Start-Sleep 3
    $n = @(Nodes -Desc)
    $script:F.v["54.today"] = (TodayTabs $n).Count
    $script:F.v["54.smoke.desc"] = [string](Named $n "Smoke folder" 0x24).desc
    $script:F.v["54.closed.desc"] = [string](Named $n "Closed folder" 0x24).desc
    Remember "54.base"

    $c = Count $reCounts
    $script:F.v["54a.input"] = "'+ New Tab' " + (Press "New Tab" 0x2B)
    Settle "54a" $c
    # The new tab is the top "New Tab" of Today (E15c.1); the click brings the window in front for Ctrl+W.
    $c = Count $reCounts
    $nt = @(TodayTabs @(Nodes) | Where-Object { $_.name -eq "New Tab" } | Sort-Object t) | Select-Object -First 1
    $r = ClickNode $nt
    $script:F.v["54b.input"] = "the top 'New Tab' $r, Ctrl+W " + $(if ($r -eq "clicked") { [E18Input]::Keys([uint32]$script:bpid, $false, 0x57) } else { "not sent" })
    Settle "54b" $c
    $c = Count $reCounts
    $script:F.v["54c.input"] = (ClickNode (TabNode @(Nodes) "E18 one") -Right) + "; " + (PressIn '^Anchor$') + "; " + (PressIn '^Anchor to this page(?! instead)')
    Settle "54c" $c
    $c = Count $reCounts
    $script:F.v["54d.input"] = "'Example A' " + (Press "Example A" 0x24)
    Obs "54d: the row opened its page ('pins: opened item 'a1'')" (WaitLog "pins: opened item 'a1'$" 10)
    Settle "54d" $c 3
    $c = Count $reCounts
    # Chromium's Pin, never the fork's "Pin to this workspace" (check-e14d2-auto.ps1 row J).
    $script:F.v["54e.input"] = (ClickNode (TabNode @(Nodes) "E18 two") -Right) + "; " + (PressIn '^Add to Favorites')
    Settle "54e" $c
    $c = Count $reCounts
    $script:F.v["54f.input"] = (ClickNode (TabNode @(Nodes) "E18 three") -Right) + "; " + (PressIn '^Move tab to workspace') + "; " + (PressIn '^Home$')
    Settle "54f" $c
    $c = Count $reCounts
    $script:F.v["54g.input"] = (ClickNode (Named @(Nodes) "Example A" 0x24) -Right) + "; " + (PressIn '^Unpin$')
    Settle "54g" $c
    Close
}

# ---- 55: the tab style -----------------------------------------------------------------------------------------
# Heights in DIPs (the MSAA box / the window's DPI) of a Today tab, the pinned page "Example A", the folder "Smoke
# folder" and "+ New Tab" in window `h`; -1 for one not found.
function Heights([IntPtr]$h, [string]$tab) {
    $n = @(Nodes $h); $s = [E18Input]::Dpi($h) / 96.0
    $dip = { param($x) if ($x) { [math]::Round($x.h / $s, 1) } else { -1 } }
    [ordered]@{ today = & $dip (TabNode $n $tab); pinned = & $dip (Named $n "Example A" 0x24); folder = & $dip (Named $n "Smoke folder" 0x24); newtab = & $dip (Named $n "New Tab" 0x2B) }
}
# The tab's height in DIPs while window `h`'s strip is collapsed; expanded again after.
function CollapsedHeight([IntPtr]$h, [string]$tab) {
    $null = Press "Collapse tabs" 0x2B $h; Start-Sleep 2
    $x = TabNode @(Nodes $h) $tab
    $v = if ($x) { [math]::Round($x.h / ([E18Input]::Dpi($h) / 96.0), 1) } else { -1 }
    $null = Press "Expand tabs" 0x2B $h; Start-Sleep 2
    $v
}
# check-93's PopupPress: the first control (e18-lib's Controls) matching `re` in a menu or bubble -- never in a
# browser window (e18-lib's PopupWindows; 55 has two) -- pressed through MSAA.
function PopupPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($h in PopupWindows ([uint32]$script:bpid) $script:win) {
            $n = @(Controls (Nodes $h) { Shown $args[0] } | Where-Object { $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $(Press $n.name $n.role $h)" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    "nothing matching '$re' in a menu or bubble"
}
# The tab style set while the browser runs, as a person sets it since patch 93 (its Settings row and settingsPrivate
# allowlist entry are gone): the rail's "+" > "Workspace settings..." > "Tab style" > `item`, then Escape.
function PickStyle([string]$item) {
    $plus = @(Nodes | Where-Object { (Shown $_) -and $_.name -match '^New tab, workspace' }) | Select-Object -First 1
    if (-not $plus) { return "no '+' on the rail" }
    $r = "'+' $(Press $plus.name $plus.role); $(PopupPress '^Workspace settings')"
    Start-Sleep 2; $r += "; $(PopupPress '^Tab style$')"
    Start-Sleep 2; $r += "; $(PopupPress "^$([regex]::Escape($item))$")"
    # Escape while a popup is up -- NoMenus counts window 2 as one, and would send its three into a page.
    foreach ($i in 1..3) {
        Start-Sleep 1
        if (-not @(PopupWindows ([uint32]$script:bpid) $script:win).Count) { break }
        $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
    }
    $r
}
function Run55 {
    NewProfile "55" @("helium.workspaces.tab_row_height=42")
    # "E18 g03" is only there to be made a favorite: the steps after it measure "E18 g01" and "E18 g02".
    Launch "55" @((Url "g01"), (Url "g03"))
    Obs "55 setup: the section drew Home's rows" (WaitLog "pins: drew \d+ row\(s\) of 'default'" 30)
    $w1 = $script:win
    # A favorite at 42 (a Chromium pinned tab, in the grid above the list): pinned from its tab menu as 54e does --
    # before the second window opens, so a menu is the only other window -- and its MSAA box read (C21: 44 tall).
    Place 1000 800
    $null = WaitTabs @("E18 g03") 20 $w1
    $script:F.v["55.fav.input"] = (ClickNode (TabNode @(Nodes) "E18 g03") -Right) + "; " + (PressIn '^Add to Favorites')
    Say "      55 favorite: 'E18 g03' $($script:F.v['55.fav.input'])"
    Start-Sleep 2; NoMenus; Alive "55 favorite"
    $t0 = Get-Date
    do { $fav = @(Nodes $w1 | Where-Object { $_.role -eq 0x25 -and (Shown $_) -and $_.name -match ' - Pinned$' }) | Select-Object -First 1; if (-not $fav) { Start-Sleep 1 } } while (-not $fav -and ((Get-Date) - $t0).TotalSeconds -lt 10)
    $script:F.v["55.fav42"] = if ($fav) { [math]::Round($fav.h / ([E18Input]::Dpi($w1) / 96.0), 1) } else { -1 }
    Start-Process $exe -ArgumentList @("--user-data-dir=$script:prof", "--new-window", (Url "g02")) | Out-Null
    $w2 = [IntPtr]::Zero; $t0 = Get-Date
    while ($w2 -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 20) {
        Start-Sleep 1; $o = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $w1 }); if ($o.Count) { $w2 = $o[0] }
    }
    Obs "55 setup: a second window opened" ($w2 -ne [IntPtr]::Zero)
    if ($w2 -eq [IntPtr]::Zero) { return }
    $miss = @(WaitTabs @("E18 g01") 20 $w1) + @(WaitTabs @("E18 g02") 20 $w2)
    Obs "55 setup: each window shows its Today tab ('E18 g01', 'E18 g02')" ($miss.Count -eq 0) $(if ($miss.Count) { "missing: $($miss -join ', ')" })
    Start-Sleep 2
    $script:F.v["55.at42.w1"] = Heights $w1 "E18 g01"
    $script:F.v["55.at42.w2"] = Heights $w2 "E18 g02"
    $script:F.v["55.col42"] = CollapsedHeight $w1 "E18 g01"
    $s0 = Count $reStyle; $i0 = Count $reInval
    Mark "55.flip0"
    $script:F.v["55.flip"] = PickStyle "Default"
    $null = WaitCount $reStyle ($s0 + 2) 15
    $null = WaitCount $reInval ($i0 + 2) 15
    Start-Sleep 2
    Alive "55 flip"
    Mark "55.flip1"
    $script:F.v["55.at30.w1"] = Heights $w1 "E18 g01"
    $script:F.v["55.at30.w2"] = Heights $w2 "E18 g02"
    $script:F.v["55.col30"] = CollapsedHeight $w1 "E18 g01"
    Close
    $script:F.v["55.saved"] = "$(Prefs @("helium.workspaces.tab_row_height"))"
}

# ---- 56: the glide ---------------------------------------------------------------------------------------------
# Where each shown Today tab is drawn (its top, px), by title.
function Tops { $o = @{}; foreach ($x in (TodayTabs @(Nodes))) { $o[$x.name] = $x.t }; $o }
# The tabs shown both times: how many, how many moved, and the median move (px).
function Moved($a, $b) {
    $d = @($a.Keys | Where-Object { $b.ContainsKey($_) } | ForEach-Object { $b[$_] - $a[$_] } | Sort-Object)
    [ordered]@{ common = $d.Count; moved = @($d | Where-Object { $_ -ne 0 }).Count; by = $(if ($d.Count) { $d[[int][math]::Floor($d.Count / 2)] } else { 0 }) }
}
function Run56 {
    NewProfile "56"
    Obs "56 precondition: Windows' animation effects are on (off, nothing glides: D13)" ([E18Input]::Animations())
    $urls = @(1..60 | ForEach-Object { Url ("g{0:D2}" -f $_) })
    foreach ($run in "on", "off") {
        # "on" leaves smooth_scrolling unseeded: the default.
        if ($run -eq "off") { EmptySessions; $null = Prefs @("helium.workspaces.smooth_scrolling=false") }
        Launch "56$run" $urls
        Place 1000 800
        # Every page's tab, its title loaded -- shown or scrolled out of the list's view.
        $t0 = Get-Date
        do { Start-Sleep 2; $mine = @(Nodes | Where-Object { $_.role -eq 0x25 -and $_.name -match '^E18 g\d\d$' }) } while ($mine.Count -lt 60 -and ((Get-Date) - $t0).TotalSeconds -lt 40)
        Obs "56 ${run}: the sixty local pages are tabs of Home, their titles loaded ($($mine.Count))" ($mine.Count -ge 60)
        $c = $script:client
        $bottom = ($mine | ForEach-Object { $_.t + $_.h } | Measure-Object -Maximum).Maximum
        Obs "56 ${run}: the list is taller than the window (its last tab ends at $bottom px, the client area at $($c[1] + $c[3]) px)" ($bottom -gt $c[1] + $c[3])
        # The wheel's point: the middle of a Today tab drawn 40-80 % down the client area -- over the list's scroll view.
        $at = @(TodayTabs $mine | Where-Object { ($_.t + $_.h / 2) -gt ($c[1] + 0.4 * $c[3]) -and ($_.t + $_.h / 2) -lt ($c[1] + 0.8 * $c[3]) } | Sort-Object t) | Select-Object -First 1
        if (-not $at) { Obs "56 ${run}: a Today tab 40-80 % down the window to roll the wheel over" $false; Close; continue }
        $x = $at.l + [int]($at.w / 2); $y = $at.t + [int]($at.h / 2)
        # That tab clicked first -- the window in front, and the active tab one already shown (no reveal to scroll) --
        # then the list rolled to its top; neither is graded.
        $pre = "'$($at.name)' " + (ClickNode $at) + "; to the top: " + [E18Input]::Wheel($script:win, $x, $y, [int[]](@(120) * 15), 60)
        Start-Sleep 2
        $tops = Tops
        Mark "56.$run.0"
        $steps = if ($run -eq "on") { @(-40, -40, -40, -120) } else { @(-120) }
        $script:F.v["56.$run.input"] = "$pre; down: " + [E18Input]::Wheel($script:win, $x, $y, [int[]]$steps, 600)
        Start-Sleep 2
        $script:F.v["56.$run.moved"] = Moved $tops (Tops)
        Alive "56 $run"
        Mark "56.$run.1"
        Close
    }
}

# ---- 57: the wider sidebar ---------------------------------------------------------------------------------------
function Edge { @(Nodes | Where-Object { $_.name -eq $edgeName -and (Shown $_) }) | Select-Object -First 1 }
# Where the edge ends, in px from the client area's left; -1 when it is not shown.
function EdgeX($e) { if ($e) { $e.l + $e.w - $script:client[0] } else { -1 } }
# The edge pressed at its middle and dragged to x `toX` (px on screen).
function DragEdge($e, [int]$toX) { if (-not $e) { return "no edge to drag" }; $y = $e.t + [int]($e.h / 2); [E18Input]::Drag($script:win, $e.l + [int]($e.w / 2), $y, $toX, $y) }
function Run57 {
    NewProfile "57" @("vertical_tabs.uncollapsed_width=240", "vertical_tabs.collapsed_state=false")
    Launch "57a"
    Place 1400 800
    $script:F.v["57.scale"] = $script:scale
    $script:F.v["57.client"] = [math]::Round($script:client[2] / $script:scale, 1)
    Obs "57 setup: the client area is 900 DIP wide or more ($($script:F.v['57.client']) DIP)" ($script:F.v["57.client"] -ge 900)
    $e = Edge
    Obs "57 setup: the resize edge is shown" ([bool]$e)
    if (-not $e) { return }
    $script:F.v["57.e0"] = EdgeX $e
    $k = Count $reWidth; Mark "57.d0"
    $script:F.v["57.d1.input"] = DragEdge $e ($e.l + [int]($e.w / 2) + [int](400 * $script:scale))
    $null = WaitCount $reWidth ($k + 1) 10; Start-Sleep 1
    $e = Edge; $script:F.v["57.e1"] = EdgeX $e; Mark "57.d1"
    $script:F.v["57.d2.input"] = DragEdge $e ($script:client[0] + $script:client[2] - [int](30 * $script:scale))
    $null = WaitCount $reWidth ($k + 2) 10; Start-Sleep 1
    $e = Edge; $script:F.v["57.e2"] = EdgeX $e; Mark "57.d2"
    Alive "57 drags"
    Close
    $script:F.v["57.saved"] = "$(Prefs @("vertical_tabs.uncollapsed_width"))"

    # The restart: a window the session restores (D16).
    Launch "57b" @("--restore-last-session")
    Place 1400 800
    $script:F.v["57.e3"] = EdgeX (Edge)
    Close

    $null = Prefs @("helium.workspaces.wide_sidebar=false", "vertical_tabs.uncollapsed_width=240")
    Launch "57c"
    Place 1400 800
    $e = Edge; $script:F.v["57.e4"] = EdgeX $e; $k = Count $reWidth; Mark "57.d3"
    $script:F.v["57.d4.input"] = DragEdge $e ($(if ($e) { $e.l + [int]($e.w / 2) } else { 0 }) + [int](600 * $script:scale))
    $null = WaitCount $reWidth ($k + 1) 10; Start-Sleep 1
    $script:F.v["57.e5"] = EdgeX (Edge); Mark "57.d4"
    Alive "57 off"
    Close
}

# ---- guards ------------------------------------------------------------------------------------------------------
if ($Tag -notmatch '^[\w.-]+$') { Abort "-Tag takes letters, digits, '.', '-' and '_' only (it names folders that are deleted)" }
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Abort "a fork browser is running -- close it first (a launch would only forward to it)" }
if (-not (Test-Path "$bin\chrome.dll")) { Abort "no $bin\chrome.dll" }
if (-not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { Abort "no $smoke (the profile every group copies)" }
# Stale binary: chrome.dll older than a SOURCE of patches 54-57 (not the patch file: a quilt refresh after the build
# rewrites it from the same sources, LOCAL.md 52), or without each group's literal.
$sources = @(Get-ChildItem -LiteralPath "$ws\helium-windows\patches\local\workspaces" -Filter "5*.patch" | Where-Object { $_.Name -match '^5[4-7]-' } |
             ForEach-Object { Select-String -LiteralPath $_.FullName -Pattern '^\+\+\+ b/(\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } } | Sort-Object -Unique)
$missing = @($sources | Where-Object { -not (Test-Path "$src\$_") })
if ($missing.Count) { Abort "missing source(s) of patches 54-57: $($missing -join ', ')" }
if ($sources.Count) {
    $newest = @($sources | ForEach-Object { (Get-Item "$src\$_").LastWriteTime } | Sort-Object)[-1]
    if ((Get-Item "$bin\chrome.dll").LastWriteTime -lt $newest) { Abort "$OutDir\chrome.dll is older than a source of patches 54-57 (stale binary: build first)" }
}
foreach ($grp in $groups) {
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $needle[$grp]
    if ($LASTEXITCODE -ne 0) { Abort "$OutDir\chrome.dll does not contain patch $grp ('$($needle[$grp])') -- not built yet? -Only runs the groups that are" }
}
# Real input needs the PC to itself (every group sends it): the gate, once, before any browser starts (the run's own
# input resets the idle).
$gate = "$(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes)"
if ($gate -notmatch '^FREE') {
    Say "VOID: groups 54, 55, 56 and 57 move the real mouse and need the PC to themselves -- the gate says: $gate. Nothing was run."
    Say "      Leave the screen UNLOCKED and hands off and run it again; started by hand, add -IdleMinutes 0 and let go of the mouse."
    exit 2
}
Say "PC: $gate"
Say "binary: $OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime)"

# ---- set-up: the pages and their server (57 opens none) -------------------------------------------------------------
$server = $null
if (@($groups | Where-Object { $_ -ne "57" }).Count) {
    $sv = ServePages $pages (@("one", "two", "three") + @(1..60 | ForEach-Object { "g{0:D2}" -f $_ }))
    $script:port = $sv.port; $server = $sv.server
    if (-not $sv.ok) { Abort "the pages are not served on port $script:port" }
}

$script:F = [ordered]@{ binary = "$OutDir, $((Get-Item "$bin\chrome.dll").LastWriteTime)"; groups = $groups; obs = @(); logs = @(); marks = [ordered]@{}; v = [ordered]@{} }
try {
    foreach ($grp in $groups) {
        $script:group = $grp
        Say "---- $($patchName[$grp]) ----"
        try {
            switch ($grp) { "54" { Run54 } "55" { Run55 } "56" { Run56 } "57" { Run57 } }
        } catch { Obs "$grp stopped early: $_" $false } finally { Close }
        Save
    }
} finally {
    if ($server) { Stop-Process -Id $server.Id -EA SilentlyContinue }
    Save
}
}

# ==== the grading (also -GradeOnly) ================================================================================
if (-not (Test-Path -LiteralPath $factsFile)) { Abort "no $factsFile -- run without -GradeOnly first" }
$F = [IO.File]::ReadAllText($factsFile) | ConvertFrom-Json
$grade = @($F.groups | Where-Object { -not $Only -or $_ -eq $Only })
if (-not $grade.Count) { Abort "$factsFile holds no group $Only" }
Say "graded: $($F.binary)"
# The first `line` lines of a mark's log.
function Ln($m) { if ($m -and [int]$m.line -gt 0 -and (Test-Path -LiteralPath $m.log)) { @(Get-Content -LiteralPath $m.log -TotalCount ([int]$m.line)) } }
# The lines matching `re` after mark k0, up to mark k1 (one log).
function Between([string]$k0, [string]$k1, [string]$re) {
    $m0 = $F.marks.$k0; $m1 = $F.marks.$k1
    if ($m0 -and $m1 -and $m0.log -eq $m1.log) { @(Ln $m1 | Select-Object -Skip ([int]$m0.line) | Select-String -Pattern $re) }
}
# The leading comma keeps a one-number list a list (check-e18.ps1's Nums: "680"[0] would be "6").
function Nums($hit) { , @($hit.Matches[0].Groups | Select-Object -Skip 1 | ForEach-Object { $_.Value }) }
function Int([string]$s) { if ($s) { [int]($s -replace ',', '') } else { 0 } }
# The counts of the last counts line up to mark k (A 0 when the line leaves it out).
function Counts([string]$k) {
    $m = @(Ln ($F.marks.$k) | Select-String -Pattern $reCounts)
    if ($m.Count) { $nm = Nums $m[-1]; [pscustomobject]@{ P = Int $nm[0]; T = Int $nm[1]; A = Int $nm[2] } }
}
function Show($c) { if ($c) { "$($c.P)/$($c.T)/$($c.A)" } else { "none" } }
# The numbers a description spells out ("5 pinned pages / 4 Today tabs / 1 anchored tab"); a piece left out is 0.
function Num([string]$d, [string]$what) { if ($d -match "([\d,]+) $what") { Int $Matches[1] } else { 0 } }
function Spelled([string]$d) { if ($d -match 'pinned page') { [pscustomobject]@{ P = Num $d 'pinned page'; T = Num $d 'Today tab'; A = Num $d 'anchored tab' } } }
function Same($a, $b) { [bool]($a -and $b -and $a.P -eq $b.P -and $a.T -eq $b.T -and $a.A -eq $b.A) }
function Near($a, [double]$b, [double]$tol = 1) { [bool]($null -ne $a -and [double]$a -ge 0 -and [math]::Abs([double]$a - $b) -le $tol) }

function Grade54 {
    $b = Counts "54.base"
    Verdict "54 base: a counts line for Work: 5 pinned pages (Example A, Example D, Smoke folder's 2, Closed folder's 1 -- inside folders too, D2), no anchored tab; log $(Show $b)" ($b -and $b.P -eq 5 -and $b.A -eq 0)
    Verdict "54 base: T is the Today tabs the list shows (MSAA: $($F.v.'54.today')); log T $($b.T)" ($b -and $b.T -eq [int]$F.v.'54.today')
    Verdict "54 base: the header (named 'Work') spells the same in its description: '$($F.v.'54.base.desc')'" (Same (Spelled $F.v.'54.base.desc') $b)
    foreach ($fd in @(@("Smoke folder", "54.smoke.desc", 2), @("Closed folder", "54.closed.desc", 1))) {
        $d = [string]$F.v.($fd[1])
        Verdict "54 base: the row '$($fd[0])' (found by its unchanged name) holds $($fd[2]) by its description: '$d'" ($d -match 'pinned page' -and (Num $d 'pinned page') -eq $fd[2])
    }
    $steps = @(
        @{ k = "54a"; what = "'+ New Tab' pressed"; want = "T+1"; d = @(0, 1, 0) },
        @{ k = "54b"; what = "that tab clicked, Ctrl+W"; want = "T-1"; d = @(0, -1, 0) },
        @{ k = "54c"; what = "'E18 one' anchored from its tab menu (Anchor > Anchor to this page)"; want = "A+1"; d = @(0, 0, 1) },
        @{ k = "54d"; what = "the row 'Example A' pressed, its page opened hidden"; want = "P, T and A unchanged"; d = @(0, 0, 0) },
        @{ k = "54e"; what = "'E18 two' pinned from its tab menu (Chromium's Pin)"; want = "T-1"; d = @(0, -1, 0) },
        @{ k = "54f"; what = "'E18 three' moved to Home from its tab menu"; want = "T-1"; d = @(0, -1, 0) },
        @{ k = "54g"; what = "the row 'Example A' unpinned from its menu"; want = "P-1, T+1 (A reported)"; d = @(-1, 1, $null) })
    $prev = $b; $prevKey = "54.base"
    foreach ($s in $steps) {
        $now = Counts $s.k
        $exp = if ($prev) { [pscustomobject]@{ P = $prev.P + $s.d[0]; T = $prev.T + $s.d[1]; A = $(if ($null -eq $s.d[2]) { $null } else { $prev.A + $s.d[2] }) } }
        $ok = [bool]($exp -and $now -and $now.P -eq $exp.P -and $now.T -eq $exp.T -and ($null -eq $exp.A -or $now.A -eq $exp.A))
        $lines = @(Between $prevKey $s.k $reCounts).Count
        Verdict "$($s.k): $($s.what) -> $($s.want): log $(Show $prev) -> $(Show $now) ($lines new line(s)) [input: $($F.v."$($s.k).input")]" $ok
        $d = [string]$F.v."$($s.k).desc"
        Verdict "$($s.k): the header's description says the same: '$d'" (Same (Spelled $d) $now)
        $prev = $now; $prevKey = $s.k
    }
}

function Grade55 {
    foreach ($want in 42, 30) {
        foreach ($wn in "w1", "w2") {
            $hh = $F.v."55.at$want.$wn"
            Verdict "55 at ${want}, window ${wn}: a Today tab $($hh.today), the pinned page 'Example A' $($hh.pinned), the folder 'Smoke folder' $($hh.folder), '+ New Tab' $($hh.newtab) DIP tall -- each $want (+-1)" ($hh -and (Near $hh.today $want) -and (Near $hh.pinned $want) -and (Near $hh.folder $want) -and (Near $hh.newtab $want))
        }
        if ($want -eq 42) {
            Verdict "55 favorite: a favorite is a C21 tile, 44 DIP at Spacious 42 (check-c21 measures 30 too): $($F.v.'55.fav42') DIP" (Near $F.v.'55.fav42' 44)
            $wr = @(Between "55.flip0" "55.flip1" "\[workspaces\] settings: helium\.workspaces\.tab_row_height -> 30\b")
            Verdict "55 flip: '+' > Workspace settings... > Tab style > Default wrote 'settings: helium.workspaces.tab_row_height -> 30' once ($($wr.Count); $($F.v.'55.flip'))" ($wr.Count -eq 1)
            $st = @(Between "55.flip0" "55.flip1" $reStyle)
            Verdict "55 flip: exactly two 'tab style: row height 42 -> 30' lines, one per window ($(@($st | ForEach-Object { $nm = Nums $_; "$($nm[0]) -> $($nm[1])" }) -join ', '))" ($st.Count -eq 2 -and -not @($st | Where-Object { $nm = Nums $_; $nm[0] -ne '42' -or $nm[1] -ne '30' }).Count)
            $iv = @(Between "55.flip0" "55.flip1" $reInval)
            Verdict "55 flip: exactly two 'tab style: N tab view(s) invalidated in M ms' lines, one per window ($(@($iv | ForEach-Object { $nm = Nums $_; "$($nm[0]) view(s) in $($nm[1]) ms" }) -join ', '))" ($iv.Count -eq 2 -and -not @($iv | Where-Object { [int](Nums $_)[0] -lt 1 }).Count)
        }
    }
    Verdict "55 collapsed: a tab is as tall at 42 ($($F.v.'55.col42') DIP) as at 30 ($($F.v.'55.col30') DIP) -- the collapsed column stays compact (D10)" ([double]$F.v.'55.col42' -gt 0 -and (Near $F.v.'55.col30' ([double]$F.v.'55.col42')))
    Verdict "55 saved: after the quit Preferences holds tab_row_height 30 (read: $($F.v.'55.saved'))" ("$($F.v.'55.saved')".Trim() -eq "30")
}

function Grade56 {
    foreach ($run in "on", "off") {
        $g = @(Between "56.$run.0" "56.$run.1" $reGlide)
        $seen = @($g | ForEach-Object { $nm = Nums $_; "$($nm[0]) -> $($nm[1]) ($($nm[2]) ms)" }) -join ', '
        $sent = "[input: $($F.v."56.$run.input")]"
        if ($run -eq "on") {
            Verdict "56 on (smooth_scrolling not seeded: the default): wheel -40, -40, -40, -120 -> exactly 4 'glide:' lines ($seen) $sent" ($g.Count -eq 4)
            Verdict "56 on: each glide moved (B != A) and took 100-200 ms" ($g.Count -and -not @($g | Where-Object { $nm = Nums $_; [double]$nm[0] -eq [double]$nm[1] -or [int]$nm[2] -lt 100 -or [int]$nm[2] -gt 200 }).Count)
        } else {
            Verdict "56 off (smooth_scrolling false): wheel -120 -> no 'glide:' line ($(if ($seen) { $seen } else { 'none' })) $sent" ($g.Count -eq 0 -and $F.marks.'56.off.1')
        }
        $mv = $F.v."56.$run.moved"
        Verdict "56 ${run}: the list scrolled -- $($mv.moved) of the $($mv.common) tabs shown before and after the wheel moved, by $($mv.by) px" ($mv -and $mv.common -gt 0 -and $mv.moved -gt 0 -and $mv.by -ne 0)
    }
}

function Grade57 {
    $s = [double]$F.v.'57.scale'; $cw = [double]$F.v.'57.client'
    # The drawn width's change in DIPs between two edge positions (px from the client area's left).
    $moved = { param($a, $b) if ($s -gt 0 -and [double]$a -ge 0 -and [double]$b -ge 0) { [math]::Round(([double]$b - [double]$a) / $s, 1) } }
    $l1 = @(Between "57.d0" "57.d1" $reWidth); $n1 = if ($l1.Count) { Nums $l1[-1] } else { @(-1, -1) }
    $w1 = [int]$n1[0]; $m1 = [int]$n1[1]
    Verdict "57a: dragged +400 DIP from 240 -> one 'sidebar: width W (max M)' line ($($l1.Count)), W 640 (+-4), past 400: W $w1 [input: $($F.v.'57.d1.input')]" ($l1.Count -eq 1 -and [math]::Abs($w1 - 640) -le 4)
    Verdict "57a: M is the window's width - 200 (client $cw DIP -> $($cw - 200), +-3): M $m1" ($l1.Count -and [math]::Abs($m1 - ($cw - 200)) -le 3)
    $d1 = & $moved $F.v.'57.e0' $F.v.'57.e1'
    Verdict "57a: the drawn edge moved W - 240 = $($w1 - 240) DIP (+-3): $d1" ($null -ne $d1 -and [math]::Abs($d1 - ($w1 - 240)) -le 3)
    $l2 = @(Between "57.d1" "57.d2" $reWidth); $n2 = if ($l2.Count) { Nums $l2[-1] } else { @(-1, -1) }
    $w2 = [int]$n2[0]; $m2 = [int]$n2[1]
    Verdict "57b: dragged to the window's right side -> one line ($($l2.Count)), wider than $w1 and at most M: W $w2, M $m2 [input: $($F.v.'57.d2.input')]" ($l2.Count -eq 1 -and $w2 -gt $w1 -and $w2 -le $m2 -and $m2 -eq $m1)
    $d2 = & $moved $F.v.'57.e1' $F.v.'57.e2'
    Verdict "57b: the drawn edge moved $($w2 - $w1) DIP (+-3): $d2" ($null -ne $d2 -and $l2.Count -and [math]::Abs($d2 - ($w2 - $w1)) -le 3)
    Verdict "57c: after the quit Preferences holds uncollapsed_width $w2 (read: $($F.v.'57.saved'))" ($l2.Count -and "$($F.v.'57.saved')".Trim() -eq "$w2")
    # A missing measurement reads -1, not 0; and only a widened sidebar (57b drew one) proves the width came back --
    # an edge that never moved would otherwise be "where it was" (an earlier run passed that way, proving nothing).
    $e2 = if ($null -ne $F.v.'57.e2') { [double]$F.v.'57.e2' } else { -1 }
    $e3 = if ($null -ne $F.v.'57.e3') { [double]$F.v.'57.e3' } else { -1 }
    Verdict "57d: restarted (--restore-last-session), the edge is where it was: $e3 px vs $e2 px (+-2) -- the saved width, not 200 (D16)" ($l2.Count -eq 1 -and $e2 -ge 0 -and $e3 -ge 0 -and [math]::Abs($e3 - $e2) -le 2)
    $l3 = @(Between "57.d3" "57.d4" $reWidth); $n3 = if ($l3.Count) { Nums $l3[-1] } else { @(-1, -1) }
    Verdict "57e: wide_sidebar false, dragged +600 DIP from 240 -> one line ($($l3.Count)), W 400 and M 400: W $($n3[0]), M $($n3[1]) [input: $($F.v.'57.d4.input')]" ($l3.Count -eq 1 -and [int]$n3[0] -eq 400 -and [int]$n3[1] -eq 400)
    $d3 = & $moved $F.v.'57.e4' $F.v.'57.e5'
    Verdict "57e: the drawn edge moved 160 DIP (+-3): $d3" ($null -ne $d3 -and [math]::Abs($d3 - 160) -le 3)
}

foreach ($grp in $grade) {
    Say "==== $($patchName[$grp]) ===="
    foreach ($o in @($F.obs | Where-Object { $_.n -like "$grp*" })) { Verdict ($o.n + $(if ($o.note) { " -- $($o.note)" })) $o.ok }
    switch ($grp) { "54" { Grade54 } "55" { Grade55 } "56" { Grade56 } "57" { Grade57 } }
    foreach ($e in @($F.logs | Where-Object { $_.g -eq $grp })) {
        $bytes = if (Test-Path -LiteralPath $e.log) { (Get-Item -LiteralPath $e.log).Length } else { 0 }
        $m = if ($bytes) { Markers $e.log } else { -1 }
        Verdict "$grp log $(Split-Path -Leaf $e.log): $bytes bytes, $m crash marker(s) (0)" ($bytes -gt 0 -and $m -eq 0)
    }
}
if ($script:failed) { Say "E18 AUTO: FAIL ($($script:failed))"; exit 1 } else { Say "E18 AUTO: ALL PASS" }
