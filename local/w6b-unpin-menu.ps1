param([string]$Profile, [int]$BrowserPid, [string]$Button = "Copy link - pinned")
# Wish 6b, check step 7c: "Unpin" chosen from a Chrome button's OWN right-click menu while the button lives in the
# toolbar (the review's high finding: the button, which owns that menu, was freed under it). The menu is opened by a
# right-click POSTED to the window (no real mouse, the window need not be in front) and "Unpin" is pressed through
# MSAA, as repro-e191.ps1 does for the tab menu. A pinned button's MSAA name ends " - pinned". Prints one line; exit 0 when both were sent.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File w6b-unpin-menu.ps1 -Profile <dir> -BrowserPid <pid>
$here = $PSScriptRoot
$win = (Get-Process -Id $BrowserPid -ErrorAction SilentlyContinue).MainWindowHandle
if (-not $win -or $win -eq [IntPtr]::Zero) { "no browser window"; exit 1 }
if (-not ("PostRC" -as [type])) { Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class PostRC {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
  public static string RightClick(IntPtr h, int sx, int sy) {
    SetThreadDpiAwarenessContext(new IntPtr(-4));
    POINT p; p.x = sx; p.y = sy; ScreenToClient(h, ref p);
    IntPtr l = new IntPtr((p.y << 16) | (p.x & 0xFFFF));
    PostMessage(h, 0x0200, IntPtr.Zero, l);    // WM_MOUSEMOVE
    PostMessage(h, 0x0204, new IntPtr(2), l);  // WM_RBUTTONDOWN, MK_RBUTTON
    PostMessage(h, 0x0205, IntPtr.Zero, l);    // WM_RBUTTONUP
    return "right-click posted at " + p.x + "," + p.y;
  }
}
"@ }
function Msaa([object[]]$a) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$here\msaa-press.ps1" -Profile $Profile -Window ([long]$win) @a }
$rect = $null
foreach ($r in @(Msaa @("-List", "-Rect"))) {
    if ($r -match "^\s*$([regex]::Escape($Button))\|0x2B\|@(-?\d+),(-?\d+),(\d+),(\d+)$") {
        $rect = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]); break
    }
}
if (-not $rect) { "no '$Button' push button in the window"; exit 1 }
$posted = [PostRC]::RightClick($win, $rect[0] + [int]($rect[2] / 2), $rect[1] + [int]($rect[3] / 2))
Start-Sleep 2
$pressed = Msaa @("-Popup", "-Name", "Unpin")
"$posted; Unpin: $($pressed -join ' ')"
exit 0
