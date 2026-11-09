param([switch]$NoLaunch, [switch]$GradeOnly, [string[]]$Steps = @())
# `pwsh -File ... -Steps 1,4` passes ONE string "1,4" (as [int] it read 14: the comma a thousands separator).
$Steps = @($Steps | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { [int]$_ })
# C21 (patch 88 `88-favorite-tiles.patch`, <local-path>\Helium-workspace\c21-progress.md): the owner's own try of favorites as Arc
# tiles -- the looks no hands-free check can judge (check-c21.ps1 measured them: 44 DIP, the card's pixels). It opens the
# built browser (out\Default) on a FRESH copy of the smoke profile (never the daily browser's profile), in Light mode,
# Tab style Default (30 px), in Home, with four Today tabs served from this PC (127.0.0.1): "Plain page", "Red page",
# "Green page", "Blue page" (the last three with a coloured dot for their icon). Before each step you press Enter here,
# so each step is graded only on the log lines written after it began; after it you answer y/n. Patch 88 logs nothing
# of its own: step 1 is graded from the tag lines (a tab made a favorite leaves its workspace) and the saved session's
# pinned tabs, step 5 from the Tab style line and Preferences; steps 2-4 are looks, your answer decides them.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c21.ps1
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal). -GradeOnly: asks and grades again from
# the last try's log, step marks and files (the browser closed).
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = "$ws\helium-windows\build\src\out\Default"
$exe   = "$bin\chrome.exe"
$py    = "C:\Python314\python.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-c21-owner"
$dflt  = "$prof\Default"
$logs  = @("$ws\c21-owner-run1.log")
$txt   = "$ws\c21-owner-try.txt"
$markf = "$ws\c21-owner-marks.json"
$web   = "$ws\c21-owner-pages"
$p88   = "$ws\helium-windows\patches\local\workspaces\88-favorite-tiles.patch"
$flags = @("--user-data-dir=$prof", "--enable-logging", "--v=0", "--no-first-run", "--no-default-browser-check")
$script:out = [System.Collections.Generic.List[string]]::new()
function Say([string]$s) { Write-Host $s; $script:out.Add($s) }
function Running { [bool](Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) }
function WaitClosed { while (Running) { Start-Sleep 2 } }
# Up to a minute for the started browser to show up, so a slow cold start is not taken for a quit.
function WaitOpen { $t0 = Get-Date; while (-not (Running) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1 } }
# The log's length now, in lines: a step is graded on the lines after its start only.
function LineCount([int]$run) { if (Test-Path -LiteralPath $logs[$run]) { @(Get-Content -LiteralPath $logs[$run]).Count } else { 0 } }

# ---- the preconditions, each checked before anything is touched ------------------------------------------------
$bad = @()
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { $bad += "a test browser is already open: close it first" }
if (-not (Test-Path -LiteralPath $exe)) { $bad += "no $exe (build first)" }
if (-not (Test-Path -LiteralPath $py)) { $bad += "no $py" }
if (-not $GradeOnly -and -not (Test-Path -LiteralPath "$smoke\Default\Workspace Pins")) { $bad += "no smoke profile at $smoke" }
# Patch 88 puts no string of its own into chrome.dll (no log line, no text): its file time only, as check-c21 does.
if ((Test-Path -LiteralPath $exe) -and (Get-Item -LiteralPath "$bin\chrome.dll").LastWriteTime -lt (Get-Item -LiteralPath $p88).LastWriteTime) {
    $bad += "out\Default\chrome.dll is older than patch 88 (no favorite tiles yet): tell Claude"
}
if ($GradeOnly -and -not (Test-Path -LiteralPath $markf)) { $bad += "no $markf to grade (no finished try)" }
if ($bad.Count) { $bad | ForEach-Object { Write-Host "NOT READY: $_" }; exit 1 }

$names = @("three favorites", "the cards in Light", "the cards in Dark", "the collapsed sidebar", "Tab style Spacious")
function Ask([int]$i) { $a = "$(Read-Host "    Done with ALL of step $($i + 1)? Did it pass? y/n (Enter: not tried)")".Trim().ToLower(); if ($a) { $a.Substring(0, 1) } else { "-" } }

