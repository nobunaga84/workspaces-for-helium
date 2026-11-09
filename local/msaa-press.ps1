param([string]$Profile, [string]$Name, [int]$Role = 0, [int]$Nth = 0, [switch]$List, [int]$MaxDepth = 40, [switch]$Where, [switch]$Rect, [switch]$Popup, [long]$Window = 0, [switch]$Desc, [switch]$States, [switch]$Expand, [switch]$Values)
# Presses a fork view by its accessible name through MSAA's accDoDefaultAction -- what a screen reader does;
# no mouse, no keyboard, nothing sent to the window in front. Roles (MSAA): 0x24 outline item (a pinned row),
# 0x2B push button, 0x25 page tab. -List prints name|role of every node down to -MaxDepth (-Where adds where
# it is drawn); web pages (0xF, document) are not entered -- and a press on a web link that opens a new tab
# opens nothing (E15c.1). Windows PowerShell 5.1; the walk is C#, where the COM cast works.
Add-Type -AssemblyName Accessibility
if (-not ("MsaaWalk" -as [type])) {
Add-Type -ReferencedAssemblies Accessibility -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Accessibility;
public static class MsaaWalk {
  public static bool Where = false;
  public static bool Rect = false;
  public static bool Desc = false;
  public static bool States = false;
  public static bool Expand = false;
  public static bool Values = false;
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  // The top shown window of the process other than its main one: an open menu (E15d.3).
  public static IntPtr PopupOf(uint pid, IntPtr main) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate (IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p == pid && h != main && IsWindowVisible(h)) { found = h; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }
  [DllImport("oleacc.dll")]
  static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint id, ref Guid iid,
      [MarshalAs(UnmanagedType.IUnknown)] out object obj);
  [DllImport("oleacc.dll")]
  static extern int AccessibleChildren(IAccessible parent, int start, int count,
      [Out] object[] children, out int obtained);

  static IAccessible Root(IntPtr hwnd) {
    Guid iid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
    object obj;
    AccessibleObjectFromWindow(hwnd, 0xFFFFFFFC, ref iid, out obj);  // OBJID_CLIENT
    return (IAccessible)obj;
  }

  static void Walk(IAccessible acc, int depth, int maxDepth, List<KeyValuePair<IAccessible, string>> all) {
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
      string name = null; int role = 0; int state = 0;
      try { name = k.get_accName(0); } catch {}
      try { role = Convert.ToInt32(k.get_accRole(0)); } catch {}
      try { state = Convert.ToInt32(k.get_accState(0)); } catch {}
      // STATE_SYSTEM_INVISIBLE: a view that exists but is not shown.
      string where = "";
      if (Where || Rect) {
        int l = 0, t = 0, w = 0, h = 0;
        try { k.accLocation(out l, out t, out w, out h, 0); } catch {}
        where = Rect ? "|@" + l + "," + t + "," + w + "," + h : "|@" + t + "," + h;
      }
      if (Desc) { string d = null; try { d = k.get_accDescription(0); } catch {} where += "|desc=" + (d ?? "").Replace("\r", "").Replace("\n", " / "); }
      string value = "";
      if (Values) { string v = null; try { v = k.get_accValue(0); } catch {} value = ((state & 0x18) != 0 ? "|CHECKED" : "") + "|=" + (v ?? ""); }
      all.Add(new KeyValuePair<IAccessible, string>(k, new string(' ', 2 * Math.Min(depth, 12)) + name + "|0x" + role.ToString("X") + ((state & 0x8000) != 0 ? "|INVISIBLE" : "") + where + (States && (state & 0x2) != 0 ? "|SELECTED" : "") + (States && (state & 0x1) != 0 ? "|UNAVAILABLE" : "") + (Expand && (state & 0x200) != 0 ? "|EXPANDED" : "") + (Expand && (state & 0x400) != 0 ? "|COLLAPSED" : "") + value));
      if (role == 0xF) continue;  // a web page
      Walk(k, depth + 1, maxDepth, all);
    }
  }

  public static string[] List(IntPtr hwnd, int maxDepth) {
    var all = new List<KeyValuePair<IAccessible, string>>();
    Walk(Root(hwnd), 0, maxDepth, all);
    var lines = new List<string>();
    foreach (var kv in all) lines.Add(kv.Value);
    return lines.ToArray();
  }

  // Returns how many nodes matched; presses the nth when there are enough.
  public static int Press(IntPtr hwnd, string name, int role, int nth, int maxDepth) {
    var all = new List<KeyValuePair<IAccessible, string>>();
    Walk(Root(hwnd), 0, maxDepth, all);
    var hits = new List<IAccessible>();
    foreach (var kv in all) {
      string n = null; int r = 0; int s = 0;
      try { n = kv.Key.get_accName(0); } catch {}
      try { r = Convert.ToInt32(kv.Key.get_accRole(0)); } catch {}
      try { s = Convert.ToInt32(kv.Key.get_accState(0)); } catch {}
      // Shown ones only: a row that was ever open keeps its buttons, hidden.
      if (n == name && (role == 0 || r == role) && (s & 0x8000) == 0) hits.Add(kv.Key);
    }
    if (hits.Count > nth) hits[nth].accDoDefaultAction(0);
    return hits.Count;
  }
}
"@
}
$browserPid = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$Profile*" -and $_.CommandLine -notmatch '--type=' } | ForEach-Object { $_.ProcessId })
if ($browserPid.Count -ne 1) { "MSAA: expected one browser process for $Profile, found $($browserPid.Count)"; exit 2 }
$hwnd = (Get-Process -Id $browserPid[0]).MainWindowHandle
if ($hwnd -eq [IntPtr]::Zero) { "MSAA: the browser has no main window"; exit 2 }
# -Window: this window of the browser (a handle), when it has several (E15d.3) -- MainWindowHandle picks one.
if ($Window) { $hwnd = [IntPtr]$Window }
# -Popup: the open menu's window instead of the main one (EnumWindows lists the top one first).
if ($Popup) { $hwnd = [MsaaWalk]::PopupOf([uint32]$browserPid[0], $hwnd); if ($hwnd -eq [IntPtr]::Zero) { "MSAA: no open menu"; exit 2 } }
# -Where: each -List line ends "|@<top>,<height>" in screen pixels -- where the view is DRAWN. The tree's
# order is the order views were added, not drawn: a tab inserted mid-list is appended as the last child
# and placed by the layout (tab_collection_node.cc AddNewChild), so sort by <top> for the list's order.
[MsaaWalk]::Where = $Where.IsPresent
# -Rect: the whole box instead, "|@<left>,<top>,<width>,<height>" -- where a mouse drag starts and ends (E15d.3).
[MsaaWalk]::Rect = $Rect.IsPresent
# -Desc: each -List line ends "|desc=<accessible description>" (a view's tooltip, newlines as " / ") -- E18's counts.
[MsaaWalk]::Desc = $Desc.IsPresent
# -States: each -List line ends "|SELECTED" (STATE_SYSTEM_SELECTED, 0x2), after every other part -- the quick search
# box's highlighted row (C1) -- and then "|UNAVAILABLE" (STATE_SYSTEM_UNAVAILABLE, 0x1): a greyed menu item (C32).
# Opt-in: five parsers anchor their patterns at the line's end.
[MsaaWalk]::States = $States.IsPresent
# -Expand: each -List line ends "|EXPANDED" (STATE_SYSTEM_EXPANDED, 0x200) or "|COLLAPSED" (0x400), after every other
# part -- a pinned folder row's open state in that window (C9, check-c16). Opt-in, for the same reason as -States.
[MsaaWalk]::Expand = $Expand.IsPresent
# -Values: each -List line ends "|CHECKED" (STATE_SYSTEM_CHECKED 0x10 or PRESSED 0x8: a switch that is on) and then "|=<accValue>"
# (a dropdown's shown item, empty for none), after every other part -- the settings bubble (check-93). Opt-in, for
# the same reason as -States.
[MsaaWalk]::Values = $Values.IsPresent
if ($List) { [MsaaWalk]::List($hwnd, $MaxDepth); exit 0 }
$count = [MsaaWalk]::Press($hwnd, $Name, $Role, $Nth, $MaxDepth)
if ($count -le $Nth) { "MSAA: no node named '$Name' (role 0x" + $Role.ToString("X") + ", #$Nth); $count match(es)"; exit 3 }
"MSAA: pressed '$Name' ($count match(es))"
