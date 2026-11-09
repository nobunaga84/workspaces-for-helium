param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$Tag = "c191", [double]$IdleMinutes = 15)
# C19.1 (patch 85): Export workspaces / Import workspaces in the "+" menu, hands-free. The browser's own dialogs are
# native and cannot be driven, so a hidden switch, --helium-workspaces-transfer-auto=<file>, makes the menu items skip the
# dialogs, the confirm and the result bubbles and use that file (the log has the result). The menu items themselves are
# pressed through MSAA (no mouse): the "+" button, then the item. On throwaway copies of the smoke profile; your daily
# profile is only READ (an export by the Python tool, local/workspaces-transfer.py, as the data to move around).
#   pwsh -NoProfile -File local\check-c191.ps1 [-Build Dcheck] [-IdleMinutes 0]
#   M1  the "+" menu lists Export workspaces and Import workspaces (the switch not given: nothing is pressed)
#   E1  the browser EXPORTS a copy A of the daily data to a .json: "export: wrote"; the Python tool reads it (checksums
#       and all) and its counts equal the daily ones
#   E2  the same menu item to a .csv: a header and one row per pinned page, the workspaces' names
#   X1  the Python tool IMPORTS the browser's file (--dry-run) into a fresh copy: the two implementations agree
#   I1  the browser IMPORTS a file made by the Python tool into a copy B of the smoke profile: "import: applied N
#       workspace(s) ..." with the file's counts, no "REFUSED"
#   I2  live, without a restart: the bar draws the daily workspaces' chips (the names read from the export)
#   I3  a pinned page of the imported Work is drawn on pressing its chip ("pins: drew N row(s) of '<Work>'", N from the file)
#   I4  after the quit, B's files equal the file's pins and archive (parsed), B's workspace list equals the file's, and the
#       profile's own "enabled" is kept
#   I5  the copy made first: Workspace Backups\before-import-*.json is a good export holding B's old counts
#   R1  a damaged file is refused: "import: refused", B's pins file unchanged
#   R2  a file that is not an export is refused the same way
#   Z   0 crash markers in the logs (case-sensitive, DanglingPtr too)
. "$PSScriptRoot\e18-lib.ps1"
$ws     = "<local-path>\Helium-workspace"
$here   = $PSScriptRoot
$bin    = "$ws\helium-windows\build\src\out\$Build"
$exe    = "$bin\chrome.exe"
$smoke  = "$ws\testprofile-e15b-smoke"
$sfx    = if ($Build -eq "Dcheck") { "-dcheck" } else { "" }
$tool   = "$here\workspaces-transfer.py"
$daily  = Join-Path $env:LOCALAPPDATA "Helium Workspaces\User Data"
$dir    = "$ws\$Tag$sfx-files"
$profA  = "$ws\testprofile-$Tag-a$sfx"
$profB  = "$ws\testprofile-$Tag-b$sfx"
$slow   = if ($Build -eq "Dcheck") { 3 } else { 1 }
$total  = 12
$script:failed = 0; $script:passed = 0; $script:logs = @()
function Say([string]$s) { Write-Host $s }
function Verdict($name, $ok) { if ($ok) { Say "PASS  $name"; $script:passed++ } else { Say "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Say "ABORT: $why"; exit 1 }
function Msaa([IntPtr]$h, [string]$prof, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
function Nodes([IntPtr]$h, [string]$prof) { ParseMsaaNodes @(Msaa $h $prof @("-List", "-Rect")) }
function Popups([uint32]$bp, [IntPtr]$main) { $wins = @([E18Input]::Windows($bp)); @([E18Input]::Others($bp, $main) | Where-Object { $wins -notcontains $_ }) }
function MenuNames([uint32]$bp, [IntPtr]$main, [string]$prof) { $o = @(); foreach ($w in (Popups $bp $main)) { $o += @(Nodes $w $prof | Where-Object { $_.shown } | ForEach-Object { $_.name }) }; $o }
function OtherPress([uint32]$bp, [IntPtr]$main, [string]$prof, [string]$re) {
    $t0 = Get-Date
    do {
        foreach ($w in (Popups $bp $main)) {
            $n = @(Nodes $w $prof | Where-Object { $_.shown -and $_.name -match $re }) | Select-Object -First 1
            if ($n) { return "'$($n.name)' $("$(Msaa $w $prof @('-Name', $n.name, '-Role', $n.role))")" }
        }
        Start-Sleep -Milliseconds 500
    } while (((Get-Date) - $t0).TotalSeconds -lt 10 * $slow)
    "nothing matching '$re'"
}
# One browser start on profile `prof`, with the log `log`; returns @{ pid; main; log }.
function Start-Browser([string]$prof, [string]$log, [string]$auto = "") {
    Remove-Item -LiteralPath $log -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check")
    if ($auto) { $a += "--helium-workspaces-transfer-auto=`"$auto`"" }
    $p = Start-Process $exe -PassThru -ArgumentList $a
    $main = [IntPtr]::Zero; $t0 = Get-Date
    while ($main -eq [IntPtr]::Zero -and ((Get-Date) - $t0).TotalSeconds -lt 40 * $slow) { Start-Sleep 1; $q = Get-Process -Id $p.Id -EA SilentlyContinue; if ($q) { $main = $q.MainWindowHandle } }
    if ($main -eq [IntPtr]::Zero) { throw "no browser window" }
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt 60 * $slow) { if ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern "pins: (drew|header)" -Quiet)) { break }; Start-Sleep -Milliseconds 500 }
    [E18Input]::Place($main, 40, 40, 1400, 900)
    Start-Sleep (2 * $slow)
    $script:logs += $log
    @{ pid = [uint32]$p.Id; main = $main; log = $log; prof = $prof }
}
function Stop-Browser($b) {
    foreach ($w in [E18Input]::Windows($b.pid)) { [E18Input]::CloseWindow($w) }
    $t0 = Get-Date
    while ((Get-Process -Id $b.pid -EA SilentlyContinue) -and ((Get-Date) - $t0).TotalSeconds -lt 40 * $slow) { Start-Sleep 1 }
    $left = @(Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }); $left | Stop-Process -Force -EA SilentlyContinue
}
function Lines($b, [string]$re) { if (Test-Path -LiteralPath $b.log) { @(Select-String -LiteralPath $b.log -CaseSensitive -Pattern $re) } else { @() } }
function WaitLog($b, [string]$re, [int]$s = 30) { $t0 = Get-Date; while (((Get-Date) - $t0).TotalSeconds -lt $s * $slow) { if ((Lines $b $re).Count) { return $true }; Start-Sleep -Milliseconds 400 }; $false }
# The "+" button, then the menu item matching `re`. What happened.
function PlusItem($b, [string]$re) {
    $r1 = "$(Msaa $b.main $b.prof @('-Name', 'New tab, workspace or search'))"
    Start-Sleep -Milliseconds (800 * $slow)
    $r2 = OtherPress $b.pid $b.main $b.prof $re
    "$($r1.Substring(0, [Math]::Min(60, $r1.Length))); $r2"
}
function Fresh([string]$prof) {
    if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
    $null = robocopy $smoke $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
    Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
    # The chips and the + need the sidebar wide enough (as check-c4 seeds it).
    & python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null
}

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" -or $_.Path -like "$bin\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath $exe)) { Abort "no $exe" }
$free = "$(& pwsh -NoProfile -File "$ws\e17-pc-free.ps1" -IdleMinutes $IdleMinutes | Select-Object -Last 1)"
Say "gate: $free"
if ($free -notlike "FREE*") { Abort "the PC is not free for the browser's windows ($free)" }
E18InputType
if (-not ("C191Win" -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class C191Win {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  // The visible windows, of any process, whose title contains `needle`. Windows runs the file dialog in a host of its
  // own, so it is not among the browser's windows.
  public static IntPtr[] Titled(string needle) {
    List<IntPtr> o = new List<IntPtr>();
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      StringBuilder t = new StringBuilder(256); GetWindowText(h, t, 256);
      if (IsWindowVisible(h) && t.ToString().IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) o.Add(h);
      return true;
    }, IntPtr.Zero);
    return o.ToArray();
  }
  public static void Close(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }
}
'@
}
New-Item -ItemType Directory -Force $dir | Out-Null

# ---- the data: a Python-made export of the DAILY profile (read-only), and what it holds
$fromPy = "$dir\from-python.json"
& python $tool export $daily $fromPy | Out-Null
$want = & python -I -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
print(json.dumps({'counts': d['counts'], 'files': {k: v['content'] for k, v in d['files'].items()}}))
" $fromPy | ConvertFrom-Json
$counts = $want.counts
$wantPins = $want.files.'Workspace Pins' | ConvertFrom-Json -AsHashtable
$titles = @(($want.files.'prefs.json' | ConvertFrom-Json).helium.workspaces.list.items | Where-Object { $_.title } | ForEach-Object { $_.title })
$workGuid = (($want.files.'prefs.json' | ConvertFrom-Json).helium.workspaces.list.items | Where-Object { $_.title -eq "Work" } | Select-Object -First 1).guid
$workRows = 0
function Drawn($rows) { $c = 0; foreach ($n in $rows) { $c++; if ($n.type -eq "folder" -and $n.open) { $c += Drawn $n.children } }; $c }
if ($workGuid -and $wantPins.workspaces.ContainsKey($workGuid)) { $workRows = Drawn $wantPins.workspaces[$workGuid] }
Say "the data: $($counts.workspaces) workspaces, $($counts.pinned_pages) pinned pages, $($counts.folders) folders, $($counts.archive_entries) archive entries; Work '$workGuid' draws $workRows rows"

try {
    # ---- A: a copy of the smoke profile that already HAS the daily data, so the browser exports it
    Fresh $profA
    & python $tool import $fromPy $profA --yes | Out-Null
    $bn = Start-Browser $profA "$ws\$Tag$sfx-menu.log"
    $r = PlusItem $bn "^Export workspaces"      # the switch is absent: this press opens the real Save dialog
    $t0 = Get-Date
    while (-not @([C191Win]::Titled("Export workspaces")).Count -and ((Get-Date) - $t0).TotalSeconds -lt 20 * $slow) { Start-Sleep -Milliseconds 500 }
    $dialogOpened = @([C191Win]::Titled("Export workspaces")).Count -gt 0
    # Cancelled before the quit: a browser that quits with a native dialog open trips Chromium's own DCHECK in
    # BaseShellDialogImpl's destructor (a debug build only), whoever opened it.
    foreach ($i in 1..6) { $ds = @([C191Win]::Titled("Export workspaces")); if (-not $ds.Count) { break }; foreach ($d in $ds) { [C191Win]::Close($d) }; Start-Sleep -Milliseconds 700 }
    Start-Sleep 1
    Stop-Browser $bn
    Verdict "M1 the + menu has Export workspaces and Import workspaces, and without the switch a real Save dialog opens ($r; dialog opened: $dialogOpened)" ($r -match "Export workspaces" -and $dialogOpened)
} catch { Say "ERROR M1 (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ }
try {
    $out1 = "$dir\browser-export.json"; Remove-Item -LiteralPath $out1 -EA SilentlyContinue
    $be = Start-Browser $profA "$ws\$Tag$sfx-export.log" $out1
    $r = PlusItem $be "^Export workspaces"
    $okw = WaitLog $be "export: wrote" 30
    Start-Sleep 2; Stop-Browser $be
    $show = & python $tool show $out1 2>&1 | Out-String
    $got = $null; try { $got = ($show | ConvertFrom-Json).counts } catch {}
    Verdict "E1 the browser exported ($r; wrote: $okw), and the Python tool reads it: counts $(if ($got) { "$($got.workspaces)/$($got.pinned_pages)/$($got.folders)/$($got.archive_entries)" } else { 'UNREADABLE' }) (want $($counts.workspaces)/$($counts.pinned_pages)/$($counts.folders)/$($counts.archive_entries); the archive may differ by entries past 60 days)" ($okw -and $got -and $got.workspaces -eq $counts.workspaces -and $got.pinned_pages -eq $counts.pinned_pages -and $got.folders -eq $counts.folders)

    $out2 = "$dir\browser-export.csv"; Remove-Item -LiteralPath $out2 -EA SilentlyContinue
    $bc = Start-Browser $profA "$ws\$Tag$sfx-csv.log" $out2
    $r = PlusItem $bc "^Export workspaces"
    $okc = WaitLog $bc "export: wrote" 30
    Start-Sleep 2; Stop-Browser $bc
    $rows = @()
    if (Test-Path -LiteralPath $out2) { $rows = @(Import-Csv -LiteralPath $out2 -Encoding UTF8) }
    $head = if (Test-Path -LiteralPath $out2) { (Get-Content -LiteralPath $out2 -TotalCount 1 -Encoding UTF8) -replace "^\uFEFF", "" } else { "" }
    Verdict "E2 the browser exported a .csv ($r; wrote: $okc): header '$head', $($rows.Count) row(s) (want $($counts.pinned_pages)), workspaces named: $((@($rows | ForEach-Object { $_.workspace } | Sort-Object -Unique) -join ', '))" ($okc -and $head -eq "workspace,folder,kind,title,url,last_used" -and $rows.Count -eq $counts.pinned_pages)

    $chk = "$ws\testprofile-$Tag-x$sfx"; Fresh $chk
    $dry = & python $tool import $out1 $chk --dry-run 2>&1 | Out-String
    Verdict "X1 the Python tool reads the browser's file in a dry run into a fresh copy: $((($dry -split "`n") | Select-Object -Last 2) -join ' ' )" ($dry -match "dry run: nothing written" -and $dry -match "pinned pages\s+now\s+\d+\s+->\s+file\s+$($counts.pinned_pages)")
} catch { Say "ERROR E (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ }

try {
    # ---- B: a copy of the smoke profile with its own small data; the browser imports the Python-made file
    Fresh $profB
    $beforePins = (Get-FileHash "$profB\Default\Workspace Pins").Hash
    $oldCounts = & python -I -c "
import json, sys
p = json.load(open(sys.argv[1] + '/Default/Workspace Pins', encoding='utf-8'))
def c(rows):
    n = 0
    for r in rows: n += (r['type'] == 'item') + c(r.get('children', []))
    return n
print(sum(c(v) for v in p['workspaces'].values()))
" ($profB -replace '\\', '/')
    $bi = Start-Browser $profB "$ws\$Tag$sfx-import.log" $fromPy
    $r = PlusItem $bi "^Import workspaces"
    $applied = WaitLog $bi "import: applied" 60
    $line = (Lines $bi "import: applied" | Select-Object -Last 1)
    $refused = (Lines $bi "REFUSED").Count
    Verdict "I1 the browser imported the Python-made file ($r): $(if ($line) { $line.Line.Substring($line.Line.IndexOf('import:')) } else { 'no line' }); refused: $refused" ($applied -and $refused -eq 0 -and $line.Line -match "applied $($counts.workspaces) workspace\(s\), $($counts.pinned_pages) pinned page\(s\), $($counts.folders) folder\(s\), \d+ archive")
    Start-Sleep (3 * $slow)
    $nodes = Nodes $bi.main $profB
    $missing = @($titles | Where-Object { $t = $_; -not @($nodes | Where-Object { $_.shown -and $_.role -eq 0x2B -and $_.name -eq $t }).Count })
    Verdict "I2 live, with no restart, the bar draws the imported workspaces' chips ($($titles -join ', ')); missing: $(if ($missing.Count) { $missing -join ', ' } else { 'none' })" ($titles.Count -ge 1 -and -not $missing.Count)
    if ($workRows -gt 0) {
        $null = Msaa $bi.main $profB @("-Name", "Work", "-Role", 0x2B)
        $drew = WaitLog $bi "pins: drew $workRows row\(s\) of '$workGuid'" 30
    } else { $drew = $true }
    Verdict "I3 pressing the Work chip draws its imported pinned rows ($workRows expected): $drew" $drew
    Start-Sleep 4; Stop-Browser $bi
    Start-Sleep 3
    $cmp = & python -I -c "
import json, sys
src = json.load(open(sys.argv[1], encoding='utf-8'))
T = sys.argv[2] + '/Default/'
ok = True
for name in ('Workspace Pins', 'Workspace Archive'):
    want = json.loads(src['files'][name]['content']); got = json.load(open(T + name, encoding='utf-8'))
    if name == 'Workspace Archive':
        # entries past the 60 days are dropped when the browser takes them
        import time
        cut = (time.time() + 11644473600 - 60 * 86400) * 1e6
        want['entries'] = [e for e in want['entries'] if int(e['archived_at']) >= cut]
    ok = ok and want == got
wl = json.loads(src['files']['prefs.json']['content'])['helium']['workspaces']['list']
pg = json.load(open(T + 'Preferences', encoding='utf-8'))['helium']['workspaces']
print('EQUAL' if ok and pg['list'] == wl else 'DIFFERENT', 'enabled=' + str(pg.get('enabled')))
" $fromPy ($profB -replace '\\', '/')
    Verdict "I4 after the quit B's files equal the file's pins and archive, and its list equals the file's: $cmp" ("$cmp" -like "EQUAL*" -and "$cmp" -like "*enabled=True*")
    $backup = @(Get-ChildItem "$profB\Default\Workspace Backups" -Filter "before-import-*.json" -EA SilentlyContinue)
    $bshow = if ($backup.Count) { & python $tool show $backup[-1].FullName 2>&1 | Out-String } else { "" }
    $bc2 = $null; try { $bc2 = ($bshow | ConvertFrom-Json).counts } catch {}
    Verdict "I5 the copy made first: $($backup.Count) file(s) in Workspace Backups; it reads as an export holding $(if ($bc2) { "$($bc2.pinned_pages) pinned pages" } else { 'nothing' }) (B had $oldCounts)" ($backup.Count -eq 1 -and $bc2 -and $bc2.pinned_pages -eq [int]$oldCounts)
} catch { Say "ERROR I (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ }

try {
    # ---- refusals, on B as it is now
    $pinsNow = (Get-FileHash "$profB\Default\Workspace Pins").Hash
    $bad = "$dir\damaged.json"
    & python -I -c "
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = d['files']['Workspace Pins']['content']
d['files']['Workspace Pins']['content'] = c.replace('https://', 'http://', 1)
json.dump(d, open(sys.argv[2], 'w', encoding='utf-8'))
" $fromPy $bad
    $br = Start-Browser $profB "$ws\$Tag$sfx-refuse1.log" $bad
    $r = PlusItem $br "^Import workspaces"
    $ref = WaitLog $br "import: refused" 30
    Start-Sleep 3; Stop-Browser $br
    Verdict "R1 a damaged file is refused ($r): refused line $ref, pins file hash $(if ((Get-FileHash "$profB\Default\Workspace Pins").Hash -eq $pinsNow) { 'unchanged' } else { 'CHANGED' })" ($ref -and (Get-FileHash "$profB\Default\Workspace Pins").Hash -eq $pinsNow)
    $notmine = "$dir\not-an-export.json"; Set-Content -LiteralPath $notmine -Value '{"hello": "world"}' -Encoding UTF8
    $br2 = Start-Browser $profB "$ws\$Tag$sfx-refuse2.log" $notmine
    $r = PlusItem $br2 "^Import workspaces"
    $ref2 = WaitLog $br2 "import: refused" 30
    Start-Sleep 3; Stop-Browser $br2
    Verdict "R2 a file that is not an export is refused ($r): refused line $ref2, pins file hash $(if ((Get-FileHash "$profB\Default\Workspace Pins").Hash -eq $pinsNow) { 'unchanged' } else { 'CHANGED' })" ($ref2 -and (Get-FileHash "$profB\Default\Workspace Pins").Hash -eq $pinsNow)
} catch { Say "ERROR R (line $($_.InvocationInfo.ScriptLineNumber)): $_"; $script:failed++ }

$markers = 0; $bytes = 0
foreach ($l in $script:logs) { if (Test-Path -LiteralPath $l) { $bytes += (Get-Item $l).Length; $markers += @(Get-Content -LiteralPath $l | Select-String -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Verdict "Z crash markers in $($script:logs.Count) log(s), $bytes bytes: $markers" ($markers -eq 0 -and $bytes -gt 0)
$verdict = if ($script:failed -or $script:passed -lt $total) { "FAIL" } else { "PASS" }
Say "RESULT $Tag$sfx pass=$($script:passed) fail=$($script:failed) verdict=$verdict"
exit [int]($verdict -eq "FAIL")
