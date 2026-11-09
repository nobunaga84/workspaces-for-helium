param([int]$BuildPid)
# Waits for dev-build.ps1's quilt prompt (LOCAL.md 7, 59). The prompt is invisible through a pipe --
# PYTHONUNBUFFERED does not change that -- so the signal is build.py (-BuildPid: the python running
# 'build.py --dev') alive with no child process and no CPU for 90 s, the input() wait. One line, then exit.
$idle = 0
while ($true) {
  $p = Get-Process -Id $BuildPid -ErrorAction SilentlyContinue
  if (-not $p) { "BUILD.PY EXITED (dev-build ended - read the owner's window)"; exit 0 }
  $c1 = $p.CPU
  Start-Sleep 30
  $p.Refresh()
  $kids = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$BuildPid")
  if ($kids.Count -eq 0 -and ($p.CPU - $c1) -lt 0.05) { $idle++ } else { $idle = 0 }
  if ($idle -ge 3) { "PROMPT: build.py idle, no child process, for 90 s"; exit 0 }
}
