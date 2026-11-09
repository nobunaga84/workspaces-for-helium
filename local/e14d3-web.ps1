param([string]$Profile, [long]$Window = 0, [string]$Name, [int]$Role = 0, [switch]$Focus, [int]$MaxDepth = 80)
# msaa-press.ps1's walk, but INTO web pages (msaa-press stops at a document, 0xF): prints each node named
# -Name (of -Role, when given) as "name|0xROLE|0xSTATE|@left,top,width,height|value". -Focus gives the first
# one not INVISIBLE the keyboard focus -- accSelect(SELFLAG_TAKEFOCUS), which Chromium turns into kFocus
# (ax_platform_node_win.cc accSelect) and which focuses the page's view too (browser_accessibility_manager.cc
# SetFocus) -- and prints "focused: 0xSTATE" read again after it (STATE_SYSTEM_FOCUSED is 0x4). For
# check-e14d3-auto.ps1 row E: the settings page's "Archive tabs after" dropdown, a <select> (0x2E, a combo
# box) inside the page. Windows PowerShell 5.1; run it in its own process, as msaa-press.ps1 is. A node leaves C#
# as System.__ComObject, which PowerShell cannot convert back to IAccessible (it never QueryInterfaces: run 1 of
# the first -Dcheck run threw "Cannot convert argument k"), so what PowerShell hands back is an object, cast in C#.
Add-Type -AssemblyName Accessibility
if (-not ("E14d3Web" -as [type])) {
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Accessibility;
public static class E14d3Web {
  [DllImport("oleacc.dll")]
  static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid,
      [MarshalAs(UnmanagedType.IUnknown)] out object obj);
  [DllImport("oleacc.dll")]
  static extern int AccessibleChildren(IAccessible parent, int start, int count,
      [Out] object[] children, out int obtained);

  static void Walk(IAccessible acc, int depth, int maxDepth, string name, int role, List<IAccessible> hits) {
    if (depth > maxDepth) return;
    int n = 0;
    try { n = acc.accChildCount; } catch { return; }
    if (n <= 0) return;
    object[] kids = new object[n];
    int got;
    if (AccessibleChildren(acc, 0, n, kids, out got) != 0) return;
    for (int i = 0; i < got; i++) {
      IAccessible k = kids[i] as IAccessible;
      if (k == null) continue;
      string nm = null; int r = 0;
      try { nm = k.get_accName(0); } catch {}
      try { r = Convert.ToInt32(k.get_accRole(0)); } catch {}
      if (nm == name && (role == 0 || r == role)) hits.Add(k);
      Walk(k, depth + 1, maxDepth, name, role, hits);
    }
  }

  public static object[] Find(IntPtr hwnd, string name, int role, int maxDepth) {
    Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
    object obj;
    AccessibleObjectFromWindow(hwnd, 0xFFFFFFFC, ref iid, out obj);  // OBJID_CLIENT
    List<IAccessible> hits = new List<IAccessible>();
    Walk((IAccessible)obj, 0, maxDepth, name, role, hits);
    return hits.ToArray();
  }

  public static int State(object o) { try { return Convert.ToInt32(((IAccessible)o).get_accState(0)); } catch { return 0; } }

  public static string Describe(object o) {
    IAccessible k = (IAccessible)o;
    string nm = null, value = null; int r = 0, l = 0, t = 0, w = 0, h = 0;
    try { nm = k.get_accName(0); } catch {}
    try { r = Convert.ToInt32(k.get_accRole(0)); } catch {}
    try { value = k.get_accValue(0); } catch {}
    try { k.accLocation(out l, out t, out w, out h, 0); } catch {}
    return nm + "|0x" + r.ToString("X") + "|0x" + State(k).ToString("X") + "|@" + l + "," + t + "," + w + "," + h + "|" + value;
  }

  public static void TakeFocus(object o) { ((IAccessible)o).accSelect(1, 0); }  // SELFLAG_TAKEFOCUS, CHILDID_SELF
}
"@
}
$browserPid = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -OperationTimeoutSec 15 | Where-Object { $_.CommandLine -like "*$Profile*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId })
if ($browserPid.Count -ne 1) { "WEB: expected one browser process for $Profile, found $($browserPid.Count)"; exit 2 }
$hwnd = if ($Window) { [IntPtr]$Window } else { (Get-Process -Id $browserPid[0]).MainWindowHandle }
if ($hwnd -eq [IntPtr]::Zero) { "WEB: the browser has no main window"; exit 2 }
$hits = @([E14d3Web]::Find($hwnd, $Name, $Role, $MaxDepth))
if (-not $hits.Count) { "WEB: no node named '$Name' (role 0x" + $Role.ToString("X") + ")"; exit 3 }
$hits | ForEach-Object { [E14d3Web]::Describe($_) }
if ($Focus) {
    $shown = @($hits | Where-Object { ([E14d3Web]::State($_) -band 0x8000) -eq 0 }) | Select-Object -First 1
    if (-not $shown) { "WEB: every match is INVISIBLE"; exit 3 }
    [E14d3Web]::TakeFocus($shown)
    Start-Sleep -Milliseconds 700
    "focused: 0x" + [E14d3Web]::State($shown).ToString("X")
}
