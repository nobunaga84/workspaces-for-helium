param([switch]$Zen)
# C35 + C31 + C32 (patches 74-76): the owner's own try. Opens the built browser (out\Default) on a FRESH copy of the
# smoke profile -- never the daily browser's profile -- twice: DARK for steps 1-6, then, after you close it, LIGHT for
# step 7 (the scheme written into the copy's Preferences between the starts, as check-c35 does). Seeded before the
# first start: Work gets the pinned page "C35 home" (a local page with one link), Canary the pinned page
# "C35 pinned Y", Unpin no pinned page at all. At steps 4 and 6 the script opens the Today tabs itself through
# DevTools (--remote-debugging-port=0, this PC only), and makes "F favorite" a favorite and "V in a group" a tab group
# through the tab's own menu: a right-click POSTED to the window plus an MSAA press (repro-e191's way, no real mouse).
# The pages are served on this PC only, on a port Windows gives, until the script ends. Both starts with
# --force-color-profile=srgb (this PC's display has HDR on). Each step is answered y/n here; the answers and the log's
# length at each answer go to c35-owner-answers.json, and the end grades the logs (c35-owner-run.log, -run2.log), the
# pins file and the Archive file, and prints a summary for Claude. -Zen: zen mode, sidebar unpinned, as the daily
# browser runs.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c35.ps1
. "$PSScriptRoot\e18-lib.ps1"
$ws      = "<local-path>\Helium-workspace"
$bin     = "$ws\helium-windows\build\src\out\Default"
$exe     = "$bin\chrome.exe"
$prof    = "$ws\testprofile-c35-owner$(if ($Zen) { '-zen' })"
$log     = "$ws\c35-owner-run.log"
$log2    = "$ws\c35-owner-run2.log"
$answers = "$ws\c35-owner-answers.json"
$pages   = "$ws\c35-owner-pages"
$work    = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"
$canary  = "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56"
$unpin   = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
foreach ($s in @("takes the page in front as its address", "duplicates: closing")) {
    & python -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" $s
    if ($LASTEXITCODE -ne 0) { Write-Host "This build has no C31 + C32 yet (no '$s' in out\Default\chrome.dll): tell Claude."; exit 1 }
}
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath $log, $log2, $answers -EA SilentlyContinue
$names = @("c35home", "c35away", "c35x", "c35y", "c35f", "c35z", "c35v")
$srv = ServePages $pages $names
if (-not $srv.ok) { Write-Host "The test pages could not be served: tell Claude."; exit 1 }
$base = "http://127.0.0.1:$($srv.port)"
# A page's title is "C35 <name>", or its #part with the dashes as spaces ("X top copy" for c35x.html#X-top-copy): two
# copies of one address told apart. C35 home has one link.
foreach ($nm in $names) {
    $link = if ($nm -eq "c35home") { "<p style='font-size:28px'><a href='c35away.html'>Go to the next page</a>" } else { "" }
    Set-Content -Encoding ASCII -LiteralPath "$pages\$nm.html" -Value "<!doctype html><title>C35 $($nm.Substring(3))</title><script>if (location.hash) document.title = location.hash.slice(1).replace(/-/g, ' ');</script><h1><script>document.write(document.title)</script></h1>$link"
}
# The pins (check-c35's): "C35 home" (c35p) at the end of Work, "C35 pinned Y" (c35y) at the end of Canary,
# Unpin emptied.
& python -c "import json,sys; p,port,work,canary,unpin=sys.argv[1:6]; u='http://127.0.0.1:%s/' % port; d=json.load(open(p,encoding='utf-8')); d['workspaces'][work].append({'type':'item','id':'c35p','title':'C35 home','url':u+'c35home.html'}); d['workspaces'][canary].append({'type':'item','id':'c35y','title':'C35 pinned Y','url':u+'c35y.html'}); d['workspaces'][unpin]=[]; open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False))" "$prof\Default\Workspace Pins" $srv.port $work $canary $unpin
$ok1 = $LASTEXITCODE -eq 0
$set = @("browser.theme.color_scheme2=2")
if ($Zen) { $set += @("helium.browser.zen_mode=true", "helium.browser.zen_mode_sidebar_pinned=false") }
& python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" @set | Out-Null
if (-not $ok1 -or $LASTEXITCODE -ne 0) { Stop-Process -Id $srv.server.Id -EA SilentlyContinue; Write-Host "Could not seed the copy of the profile: tell Claude."; exit 1 }

