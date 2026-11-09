param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "", [switch]$LogOnly)
# Patch 96 (chunk B, LOCAL.md 125): a Pins or Archive file the browser cannot use is told in Chromium's "Profile error
# occurred" box, once per file (the review's data-files F2-F4, overlooked F8). Two launches, each on a new scratch
# profile (Local State and Preferences copied from testprofile-e15b-smoke: vertical, Workspaces on) holding a broken
# pair of files. Each box is read (title and text, UI Automation) and closed (WM_CLOSE, what its X sends). No mouse, no
# keys -- but the boxes show for a few seconds per run: run it with the PC free (the owner's word).
#   pwsh -NoProfile -File local\check-96.ps1 [-Build Dcheck] [-BinDir <dir>]
#   N1  run 1, Pins not JSON: a box says the pinned pages file was kept as .bad; "Workspace Pins.bad" exists
#   N2  run 1, Archive version 99: a box says the Archive could not be read; the file is byte for byte as written
#   N3  run 2, Pins version 99: a box says the pinned pages could not be read; the file is byte for byte as written
#   N4  run 2, Archive not JSON: a box says the Archive file was kept as .bad; "Workspace Archive.bad" exists
#   N5  exactly two boxes per run: one per file
# Then the log lines that name a site, an address or a title, now VLOG(1) (privacy F6): two launches with a site rule
# (example.com -> the smoke profile's "Unpin" workspace) opening http://example.com/ from the command line:
#   V1  without the switch: the tab is stamped for the rule's workspace, and no line names example.com
#   V2  with --helium-workspaces-log-addresses (what the checks pass): "site rule: 'example.com' -> workspace
#       '<Unpin>'" is there. Not --vmodule: in this build it never reaches the browser process's own lines.
# -LogOnly runs V1 and V2 alone: no box, so no need for the PC to be free.
. "$PSScriptRoot\e18-lib.ps1"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$ws      = "<local-path>\Helium-workspace"
$bin     = if ($BinDir) { $BinDir } else { "$ws\helium-windows\build\src\out\$Build" }
$smoke   = "$ws\testprofile-e15b-smoke"
$scratch = "$env:TEMP\check-96-$(Get-Date -Format yyyyMMdd-HHmmss)"
$slow    = if ($Build -eq "Dcheck") { 3 } else { 1 }
$script:passed = 0; $script:failed = 0
function Verdict($name, $ok) { if ($ok) { Write-Host "PASS  $name"; $script:passed++ } else { Write-Host "FAIL  $name"; $script:failed++ } }
function Abort([string]$why) { Write-Host "ABORT: $why"; exit 1 }

if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Abort "a fork browser is already running" }
if (-not (Test-Path -LiteralPath "$bin\chrome.exe")) { Abort "no $bin\chrome.exe" }
E18InputType
$UIA = [System.Windows.Automation.AutomationElement]
$title = "Profile error occurred"

# The browser's "Profile error occurred" boxes: their text (every name inside, joined), each closed once read.
function Boxes([int]$bpid) {
    $cond = New-Object System.Windows.Automation.PropertyCondition($UIA::ProcessIdProperty, $bpid)
    @($UIA::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, $cond) | Where-Object { $_.Current.Name -eq $title } | ForEach-Object {
        $all = $_.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
        $text = (@($all | ForEach-Object { $_.Current.Name }) | Where-Object { $_ }) -join " | "
        [E18Input]::CloseWindow([IntPtr]$_.Current.NativeWindowHandle)
        $text
    })
}

# One launch: the two files written, the browser started, the boxes collected for 25 s (the two loads are at startup;
# the rest of the wait is for a third box that must not come), the browser stopped.
function Run([string]$name, [string]$pins, [string]$archive) {
    $prof = "$scratch\$name"
    $null = New-Item -ItemType Directory "$prof\Default"
    Copy-Item -LiteralPath "$smoke\Local State" "$prof\Local State"
    Copy-Item -LiteralPath "$smoke\Default\Preferences" "$prof\Default\Preferences"
    [IO.File]::WriteAllText("$prof\Default\Workspace Pins", $pins)
    [IO.File]::WriteAllText("$prof\Default\Workspace Archive", $archive)
    $log = "$ws\e96-$name$(if ($Build -eq 'Dcheck') { '-dcheck' }).log"
    $p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList "--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run", "--no-default-browser-check"
    $seen = @()
    try {
        $t0 = Get-Date
        while (((Get-Date) - $t0).TotalSeconds -lt 25 * $slow) { $seen += Boxes $p.Id; Start-Sleep -Milliseconds 500 }
    } finally { Stop-Process -Id $p.Id -EA SilentlyContinue; Wait-Process -Id $p.Id -Timeout 15 -EA SilentlyContinue }
    $seen | ForEach-Object { Write-Host "      $name box: $_" }
    if (-not $seen.Count) { Write-Host "      $name box: (none)" }
    [pscustomobject]@{ prof = "$prof\Default"; boxes = $seen }
}
function Same([string]$file, [string]$text) { (Test-Path -LiteralPath $file) -and [IO.File]::ReadAllText($file) -eq $text }

