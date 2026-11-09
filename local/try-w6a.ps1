param([switch]$Zen, [switch]$Keep)
# Wish 6a-6c (patches 67-69): the owner's own try of the toolbar order -- the list, and dragging in the toolbar (steps 6b-6f). Opens the built browser (out\Default) on a FRESH copy
# of the smoke profile -- never the daily browser's profile -- with three Chrome buttons switched on (Downloads, Task
# manager, Copy link), and a log for Claude to read afterwards. -Zen: zen mode, sidebar unpinned, as the daily
# browser runs. -Keep: reopen the SAME copy (step 7, the restart) instead of making a fresh one.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-w6a.ps1
$ws   = "<local-path>\Helium-workspace"
$exe  = "$ws\helium-windows\build\src\out\Default\chrome.exe"
$prof = "$ws\testprofile-w6a-owner$(if ($Zen) { '-zen' })"
$log  = "$ws\w6a-owner-run$(if ($Keep) { '2' }).log"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (-not $Keep -or -not (Test-Path -LiteralPath $prof)) {
  if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
  $null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
  Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
  $set = @('toolbar.pinned_actions=["kActionShowDownloads","kActionTaskManager","kActionCopyUrl"]')
  if ($Zen) { $set += @("helium.browser.zen_mode=true", "helium.browser.zen_mode_sidebar_pinned=false") }
  & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" @set | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "Seeding the profile failed: tell Claude."; exit 1 }
}
$null = Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
if ($Keep) {
@"
The SAME test copy is open again (step 7). PASS: the toolbar looks as you left it -- Downloads and Reload left of the
address bar; right of it Forward, then the three dots (menu), the puzzle piece, the + (New tab), Task manager and Copy
link. Then do step 8, close the test browser, and tell Claude which steps passed. The log is $log.
"@
  exit 0
}
@"
The test browser is open on a copy of the smoke profile (your daily browser is not touched). Words used below:
  the TOOLBAR      = the row of buttons at the very top, with the address bar in it
  the TOOLBAR LIST = the panel "Toolbar" that opens on the right side of the window in step 2
 1. Look at the toolbar. PASS: Back, Forward, Reload left of the address bar; right of it a + (New tab -- NEW since
    your morning try), the puzzle piece, then Downloads (arrow), Task manager, Copy link (chain), the three dots (menu).
 2. Press Alt+F (or click the three dots) > Settings > Appearance > "Customize toolbar".
    PASS: the toolbar list opens on the right: ONE list with no lines between groups; read top to bottom it is the
    toolbar left to right; a shaded row "Address and search bar" sits just under "Open in split view" (above it:
    Collapse tabs, Back, Forward, Reload, Home; below it: New tab, Extensions, Downloads, Task manager, Copy link, the
    buttons that are off, Media controls, Profiles, Main Menu).
 3. In the toolbar list, press on the WORD "Reload" (not its switch), hold, drag it just below the shaded "Address and
    search bar" row, let go. PASS: in the toolbar, Reload now sits RIGHT of the address bar; in the list it stays
    where you dropped it; its switch did not flip.
 4. Drag "Main Menu" to the very top of the list. PASS: the three dots are now at the far LEFT of the toolbar.
 5. Drag "Downloads" above the shaded "Address and search bar" row. PASS: Downloads ALONE moves to the left of the
    address bar; Task manager and Copy link stay on the right, in the toolbar and in the list.
 6. Click the shaded "Address and search bar" row once (it gets a ring), then press Alt+Down once.
    PASS: the shaded row moves one place down, below Reload, and in the toolbar Reload is LEFT of the address bar
    again.
Now drag in the TOOLBAR itself (wish 6c). Keep the toolbar list open on the right: it should follow every move.
 6b. In the TOOLBAR, press and HOLD on the three dots (menu) at the far left, slide the mouse SIDEWAYS to the right
    across the address bar, and let go over the right end of the address bar.
    PASS: the three dots slid along with the mouse and now sit just right of the address bar; letting go did NOT
    open the menu; in the toolbar list "Main Menu" jumped to just below "Address and search bar".
 6c. Press and hold on Forward (the right arrow -- greyed out, that is fine), slide it sideways to the right and let
    go over the right end of the address bar. PASS: Forward now sits just right of the address bar, before the dots.
 6d. Press and hold on Task manager, slide it sideways to the far left, then press Esc BEFORE letting go.
    PASS: everything jumps back to where it was; nothing moved in the list.
 6e. Click the three dots once, without sliding. PASS: the menu opens as you let go of the mouse button. Press Esc.
 6f. Press and hold on the puzzle piece, slide it sideways to the left and let go over the LEFT end of the address
    bar. PASS: the puzzle piece (with any extension icons next to it) now sits left of the address bar; in the list
    "Extensions" moved above "Address and search bar". Then drag it back the same way to the right of the dots.
 6g. In the toolbar list, click the switch of "New tab" off, then on again. PASS: the + leaves the toolbar, then comes
    back where its row is.
 7. Close the test browser (the X at the top right), then run this script again with -Keep:
      pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-w6a.ps1 -Keep$(if ($Zen) { ' -Zen' })
    PASS: the toolbar is as you left it (it prints what to look for).
 8. Open the toolbar list again (step 2) and click "Reset to default" at its bottom.
    PASS: Back, Forward, Reload are left of the address bar again and the three dots are at the far right; the list
    shows "Address and search bar" under "Open in split view". (Reset also switches Chrome's buttons back to
    Helium's defaults, so Downloads, Task manager and Copy link may switch off: that part is Chromium's own reset.)
Close the test browser, then tell Claude which steps passed. The log is $log.
"@
