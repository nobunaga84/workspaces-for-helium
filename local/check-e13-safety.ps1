param([string]$Log = "", [switch]$GradeOnly, [switch]$OnlyBC)
# -OnlyBC runs and grades parts B and C alone, into their own log, so a finished part A's
# evidence is not overwritten by a second run.
if (-not $Log) { $Log = if ($OnlyBC) { "<local-path>\Helium-workspace\e13s-bc-run.log" } else { "<local-path>\Helium-workspace\e13s-run.log" } }
# E13.5 patch 32 (LOCAL.md 35): the safety chunk before the Arc import.
#   A. "Close all tabs" / "Delete workspace" ask first above 25 tabs -- Recently Closed keeps only
#      25 entries, so beyond that Ctrl+Shift+T is no undo -- and act at once at 25 or fewer.
#   B. Ctrl+W on an anchored page with a "Leave site?" listener puts it away but keeps it live:
#      not hibernated (typed text would be lost) and not closed (a PDF's listener never asks).
#   C. "Hibernate this workspace" keeps such a page awake.
# The "Leave site?" page is served locally by this script (python http.server on 127.0.0.1, on a port Windows hands out),
# because an anchor must be an http(s) page and no public page reliably has the handler.
# -GradeOnly re-grades an existing log.
$exe  = "<local-path>\Helium-workspace\helium-windows\build\src\out\Default\chrome.exe"
$prof = "<local-path>\Helium-workspace\testprofile"
$flags = @("--user-data-dir=$prof","--enable-logging","--v=0","--no-first-run","--no-default-browser-check")
$pageDir = "<local-path>\Helium-workspace\e13s-page"
# Asked of Windows, not fixed: at R5 8765 was taken -- Logi Options+ (LogiPluginService.exe) registers
# http://localhost:8765/ with http.sys, which answered every test page "Bad Request" (LOCAL.md 59).
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $l.Start(); $port = $l.LocalEndpoint.Port; $l.Stop()

$items = (Get-Content "$prof\Default\Preferences" -Raw | ConvertFrom-Json).helium.workspaces.list.items
$work = @($items | Where-Object { $_.guid -ne 'default' })[0]
$guid = $work.guid; $Ws = $work.title.ToUpper()

