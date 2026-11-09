param([string]$Dest = "<local-path>\Helium-workspace\backups",
      [ValidateSet("arc", "helium")][string]$Only,
      [string]$ArcDir,
      [string]$HeliumDir,
      [switch]$SelfTest)
# E14e, deliverable 1: a safety copy of Arc and of official Helium before switch day touches anything
# (e14e-contract.md). Copies Arc's WHOLE package folder (an uninstall deletes all of it) and official Helium's
# User Data into a new folder <local-path>\Helium-workspace\backups\<yyyy-MM-dd_HHmmss>\ (arc\ and helium-user-data\),
# then checks each copy against its source -- the number of files, the total bytes, and the SHA-256 of the files
# that matter most (Arc's StorableSidebar.json and StorableArchiveItems.json; Helium's Local State and
# Default\Preferences), that nothing in the source changed while it was being copied, and that no browser runs on
# it once the copy ends -- and writes manifest.txt beside them with the numbers and the one-line command that
# puts each copy back (it renames the current folder aside first, so nothing newer mixes into the restored one).
# The last line printed is
#   RESULT backup=<the backup folder> verdict=PASS|FAIL
# and the exit code is 0 only on PASS. A copy that does not verify is KEPT, never deleted.
# It refuses (exit 1, nothing copied) when Arc runs, when official Helium runs, when a source is missing, when
# the backup folder already exists, or when the destination drive has less than 1.2 x the sources' size free.
# Every refusal says why and what to do. -ArcDir / -HeliumDir back up another folder instead; the running-browser
# checks then become "no lockfile in that folder" (how -SelfTest runs while Arc is open).
# Nothing here prints a web address or a page title: a folder named after a website shows as <site>.
# One line each, in PowerShell 7 (Windows PowerShell 5.1 works too):
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\backup-browsers.ps1
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\backup-browsers.ps1 -Only helium
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\backup-browsers.ps1 -SelfTest
$ErrorActionPreference = "Stop"
$DefaultArcDir    = Join-Path $env:LOCALAPPDATA "Packages\TheBrowserCompany.Arc_ttt1ap7aakyb4"
$DefaultHeliumDir = Join-Path $env:LOCALAPPDATA "imput\Helium\User Data"
$ArcHashed        = @("LocalCache\Local\Arc\StorableSidebar.json", "LocalCache\Local\Arc\StorableArchiveItems.json")
$HeliumHashed     = @("Local State", "Default\Preferences")
# The copy switches, shared by the copy and by the restore commands in the manifest. Never /MIR, /PURGE or /MOV:
# each of those deletes files somewhere.
$CopyFlags        = @("/E", "/COPY:DAT", "/DCOPY:T", "/R:1", "/W:1", "/XJ", "/MT:8")

function Refuse([string]$Why, [string]$Todo) {
    Write-Host "REFUSED: $Why" -ForegroundColor Red
    Write-Host "What to do: $Todo"
    Write-Host "Nothing was copied."
    exit 1
}

