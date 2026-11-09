param([switch]$Zen)
# C14 + C34 (patches 72, 73): the owner's own try. Opens the built browser (out\Default) on a FRESH copy of the
# smoke profile -- never the daily browser's profile -- with a log for Claude to read afterwards, and prints what to
# do and what a pass looks like. The test pages (local\c14-pages\page.html: a faint tone, a FAKE camera and
# microphone -- the launch flags; your real camera is never used -- plain pages) are served on this PC only, on a
# port Windows gives, until Enter is pressed here: http, not file://, so "Mute site" works on them. -Zen: zen mode,
# sidebar unpinned, as the daily browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c14.ps1
. "$PSScriptRoot\e18-lib.ps1"
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-c14-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\c14-owner-run.log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()
$server = Start-Process python -ArgumentList "-m", "http.server", $port, "--bind", "127.0.0.1", "--directory", "$PSScriptRoot\c14-pages" -WindowStyle Hidden -PassThru
$page = "http://127.0.0.1:$port/page.html"
if (-not (AllowCameraAt "$prof\Default\Preferences" $port)) { Write-Host "Could not allow the fake camera in the copy: step 4 will show no red dot." }
if ($Zen) { & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check",
                                   "--autoplay-policy=no-user-gesture-required", "--use-fake-device-for-media-stream")
@"
The test browser is opening (a copy of the smoke profile; your daily browser is not touched). Copy each address
below into the address bar. "Work's button" is Work's square in the bar at the bottom of the sidebar.$(if ($Zen) { "
Zen mode: the sidebar (and its bar) shows while the mouse is at the window's left edge." })
 C14 -- the sound badge
 1. Shift+Alt+2 (Work). Open:  $page`?c14-tone
    (a faint, steady beep). Then Shift+Alt+3 (Canary).
    PASS: Work's button shows a small speaker at its bottom-right corner; resting the mouse on it shows
    "Work" and under it "Playing audio - c14 tone" (Chromium's wording).
 2. Click Work's button.  PASS: Work, with the BEEPING tab in front (not the tab you were on in Work before).
 3. Right-click the "c14 tone" tab > Mute site. Shift+Alt+3.  PASS: no speaker on Work's button (a muted tab is
    silent). Back in Work, unmute it (right-click > Unmute site).
 4. In Work open:  $page`?c14-cam
    (a FAKE camera and microphone -- the page says nothing, the tab shows a red dot). Shift+Alt+3.
    PASS: Work's button shows the red recording dot instead of the speaker (recording comes first).
 5. Shift+Alt+2, close the "c14 cam" and "c14 tone" tabs, Shift+Alt+3.  PASS: Work's button is plain again
    (within about 2 seconds).
 C34 -- a close returns to the tab you used last (everything in Work, Shift+Alt+2)
 6. Open three tabs, in this order:  $page`?p3   then  $page`?p1   then  $page`?p2
    Click the tabs "p1", then "p3", then "p2". Press Ctrl+W.
    PASS: "p3" comes to the front (the tab you used before p2) -- not "p1", the tab next to it.
 7. Click the pinned page "Example A" (it opens), then click the tab "p1", then Ctrl+W.
    PASS: Example A's page comes to the front and STAYS there.
 8. Open:  $page`?c34-links
    Ctrl+click both links on it (two tabs open behind it). Click the tab "c34 l1", then Ctrl+W.
    PASS: back on "c34 links" (the page you came from) -- not "c34 l2".
Then close the test browser and tell Claude which steps passed. The log is $log.
"@
$null = Read-Host "Press Enter here once the test browser is closed (stops the page server)"
Stop-Process -Id $server.Id -EA SilentlyContinue
