$ws    = "<local-path>\Helium-workspace"
$check = "$ws\helium\local\check-phase2.ps1"
$feed  = "$ws\p2-driver-feed.txt"
$out   = "$ws\p2-driver-out.txt"
$dir   = "$env:LOCALAPPDATA\Programs\Helium Workspaces"
$prof  = "$env:LOCALAPPDATA\Helium Workspaces\User Data"
$exe   = "$dir\chrome.exe"
$lnk   = [Environment]::GetFolderPath('Programs') + "\Workspaces for Helium.lnk"
$html  = "$ws\dist\phase2-test.html"
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public static class Nsis {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EnumProc f, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetDlgItem(IntPtr h, int id);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static IntPtr Find(string suffix) {
    IntPtr found = IntPtr.Zero;
    EnumWindows((h, l) => { var s = new StringBuilder(256); GetWindowText(h, s, 256); var t = s.ToString().Trim();
      if (IsWindowVisible(h) && t.StartsWith("Workspaces for Helium") && t.EndsWith(suffix)) { found = h; return false; } return true; }, IntPtr.Zero);
    return found;
  }
  // Button 1 is NSIS's Next / I Agree / Install / Uninstall / Finish / Close; WM_COMMAND is what its click sends.
  public static bool Next(IntPtr dlg) { var b = GetDlgItem(dlg, 1); if (b == IntPtr.Zero || !IsWindowEnabled(b) || !IsWindowVisible(b)) return false;
    return PostMessage(dlg, 0x0111, (IntPtr)1, b); }
  // The components tree: select the 2nd item and press Space, which NSIS's tree takes as a tick.
  public static void Cancel(IntPtr dlg) { PostMessage(dlg, 0x0111, (IntPtr)2, IntPtr.Zero); }
  public static bool TickSecond(IntPtr dlg) {
    IntPtr tree = IntPtr.Zero;
    EnumChildWindows(dlg, (h, l) => { var s = new StringBuilder(64); GetClassName(h, s, 64); if (s.ToString() == "SysTreeView32") { tree = h; return false; } return true; }, IntPtr.Zero);
    if (tree == IntPtr.Zero) return false;
    var root = SendMessage(tree, 0x110A, IntPtr.Zero, IntPtr.Zero);
    var second = SendMessage(tree, 0x110A, (IntPtr)1, root);
    if (second == IntPtr.Zero) return false;
    SendMessage(tree, 0x110B, (IntPtr)9, second);
    SendMessage(tree, 0x0100, (IntPtr)0x20, IntPtr.Zero);
    SendMessage(tree, 0x0101, (IntPtr)0x20, IntPtr.Zero);
    return true;
  }
}
"@
function Say($s) { Write-Host "$(Get-Date -Format HH:mm:ss) driver: $s" }
function Answer($s) { Add-Content -LiteralPath $feed -Value $s; Say "answered '$s'"; Start-Sleep 3 }
function Pids { @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$prof*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId }) }
function WaitFor([scriptblock]$cond, [int]$sec = 120) { $t = Get-Date; while (-not (& $cond) -and ((Get-Date) - $t).TotalSeconds -lt $sec) { Start-Sleep 1 }; & $cond }
function CloseBrowser { foreach ($id in Pids) { $null = (Get-Process -Id $id -EA SilentlyContinue).CloseMainWindow() }; $null = WaitFor { (Pids).Count -eq 0 } 60; Start-Sleep 2 }
function ClickThrough([string]$suffix, [switch]$Tick) {
  $w = [IntPtr]::Zero; $null = WaitFor { $script:w = [Nsis]::Find($suffix); $script:w -ne [IntPtr]::Zero } 120
  if ($script:w -eq [IntPtr]::Zero) { Say "NO '$suffix' window"; return }
  Start-Sleep 2
  if ($Tick) { Say "tick: $([Nsis]::TickSecond($script:w))"; Start-Sleep 1 }
  $t = Get-Date
  while (([Nsis]::Find($suffix) -ne [IntPtr]::Zero) -and ((Get-Date) - $t).TotalMinutes -lt 10) { if ([Nsis]::Next($script:w)) { Say "next ($suffix)" }; Start-Sleep 3 }
}

Remove-Item $feed, $out -EA SilentlyContinue
New-Item -ItemType File $feed | Out-Null
$runner = "$ws\p2-driver-run.ps1"
Set-Content -LiteralPath $runner -Value "Get-Content -Wait -LiteralPath '$feed' | pwsh -NoProfile -File '$check' *> '$out'"
$child = Start-Process pwsh -ArgumentList @("-NoProfile", "-File", $runner) -WindowStyle Hidden -PassThru
Say "check started (pid $($child.Id))"
ClickThrough " Setup";                                                      Answer "y"   # 1
Invoke-Item $lnk; $null = WaitFor { (Pids).Count -ge 1 } 60; Start-Sleep 15; Say "opened: $((Pids).Count)"; Answer "y"   # 2
CloseBrowser; Invoke-Item $lnk; $null = WaitFor { (Pids).Count -ge 1 } 60; Start-Sleep 10; Answer "y"   # 3 (a pin opens the shortcut)
$null = WaitFor { Test-Path $html } 60
Start-Process $exe -ArgumentList @("--user-data-dir=`"$prof`"", "--single-argument", "`"$html`"") | Out-Null; Start-Sleep 10; Answer "y"   # 4
Answer "y"                                                                                   # 5
CloseBrowser; ClickThrough " Uninstall";                                                     Answer "y"   # 6
# 7: a sent Space does not tick NSIS's box (p2-tick.ps1): cancel the screen, tick by /DELETEDATA instead
$null = WaitFor { $script:w = [Nsis]::Find(" Uninstall"); $script:w -ne [IntPtr]::Zero } 120; Start-Sleep 2; [Nsis]::Cancel($script:w); Start-Sleep 3
Start-Process "$dir\uninstall.exe" -ArgumentList @("/S", "/DELETEDATA") -Wait; Say "uninstalled /S /DELETEDATA"; Answer "y"
Answer "driver run, not the owner"                                                           # comment
$null = WaitFor { Select-String -LiteralPath $out -Pattern "ALL PASS|FAIL\(s\)|ABORT" -Quiet } 60
Stop-Process -Id $child.Id -EA SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='pwsh.exe'" | Where-Object { $_.CommandLine -like "*check-phase2.ps1*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }
Say "done"
