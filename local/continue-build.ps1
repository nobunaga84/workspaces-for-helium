# Releases the quilt prompt held open by dev-build.ps1.
# Run ONLY after "quilt push -a" has completed successfully.
$release = "<local-path>\Helium-workspace\.build-release"
$pc = "<local-path>\Helium-workspace\helium-windows\build\src\.pc\applied-patches"
if (-not (Test-Path $pc)) {
    # Since R4 an unpatched release no longer fails fast at gn bootstrap: it
    # builds an unpatched tree for hours. So this is a hard stop, not a prompt.
    Write-Host "ABORT: no .pc/applied-patches - quilt has not run. Nothing released." -ForegroundColor Red
    exit 1
}
$n = (Get-Content $pc).Count
Write-Host "quilt reports $n patches applied." -ForegroundColor Green
New-Item -ItemType File -Path $release -Force | Out-Null
Write-Host "Released - build.py continues to args.gn and gn gen." -ForegroundColor Green
