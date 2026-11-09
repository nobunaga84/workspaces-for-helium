param([string]$Ext = ".html")
# Prints every "Open with" handler Windows offers for $Ext whose program path or shown name mentions Helium:
# <shown name> | <program>. The shown name is what the Open with menu draws (IAssocHandler::GetUIName).
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Collections.Generic;
[ComImport, Guid("F04061AC-1659-4a3f-A954-775AA57FC083"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAssocHandler {
  [PreserveSig] int GetName([MarshalAs(UnmanagedType.LPWStr)] out string s);
  [PreserveSig] int GetUIName([MarshalAs(UnmanagedType.LPWStr)] out string s);
}
[ComImport, Guid("973810ae-9599-4b88-9e4d-6ee98c9552da"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IEnumAssocHandlers {
  [PreserveSig] int Next(uint n, [MarshalAs(UnmanagedType.Interface)] out IAssocHandler h, out uint got);
}
public static class OpenWith {
  [DllImport("shell32.dll")] static extern int SHAssocEnumHandlers([MarshalAs(UnmanagedType.LPWStr)] string ext, int filter, out IEnumAssocHandlers e);
  public static List<string> List(string ext) {
    var r = new List<string>(); IEnumAssocHandlers e;
    if (SHAssocEnumHandlers(ext, 0, out e) != 0) return r;
    IAssocHandler h; uint got;
    while (e.Next(1, out h, out got) == 0 && got == 1) { string n, u; h.GetName(out n); h.GetUIName(out u); r.Add(u + " | " + n); }
    return r;
  }
}
"@
[OpenWith]::List($Ext) | Where-Object { $_ -match 'Helium' }
