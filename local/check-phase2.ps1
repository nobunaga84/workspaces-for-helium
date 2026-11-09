param([switch]$GradeOnly)
# Phase 2, the owner's look at the INSTALLER (local/package-installer.py made it): install it, open it from the
# Start menu, pin it, open a page with it, see it in Default apps, then uninstall it twice -- keeping the data,
# then deleting it. It ends with NOTHING installed and no Helium Workspaces profile, as switch day needs
# (LOCAL.md 55's sheet installs it again). It never touches official Helium: graded by official Helium's
# 'Last Browser' file, which names the last program to open official Helium's profile.
# Each step is answered y/n here; the files and registry are graded too.
# One line, PowerShell 7 (pwsh):
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-phase2.ps1
#   (-GradeOnly grades the saved answers again)
$ws      = "<local-path>\Helium-workspace"
$answers = "$ws\p2-owner-answers.json"
$dir     = "$env:LOCALAPPDATA\Programs\Helium Workspaces"
$data    = "$env:LOCALAPPDATA\Helium Workspaces"
$prof    = "$data\User Data"
$exe     = "$dir\chrome.exe"
$lnk     = [Environment]::GetFolderPath('Programs') + "\Helium Workspaces.lnk"
$offLB   = "$env:LOCALAPPDATA\imput\Helium\User Data\Last Browser"
$html    = "$ws\dist\phase2-test.html"
$ukey    = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HeliumWorkspaces"
function Fail([string]$why) { Write-Host "ABORT: $why" -ForegroundColor Red; exit 1 }
$questions = [ordered]@{
    s1 = "1. The installer's first page was the warning ('unofficial personal add-on'), its last page said where to find it (y/n)"
    s2 = "2. Helium Workspaces opened: the tab list on the left, the workspace rail (Home) at the bottom (y/n)"
    s3 = "3. The taskbar icon opened Helium Workspaces again, with its rail, not official Helium (y/n)"
    s4 = "4. Open with listed 'Helium Workspaces' (not a second 'Helium'), and 'Phase 2 test page' opened in it (y/n)"
    s5 = "5. Settings > Default apps lists Helium Workspaces (you did NOT pick it) (y/n)"
    s6 = "6. The uninstaller's 'Also delete my data' box was EMPTY, and you left it empty (y/n)"
    s7 = "7. You ticked 'Also delete my data' and the uninstaller finished (y/n)"
}
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function Reg($path, $name) { try { (Get-ItemProperty -LiteralPath $path -EA Stop).$name } catch { $null } }
function Hash($p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p).Hash } else { "" } }
function LBName($p) { if (Test-Path -LiteralPath $p) { [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($p)).TrimEnd([char]0) } else { "" } }
# Tracked prefs (restore_on_startup) live in Secure Preferences on Windows, the rest in Preferences.
function Json([string]$file) { try { [IO.File]::ReadAllText("$prof\Default\$file") | ConvertFrom-Json } catch { $null } }
function SessionHas([string]$s) { @(Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Where-Object { [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains($s) }).Count -ge 1 }
# The names the Open with menu shows for .html, as "<shown name> | <program>" (IAssocHandler::GetUIName).
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
[ComImport, Guid("F04061AC-1659-4a3f-A954-775AA57FC083"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAssocHandler {
  [PreserveSig] int GetName([MarshalAs(UnmanagedType.LPWStr)] out string s);
  [PreserveSig] int GetUIName([MarshalAs(UnmanagedType.LPWStr)] out string s);
}
[ComImport, Guid("973810ae-9599-4b88-9e4d-6ee98c9552da"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IEnumAssocHandlers {
  [PreserveSig] int Next(uint n, [MarshalAs(UnmanagedType.Interface)] out IAssocHandler h, out uint got);
}
public static class OpenWith {
  [DllImport("shell32.dll")] static extern int SHAssocEnumHandlers([MarshalAs(UnmanagedType.LPWStr)] string ext, int filter, out IEnumAssocHandlers e);
  public static List<string> List(string ext) {
    var r = new List<string>(); IEnumAssocHandlers e;
    if (SHAssocEnumHandlers(ext, 0, out e) != 0) return r;
    IAssocHandler h; uint got;
    while (e.Next(1, out h, out got) == 0 && got == 1) { string n, u; h.GetName(out n); h.GetUIName(out u); r.Add(u + " | " + n); }
    return r;
  }
}
"@
function Save { $F | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $answers -Encoding utf8 }
function Ask([string]$k) {
    do { $r = "$(Read-Host $questions[$k])".Trim().ToLower() } while ($r -notin @('y', 'n'))
    $F.answers[$k] = $r; Save
}
function Step([string]$text) { Write-Host $text -ForegroundColor Yellow }
function WaitGone([string]$path, [int]$sec = 600) { $t = Get-Date; while ((Test-Path -LiteralPath $path) -and ((Get-Date) - $t).TotalSeconds -lt $sec) { Start-Sleep 1 } }
function Removed { -not (Test-Path $dir) -and -not (Test-Path $lnk) -and -not (Test-Path $ukey) -and -not (Test-Path "HKCU:\Software\Classes\HeliumWorkspacesHTML") -and $null -eq (Reg "HKCU:\Software\RegisteredApplications" "Helium Workspaces") }

if (-not $GradeOnly) {
    $setup = @(Get-ChildItem "$ws\dist\workspaces-for-helium_*_x64-setup.exe" | Sort-Object LastWriteTime) | Select-Object -Last 1
    if (-not $setup) { Fail "no installer in $ws\dist -- run local\package-installer.py first" }
    if (Test-Path -LiteralPath $dir) { Fail "Helium Workspaces is already installed ($dir) -- uninstall it first" }
    # This check deletes the profile at step 7: it must be the one step 2 makes, never an older one.
    if (Test-Path -LiteralPath $data) { Fail "$data already exists -- it may hold real tabs; this check will not run over it" }
    $F = @{ answers = @{}; comment = ""; setup = $setup.Name; lb_before = (Hash $offLB); lb_name = (LBName $offLB) }
    Save
    Step @"

 1. The installer opens now. Read its first page, click I Agree, then Finish at the end.
                                   EXPECT: the first page is the warning ('unofficial personal add-on');
                                           the last page says: open it from the Start menu.
"@
    Start-Process -FilePath $setup.FullName -Wait
    $sh = if (Test-Path $lnk) { (New-Object -ComObject WScript.Shell).CreateShortcut($lnk) } else { $null }
    $F.installed = (Test-Path $exe) -and (Get-Item $exe).VersionInfo.ProductVersion -eq (Get-Item "$ws\helium-windows\build\src\out\Default\chrome.exe").VersionInfo.ProductVersion
    $F.shortcut  = $sh -and $sh.TargetPath -eq $exe -and $sh.Arguments -eq "--user-data-dir=`"$prof`""
    $F.handler   = (Reg "HKCU:\Software\Classes\HeliumWorkspacesHTML\shell\open\command" "(default)") -eq "`"$exe`" --user-data-dir=`"$prof`" --single-argument %1"
    $F.entry     = (Reg $ukey DisplayName) -eq "Helium Workspaces"
    $F.openwith  = @([OpenWith]::List(".html") | Where-Object { $_.EndsWith("| $exe") }) -join "; "
    Ask "s1"
    Step @"

 2. Start menu > type Helium Workspaces > open it.
                                   EXPECT: a new window: the tab list on the LEFT, and at its bottom the
                                           workspace rail (Home). It is a fresh profile: no tabs of yours.
"@
    Ask "s2"
    Step @"

 3. Start menu > type Helium Workspaces > RIGHT-click it > Pin to taskbar.
    Close the Helium Workspaces window (its X), then click the new taskbar icon.
                                   EXPECT: Helium Workspaces opens again, with its rail (not official Helium).
"@
    Ask "s3"
    Set-Content -LiteralPath $html -Value "<!doctype html><title>Phase 2 test page</title><h1>Phase 2 test page</h1>" -Encoding utf8
    Start-Process explorer.exe "/select,`"$html`""
    Step @"

 4. An Explorer window shows phase2-test.html selected. RIGHT-click it > Open with > Helium Workspaces
    (not in the list? 'Choose another app', then Helium Workspaces, and 'Just once').
                                   EXPECT: the list says 'Helium Workspaces' (official Helium stays 'Helium');
                                           'Phase 2 test page' opens as a tab in Helium Workspaces.
"@
    Ask "s4"
    Step @"

 5. Windows Settings > Apps > Default apps. Look for Helium Workspaces in the list. Do NOT click it.
                                   EXPECT: it is listed.
"@
    Ask "s5"
    Step @"

 6. Close Helium Workspaces (its X). Nothing to press here: this window waits for it to close.
"@
    while ((Pids).Count -gt 0) { Start-Sleep -Milliseconds 500 }
    Start-Sleep 3
    $F.opened_by   = LBName "$prof\Last Browser"
    $F.layout      = (Json "Preferences").helium.browser.layout
    $F.restore     = (Json "Secure Preferences").session.restore_on_startup
    $F.page_kept   = SessionHas "phase2-test.html"
    Save
    Step @"
    Closed. The UNINSTALLER opens now: leave 'Also delete my Helium Workspaces data' EMPTY,
    click Uninstall, then Close.
                                   EXPECT: the box is there, empty.
"@
    Start-Process -FilePath "$dir\uninstall.exe"
    WaitGone $dir
    Start-Sleep 2
    $F.removed1   = Removed
    $F.data_kept  = Test-Path "$prof\Default\Preferences"
    Ask "s6"
    Write-Host "Installing it again, silently, for the last step..." -ForegroundColor Cyan
    Start-Process -FilePath $setup.FullName -ArgumentList "/S" -Wait
    $F.reinstalled = Test-Path $exe
    Step @"

 7. The UNINSTALLER opens again: this time TICK 'Also delete my Helium Workspaces data',
    click Uninstall, then Close.
"@
    Start-Process -FilePath "$dir\uninstall.exe"
    WaitGone $dir
    WaitGone $data 60  # seconds: the box unticked leaves it for good
    $F.removed2   = Removed
    $F.data_gone  = -not (Test-Path $data)
    $F.lb_after   = Hash $offLB
    Ask "s7"
    Remove-Item -LiteralPath $html -EA SilentlyContinue
    Step @"

 8. RIGHT-click the Helium Workspaces taskbar icon > Unpin from taskbar (it points at nothing now).
"@
    $F.comment = "$(Read-Host "Anything that looked wrong, odd or missing? (Enter for nothing)")".Trim()
    Save
}

# ---- grading (also -GradeOnly) -----------------------------------------------------------------
if (-not (Test-Path -LiteralPath $answers)) { Fail "no $answers -- run without -GradeOnly first" }
$F = [IO.File]::ReadAllText($answers, [Text.Encoding]::UTF8) | ConvertFrom-Json
$script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name" -ForegroundColor Green } else { Write-Host "FAIL  $name" -ForegroundColor Red; $script:failed++ } }
Write-Host ""
Write-Host "Installer: $($F.setup)"
foreach ($k in $questions.Keys) { Verdict "$($questions[$k] -replace ' \(y/n\)$', '') -- you said $($F.answers.$k)" ($F.answers.$k -eq 'y') }
Verdict "step 1: installed, the version built" $F.installed
Verdict "step 1: the Start-menu shortcut opens it with its own profile (--user-data-dir)" $F.shortcut
Verdict "step 1: the Open with / Default apps command carries the profile and --single-argument" $F.handler
Verdict "step 1: Apps & features lists it" $F.entry
Verdict "step 1: Open with shows it as 'Helium Workspaces' ($($F.openwith))" ($F.openwith -eq "Helium Workspaces | $exe")
Verdict "step 2: the new profile was opened by the installed browser ($($F.opened_by))" ($F.opened_by -eq $exe)
Verdict "step 2: the new profile is vertical (layout $($F.layout), 2 = vertical)" ($F.layout -eq 2)
Verdict "step 2: 'Continue where you left off' set (restore_on_startup $($F.restore), 1 = continue)" ($F.restore -eq 1)
Verdict "step 4: the session holds the page opened with Open with" $F.page_kept
Verdict "step 6: program, shortcut and registry entries removed" $F.removed1
Verdict "step 6: the data KEPT (box empty)" $F.data_kept
Verdict "step 7: installed again" $F.reinstalled
Verdict "step 7: program, shortcut and registry entries removed" $F.removed2
Verdict "step 7: the data DELETED (box ticked)" $F.data_gone
Verdict "official Helium's profile never opened by Helium Workspaces (Last Browser: $($F.lb_name))" ($F.lb_before -and $F.lb_before -eq $F.lb_after)
Write-Host "comment: $(if ($F.comment) { $F.comment } else { '(none)' })"
Write-Host ""
if ($script:failed) { Write-Host "$($script:failed) FAIL(s)." -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS." -ForegroundColor Green