$F = [ordered]@{ binary = (Get-Item "$bin\chrome.dll").LastWriteTime.ToString("o"); zen = [bool]$Zen; answers = [ordered]@{}; marks = [ordered]@{ s0 = 0 }; seed = [ordered]@{}; comment = "" }
function Save { $F | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath $answers }
function LogLines { if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log).Count } else { 0 } }
function Step([string]$text) { Write-Host $text -ForegroundColor Yellow }
# The y/n for step `k`, and the log's length at that moment, saved at once.
function Ask([string]$k, [string]$q) {
    do { $r = "$(Read-Host $q)".Trim().ToLower() } while ($r -notin @("y", "n"))
    $F.answers[$k] = $r; $F.marks[$k] = LogLines; Save
}
# The browser, its stdout and stderr in files of their own: with --enable-logging it prints ERROR lines into the
# console that started it, in the middle of the steps (check-e14d3). Its pid.
function Launch([string]$logFile, [string[]]$more) {
    Remove-Item -LiteralPath $logFile, "$prof\DevToolsActivePort" -EA SilentlyContinue
    $a = @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$logFile`"", "--v=0", "--no-first-run", "--no-default-browser-check", "--force-color-profile=srgb") + $more
    (Start-Process $exe -PassThru -ArgumentList $a -RedirectStandardOutput "$logFile.out.txt" -RedirectStandardError "$logFile.err.txt").Id
}
function WaitClosed {
    $t0 = Get-Date; $told = $false
    while (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) {
        if (-not $told -and ((Get-Date) - $t0).TotalSeconds -gt 60) { Write-Host "    (still waiting for the test browser to close: is a window of it still open?)"; $told = $true }
        Start-Sleep -Milliseconds 500
    }
}
# Until the log's last "active workspace" line is `guid` (you pressed its shortcut); false when the browser closed.
function WaitWorkspace([string]$guid) {
    $t0 = Get-Date; $told = $false
    while (Get-Process -Id $script:bpid -EA SilentlyContinue) {
        $m = @(Select-String -LiteralPath $log -Pattern "\[workspaces\] active workspace -> '([^']*)'" -EA SilentlyContinue) | Select-Object -Last 1
        if ($m -and $m.Matches[0].Groups[1].Value -eq $guid) { Start-Sleep 1; return $true }
        if (-not $told -and ((Get-Date) - $t0).TotalSeconds -gt 30) { Write-Host "    (still waiting for Canary: click the test browser's window, then press Shift+Alt+3)"; $told = $true }
        Start-Sleep -Milliseconds 500
    }
    $false
}
# Page `path` opened in front through DevTools (below the tab opened before it), waited for until its title shows: its
# target, or $null. In brackets: pwsh 7's Invoke-RestMethod writes a JSON array to the pipeline as ONE object.
function OpenTab([string]$path) {
    $t = try { Invoke-RestMethod -Method Put -TimeoutSec 10 -Uri "$($script:dev)/new?$([uri]::EscapeDataString("$base/$path"))" } catch { $null }
    if (-not $t) { return $null }
    $want = $path.Split('#')[1].Replace('-', ' ')
    $t0 = Get-Date
    do {
        Start-Sleep -Milliseconds 300
        $n = @(try { (Invoke-RestMethod -TimeoutSec 10 "$($script:dev)/list") | Where-Object { $_.id -eq $t.id -and $_.title -eq $want } } catch { }).Count
    } while (-not $n -and ((Get-Date) - $t0).TotalSeconds -lt 10)
    Start-Sleep -Milliseconds 500
    $t
}
function Msaa([IntPtr]$h, [object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\msaa-press.ps1" -Profile $prof -Window ([long]$h) @a }
if (-not ("PostRC" -as [type])) { Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class PostRC {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  public static void RightClick(IntPtr h, int sx, int sy) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    POINT p; p.x = sx; p.y = sy; ScreenToClient(h, ref p);
    IntPtr l = new IntPtr((p.y << 16) | (p.x & 0xFFFF));
    PostMessage(h, 0x0200, IntPtr.Zero, l);    // WM_MOUSEMOVE
    PostMessage(h, 0x0204, new IntPtr(2), l);  // WM_RBUTTONDOWN, MK_RBUTTON
    PostMessage(h, 0x0205, IntPtr.Zero, l);    // WM_RBUTTONUP
  }
}
"@ }
E18InputType
# Today tab `title`'s own menu, opened by a right-click POSTED to the window, its first shown item matching `re`
# pressed through MSAA by the name it has there (a menu name can carry a shortcut, "Close Ctrl+W"), looked for in
# every other window of the browser (check-c35's OtherPress: in zen mode the first one need not be the menu). True when
# pressed. In zen mode the tab is drawn only while the sidebar is out.
function TabMenu([string]$title, [string]$re) {
    $h = (Get-Process -Id $script:bpid -EA SilentlyContinue).MainWindowHandle
    if (-not $h -or $h -eq [IntPtr]::Zero) { return $false }
    $n = @(ParseMsaaNodes @(Msaa $h @("-List", "-Rect")) | Where-Object { $_.shown -and $_.role -eq 0x25 -and $_.name -like "$title*" }) | Select-Object -First 1
    if (-not $n) { return $false }
    [PostRC]::RightClick($h, $n.l + [int]($n.w / 2), $n.t + [int]($n.h / 2))
    $t0 = Get-Date
    do {
        Start-Sleep -Milliseconds 700
        foreach ($w in [E18Input]::Others([uint32]$script:bpid, $h)) {
            $name = @(Msaa $w @("-List") | ForEach-Object { if ("$_" -match '^\s*(.*?)\|0x[0-9A-F]+$') { $Matches[1] } } | Where-Object { $_ -match $re }) | Select-Object -First 1
            if ($name) { return "$(Msaa $w @('-Name', $name))" -like "MSAA: pressed*" }
        }
    } while (((Get-Date) - $t0).TotalSeconds -lt 10)
    $false
}
$hands = "Keep your hands off the browser until this window says Done.$(if ($Zen) { ' Zen mode: first rest the mouse at the window''s left edge so the sidebar stays out.' })"
$pinText = ""; $archText = ""

try {
    $script:bpid = Launch $log @("--remote-debugging-port=0")
    Write-Host @"
The test browser is opening in DARK mode (a copy of the smoke profile; your daily browser is not touched).
WORDS USED BELOW (the sidebar is the strip on the left of the window):
  PINNED PAGE         a page in the pinned card at the top of the sidebar, e.g. "Example A"
  THE CARD            the rounded background behind the pinned pages
  TODAY TAB           a tab in the list under "+ New Tab"
  FAVORITE            a tab pinned with its own right-click > Pin; it shows in every workspace
  THE WORKSPACE MENU  what opens when you RIGHT-click the workspace's name at the top of the sidebar
                      (a LEFT click there folds the pinned pages away; click it again to bring them back)
  THE ARCHIVE         what the Archive button in the bar at the bottom of the sidebar opens: the closed tabs
$(if ($Zen) { "Zen mode: the sidebar shows while the mouse is at the window's left edge.
" })Answer each question HERE, in this window: y or n, then Enter.
"@
    Step @"

 1. C35 (dark) -- press Shift+Alt+2 (Work) and look at the top of the sidebar.
    PASS: THE CARD is clearly lighter than the sidebar around it; a thin grey edge runs all round it (rounded
    corners); a thin grey line runs across between THE CARD and "+ New Tab".
    Click the PINNED PAGE "Example A" (it opens and is highlighted).
    PASS: the thin edge still shows all round THE CARD, also beside the highlighted "Example A".
    Press Shift+Alt+5 (Unpin: it has no pinned pages).
    PASS: no card, and no grey line above "+ New Tab".
"@
    Ask "s1" "1. dark: THE CARD stands out, a thin edge all round (also beside Example A), a line above + New Tab; Unpin has neither (y/n)"
    Step @"

 2. C31 -- press Shift+Alt+2 (Work). Click the PINNED PAGE "C35 home" (the last one in THE CARD): its page opens.
    Right-click the PINNED PAGE "C35 home".
    PASS: the menu has "Close page" but NOT "Use current page" (the page is still at its pinned
    address). Press Esc.
"@
    Ask "s2" "2. at its own address, C35 home's menu had Close page and no 'Use current page' (y/n)"
    Step @"

 3. On the "C35 home" page, click the link "Go to the next page".
    PASS: the page "C35 away" shows, and a small back arrow appears on the PINNED PAGE "C35 home" (resting the
    mouse on the arrow says "Back to the pinned page").
    Right-click the PINNED PAGE "C35 home".
    PASS: the menu has "Use current page", right above "Unpin". Click it.
    PASS: the back arrow is gone, and the PINNED PAGE now reads "C35 away".
    Right-click the PINNED PAGE "C35 away" (the same one).
    PASS: no "Use current page" this time (the page is at its new pinned address). Press Esc.
"@
    Ask "s3" "3. the back arrow showed; Use current page took it away and renamed the pinned page 'C35 away'; then its menu no longer offered it (y/n)"

    Step @"

 4. C32 -- press Shift+Alt+3 (Canary). This window then opens six TODAY TABS there by itself and makes one
    of them a FAVORITE (about 20 seconds). $hands
"@
    if (-not (WaitWorkspace $canary)) { throw "the browser closed before Canary showed" }
    $port = Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1 -EA SilentlyContinue
    $script:dev = "http://127.0.0.1:$port/json"
    # The LOWER copy of X is the one used last: a tab opened through DevTools lands below the one before (10-18),
    # and "X used last" is left only when Y opens -- so "the top one" would be the wrong keeper.
    $xt = OpenTab "c35x.html#X-top-copy"
    $xl = OpenTab "c35x.html#X-used-last"
    $y  = OpenTab "c35y.html#Y-copy-of-pinned"
    $fv = OpenTab "c35f.html#F-favorite"
    $pinned = TabMenu "F favorite" '^Add to Favorites'
    Start-Sleep 1
    $fc = OpenTab "c35f.html#F-copy-of-favorite"
    $z  = OpenTab "c35z.html#Z-only-one"
    $opened = @($xl, $xt, $y, $fv, $fc, $z | Where-Object { $_ }).Count
    $F.seed["s4"] = "DevTools port '$port': $opened of 6 tabs opened; F favorite made a favorite: $pinned"; Save
    if ($opened -lt 6) { Step "    The script opened only $opened of the 6 tabs: answer n, and tell Claude." }
    if (-not $pinned) { Step "    The script could not make 'F favorite' a FAVORITE by itself. If a menu is open press Esc, then right-click`n    the TODAY TAB 'F favorite' > Pin." }
    Step @"
    Done. Canary now has the FAVORITE "F favorite" and these TODAY TABS, top to bottom:
        X top copy / X used last / Y copy of pinned / F copy of favorite / Z only one
    (An empty New Tab may sit among them, opened by the switch: leave it -- a New Tab is never a copy.)
    The copies: "X top copy" and "X used last" are one address, and "X used last" is the one you used last (the
    script opened it after "X top copy"); "Y copy of pinned" is the address of the PINNED PAGE "C35 pinned Y";
    "F copy of favorite" is the address of the FAVORITE "F favorite".
    Do NOT click any TODAY TAB before the box below has closed them: the tab you click becomes the one used last.
    Open THE WORKSPACE MENU: right-click the name "Canary" at the top of the sidebar.
    PASS: "Close duplicate tabs..." is in it, just above "Close all tabs", and not greyed. Click it.
    PASS: a box asks "Close 3 duplicate tabs?", lists "F copy of favorite", "Y copy of pinned" and "X top copy",
    and says "They stay in the Archive." Click "Close tabs".
    PASS: "F copy of favorite", "Y copy of pinned" and "X top copy" are gone. "X used last" stays (the copy used
    last, though it is the lower one), and so do "Z only one" and the FAVORITE "F favorite".
    Click the Archive button in the bar at the bottom of the sidebar.
    PASS: THE ARCHIVE lists "F copy of favorite", "Y copy of pinned" and "X top copy" at the top. Click outside
    it to close it.
"@
    Ask "s4" "4. the box asked to close 3 (F copy of favorite, Y copy of pinned, X top copy); X used last, Z only one and F favorite stayed; THE ARCHIVE lists the 3 (y/n)"
    Step @"

 5. Open THE WORKSPACE MENU again (right-click "Canary").
    PASS: "Close duplicate tabs..." is there but greyed: no copies are left. Press Esc.
"@
    Ask "s5" "5. 'Close duplicate tabs...' was greyed (y/n)"

    Step @"

 6. A tab in a tab group is never closed as a copy (you put it there on purpose). Stay in Canary (Shift+Alt+3): this
    window opens "V in a group" (and puts it in a new tab group) and "V loose copy" -- one address (about 15
    seconds). $hands
"@
    if (-not (WaitWorkspace $canary)) { throw "the browser closed before step 6" }
    $vg = OpenTab "c35v.html#V-in-a-group"
    $grouped = TabMenu "V in a group" '^Add tab to new group$'
    Start-Sleep 2
    $vl = OpenTab "c35v.html#V-loose-copy"
    $F.seed["s6"] = "$(@($vg, $vl | Where-Object { $_ }).Count) of 2 tabs opened; V in a group grouped: $grouped"; Save
    if (-not $grouped) { Step "    The script could not put 'V in a group' in a group by itself. If a menu is open press Esc, then right-click`n    the TODAY TAB 'V in a group' > Add tab to new group (or Add tab to group > New group)." }
    Step @"
    Done. If a small box to name the group is open, press Esc.
    Open THE WORKSPACE MENU > "Close duplicate tabs...".
    PASS: the box asks "Close 1 duplicate tab?" and lists only "V loose copy". Click "Close tabs".
    PASS: "V loose copy" is gone; "V in a group" is still there, inside its group.
"@
    Ask "s6" "6. the box listed only V loose copy; V in a group stayed, inside its group (y/n)"

    Step @"

 Now close the test browser (the X at its top right). This window waits for it, then opens it again in LIGHT mode.
"@
    WaitClosed
    $pinText  = try { [IO.File]::ReadAllText("$prof\Default\Workspace Pins", [Text.Encoding]::UTF8) } catch { "" }
    $archText = try { [IO.File]::ReadAllText("$prof\Default\Workspace Archive", [Text.Encoding]::UTF8) } catch { "" }
    & python "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "browser.theme.color_scheme2=1" | Out-Null
    if ($LASTEXITCODE -ne 0) { Step "    Could not switch the copy to light mode: answer step 7 n, and tell Claude." }
    $script:bpid = Launch $log2 @()
    Step @"

 7. C35 (light) -- press Shift+Alt+2 (Work) and look at the top of the sidebar.
    PASS: the same thin edge all round THE CARD and the same thin line between THE CARD and "+ New Tab", light
    grey here. THE CARD itself is only a faint grey on the white sidebar (its light shade did not change).
"@
    Ask "s7" "7. light: the same thin edge round THE CARD and the line above + New Tab (y/n)"
    Step "`n Close the test browser. This window then grades the run."
    WaitClosed
    $F.comment = "$(Read-Host "Anything that looked wrong or odd? (Enter for nothing)")".Trim(); Save
} catch {
    Write-Host "STOPPED: $_" -ForegroundColor Red
} finally {
    Stop-Process -Id $srv.server.Id -EA SilentlyContinue
}

