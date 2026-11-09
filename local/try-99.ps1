param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "", [switch]$NoLaunch)
# Patch 99 (the polish batch, LOCAL.md 129): the owner's own try of the three fixes a right-click reaches -- the review's
# #36 (no Snooze for a grouped tab), #49 (a folder deleted after its question box waited keeps its pages in its own
# workspace's Archive) and #50 (Move to workspace -> Home files the pinned page under Home itself). check-99.ps1 covers
# the rest hands-free. It opens the built browser (out\Default, or -Build Dcheck / -BinDir) on a FRESH copy of the
# smoke profile (never the daily browser's profile), in Home, with three pinned pages added: "P99 folder" (a folder
# holding one page) at the end of Home, "P99 move" at the end of Work, and "P99 leftover" kept under a workspace that
# no longer exists (so it shows at the end of Home). Do the steps, close the browser, and the script grades its files.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-99.ps1 [-Build Dcheck]
# -NoLaunch: sets everything up and prints, starts nothing.
$ws    = "<local-path>\Helium-workspace"
$bin   = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-99-owner$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$log   = "$ws\99-owner$(if ($Build -eq 'Dcheck') { '-dcheck' })-run.log"
$work  = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "Close the test browser first."; exit 1 }
if (-not (Test-Path -LiteralPath "$bin\chrome.exe")) { Write-Host "No $bin\chrome.exe"; exit 1 }

# A fresh copy of the smoke profile, the three rows added to its pinned pages.
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NJS /NP /XD Cache "Code Cache" GPUCache
$seed = "$env:TEMP\try-99-seed.py"
Set-Content -LiteralPath $seed -Encoding utf8 -Value @'
import json, sys
path, work = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))
rows = d.setdefault("workspaces", {})
rows.setdefault("default", []).append({"type": "folder", "id": "p99f", "title": "P99 folder", "open": True,
    "children": [{"type": "item", "id": "p99fa", "title": "P99 in folder", "url": "https://example.com/p99-in-folder"}]})
rows.setdefault(work, []).append({"type": "item", "id": "p99m", "title": "P99 move", "url": "https://example.com/p99-move"})
rows["p99-gone"] = [{"type": "item", "id": "p99o", "title": "P99 leftover", "url": "https://example.com/p99-leftover"}]
json.dump(d, open(path, "w", encoding="utf-8"))
'@
& python -I $seed "$prof\Default\Workspace Pins" $work

Write-Host @"

Your try of patch 99: three steps, then close the browser. Pinned pages are the rows above the Today tabs.

1  (#36) In Home, right-click any Today tab and pick "Add tab to new group". Right-click that same tab again.
   PASS: the menu has NO "Snooze tab" (before this fix it had one).
2  (#49) In Home, right-click the pinned folder "P99 folder" and pick "Delete folder". While its question box is
   open, click Work on the bar. If the box is still there, click Delete in it.
   If the box CLOSED when you clicked Work, say so: then this path cannot reach the bug (the old build is safe
   here too), and the fix is covered by reading the code only.
   PASS: graded from the Archive after you close the browser (the folder's page is kept under Home, not Work).
3  (#50) In Work, right-click the pinned page "P99 move" -> Move to workspace -> Home. Click Home on the bar.
   PASS: "P99 move" sits ABOVE "P99 leftover" (before this fix it went below it).

Then close the browser with its X.
"@
if ($NoLaunch) { exit 0 }
$p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList "--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check"
Wait-Process -Id $p.Id
Start-Sleep -Seconds 3

# Graded from the files the browser wrote at its close.
$pins = (Get-Content -LiteralPath "$prof\Default\Workspace Pins" -Raw | ConvertFrom-Json -AsHashtable).workspaces
$owner = @($pins.Keys | Where-Object { @($pins[$_] | Where-Object { $_.id -eq "p99m" }).Count })
$homeRows = @($pins["default"] | ForEach-Object { $_.id })
$archiveFile = "$prof\Default\Workspace Archive"  # absent until something is archived
$archive = @(if (Test-Path -LiteralPath $archiveFile) { (Get-Content -LiteralPath $archiveFile -Raw | ConvertFrom-Json -AsHashtable).entries |
    Where-Object { $_.url -like "*p99-in-folder*" } })
$folderGone = -not @($pins["default"] | Where-Object { $_.id -eq "p99f" }).Count
Write-Host ""
Write-Host "1  your answer: does the grouped tab's menu show 'Snooze tab'? (it should not)"
Write-Host "2  folder deleted: $folderGone; its page in the Archive under: $(if ($archive.Count) { ($archive | ForEach-Object { $_.workspace }) -join ', ' } else { '(not in the Archive)' }) -- PASS when 'default' (Home)"
Write-Host "3  'P99 move' kept under: $($owner -join ', ') -- PASS when 'default'; Home's own rows now end: $(($homeRows | Select-Object -Last 3) -join ', ')"
