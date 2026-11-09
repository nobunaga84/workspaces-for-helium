param([switch]$NoLaunch, [switch]$GradeOnly)
# C16 + C25 + C27 + C9 + C11 (patch 87): the owner's own try -- the looks no hands-free check can judge (the emoji on a
# pinned page, a Today tab and a folder, the folder's box, in light and dark; the drop line of the C25 drag; the star of
# a favorite in the Archive; two windows' own folders; a group made a workspace; the bookmarks folder). It opens the
# built browser (out\Default) on a FRESH copy of the smoke profile (never the daily browser's profile), in Light mode,
# with four Today tabs, waits while you do the ten steps below, opens it again by itself after your Exit (step 10), then
# asks one y/n per step and grades each from the two logs and the profile's files.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c16.ps1
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again from
# the last try's logs and files (the browser closed).
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = "$ws\helium-windows\build\src\out\Default"
$exe   = "$bin\chrome.exe"
$py    = "C:\Python314\python.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-c16-owner"
$dflt  = "$prof\Default"
$logs  = @("$ws\c16-owner-run1.log", "$ws\c16-owner-run2.log")
$txt   = "$ws\c16-owner-try.txt"
$pages = @("https://example.com/", "https://www.iana.org/help/example-domains", "https://www.wikipedia.org/", "https://httpbin.org/html")
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
$script:out = [System.Collections.Generic.List[string]]::new()
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Running { [bool](Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) }
function WaitClosed { while (Running) { Start-Sleep 2 } }
# Up to a minute for the started browser to show up, so a slow cold start is not taken for a quit.
function WaitOpen { $t0 = Get-Date; while (-not (Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 } }

# ---- the preconditions, each checked before anything is touched ------------------------------------------------
$bad = @()
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { $bad += "a test browser is already open: close it first" }
if (-not (Test-Path -LiteralPath $exe)) { $bad += "no $exe (build first)" }
if (-not (Test-Path -LiteralPath $py)) { $bad += "no $py" }
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { $bad += "no smoke profile at $smoke" }
if (Test-Path -LiteralPath $exe) {
    & $py -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "group -> new workspace '"
    if ($LASTEXITCODE -ne 0) { $bad += "this build has no patch 87 yet (no 'group -> new workspace' in out\Default\chrome.dll): tell Claude" }
}
if ($GradeOnly -and -not (Test-Path -LiteralPath $logs[0])) { $bad += "no $($logs[0]) to grade" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath (@("$dflt\Workspace Archive") + $logs + @($txt)) -EA SilentlyContinue
    # 280 wide (every workspace chip shown), Light mode to start (browser.theme.color_scheme2: 1 light, 2 dark).
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    if (-not $NoLaunch) { Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[0])`"") + $flags + $pages) }
    @"

The test browser is opening on a COPY of the smoke profile (your daily browser is not touched), in Light mode, in its
workspace Home, with four Today tabs: Example Domain, Example Domains (IANA), Wikipedia, "Herman Melville - Moby-Dick".
Words used below:
  - a PINNED PAGE: a row in the sidebar's top section, above the Today tabs (Home's: Example A, Example D, and the
    pages inside the folders).
  - a FOLDER: a pinned row that holds pinned pages: "Smoke folder" (open: Wikipedia and a GitHub page) and "Closed
    folder" (Hidden).
  - a TODAY TAB: a tab in the sidebar's list UNDER the pinned pages.
  - a FAVORITE: a tab pinned the Chromium way (its menu's "Add to Favorites", not "Pin to this workspace"): an icon at the very top of the
    sidebar, the same in every workspace.
  - the BAR: the row at the bottom of the sidebar: the Archive button, one round WORKSPACE CHIP per workspace, and "+".
  - WINDOW 1 is the window opening now; WINDOW 2 is the one you open in step 7.
Do every step FROM WINDOW 1, IN HOME, unless the step says otherwise. Remember a y or n for each step: the script asks
for them at the end.

 1. Pinned page emoji. Right-click the pinned page "Example A" > "Set emoji...". PASS: a small box titled "Set emoji..."
    with one field. Press Win+. (Windows' emoji panel), pick an emoji (a rocket, say), press Enter. PASS: Example A
    shows the emoji where its icon was, as big as the other icons, not cut off.
 2. Folder emoji. Right-click the folder "Closed folder" > "Set emoji...", pick another emoji (books), press Enter.
    PASS: the folder's icon becomes the emoji INSIDE a small rounded BOX in the folder's colour (an outline over a
    faint fill): it must not look like a pinned page's emoji.
 3. Today tab emoji. Right-click the Today tab "Example Domain" > "Set emoji...". PASS: a box over the page, like
    "Rename tab..."'s, titled "Set emoji...". Pick an emoji (fire), click OK. PASS: the tab shows it in place of its icon.
 4. Light, dark, and taking one off. PASS in Light: the three emoji of steps 1-3 are clear, the folder's box visible.
    Then Alt+F > Settings > Appearance, switch the mode to Dark, and look at the sidebar again. PASS: the three are
    still clear and the folder's box still shows against the dark sidebar. Switch back to Light and close Settings.
    Then right-click "Example A" > "Set emoji...", delete what is in the box, press Enter. PASS: Example A's own icon is
    back.
 5. The drag to a folder's end. Drag the pinned page "Example D" up and drop it on the LOWER half of the last page inside
    "Smoke folder" (the GitHub one, under Wikipedia). PASS: while you drag, the drop line is indented like the folder's
    pages; Example D lands INSIDE the folder, as its last page. Then drag "Example A" onto the UPPER half of "Closed
    folder". PASS: it lands just after Smoke folder, NOT inside it, above Closed folder.
 6. A favorite in the Archive. Right-click the Today tab "Wikipedia" > "Add to Favorites". PASS: it becomes a favorite. Right-click
    the favorite > "Close". Click Archive on the bar. PASS: its row shows a STAR before "Wikipedia"; hovering the row,
    the tooltip begins "Favorite: Wikipedia". Click the row. PASS: Wikipedia comes back as a FAVORITE (at the top, not a
    Today tab) and the window stays in Home.
 7. Two windows, each with its own folders. Press Ctrl+N: window 2 opens (if it does not show Home, click Home on ITS
    bar). Put the two side by side. In WINDOW 2 click "Smoke folder". PASS: it closes in window 2 only; window 1 still
    shows it open, its pages under it. Then in WINDOW 1 click "Closed folder". PASS: it opens in window 1 only; window
    2's stays closed.
 8. A group made a workspace. In window 1 click the Today tab "Example Domains", Ctrl+click "Herman Melville -
    Moby-Dick", right-click one of them > "Add tabs to new group" (or "Add tabs to group" > "New group"). In the
    group's box type the name Reading, pick a colour (Blue), press Esc. Right-click one of the two > "Make this group a
    workspace". PASS: a new workspace chip "Reading" on the bar, in the group's colour; the window switches to it; the
    two tabs are there, still in their group.
 9. Bookmark all tabs. In window 1 right-click the HOME workspace chip on the bar > "Bookmark all tabs". PASS: nothing
    pops up. Press Ctrl+Shift+O (the bookmark manager) > Other bookmarks > Workspaces. PASS: a folder "Home <today's
    date> <time>" holding Home's pinned pages, Smoke folder and Closed folder as folders, then a "Today" folder with
    Home's Today tab(s). Close the bookmark manager's tab.
10. The restart. Quit with the app menu: Alt+F > More tools > Exit (NOT the windows' X: closing them one by one forgets
    window 2). Wait: the script opens the browser again by itself. PASS: BOTH windows come back. On each window's bar
    click Home. PASS: window 1 shows Smoke folder open and Closed folder open; window 2 shows both closed; the Today
    tab "Example Domain" still has its emoji. Then close the browser any way you like.
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof)"; exit 0 }
    Write-Host "`nWaiting for you to quit the browser (step 10)..."
    WaitOpen
    WaitClosed
    Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[1])`"") + $flags + @("--restore-last-session"))
    Say "`nThe browser is opening again with the last session (step 10). Check it, then close it."
    WaitOpen
    WaitClosed
    Start-Sleep 3
}

