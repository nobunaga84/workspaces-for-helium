# Runs helium-windows build.py --dev, holding the quilt prompt open until released.
#
# Background: build.py prints "Apply patches using quilt, then press Enter" and
# calls input(). Anything already sitting in stdin satisfies it instantly and the
# build proceeds WITHOUT patches. Before R4 that failed fast at gn bootstrap;
# since helium-windows 0.17.2.1 gn is a prebuilt CIPD binary, so an unpatched
# release now runs gn gen and then a multi-hour build of an unpatched tree.
#
# Hold mechanism (verified): stdin is fed by a script block that emits NOTHING
# until a release flag file appears, then emits exactly one empty line.
# continue-build.ps1 creates that flag.

$ErrorActionPreference = "Stop"
$root    = "<local-path>\Helium-workspace\helium-windows"
$release = "<local-path>\Helium-workspace\.build-release"

try { $Host.UI.RawUI.FlushInputBuffer() } catch {}

# ---- clear stale extraction targets (MUST run before every build) ----
# Both sit under gclient-managed checkouts (gitlinks), so clone.py's
# "git clean -ffdx" cannot reach them, and both are pure download artifacts
# (0 tracked files) re-created from build\download_cache with no network access.
#  - microsoft_webauthn/src is a 7-Zip target: left populated, strip_leading_dirs
#    fails with FileExistsError: [WinError 183].
#  - dawn's golang dir is a CIPD root since R4 (it was a 7-Zip target before);
#    cleared so "cipd ensure" installs into an empty directory.
foreach ($d in @(
  "$root\build\src\third_party\dawn\tools\golang\windows-amd64",
  "$root\build\src\third_party\microsoft_webauthn\src"
)) {
  if (Test-Path $d) {
    Remove-Item -Recurse -Force $d
    Write-Host "cleared stale extraction target: $d" -ForegroundColor DarkGray
  }
}

# build.py (since R4) needs clang-format on PATH AFTER the quilt prompt, and
# symlinks buildtools\win-format\clang-format.exe to it. This copy is Chromium's
# own binary (sha256 matches the .52 DEPS pin), kept OUTSIDE build\ because
# clone.py's git clean deletes the one in the tree. Never move it: the symlink
# build.py makes points at it.
$env:PATH = "<local-path>\Helium-workspace\tools\clang-format;$env:PATH"
if (-not (Get-Command clang-format -ErrorAction SilentlyContinue)) {
  Write-Host "ABORT: clang-format not on PATH (build.py needs it after the quilt prompt)." -ForegroundColor Red
  exit 1
}

Remove-Item $release -Force -ErrorAction SilentlyContinue
Write-Host "release flag cleared: $release" -ForegroundColor DarkGray

$env:GIT_CONFIG_COUNT   = 2
$env:GIT_CONFIG_KEY_0   = "url.<local-path>/Helium-workspace/gitcache/github.com/.insteadOf"
$env:GIT_CONFIG_VALUE_0 = "https://github.com/"
$env:GIT_CONFIG_KEY_1   = "protocol.file.allow"
$env:GIT_CONFIG_VALUE_1 = "always"

Set-Location $root
Write-Host ""
Write-Host "The quilt prompt WILL WAIT. When you see it:" -ForegroundColor Yellow
Write-Host "  1. MSYS2:  cd <local-path>/Helium-workspace/helium-windows && source devutils/set_quilt_vars.sh && cd build/src && quilt push -a" -ForegroundColor Yellow
Write-Host "  2. then in a 2nd PowerShell:  <local-path>\Helium-workspace\continue-build.ps1" -ForegroundColor Yellow
Write-Host ""

& {
  while (-not (Test-Path $release)) { Start-Sleep -Milliseconds 500 }
  ""
} | python build.py --dev
