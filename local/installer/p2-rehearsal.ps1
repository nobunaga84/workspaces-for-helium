$ws     = "<local-path>\Helium-workspace"
$setup  = (Get-ChildItem "$ws\dist\workspaces-for-helium_*_x64-setup.exe" | Sort-Object LastWriteTime | Select-Object -Last 1).FullName
$dir    = "$env:LOCALAPPDATA\Programs\Helium Workspaces"
$data   = "$env:LOCALAPPDATA\Helium Workspaces"
$prof   = "$data\User Data"
$exe    = "$dir\chrome.exe"
$lnk    = [Environment]::GetFolderPath('Programs') + "\Workspaces for Helium.lnk"
$offLB  = "$env:LOCALAPPDATA\imput\Helium\User Data\Last Browser"
$html   = "$ws\dist\phase2-test.html"
$script:failed = 0
function V($name, $ok) { if ($ok) { Write-Host "PASS  $name" } else { Write-Host "FAIL  $name"; $script:failed++ } }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function WaitClosed { $t = Get-Date; while ((Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }; Start-Sleep 3 }
function CloseIt { foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }; WaitClosed }
function WaitOpen { $t = Get-Date; while (-not (Pids).Count -and ((Get-Date) - $t).TotalSeconds -lt 30) { Start-Sleep 1 }; Start-Sleep 15 }
function Prefs { [IO.File]::ReadAllText("$prof\Default\Preferences") | ConvertFrom-Json }
# Tracked prefs (restore_on_startup) live in Secure Preferences on Windows.
function Restore { foreach ($f in "Secure Preferences", "Preferences") { $v = ([IO.File]::ReadAllText("$prof\Default\$f") | ConvertFrom-Json).session.restore_on_startup; if ($null -ne $v) { return "$v in $f" } }; "(unset)" }
function Run($file, $a) { (Start-Process $file -ArgumentList $a -Wait -PassThru).ExitCode }
function Reg($path, $name) { try { (Get-ItemProperty -LiteralPath $path -EA Stop).$name } catch { $null } }
function Markers($log) { @(Get-Content -LiteralPath $log | Select-String -CaseSensitive 'Check failed|FATAL|ReentrancyCheck|dangling|NOTREACHED').Count }
function LBName($p) { [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($p)).TrimEnd([char]0) }

Write-Host "--- 0 preconditions"
V "no install folder yet" (-not (Test-Path $dir))
V "no profile yet" (-not (Test-Path $data))
$lb0 = (Get-FileHash $offLB).Hash
Write-Host "official Last Browser: $(LBName $offLB)"