# ---- grading: the logs and files (what you saw is your y/n) -----------------------------------------------------
$script:passed = 0; $script:failed = 0
function Row($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green; $script:passed++ } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
$lines = if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) } else { @() }
# The first group of each log line matching `re` logged during step `k` (after the previous answer, up to this one).
function During([string]$k, [string]$re) {
    $a = $F.marks["s$([int]$k.Substring(1) - 1)"]; $b = $F.marks[$k]
    if ($null -eq $a -or $null -eq $b) { return @() }
    @($lines | Select-String -Pattern $re | Where-Object { $_.LineNumber -gt $a -and $_.LineNumber -le $b } | ForEach-Object { $_.Matches[0].Groups[1].Value })
}
$took     = "\[workspaces\] pins: '(c35p)' takes the page in front as its address"
$menuDup  = "\[workspaces\] duplicates: (\d+) of workspace '$canary' \(menu\)"
$askedDup = "\[workspaces\] duplicates: asked to close (\d+)"
$closeDup = "\[workspaces\] duplicates: closing (\d+ of \d+) listed in workspace '$canary'"
$lines | Select-String -Pattern "\[workspaces\] (duplicates: |pins: 'c35p')" | ForEach-Object { Write-Host ("      log: " + ($_.Line -replace '^.*?\[workspaces\] ', '')) }

