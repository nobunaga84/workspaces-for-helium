# After a rebase: repair args.gn once build.py's own gn gen has run (LOCAL.md 5.5 for Default, 5.8 for
# Dcheck), then gn gen both with the CIPD gn and --script-executable. Run with build.py STOPPED.
# The two override blocks live beside this script in local/args/.
$src = "<local-path>\Helium-workspace\helium-windows\build\src"
$blocks = "$PSScriptRoot\args"
if (-not (Test-Path "$blocks\dev-block.gn") -or -not (Test-Path "$blocks\dcheck-block.gn")) { Write-Host "ABORT: override blocks not found in $blocks" -ForegroundColor Red; exit 1 }
$vcvars = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"

$def = Get-Content "$src\out\Default\args.gn" -Raw
if ($def -notmatch 'use_siso=true') { Write-Host "ABORT: out\Default\args.gn is not build.py's (no use_siso=true)" -ForegroundColor Red; exit 1 }
if ($def -match 'dev overrides') { Write-Host "ABORT: dev block already appended" -ForegroundColor Red; exit 1 }
Add-Content "$src\out\Default\args.gn" (Get-Content "$blocks\dev-block.gn" -Raw) -NoNewline
New-Item -ItemType Directory -Force "$src\out\Dcheck" | Out-Null
Copy-Item "$src\out\Default\args.gn" "$src\out\Dcheck\args.gn"
Add-Content "$src\out\Dcheck\args.gn" (Get-Content "$blocks\dcheck-block.gn" -Raw) -NoNewline

$env:PATH = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer;$env:PATH"
foreach ($d in @("Default", "Dcheck")) {
  cmd /c "call `"$vcvars`" >nul && set DEPOT_TOOLS_WIN_TOOLCHAIN=0 && cd /d `"$src`" && buildtools\win\gn.exe gen out\$d --fail-on-unused-args --script-executable=C:/Python314/python.exe 2>&1"
  if ($LASTEXITCODE -ne 0) { Write-Host "FAIL: gn gen out\$d exit $LASTEXITCODE" -ForegroundColor Red; exit 1 }
  $stub = @(Select-String -Path "$src\out\$d\*.ninja" -SimpleMatch "WindowsApps" -List).Count
  Write-Host "out\$d : gn gen ok, WindowsApps references in *.ninja = $stub"
  if ($stub -ne 0) { Write-Host "FAIL: python3 store stub leaked into out\$d (5.5)" -ForegroundColor Red; exit 1 }
}
Write-Host "last lines of each args.gn:"; foreach ($d in @("Default", "Dcheck")) { "--- $d"; Get-Content "$src\out\$d\args.gn" | Select-String -Pattern '^(is_component_build|dcheck_always_on|symbol_level|use_siso|enable_precompiled_headers|chrome_pgo_phase)=' | ForEach-Object { "  $($_.Line)" } }
