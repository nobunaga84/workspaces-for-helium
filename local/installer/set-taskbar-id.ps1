# Stamps the browser's taskbar identity (AppUserModelID) on the Start menu shortcut, so Windows
# matches the running window to it: "Pin to taskbar" on the window, or on the Start menu entry,
# then pins a copy of THIS shortcut, --user-data-dir included. Without it Windows pinned the bare
# chrome.exe, which opens official Helium's profile (README, "Pinning to the taskbar").
# Run by helium-workspaces.nsi under Windows PowerShell 5.1:  set-taskbar-id.ps1 -Lnk <path> -UserDataDir <user data dir>
# -Show prints the id without writing anything.
param([string]$Lnk, [Parameter(Mandatory)][string]$UserDataDir, [switch]$Show)
$ErrorActionPreference = 'Stop'

# Chromium's own formula (chrome/installer/util/shell_util.cc + chrome/browser/shell_integration_win.cc):
# "Helium" + "." + Base32(MD5(user SID)) is the browser id; the profile id is the user data dir's
# name + ".Default", letters/digits/dots only; each part is cut to 31 characters by keeping its
# first 15 and last 16 (ShortenAppModelIdComponent), and the two are joined by a dot.
function Get-TaskbarId([string]$UserDataDir) {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $md5 = [Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($sid))
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
    $bits = ($md5 | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
    $base32 = -join (0..([Math]::Ceiling($bits.Length / 5) - 1) | ForEach-Object {
        $alphabet[[Convert]::ToInt32($bits.Substring($_ * 5, [Math]::Min(5, $bits.Length - $_ * 5)).PadRight(5, '0'), 2)] })
    $profileId = ((Split-Path $UserDataDir -Leaf) + '.Default') -replace '[^A-Za-z0-9.]', ''
    $max = 31  # (64 - 1 dot) / 2 parts
    $parts = foreach ($p in "Helium.$base32", $profileId) {
        if ($p.Length -gt $max) { $p.Substring(0, 15) + $p.Substring($p.Length - 16) } else { $p }
    }
    $parts -join '.'
}

$id = Get-TaskbarId $UserDataDir
if ($Show) { $id; return }
if (-not $Lnk) { throw '-Lnk is required unless -Show' }

Add-Type @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore { void GetCount(out uint c); void GetAt(uint i, out PropKey k); void GetValue(ref PropKey k, IntPtr v); void SetValue(ref PropKey k, IntPtr v); void Commit(); }
[StructLayout(LayoutKind.Sequential, Pack = 4)] struct PropKey { public Guid fmtid; public uint pid; }
public static class TaskbarId {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
  static extern void SHGetPropertyStoreFromParsingName(string path, IntPtr bind, int flags, ref Guid iid, out IPropertyStore store);
  public static void Set(string lnk, string id) {
    Guid iid = typeof(IPropertyStore).GUID; IPropertyStore store;
    SHGetPropertyStoreFromParsingName(lnk, IntPtr.Zero, 2 /* GPS_READWRITE */, ref iid, out store);
    var key = new PropKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };  // PKEY_AppUserModel_ID
    IntPtr pv = Marshal.AllocCoTaskMem(24);  // PROPVARIANT: vt (VT_LPWSTR = 31), 6 reserved bytes, the string
    try {
      for (int i = 0; i < 24; i++) Marshal.WriteByte(pv, i, 0);
      Marshal.WriteInt16(pv, 0, 31);
      Marshal.WriteIntPtr(pv, 8, Marshal.StringToCoTaskMemUni(id));
      store.SetValue(ref key, pv); store.Commit();
    } finally { Marshal.FreeCoTaskMem(Marshal.ReadIntPtr(pv, 8)); Marshal.FreeCoTaskMem(pv); Marshal.ReleaseComObject(store); }
  }
}
'@
[TaskbarId]::Set($Lnk, $id)
$read = (New-Object -ComObject Shell.Application).Namespace((Split-Path $Lnk)).ParseName((Split-Path $Lnk -Leaf)).ExtendedProperty('System.AppUserModel.ID')
if ($read -ne $id) { throw "taskbar id not written: read '$read', wanted '$id'" }
"taskbar id $id -> $Lnk"
