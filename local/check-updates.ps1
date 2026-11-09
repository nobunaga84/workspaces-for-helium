param([switch]$Weekly, [switch]$SelfTest, [switch]$Register)
# Phase 4a (LOCAL.md 57): is Helium Workspaces too old? The weekly check behind the deferral rule (roadmap, 2026-09-19):
#   a Helium release that changes the browser is rebased onto within 14 days (an R chunk); while deferring, if a fix
#   for an attack "in the wild" is in the gap, do risky browsing in official Helium until the rebase.
# It reads (never writes): helium-windows' tags (git fetch), the pinned Helium commit's chromium_version.txt, the
# fork's own version (installed, else out/Default), official Helium's version, and Chrome's release blog. It appends
# one line to <local-path>\Helium-workspace\update-checks.log ("FAILED" when it cannot read helium-windows' tags; "fetch FAILED"
# when the verdict comes from the tags known before).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-updates.ps1
#   -Weekly    what the scheduled task runs: the same, then waits for Enter
#   -Register  creates the scheduled task "Helium Workspaces update check" (Fridays 20:00; missed -> next sign-in)
#   -SelfTest  the verdict on six made-up situations
$ws       = "<local-path>\Helium-workspace"
$hw       = "$ws\helium-windows"
$repo     = "$ws\helium"
$record   = "$ws\update-checks.log"
$official = "C:\Program Files\imput\Helium\Application"
$feed     = "https://chromereleases.googleblog.com/feeds/posts/default/-/Desktop%20Update?max-results=40"
$maxDefer = 14

# The verdict: OK (nothing to rebase), DEFER (allowed until a date), REBASE (overdue), MAJOR (a new Chromium major).
# The 14 days count from $sinceTag, the FIRST release after the fork whose Helium commit or Windows patches differ
# -- a newer release must not restart them. On the safe side: 0.17.2.2 changed only installer and build-tool patches,
# and it still starts the clock.
function Verdict([string]$forkTag, [version]$forkChromium, [string]$newTag, [version]$newChromium, [bool]$sameCode,
                 [string]$sinceTag, [datetime]$sinceDate, [datetime]$today, [int]$wildInGap) {
    if ($newTag -eq $forkTag) { return [pscustomobject]@{ Level = "OK"; Text = "the fork is on the newest Helium ($newTag)" } }
    if ($sameCode) { return [pscustomobject]@{ Level = "OK"; Text = "$newTag changes packaging only (same Helium, same Windows patches): nothing to rebase" } }
    $due  = $sinceDate.Date.AddDays($maxDefer)
    $late = ($today.Date - $due).Days
    $v = if ($newChromium.Major -gt $forkChromium.Major) {
        [pscustomobject]@{ Level = "MAJOR"; Text = "$newTag moves to Chromium $($newChromium.Major): plan an R chunk (a long build); rebase by $($due.ToString('yyyy-MM-dd'))" }
    } elseif ($late -gt 0) {
        [pscustomobject]@{ Level = "REBASE"; Text = "$sinceTag (the first release since $forkTag to change Helium or its Windows patches) came out $($sinceDate.ToString('yyyy-MM-dd')): the 14 days ran out $late day(s) ago -- rebase now (an R chunk)" }
    } else {
        [pscustomobject]@{ Level = "DEFER"; Text = "$sinceTag (the first release since $forkTag to change Helium or its Windows patches) came out $($sinceDate.ToString('yyyy-MM-dd')): deferring is allowed until $($due.ToString('yyyy-MM-dd'))" }
    }
    if ($wildInGap -gt 0) { $v.Text += "; an attack IN THE WILD is fixed in $newTag -- do risky browsing in official Helium (updated) until the rebase" }
    $v
}
# Chrome's updates beyond every Helium, for the record line ([int]: an empty list's Sum is $null, not 0).
function Ahead($list) { "$(@($list).Count) update(s), $([int]($list | Measure-Object Critical -Sum).Sum) critical" }

