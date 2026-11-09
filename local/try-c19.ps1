param([switch]$Yes, [switch]$NoLaunch)
# C19 (local/workspaces-transfer.py): the owner's own try. It plays "a second PC": a FRESH copy of the smoke profile (never the
# daily browser's profile) that gets YOUR daily workspaces, pinned pages and Archive by an export file, then opens the built
# browser (out\Default) on it for you to compare with your daily browser. Your daily profile is only READ (the export).
# -Yes: no "type YES" (Claude's rehearsal); -NoLaunch: set everything up and print, start nothing.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c19.ps1
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\Default"
$exe    = "$bin\chrome.exe"
$tool   = "$here\workspaces-transfer.py"
$prof   = "$ws\testprofile-c19-owner"
$log    = "$ws\c19-owner-run.log"
$zip    = "$ws\backups\exports\c19-try.zip"
$bad    = "$ws\backups\exports\c19-try-tampered.zip"
$daily  = Join-Path $env:LOCALAPPDATA "Helium Workspaces\User Data"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (-not (Test-Path -LiteralPath "$daily\Default\Workspace Pins")) { Write-Host "No daily pins file: tell Claude."; exit 1 }
New-Item -ItemType Directory -Force "$ws\backups\exports" | Out-Null

Write-Host "1/4  Exporting your daily workspaces (read-only)..." -ForegroundColor Cyan
& python $tool export $daily $zip
if ($LASTEXITCODE -ne 0) { Write-Host "The export failed: tell Claude."; exit 1 }
# A damaged copy for the refusal test: the same file with one pinned page's title changed after the checksum was taken.
& python -I -c "
import sys, zipfile
src, dst = sys.argv[1:3]
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zo:
    for n in zi.namelist():
        data = zi.read(n)
        if n == 'Workspace Pins':
            i = data.index(b'title') + 8
            data = data[:i] + b'X' + data[i + 1:]
        zo.writestr(n, data)
" $zip $bad

Write-Host "2/4  Making the 'second PC': a fresh copy of the smoke profile..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $log -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null

Write-Host "3/4  Importing. This is what the tool says it will change; it asks you to type YES:" -ForegroundColor Cyan
if ($Yes) { & python $tool import $zip $prof --yes } else { & python $tool import $zip $prof }
$imported = (Test-Path -LiteralPath "$prof\Default\Workspace Pins.transfer.bak")
if (-not $imported) { Write-Host "Nothing was imported (you did not type YES, or it failed). Run the script again." -ForegroundColor Yellow; exit 1 }
if ($NoLaunch) { Write-Host "(rehearsal: browser not started)"; }
else {
    Write-Host "4/4  Opening the browser on the copy..." -ForegroundColor Cyan
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
}
@"

The test browser is the "second PC" (a copy; your daily browser is not touched). It opens on HOME. Keep your daily browser open
beside it to compare. Do the steps in order.

 1. The bar at the bottom of the sidebar. PASS: the same workspaces as your daily browser -- Home, Canary, Private, Work --
    in the same order, with the same icons and names.
 2. Click Work, then Canary. PASS: the pinned pages and folders look like your daily browser's for the same workspace (same
    names, same order, same open/closed folders). The header numbers (pinned pages / Today tabs) show the pinned count; Today is
    empty here, which is right: Today tabs are not part of the file.
 3. Open the Archive (Shift+Alt+H). PASS: it lists the same recently closed pages as your daily browser's Archive (about 1,642).
 4. In the test browser press Ctrl+click on two pinned pages and Esc: it all works as in your daily browser (nothing was lost on
    the way). Do NOT use Delete here unless you want to: it is a copy, nothing else is touched.
 5. REFUSAL 1 -- with the test browser STILL OPEN, in another PowerShell window run:
      python <local-path>\Helium-workspace\helium\local\workspaces-transfer.py import $zip $prof --dry-run
    PASS: it prints "error: a browser holds ... (lockfile): close it first, then import" -- even for a dry run, and writes nothing.
 6. Close the test browser. REFUSAL 2 -- run:
      python <local-path>\Helium-workspace\helium\local\workspaces-transfer.py import $bad $prof --dry-run
    PASS: it prints "error: Workspace Pins: size or SHA-256 differs from the manifest: the file was changed or damaged". Then
    the good file again with --dry-run: it lists the plan (now 4 -> file 4 workspaces, and the page counts) and "dry run: nothing written".

Then tell Claude which steps passed (or what you saw). The log is $log; your export is $zip (a rescue copy of your workspaces,
pinned pages and Archive -- keep it if you like).
"@