# A full path from what was typed, relative to PowerShell's current folder (not .NET's, which can differ).
function Full([string]$Path) { $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path).TrimEnd('\') }

# Every file under $Root with its size and last-write time, counted the way robocopy /XJ copies: hidden and system
# files included, links (junctions, symbolic links) skipped rather than followed -- following one would count files
# that live outside the tree.
# The \\?\ prefix lets Windows PowerShell 5.1 read paths longer than 260 characters (Arc's package can have them).
# ponytail: any reparse point is skipped, as robocopy skips links; an exotic one (a cloud placeholder) that
# robocopy does copy would show up as a difference -- a false FAIL, never a false PASS.
function Listing([string]$Root) {
    $prefix = if ($Root.StartsWith('\\')) { $Root } else { '\\?\' + $Root }
    $map = @{}; $time = @{}; $bytes = [long]0
    $unreadable = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($prefix)
    while ($stack.Count) {
        $dir = $stack.Pop()
        try {
            foreach ($item in ([IO.DirectoryInfo]::new($dir)).EnumerateFileSystemInfos()) {
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($item -is [IO.DirectoryInfo]) { $stack.Push($item.FullName); continue }
                $rel = $item.FullName.Substring($prefix.Length + 1)
                $map[$rel] = $item.Length; $time[$rel] = $item.LastWriteTimeUtc.Ticks
                $bytes += $item.Length
            }
        } catch {
            $unreadable.Add($(if ($dir.Length -gt $prefix.Length) { $dir.Substring($prefix.Length + 1) } else { "." }))
        }
    }
    [pscustomobject]@{ Files = $map.Count; Bytes = $bytes; Map = $map; Time = $time; Unreadable = $unreadable }
}

function Sha([string]$Path) {
    try { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } catch { "" }
}

# The source's listing from before the copy ($Src) against the source listed again now and a fresh listing of the
# copy, plus the key files' hashes. A relative path is a difference when it changed in the source WHILE it was being
# copied (its size or last-write time moved, or it appeared or went: a browser wrote there, so the copy can be torn),
# or when it is missing, extra or a different size in the copy; so is a key file whose hash differs or that is
# missing (the files a restore needs most must be there). Source and copy compare sizes only: a FAT/exFAT drive
# keeps coarser times than NTFS. Changed = how many paths changed in the source during the copy.
function Compare-Copy($Src, [string]$SrcRoot, [string]$DstRoot, [string[]]$Hashed) {
    $now = Listing $SrcRoot
    $dst = Listing $DstRoot
    $diff = New-Object System.Collections.Generic.List[string]
    $changed = 0
    foreach ($k in $Src.Map.Keys) {
        $moved = -not $now.Map.ContainsKey($k) -or $now.Map[$k] -ne $Src.Map[$k] -or $now.Time[$k] -ne $Src.Time[$k]
        if ($moved) { $changed++ }
        if ($moved -or -not $dst.Map.ContainsKey($k) -or $dst.Map[$k] -ne $Src.Map[$k]) { $diff.Add($k) }
    }
    foreach ($k in $now.Map.Keys) { if (-not $Src.Map.ContainsKey($k)) { $changed++; $diff.Add($k) } }
    foreach ($k in $dst.Map.Keys) { if (-not $Src.Map.ContainsKey($k) -and -not $now.Map.ContainsKey($k)) { $diff.Add($k) } }
    foreach ($u in @($Src.Unreadable) + @($dst.Unreadable)) { $diff.Add("$u (a folder that could not be read)") }
    $hashes = @(foreach ($rel in $Hashed) {
        $a = Sha (Join-Path $SrcRoot $rel); $b = Sha (Join-Path $DstRoot $rel)
        if ((-not $a -or $a -ne $b) -and -not $diff.Contains($rel)) { $diff.Add($rel) }
        [pscustomobject]@{ Path = $rel; Source = $a; Copy = $b }
    })
    [pscustomobject]@{ Dst = $dst; Hashes = $hashes; Diff = $diff; Changed = $changed; Ok = ($diff.Count -eq 0) }
}

# Folder names under IndexedDB, Service Worker and the like are made from a site's address; shown as <site>.
function Hide-Site([string]$Rel) { (($Rel -split '\\') | ForEach-Object { if ($_ -match '^(?i)(https?|wss?|ftp)_') { "<site>" } else { $_ } }) -join '\' }

# Is a browser using source $s right now? Returns (why, what to do), or nothing. Run before the copy (a refusal) and
# again after it (a FAIL). Chromium keeps a 'lockfile' in a user-data folder only while a browser runs on it; Arc's
# is inside its package (LocalCache\Local\Arc\User Data), never at the package root, so $s.Locks names each place.
# With -ArcDir / -HeliumDir the process checks are skipped (the self-test runs while Arc is open); the lockfiles stay.
function Get-InUse($s) {
    if (-not $s.Override -and $s.Name -eq "arc") {
        if (Get-Process -Name Arc -ErrorAction SilentlyContinue) { return "Arc is running.", $s.Close }
    } elseif (-not $s.Override) {
        # Its install folder's chrome.exe, and whatever 'Last Browser' names (the fork writes it there if it was
        # ever started without --user-data-dir, so it cannot replace the install path, only add to it).
        $exes = @(Join-Path $env:ProgramFiles "imput\Helium\Application\chrome.exe")
        $lastBrowser = Join-Path $s.Dir "Last Browser"
        if (Test-Path -LiteralPath $lastBrowser) { $exes += [IO.File]::ReadAllText($lastBrowser, [Text.Encoding]::Unicode).Trim([char[]](0, 9, 10, 13, 32)) }
        $running = @(Get-Process -Name chrome -ErrorAction SilentlyContinue | Where-Object { $exes -contains $_.Path })
        if ($running.Count) { return "official Helium is running ($($running[0].Path)).", $s.Close }
    }
    foreach ($l in $s.Locks) {
        if (Test-Path -LiteralPath (Join-Path $s.Dir $l)) { return "a browser is using $($s.Dir) right now (its '$l' exists).", $s.Close }
    }
}

# A path as a PowerShell single-quoted string, for the restore commands in the manifest.
function Quote([string]$Text) { "'" + $Text.Replace("'", "''") + "'" }

function Invoke-SelfTest {
    $root     = Join-Path $env:TEMP ("backup-browsers-selftest-" + (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    $arcSrc   = Join-Path $root "arc-src"
    $helSrc   = Join-Path $root "helium-src"
    $outside  = Join-Path $root "outside"
    $junction = Join-Path $arcSrc "LocalCache\link-to-outside"
    $shell    = (Get-Process -Id $PID).Path
    function Put([string]$Path, [string]$Text) { [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)); [IO.File]::WriteAllText($Path, $Text) }
    function Check([bool]$Ok, [string]$What) { if (-not $Ok) { throw "selftest assertion failed: $What" } }
    # This script again, in its own process with the same PowerShell, exactly as the owner would run it.
    function Run([string[]]$Argv) {
        $ErrorActionPreference = "Continue"
        $out = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @Argv 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE; $global:LASTEXITCODE = 0
        [pscustomobject]@{ Out = $out; Code = $code }
    }
    $failed = ""
    try {
        Write-Host "Self-test: building two small throwaway browser folders in $root"
        foreach ($f in $ArcHashed + @("LocalCache\Local\Arc\User Data\Default\deep\nested\page.bin", "Settings\a file with spaces.txt", "LocalState\read-only.txt", "LocalState\hidden.txt")) { Put (Join-Path $arcSrc $f) "arc $f" }
        foreach ($f in $HeliumHashed + @("Default\IndexedDB\https_example.org_0.indexeddb.leveldb\000003.log")) { Put (Join-Path $helSrc $f) "helium $f" }
        [IO.File]::SetAttributes((Join-Path $arcSrc "LocalState\read-only.txt"), "ReadOnly")
        [IO.File]::SetAttributes((Join-Path $arcSrc "LocalState\hidden.txt"), "Hidden")
        [void][IO.Directory]::CreateDirectory((Join-Path $arcSrc "TempState\empty"))
        Put (Join-Path $outside "outside-marker.txt") "must never be copied"
        [void](New-Item -ItemType Junction -Path $junction -Target $outside)

        Write-Host "Self-test: backing them up (a child run of this script)"
        $r = Run @("-Dest", (Join-Path $root "dest"), "-ArcDir", $arcSrc, "-HeliumDir", $helSrc)
        $last = if ($r.Out.Count) { $r.Out[-1] } else { "" }
        if ($r.Code -ne 0) { $r.Out | ForEach-Object { Write-Host "    | $_" } }
        Check ($r.Code -eq 0) "the backup exits 0 (it exited $($r.Code))"
        Check ($last -match '^RESULT backup=(.+) verdict=PASS$') "the last line is 'RESULT backup=... verdict=PASS' (it is '$last')"
        $bk = $Matches[1]
        Check ($bk.StartsWith((Join-Path $root "dest\"))) "the backup folder is inside the -Dest given"
        foreach ($f in "arc\LocalCache\Local\Arc\User Data\Default\deep\nested\page.bin", "arc\Settings\a file with spaces.txt", "arc\LocalState\read-only.txt", "arc\LocalState\hidden.txt", "helium-user-data\Default\Preferences", "manifest.txt", "robocopy-arc.log", "robocopy-helium.log") {
            Check (Test-Path -LiteralPath (Join-Path $bk $f) -PathType Leaf) "the copy holds $f"
        }
        Check (Test-Path -LiteralPath (Join-Path $bk "arc\TempState\empty") -PathType Container) "the empty folder is copied"
        Check (-not (Test-Path -LiteralPath (Join-Path $bk "arc\LocalCache\link-to-outside\outside-marker.txt"))) "the junction's target is NOT copied"
        Check ((Select-String -LiteralPath (Join-Path $bk "manifest.txt") -SimpleMatch "verdict: PASS" -Quiet) -eq $true) "manifest.txt says 'verdict: PASS'"
        Check ((Hide-Site "Default\IndexedDB\https_example.org_0.indexeddb.leveldb\000003.log") -eq "Default\IndexedDB\<site>\000003.log") "a folder named after a website is shown as <site>"

        Write-Host "Self-test: changing one byte of the copied Local State; the check must now FAIL"
        $ls = Join-Path $bk "helium-user-data\Local State"
        $bytes = [IO.File]::ReadAllBytes($ls); $bytes[0] = $bytes[0] -bxor 1; [IO.File]::WriteAllBytes($ls, $bytes)
        $c = Compare-Copy (Listing $helSrc) $helSrc (Join-Path $bk "helium-user-data") $HeliumHashed
        Check (-not $c.Ok) "a one-byte change in a copied key file fails the check"
        Check ($c.Diff.Contains("Local State")) "the failed check names 'Local State'"

        Write-Host "Self-test: a file rewritten in the original during the copy (same size) and a new one must FAIL the check"
        $before = Listing $helSrc
        [IO.File]::SetLastWriteTimeUtc((Join-Path $helSrc "Default\Preferences"), [datetime]::UtcNow.AddMinutes(1))
        Put (Join-Path $helSrc "Default\History-journal") ""
        $c = Compare-Copy $before $helSrc (Join-Path $bk "helium-user-data") @()
        Check (-not $c.Ok -and $c.Changed -eq 2) "the check fails with 2 files changed during the copy (it counted $($c.Changed))"
        Check ($c.Diff.Contains("Default\Preferences") -and $c.Diff.Contains("Default\History-journal")) "the failed check names both files"

        Write-Host "Self-test: a lockfile in the source (a browser using it) must be refused"
        Put (Join-Path $helSrc "lockfile") ""
        $dest2 = Join-Path $root "dest2"
        $r = Run @("-Dest", $dest2, "-Only", "helium", "-HeliumDir", $helSrc)
        Check ($r.Code -eq 1) "a source in use exits 1 (it exited $($r.Code))"
        Check (-not ($r.Out -match '^RESULT ')) "a refusal prints no RESULT line"
        Check (-not (Test-Path -LiteralPath $dest2)) "a refusal creates no backup folder"
        Put (Join-Path $arcSrc "LocalCache\Local\Arc\User Data\lockfile") ""
        $r = Run @("-Dest", $dest2, "-Only", "arc", "-ArcDir", $arcSrc)
        Check ($r.Code -eq 1 -and -not (Test-Path -LiteralPath $dest2)) "Arc's own lockfile deep in its package is refused too (it exited $($r.Code))"

        Write-Host "Self-test: the manifest's restore lines put each copy back, the newer files renamed aside, not mixed in"
        $lines = [IO.File]::ReadAllLines((Join-Path $bk "manifest.txt"))
        $restores = @(for ($i = 0; $i -lt $lines.Count - 1; $i++) { if ($lines[$i].StartsWith("restore")) { $lines[$i + 1].Trim() } })
        Check ($restores.Count -eq 2) "manifest.txt holds two restore lines (it holds $($restores.Count))"
        foreach ($cmd in $restores) { & { $ErrorActionPreference = "Continue"; $null = & $shell -NoProfile -Command $cmd 2>&1 }; $global:LASTEXITCODE = 0 }
        $helCopy = Join-Path $bk "helium-user-data"
        $c = Compare-Copy (Listing $helCopy) $helCopy $helSrc @()
        Check $c.Ok "the restored Helium folder equals its copy, with no newer file left in it ($($c.Diff.Count) difference(s))"
        $aside = @(Get-ChildItem -LiteralPath $root -Directory -Filter "helium-src.before-restore-*")
        Check ($aside.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $aside[0].FullName "lockfile"))) "the newer Helium folder was renamed aside, whole"
        $arcCopy = Join-Path $bk "arc"
        $c = Compare-Copy (Listing $arcCopy) $arcCopy $arcSrc @()
        $left = @($c.Diff | Where-Object { -not $_.StartsWith("LocalCache\Local.before-restore-") })
        Check ($left.Count -eq 0) "the restored Arc folder equals its copy apart from the renamed-aside folder ($($left.Count) difference(s))"
        $aside = @(Get-ChildItem -LiteralPath (Join-Path $arcSrc "LocalCache") -Directory -Filter "Local.before-restore-*")
        Check ($aside.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $aside[0].FullName "Arc\User Data\lockfile"))) "Arc's newer LocalCache\Local was renamed aside, whole"
    } catch {
        $failed = $_.Exception.Message
    } finally {
        # Remove the link first, on its own, so no delete can walk through it; then only the self-test's own folder.
        if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
    if ($failed) { Write-Host $failed -ForegroundColor Red; Write-Host "backup-browsers selftest: FAIL"; exit 1 }
    Write-Host "backup-browsers selftest: PASS"
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

# ---- 1. What to back up, and may it be copied now? ----
$sources = @()
if ($Only -ne "helium") {
    # Aside: what a restore renames out of the way first. Arc's own data is all in LocalCache\Local; the package's
    # other folders carry Windows' own permissions, which robocopy /COPY:DAT would not recreate, so they stay put.
    $sources += [pscustomobject]@{ Name = "arc"; Label = "Arc"; Folder = "arc"; Flag = "-ArcDir"; Other = "helium"; Override = [bool]$ArcDir
        Dir = (Full $(if ($ArcDir) { $ArcDir } else { $DefaultArcDir })); Hashed = $ArcHashed; Listing = $null; Robocopy = $null; Result = $null
        Locks = @("lockfile", "LocalCache\Local\Arc\User Data\lockfile"); Aside = "LocalCache\Local"
        Close = "Quit Arc completely (Ctrl+Q, or right-click Arc in the taskbar and choose Quit), wait a few seconds, then run this again. Or add -Only helium to back up official Helium alone." }
}
if ($Only -ne "arc") {
    $sources += [pscustomobject]@{ Name = "helium"; Label = "official Helium"; Folder = "helium-user-data"; Flag = "-HeliumDir"; Other = "arc"; Override = [bool]$HeliumDir
        Dir = (Full $(if ($HeliumDir) { $HeliumDir } else { $DefaultHeliumDir })); Hashed = $HeliumHashed; Listing = $null; Robocopy = $null; Result = $null
        Locks = @("lockfile"); Aside = ""
        # Its lockfile also catches the fork opened without --user-data-dir, which uses this same profile.
        Close = "Close every Helium window (and the fork, if it is open), wait a few seconds, then run this again. Or add -Only arc to back up Arc alone." }
}
foreach ($s in $sources) {
    if (-not (Test-Path -LiteralPath $s.Dir -PathType Container)) {
        Refuse "$($s.Label)'s folder was not found: $($s.Dir)" "If it lives somewhere else, pass $($s.Flag) <that folder>. To back up only the other browser, add -Only $($s.Other)."
    }
}
# A browser rewrites its files while it runs, so a copy taken then can be half-written and useless.
foreach ($s in $sources) {
    $inUse = Get-InUse $s
    if ($inUse) { Refuse $inUse[0] $inUse[1] }
}
$destRoot = Full $Dest
$backup = Join-Path $destRoot (Get-Date -Format "yyyy-MM-dd_HHmmss")
if (Test-Path -LiteralPath $backup) {
    Refuse "the backup folder $backup already exists." "Wait a second and run this again: each backup gets its own new folder, and an older backup is never written into."
}
$total = [long]0
foreach ($s in $sources) {
    Write-Host "Counting $($s.Label)'s files in $($s.Dir) ..."
    $s.Listing = Listing $s.Dir
    $total += $s.Listing.Bytes
    Write-Host ("  {0:N0} files, {1:N2} GB" -f $s.Listing.Files, ($s.Listing.Bytes / 1GB))
}
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($destRoot))
if ($drive.AvailableFreeSpace -lt 1.2 * $total) {
    Refuse ("drive {0} has {1:N1} GB free; the copy needs {2:N1} GB plus a 20% margin." -f $drive.Name, ($drive.AvailableFreeSpace / 1GB), ($total / 1GB)) "Free up space on that drive, or pass -Dest <a folder on a drive with more room>."
}

# ---- 2. Copy, then check each copy against its source ----
[void][IO.Directory]::CreateDirectory($backup)
Write-Host "Backing up into $backup"
$ok = $true
foreach ($s in $sources) {
    $dst = Join-Path $backup $s.Folder
    Write-Host ("Copying {0} ({1:N2} GB). This can take several minutes; nothing is shown until it ends." -f $s.Label, ($s.Listing.Bytes / 1GB))
    $null = robocopy $s.Dir $dst @CopyFlags /NP /NFL /NDL "/LOG:$(Join-Path $backup "robocopy-$($s.Name).log")"
    $s.Robocopy = $LASTEXITCODE
    # robocopy's success codes 1-7 would otherwise leak out as this script's exit code.
    $global:LASTEXITCODE = 0
    Write-Host "  robocopy finished with code $($s.Robocopy) (0 to 7 mean copied; 8 or more means some files failed)."
    Write-Host "Checking the copy of $($s.Label) against the original ..."
    $s.Result = Compare-Copy $s.Listing $s.Dir $dst $s.Hashed
    # Checked again now: a browser started during the copy may have rewritten files after robocopy had read them.
    $inUse = Get-InUse $s
    if ($inUse) { $s.Result.Diff.Insert(0, "(when the copy ended: $($inUse[0]))"); $s.Result.Ok = $false }
    Write-Host ("  original: {0:N0} files, {1:N0} bytes; copy: {2:N0} files, {3:N0} bytes" -f $s.Listing.Files, $s.Listing.Bytes, $s.Result.Dst.Files, $s.Result.Dst.Bytes)
    foreach ($h in $s.Result.Hashes) { Write-Host "  SHA-256 of $($h.Path): $(if (-not $h.Source) { 'MISSING in the original' } elseif ($h.Source -eq $h.Copy) { 'same' } else { 'DIFFERENT' })" }
    if ($s.Robocopy -ge 8) { $ok = $false; Write-Host "  robocopy reports files it could not copy: see $(Join-Path $backup "robocopy-$($s.Name).log")" -ForegroundColor Red }
    if ($s.Result.Ok) { Write-Host "  The copy matches the original." -ForegroundColor Green }
    else {
        $ok = $false
        Write-Host "  The copy does NOT match: $($s.Result.Diff.Count) difference(s). The first ones:" -ForegroundColor Red
        $s.Result.Diff | Select-Object -First 20 | ForEach-Object { Write-Host "    $(Hide-Site $_)" }
        if ($s.Result.Changed) { Write-Host "  $($s.Result.Changed) of them changed in the original WHILE it was being copied: a browser (or another program) was writing there." -ForegroundColor Red }
    }
}
$verdict = if ($ok) { "PASS" } else { "FAIL" }

# ---- 3. manifest.txt: what was copied, the numbers, and how to put it back ----
$m = New-Object System.Collections.Generic.List[string]
$m.Add("Backup made by backup-browsers.ps1")
$m.Add("time: $((Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz'))")
$m.Add("backup folder: $backup")
$m.Add("verdict: $verdict")
foreach ($s in $sources) {
    $dst = Join-Path $backup $s.Folder
    $m.Add("")
    $m.Add("[$($s.Folder)]")
    $m.Add("source: $($s.Dir)")
    $m.Add("copy: $dst")
    $m.Add("robocopy exit code: $($s.Robocopy) (0-7 copied, 8+ failed)")
    $m.Add("files: source $($s.Listing.Files), copy $($s.Result.Dst.Files)")
    $m.Add("bytes: source $($s.Listing.Bytes), copy $($s.Result.Dst.Bytes)")
    foreach ($h in $s.Result.Hashes) { $m.Add("sha256 $($h.Path): source $($h.Source), copy $($h.Copy)") }
    $m.Add("differences: $($s.Result.Diff.Count) (changed in the original during the copy: $($s.Result.Changed))")
    $s.Result.Diff | Select-Object -First 20 | ForEach-Object { $m.Add("  $(Hide-Site $_)") }
    # Copying over the current folder would leave every newer file beside the restored ones (a LevelDB replays its
    # newer logs onto the old tables): a mix of two dates. So the current folder is renamed aside first -- nothing is
    # deleted -- and the rename fails while a browser holds a file in it, which stops the line before any copy.
    $aside = if ($s.Aside) { Join-Path $s.Dir $s.Aside } else { $s.Dir }
    $leaf = Split-Path $aside -Leaf
    $m.Add("restore ($($s.Label) CLOSED first). It renames $aside to $leaf.before-restore-<time> (nothing is deleted), then copies the backup back. One line in PowerShell:")
    $m.Add("  if (Test-Path -LiteralPath $(Quote $aside)) { Rename-Item -LiteralPath $(Quote $aside) -NewName ($(Quote "$leaf.before-restore-") + (Get-Date -Format yyyyMMdd-HHmmss)) -ErrorAction Stop }; robocopy $(Quote $dst) $(Quote $s.Dir) $($CopyFlags -join ' ')")
}
[IO.File]::WriteAllLines((Join-Path $backup "manifest.txt"), $m)

Write-Host ""
if ($ok) {
    Write-Host "Backup finished and verified. Keep $backup until you are sure you will not need to go back." -ForegroundColor Green
    Write-Host "manifest.txt in that folder has the numbers and the one-line command that restores each copy."
} else {
    Write-Host "The backup did NOT verify. The copy is kept at $backup (nothing was deleted)." -ForegroundColor Red
    Write-Host "Read the differences above and the robocopy-*.log files there. The usual cause is a browser (or another program) using those files during the copy: close it and run this again (each run makes a new folder)."
}
Write-Host "RESULT backup=$backup verdict=$verdict"
exit $(if ($ok) { 0 } else { 1 })
