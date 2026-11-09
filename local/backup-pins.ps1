param([string]$Dest = "<local-path>\Helium-workspace\backups\pins",
      [string]$UserData = (Join-Path $env:LOCALAPPDATA "Helium Workspaces\User Data"),
      [string]$At = "21:00",
      [switch]$SelfTest, [switch]$Register)
# C18 (ideas.md): dated copies of the two files that are ours alone -- "Workspace Pins" (every pinned page and
# folder) and "Workspace Archive" -- for each profile in the daily browser's User Data. The browser writes both
# through base::ImportantFileWriter (a new file renamed over the old one; the rename is retried 5 x 100 ms), so a
# copy taken while it runs is always one whole version and never costs it a save. What nothing guarded against: a
# WRONG save -- a bug of ours, or a delete noticed a day later.
# Each run copies them into <Dest>\<yyyy-MM-dd_HHmmss>\<profile>\, unless they are byte for byte the newest copy
# (then nothing is copied: a kept copy is a VERSION, not a day), then removes the copies Select-Expired names.
# It reads the profile, never writes it, and appends one line to <local-path>\Helium-workspace\pins-backups.log.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\backup-pins.ps1
#   -Register  creates the scheduled task "Helium Workspaces pins backup" (daily at -At; missed -> next sign-in; no window)
#   -SelfTest  the keep rule on made-up dates, and copy runs on a made-up profile
# To put a copy back: QUIT the browser first (it writes its own version at exit), then, for example:
#   Copy-Item "<local-path>\Helium-workspace\backups\pins\<stamp>\Default\Workspace Pins" "$env:LOCALAPPDATA\Helium Workspaces\User Data\Default\"
$ErrorActionPreference = "Stop"
$Files    = @("Workspace Pins", "Workspace Archive")
$Stamp    = "yyyy-MM-dd_HHmmss"
$Inv      = [cultureinfo]::InvariantCulture
$Record   = "<local-path>\Helium-workspace\pins-backups.log"
$TaskName = "Helium Workspaces pins backup"

# Which copies to remove. $Stamps: the time of every copy in <Dest>, newest first (the one this run made included).
# Returns the times to remove. The newest is never removed, whatever this returns.
# The owner's rule: every copy from the newest 30 days that have copies -- a busy day counts once.
function Select-Expired([datetime[]]$Stamps) {
    $keep = $Stamps.Date | Select-Object -Unique | Select-Object -First 30
    $Stamps | Where-Object { $keep -notcontains $_.Date }
}

# The copies in $Dest: only folders named by $Stamp count -- nothing else there is ever touched.
function Get-Copies([string]$Dest) {
    if (-not (Test-Path -LiteralPath $Dest)) { return @() }
    @(Get-ChildItem -LiteralPath $Dest -Directory | ForEach-Object {
        $t = [datetime]::MinValue
        if ([datetime]::TryParseExact($_.Name, $Stamp, $Inv, 'None', [ref]$t)) { [pscustomobject]@{ Dir = $_.FullName; Time = $t } }
    } | Sort-Object Time -Descending)
}

function Backup([string]$UserData, [string]$Dest, [datetime]$Now) {
    $src = @(foreach ($d in Get-ChildItem -LiteralPath $UserData -Directory -ErrorAction SilentlyContinue) {
        foreach ($f in $Files) {
            $p = Join-Path $d.FullName $f
            if (Test-Path -LiteralPath $p -PathType Leaf) { [pscustomobject]@{ Path = $p; Rel = Join-Path $d.Name $f; Hash = (Get-FileHash -LiteralPath $p).Hash } }
        }
    })
    if (-not $src) { return "FAIL nothing to copy: no '$($Files -join "' or '")' in any profile under $UserData" }
    $newest = Get-Copies $Dest | Select-Object -First 1
    $same = $newest -and @(Get-ChildItem -LiteralPath $newest.Dir -File -Recurse).Count -eq $src.Count -and -not ($src | Where-Object {
        $c = Join-Path $newest.Dir $_.Rel
        -not (Test-Path -LiteralPath $c) -or (Get-FileHash -LiteralPath $c).Hash -ne $_.Hash })
    if ($same) { $line = "UNCHANGED since $(Split-Path $newest.Dir -Leaf)" }
    else {
        $dir = Join-Path $Dest $Now.ToString($Stamp, $Inv)
        foreach ($s in $src) {
            $to = Join-Path $dir $s.Rel
            New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
            Copy-Item -LiteralPath $s.Path -Destination $to
        }
        $line = "COPIED $($src.Count) file(s) to $dir"
    }
    $copies  = Get-Copies $Dest
    $expired = @(Select-Expired @($copies.Time) | Where-Object { $_ -ne $copies[0].Time })
    foreach ($c in $copies | Where-Object { $expired -contains $_.Time }) { Remove-Item -LiteralPath $c.Dir -Recurse -Force }
    "$line; kept $($copies.Count - $expired.Count), removed $($expired.Count)"
}

