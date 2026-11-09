param([string]$From = "")
# Chunk D (LOCAL.md 127): the weekly update check and the installer script, after the negative review's route D.
# No browser starts and no setup runs (the installer freeze, LOCAL.md 121). The update check runs as a scratch COPY
# with its clone, repo and log lines pointed at scratch: bare --shared clones of helium-windows and helium whose
# remotes lead nowhere (offline), so the owner's repos, their refs and update-checks.log are never touched. Chrome's
# release blog is still read over the network.
#   pwsh -NoProfile -File local\check-d.ps1 [-From <git rev>]   (-From: test that commit's two scripts, e.g. a red run)
#   U1  the clone moved: a FAILED record line, exit 1            (data-files F6)
#   U2  git missing: a FAILED record line, exit 1                (data-files F6)
#   U3  offline: the record line says "fetch FAILED"             (data-files F7)
#   U4  the log locked: "Could NOT record", never "Recorded"     (data-files F6)
#   U5  -SelfTest passes, with Chrome ahead by nothing = "0 update(s), 0 critical"   (data-files F8)
#   I1-I5  the installer script holds installer F2 F3 F6 F7 F9; I6 it compiles (makensis, into scratch, never run)
$repo    = Split-Path -Parent $PSScriptRoot
$ws      = "<local-path>\Helium-workspace"
$scratch = "$env:TEMP\check-d-$(Get-Date -Format yyyyMMdd-HHmmss)"
$script:passed = 0; $script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }
# A file of this repo, from the working tree or from -From's commit.
function Source([string]$rel) {
    if (-not $From) { return [IO.File]::ReadAllText("$repo\$rel") }
    $enc = [Console]::OutputEncoding   # git's bytes are UTF-8; this console's code page is not
    try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); (git -C $repo show "${From}:$rel") -join "`n" }
    finally { [Console]::OutputEncoding = $enc }
}

# ---- the update check -------------------------------------------------------------------------------------------
# Each copy must lose all three real paths, or it would write the owner's log: checked before anything is made.
$text = Source "local/check-updates.ps1"
foreach ($v in @("hw", "repo", "record")) {
    $n = [regex]::Matches($text, "(?m)^\`$$v\s+=").Count
    if ($n -ne 1) { throw "check-updates.ps1 has $n `$$v lines, not 1" }
}
$null = New-Item -ItemType Directory $scratch
git clone -q --bare --shared "$ws\helium-windows" "$scratch\hw.git"
git -C "$scratch\hw.git" remote set-url origin "$scratch\nowhere"
git clone -q --bare --shared "$ws\helium" "$scratch\helium.git"   # no "upstream" remote: its fetch fails too
# One copy per case: its clone, its log.
function Copy-Check([string]$name, [string]$hw) {
    # `$`$ is a literal $ in a -replace replacement.
    $t = $text -replace '(?m)^\$hw\s+=.*$', "`$`$hw = '$hw'" -replace '(?m)^\$repo\s+=.*$', "`$`$repo = '$scratch\helium.git'" -replace '(?m)^\$record\s+=.*$', "`$`$record = '$scratch\$name.log'"
    [IO.File]::WriteAllText("$scratch\$name.ps1", $t, [Text.UTF8Encoding]::new($true))
    "$scratch\$name.ps1"
}
$pwsh = (Get-Process -Id $PID).Path
function Run([string]$script, [string[]]$extra = @()) {
    $o = @(& $pwsh -NoProfile -File $script @extra 2>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ Out = $o -join "`n"; Code = $LASTEXITCODE }
}
function Record([string]$name) { if (Test-Path -LiteralPath "$scratch\$name.log") { Get-Content -LiteralPath "$scratch\$name.log" } }

$r = Run (Copy-Check "u1" "$scratch\moved")
$rec = @(Record "u1")
Verdict "U1 the clone moved: one FAILED record line, exit 1 (exit $($r.Code); record: $($rec -join ' / '))" ($r.Code -eq 1 -and $rec.Count -eq 1 -and $rec[0] -match 'FAILED')

$gitDirs = @($env:PATH -split ';' | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_ "git.exe")) })
$path = $env:PATH
$env:PATH = (@($env:PATH -split ';' | Where-Object { $_ -notin $gitDirs }) -join ';')   # this child only; put back at once
try { $r = Run (Copy-Check "u2" "$scratch\hw.git") } finally { $env:PATH = $path }
$rec = @(Record "u2")
Verdict "U2 git missing ($($gitDirs.Count) PATH folder(s) left out): one FAILED record line, exit 1 (exit $($r.Code); record: $($rec -join ' / '))" ($gitDirs.Count -gt 0 -and $r.Code -eq 1 -and $rec.Count -eq 1 -and $rec[0] -match 'FAILED')

