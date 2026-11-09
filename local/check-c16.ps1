param([ValidateSet("Default", "Dcheck")][Alias("Build")][string]$OutDir = "Default", [string]$Tag = "c16", [double]$IdleMinutes = 15,
      [string[]]$Rows = @())
# C16 + C25 + C27 + C9 + C11 (patch 87 "87-small-five", <local-path>\Helium-workspace\c16-progress.md), hands-free. On a throwaway
# copy of the smoke profile (Home, Work, Canary, Private, Unpin; every workspace's pinned rows Example A, Smoke
# folder (open: Wikipedia, a github page), Closed folder (Hidden), Example D -- ids a, f, b, c, g, h, d + the
# workspace's index: Work's a1, f1, b1, c1, g1, h1, d1), Sessions emptied, Unpin's pinned rows REMOVED (B2's empty
# workspace), the sidebar 280 wide (five chips, no scroll arrow). Real right-clicks, clicks, drags and keys (SendInput,
# guarded: the user's desktop, the fork's window under the point or in front), so it starts only when
# <local-path>\Helium-workspace\e17-pc-free.ps1 says FREE. Start it from the session shell with the Claude window minimized.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-c16.ps1 [-OutDir Dcheck] [-IdleMinutes 0] [-Rows E1,D1]
# Launch 1, in Work unless a row says otherwise (Today tabs E18 c16t, c16u, c16fav, c16g1, c16g2 opened there):
#   E1  Example A's menu > "Set emoji..." (the rail's one-field bubble), U+1F680 then "x" typed, Enter: "pins: emoji of
#       'a1' set"; the pins file's a1 has "emoji" = U+1F680 alone (the first character kept, D5)
#   E2  Closed folder (g1) the same with U+1F4DA: logged; the file's g1, still a folder, has it
#   E3  Today tab c16t's menu > "Set emoji..." (a tab-modal box), U+1F525, Enter: "tab emoji set at index N"; graded in
#       launch 2: "restored tab emoji" exactly once (c16t's; E4 cleared c16u's)
#   E4  a blank box clears: Example D (d1) set to U+1F319, then its box emptied + Enter: "set" then "cleared", the file's
#       d1 has no "emoji" key; Today tab c16u set to U+1F340, then its box made two spaces + Enter: "tab emoji set", then
#       "tab emoji cleared"
#   D1  C25: Example D dragged onto the LOWER part of the github row (Smoke folder's LAST row): "pins: moved 'd1' after
#       'c1'", f1 holds b1,c1,d1, Work's roots a1,f1,g1; then Example A onto the UPPER part of Closed folder (the row
#       below the folder's end): "moved 'a1' before 'g1'", roots f1,a1,g1, f1 unchanged -- after the folder
#   F1  C27: c16fav made a favorite by its menu's "Pin", then its menu's Close: "archived a manual close in '<Work>'
#       (favorite)"; the archive file's entry: "favorite": true, workspace Work, reason manual
#   F2  the bar's Archive: the row NAMED "Favorite: E18 c16fav" (the star is only drawn) pressed: "archive: restored an
#       entry into '<Work>' a favorite"; "E18 c16fav - Pinned" drawn again, no switch, the entry gone from the file
#   B1  C11b: the Work chip's menu > "Bookmark all tabs": "bookmarks: saved '<Work>' as N pinned + M Today", N = Work's
#       pinned pages in the pins file, M = the Today tabs drawn; after the quit the Bookmarks file has Other bookmarks >
#       Workspaces > "Work YYYY-MM-DD HH:MM" holding Work's pinned rows in order (folders as folders), then "Today" (M)
#   B2  the Unpin chip's menu > "Bookmark all tabs" (no pinned rows, no tabs): "bookmarks: nothing to save in
#       '<Unpin>'"; after the quit no "Unpin ..." folder under Workspaces
#   G1  C11a: c16g1 + Ctrl+click c16g2, the menu's "Add tabs to new group" (> "New group"), "grp" typed in the group's
#       bubble, its Purple pressed; c16g1's menu > "Make this group a workspace": "group -> new workspace '<guid>', 2
#       tab(s)", the window switched to <guid>, both tabs still "Part of" their group (the header named after it is
#       printed, not graded: an empty pinned section may draw none); after the quit Preferences lists <guid> titled
#       "grp" ("New workspace" if the name did not take), colour 6 (Purple)
#   W1  C9, on Canary: a second window (--new-window); window 1 clicks Smoke folder (f2), window 2 clicks Closed
#       folder (g2): "folder 'f2' closed in this window (1 other window(s) keep theirs)", "folder 'g2' open ... (1 ...)";
#       MSAA (msaa-press -Expand): window 1 both folders COLLAPSED (Wikipedia, Hidden not drawn), window 2 both EXPANDED
#       (both drawn); the pins file, the last change anywhere: f2 closed, g2 open. Quit by the app menu's More tools >
#       Exit, which keeps both windows in the session (check-e14d1-auto's J)
# Launch 2 (--restore-last-session):
#   W2  both windows back: "window folders: restored N" at least twice (N >= 2); on Canary one window draws both folders
#       collapsed, the other both expanded (which one holds c16w2 is printed). Quit by Exit again, NO folder touched
# Launch 3 (--restore-last-session again; review R1: a restored window must write its folders back at once, since the
# session's startup rebuild runs before any window exists -- without that, launch 2's quit forgot them):
#   W3  as W2: both windows back, "window folders: restored N" at least twice, one window both collapsed, one both open
#   M1  0 crash markers in every log, case-sensitive (Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr:
#       "dangling" never matches the histogram DanglingUserSubscription...)
# -Rows E1,D1 runs only those rows (W3 brings W2, W2 brings W1; launch 2 runs for E3 or W2); the setup and M1 always run. Every line
# goes to the screen and to <local-path>\Helium-workspace\<Tag>-check-<default|dcheck>[-rows].txt. A pass needs every verdict.
. "$PSScriptRoot\e18-lib.ps1"
# `pwsh -File ... -Rows E1,D1` passes ONE string "E1,D1": split it.
$Rows    = @($Rows | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
if ($Rows -contains "W3" -and $Rows -notcontains "W2") { $Rows += "W2" }
if ($Rows -contains "W2" -and $Rows -notcontains "W1") { $Rows += "W1" }
$ws      = "<local-path>\Helium-workspace"
$here    = $PSScriptRoot
$bin     = "$ws\helium-windows\build\src\out\$OutDir"
$exe     = "$bin\chrome.exe"
$py      = "C:\Python314\python.exe"
$smoke   = "$ws\testprofile-e15b-smoke"
$suffix  = if ($OutDir -eq "Dcheck") { "-dcheck" } else { "" }
$prof    = "$ws\testprofile-$Tag$suffix"
$dflt    = "$prof\Default"
$logs    = @(1..3 | ForEach-Object { if ($OutDir -eq "Dcheck") { "$ws\$Tag-dcheck-exercise$_.log" } else { "$ws\$Tag-run$_.log" } })
$txt     = "$ws\$Tag-check-$($OutDir.ToLower())$(if ($Rows.Count) { '-rows' }).txt"
$pageDir = "$ws\$Tag-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
$slow    = if ($OutDir -eq "Dcheck") { 3 } else { 1 }
$every   = @("E1", "E2", "E3", "E4", "D1", "F1", "F2", "B1", "B2", "G1", "W1", "W2", "W3")
$want    = if ($Rows.Count) { @($every | Where-Object { $Rows -contains $_ }) } else { $every }
$total   = $want.Count + 2   # + the setup and M1
$second  = ($want -contains "E3") -or ($want -contains "W2")
# The emoji, made from code points: the file stays ASCII whatever editor opens it.
function U([int]$cp) { [char]::ConvertFromUtf32($cp) }
$rocket = U 0x1F680; $books = U 0x1F4DA; $fire = U 0x1F525; $moon = U 0x1F319; $clover = U 0x1F340
# The contract's lines (patch 87, grepped), graded case-sensitively.
$active   = "\[workspaces\] active workspace -> '([^']*)'"
$opensOn  = "\[workspaces\] a window opens on workspace '([^']*)'"
function PinEmoji([string]$id, [string]$what) { "\[workspaces\] pins: emoji of '$id' $what" }
$tabSet   = "\[workspaces\] tab emoji set at index (\d+)"
$tabClr   = "\[workspaces\] tab emoji cleared at index (\d+)"
$restored = "\[workspaces\] restored tab emoji"
function Moved([string]$id, [string]$where, [string]$to) { "\[workspaces\] pins: moved '$id' $where '$to'" }
function FavFiled([string]$g) { "\[workspaces\] archived a manual close in '$g' \(favorite\)" }
function FavBack([string]$g) { "\[workspaces\] archive: restored an entry into '$g' a favorite" }
$screen   = "archive screen: opened"
$saved    = "\[workspaces\] bookmarks: saved '([^']*)' as (\d+) pinned \+ (\d+) Today"
function Nothing([string]$g) { "\[workspaces\] bookmarks: nothing to save in '$g'" }
$fromGrp  = "\[workspaces\] group -> new workspace '([^']*)', (\d+) tab\(s\)"
function Folder([string]$id, [string]$how) { "\[workspaces\] folder '$id' $how in this window \((\d+) other window\(s\) keep theirs\)" }
$winDirs  = "\[workspaces\] window folders: restored (\d+)"

$script:out = [System.Collections.Generic.List[string]]::new()
$script:passed = 0; $script:failed = 0; $script:bpid = 0; $script:main = [IntPtr]::Zero; $script:w2 = [IntPtr]::Zero
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Save { try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8 } catch { Write-Host "could not write $($txt): $_" } }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; Save; exit 1 }
function Lines([string]$re) { if (Test-Path -LiteralPath $script:log) { @(Select-String -LiteralPath $script:log -CaseSensitive -Pattern $re) } else { @() } }
function Count([string]$re) { @(Lines $re).Count }
function WaitLog([string]$re, [int]$n = 1, [int]$s = 15) {
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Count $re) -ge $n) { return $true }; Start-Sleep -Milliseconds 300 }
    $false
}
# The `i`-th line (from 0) matching `re`: the whole match, then its groups (empty when none).
function Nth([string]$re, [int]$i) { $l = @(Lines $re); if ($l.Count -gt $i) { @($l[$i].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Grp([string]$re) { $l = @(Lines $re); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Running { $script:bpid -and [bool](Get-Process -Id $script:bpid -EA SilentlyContinue) }
function Hex([string]$s) { if (-not $s) { return "none" }; @($s.EnumerateRunes() | ForEach-Object { 'U+{0:X}' -f $_.Value }) -join ' ' }

# ---- MSAA (msaa-press.ps1) and the menus, as check-c33's ----------------------------------------------------------
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Press([IntPtr]$h, [string]$name, [int]$role) { "$(Msaa $h @('-Name', $name, '-Role', $role))" }
function Nodes([IntPtr]$h) { ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) }
function NodeIn($nodes, [string]$name, [int]$role) { @($nodes | Where-Object { $_.shown -and $_.role -eq $role -and $_.name -eq $name } | Sort-Object t) | Select-Object -Last 1 }
# A restored page never loaded since is named by its address ("127.0.0.1:<port>/c16t.html"): "E18 c16t" matches that.
function TabIn($nodes, [string]$title) {
    $page = if ($title -like "E18 *") { "*/$($title.Substring(4)).html" } else { $null }
    @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and ($_.name -eq $title -or $_.name.StartsWith("$title - ") -or ($page -and $_.name -like $page)) }) | Select-Object -First 1
}
function Today($nodes) { @($nodes | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -notmatch ' - Pinned$' } | Sort-Object t, l) }
function Names($list) { @($list | ForEach-Object { $_.name }) -join ", " }
function Popups { $wins = @([E18Input]::Windows([uint32]$script:bpid)); @([E18Input]::Others([uint32]$script:bpid, $script:main) | Where-Object { $wins -notcontains $_ }) }
function NoPopups { foreach ($i in 1..3) { if (-not @(Popups).Count) { return }; $null = [E18Input]::Tap([uint32]$script:bpid, 0x1B) } }
function PopupNames { @(foreach ($w in Popups) { Nodes $w | Where-Object { $_.shown } | ForEach-Object { $_.name } }) }
# Node `n` of window `w` pressed through MSAA -- or clicked at its middle when its name did not survive MSAA's text
# round trip (an ellipsis: "Set emoji..." arrives as one character; an emoji mark).
function PressNode([IntPtr]$w, $n) {
    $r = Press $w $n.name $n.role
    if ($r -notmatch '^MSAA: pressed') { $r += "; $([E18Input]::Click($w, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false))" }
    "'$($n.name)' $r"
}
# The first shown node matching `re` in a menu or bubble, pressed.
function OtherPress([string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in Popups) {
            $n = @(Nodes $w | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return PressNode $w $n }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re' (shown: $((@(PopupNames) | Select-Object -First 40) -join ' | '))"
}
function RightClick([IntPtr]$h, $n, [string]$what) {
    if (-not $n) { return "no $what drawn" }
    $r = [E18Input]::Click($h, $n.l + [int]($n.w / 3), $n.t + [int]($n.h / 2), $true)
    Start-Sleep -Milliseconds (800 * $slow)
    $r
}
# Today tab `title`'s menu (a guarded right-click), then its items matching each of `res` pressed in turn.
function TabMenu([string]$title, [string[]]$res) {
    $r = RightClick $script:main (TabIn (Nodes $script:main) $title) "Today tab '$title'"
    if ($r -ne "right-clicked") { return $r }
    foreach ($re in $res) {
        $p = OtherPress $re
        $r += "; $p"
        if ($p -like "nothing matching*") { NoPopups; break }
        Start-Sleep -Milliseconds (500 * $slow)
    }
    $r
}
# Pinned row `name`'s menu in window `h`, then the item matching `re`.
function RowMenu([IntPtr]$h, [string]$name, [string]$re) {
    $r = RightClick $h (NodeIn (Nodes $h) $name 0x24) "pinned row '$name'"
    if ($r -ne "right-clicked") { return $r }
    $p = OtherPress $re
    if ($p -like "nothing matching*") { NoPopups }
    "$r; $p"
}
function ClickTab([string]$title, [switch]$Ctrl) {
    $n = TabIn (Nodes $script:main) $title
    if (-not $n) { return "no Today tab '$title' drawn" }
    $p = [uint32]$script:bpid
    if ($Ctrl) { $d = [E18Input]::KeyDown($p, 0x11); if ($d -ne "sent") { return "Ctrl not held: $d" } }
    try { [E18Input]::Click($script:main, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2), $false) }
    finally { if ($Ctrl) { $null = [E18Input]::KeyUp($p, 0x11) } }
}
function ClickRow([IntPtr]$h, [string]$name) {
    $n = NodeIn (Nodes $h) $name 0x24
    if (-not $n) { return "no pinned row '$name' drawn" }
    [E18Input]::Click($h, $n.l + [int]($n.w * 0.4), $n.t + [int]($n.h / 2), $false)
}
# Workspace `name` shown in window `h` by its chip, pressed through MSAA: true once its header (a heading) is drawn.
function Go([IntPtr]$h, [string]$name, [string]$guid) {
    if (NodeIn (Nodes $h) $name 0x14) { return $true }
    $c = Count $active
    $null = Press $h $name 0x2B
    $ok = (WaitLog $active ($c + 1) 10) -and (@(Grp $active)[1] -eq $guid)
    Start-Sleep (1 * $slow)
    $ok
}
# An emoji box (a pinned row's bubble, or a Today tab's tab-modal box): whether one shows -- its title, or its field
# "Icon (an emoji; empty for none)" -- in a popup or in the window itself.
function BoxShown {
    $t0 = Get-Date
    do {
        $n = @(@(PopupNames) + @(Nodes $script:main | Where-Object { $_.shown } | ForEach-Object { $_.name }))
        if (@($n | Where-Object { $_ -match '^Set emoji|^Icon \(an emoji' }).Count) { return "a box shown" }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 5 * $slow)
    "NO box shown (popups: $((@(PopupNames) | Select-Object -First 20) -join ' | '))"
}
# Keys into the box in front: -Clear selects its text first (Ctrl+A) and, with no `text`, deletes it; `text` typed as
# characters; Enter accepts (the box's OK).
function BoxType([string]$text, [switch]$Clear) {
    $p = [uint32]$script:bpid
    $k = @()
    if ($Clear) { $k += "Ctrl+A $([E18Input]::Keys($p, $false, 0x41))"; if (-not $text) { $k += "Delete $([E18Input]::Tap($p, 0x2E))" } }
    if ($text) { $k += "$(Hex $text) $([C16Input]::Type($p, $text))" }
    $k += "Enter $([E18Input]::Tap($p, 0x0D))"
    $k -join ", "
}
# A pinned row's box: typed into only once it shows -- else the keys would reach the focused row, and Enter opens it.
function RowEmoji([string]$name, [string]$text, [switch]$Clear) {
    $r = RowMenu $script:main $name '^Set emoji'
    if ($r -notlike "right-clicked; '*") { return $r }
    Start-Sleep (1 * $slow)
    $b = BoxShown
    if ($b -ne "a box shown") { NoPopups; return "$r; $b; nothing typed" }
    "$r; $b; $(BoxType $text -Clear:$Clear)"
}
# A Today tab's tab-modal box: typed into even when MSAA did not find it (where a web-modal dialog shows in the tree is
# not certain); without it the keys reach the page, where they do nothing.
function TabEmoji([string]$title, [string]$text, [switch]$Clear) {
    $r = TabMenu $title @('^Set emoji')
    if ($r -notlike "right-clicked; '*") { return $r }
    Start-Sleep (1 * $slow)
    "$r; $(BoxShown); $(BoxType $text -Clear:$Clear)"
}
# A guarded real drag from pinned row node `src` (40% of its width) to `fy` of node `dst`'s height.
function DragTo($src, $dst, [double]$fy) {
    [E18Input]::Drag($script:main, $src.l + [int]($src.w * 0.4), $src.t + [int]($src.h / 2), $dst.l + [int]($dst.w * 0.4), $dst.t + [int]($dst.h * $fy))
}
# Window `h`'s folder rows on the workspace it shows (msaa-press -Expand): Smoke folder's and Closed folder's state
# (expanded / collapsed / none / no row), and whether their pages Wikipedia and Hidden are drawn.
function FolderLook([IntPtr]$h) {
    $x = @(foreach ($l in @(Msaa $h @("-List", "-Rect", "-Expand"))) {
        $n = @(ParseMsaaNodes @($l))
        if ($n.Count) { $n[0] | Add-Member -NotePropertyName state -NotePropertyValue $(if ($l -match '\|EXPANDED$') { "expanded" } elseif ($l -match '\|COLLAPSED$') { "collapsed" } else { "none" }) -PassThru }
    })
    $s = NodeIn $x "Smoke folder" 0x24; $c = NodeIn $x "Closed folder" 0x24
    [pscustomobject]@{ smoke = $(if ($s) { $s.state } else { "no row" }); closed = $(if ($c) { $c.state } else { "no row" })
                       wiki = [bool](NodeIn $x "Wikipedia" 0x24); hidden = [bool](NodeIn $x "Hidden" 0x24); w2tab = [bool](TabIn $x "E18 c16w2") }
}
function Look($f) { "Smoke folder $($f.smoke), Closed folder $($f.closed), Wikipedia $(if ($f.wiki) { 'drawn' } else { 'not drawn' }), Hidden $(if ($f.hidden) { 'drawn' } else { 'not drawn' })" }
function AllShut($f) { $f.smoke -eq "collapsed" -and $f.closed -eq "collapsed" -and -not $f.wiki -and -not $f.hidden }
function AllOpen($f) { $f.smoke -eq "expanded" -and $f.closed -eq "expanded" -and $f.wiki -and $f.hidden }
function Row([string]$row, [scriptblock]$body, [switch]$Offline) {
    if ($Rows.Count -and $row -ne "setup" -and $Rows -notcontains $row) { return }
    try { & $body } catch {
        Say "ERROR $row (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
        if (-not $Offline -and -not (Running)) { throw "the browser is gone after $row" }
    }
    if (-not $Offline) { NoPopups }
}