if ($SelfTest) {
    $fail = 0
    function Check([string]$Name, [bool]$Ok) { Write-Host ("{0} {1}" -f ($(if ($Ok) { "PASS" } else { "FAIL" }), $Name)); if (-not $Ok) { $script:fail++ } }
    $now = [datetime]::new(2026, 10, 6, 13, 0, 0)
    # The keep rule: what any rule must do, on three made-up histories (newest first).
    $histories = [ordered]@{
        "one copy"                     = @($now)
        "60 daily copies"              = @(0..59 | ForEach-Object { $now.AddDays(-$_) })
        "10 copies in an hour + daily" = @((0..9 | ForEach-Object { $now.AddMinutes(-6 * $_) }) + (1..30 | ForEach-Object { $now.AddDays(-$_) }))
    }
    foreach ($h in $histories.GetEnumerator()) {
        $gone = @(Select-Expired $h.Value)
        Check "$($h.Key): keeps the newest" (-not ($gone -contains $h.Value[0]))
        Check "$($h.Key): names only copies that exist" (-not ($gone | Where-Object { $h.Value -notcontains $_ }))
    }
    # The rule the owner chose: every copy from the newest 30 days that have copies.
    $h = $histories["60 daily copies"]; $gone = @(Select-Expired $h)
    Check "60 daily copies: the 30 oldest days go, the 30 newest stay" ($gone.Count -eq 30 -and $gone -contains $h[30] -and $gone -notcontains $h[29])
    $h = $histories["10 copies in an hour + daily"]; $gone = @(Select-Expired $h)
    Check "a busy day counts once: of 31 days only the oldest goes" ($gone.Count -eq 1 -and $gone[0] -eq $h[-1])
    # Copy runs on a made-up profile, in a temporary folder.
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "backup-pins-selftest-$PID"
    $ud = Join-Path $tmp "User Data"; $to = Join-Path $tmp "copies"
    New-Item -ItemType Directory -Force (Join-Path $ud "Default"), (Join-Path $ud "Profile 1"), (Join-Path $to "notes") | Out-Null
    Set-Content -LiteralPath (Join-Path $ud "Default\Workspace Pins") "pins v1"
    Set-Content -LiteralPath (Join-Path $ud "Default\Workspace Archive") "archive v1"
    Set-Content -LiteralPath (Join-Path $ud "Profile 1\Workspace Pins") "other pins"
    Set-Content -LiteralPath (Join-Path $to "keep-me.txt") "not a copy"
    try {
        $r1 = Backup $ud $to $now
        Check "first run copies 3 files: $r1" ($r1 -like "COPIED 3 file(s)*")
        $r2 = Backup $ud $to $now.AddMinutes(1)
        Check "nothing changed -> no new copy: $r2" ($r2 -like "UNCHANGED since 2026-10-06_130000*")
        Set-Content -LiteralPath (Join-Path $ud "Default\Workspace Pins") "pins v2"
        $r3 = Backup $ud $to $now.AddMinutes(2)
        Check "a changed file -> a new copy: $r3" ($r3 -like "COPIED 3 file(s)*")
        Check "the new copy holds the new bytes" ((Get-Content -LiteralPath (Join-Path $to "2026-10-06_130200\Default\Workspace Pins")) -eq "pins v2")
        foreach ($d in 1..30) { $old = Join-Path $to ($now.AddDays(-$d).ToString($Stamp, $Inv)); New-Item -ItemType Directory $old | Out-Null; Set-Content (Join-Path $old "x") "old" }
        $r4 = Backup $ud $to $now.AddMinutes(3)
        Check "31 days of copies -> the oldest day's folder is removed: $r4" (($r4 -like "*removed 1") -and -not (Test-Path (Join-Path $to "2026-09-06_130000")) -and (Test-Path (Join-Path $to "2026-09-07_130000")))
        Check "a folder and a file that are not copies are left alone" ((Test-Path (Join-Path $to "notes")) -and (Test-Path (Join-Path $to "keep-me.txt")))
        Check "no profile files -> FAIL" ((Backup (Join-Path $tmp "nowhere") $to $now) -like "FAIL*")
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force }
    if ($fail) { Write-Host "SELFTEST FAIL ($fail)" -ForegroundColor Red; exit 1 }
    Write-Host "SELFTEST PASS" -ForegroundColor Green; exit 0
}

if ($Register) {
    # Task Scheduler does not search PATH, and Get-Command pwsh gives a versioned Store folder: the alias (LOCAL.md 57).
    # conhost --headless runs it with no window at all.
    $pw = "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
    $action   = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\conhost.exe" -Argument "--headless `"$pw`" -NoProfile -File `"$PSCommandPath`""
    $trigger  = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "Registered: $TaskName, daily at $At (missed -> at the next sign-in)."
    Write-Host "Remove it with: Unregister-ScheduledTask -TaskName '$TaskName'"
    exit 0
}

$now = Get-Date
try { $line = Backup $UserData $Dest $now } catch { $line = "FAIL $($_.Exception.Message)" }
Add-Content -LiteralPath $Record "$($now.ToString('yyyy-MM-dd HH:mm:ss', $Inv)) $line"
Write-Host $line
if ($line -like "FAIL*") { exit 1 }