if (-not $GradeOnly) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$dflt\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    Remove-Item -LiteralPath (@("$dflt\Workspace Archive", $markf, $txt) + $logs) -EA SilentlyContinue
    # 280 wide, Light mode (browser.theme.color_scheme2: 1 light, 2 dark), Tab style Default (30 px).
    & $py -I "$here\prefs.py" "$dflt\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" "browser.theme.color_scheme2=1" "helium.workspaces.tab_row_height=30" | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host "NOT READY: the copy's preferences were not written"; exit 1 }
    # The four pages; a dot of colour as each favorite's icon, so the tiles are told apart (a tile shows its icon only).
    $null = New-Item -ItemType Directory -Force $web
    $pages = [ordered]@{ plain = @("Plain page", ""); red = @("Red page", "%23d62828"); green = @("Green page", "%232a9d3f"); blue = @("Blue page", "%231e6fd9") }
    foreach ($k in $pages.Keys) {
        $t, $fill = $pages[$k]
        $icon = if ($fill) { "<link rel=`"icon`" href=`"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Ccircle cx='8' cy='8' r='7' fill='$fill'/%3E%3C/svg%3E`">" }
        Set-Content -Encoding UTF8 -LiteralPath "$web\$k.html" -Value "<!doctype html><title>$t</title>$icon<body style=`"margin:24px;font:24px sans-serif`"><h1>$t</h1></body>"
    }
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
    @"

The test browser opens on a fresh COPY of the smoke profile (your daily browser is not touched), in Light mode, in its
workspace Home. Words used below:
  - a FAVORITE: a tab pinned with its menu's "Add to Favorites" (NOT "Pin to this workspace"): a TILE at the very top of the
    sidebar, the same in every workspace. A tile shows only the page's icon; hovering it shows the page's name.
  - a PINNED PAGE: a row in the section under the workspace's header (Home's: Example A, Smoke folder, Closed folder,
    Example D). Not used here: leave them alone.
  - a TODAY TAB: an ordinary tab in the list under the pinned pages. Home starts with four: "Plain page", "Red page",
    "Green page", "Blue page" ("Red page" has a red dot for its icon, and so on; "Plain page" a grey globe).
  - the TILE IN FRONT: the favorite whose page is the one showing.
Do every step in WINDOW 1 (the only window), IN HOME. THIS window says "STEP N: do it now" -- do ALL of step N in
the browser, come back here, answer y or n; the next step starts at once.

 1. Three favorites. Right-click the Today tab "Red page"; in its menu choose "Add to Favorites" (in the MIDDLE group,
    between "Duplicate" and "Mute site" -- NOT "Pin to this workspace" in the top group). Do the same for "Green page",
    then for "Blue page".
    PASS: each leaves the Today list and becomes a tile at the very top of the sidebar: red, green, blue side by side
    in ONE row, each tile about one and a half times as tall as a Today tab, its dot in the middle, small and sharp
    (not blown up). "Plain page" stays a Today tab.
 2. The cards, in Light. Click the Today tab "Plain page".
    PASS: behind EACH of the three tiles a VERY faint grey card with rounded corners, just darker than the white
    sidebar, a thin gap between the cards (half as strong as the card behind the pinned pages, on purpose).
    Then click the RED tile.
    PASS: the red tile now has Helium's own highlight (like a selected Today tab) and NO faint card; the green and
    blue tiles keep theirs, and the red one is EASY to tell apart from them (clearly greyer than their faint cards).
 3. The cards, in Dark. Press Alt+F; near the bottom of the menu choose "Customize Chromium" (the pencil icon). In
    the panel that opens at the right of the window, click "Dark". (The panel is no tab: the RED tile is still in
    front from step 2.)
    PASS: on the dark sidebar the green and blue tiles have a very faint LIGHT card, quiet; the red tile has the
    highlight and no card, and is EASY to tell apart from them (clearly lighter); the dots still sharp.
    Click the GREEN tile. PASS: green has the highlight and no card; red and blue keep their cards.
    Then click "Light" in the same panel and close the panel with its x (its top right).
 4. The collapsed sidebar. Click the button at the far LEFT of the toolbar, just left of Back (hovering it shows
    "Collapse tabs").
    PASS: the sidebar becomes a narrow column of icons; the three favorites are SMALL SQUARES one under another at its
    top, no taller than the other icons there (not the tall tiles); each but the tile in front with its faint card.
    Click the same button again (now "Expand tabs"). PASS: the tall tiles are back, side by side in one row.
 5. Tab style Spacious. Click the sidebar's "+" > "Workspace settings$([char]0x2026)" > "Tab style" > "Spacious, 42 px", then close the
    box with Escape.
    PASS: the Today tab "Plain page" is taller now, about as tall as a tile; the tiles are NOT taller than before
    (they stay 44 px: a hair taller than the 42 px Today tab).
Then close the browser any way you like: the script grades.
"@ | ForEach-Object { Say $_ }
    if ($NoLaunch) { Say "(-NoLaunch: nothing started; the copy is $prof, the pages $web, port $port)"; exit 0 }
    $srv = Start-Process $py -ArgumentList "-I", "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", $web -WindowStyle Hidden -PassThru
    $up = $false
    foreach ($i in 1..20) { Start-Sleep -Milliseconds 500; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 "http://127.0.0.1:$port/red.html").Content -match "Red page") { $up = $true; break } } catch {} }
    if (-not $up) { Stop-Process -Id $srv.Id -EA SilentlyContinue; Write-Host "NOT READY: the pages were not served on 127.0.0.1:$port"; exit 1 }
    $marks = @(); $said = @()
    try {
        Start-Process $exe -ArgumentList (@("--log-file=`"$($logs[0])`"") + $flags + @($pages.Keys | ForEach-Object { "http://127.0.0.1:$port/$_.html" }))
        WaitOpen
        for ($i = 0; $i -lt $names.Count; $i++) {
            if ($Steps.Count -and $Steps -notcontains ($i + 1)) { $said += "-"; $marks += [pscustomobject]@{ run = 0; start = (LineCount 0); send = 0; end = (LineCount 0) }; continue }
            Write-Host "`n==> STEP $($i + 1) ($($names[$i])): do it NOW in the browser (its words are above, under '$($i + 1).')."
            $m = [pscustomobject]@{ run = 0; start = (LineCount 0); end = 0 }
            $said += Ask $i
            $m.end = LineCount 0; $marks += $m
        }
        Write-Host "`nNow close the test browser (any way). Waiting for it..."
        WaitClosed
        Start-Sleep 3
    } finally { Stop-Process -Id $srv.Id -EA SilentlyContinue }
    ConvertTo-Json -InputObject @($marks) | Set-Content -Encoding UTF8 -LiteralPath $markf
} else {
    $marks = @(Get-Content -Raw -LiteralPath $markf | ConvertFrom-Json)
    Say ""
    $said = @(for ($i = 0; $i -lt $names.Count; $i++) { Ask $i })
}

