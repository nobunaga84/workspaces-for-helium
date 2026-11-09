param([switch]$NoLaunch)
# C19.1 (patch 85): the owner's own try of Export workspaces / Import workspaces in the "+" menu -- the part no
# automated check can drive: the real Save and Open dialogs, the confirm box and the messages. It opens the built browser
# (out\Default) on a FRESH copy of the smoke profile (never the daily browser's profile), makes the file you will import
# from YOUR daily workspaces (read-only: local/workspaces-transfer.py), and a damaged copy of it for the refusal.
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c191.ps1
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\Default"
$exe    = "$bin\chrome.exe"
$tool   = "$here\workspaces-transfer.py"
$prof   = "$ws\testprofile-c191-owner"
$log    = "$ws\c191-owner-run.log"
$dir    = "$ws\backups\exports\c191-try"
$good   = "$dir\from-daily.json"
$bad    = "$dir\damaged.json"
$daily  = Join-Path $env:LOCALAPPDATA "Helium Workspaces\User Data"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
foreach ($s in @("rail + menu: export workspaces", "import: applied")) {
    & python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -ne 0) { Write-Host "This build has no C19.1 yet (no '$s' in out\Default\chrome.dll): tell Claude."; exit 1 }
}
if (-not (Test-Path -LiteralPath "$daily\Default\Workspace Pins")) { Write-Host "No daily pins file: tell Claude."; exit 1 }
New-Item -ItemType Directory -Force $dir | Out-Null
& python $tool export $daily $good
if ($LASTEXITCODE -ne 0) { Write-Host "The export of your daily workspaces failed: tell Claude."; exit 1 }
& python -I -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = d['files']['Workspace Pins']['content']
d['files']['Workspace Pins']['content'] = c.replace('https://', 'http://', 1)
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
" $good $bad
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $log -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null
if (-not $NoLaunch) {
    Start-Process $exe -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
}
@"

The test browser is opening on a COPY of the smoke profile (your daily browser is not touched). It has its own small set of
workspaces: Home, Work, Canary, Private, Unpin, and 25 pinned pages. Your daily workspaces are in this file, ready to import:
   $good
and a damaged copy of it:
   $bad
The "+" is the round button at the bottom of the sidebar, beside the workspaces. Do the steps in order.

 1. Click +. PASS: under "Import from Arc" the menu has "Export workspaces$([char]0x2026)" and "Import workspaces$([char]0x2026)".
 2. + > Export workspaces$([char]0x2026). PASS: a Save dialog titled "Export workspaces" opens, named helium-workspaces-<today>.json, with a
    "Save as type" list that has two choices (everything / pinned pages list). Save the .json on your Desktop. PASS: a box
    says "Workspaces exported" and where it went. Click OK.
 3. + > Export workspaces$([char]0x2026) again, choose the second type (the pinned pages list, .csv), save it. PASS: the box says "A list of 25
    pinned pages was saved". Open the .csv in Excel or Notepad: a header line, then one line per pinned page.
 4. Click + twice quickly, then Export. PASS: only ONE Save dialog opens. Cancel it.
 5. + > Import workspaces$([char]0x2026). PASS: an Open dialog titled "Import workspaces". Choose from-daily.json (path above). PASS: a box
    asks "Replace your workspaces with the ones in this file?", saying Now: 5 workspaces, 25 pinned pages ... In the file: 4
    workspaces, 3,4xx pinned pages ... and that a copy is saved first. Click Cancel. PASS: nothing changed (still Home, Work,
    Canary, Private, Unpin).
 6. + > Import workspaces$([char]0x2026) > from-daily.json again, this time click Replace. PASS: a box says "Workspaces imported ... You now
    have 4 workspaces, 3,4xx pinned pages ...". The bar changes AT ONCE, with no restart, to YOUR workspaces (the ones in
    your export). Click Work: your pinned pages are there. Shift+Alt+H opens the Archive: your archived tabs.
 7. The safety copy: open the folder $prof\Default\Workspace Backups . PASS: it holds one before-import-<date>.json
    (a small file: the 25 pages this profile had before step 6).
 8. + > Import workspaces$([char]0x2026) > damaged.json (path above). PASS: a box says "Could not import this file" and that the file
    "was changed or damaged"; the workspaces do not change.
 9. + > Import workspaces$([char]0x2026) and press Cancel in the Open dialog. PASS: nothing happens.

Then close the test browser and tell Claude which steps passed (or what you saw). The log is $log .
"@