$r = Run (Copy-Check "u3" "$scratch\hw.git")
$rec = @(Record "u3")
Verdict "U3 offline: the record line says 'fetch FAILED' (exit $($r.Code); record: $($rec -join ' / '))" ($r.Code -eq 0 -and $rec.Count -eq 1 -and $rec[0] -match '\| (OK|DEFER|REBASE|MAJOR) \| fetch FAILED$')

$u4 = Copy-Check "u4" "$scratch\hw.git"
[IO.File]::WriteAllText("$scratch\u4.log", "")
$lock = [IO.File]::Open("$scratch\u4.log", "Open", "ReadWrite", "None")
try { $r = Run $u4 } finally { $lock.Dispose() }
Verdict "U4 the log locked: 'Could NOT record', no 'Recorded in', exit 1 (exit $($r.Code))" ($r.Code -eq 1 -and $r.Out -match 'Could NOT record' -and $r.Out -notmatch 'Recorded in')

$r = Run (Copy-Check "u5" "$scratch\hw.git") @("-SelfTest")
Verdict "U5 -SelfTest passes, Chrome ahead by nothing reads '0 update(s), 0 critical' (exit $($r.Code))" ($r.Code -eq 0 -and $r.Out -match 'SELFTEST PASS' -and $r.Out -match '0 update\(s\), 0 critical')

# ---- the installer script (read, then compiled; never run) ------------------------------------------------------
$nsi = Source "local/installer/helium-workspaces.nsi"
$py  = Source "local/package-installer.py"
function Body([string]$re) { $m = [regex]::Match($nsi, "(?ms)$re(.*?)^(SectionEnd|FunctionEnd)"); if ($m.Success) { $m.Groups[1].Value } else { "" } }
$install = Body '^Section\s*$'
$unProg  = Body '^Section "un\.\$\{NAME\} \(the program\)"'
$unData  = Body '^Section /o "un\.Also delete'
$onInit  = Body '^Function \.onInit'
function Before([string]$body, [string]$a, [string]$b) { $i = $body.IndexOf($a); $j = $body.IndexOf($b); $i -ge 0 -and $j -ge 0 -and $i -lt $j }
Verdict "I1 (F2) both Sections ask whether the browser is open before they delete" ((Before $install '!insertmacro RefuseWhileRunning' 'RMDir /r') -and (Before $unProg '!insertmacro RefuseWhileRunning' 'Delete '))
Verdict "I2 (F3) .onInit checks the free space; the uninstaller is written before the files" ($onInit -match '\$\{DriveSpace\}' -and (Before $install 'WriteUninstaller' '!include "${FILES_NSH}"'))
Verdict "I3 (F6) the taskbar-id step has a timeout" ($install -match 'nsExec::ExecToLog /TIMEOUT=\d+')
Verdict "I4 (F7) deleting the data checks what is left" (Before $unData 'RMDir /r "${DATA}"' '${FileExists} "${DATA}')
Verdict "I5 (F9) the licence page names the Helium and Chromium, and package-installer.py passes them" ($nsi -match 'MUI_LICENSEPAGE_TEXT_TOP "[^"]*\$\{BUILT_FOR\}' -and $py -match '-DBUILT_FOR=Helium \{helium\} / Chromium \{chromium\}')

$here = "$scratch\installer"
$null = New-Item -ItemType Directory $here
foreach ($f in @("disclaimer.txt", "initial_preferences", "set-taskbar-id.ps1")) { [IO.File]::WriteAllText("$here\$f", (Source "local/installer/$f")) }
[IO.File]::WriteAllText("$here\helium-workspaces.nsi", $nsi)
[IO.File]::WriteAllText("$here\dummy.txt", "check-d")
[IO.File]::WriteAllText("$here\files.nsh", "SetOutPath `"`$INSTDIR`"`r`nFile `"$here\dummy.txt`"`r`n")
$makensis = "C:\Program Files (x86)\NSIS\makensis.exe"
$o = @(& $makensis -V2 "-DVERSION=0.0.0.0" "-DFILES_NSH=$here\files.nsh" "-DHERE=$here" "-DICON_FILE=C:\Program Files (x86)\NSIS\Contrib\Graphics\Icons\modern-install.ico" "-DSIZE_KB=1" "-DBUILT_FOR=Helium 0.0.0.0 / Chromium 0.0.0.0" "-DOUTPUT_FILE=$here\never-run.exe" "$here\helium-workspaces.nsi" 2>&1 | ForEach-Object { "$_" })
$built = Test-Path -LiteralPath "$here\never-run.exe"
Verdict "I6 makensis compiles it (exit $LASTEXITCODE; $(@($o | Where-Object { $_ -match 'warning' }).Count) warning line(s)$(if ($LASTEXITCODE) { ': ' + ($o -join ' / ') }))" ($LASTEXITCODE -eq 0 -and $built)

Remove-Item -LiteralPath $scratch -Recurse -Force -EA SilentlyContinue   # the never-run setup goes with it
Write-Host ""
Write-Host "check-d: $script:passed passed, $script:failed failed$(if ($From) { " (from $From)" })"
exit ([int]($script:failed -gt 0))
