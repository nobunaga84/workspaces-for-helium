param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$BinDir = "", [switch]$Gui)
# F4 (patch 102 + the branding files, LOCAL.md 134): the name "Workspaces for Helium" and icon B.
#   pwsh -NoProfile -File local\check-f4.ps1 [-Build Dcheck] [-BinDir <dir>]    no window: S1-S3
#   pwsh -NoProfile -File local\check-f4.ps1 -Gui                              also G1-G2: a window for ~10 s
#   S1  chrome.exe's file details (Task Manager, Properties): FileDescription and ProductName are the new name
#   S2  the icon Windows draws from chrome.exe at 16 and 32 px is the hand-tuned drawing (local/branding/*-16/32.svg)
#   S3  the string pack has the window title "... - Workspaces for Helium" and "About Workspaces for Helium"
#   G1  a new window's title ends with " - Workspaces for Helium" (the taskbar hover, Alt+Tab)
#   G2  chrome://settings/help's own string for its heading is "About Workspaces for Helium"
# G starts the browser as check-95 does: LOCALAPPDATA = a new scratch folder, no --user-data-dir, a DevTools port;
# the owner's profiles are never opened. No mouse, no keys.
. "$PSScriptRoot\e18-lib.ps1"
$name = "Workspaces for Helium"
$bin  = if ($BinDir) { $BinDir } else { "<local-path>\Helium-workspace\helium-windows\build\src\out\$Build" }
$repo = Split-Path $PSScriptRoot
$script:passed = 0; $script:failed = 0
function Verdict($what, $ok) { if ($ok) { Write-Host "PASS  $what"; $script:passed++ } else { Write-Host "FAIL  $what"; $script:failed++ } }

# S1: the version resource.
$v = (Get-Item -LiteralPath "$bin\chrome.exe").VersionInfo
Write-Host "      FileDescription '$($v.FileDescription)', ProductName '$($v.ProductName)'"
Verdict "S1 the file details name it" ($v.FileDescription -eq $name -and $v.ProductName -eq $name)

# S2: the icons Windows extracts, pixel by pixel against the tuned PNGs (a channel may differ by 8).
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace F4 -Name Shell -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint PrivateExtractIcons(string file, int index, int cx, int cy, IntPtr[] icons, uint[] ids, uint n, uint flags);
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
'@
# The exact sizes asked for, whatever the display scale (the shell's "small icon" is 24 px at 150 %).
$large = [IntPtr[]]::new(1); $small = [IntPtr[]]::new(1)
$null = [F4.Shell]::PrivateExtractIcons("$bin\chrome.exe", 0, 32, 32, $large, [uint32[]]::new(1), 1, 0)
$null = [F4.Shell]::PrivateExtractIcons("$bin\chrome.exe", 0, 16, 16, $small, [uint32[]]::new(1), 1, 0)
function Same([IntPtr]$h, [string]$png, [int]$px) {
    if ($h -eq [IntPtr]::Zero) { return "no icon" }
    $got = [System.Drawing.Icon]::FromHandle($h).ToBitmap(); $want = [System.Drawing.Bitmap]::new($png)
    if ($got.Width -ne $px -or $want.Width -ne $px) { return "size $($got.Width)" }
    $bad = 0
    for ($y = 0; $y -lt $px; $y++) { for ($x = 0; $x -lt $px; $x++) {
        $a = $got.GetPixel($x, $y); $b = $want.GetPixel($x, $y)
        if ([Math]::Abs($a.A - $b.A) -gt 8 -or ($b.A -gt 0 -and ([Math]::Abs($a.R - $b.R) -gt 8 -or [Math]::Abs($a.G - $b.G) -gt 8 -or [Math]::Abs($a.B - $b.B) -gt 8))) { $bad++ }
    } }
    $got.Dispose(); $want.Dispose()
    "$bad of $($px * $px) pixels differ"
}
$s16 = Same $small[0] "$repo\resources\branding\app_icon\raw_16.png" 16
$s32 = Same $large[0] "$repo\resources\branding\app_icon\raw_32.png" 32
foreach ($h in $large + $small) { if ($h -ne [IntPtr]::Zero) { $null = [F4.Shell]::DestroyIcon($h) } }
Write-Host "      16 px: $s16; 32 px: $s32"
Verdict "S2 the program icon is icon B at 16 and 32 px" ($s16 -like "0 of *" -and $s32 -like "0 of *")

# S3: the strings, read from the pack as bytes (UTF-8).
$pak = [System.Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes("$bin\locales\en-US.pak"))
$title = $pak.Contains("$([char]0x24)1 - $name"); $about = $pak.Contains("About $name")
Write-Host "      title format: $title; About: $about"
Verdict "S3 the window title and About strings" ($title -and $about)

if ($Gui) {
    Add-Type -Namespace F4 -Name Win -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
'@
    $scratch = "$env:TEMP\check-f4-$(Get-Date -Format yyyyMMdd-HHmmss)"; $own = "$scratch\Helium Workspaces\User Data"
    $null = New-Item -ItemType Directory $scratch
    $real = $env:LOCALAPPDATA; $env:LOCALAPPDATA = $scratch
    try { $p = Start-Process "$bin\chrome.exe" -ArgumentList "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0" -PassThru }
    finally { $env:LOCALAPPDATA = $real }
    try {
        $titles = @(); $t0 = Get-Date
        while (-not @($titles | Where-Object { $_ -like "* - *" }).Count -and ((Get-Date) - $t0).TotalSeconds -lt 30) {
            Start-Sleep 1
            $ids = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$scratch*" -or $_.ProcessId -eq $p.Id } | ForEach-Object { [uint32]$_.ProcessId })
            $found = [System.Collections.Generic.List[string]]::new()
            $null = [F4.Win]::EnumWindows({ param($h, $l)
                $wp = [uint32]0; $null = [F4.Win]::GetWindowThreadProcessId($h, [ref]$wp)
                if ($ids -contains $wp -and [F4.Win]::IsWindowVisible($h)) { $sb = [System.Text.StringBuilder]::new(512); $null = [F4.Win]::GetWindowText($h, $sb, 512); if ($sb.Length) { $found.Add($sb.ToString()) } }
                $true }, [IntPtr]::Zero)
            $titles = @($found)
        }
        Write-Host "      window titles: $(($titles | ForEach-Object { "'$_'" }) -join ', ')"
        Verdict "G1 the window title ends with ' - $name'" (@($titles | Where-Object { $_.EndsWith(" - $name") }).Count -ge 1)
        $about = "(no page)"
        $s = OpenSettings $own
        Write-Host "      settings: $($s.note)"
        if ($s.ready) { $about = Evaluate $s.page.webSocketDebuggerUrl "import('chrome://resources/js/load_time_data.js').then(m => m.loadTimeData.getString('aboutPageTitle'))" }
        Write-Host "      About heading: '$about'"
        Verdict "G2 the About page's heading" ($about -eq "About $name")
    } finally { Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" | Where-Object { $_.CommandLine -like "*$scratch*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -EA SilentlyContinue }; Stop-Process -Id $p.Id -EA SilentlyContinue }
}
Write-Host "$script:passed passed, $script:failed failed"
exit [int]($script:failed -gt 0)
