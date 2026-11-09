param([switch]$Zen)
# C3 + C17 + C15 + C8 (patch 71): the owner's own try. Opens the built browser (out\Default) on a FRESH copy of the
# smoke profile -- never the daily browser's profile -- with "Big folder" (16 pinned pages, closed) added to Work, a
# log for Claude to read afterwards, and prints what to do and what a pass looks like. -Zen: zen mode, sidebar
# unpinned, as the daily browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c3.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-c3-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\c3-owner-run.log"
$work = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
& python -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); d['workspaces'][sys.argv[2]].append({'type':'folder','id':'big1','title':'Big folder','open':False,'children':[{'type':'item','id':'big1-%d'%i,'title':'Big %d'%i,'url':'https://example.com/?big=%d'%i} for i in range(1,17)]}); open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins" $work
if ($LASTEXITCODE -ne 0) { Write-Host "Could not add Big folder to the copy."; exit 1 }
if ($Zen) { & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
@"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched). Press Shift+Alt+2
first: everything below happens in Work. Its pinned pages: Example A, "Smoke folder" (open: Wikipedia, Renamed C),
"Closed folder" (Hidden), Example D, "Big folder" (16 pages, closed).
 1. C17 folder actions -- right-click "Smoke folder".
    a. Copy links, then paste into Notepad. PASS: two lines, the Wikipedia and the GitHub addresses.
    b. Sort by name. PASS: "Renamed C" moves above "Wikipedia" (folders first, then A-Z; case and accents do not
       decide alone). Right-click again: "Undo sort" is there and puts Wikipedia back on top.
    c. Open all. PASS: no question; both pinned pages show their x when the mouse is over them, and the page you
       were on stays in front. Right-click: "Close all" is there now; it closes both.
    d. Right-click "Big folder" > Open all. PASS: a box asks "Open 16 pages?". Cancel opens nothing. Open all
       again > "Open all": 16 pages open (open the folder to see their x's). Close all closes them.
 2. C3 move -- click "Example D" (its page opens), right-click it > Move to workspace > Canary.
    PASS: "Example D" leaves Work's pinned pages and another page comes to the front. Shift+Alt+3: Canary
    now has two "Example D" pinned pages, one of them open; clicking it shows it WITHOUT switching back to Work.
 3. C15 fold -- Shift+Alt+2 (Work). Click the name "Work" at the top of the section.
    PASS: the pinned pages fold away; a small arrow shows just left of the numbers; hovering the name says
    "Pinned pages folded $([char]0x2014) click to show them". Click it again: they come back.
    Then click "Example A" and fold again. PASS: only "Example A" stays (the page you are on). Click a Today tab:
    its row goes too. Ctrl+N: the new window shows Work folded as well. Unfold before step 4.
 4. C8 drag -- drag "Example A" and HOLD it over the middle of "Closed folder" for half a second.
    PASS: the folder opens under the pointer; move onto "Hidden" and let go: "Example A" lands in the folder
    above "Hidden", and the folder stays open.
    Then drag "Wikipedia", hold it over "Big folder" until it opens, drag back up and let go where it started.
    PASS: nothing moves, and "Big folder" closes again.
Then close the test browser and tell Claude which steps passed. The log is $log.
"@