if ($SelfTest) {
    $t = [datetime]"2026-10-02"; $bad = 0
    $cases = @(  # each row behind a comma: without it PowerShell flattens the rows into one list
        ,@("0.17.2.1", "153.0.8010.52", "0.17.2.1", "153.0.8010.52", $false, "0.17.2.1", "2026-09-18", 0, "OK", "newest")
        ,@("0.17.2.1", "153.0.8010.52", "0.17.2.2", "153.0.8010.52", $true,  "0.17.2.2", "2026-09-20", 0, "OK", "packaging")
        ,@("0.17.2.1", "153.0.8010.52", "0.17.3.1", "153.0.8010.70", $false, "0.17.3.1", "2026-09-27", 0, "DEFER", "until 2026-10-11")
        ,@("0.17.2.1", "153.0.8010.52", "0.17.3.1", "153.0.8010.70", $false, "0.17.3.1", "2026-09-10", 0, "REBASE", "8 day(s) ago")
        ,@("0.17.2.1", "153.0.8010.52", "0.18.0.1", "154.0.8037.93", $false, "0.18.0.1", "2026-09-30", 0, "MAJOR", "Chromium 154")
        ,@("0.17.2.1", "153.0.8010.52", "0.17.3.1", "153.0.8010.70", $false, "0.17.3.1", "2026-09-27", 1, "DEFER", "IN THE WILD")
        ,@("0.17.2.1", "153.0.8010.52", "0.17.4.1", "153.0.8010.80", $false, "0.17.3.1", "2026-09-10", 0, "REBASE", "0.17.3.1 (the first release")
    )
    foreach ($c in $cases) {
        $v = Verdict $c[0] $c[1] $c[2] $c[3] $c[4] $c[5] ([datetime]$c[6]) $t $c[7]
        $ok = $v.Level -eq $c[8] -and $v.Text.Contains($c[9])
        if (-not $ok) { $bad++ }
        Write-Host "$(if ($ok) { 'PASS' } else { 'FAIL' })  $($c[2]) -> $($v.Level): $($v.Text)"
    }
    $ok = (Ahead @()) -eq "0 update(s), 0 critical"
    if (-not $ok) { $bad++ }
    Write-Host "$(if ($ok) { 'PASS' } else { 'FAIL' })  Chrome ahead by nothing -> $(Ahead @())"
    if ($bad) { Write-Host "SELFTEST FAIL ($bad)"; exit 1 }
    Write-Host "SELFTEST PASS"; exit 0
}

if ($Register) {
    # The app alias: the Store install's own path carries its version (breaks at the next update), and the task
    # runner does not search PATH for a bare pwsh.exe (0x80070002, 2026-09-30).
    $action = New-ScheduledTaskAction -Execute "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe" -Argument "-NoProfile -File `"$PSCommandPath`" -Weekly"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At "20:00"
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName "Helium Workspaces update check" -Action $action -Trigger $trigger -Settings $settings -Force `
        -Description "Weekly: is Helium Workspaces too old? (<local-path>\Helium-workspace\helium\local\check-updates.ps1, LOCAL.md 57)" | Out-Null
    Write-Host "Registered: Helium Workspaces update check, Fridays 20:00 (missed -> at the next sign-in)."
    Write-Host "Remove it with: Unregister-ScheduledTask -TaskName 'Helium Workspaces update check'"
    exit 0
}