# ---- the grades -----------------------------------------------------------------------------------------------------
function Lines([int]$run, [string]$re) { if (Test-Path -LiteralPath $logs[$run]) { @(Select-String -LiteralPath $logs[$run] -CaseSensitive -Pattern $re) } else { @() } }
# Step i's lines matching re: only those written after it began and before your answer.
function In([int]$i, [string]$re) { $m = $marks[$i]; if (-not $m) { return @() }; @(Lines $m.run $re | Where-Object { $_.LineNumber -gt $m.start -and $_.LineNumber -le $m.end }) }
function Last($l) { $l = @($l | Where-Object { $_ }); if ($l.Count) { @($l[-1].Matches[0].Groups | ForEach-Object { $_.Value }) } else { @() } }
# The favorites (Chromium pinned tabs) of the last saved session: its SetPinnedState commands (id 12, the tab's id then
# a bool), last write wins, closed tabs (16) dropped; the file read by session-tags.py's own reader.
function Favorites {
    $s = Get-ChildItem -LiteralPath "$dflt\Sessions" -Filter "Session_*" -File -EA SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $s) { return "no session file" }
    "$(& $py -I -c "import importlib.util as u,struct,sys; s=u.spec_from_file_location('st',sys.argv[1]); m=u.module_from_spec(s); s.loader.exec_module(m); r=list(m.records(sys.argv[2])); pin={}; [pin.__setitem__(struct.unpack_from('<i',d)[0],d[4]) for c,d in r if c==12]; gone={struct.unpack_from('<i',d)[0] for c,d in r if c==16}; print(sum(1 for t,v in pin.items() if v and t not in gone))" "$here\session-tags.py" $s.FullName 2>&1)".Trim()
}
function Eyes([string]$what) { [pscustomobject]@{ ok = $true; why = "your eyes only: $what (patch 88 logs nothing; check-c21 measured it by pixels)" } }

$grades = @()
$t = @(In 0 "\[workspaces\] tag 'default' -> ''")
$f = Favorites
$grades += [pscustomobject]@{ ok = ($t.Count -ge 3 -and "$f" -match '^\d+$' -and [int]$f -ge 3); why = "a Home tab made a favorite (its tag cleared) x$($t.Count) in this step (want 3); the saved session holds $f favorite(s) (want 3)" }
$grades += Eyes "a faint card behind each tile, none behind the tile in front"
$grades += Eyes "the light cards on the dark sidebar"
$grades += Eyes "small squares in the collapsed column, the tall tiles back after"
$r = Last (In 4 "\[workspaces\] tab style: row height (\d+) -> (\d+)")
$h = "$(& $py -I "$here\prefs.py" "$dflt\Preferences" "helium.workspaces.tab_row_height")".Trim()
$grades += [pscustomobject]@{ ok = ($r.Count -and $r[2] -eq "42" -and $h -eq "42"); why = "$(if ($r.Count) { "'tab style: row height $($r[1]) -> $($r[2])'" } else { 'no Tab style line in this step' }) (want -> 42); Preferences' Tab style $h (want 42); the tiles staying 44 is your eyes (check-c21's C21e measured it)" }

Say ""
$pass = 0
for ($i = 0; $i -lt $names.Count; $i++) {
    $g = $grades[$i]; $a = $said[$i]
    $v = if ($a -eq "y" -and $g.ok) { "PASS" } elseif ($a -eq "n") { "FAIL" } elseif ($a -eq "-") { "NOT TRIED" } else { "LOOK" }
    if ($v -eq "PASS") { $pass++ }
    Say ("{0,-9} step {1} {2}: you said {3}; the log: {4}" -f $v, ($i + 1), $names[$i], $a, $g.why)
}
$markers = 0
foreach ($l in $logs) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Say "crash markers in the log: $markers (want 0)"
Say "RESULT try-c21 $pass of $($names.Count) PASS$(if ($markers) { ', CRASH MARKERS' }) -- LOOK means your answer and the log disagree: tell Claude. Log: $($logs -join ', ')"
try { Set-Content -LiteralPath $txt -Value $script:out -Encoding UTF8; Write-Host "(written to $txt)" } catch { Write-Host "could not write $($txt): $_" }
