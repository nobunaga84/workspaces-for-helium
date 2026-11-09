param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "")
# Patch 95 (chunk A, LOCAL.md 124): the fork's own default profile folder, and no "make default" inside the browser.
# The browser starts with LOCALAPPDATA pointed at a new scratch folder and no --user-data-dir, so the folder it picks
# is made there: the owner's profiles and official Helium's are never opened. --remote-debugging-port keeps the
# launch from being handed to a running browser (AttemptFastNotify). A window shows for about 10 s; no mouse or keys.
#   pwsh -NoProfile -File local\check-95.ps1 [-Build Dcheck] [-BinDir <dir>]
#   F1  the default folder is <scratch>\Helium Workspaces\User Data, and nothing is made under <scratch>\imput
#   F2  chrome://settings answers canBeDefault false: no "Make default" button, no onboarding default-browser page
. "$PSScriptRoot\e18-lib.ps1"
$bin     = if ($BinDir) { $BinDir } else { "<local-path>\Helium-workspace\helium-windows\build\src\out\$Build" }
$scratch = "$env:TEMP\check-95-$(Get-Date -Format yyyyMMdd-HHmmss)"
$own     = "$scratch\Helium Workspaces\User Data"
$null = New-Item -ItemType Directory $scratch
$script:passed = 0; $script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }

$real = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $scratch   # inherited by the browser only; put back at once
try { $p = Start-Process "$bin\chrome.exe" -ArgumentList "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0" -PassThru }
finally { $env:LOCALAPPDATA = $real }
try {
    # The DevTools port file lands in whichever folder the browser chose: its own, or official Helium's name.
    $t0 = Get-Date; $chosen = $null
    while (-not $chosen -and ((Get-Date) - $t0).TotalSeconds -lt 30) {
        Start-Sleep 1
        $chosen = @($own, "$scratch\imput\Helium\User Data") | Where-Object { Test-Path -LiteralPath "$_\DevToolsActivePort" } | Select-Object -First 1
    }
    Write-Host "      folder: $(if ($chosen) { $chosen } else { '(none in 30 s)' })"

    $can = "(no page)"
    if ($chosen) {
        $s = OpenSettings $chosen
        Write-Host "      settings: $($s.note)"
        if ($s.ready) { $can = Evaluate $s.page.webSocketDebuggerUrl "import('chrome://resources/js/cr.js').then(m => m.sendWithPromise('requestDefaultBrowserState')).then(r => r.canBeDefault)" }
    }
    Write-Host "      canBeDefault: $can"
    # After the settings page, so a late write under official Helium's name is seen too.
    Verdict "F1 own default folder" ($chosen -eq $own -and -not (Test-Path -LiteralPath "$scratch\imput"))
    Verdict "F2 no make-default" ($can -eq $false)
} finally { Stop-Process -Id $p.Id -EA SilentlyContinue }
Write-Host "$script:passed passed, $script:failed failed (scratch folder $scratch)"
exit [int]($script:failed -gt 0)