Write-Host "--- 1 silent install of $setup"
V "setup /S exit 0" ((Run $setup "/S") -eq 0)
$built = (Get-Item "$ws\helium-windows\build\src\out\Default\chrome.exe").VersionInfo.ProductVersion
V "chrome.exe installed, version $built" ((Test-Path $exe) -and (Get-Item $exe).VersionInfo.ProductVersion -eq $built)
$n = @(Get-ChildItem $dir -Recurse -File).Count
# What the packager put in (dist\files.nsh, one File line each): Helium's FILES.cfg changes with Helium
# (76 files at 0.17.2, 74 at 0.18.2), so the count is read, never written down.
$packed = @(Select-String -LiteralPath "$ws\dist\files.nsh" -Pattern '^\s*File ').Count
V "$($packed + 2) files ($packed packaged + initial_preferences + uninstall.exe): $n" ($packed -gt 0 -and $n -eq $packed + 2)
V "initial_preferences = the repo's" ((Get-FileHash "$dir\initial_preferences").Hash -eq (Get-FileHash "$ws\helium\local\installer\initial_preferences").Hash)
$sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
V "shortcut -> $($sh.TargetPath) $($sh.Arguments)" ($sh.TargetPath -eq $exe -and $sh.Arguments -eq "--user-data-dir=`"$prof`"")
$u = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\HeliumWorkspaces"
V "Apps & features: $(Reg $u DisplayName) $(Reg $u DisplayVersion)" ((Reg $u DisplayName) -eq "Workspaces for Helium" -and (Reg $u UninstallString) -eq "`"$dir\uninstall.exe`"")
$cmd = Reg "HKCU:\Software\Classes\HeliumWorkspacesHTML\shell\open\command" "(default)"
V "handler: $cmd" ($cmd -eq "`"$exe`" --user-data-dir=`"$prof`" --single-argument %1")
V "Default apps registration" ((Reg "HKCU:\Software\RegisteredApplications" "Workspaces for Helium") -eq "Software\Clients\StartMenuInternet\HeliumWorkspaces\Capabilities" -and (Reg "HKCU:\Software\Clients\StartMenuInternet\HeliumWorkspaces\Capabilities\URLAssociations" "https") -eq "HeliumWorkspacesHTML")
V "Open with .html" ($null -ne (Reg "HKCU:\Software\Classes\.html\OpenWithProgids" "HeliumWorkspacesHTML"))
$ow = @(pwsh -NoProfile -File "$PSScriptRoot\p2-openwith.ps1")
V "Open with shows ours as Workspaces for Helium: $($ow -join '; ')" ($ow -contains "Workspaces for Helium | $exe")

Write-Host "--- 2 'Open with': the handler's command (+ logging) on a local page -- a NEW profile's first run"
Set-Content -LiteralPath $html -Value "<!doctype html><title>Phase 2 test page</title><h1>Phase 2 test page</h1>" -Encoding utf8
$log1 = "$ws\p2-run1.log"; Remove-Item $log1 -EA SilentlyContinue
Start-Process $exe -ArgumentList @("--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log1`"", "--v=0", "--single-argument", "`"$html`"") | Out-Null
WaitOpen
V "a browser runs on $prof" ((Pids).Count -ge 1)
CloseIt
V "closed" ((Pids).Count -eq 0)
$p = Prefs
V "first run applied initial_preferences: layout $($p.helium.browser.layout) (2 = vertical)" ($p.helium.browser.layout -eq 2)
$r = Restore; V "restore_on_startup $r (1 = continue)" ($r -like "1 in *")
V "the new profile's Last Browser is the installed exe: $(LBName "$prof\Last Browser")" ((LBName "$prof\Last Browser") -eq $exe)
$hit = @(Get-ChildItem "$prof\Default\Sessions" -File | Where-Object { [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains("phase2-test.html") }).Count
V "the session holds the opened page ($hit file(s))" ($hit -ge 1)
V "run 1 log: 0 crash markers" ((Markers $log1) -eq 0)

Write-Host "--- 3 the shortcut's command (+ logging), a second run; refusals while it runs"
$log2 = "$ws\p2-run2.log"; Remove-Item $log2 -EA SilentlyContinue
Start-Process $exe -ArgumentList @($sh.Arguments, "--enable-logging", "--log-file=`"$log2`"", "--v=0") | Out-Null
WaitOpen
V "running" ((Pids).Count -ge 1)
$dll0 = (Get-Item "$dir\chrome.dll").LastWriteTimeUtc
V "setup /S refuses while it runs (exit 2)" ((Run $setup "/S") -eq 2)
V "uninstall /S refuses while it runs (exit 2)" ((Run "$dir\uninstall.exe" @("/S", "_?=$dir")) -eq 2)
V "chrome.dll untouched" ((Get-Item "$dir\chrome.dll").LastWriteTimeUtc -eq $dll0)
CloseIt
$p = Prefs
$r = Restore; V "after run 2: restore_on_startup still $r (the signed value was accepted)" ($r -like "1 in *")
V "no tracked-pref reset recorded" (-not "$($p.prefs.tracked_preferences_reset)")
V "the page came back at restart (restore works): session still holds it" (@(Get-ChildItem "$prof\Default\Sessions" -File | Where-Object { $_.LastWriteTimeUtc -gt $dll0 -and [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($_.FullName)).Contains("phase2-test.html") }).Count -ge 1)
V "run 2 log: 0 crash markers" ((Markers $log2) -eq 0)

Write-Host "--- 4 reinstall over it with /D= elsewhere; an uninstaller copy run from elsewhere"
$prefT = (Get-Item "$prof\Default\Preferences").LastWriteTimeUtc
V "setup /S /D=... exit 0" ((Run $setup @("/S", "/D=$ws\dist\wrongdir")) -eq 0)
V "/D= ignored: nothing at dist\wrongdir, the install in place" (-not (Test-Path "$ws\dist\wrongdir") -and (Test-Path $exe))
V "the profile untouched by the reinstall" ((Get-Item "$prof\Default\Preferences").LastWriteTimeUtc -eq $prefT)
New-Item -ItemType Directory "$ws\dist\uncopy" -Force | Out-Null
Copy-Item "$dir\uninstall.exe" "$ws\dist\uncopy\"
V "an uninstaller copy elsewhere refuses (exit 2)" ((Run "$ws\dist\uncopy\uninstall.exe" @("/S", "_?=$ws\dist\uncopy")) -eq 2)
V "and deleted nothing there" (Test-Path "$ws\dist\uncopy\uninstall.exe")
Remove-Item "$ws\dist\uncopy" -Recurse

Write-Host "--- 5 silent uninstall (the data box stays unticked)"
Run "$dir\uninstall.exe" "/S" | Out-Null
$t = Get-Date; while ((Test-Path $dir) -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
V "program folder gone" (-not (Test-Path $dir))
V "shortcut gone" (-not (Test-Path $lnk))
V "Apps & features entry gone" (-not (Test-Path $u))
V "handler and Default apps entries gone" (-not (Test-Path "HKCU:\Software\Classes\HeliumWorkspacesHTML") -and -not (Test-Path "HKCU:\Software\Clients\StartMenuInternet\HeliumWorkspaces") -and $null -eq (Reg "HKCU:\Software\RegisteredApplications" "Workspaces for Helium") -and $null -eq (Reg "HKCU:\Software\Classes\.html\OpenWithProgids" "HeliumWorkspacesHTML"))
V "the profile KEPT" (Test-Path "$prof\Default\Preferences")

Write-Host "--- 6 official Helium"
V "official Last Browser unchanged: $(LBName $offLB)" ((Get-FileHash $offLB).Hash -eq $lb0)

Write-Host "--- 7 /DELETEDATA while another browser holds the profile: data KEPT"
V "reinstall /S exit 0" ((Run $setup "/S") -eq 0)
$tree = "$ws\helium-windows\build\src\out\Default\chrome.exe"
Start-Process $tree -ArgumentList @("--user-data-dir=`"$prof`"", "--no-first-run") | Out-Null
WaitOpen
V "the build-tree browser holds the profile (lockfile)" (Test-Path "$prof\lockfile")
Run "$dir\uninstall.exe" @("/S", "/DELETEDATA") | Out-Null
$t = Get-Date; while ((Test-Path $dir) -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }; Start-Sleep 3
V "program folder gone" (-not (Test-Path $dir))
V "the data KEPT while in use" (Test-Path "$prof\Default\Preferences")
CloseIt
Write-Host "--- 8 /DELETEDATA with the profile free: data DELETED"
V "reinstall /S exit 0" ((Run $setup "/S") -eq 0)
Run "$dir\uninstall.exe" @("/S", "/DELETEDATA") | Out-Null
$t = Get-Date; while (((Test-Path $dir) -or (Test-Path $data)) -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
V "program folder gone" (-not (Test-Path $dir))
V "the data DELETED ($data)" (-not (Test-Path $data))
V "everything else of ours gone" (-not (Test-Path $lnk) -and -not (Test-Path $u))
V "official Last Browser still unchanged" ((Get-FileHash $offLB).Hash -eq $lb0)
Write-Host "--- 9 a virus scan's moment: chrome.dll held without write sharing for 2 s -- the uninstaller waits, it does not refuse"
V "reinstall /S exit 0" ((Run $setup "/S") -eq 0)
Start-Sleep 5
$dll = "$dir\chrome.dll"
$hold = Start-Process pwsh -ArgumentList @("-NoProfile", "-Command", "`$f = [IO.File]::Open('$dll', 'Open', 'Read', 'Read'); Start-Sleep 2; `$f.Close()") -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 700
$blocked = try { $f = [IO.File]::Open($dll, 'Open', 'ReadWrite', 'ReadWrite'); $f.Close(); $false } catch { $true }
V "the hold blocks a write-open (the test is live)" $blocked
V "uninstall /S /DELETEDATA (in place) exits 0, not 2" ((Run "$dir\uninstall.exe" @("/S", "/DELETEDATA", "_?=$dir")) -eq 0)
$hold.WaitForExit()
Run "$dir\uninstall.exe" "/S" | Out-Null
$t = Get-Date; while ((Test-Path $dir) -and ((Get-Date) - $t).TotalSeconds -lt 60) { Start-Sleep 1 }
V "program folder gone" (-not (Test-Path $dir))
Remove-Item $html
Write-Host ""
if ($script:failed) { Write-Host "$($script:failed) FAIL(s)"; exit 1 } else { Write-Host "ALL PASS" }
