param([ValidateSet("Default", "Dcheck")][Alias("OutDir")][string]$Build = "Default", [string]$Tag = "c20", [double]$IdleMinutes = 15,
      [string[]]$Rows = @())
# C20 (patch 89, 89-link-preview.patch; <local-path>\Helium-workspace\c21-progress.md): the link preview. A link opens in a card
# over its tab -- a tab-modal dialog (MSAA dialog "Link preview", a push button "Open as tab", the frame's X "Close"),
# 85% of the page area over the tab's own pane, the page behind dimmed -- by two ways in only (no Alt+click): "Preview
# link" on a link's right-click menu, and Arc's rule, a plain click on an OPEN PINNED PAGE's link to ANOTHER SITE.
# "Open as tab" moves the SAME page to the top of Today in the workspace on screen.
# On a throwaway copy of the smoke profile (Home, Work, Canary, Private, Unpin), the sidebar 280 wide, Work
# given a pinned page "C20 pinned" (c20pin.html). Every row runs in the one browser window, in Work. The pages are
# local\c20\*.html (+ ServePages' plain c20same, c20next, c20side), served by ServePages' python on 127.0.0.1:<port>
# and reached as localhost:<port> too: two hosts with no registrable domain, so two SITES to SameDomainOrHost.
# The right-clicks, clicks and keys are REAL input (SendInput, guarded): it starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE (a person starting it passes -IdleMinutes 0 and lets go).
#   pwsh -NoProfile -File local\check-c20.ps1 [-Build Dcheck] [-IdleMinutes 0] [-Rows M1,B1]
# "a card" below: c20home in front in Work, a real right-click on its "C20 target link", "Preview link" pressed, the
# card up on c20target.html (127.0.0.1). The card's own page is read through DevTools (a target of no tab).
# Launch 1:
#   setup  Work on screen; c20side and c20home opened in it (DevTools /json/new); the row "C20 pinned" drawn
#   M1     the link's menu lists "Preview link"; pressed: "shown (menu) over tab <n>", the dialog "Link preview" with
#          "Open as tab" and "Close" inside it, 82-88% of the page's width and height, centred within 16 px; the page
#          below the card 30+ levels darker than before it (the dim); no new tab (DevTools page count), no "-> new tab"
#   E1     a card, a click in it, Escape: "closed (escape)", the dialog gone
#   O1     a card, a real click on the dimmed page below it: "closed (outside)", the dialog gone
#   X1     a card, a real click on its frame's X: "closed (x)", the dialog gone
#   K1     a card, a click in it, Ctrl+W: "closed (ctrl+w)", the dialog gone, c20home still open, the page count the same
#   B1     a card; its "C20 next link" clicked: the card's page at c20next; Alt+Left: back at c20target IN THE CARD, the
#          card still up; c20home's address unchanged throughout
#   T1     a card; c20side activated (DevTools /json/activate, a tab switch): "closed (tab switch)", the dialog gone
#   T2     a card, a click in it, a REAL Ctrl+Tab (the owner's try: it did nothing): "closed (tab switch)", gone
#   E2     a card and NO click in it (as the owner did): Escape at once: "closed (escape)" -- the keyboard is the card's
#   T3     a card and NO click in it: Ctrl+Tab at once: "closed (tab switch)"
#   P1     (D8) "C20 pinned" pressed, its page c20pin in front; a real click on "C20 same link" (127.0.0.1 ->
#          127.0.0.1): the pinned page itself goes to c20same.html; no "a pinned page's link" line, no "shown (" line,
#          no card, the page count the same. Then history.back() to c20pin.
#   P2     (D8) the same page at c20pin; a real click on "C20 other link" (127.0.0.1 -> localhost): "a pinned page's
#          link to another site", "shown (pinned page) over tab <n>", the card up on localhost's c20target.html; the
#          pinned page still at c20pin.html with its history.length unchanged; the page count the same
#   A1     a card (c20target: a counter, 2 history entries); its counter, performance.timeOrigin and history.length
#          read; "Open as tab" clicked: "closed (open as tab)", "opened as tab at index <i>, 2 entries, loading 0", the
#          dialog gone; the SAME DevTools target now a tab: the same timeOrigin (not reloaded), the counter higher,
#          history.length 2, visible; Work's first Today tab "E18 c20target"; no workspace switch; the page count +1
# Launch 2 (--restore-last-session, after a WM_CLOSE):
#   R1     Work's first Today tab is c20target again, at c20target.html#pushed with history.length 2
#   Z      0 crash markers in both logs (case-sensitive, DanglingPtr too)
# P1/P2 ASSUME D8 (c21-progress.md): ShouldPreviewPinnedLink (workspace_stamping.cc, the owner's, by hand) is true for
# pinned page AND renderer-initiated AND user gesture AND link click AND not POST AND http(s) AND not same site. With
# the TODO(human) stub (false) P2 fails and P1 passes. A pass needs all 13 verdicts ($total below).
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows M1,B1` passes ONE string "M1,B1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = "$ws\helium-windows\build\src\out\$Build"
$exe     = "$bin\chrome.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = "$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$prof    = "$ws\testprofile-$Tag$suffix"
$logs    = @(1..2 | ForEach-Object { if ($Build -eq "Dcheck") { "$ws\$Tag-dcheck-exercise$_.log" } else { "$ws\$Tag-run$_.log" } })
$pages   = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total   = 16
# workspace_link_preview.cc's lines (patch 89), graded case-sensitively.
$active     = "\[workspaces\] active workspace -> '([^']*)'"
function Shown([string]$trigger) { "\[workspaces\] link preview: shown \($trigger\) over tab (\d+)" }
$shownAny   = "\[workspaces\] link preview: shown \("
function Closed([string]$cause) { "\[workspaces\] link preview: closed \($([regex]::Escape($cause))\)" }
$pinnedLink = "\[workspaces\] link preview: a pinned page's link to another site"
$asTab      = "\[workspaces\] link preview: opened as tab at index (-?\d+), (\d+) entries, loading (\d)"
$newTab     = "\[workspaces\] link preview: cannot show -> new tab"
$refusal    = "\[workspaces\] link preview: (cannot show|dropped) .*"
$openedPin  = "\[workspaces\] pins: opened item 'c20p'"

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
# Why no card showed: the last "cannot show" / "dropped" line.
function Why { $l = @(Lines $refusal); if ($l.Count) { "last refusal '$($l[-1].Matches[0].Value)'" } else { "no refusal line" } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }
# `get` polled until its value matches `re`: the last value. (Its own names are odd: `get` sees the caller's.)
function Until([scriptblock]$get, [string]$re) {
    $untilT0 = Get-Date
    do { $untilV = "$(& $get)"; if ($untilV -match $re) { break }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $untilT0).TotalSeconds -lt 10 * $slow)
    $untilV
}

# ---- MSAA (msaa-press.ps1, e14d3-web.ps1) and the menus, as check-c33's --------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
function TabIn($nodes, [string]$title) {
    $page = if ($title -like "E18 *") { "*/$($title.Substring(4)).html*" } else { $null }
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
# A guarded left (or right) click at the middle of node `n` of the main window (check-e18-auto's).
function ClickNode($n, [switch]$Right) {
    if (-not $n) { return "nothing to click" }
    [E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $Right.IsPresent)
}
# Link `name` of the web page drawn in the main window -- the page in front, or the card's while a card is up (a
# focused tab-modal dialog is then all the window's tree shows) -- through e14d3-web.ps1, msaa-press's walk INTO pages:
# its box, polled (the first walk turns the page's accessibility on); $null when none is shown.
function Link([string]$name) {
    $t0 = Get-Date
    do {
        foreach ($line in @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\e14d3-web.ps1" -Profile $prof -Window ([long]$script:main) -Name $name -Role 0x1E)) {
            # name|0xROLE|0xSTATE|@l,t,w,h|value: neither INVISIBLE (0x8000) nor OFFSCREEN (0x10000), a box with a size.
            if ("$line" -match '\|0x([0-9A-F]+)\|@(-?\d+),(-?\d+),(\d+),(\d+)\|' -and -not ([Convert]::ToInt32($Matches[1], 16) -band 0x18000) -and [int]$Matches[4] -gt 0 -and [int]$Matches[5] -gt 0) {
                return [pscustomobject]@{ l = [int]$Matches[2]; t = [int]$Matches[3]; w = [int]$Matches[4]; h = [int]$Matches[5] }
            }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
function Go([string]$name, [string]$guid) {
    if (NodeIn (Nodes $script:main) $name 0x14) { return $true }
    $c = Count $active
    $null = Press $script:main $name 0x2B
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Nth $active $c)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}

# ---- the card ------------------------------------------------------------------------------------------------------
# The card's node in the main window: a kChild dialog is a CHILD widget there, its views in the window's own tree.
function Card { @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x12 -and $_.name -eq "Link preview" }) | Select-Object -First 1 }
# The card polled until its being up is `want`: its node then, or $null.
function WaitCard([bool]$want) {
    $t0 = Get-Date
    do { $c = Card; if ([bool]$c -eq $want) { return $c }; Start-Sleep -Milliseconds 500 } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $c
}
# Push button `name` inside the card's box: its "Open as tab", its frame's X "Close" -- never a tab's close button.
function CardButton($card, [string]$name) {
    if (-not $card) { return $null }
    @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq $name -and $_.l -ge $card.l -and $_.t -ge $card.t -and
                                          $_.l + $_.w -le $card.l + $card.w -and $_.t + $_.h -le $card.t + $card.h }) | Select-Object -First 1
}
# A real click in the card's middle (its page, blank there): the page gets the keyboard, the window comes in front;
# a press inside the card is no "outside".
function FocusCard($card) { if (-not $card) { return "no card" }; ClickNode $card }
# The page in front's document node (read with no card up: a focused card hides the rest of the tree).
function Doc { @(Nodes $script:main | Where-Object { $_.shown -and $_.role -eq 0xF } | Sort-Object { $_.w * $_.h }) | Select-Object -Last 1 }
# The band the card leaves free at the bottom of page `doc` (3/40 of its height): the dimmed page, outside the card.
function Below($doc) { [pscustomobject]@{ l = $doc.l; t = $doc.t + $doc.h - [int]($doc.h * 3 / 40); w = $doc.w; h = [int]($doc.h * 3 / 40) } }
# The brightness (0-255, the mean of R, G and B) of the screen at node `n`'s middle. E18Input's calls make this thread
# per-monitor aware, as the MSAA boxes are (check-c35's Grab); --force-color-profile=srgb gives true colours (HDR).
function Bright($n) {
    $null = [E18Input]::Screen()
    $bmp = [System.Drawing.Bitmap]::new(1, 1); $g = [System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), 0, 0, $bmp.Size); $c = $bmp.GetPixel(0, 0); [int](($c.R + $c.G + $c.B) / 3) } finally { $g.Dispose(); $bmp.Dispose() }
}
# A card from the right-click menu of link `link` of the page in front: a real right-click (it also brings the window
# in front for the keys after), "Preview link" pressed. What was said, the menu's items, the "shown (menu)" line seen,
# the card's node -- a second after it is up: its buttons ignore a press in their first moments (views' input
# protector).
function OpenCard([string]$link = "C20 target link") {
    $c = Count (Shown "menu")
    $n = Link $link
    if (-not $n) { return [pscustomobject]@{ said = "no link '$link' drawn"; items = @(); shown = $false; card = $null } }
    $r = ClickNode $n -Right
    $items = @(); $t0 = Get-Date
    do { Start-Sleep -Milliseconds 500; $items = @(PopupNames) } while (-not $items.Count -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $p = OtherPress '^Preview link$'
    if ($p -like "nothing matching*") { NoPopups }
    $shown = WaitLog (Shown "menu") ($c + 1) 10
    $card = WaitCard $true
    Start-Sleep -Milliseconds (1000 * $slow)
    [pscustomobject]@{ said = "$r; $p$(if (-not $shown) { "; $(Why)" })"; items = $items; shown = $shown; card = $card }
}
# A card a row left up (P2's, or one its close did not take): Escape, then its X.
function NoCard {
    $c = Card
    if (-not $c) { return }
    $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
    if (WaitCard $false) { $null = ClickNode (CardButton $c "Close"); $null = WaitCard $false }
}
function Row([string]$row, [scriptblock]$body) {
    # -Rows M1,B1: only those rows (and the setup); the RESULT then counts fewer verdicts.
    if ($Rows.Count -and $row -ne "setup" -and $Rows -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not (Running)) { throw "the browser is gone after $row" }
    }
    NoPopups
    NoCard
}

# ---- the pages and DevTools ----------------------------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
# Every DevTools target. In brackets: pwsh 7's Invoke-RestMethod writes a JSON array as ONE object (check-c35's).
function Targets { try { @((Invoke-RestMethod -TimeoutSec 10 "$(Base)/list") | Where-Object { $_ }) } catch { @() } }
# The tabs' pages ("page"); the card's page is a WebContents of no tab, listed as another type.
function Pages { @(Targets | Where-Object { $_.type -eq "page" }) }
function PageOf([string]$name) { @(Pages | Where-Object { $_.url -like "*/$name.html*" }) | Select-Object -First 1 }
# The card's page is a DevTools "page" target like a tab's (every WebContents is), told apart by its address: no tab
# shows c20target or c20next until A1 promotes the card's own page.
function CardPage { @(Targets | Where-Object { $_.url -match '^http://(127\.0\.0\.1|localhost):\d+/c20(target|next)\.html' }) | Select-Object -First 1 }
function UrlOf([string]$id) { "$(@(Targets | Where-Object { $_.id -eq $id }) | Select-Object -First 1 | ForEach-Object { $_.url })" }
# Tab `name` once loaded, or $null.
function WaitPage([string]$name) {
    $t0 = Get-Date
    do {
        $t = PageOf $name
        if ($t -and (Evaluate $t.webSocketDebuggerUrl "document.readyState") -eq "complete") { return $t }
        Start-Sleep -Milliseconds 300
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    $null
}
# Page `name` opened in front (/json/new: no opener; it lands below the tab before), once titled: its target.
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url "$name.html")))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
    $t
}
# A tab brought in front (/json/activate: the tab activated, as a click on it -- check-c35's).
function Show($t) { try { $null = Invoke-RestMethod -TimeoutSec 10 "$(Base)/activate/$($t.id)" } catch {}; Start-Sleep -Milliseconds (500 * $slow) }
# Work on screen, c20home open in it and in front: where every card row starts. Its target.
function Home {
    if (-not (Go "Work" $work)) { throw "Work did not come on screen" }
    $h = PageOf "c20home"
    if ($h) { Show $h } else { $h = NewTab "c20home" }
    $h
}
# Work on screen, its pinned row "C20 pinned" pressed (opened, or brought in front when open): its page's target once
# at c20pin.html and shown; $null when not.
function PinnedFront {
    if (-not (Go "Work" $work)) { return $null }
    $null = Press $script:main "C20 pinned" 0x24
    $t = WaitPage "c20pin"
    if ($t -and (Until { Evaluate $t.webSocketDebuggerUrl "document.visibilityState" } '^visible$') -eq "visible") { $t } else { $null }
}

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
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "link preview: opened as tab"
Say "build: $Build\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($LASTEXITCODE -eq 0) { 'WITH' } else { 'WITHOUT' }) patch 89"
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
Add-Type -AssemblyName System.Drawing
$scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $scr[0] - 80), [Math]::Min(1300, $scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$prof\Default\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $logs -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
# ServePages' plain pages, then local\c20's own beside them (the server serves the whole folder); localhost reaches the
# same server (python binds 127.0.0.1; the browser falls back to it from ::1).
$script:srv = ServePages $pages @("c20same", "c20next", "c20side")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
Copy-Item -Path "$here\c20\*.html" -Destination $pages -Force
$other = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 "http://localhost:$($script:srv.port)/c20pin.html").Content -match "E18 c20pin" } catch { $false }
if (-not $other) { Abort "c20pin.html is not served on localhost:$($script:srv.port) (P2's other site)" }
# The pinned page "C20 pinned" (c20p) at the end of Work; written as UTF-8, its version kept (check-c35's way).
& python -I -c "import json,sys; p,port,work=sys.argv[1:4]; d=json.load(open(p,encoding='utf-8')); d['workspaces'][work].append({'type':'item','id':'c20p','title':'C20 pinned','url':'http://127.0.0.1:%s/c20pin.html' % port}); open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins" $script:srv.port $work
if ($LASTEXITCODE -ne 0) { Abort "the pinned page was not seeded into $prof" }

try {
    # ---- launch 1 ------------------------------------------------------------------------------------------------
    $script:log = $logs[0]
    Launch @()
    Row "setup" {
        $s = "Work $(Go 'Work' $work)"
        $null = NewTab "c20side"
        $null = NewTab "c20home"
        $n = Nodes $script:main
        $t = @(Today $n)
        $pin = NodeIn $n "C20 pinned" 0x24
        Verdict "setup ($s; localhost served $other): Work's Today $(Names $t); the row 'C20 pinned' drawn $([bool]$pin)" ((TabIn $t "E18 c20home") -and (TabIn $t "E18 c20side") -and $pin)
    }
    Row "M1" {
        $null = Home
        $doc = Doc
        if (-not $doc) { throw "no page drawn in the main window" }
        $b = Below $doc
        $lit = Bright $b
        $p0 = @(Pages).Count; $cn = Count $newTab
        $oc = OpenCard
        $card = $oc.card
        $dim = Bright $b
        $open = CardButton $card "Open as tab"; $x = CardButton $card "Close"
        $wr = 0; $hr = 0; $off = 999
        if ($card) {
            $wr = [Math]::Round($card.w / $doc.w, 3); $hr = [Math]::Round($card.h / $doc.h, 3)
            $off = [Math]::Max([Math]::Abs(2 * $card.l + $card.w - 2 * $doc.l - $doc.w), [Math]::Abs(2 * $card.t + $card.h - 2 * $doc.t - $doc.h)) / 2
        }
        $p1 = @(Pages).Count
        Verdict "M1 c20home's link menu ($($oc.said)): $(($oc.items | Select-Object -First 20) -join ' | '); the card $(if ($card) { "@$($card.l),$($card.t) $($card.w)x$($card.h) over the page @$($doc.l),$($doc.t) $($doc.w)x$($doc.h): ${wr} x $hr of it (want 0.82-0.88), $off px off centre (want <= 16)" } else { 'not drawn' }); 'Open as tab' $([bool]$open), 'Close' $([bool]$x) inside it; the page below it $lit -> $dim (want 30+ darker); page targets $p0 -> $p1 (want +1: the card's own page, no tab); '-> new tab' +$((Count $newTab) - $cn)" (@($oc.items -match '^Preview link$').Count -eq 1 -and $oc.shown -and $card -and $open -and $x -and $wr -ge 0.82 -and $wr -le 0.88 -and $hr -ge 0.82 -and $hr -le 0.88 -and $off -le 16 -and $lit - $dim -ge 30 -and $p1 -eq $p0 + 1 -and (Count $newTab) -eq $cn)
    }
    Row "E1" {
        $null = Home
        $oc = OpenCard
        $cc = Count (Closed "escape")
        $f = FocusCard $oc.card
        $k = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
        $closed = WaitLog (Closed "escape") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Verdict "E1 a card ($($oc.said)); a click in it ($f), Escape ($k): 'closed (escape)' $closed, the card gone $gone" ($oc.card -and $closed -and $gone)
    }
    Row "E2" {
        $null = Home
        $oc = OpenCard
        $cc = Count (Closed "escape")
        $k = [E18Input]::Tap([uint32]$script:bpid, 0x1B)
        $closed = WaitLog (Closed "escape") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Verdict "E2 a card ($($oc.said)); NO click in it, Escape ($k): 'closed (escape)' $closed, the card gone $gone" ($oc.card -and $closed -and $gone)
    }
    Row "O1" {
        $null = Home
        $doc = Doc
        if (-not $doc) { throw "no page drawn in the main window" }
        $oc = OpenCard
        $cc = Count (Closed "outside")
        $c = ClickNode (Below $doc)
        $closed = WaitLog (Closed "outside") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Verdict "O1 a card ($($oc.said)); a click on the dimmed page below it ($c): 'closed (outside)' $closed, the card gone $gone" ($oc.card -and $closed -and $gone)
    }
    Row "X1" {
        $null = Home
        $oc = OpenCard
        $cc = Count (Closed "x")
        $c = ClickNode (CardButton $oc.card "Close")
        $closed = WaitLog (Closed "x") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Verdict "X1 a card ($($oc.said)); its X clicked ($c): 'closed (x)' $closed, the card gone $gone" ($oc.card -and $closed -and $gone)
    }
    Row "K1" {
        $null = Home
        $p0 = @(Pages).Count
        $oc = OpenCard
        $cc = Count (Closed "ctrl+w")
        $f = FocusCard $oc.card
        $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x57)
        $closed = WaitLog (Closed "ctrl+w") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Start-Sleep (2 * $slow)
        $p1 = @(Pages).Count; $kept = [bool](PageOf "c20home")
        Verdict "K1 a card ($($oc.said)); a click in it ($f), Ctrl+W ($k): 'closed (ctrl+w)' $closed, the card gone $gone; c20home still open $kept, page tabs $p0 -> $p1" ($oc.card -and $closed -and $gone -and $kept -and $p1 -eq $p0)
    }
    Row "T2" {
        $null = Home
        $oc = OpenCard
        $cc = Count (Closed "tab switch")
        $f = FocusCard $oc.card
        $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x09)
        $closed = WaitLog (Closed "tab switch") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Verdict "T2 a card ($($oc.said)); a click in it ($f), Ctrl+Tab ($k): 'closed (tab switch)' $closed, the card gone $gone" ($oc.card -and $closed -and $gone)
    }
    Row "T3" {
        $null = Home
        $oc = OpenCard
        $cc = Count (Closed "tab switch")
        $k = [E18Input]::Keys([uint32]$script:bpid, $false, 0x09)
        $closed = WaitLog (Closed "tab switch") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        Verdict "T3 a card ($($oc.said)); NO click in it, Ctrl+Tab ($k): 'closed (tab switch)' $closed, the card gone $gone" ($oc.card -and $closed -and $gone)
    }
    Row "B1" {
        $h = Home
        $oc = OpenCard
        $u0 = "$((CardPage).url)"
        $behind0 = UrlOf $h.id
        $c = ClickNode (Link "C20 next link")
        $next = Until { (CardPage).url } '/c20next\.html$'
        $k = "$([E18Input]::KeyDown([uint32]$script:bpid, 0x12)), $([E18Input]::Tap([uint32]$script:bpid, 0x25)), $([E18Input]::KeyUp([uint32]$script:bpid, 0x12))"
        $back = Until { (CardPage).url } '/c20target\.html'
        $still = [bool](Card)
        $behind1 = UrlOf $h.id
        Verdict "B1 a card ($($oc.said)) at '$u0'; its 'C20 next link' clicked ($c): the card at '$next'; Alt+Left ($k): the card at '$back', still up $still; the tab behind '$behind0' -> '$behind1'" ($oc.card -and $u0 -match '/c20target\.html' -and $next -match '/c20next\.html$' -and $back -match '/c20target\.html' -and $still -and $behind0 -match '/c20home\.html$' -and $behind1 -eq $behind0)
    }
    Row "T1" {
        $side = PageOf "c20side"
        if (-not $side) { $side = NewTab "c20side" }
        $null = Home
        $oc = OpenCard
        $cc = Count (Closed "tab switch")
        Show $side
        $closed = WaitLog (Closed "tab switch") ($cc + 1) 10
        $gone = -not (WaitCard $false)
        $vis = Evaluate $side.webSocketDebuggerUrl "document.visibilityState"
        Verdict "T1 a card ($($oc.said)); c20side activated (DevTools): 'closed (tab switch)' $closed, the card gone $gone, c20side $vis" ($oc.card -and $closed -and $gone)
    }
    Row "P1" {
        $t = PinnedFront
        if (-not $t) { throw "the pinned page 'C20 pinned' is not in front at c20pin.html" }
        $ca = Count $pinnedLink; $cs = Count $shownAny; $p0 = @(Pages).Count
        $c = ClickNode (Link "C20 same link")
        $u = Until { UrlOf $t.id } '/c20same\.html$'
        Start-Sleep (2 * $slow)
        $card = Card
        $arrow = [bool](NodeIn (Nodes $script:main) "Back to the pinned page" 0x2B)
        $p1 = @(Pages).Count; $rule = (Count $pinnedLink) - $ca; $shows = (Count $shownAny) - $cs
        $null = Evaluate $t.webSocketDebuggerUrl "history.back()"
        $returned = Until { UrlOf $t.id } '/c20pin\.html$'
        Verdict "P1 (D8) the pinned page's same-site link clicked ($c): the pinned page now '$u' (want c20same.html); 'a pinned page's link' +$rule, 'shown (' +$shows (want 0, 0); a card $([bool]$card); the back arrow $arrow; page tabs $p0 -> $p1; back to '$returned'" ($u -match '/c20same\.html$' -and -not $card -and $rule -eq 0 -and $shows -eq 0 -and $p1 -eq $p0)
    }
    Row "P2" {
        $t = PinnedFront
        if (-not $t) { throw "the pinned page 'C20 pinned' is not in front at c20pin.html" }
        $ca = Count $pinnedLink; $cs = Count (Shown "pinned page"); $p0 = @(Pages).Count
        $h0 = Evaluate $t.webSocketDebuggerUrl "history.length"
        $c = ClickNode (Link "C20 other link")
        $rule = WaitLog $pinnedLink ($ca + 1) 10
        $shown = WaitLog (Shown "pinned page") ($cs + 1) 10
        $card = WaitCard $true
        $cu = Until { (CardPage).url } '^http://localhost:\d+/c20target\.html'
        $u = UrlOf $t.id; $h1 = Evaluate $t.webSocketDebuggerUrl "history.length"; $p1 = @(Pages).Count
        Verdict "P2 (D8) the pinned page's other-site link clicked ($c): 'a pinned page's link to another site' $rule$(if (-not $rule) { ' (no line: ShouldPreviewPinnedLink said no)' }), 'shown (pinned page)' $shown$(if (-not $shown) { " ($(Why))" }); the card $([bool]$card) at '$cu'; the pinned page at '$u' (want c20pin.html), history.length $h0 -> $h1; page targets $p0 -> $p1 (want +1: the card's own page, no tab)" ($rule -and $shown -and $card -and $cu -match '^http://localhost:\d+/c20target\.html' -and $u -match '/c20pin\.html$' -and "$h1" -eq "$h0" -and $p1 -eq $p0 + 1)
    }
    Row "A1" {
        $null = Home
        $first0 = FirstToday
        $ca = Count $active; $p0 = @(Pages).Count
        $oc = OpenCard
        $cp = CardPage
        $n1 = $null; $o1 = $null; $h1 = $null
        if ($cp) { $n1 = Evaluate $cp.webSocketDebuggerUrl "+document.getElementById('n').textContent"; $o1 = Evaluate $cp.webSocketDebuggerUrl "String(performance.timeOrigin)"; $h1 = Evaluate $cp.webSocketDebuggerUrl "history.length" }
        $cc = Count (Closed "open as tab"); $co = Count $asTab
        $c = ClickNode (CardButton $oc.card "Open as tab")
        $closed = WaitLog (Closed "open as tab") ($cc + 1) 10
        $null = WaitLog $asTab ($co + 1) 10
        $g = @(Nth $asTab $co)
        $gone = -not (WaitCard $false)
        Start-Sleep (1 * $slow)
        $t = if ($cp) { @(Pages | Where-Object { $_.id -eq $cp.id }) | Select-Object -First 1 }
        if (-not $t) { $t = PageOf "c20target" }
        $n2 = $null; $o2 = $null; $h2 = $null; $vis = $null
        if ($t) { $n2 = Evaluate $t.webSocketDebuggerUrl "+document.getElementById('n').textContent"; $o2 = Evaluate $t.webSocketDebuggerUrl "String(performance.timeOrigin)"; $h2 = Evaluate $t.webSocketDebuggerUrl "history.length"; $vis = Evaluate $t.webSocketDebuggerUrl "document.visibilityState" }
        $first = Until { FirstToday } '^E18 c20target'
        $sw = (Count $active) - $ca; $p1 = @(Pages).Count
        Verdict "A1 Work's first Today tab before: '$first0'; a card ($($oc.said)): its page $(if ($cp) { "'$($cp.url)' ($($cp.type))" } else { 'not a DevTools target' }), counter $n1, history.length $h1 (want 2); 'Open as tab' clicked ($c): 'closed (open as tab)' $closed, $(if ($g.Count) { "'$($g[0])'" } else { 'no opened-as-tab line' }) (want 2 entries, loading 0); the card gone $gone; the same page a tab now $([bool]($t -and $cp -and $t.id -eq $cp.id)): timeOrigin $(if ($o1 -and $o2 -eq $o1) { 'kept' } else { "'$o1' -> '$o2'" }), counter $n2 (want > $n1), history.length $h2, $vis; Work's first Today tab '$first' (want E18 c20target); switches +$sw; page tabs $p0 -> $p1 (want +1)" ($oc.card -and $cp -and "$h1" -eq "2" -and $closed -and $g.Count -and $g[2] -eq "2" -and $g[3] -eq "0" -and $gone -and $t -and $o1 -and $o2 -eq $o1 -and "$n1$n2" -notmatch '[^\d]' -and "$n1" -and "$n2" -and [int]$n2 -gt [int]$n1 -and "$h2" -eq "2" -and $vis -eq "visible" -and $first -match '^E18 c20target' -and $sw -eq 0 -and $p1 -eq $p0 + 1)
    }
    Say "quit 1: $(Quit)"

    # ---- launch 2: the last session restored ----------------------------------------------------------------------
    $script:log = $logs[1]
    Launch @()
    Row "R1" {
        $went = Go "Work" $work
        $first = Until { FirstToday } '^E18 c20target|/c20target\.html'
        $t = WaitPage "c20target"
        $h = if ($t) { Evaluate $t.webSocketDebuggerUrl "history.length" }
        Verdict "R1 after the restart, Work ($went): its first Today tab '$first' (want E18 c20target); its page $(if ($t) { "'$($t.url)'" } else { 'not open' }) (want c20target.html#pushed), history.length $h (want 2)" ($first -match '^E18 c20target|/c20target\.html' -and $t -and $t.url -match '/c20target\.html#pushed$' -and "$h" -eq "2")
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