function Say([string]$label, [string]$text) { Write-Host ("{0,-30} {1}" -f $label, $text) }
# The record line appended -- "Recorded" only when it was (a locked log says so) -- then the -Weekly pause and the exit.
function Finish([string]$line, [int]$code) {
    try { Add-Content -LiteralPath $record -Value $line -EA Stop; Write-Host "Recorded in $record" }
    catch { Write-Host "Could NOT record in ${record}: $($_.Exception.Message)" -ForegroundColor Red; $code = 1 }
    if ($Weekly) { Read-Host "Press Enter to close" | Out-Null }
    exit $code
}
# A browser folder's versions: Chromium from chrome.exe; Helium from a <version>.manifest (the fork's flat folder)
# or the newest <version> subfolder (an installed Helium's Application folder).
function FolderVersion([string]$dir) {
    $named = @(Get-ChildItem -LiteralPath $dir -EA SilentlyContinue | Where-Object { $_.BaseName -match '^\d+(\.\d+){3}$' -and ($_.PSIsContainer -or $_.Extension -eq ".manifest") })
    [pscustomobject]@{ Helium = ($named | Sort-Object { [version]$_.BaseName } | Select-Object -Last 1).BaseName
                       Chromium = [version](Get-Item -LiteralPath "$dir\chrome.exe").VersionInfo.ProductVersion }
}

Write-Host ""
Write-Host "Helium Workspaces update check, $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
$installedDir = "$env:LOCALAPPDATA\Programs\Helium Workspaces"
$forkDir = if (Test-Path "$installedDir\chrome.exe") { $installedDir } else { "$hw\build\src\out\Default" }
$fork = FolderVersion $forkDir
Say "Helium Workspaces" "$($fork.Helium) (Chromium $($fork.Chromium)) -- $(if ($forkDir -eq $installedDir) { 'installed' } else { 'the build (not installed)' })"

$fetchErr = @(git -C $hw fetch --quiet --tags origin 2>&1) + @(if ($LASTEXITCODE) { "(exit $LASTEXITCODE)" })
$fetchErr += @(git -C $repo fetch --quiet --tags upstream 2>&1) + @(if ($LASTEXITCODE) { "(exit $LASTEXITCODE)" })
$fetched = -not ($fetchErr -match '\(exit ')
$newTag  = @(git -C $hw tag --sort=-v:refname | Where-Object { $_ -match '^\d+(\.\d+){3}$' })[0]
# No tags: git is missing, or the clone moved. Then every number below is empty, so no verdict this week.
if (-not $newTag) {
    $why = "no helium-windows tags in $hw (git missing, or the clone moved)"
    Write-Host "FAILED: $why -- no verdict this week." -ForegroundColor Red
    Finish ("{0} | FAILED: {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"), $why) 1
}
$newDate = [datetime](git -C $hw log -1 --format=%cI $newTag)
$pin     = (git -C $hw ls-tree $newTag helium-chromium) -split '\s+' | Select-Object -Index 2
$newChr  = git -C $repo show "${pin}:chromium_version.txt" 2>$null
$newChromium = if ($newChr) { [version]$newChr.Trim() } else { $null }
$forkPin = (git -C $hw ls-tree $fork.Helium helium-chromium) -split '\s+' | Select-Object -Index 2
git -C $hw diff --quiet $fork.Helium $newTag -- patches/ 2>$null
$sameCode = $pin -and $pin -eq $forkPin -and $LASTEXITCODE -eq 0
# The first newer release whose Helium commit or Windows patches differ from the fork's: the deferral clock's start.
$sinceTag = @(git -C $hw tag --sort=v:refname | Where-Object { $_ -match '^\d+(\.\d+){3}$' -and [version]$_ -gt [version]$fork.Helium } | Where-Object {
    $p = (git -C $hw ls-tree $_ helium-chromium) -split '\s+' | Select-Object -Index 2
    git -C $hw diff --quiet $fork.Helium $_ -- patches/ 2>$null
    -not ($p -eq $forkPin -and $LASTEXITCODE -eq 0) }) | Select-Object -First 1
