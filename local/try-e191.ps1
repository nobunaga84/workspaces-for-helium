param([switch]$Zen)
# E19.1 (patch 66): the owner's own try of the Today split fix. Opens the built browser (out\Default) on a FRESH copy
# of the smoke profile -- never the daily browser's profile -- with the made-up Arc file's 3 pinned splits seeded into Work (as in
# the E19 try), and a log for Claude to read afterwards. -Zen: zen mode, sidebar unpinned, as the daily browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-e191.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-e191-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\e191-owner-run.log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$null = & python "$PSScriptRoot\e19-seed-splits.py" $prof
if ($LASTEXITCODE -ne 0) { Write-Host "Seeding the pinned splits failed: tell Claude."; exit 1 }
$env:HELIUM_ARC_SIDEBAR = "$ws\arc-made-up\StorableSidebar.json"  # the repair reads Arc's file: the made-up one (LOCAL.md 133)
if ($Zen) { & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.zen_mode=true" "helium.browser.zen_mode_sidebar_pinned=false" | Out-Null }
$bpid = (Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")).Id
# The first window opens on Home (E15e); the bug lives in Work, so the script switches for you -- a screen
# reader's press on the rail's Work button (no keys, no mouse). Your 2026-10-14 first try ran all in Home.
$win = [IntPtr]::Zero; $t0 = Get-Date
while ($win -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1; $p = Get-Process -Id $bpid -EA SilentlyContinue; if ($p) { $win = $p.MainWindowHandle } }
Start-Sleep 3
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof -Window ([long]$win) -Name "Work" -Role 0x2B
Start-Sleep 2
$inWork = (Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern "active workspace -> '2ab592d4" -Quiet)
if (-not $inWork) { Write-Host "Could not switch to Work by itself: press Shift+Alt+2 now, and check the name at the top of the sidebar reads Work." }
@"
The test browser is open on a copy of the smoke profile (your daily browser is not touched), already switched to
WORK: the name at the top of the sidebar reads "Work". Steps 1-6 happen in Work. A "split view" in the Today list is
ONE row with two halves -- an icon and a title on the left, another icon and title on the right.
 1. Two Today tabs -- click the New Tab in Today, type wikipedia.org, Enter. Press Ctrl+T, type google.com, Enter.
    PASS: Google and Wikipedia are two Today tabs; Google is in front.
 2. The bug's own steps -- right-click the Today tab IN FRONT (Google) > Add tab to new split view.
    PASS: ONE Today row with two halves: Google on the left, "Choose a tab" on the right (icon and title both
    drawn, the right half NOT empty). Nothing else new appears in Today (no extra row for either page).
 3. The right half ("Choose a tab") is in front now: click the address bar, type bing.com, Enter.
    PASS: the row's right half now reads Bing; still one row of two halves.
 4. The other way -- press Ctrl+T, type example.org, Enter (a Today tab of its own, in front). Right-click the
    Wikipedia Today tab (not in front) > New split view with current tab.
    PASS: Wikipedia and example.org become one split view row, both halves drawn.
 5. A group still works -- press Ctrl+T, type example.com, Enter. Right-click that Today tab > Add tab to new group
    (pick "New group" if a list opens). PASS: the group shows with the tab inside it, drawn.
 6. A pinned split still unpins whole -- look at the PINNED section at the top of the sidebar (above "+ New Tab").
    Below the row "Example D" are three rows that each show TWO small pages side by side, e.g. "as8z...  gf9f...".
    Each of those rows is a "pinned split". Click the LEFT half ("as8z...") of the first one: the page area shows
    two pictures side by side. Now press Shift+Alt+D (unpin).
    PASS: that row leaves the pinned section and appears at the TOP of Today (under "+ New Tab") as ONE row with
    two halves, "as8z..." on the left and "gf9f..." on the right -- an icon and a title in EACH half, no empty half.
 7. Home stays right -- press Shift+Alt+1: the name at the top of the sidebar changes to "Home". Press Ctrl+T, type
    example.net, Enter. Right-click that Today tab (it is in front) > Add tab to new split view.
    PASS: one row with two halves (example.net | Choose a tab), both drawn.
Close the test browser, then tell Claude which steps passed -- and, if you remember it, what the "page drawn as its
own full row underneath" from your E19 try looked like (which title, where). The log is $log.
"@