# ---- the answers, then the grades ---------------------------------------------------------------------------------
$names = @("pinned page emoji", "folder emoji in a box", "Today tab emoji", "light, dark, taking one off", "the drag to a folder's end",
           "a favorite in the Archive", "two windows' own folders", "a group made a workspace", "Bookmark all tabs", "the restart")
Say ""
$said = @(for ($i = 0; $i -lt 10; $i++) { $a = "$(Read-Host "Step $($i + 1) ($($names[$i])): did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } })
function Lines([int]$run, [string]$re) { if (Test-Path -LiteralPath $logs[$run]) { @(Select-String -LiteralPath $logs[$run] -CaseSensitive -Pattern $re) } else { @() } }
function Last([int]$run, [string]$re) { $l = @(Lines $run $re); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
function Json([string]$path) { try { Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json } catch { $null } }
function FindPin($list, [string]$id) {
    foreach ($n in @($list)) { if (-not $n) { continue }; if ($n.id -eq $id) { return $n }; $f = FindPin $n.children $id; if ($f) { return $f } }
    $null
}
function Has($n) { $n -and $n.PSObject.Properties["emoji"] -and $n.emoji }
$pins  = Json "$dflt\Workspace Pins"
$homeRows = @($pins.workspaces.default | Where-Object { $_ })
$bm    = Json "$dflt\Bookmarks"
$list  = try { (& $py -I "$here\prefs.py" "$dflt\Preferences" "helium.workspaces.list" | Out-String) | ConvertFrom-Json } catch { $null }
$a0 = FindPin $homeRows "a0"; $g0 = FindPin $homeRows "g0"; $f0 = FindPin $homeRows "f0"

# Each step: the log's (and files') word, true or false, and what it found.
$grades = @()
$ok = (Lines 0 "\[workspaces\] pins: emoji of 'a0' set").Count -gt 0
$grades += [pscustomobject]@{ ok = $ok; why = "'pins: emoji of a0 set' $ok" }
$ok = (Lines 0 "\[workspaces\] pins: emoji of 'g0' set").Count -gt 0
$grades += [pscustomobject]@{ ok = ($ok -and (Has $g0)); why = "'pins: emoji of g0 set' $ok; the pins file's Closed folder has an emoji $([bool](Has $g0))" }
$t = @(Last 0 "\[workspaces\] tab emoji set at index (\d+)")
$grades += [pscustomobject]@{ ok = [bool]$t.Count; why = "$(if ($t.Count) { "'$($t[0] -replace '^\[workspaces\] ', '')'" } else { "no 'tab emoji set' line" })" }
$ok = (Lines 0 "\[workspaces\] pins: emoji of 'a0' cleared").Count -gt 0
$grades += [pscustomobject]@{ ok = ($ok -and $a0 -and -not (Has $a0)); why = "the looks are yours; 'pins: emoji of a0 cleared' $ok, the file's Example A has no emoji $($a0 -and -not (Has $a0))" }
$m1 = (Lines 0 "\[workspaces\] pins: moved 'd0' after 'c0'").Count -gt 0
$m2 = (Lines 0 "\[workspaces\] pins: moved 'a0' before 'g0'").Count -gt 0
$kids = @($f0.children | Where-Object { $_ } | ForEach-Object { $_.id }) -join ","
$tops = @($homeRows | ForEach-Object { $_.id }) -join ","
$grades += [pscustomobject]@{ ok = ($m1 -and $m2 -and $kids -like "*,d0" -and $tops -like "*f0,a0,g0*"); why = "'moved d0 after c0' $m1, 'moved a0 before g0' $m2; the file: Smoke folder holds $kids (want ...,d0), Home's rows $tops (want f0,a0,g0)" }
$fa = @(Last 0 "\[workspaces\] archived a manual close in '([^']*)' \(favorite\)")
$fb = @(Last 0 "\[workspaces\] archive: restored an entry into '([^']*)' a favorite")
$grades += [pscustomobject]@{ ok = ($fa.Count -and $fb.Count); why = "filed $(if ($fa.Count) { "under '$($fa[1])'" } else { 'NOT logged' }) (favorite); restored $(if ($fb.Count) { "into '$($fb[1])' a favorite" } else { 'NOT logged' })" }
$w1 = @(Last 0 "\[workspaces\] folder 'f0' closed in this window \((\d+) other window\(s\) keep theirs\)")
$w2 = @(Last 0 "\[workspaces\] folder 'g0' open in this window \((\d+) other window\(s\) keep theirs\)")
# The "other window(s)" number is printed, not graded: a window that already had its own word on a folder (a drag's
# hover-open in step 5) is not given one again, and says 0 rightly.
$grades += [pscustomobject]@{ ok = ($w1.Count -and $w2.Count); why = "Smoke folder closed $(if ($w1.Count) { "with $($w1[1]) other window(s) keeping theirs" } else { 'NOT logged' }); Closed folder opened $(if ($w2.Count) { "with $($w2[1]) other window(s) keeping theirs" } else { 'NOT logged' })" }
$gl = @(Last 0 "\[workspaces\] group -> new workspace '([^']*)', (\d+) tab\(s\)")
$it = if ($gl.Count) { @(@($list.items) | Where-Object { $_ -and $_.guid -eq $gl[1] }) | Select-Object -First 1 }
$grades += [pscustomobject]@{ ok = ($gl.Count -and $it); why = "$(if ($gl.Count) { "'group -> new workspace', $($gl[2]) tab(s)" } else { 'no group -> workspace line' }); Preferences: $(if ($it) { "'$($it.title)', colour $($it.color) (0 grey 1 blue 2 red 3 yellow 4 green 5 pink 6 purple 7 cyan 8 orange)" } else { 'no such workspace' })" }
$bl = @(Last 0 "\[workspaces\] bookmarks: saved '([^']*)' as (\d+) pinned \+ (\d+) Today")
$top = @(@($bm.roots.other.children) | Where-Object { $_ -and $_.type -eq "folder" -and $_.name -eq "Workspaces" }) | Select-Object -First 1
$made = @(@($top.children) | Where-Object { $_ -and $_.name -match '^Home \d{4}-\d{2}-\d{2} \d{2}:\d{2}$' }) | Select-Object -Last 1
$todayDir = @(@($made.children) | Where-Object { $_ -and $_.type -eq "folder" -and $_.name -eq "Today" }) | Select-Object -First 1
$grades += [pscustomobject]@{ ok = ($bl.Count -and $bl[1] -eq "default" -and $made -and ($bl[3] -eq "0" -or $todayDir)); why = "$(if ($bl.Count) { "saved '$($bl[1])' as $($bl[2]) pinned + $($bl[3]) Today" } else { 'no saved line' }); Bookmarks: $(if ($made) { "Other bookmarks > Workspaces > '$($made.name)' [$(@($made.children | ForEach-Object { $_.name }) -join ', ')]" } else { "no 'Home <date> <time>' folder under Other bookmarks > Workspaces" })" }
$wr = @(Lines 1 "\[workspaces\] window folders: restored (\d+)")
$er = (Lines 1 "\[workspaces\] restored tab emoji").Count
$grades += [pscustomobject]@{ ok = ($wr.Count -ge 2 -and $er -ge 1); why = "after the restart: 'window folders: restored N' for $($wr.Count) window(s) (want 2: an Exit keeps both), 'restored tab emoji' x$er (want 1+)" }

Say ""
$pass = 0
for ($i = 0; $i -lt 10; $i++) {
    $g = $grades[$i]; $a = $said[$i]
    $v = if ($a -eq "y" -and $g.ok) { "PASS" } elseif ($a -eq "n") { "FAIL" } elseif ($a -eq "-") { "NOT TRIED" } else { "LOOK" }
    if ($v -eq "PASS") { $pass++ }
    Say ("{0,-9} step {1,2} {2}: you said {3}; the log: {4}" -f $v, ($i + 1), $names[$i], $a, $g.why)
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Say "crash markers in the two logs: $markers (want 0)"
Say "RESULT try-c16 $pass of 10 PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Logs: $($logs -join ', ')"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
