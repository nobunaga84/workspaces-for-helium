param([Parameter(Mandatory = $true)][string]$Chunk, [ValidateSet("Default", "Dcheck")][string]$OutDir = "Default")
# After a rebase's builds (LOCAL.md 7): the hands-free checks of E14d-E16 against one output dir. Each script
# runs in its OWN pwsh process -- two in one process share the first's Input type (memory) -- with its own
# transcript, $Chunk-<name>-auto[-dcheck].txt in <local-path>\Helium-workspace, and prints one verdict line. Needs the
# screen unlocked and nobody at the mouse: e15d3 and e16 drag with the real one (guarded; a lock or an overlay
# makes their steps FAIL, not misclick). e14d2/e14d3 have no -Tag and reuse their fixed log names.
$pwsh = "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe"
$sfx  = if ($OutDir -eq "Dcheck") { "-dcheck" } else { "" }
foreach ($n in "e14d1", "e14d2", "e14d3", "e15c", "e15c1", "e15d3", "e15e", "e16") {
  # @() keeps a one-item list a list: a bare switch hands "-Dcheck" back as a plain string, and splatting
  # a string passes its CHARACTERS -- e14d3 ran Default under a -dcheck transcript name (R5, LOCAL.md 59).
  $a = @(switch ($n) {
    "e14d2" { "-OutDir", $OutDir }
    "e14d3" { if ($OutDir -eq "Dcheck") { "-Dcheck" } }
    default { "-OutDir", $OutDir, "-Tag", "$Chunk-$n-auto$sfx" }
  })
  $out = "<local-path>\Helium-workspace\$Chunk-$n-auto$sfx.txt"
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\check-$n-auto.ps1" @a *>&1 | Out-File $out -Encoding utf8
  $v = Select-String -Path $out -Pattern "ALL PASS|FAIL|ABORT|VOID" | Select-Object -Last 1
  "{0,-6} {1,-8} exit {2,-3} {3}" -f $n, $OutDir, $LASTEXITCODE, $(if ($v) { $v.Line.Trim() } else { "(no verdict line)" })
}