$n3 = @(During "s3" $took).Count; $all = @($lines | Select-String -Pattern $took).Count
Row "step 3 C31: 'takes the page in front as its address' logged $n3 time(s) during step 3, $all in the run (want 1 and 1)" ($n3 -eq 1 -and $all -eq 1)
$pin = try { @(($pinText | ConvertFrom-Json).workspaces.$work | Where-Object { $_ -and $_.id -eq "c35p" }) | Select-Object -First 1 } catch { $null }
Row "step 3 C31: the pins file: 'C35 home' now '$($pin.url)', titled '$($pin.title)' (want $base/c35away.html, 'C35 away')" ($pin -and $pin.url -eq "$base/c35away.html" -and $pin.title -eq "C35 away")
$m4 = During "s4" $menuDup; $a4 = During "s4" $askedDup; $c4 = During "s4" $closeDup
Row "step 4 C32: the menu counted $($m4 -join ',') (want 3), the box asked $($a4 -join ',') (want 3), closing $($c4 -join ',') (want 3 of 3)" ($m4 -contains "3" -and $a4 -contains "3" -and $c4 -contains "3 of 3")
$m5 = During "s5" $menuDup
Row "step 5 C32: the menu counted $($m5 -join ',') (want 0: greyed)" ($m5 -contains "0")
$m6 = During "s6" $menuDup; $a6 = During "s6" $askedDup; $c6 = During "s6" $closeDup
Row "step 6 D12: the menu counted $($m6 -join ',') (want 1), the box asked $($a6 -join ',') (want 1), closing $($c6 -join ',') (want 1 of 1)" ($m6 -contains "1" -and $a6 -contains "1" -and $c6 -contains "1 of 1")
$closed = @("c35x.html#X-top-copy", "c35y.html#Y-copy-of-pinned", "c35f.html#F-copy-of-favorite", "c35v.html#V-loose-copy")
$stay   = @("c35x.html#X-used-last", "c35z.html#Z-only-one", "c35f.html#F-favorite", "c35v.html#V-in-a-group")
$inArch = @(try { ($archText | ConvertFrom-Json).entries | Where-Object { $_ -and $_.workspace -eq $canary } | ForEach-Object { "$($_.url)".Replace("$base/", "") } } catch { })
$missing = @($closed | Where-Object { $inArch -notcontains $_ }); $wrong = @($stay | Where-Object { $inArch -contains $_ })
Row "steps 4 + 6 C32: the Archive file holds $($closed.Count - $missing.Count) of the 4 closed copies (missing: $($missing -join ', ')) and $($wrong.Count) of the tabs that stay (want 4 and 0: $($wrong -join ', '))" ($missing.Count -eq 0 -and $wrong.Count -eq 0)
# Case-sensitive, as LOCAL.md grades (check-c35's markers).
$markers = 0
foreach ($l in @($log, $log2)) { if (Test-Path -LiteralPath $l) { $markers += @(Select-String -LiteralPath $l -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count } }
Row "crash markers in both logs: $markers (want 0)" ($markers -eq 0)

$yes = @($F.answers.Values | Where-Object { $_ -eq "y" }).Count
Write-Host "your answers: $(@($F.answers.Keys | ForEach-Object { "$_ $($F.answers[$_])" }) -join ', ')$(if ($F.comment) { "; comment: $($F.comment)" })"
Write-Host "seeding: step 4 $($F.seed['s4']); step 6 $($F.seed['s6'])"
$verdict = if ($yes -eq 7 -and $script:failed -eq 0) { "PASS" } else { "FAIL" }
Write-Host "RESULT c35-owner$(if ($Zen) { '-zen' }) you said y to $yes of 7; log checks pass=$($script:passed) fail=$($script:failed); crash markers $markers; verdict=$verdict"
Write-Host "Tell Claude the RESULT line (or copy this whole window). Logs: $log, $log2; answers: $answers."