# ---- the files: pins, archive (written 2.5 s after a change), and after a quit Bookmarks and Preferences ---------
function Pins { Start-Sleep (4 * $slow); try { Get-Content -Raw -Encoding UTF8 -LiteralPath "$dflt\Workspace Pins" | ConvertFrom-Json } catch { $null } }
function RootsOf($d, [string]$g) { if ($d) { @($d.workspaces.$g | Where-Object { $_ }) } else { @() } }
function FindPin($list, [string]$id) {
    foreach ($n in @($list)) { if (-not $n) { continue }; if ($n.id -eq $id) { return $n }; $f = FindPin $n.children $id; if ($f) { return $f } }
    $null
}
function Ids($list) { @($list | Where-Object { $_ } | ForEach-Object { $_.id }) -join "," }
function EmojiOf($n) { if ($n -and $n.PSObject.Properties["emoji"]) { [string]$n.emoji } else { "" } }
# The pinned pages under `list` (a split's two count, a folder's by its children): what Bookmark all tabs saves.
function PageCount($list) { $c = 0; foreach ($n in @($list | Where-Object { $_ })) { if ($n.type -eq "folder" -or $n.type -eq "split") { $c += PageCount $n.children } else { $c++ } }; $c }
# A pinned row as Bookmark all tabs lays it out (a folder as a folder, a split as its pages), and a bookmark node.
function PinShape($n) {
    if ($n.type -eq "folder") { "folder:$($n.title)[$((@($n.children | Where-Object { $_ } | ForEach-Object { PinShape $_ })) -join ',')]" }
    elseif ($n.type -eq "split") { (@($n.children | ForEach-Object { PinShape $_ })) -join "," }
    else { "url:$($n.url)" }
}
function BmShape($n) { if ($n.type -eq "url") { "url:$($n.url)" } else { "folder:$($n.name)[$((@($n.children | Where-Object { $_ } | ForEach-Object { BmShape $_ })) -join ',')]" } }
function Entries { Start-Sleep (4 * $slow); try { @((Get-Content -Raw -Encoding UTF8 -LiteralPath "$dflt\Workspace Archive" | ConvertFrom-Json).entries) } catch { @() } }
function EntryOf([string]$name) { @(Entries | Where-Object { $_.url -like "*/$name.html" }) | Select-Object -First 1 }

