# Resumes a Chromium compile. Safe to run repeatedly - siso is incremental and
# picks up exactly where it stopped, so Ctrl+C costs nothing (press it ONCE and
# let siso save its state; do not close the window).
#
# Since R4 (helium-windows 0.17.2.1) the build runs siso, not ninja: the same
# build.ninja files, the same targets, run by third_party\siso\cipd\siso.exe,
# which build.py installs from CIPD. This is exactly what autoninja runs here
# ("siso ninja --offline"): no login, no remote execution.
#
# Prerequisites already satisfied (do NOT re-run dev-build.ps1, which would reset
# the source tree and wipe the applied patches):
#   - patches applied               (build/src/.pc/applied-patches)
#   - gn gen done                   (build/src/out/<OutDir>/build.ninja)
#
# Run this in an ordinary PowerShell window. It survives closing Claude Code.
#
#   .\resume-build.ps1                                   # the browser
#   .\resume-build.ps1 -Targets workspaces_unittests      # the fork's own tests
#   .\resume-build.ps1 -Targets unit_tests -KeepGoing
#   .\resume-build.ps1 -OutDir Dcheck -Targets chrome     # the DCHECK build
#
# -KeepGoing passes "-k 0": keep building past a failing step instead of
# stopping at the first one. Use it to survey how much is broken (E5a); siso
# still exits non-zero, and still stops if everything left depends on a failure.
#
# -LocalJobs N passes "-local_jobs N": at most N compile steps at once (siso's
# default is one per CPU, 16 here) -- for a build while the owner uses the PC.
# siso refuses -j. The link is one process either way.
#
# Reading the log: a failed step starts with "FAILED: ", and the last line is
# "Build Succeeded: N steps" or "Build Failure: ..." (siso prints that summary
# on stderr, hence the 2>&1 below). "ninja: build stopped" no longer appears.
#
# -OutDir picks the output directory under build/src/out. "Default" is the
# normal build. "Dcheck" is the same source with dcheck_always_on=true and
# symbol_level=1 (LOCAL.md 5.8) - a separate directory so the two never share
# state and neither invalidates the other's objects.
#
# NOTE: close the fork browser first. Windows locks chrome.dll while it runs, so
# the link step fails with a permission error if an instance is still open.

param(
    [string[]]$Targets = @("chrome", "chromedriver"),
    [string]$OutDir = "Default",
    [switch]$KeepGoing,
    [int]$LocalJobs = 0
)

$src = "<local-path>\Helium-workspace\helium-windows\build\src"

if (-not (Test-Path "$src\.pc\applied-patches")) {
    Write-Host "ABORT: patches are not applied. See LOCAL.md section 5." -ForegroundColor Red; exit 1
}
if (-not (Test-Path "$src\out\$OutDir\build.ninja")) {
    Write-Host "ABORT: no build.ninja in out\$OutDir - run gn gen for it first." -ForegroundColor Red
    Write-Host "       See LOCAL.md section 5.5 (Default) or 5.8 (Dcheck)." -ForegroundColor Red
    exit 1
}
Write-Host "patches applied: $((Get-Content "$src\.pc\applied-patches").Count)" -ForegroundColor Green

$vcvars = "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
# Put the VS Installer dir on PATH so vcvars can find vswhere.exe (harmless probe
# warning otherwise, but keeps the log clean).
$env:PATH = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer;$env:PATH"

$flags = if ($KeepGoing) { "-k 0 " } else { "" }
$flags += if ($LocalJobs -gt 0) { "-local_jobs $LocalJobs " } else { "" }
Write-Host "Starting siso in out\$OutDir on: $($Targets -join ' ')  (Ctrl+C once is safe - rerun to resume)" -ForegroundColor Yellow
cmd /c "call `"$vcvars`" >nul && set DEPOT_TOOLS_WIN_TOOLCHAIN=0 && cd /d `"$src`" && third_party\siso\cipd\siso.exe ninja --offline -C out\$OutDir $flags$($Targets -join ' ') 2>&1"
exit $LASTEXITCODE