if (-not $GradeOnly) {
if (Get-Process chrome -EA SilentlyContinue | Where-Object Path -like '*Helium-workspace*') { Write-Host "ABORT: a fork browser is already running (forwarded-launch trap)." -ForegroundColor Red; exit 1 }
$live = "<local-path>\Helium-workspace\helium-windows\patches\local\workspaces\32-e13-safety.patch"
if (-not (Test-Path $live)) { Write-Host "ABORT: no $live" -ForegroundColor Red; exit 1 }
if ((Get-Item $exe).LastWriteTime -lt (Get-Item $live).LastWriteTime) { Write-Host "ABORT: chrome.exe older than the patch (stale binary, LOCAL.md 18)" -ForegroundColor Red; exit 1 }
foreach ($f in 'workspace_service\.cc','workspace_service\.h','workspaces/BUILD\.gn','workspace_rail_view\.cc','workspace_rail_view\.h','generated_resources\.grd') {
    if (-not (Select-String -Path $live -Pattern "^\+\+\+ b/.*$f" -Quiet)) { Write-Host "ABORT: the live patch does not touch $f -- an edit was not quilt-added (LOCAL.md 30)" -ForegroundColor Red; exit 1 }
}
& python <local-path>\Helium-workspace\helium\local\set-workspaces-pref.py $prof --show | Select-Object -Last 2
if ($LASTEXITCODE -ne 0) { Write-Host "ABORT: preconditions not met" -ForegroundColor Red; exit 1 }

# A bookmark folder whose "Open all" gives more than 25 tabs: the shortest path with 26-80 links.
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$folder = & python -c @"
import json
b = json.load(open(r'$prof\Default\Bookmarks', encoding='utf-8'))
found = []
def walk(n, path):
    kids = n.get('children', [])
    urls = sum(1 for k in kids if k.get('type') == 'url')
    if n.get('type') == 'folder' and 26 <= urls <= 80:
        found.append((len(path), urls, ' > '.join(path)))
    for k in kids:
        if k.get('type') == 'folder':
            walk(k, path + [k.get('name', '')])
for r, name in (('bookmark_bar', 'Bookmarks bar'), ('other', 'Other bookmarks')):
    walk(b['roots'][r], [name])
found.sort()
print(f'{found[0][2]}  ({found[0][1]} links)' if found else '')
"@
if (-not $folder -and -not $OnlyBC) { Write-Host "ABORT: no bookmark folder with 26-80 links in testprofile (add one there first)" -ForegroundColor Red; exit 1 }

Remove-Item $Log -EA SilentlyContinue
New-Item -ItemType Directory -Force $pageDir | Out-Null
Set-Content -Path "$pageDir\leave.html" -Encoding utf8 -Value @'
<!doctype html><title>LEAVE TEST</title>
<h1>Type something in the box</h1><textarea rows="4" cols="40"></textarea>
<script>window.addEventListener('beforeunload', e => { e.preventDefault(); e.returnValue = ''; });</script>
'@
Set-Content -Path "$pageDir\test.pdf" -Encoding ascii -NoNewline -Value "%PDF-1.1`n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj`n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj`n3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 300 144]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj`n4 0 obj<</Length 38>>stream`nBT /F1 24 Tf 40 60 Td (PDF TEST) Tj ET`nendstream endobj`n5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj`ntrailer<</Root 1 0 R>>`n%%EOF`n"
$server = Start-Process -FilePath python -ArgumentList @("-m","http.server","$port","--bind","127.0.0.1","--directory",$pageDir) -PassThru -WindowStyle Hidden
try {
Start-Sleep 2
# The page must be OURS: a leftover server or another program on the port would serve something else.
$probe = try { (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 "http://127.0.0.1:$port/leave.html").Content } catch { "" }
if ($probe -notmatch 'LEAVE TEST' -or $server.HasExited) { Write-Host "ABORT: the local test page is not being served on port $port (is something else using it?)" -ForegroundColor Red; exit 1 }
if (-not $OnlyBC) {
Write-Host @"

E13 SAFETY -- every step says which workspace you are IN.

 A. BULK CLOSE ASKS FIRST ABOVE 25 TABS
  1. [any]   click $Ws in the rail. Then open the bookmark folder
               $folder
             (helium://bookmarks, or the bookmarks menu), right-click it -> "Open all",
             and say yes if Helium asks. EXPECT: more than 25 new tabs, in $Ws.
  2. [$Ws]  right-click $Ws in the rail -> "Close all tabs".
             EXPECT: a box "Close all N tabs in this workspace?". Click CANCEL.
             EXPECT: nothing closed.
  3. [$Ws]  right-click $Ws -> "Close all tabs" again, and this time click the box's
             "Close all tabs" button.   EXPECT: they all close; one fresh tab remains.
  4. [$Ws]  Ctrl+T twice (a few tabs only). Right-click $Ws -> "Close all tabs".
             EXPECT: NO box -- they close at once, as before.
"@ -ForegroundColor Yellow
} else {
    Write-Host "`nE13 SAFETY, parts B and C only -- every step says which workspace you are IN." -ForegroundColor Yellow
}
Write-Host @"

 B. CTRL+W ON AN ANCHORED PAGE THAT ASKS BEFORE LEAVING
  5. [any]   click HOME in the rail. Ctrl+T, go to  http://127.0.0.1:$port/leave.html
             Click in the box and type anything.
  6. [Home]  right-click the LEAVE TEST tab -> "Anchor" -> "Anchor to this page".
  7. [Home]  press Ctrl+W.   EXPECT: NO dialog. You move to another tab, and LEAVE TEST
             stays in the strip, awake -- click it: your text is still there.
 7b. [Home]  Ctrl+T, go to  http://127.0.0.1:$port/test.pdf  (it shows "PDF TEST").
             Right-click that tab -> "Anchor" -> "Anchor to this page". Press Ctrl+W.
             EXPECT: you move to another tab; the PDF tab is still in the strip (NOT closed).

 C. UNLOAD KEEPS IT AWAKE
  8. [Home]  Ctrl+T, go to  https://example.com  (LEAVE TEST is now a background tab).
             Right-click HOME in the rail -> "Hibernate this workspace".
             Click LEAVE TEST.   EXPECT: your text is still in the box (it never slept).
  9. Close the browser window; when "Leave site?" appears, click Leave.

"@ -ForegroundColor Yellow
Start-Process -FilePath $exe -ArgumentList ($flags + @("--log-file=`"$Log`"")) -Wait
Start-Sleep 2
} finally {
    if (-not $server.HasExited) { $server.Kill(); $server.WaitForExit(3000) | Out-Null }
}
}
if (-not (Test-Path $Log) -or (Get-Item $Log).Length -eq 0) { Write-Host "FAIL: log missing or EMPTY" -ForegroundColor Red; exit 1 }

function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red } }
$w = @(Get-Content $Log | Where-Object { $_ -match '\[workspaces\]' })
Write-Host "`n--- [workspaces] lines: $($w.Count) ---"; $w | ForEach-Object { "  " + ($_ -replace '^.*?\] ','') }
Write-Host ""

if (-not $OnlyBC) {
# A, in order: asked -> cancelled (nothing closed) -> asked -> closing >25 -> closing <=25 with no ask.
$rx = @{
    asked     = "confirm asked: close all of workspace '$guid', (\d+) tab"
    cancelled = "confirm cancelled"
    closing   = "closing (\d+) tab\(s\) of workspace '$guid'"
}
$events = @(for ($i = 0; $i -lt $w.Count; $i++) {
    foreach ($k in 'asked','cancelled','closing') {
        $m = [regex]::Match($w[$i], $rx[$k]); if ($m.Success) { [pscustomobject]@{ Kind = $k; N = $(if ($m.Groups.Count -gt 1) { [int]$m.Groups[1].Value } else { 0 }) } }
    }
})
Write-Host "A: $(($events | ForEach-Object { if ($_.N) { "$($_.Kind) $($_.N)" } else { $_.Kind } }) -join ' -> ')"
# Found wherever it starts, not only at the top: an earlier accepted ask (asked,closing) before the
# Cancel was tried is harmless and must not hide the sequence that follows it.
$kinds = @($events | ForEach-Object Kind)
$at = -1
for ($i = 0; $i -le $kinds.Count - 5; $i++) { if (($kinds[$i..($i + 4)] -join ',') -eq 'asked,cancelled,asked,closing,closing') { $at = $i; break } }
Verdict "step 2: above 25 it asked, and Cancel closed nothing" ($at -ge 0 -and $events[$at].N -gt 25)
Verdict "step 3: the second ask was accepted and closed them all" ($at -ge 0 -and $events[$at + 3].N -gt 25)
Verdict "step 4: 25 or fewer closed at once, with no ask" ($at -ge 0 -and $events[$at + 4].N -le 25)
}

$j = $w -join "`n"
$kept = ([regex]::Matches($j, "anchored tab at index \d+ asks before leaving; kept live")).Count
Write-Host "B: $kept anchored tab(s) kept live on Ctrl+W"
Verdict "step 7: Ctrl+W on the anchored LEAVE TEST page kept it live, not hibernated or closed" ($kept -ge 1)
Verdict "step 7b: Ctrl+W on an anchored PDF kept it live too, not closed (E13.5 review)" ($kept -ge 2)
Verdict "step 8: 'Hibernate this workspace' kept the LEAVE TEST page awake" ($j -match "unload workspace 'default': asking \d+ tab\(s\), kept [1-9]\d* awake")

$crash = @(Select-String -Path $Log -Pattern 'Check failed|FATAL|NOTREACHED' -CaseSensitive).Count
Verdict "no Check failed / FATAL / NOTREACHED in the log ($crash)" ($crash -eq 0)
Write-Host "`nSteps 2 (the box you saw), 7 and 7b (the tabs still in the strip) and 8 (your text still there) are yours to confirm by eye." -ForegroundColor Yellow