# ---- the pages, DevTools, one launch, the quit ---------------------------------------------------------------------
function Url([string]$path) { "http://127.0.0.1:$($script:srv.port)/$path" }
function Base { "http://127.0.0.1:$($script:port)/json" }
function NewTab([string]$name) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$(Base)/new?$([uri]::EscapeDataString((Url "$name.html")))" } catch { $null }
    if (-not $t) { throw "DevTools opened no tab for '$name'" }
    $t0 = Get-Date
    while ((Evaluate $t.webSocketDebuggerUrl "document.readyState === 'complete' ? document.title : ''") -ne "E18 $name" -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep -Milliseconds 300 }
    Start-Sleep -Milliseconds (500 * $slow)
}
function Launch {
    Remove-Item -LiteralPath "$prof\DevToolsActivePort", $script:log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$($script:log)`"", "--v=0", "--remote-debugging-port=0",
           "--force-color-profile=srgb", "--no-first-run", "--no-default-browser-check", "--restore-last-session")
    $script:bpid = (Start-Process $exe -PassThru -ArgumentList $a).Id
    $script:main = [IntPtr]::Zero; $script:w2 = [IntPtr]::Zero; $t0 = Get-Date
    while ($script:main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1; $p = Get-Process -Id $script:bpid -EA SilentlyContinue; if ($p) { $script:main = $p.MainWindowHandle } }
    if ($script:main -eq [IntPtr]::Zero) { throw "no browser window" }
    $null = WaitLog "pins: drew \d+ row\(s\) of '" 1 30
    [E18Input]::Place($script:main, $script:box[0], $script:box[1], $script:box[2], $script:box[3])
    Start-Sleep (2 * $slow)
    $t0 = Get-Date
    while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1 }
    $script:port = [int](Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1)
    Say "browser $($script:bpid), DevTools port $($script:port), pages on port $($script:srv.port), log $($script:log); window dpi $([E18Input]::Dpi($script:main))"
}
# Two windows placed side by side, `a` left; both topmost, so a guarded click finds its window under the point.
function SideBySide([IntPtr]$a, [IntPtr]$b) {
    $half = [int]($script:scr[0] / 2)
    [E18Input]::Place($a, 0, 0, $half, $script:scr[1] - 80); [E18Input]::Place($b, $half, 0, $half, $script:scr[1] - 80)
    Start-Sleep (1 * $slow)
}
# The app menu's More tools > Exit (Helium keeps Exit there): chrome::AttemptUserExit -- unlike closing the windows one
# by one, the session keeps every window (check-e14d1-auto's J). What happened.
function AppExit {
    NoPopups
    $r = "Alt+F $([C16Input]::AltKey([uint32]$script:bpid, 0x46))"
    $r += "; $(OtherPress '^More tools$')"
    Start-Sleep (1 * $slow)
    "$r; $(OtherPress '^Exit$')"
}
# The quit. -Keep with two windows: the app menu's Exit first; else (or if that left it running) each window closed as
# its X does. Then any leftover process of this build stopped. What happened.
function Quit([switch]$Keep) {
    if (-not (Running)) { return "the browser was not running" }
    $how = ""
    if ($Keep -and @([E18Input]::Windows([uint32]$script:bpid)).Count -gt 1) {
        $how = "app menu: $(AppExit); "
        $t0 = Get-Date
        while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    }
    if (Running) {
        $how += "windows closed; "
        foreach ($w in [E18Input]::Windows([uint32]$script:bpid)) { [E18Input]::CloseWindow($w) }
        $t0 = Get-Date
        while ((Running) -and ((Get-Date) - $t0).TotalSeconds -lt 30 * $slow) { Start-Sleep 1 }
    }
    $closed = -not (Running)
    Start-Sleep 2
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" })
    $left | Stop-Process -Force -EA SilentlyContinue
    "$how$(if ($closed) { 'closed' } else { 'NOT closed' })$(if ($left.Count) { ", $($left.Count) process(es) force-stopped" })"
}

# ==== the run =====================================================================================================
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
if (-not (Test-Path -LiteralPath $py)) { Abort "no $py" }
& $py -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "group -> new workspace '"
$with87 = $LASTEXITCODE -eq 0
Say "build: $OutDir\chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime), $(if ($with87) { 'WITH' } else { 'WITHOUT' }) patch 87; rows: $($want -join ', ')"
if (-not $with87) { Abort "this chrome.dll has no patch 87 ('group -> new workspace' is not in it)" }
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for real input ($free)" }
E18InputType
# What E18Input has not: characters typed as characters (an emoji's two UTF-16 halves), and Alt+key with Alt let go at
# once (check-e14d1-auto's AltKey). Both only to the browser's window in front, on the user's desktop.
if (-not ("C16Input" -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class C16Input {
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint data, flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetUserObjectInformation(IntPtr h, int index, StringBuilder buf, int len, out int needed);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr h);
  // Null when the input desktop is the user's (not the lock screen) and the window in front is `pid`'s; else why not.
  static string Guard(uint pid) {
    IntPtr d = OpenInputDesktop(0, false, 0x0001);  // DESKTOP_READOBJECTS
    if (d == IntPtr.Zero) return "no input desktop (the screen is locked?)";
    StringBuilder name = new StringBuilder(256); int needed;
    GetUserObjectInformation(d, 2, name, 256, out needed);  // UOI_NAME
    CloseDesktop(d);
    if (name.ToString() != "Default") return "the input desktop is '" + name + "' (the screen is locked?)";
    uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p);
    return p == pid ? null : "not sent: the window in front is not the browser's";
  }
  static INPUT Key(ushort vk, ushort scan, uint flags) { INPUT i = new INPUT(); i.type = 1; i.u.ki.vk = vk; i.u.ki.scan = scan; i.u.ki.flags = flags; return i; }
  // KEYEVENTF_UNICODE (4), each UTF-16 unit down then up (KEYUP 2), all in one SendInput so a surrogate pair arrives
  // whole.
  public static string Type(uint pid, string text) {
    string e = Guard(pid); if (e != null) return e;
    List<INPUT> all = new List<INPUT>();
    foreach (char c in text) { all.Add(Key(0, c, 4)); all.Add(Key(0, c, 4 | 2)); }
    SendInput((uint)all.Count, all.ToArray(), Marshal.SizeOf(typeof(INPUT)));
    Thread.Sleep(500);
    return "typed";
  }
  public static string AltKey(uint pid, ushort vk) {
    string e = Guard(pid); if (e != null) return e;
    INPUT[] k = { Key(0x12, 0, 0), Key(vk, 0, 0), Key(vk, 0, 2), Key(0x12, 0, 2) };
    SendInput(4, k, Marshal.SizeOf(typeof(INPUT)));
    Thread.Sleep(1000);
    return "sent";
  }
}
"@
}
$script:scr = [E18Input]::Screen()
$script:box = @(40, 40, [Math]::Min(1400, $script:scr[0] - 80), [Math]::Min(1300, $script:scr[1] - 120))
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
if (-not (Test-Path -LiteralPath "$dflt\Preferences")) { Abort "the copy of $smoke failed" }
Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath (@("$dflt\Workspace Archive") + $logs) -EA SilentlyContinue
& $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false"
if ($LASTEXITCODE -ne 0) { Abort "the preferences were not seeded into $prof" }
# B2's empty workspace: Unpin without pinned rows (and never shown, so no Today tab).
& $py -I -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); d['workspaces'].pop(sys.argv[2]); open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$dflt\Workspace Pins" $unpin
if ($LASTEXITCODE -ne 0) { Abort "Unpin's pinned rows were not removed from the copy" }
$script:srv = ServePages $pageDir @("c16t", "c16u", "c16fav", "c16g1", "c16g2", "c16w2")
if (-not $script:srv.ok) { Abort "the local pages were not served" }
$script:e3 = $null; $script:b1 = $null; $script:b2 = $null; $script:g1 = $null

try {
    # ---- launch 1 --------------------------------------------------------------------------------------------------
    $script:log = $logs[0]
    Launch
    Row "setup" {
        $s = "Work $(Go $script:main 'Work' $work)"
        foreach ($nm in "c16t", "c16u", "c16fav", "c16g1", "c16g2") { NewTab $nm }
        $t = @(Today (Nodes $script:main))
        Verdict "setup ($s): Work's Today $(Names $t)" (@("c16t", "c16u", "c16fav", "c16g1", "c16g2" | Where-Object { TabIn $t "E18 $_" }).Count -eq 5)
    }
    Row "E1" {
        $c = Count (PinEmoji "a1" "set")
        $r = RowEmoji "Example A" "$($rocket)x"
        $ok = WaitLog (PinEmoji "a1" "set") ($c + 1) 10
        $e = EmojiOf (FindPin (RootsOf (Pins) $work) "a1")
        Verdict "E1 pinned page Example A > Set emoji..., U+1F680 + 'x', Enter ($r): 'pins: emoji of a1 set' $ok; the pins file's a1 emoji: $(Hex $e) (want U+1F680 alone)" ($ok -and $e -ceq $rocket)
    }
    Row "E2" {
        $c = Count (PinEmoji "g1" "set")
        $r = RowEmoji "Closed folder" $books
        $ok = WaitLog (PinEmoji "g1" "set") ($c + 1) 10
        $n = FindPin (RootsOf (Pins) $work) "g1"
        $e = EmojiOf $n
        Verdict "E2 folder Closed folder > Set emoji..., U+1F4DA, Enter ($r): 'pins: emoji of g1 set' $ok; the file's g1: type $(if ($n) { $n.type } else { 'MISSING' }), emoji $(Hex $e) (want folder, U+1F4DA)" ($ok -and $n -and $n.type -eq "folder" -and $e -ceq $books)
    }
    Row "E3" {
        $c = Count $tabSet
        $r = TabEmoji "E18 c16t" $fire
        $ok = WaitLog $tabSet ($c + 1) 10
        $script:e3 = [pscustomobject]@{ said = $r; ok = $ok }
        Say "      E3 (graded after the restart) Today tab c16t > Set emoji..., U+1F525, Enter ($r): 'tab emoji set at index N' $ok"
    }
    Row "E4" {
        $cs = Count (PinEmoji "d1" "set"); $cc = Count (PinEmoji "d1" "cleared")
        $r1 = RowEmoji "Example D" $moon
        $s1 = WaitLog (PinEmoji "d1" "set") ($cs + 1) 10
        $r2 = RowEmoji "Example D" "" -Clear
        $s2 = WaitLog (PinEmoji "d1" "cleared") ($cc + 1) 10
        $n = FindPin (RootsOf (Pins) $work) "d1"
        $kept = $n -and $n.PSObject.Properties["emoji"]
        $ts = Count $tabSet; $tc = Count $tabClr
        $r3 = TabEmoji "E18 c16u" $clover
        $t1 = WaitLog $tabSet ($ts + 1) 10
        # Two spaces over the selected emoji: the service trims them away (FirstGrapheme), which clears it.
        $r4 = TabEmoji "E18 c16u" "  " -Clear
        $t2 = WaitLog $tabClr ($tc + 1) 10
        Verdict "E4 a blank box clears: Example D set ($r1): $s1, then emptied + Enter ($r2): 'cleared' $s2, the file's d1 $(if (-not $n) { 'MISSING' } elseif ($kept) { "STILL has emoji $(Hex (EmojiOf $n))" } else { 'has no emoji key' }); Today tab c16u set ($r3): $t1, then two spaces + Enter ($r4): 'tab emoji cleared' $t2" ($s1 -and $s2 -and $n -and -not $kept -and $t1 -and $t2)
    }
    Row "D1" {
        $nodes = Nodes $script:main
        $drawn = @($nodes | Where-Object { $_.shown -and $_.role -eq 0x24 } | Sort-Object t)
        $wiki = NodeIn $nodes "Wikipedia" 0x24
        # Smoke folder's last row: the github page (c1, untitled), the row under Wikipedia.
        $last = if ($wiki) { @($drawn | Where-Object { $_.t -gt $wiki.t }) | Select-Object -First 1 }
        $src = NodeIn $nodes "Example D" 0x24
        $cm = Count (Moved "d1" "after" "c1")
        $r1 = if ($src -and $last) { DragTo $src $last 0.8 } else { "not dragged: Example D $([bool]$src), the row under Wikipedia $([bool]$last)" }
        $ok1 = WaitLog (Moved "d1" "after" "c1") ($cm + 1) 8
        $d = Pins; $k1 = Ids (FindPin (RootsOf $d $work) "f1").children; $o1 = Ids (RootsOf $d $work)
        $nodes = Nodes $script:main
        $src = NodeIn $nodes "Example A" 0x24; $dst = NodeIn $nodes "Closed folder" 0x24
        $cb = Count (Moved "a1" "before" "g1")
        $r2 = if ($src -and $dst) { DragTo $src $dst 0.15 } else { "not dragged: Example A $([bool]$src), Closed folder $([bool]$dst)" }
        $ok2 = WaitLog (Moved "a1" "before" "g1") ($cb + 1) 8
        $d = Pins; $k2 = Ids (FindPin (RootsOf $d $work) "f1").children; $o2 = Ids (RootsOf $d $work)
        $moves = @(Lines "\[workspaces\] pins: moved '" | Select-Object -Last 3 | ForEach-Object { $_.Line -replace '^.*\[workspaces\] ', '' }) -join " | "
        Verdict "D1 drawn rows $(Names $drawn); Example D onto the lower part of '$(if ($last) { $last.name } else { '-' })' ($r1): 'moved d1 after c1' $ok1, f1 holds $k1 (want b1,c1,d1), roots $o1 (want a1,f1,g1); Example A onto the upper part of Closed folder ($r2): 'moved a1 before g1' $ok2, roots $o2 (want f1,a1,g1), f1 holds $k2 (want b1,c1,d1); the last moves: $moves" ($ok1 -and $k1 -eq "b1,c1,d1" -and $o1 -eq "a1,f1,g1" -and $ok2 -and $o2 -eq "f1,a1,g1" -and $k2 -eq "b1,c1,d1")
    }
    Row "F1" {
        $r = TabMenu "E18 c16fav" @('^Add to Favorites')
        $fav = $false; $t0 = Get-Date
        while (-not $fav -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1; $fav = [bool](NodeIn (Nodes $script:main) "E18 c16fav - Pinned" 0x25) }
        $cf = Count (FavFiled $work)
        $r += "; $(TabMenu 'E18 c16fav' @('^Close( Ctrl\+W)?$'))"
        $ok = WaitLog (FavFiled $work) ($cf + 1) 10
        $why = @(Lines "\[workspaces\] (not )?archived" | Select-Object -Last 2 | ForEach-Object { $_.Line -replace '^.*\[workspaces\] ', '' }) -join " | "
        $e = EntryOf "c16fav"
        Verdict "F1 c16fav made a favorite ('E18 c16fav - Pinned' drawn: $fav), then closed ($r): 'archived a manual close in Work (favorite)' $ok (the last archive lines: $why); the file's entry $(if ($e) { "favorite $($e.favorite), workspace $($e.workspace), reason $($e.reason)" } else { 'MISSING' }) (want True, Work, manual)" ($fav -and $ok -and $e -and $e.favorite -eq $true -and $e.workspace -eq $work -and $e.reason -eq "manual")
    }
    Row "F2" {
        $ca = Count $active; $cb = Count (FavBack $work); $co = Count $screen
        $p = Press $script:main "Archive" 0x2B
        $null = WaitLog $screen ($co + 1) 10
        Start-Sleep (1 * $slow)
        # The screen's rows, in a popup or the window itself: the favorite's is NAMED "Favorite: <title>".
        $hit = $null; $seen = @()
        foreach ($w in @($script:main) + @(Popups)) {
            $n = @(Nodes $w | Where-Object { $_.shown })
            $seen += @($n | Where-Object { $_.name -match 'c16|Favorite' } | ForEach-Object { $_.name })
            $x = @($n | Where-Object { $_.name -match 'Favorite: E18 c16fav$' }) | Select-Object -First 1
            if ($x -and -not $hit) { $hit = [pscustomobject]@{ w = $w; n = $x } }
        }
        $r = if ($hit) { PressNode $hit.w $hit.n } else { "no row named 'Favorite: E18 c16fav'" }
        $ok = WaitLog (FavBack $work) ($cb + 1) 10
        NoPopups
        $back = $false; $t0 = Get-Date
        while (-not $back -and ((Get-Date) - $t0).TotalSeconds -lt 10 * $slow) { Start-Sleep 1; $back = [bool](NodeIn (Nodes $script:main) "E18 c16fav - Pinned" 0x25) }
        $acts = (Count $active) - $ca
        $e = EntryOf "c16fav"
        Verdict "F2 the Archive ($p) shows [$($seen -join ' | ')]; the favorite's row pressed ($r): 'restored an entry into Work a favorite' $ok; 'E18 c16fav - Pinned' drawn again $back; switches +$acts (want 0); the entry $(if ($e) { 'STILL in the file' } else { 'gone from the file' })" ($hit -and $ok -and $back -and $acts -eq 0 -and -not $e)
    }
    Row "B1" {
        $null = Go $script:main "Work" $work
        # Not the untouched New Tab page a workspace is shown with: Bookmark all tabs skips it (review R3).
        $today = @(Today (Nodes $script:main) | Where-Object { $_.name -ne "New Tab" })
        $d = Pins; $roots = RootsOf $d $work
        $script:b1 = [pscustomobject]@{ pages = (PageCount $roots); shape = (@($roots | ForEach-Object { PinShape $_ }) -join ","); today = $today.Count; said = ""; line = @() }
        $cs = Count $saved
        $r = RightClick $script:main (NodeIn (Nodes $script:main) "Work" 0x2B) "Work chip"
        $r += "; $(OtherPress '^Bookmark all tabs$')"
        $null = WaitLog $saved ($cs + 1) 10
        $script:b1.said = $r; $script:b1.line = @(Nth $saved $cs)
        Say "      B1 (graded after the quit) the Work chip's Bookmark all tabs ($r): $(if ($script:b1.line.Count) { "'$($script:b1.line[0])'" } else { 'no saved line' }); want $($script:b1.pages) pinned + $($today.Count) Today ($(Names $today))"
    }
    Row "B2" {
        $cn = Count (Nothing $unpin)
        $r = RightClick $script:main (NodeIn (Nodes $script:main) "Unpin" 0x2B) "Unpin chip"
        $r += "; $(OtherPress '^Bookmark all tabs$')"
        $ok = WaitLog (Nothing $unpin) ($cn + 1) 10
        $script:b2 = [pscustomobject]@{ said = $r; ok = $ok }
        Say "      B2 (graded after the quit) the Unpin chip's Bookmark all tabs ($r): 'nothing to save' $ok"
    }
    Row "G1" {
        $null = Go $script:main "Work" $work
        $r = "$(ClickTab 'E18 c16g1'); $(ClickTab 'E18 c16g2' -Ctrl)"
        $r += "; $(RightClick $script:main (TabIn (Nodes $script:main) 'E18 c16g1') 'Today tab E18 c16g1')"
        $r += "; $(OtherPress '^Add tabs? to (new )?group$')"
        Start-Sleep (1 * $slow)
        # A submenu when the window already has groups: its "New group".
        if (@(PopupNames | Where-Object { $_ -match '^New group$' }).Count) { $r += "; $(OtherPress '^New group$')" }
        Start-Sleep (2 * $slow)
        # The new group's bubble: its name field has the focus; Purple pressed through MSAA (no focus change). With no
        # bubble nothing is typed: the keys would reach whatever has the focus.
        $bub = @(PopupNames)
        $r += if ($bub.Count) { "; the group's bubble [$(($bub | Select-Object -First 12) -join ' | ')]: 'grp' $([C16Input]::Type([uint32]$script:bpid, 'grp')); $(OtherPress '^Purple')" } else { "; NO group bubble shown, nothing typed" }
        Start-Sleep (1 * $slow)
        NoPopups
        $nodes = Nodes $script:main
        $part = @(Today $nodes | Where-Object { $_.name -like "E18 c16g[12] - Part of*" })
        $named = [bool]@($nodes | Where-Object { $_.shown -and $_.name -match '\bgrp\b' }).Count
        $title = if ($named) { "grp" } else { "New workspace" }
        $cg = Count $fromGrp; $ca = Count $active
        $r += "; $(TabMenu 'E18 c16g1' @('^Make this group a workspace$'))"
        $ok = WaitLog $fromGrp ($cg + 1) 10
        $null = WaitLog $active ($ca + 1) 10
        Start-Sleep (1 * $slow)
        $g = @(Nth $fromGrp $cg); $now = @(Grp $active)
        $nodes = Nodes $script:main
        $still = @(Today $nodes | Where-Object { $_.name -like "E18 c16g[12] - Part of*" })
        $script:g1 = [pscustomobject]@{ said = $r; ok = $ok; guid = $(if ($g.Count) { $g[1] } else { "" }); n = $(if ($g.Count) { $g[2] } else { "" })
                                        switched = ($g.Count -and $now.Count -and $now[1] -eq $g[1]); grouped = $part.Count; still = $still.Count
                                        head = [bool](NodeIn $nodes $title 0x14); title = $title; tabs = (Names $still) }
        Say "      G1 (graded after the quit) ($r): grouped $($part.Count) of 2, named 'grp' $named; $(if ($g.Count) { "'$($g[0])'" } else { 'no group -> workspace line' }); the window on it $($script:g1.switched), still grouped there: $($script:g1.tabs), its header '$title' drawn $($script:g1.head)"
    }
    Row "W1" {
        $went = Go $script:main "Canary" $canary
        $co = Count $opensOn
        Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--new-window", (Url "c16w2.html")) | Out-Null
        $t0 = Get-Date
        do {
            Start-Sleep 1
            $o = @([E18Input]::Windows([uint32]$script:bpid) | Where-Object { $_ -ne $script:main })
            if ($o.Count) { $script:w2 = $o[0] }
        } while ($script:w2 -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow)
        if ($script:w2 -eq [IntPtr]::Zero) { Verdict "W1 a second window opened (main on Canary: $went)" $false; return }
        SideBySide $script:main $script:w2
        $on = WaitLog $opensOn ($co + 1) 15; $g = @(Nth $opensOn $co)
        # Polled: the forwarded launch is a second process of the profile until it exits, which msaa-press refuses.
        $t0 = Get-Date
        do { Start-Sleep 1; $b0 = FolderLook $script:w2 } while ($b0.smoke -eq "no row" -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow)
        $went2 = Go $script:w2 "Canary" $canary
        $a0 = FolderLook $script:main; $b0 = FolderLook $script:w2
        $c1 = Count (Folder "f2" "closed"); $c2 = Count (Folder "g2" "open")
        $r1 = ClickRow $script:main "Smoke folder"
        $ok1 = WaitLog (Folder "f2" "closed") ($c1 + 1) 8
        $r2 = ClickRow $script:w2 "Closed folder"
        $ok2 = WaitLog (Folder "g2" "open") ($c2 + 1) 8
        Start-Sleep (1 * $slow)
        $a = FolderLook $script:main; $b = FolderLook $script:w2
        $k1 = @(Nth (Folder "f2" "closed") $c1); $k2 = @(Nth (Folder "g2" "open") $c2)
        $d = Pins; $fs = FindPin (RootsOf $d $canary) "f2"; $gs = FindPin (RootsOf $d $canary) "g2"
        Verdict "W1 window 2 opened on '$(if ($g.Count) { $g[1] } else { '?' })' ($on; both on Canary: $went, $went2); before: window 1 $(Look $a0) / window 2 $(Look $b0); window 1 clicks Smoke folder ($r1): 'f2 closed ... ($(if ($k1.Count) { $k1[1] } else { '-' }) other)' $ok1; window 2 clicks Closed folder ($r2): 'g2 open ... ($(if ($k2.Count) { $k2[1] } else { '-' }) other)' $ok2 (want 1 other each); after: window 1 $(Look $a) (want both collapsed, neither page) / window 2 $(Look $b) (want both expanded, both pages); the file: f2 open $(if ($fs) { [bool]$fs.open } else { 'MISSING' }), g2 open $(if ($gs) { [bool]$gs.open } else { 'MISSING' }) (want False, True)" ($ok1 -and $ok2 -and $k1.Count -and $k1[1] -eq "1" -and $k2.Count -and $k2[1] -eq "1" -and (AllShut $a) -and (AllOpen $b) -and $fs -and -not $fs.open -and $gs -and $gs.open -eq $true)
    }
} catch {
    Say "ERROR launch 1 (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
} finally {
    NoPopups
    Say "quit 1: $(Quit -Keep:$second)"
}

# ---- after quit 1: the files the browser wrote at its quit ------------------------------------------------------
Row "B1" -Offline {
    $b = $script:b1
    $bm = try { Get-Content -Raw -Encoding UTF8 -LiteralPath "$dflt\Bookmarks" | ConvertFrom-Json } catch { $null }
    $top = @(@($bm.roots.other.children) | Where-Object { $_ -and $_.type -eq "folder" -and $_.name -eq "Workspaces" }) | Select-Object -First 1
    $made = @(@($top.children) | Where-Object { $_ -and $_.name -match '^Work \d{4}-\d{2}-\d{2} \d{2}:\d{2}$' }) | Select-Object -First 1
    $kids = @(@($made.children) | Where-Object { $_ })
    $todayDir = if ($kids.Count -and $kids[-1].type -eq "folder" -and $kids[-1].name -eq "Today") { $kids[-1] } else { $null }
    $got = @($kids | Where-Object { $_ -ne $todayDir } | ForEach-Object { BmShape $_ }) -join ","
    $inToday = @(@($todayDir.children) | Where-Object { $_ -and $_.type -eq "url" }).Count
    $l = if ($b) { @($b.line) } else { @() }
    Verdict "B1 Bookmark all tabs on Work ($($b.said)): $(if ($l.Count) { "'$($l[0])'" } else { 'no saved line' }) (want '$work', $($b.pages) pinned + $($b.today) Today); Bookmarks: Other bookmarks > $(if ($top) { "Workspaces [$(Names $top.children)]" } else { 'NO Workspaces folder' }) > $(if ($made) { "'$($made.name)'" } else { "NO 'Work <date> <time>' folder" }); its pinned part $got (want $($b.shape)); its last folder $(if ($todayDir) { "Today with $inToday page(s)" } else { "NOT 'Today'" }) (want $($b.today))" ($l.Count -and $l[1] -eq $work -and $l[2] -eq "$($b.pages)" -and $l[3] -eq "$($b.today)" -and $made -and $got -eq $b.shape -and $todayDir -and $inToday -eq $b.today)
}
Row "B2" -Offline {
    $bm = try { Get-Content -Raw -Encoding UTF8 -LiteralPath "$dflt\Bookmarks" | ConvertFrom-Json } catch { $null }
    $top = @(@($bm.roots.other.children) | Where-Object { $_ -and $_.type -eq "folder" -and $_.name -eq "Workspaces" }) | Select-Object -First 1
    $made = @(@($top.children) | Where-Object { $_ })
    # B1's folder, when B1 logged one, is the only one; B2 adds none.
    $wantSaves = if ($script:b1 -and @($script:b1.line).Count) { 1 } else { 0 }
    Verdict "B2 Bookmark all tabs on the empty Unpin ($($script:b2.said)): 'nothing to save in Unpin' $($script:b2.ok); under Workspaces: [$(Names $made)] (want $wantSaves folder(s), none 'Unpin ...')" ($script:b2.ok -and $made.Count -eq $wantSaves -and -not @($made | Where-Object { $_.name -like "Unpin *" }).Count)
}
Row "G1" -Offline {
    $g = $script:g1
    $list = try { (& $py -I "$here\prefs.py" "$dflt\Preferences" "helium.workspaces.list" | Out-String) | ConvertFrom-Json } catch { $null }
    $it = @(@($list.items) | Where-Object { $_ -and $_.guid -eq $g.guid }) | Select-Object -First 1
    Verdict "G1 Make this group a workspace ($($g.said)): the line $($g.ok) ('$($g.guid)', $($g.n) tab(s); want 2), grouped before $($g.grouped) of 2, the window switched to it $($g.switched), still grouped there: $($g.still) ($($g.tabs)), its header '$($g.title)' drawn $($g.head); Preferences: $(if ($it) { "title '$($it.title)', colour $($it.color)" } else { 'NO such workspace' }) (want '$($g.title)', 6 = Purple)" ($g.ok -and $g.guid -and $g.n -eq "2" -and $g.grouped -eq 2 -and $g.switched -and $g.still -eq 2 -and $it -and $it.title -eq $g.title -and $it.color -eq 6)
}

# W2 and W3: the two windows back from a restart, each with its own folders.
function WindowsBack([string]$row) {
    $null = WaitLog $winDirs 2 15
    $ns = @(Lines $winDirs | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
    $wins = @([E18Input]::Windows([uint32]$script:bpid))
    if ($wins.Count -ge 2) { SideBySide $wins[0] $wins[1] }
    $looks = @(foreach ($h in $wins) { $null = Go $h "Canary" $canary; FolderLook $h })
    $shut = @($looks | Where-Object { AllShut $_ }); $open = @($looks | Where-Object { AllOpen $_ })
    $said = @(for ($i = 0; $i -lt $looks.Count; $i++) { "window $($i + 1)$(if ($looks[$i].w2tab) { ' (holds c16w2)' }): $(Look $looks[$i])" }) -join " / "
    Verdict "$row after the restart: $($wins.Count) window(s); 'window folders: restored N' N = $($ns -join ', ') (want 2+ lines, each 2+); on Canary: $said (want one both collapsed, one both expanded)" ($wins.Count -eq 2 -and $ns.Count -ge 2 -and -not @($ns | Where-Object { $_ -lt 2 }).Count -and $shut.Count -eq 1 -and $open.Count -eq 1)
}

# ---- launch 2: the restart (E3's emoji, W2's windows) -----------------------------------------------------------
if ($second) {
    try {
        $script:log = $logs[1]
        Launch
        $t0 = Get-Date
        while (@([E18Input]::Windows([uint32]$script:bpid)).Count -lt 2 -and ($want -contains "W2") -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow) { Start-Sleep 1 }
        Row "E3" {
            $null = WaitLog $restored 1 15
            $n = Count $restored
            Verdict "E3 Today tab c16t's emoji set in launch 1 ($($script:e3.said); 'tab emoji set' $($script:e3.ok)); after the restart 'restored tab emoji' x$n (want 1: c16u's was cleared)" ($script:e3 -and $script:e3.ok -and $n -eq 1)
        }
        Row "W2" { WindowsBack "W2" }
    } catch {
        Say "ERROR launch 2 (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
    } finally {
        NoPopups
        # Exit again for W3, so the session keeps both windows; nothing in launch 2 touched a folder.
        Say "quit 2: $(Quit -Keep:($want -contains 'W3'))"
    }
}

# ---- launch 3: a restart after a restart with no folder touched (W3, review R1) -----------------------------------
if ($want -contains "W3") {
    try {
        $script:log = $logs[2]
        Launch
        $t0 = Get-Date
        while (@([E18Input]::Windows([uint32]$script:bpid)).Count -lt 2 -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow) { Start-Sleep 1 }
        Row "W3" { WindowsBack "W3" }
    } catch {
        Say "ERROR launch 3 (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++
    } finally {
        NoPopups
        Say "quit 3: $(Quit)"
    }
}
if ($script:srv.server) { Stop-Process -Id $script:srv.server.Id -EA SilentlyContinue }

$markers = @(); $bytes = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $bytes += (Get-Item -LiteralPath $l).Length; $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr") } }
Verdict "M1 crash markers in $(@($logs | Where-Object { Test-Path -LiteralPath $_ }) -join ', ') ($bytes bytes): $($markers.Count)$(if ($markers.Count) { ' -- ' + ((@($markers | Select-Object -First 3 | ForEach-Object { $_.Line.Substring(0, [Math]::Min(160, $_.Line.Length)) })) -join ' | ') })" ($markers.Count -eq 0 -and $bytes -gt 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$suffix pass=$($script:passed) fail=$($script:failed) total=$total verdict=$verdict"
Save
exit [int]($verdict -ne "PASS")
