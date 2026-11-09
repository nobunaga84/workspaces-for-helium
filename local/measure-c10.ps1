param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [int]$Runs = 3)
# C10 research (ideas.md): what does the biggest pinned folder cost TODAY? On a throwaway copy of the smoke profile whose
# only pinned row is a copy of the biggest folder of the DAILY pins file (read-only; the daily profile is never written),
# it starts the built browser with that folder open and then closed, $Runs times each, no clicks and no input:
#   draw  = the "pins: drew N row(s) of 'default' in M ms" line (a rebuild's whole cost, as the section logs it)
#   quit  = the window's close request to the process's exit (the rows are torn down with the window)
#   mem   = the browser process's private memory a few seconds after the draw
# Earlier numbers (LOCAL.md 45, with 444 tabs open): draw 1,313 rows 491-616 ms; close 6.0 s open vs 2.2 s closed.
# A browser window opens on the screen for a moment each run (placed topmost, no input is sent).
#   pwsh -NoProfile -File local\measure-c10.ps1 [-Build Dcheck] [-Runs 3]
. "$PSScriptRoot\e18-lib.ps1"
$ws    = "<local-path>\Helium-workspace"
$bin   = "$ws\helium-windows\build\src\out\$Build"
$exe   = "$bin\chrome.exe"
$smoke = "$ws\testprofile-e15b-smoke"
$prof  = "$ws\testprofile-c10$(if ($Build -eq 'Dcheck') { '-dcheck' })"
$daily = Join-Path $env:LOCALAPPDATA "Helium Workspaces\User Data\Default\Workspace Pins"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
if (-not (Test-Path -LiteralPath $exe)) { Write-Host "No $exe"; exit 1 }
if (-not (Test-Path -LiteralPath $daily)) { Write-Host "No daily pins file at $daily"; exit 1 }
E18InputType
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
$pins = "$prof\Default\Workspace Pins"
# The biggest folder (most pages, any depth) of the daily file, as the only row of 'default'; open or closed.
function SeedPins([bool]$open) {
    $py = @'
import json, sys
src, dst, want = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
d = json.load(open(src, encoding="utf-8"))
def pages(n):
    return 1 if n["type"] == "item" else sum(pages(c) for c in n.get("children", []))
best = None
def walk(rows):
    global best
    for n in rows:
        if n["type"] == "folder" and (best is None or pages(n) > pages(best)):
            best = n
        walk(n.get("children", []))
for roots in d["workspaces"].values():
    walk(roots)
best = json.loads(json.dumps(best))
best["open"] = want
# a sub-folder keeps its own open state: all open when asked, all closed otherwise
def setopen(n):
    for c in n.get("children", []):
        if c["type"] == "folder":
            c["open"] = want
        setopen(c)
setopen(best)
out = {"version": d["version"], "workspaces": {"default": [best]}}
json.dump(out, open(dst, "w", encoding="utf-8"), ensure_ascii=False)
print(pages(best))
'@
    $n = $py | & python - $daily $pins ($(if ($open) { "1" } else { "0" }))
    "$n".Trim()
}
function OneRun([bool]$open, [int]$k) {
    $pages = SeedPins $open
    $log = "$ws\c10-$(if ($open) { 'open' } else { 'closed' })-$k$(if ($Build -eq 'Dcheck') { '-dcheck' }).log"
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
    $p = Start-Process $exe -PassThru -ArgumentList $a
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep 1; $q = Get-Process -Id $p.Id -EA SilentlyContinue; if ($q) { $main = $q.MainWindowHandle } }
    $draw = $null; $rows = $null
    $t0 = Get-Date
    while (-not $draw -and ((Get-Date) - $t0).TotalSeconds -lt 120) {
        if (Test-Path -LiteralPath $log) {
            $l = Select-String -LiteralPath $log -Pattern "pins: drew (\d+) row\(s\) of 'default' in (\d+) ms" | Select-Object -Last 1
            if ($l) { $rows = [int]$l.Matches[0].Groups[1].Value; $draw = [int]$l.Matches[0].Groups[2].Value }
        }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep 5
    $mem = [int]((Get-Process -Id $p.Id -EA SilentlyContinue).PrivateMemorySize64 / 1MB)
    $c0 = Get-Date
    foreach ($w in [E18Input]::Windows([uint32]$p.Id)) { [E18Input]::CloseWindow($w) }
    while ((Get-Process -Id $p.Id -EA SilentlyContinue) -and ((Get-Date) - $c0).TotalSeconds -lt 120) { Start-Sleep -Milliseconds 200 }
    $quit = [math]::Round(((Get-Date) - $c0).TotalSeconds, 1)
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }); $left | Stop-Process -Force -EA SilentlyContinue
    [pscustomobject]@{ folder = $(if ($open) { "open" } else { "closed" }); run = $k; pages = $pages; rows = $rows; draw_ms = $draw; quit_s = $quit; mem_mb = $mem; stragglers = $left.Count }
}
$res = @()
foreach ($open in @($true, $false)) { foreach ($k in 1..$Runs) { $r = OneRun $open $k; $res += $r; $r | Format-Table -AutoSize | Out-String | Write-Host } }
Write-Host "build: $Build chrome.dll $((Get-Item "$bin\chrome.dll").LastWriteTime)"
$res | Format-Table -AutoSize
$res | ConvertTo-Json | Set-Content -Encoding UTF8 "$ws\c10-measure$(if ($Build -eq 'Dcheck') { '-dcheck' }).json"