$newerPins    = '{"version": 99, "workspaces": {}}'
$newerArchive = '{"version": 99, "entries": []}'
if (-not $LogOnly) {
$r1 = Run "run1" "not json" $newerArchive
$r2 = Run "run2" $newerPins "not json"

Verdict "N1 run 1: Pins kept as .bad, and said" (@($r1.boxes -match 'pinned pages file could').Count -eq 1 -and (Test-Path -LiteralPath "$($r1.prof)\Workspace Pins.bad"))
Verdict "N2 run 1: Archive read-only, said, file unchanged" (@($r1.boxes -match 'Archive could').Count -eq 1 -and (Same "$($r1.prof)\Workspace Archive" $newerArchive))
Verdict "N3 run 2: Pins read-only, said, file unchanged" (@($r2.boxes -match 'pinned pages could').Count -eq 1 -and (Same "$($r2.prof)\Workspace Pins" $newerPins))
Verdict "N4 run 2: Archive kept as .bad, and said" (@($r2.boxes -match 'Archive file could').Count -eq 1 -and (Test-Path -LiteralPath "$($r2.prof)\Workspace Archive.bad"))
Verdict "N5 two boxes per run (run 1: $($r1.boxes.Count), run 2: $($r2.boxes.Count))" ($r1.boxes.Count -eq 2 -and $r2.boxes.Count -eq 2)
}

# One launch with the site rule, the rule's page opened by the command line; the log returned.
$unpin = "d7ba2239-6fc1-4d07-9750-7b250403ba4f"
function RuleRun([string]$name, [string[]]$extra) {
    $prof = "$scratch\$name"
    $null = New-Item -ItemType Directory "$prof\Default"
    Copy-Item -LiteralPath "$smoke\Local State" "$prof\Local State"
    Copy-Item -LiteralPath "$smoke\Default\Preferences" "$prof\Default\Preferences"
    & python -I -c "import json,sys; p=sys.argv[1]; d=json.load(open(p,encoding='utf-8')); [i.__setitem__('sites',['example.com']) for i in d['helium']['workspaces']['list']['items'] if i['guid']==sys.argv[2]]; json.dump(d,open(p,'w',encoding='utf-8'))" "$prof\Default\Preferences" $unpin
    $log = "$ws\e96-$name$(if ($Build -eq 'Dcheck') { '-dcheck' }).log"
    $p = Start-Process "$bin\chrome.exe" -PassThru -ArgumentList (@("--user-data-dir=`"$prof`"", "--enable-logging", "--log-file=`"$log`"", "--v=0") + $extra + @("--no-first-run", "--no-default-browser-check", "http://example.com/"))
    try { Start-Sleep -Seconds (15 * $slow) } finally { Stop-Process -Id $p.Id -EA SilentlyContinue; Wait-Process -Id $p.Id -Timeout 15 -EA SilentlyContinue }
    # Shared: the browser's helper processes can still hold the log open.
    if (-not (Test-Path -LiteralPath $log)) { return "" }
    $fs = [IO.File]::Open($log, "Open", "Read", "ReadWrite, Delete")
    try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
$plain   = RuleRun "rule-plain" @()
$verbose = RuleRun "rule-verbose" @("--helium-workspaces-log-addresses")
$stamped = $plain -match "\[workspaces\] tab inserted at index \d+ -> workspace '$unpin'"
Verdict "V1 without the switch: stamped for the rule ($stamped), no line names example.com" ($stamped -and $plain -notmatch "example\.com")
Verdict "V2 with --helium-workspaces-log-addresses: the site rule line names the site" ($verbose -match "\[workspaces\] site rule: 'example\.com' -> workspace '$unpin'")
Write-Host "$script:passed passed, $script:failed failed (scratch folder $scratch)"
exit [int]($script:failed -gt 0)