if (-not $sinceTag) { $sinceTag = $newTag }
$sinceDate = [datetime](git -C $hw log -1 --format=%cI $sinceTag)
Say "Newest Helium release" "$newTag, $($newDate.ToString('yyyy-MM-dd')) (Chromium $(if ($newChromium) { $newChromium } else { 'unknown: its Helium commit is not fetched' }))"
if (-not $fetched) { Write-Host "The fetch FAILED, so this is what was known before: $($fetchErr -join ' / ')" -ForegroundColor Red }

$off = if (Test-Path "$official\chrome.exe") { FolderVersion $official } else { $null }
Say "Official Helium" "$(if ($off) { "$($off.Helium) (Chromium $($off.Chromium))" } else { 'not installed' })"

# Chrome's own Stable desktop updates newer than the fork: in the gap a rebase closes (up to the newest Helium's
# Chromium), and beyond it (Chrome ahead of every Helium).
$gap = @(); $beyond = @(); $feedOk = $true
try {
    foreach ($e in @(Invoke-RestMethod $feed -TimeoutSec 30)) {
        if ("$($e.title.'#text')" -notlike "Stable Channel Update for Desktop*") { continue }
        $c = "$($e.content.'#text')"
        $max = [regex]::Matches($c, '\b1\d\d\.0\.\d{4}\.\d+') | ForEach-Object { [version]$_.Value } | Sort-Object | Select-Object -Last 1
        if (-not $max -or $max -le $fork.Chromium) { continue }
        $post = [pscustomobject]@{ Date = "$($e.published)".Substring(0, 10); Version = $max; Critical = ([regex]::Matches($c, 'Critical CVE')).Count; Wild = $c -match 'in the wild' }
        if ($newChromium -and $max -le $newChromium) { $gap += $post } else { $beyond += $post }
    }
} catch { $feedOk = $false; $feedErr = $_.Exception.Message }
function Posts($list) { if (-not $list) { return "none" }; ($list | ForEach-Object { "$($_.Date) $($_.Version) ($($_.Critical) critical$(if ($_.Wild) { ', IN THE WILD' }))" }) -join "; " }
if ($feedOk) {
    Say "Chrome fixes a rebase closes" (Posts $gap)
    Say "Chrome ahead of Helium" (Posts $beyond)
} else {
    Write-Host "Could NOT read Chrome's release blog ($feedErr): read https://chromereleases.googleblog.com/ yourself." -ForegroundColor Red
}

$v = Verdict $fork.Helium $fork.Chromium $newTag $newChromium $sameCode $sinceTag $sinceDate (Get-Date) @($gap | Where-Object Wild).Count
Write-Host ""
Write-Host "VERDICT: $($v.Level) -- $($v.Text)" -ForegroundColor $(switch ($v.Level) { "OK" { "Green" } "DEFER" { "Yellow" } default { "Red" } })
if ($off -and $off.Helium -and [version]$off.Helium -lt [version]$newTag) {
    Write-Host "Official Helium ($($off.Helium)) is older than $newTag`: open it, helium://settings/help, and let it update -- it is the fallback." -ForegroundColor Yellow
}
if (@($beyond | Where-Object Wild).Count) {
    Write-Host "Chrome has fixed an attack IN THE WILD that no Helium has yet: be careful on unfamiliar sites until Helium catches up." -ForegroundColor Yellow
}
if (-not $feedOk) { Write-Host "(the verdict could not weigh Chrome's security fixes this time)" -ForegroundColor Red }
# "fetch FAILED": the verdict is from the tags known before, not a fresh check.
$line = "{0} | fork {1} ({2}) | newest {3} ({4}, {5}{6}) | official {7} | chrome ahead: {8} | {9}{10}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"), $fork.Helium, $fork.Chromium, $newTag, $newChromium, $newDate.ToString("yyyy-MM-dd"), $(if ($sameCode) { ", packaging only" } else { "" }), $(if ($off) { $off.Helium } else { "-" }), $(if ($feedOk) { Ahead $beyond } else { "feed unread" }), $v.Level, $(if ($fetched) { "" } else { " | fetch FAILED" })
Finish $line 0
