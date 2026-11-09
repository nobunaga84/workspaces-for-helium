param([string]$Tag = "p111")
# I1 Fix 3 / patch 111: every tab view's Glic underline recoloured itself on every tab switch (3 ThemeService lookups
# per tab, ~37 ms at 3,238 tabs), and GetFocusedTabIndex walked the whole tab tree once per tab (~30 ms). Hands-free,
# small: a throwaway copy of the smoke profile, 100 blank tabs opened through DevTools, two of them shown in turn 10
# times under Chrome's trace, the browser closed through DevTools, then grade-i1.py --tail-themes 50: the lookups
# after Browser::OnActiveTabChanged's toolbar update, ~3 per tab before 111, a handful after.
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-111.ps1 [-Tag p111-red]
$ws = "<local-path>\Helium-workspace"; $bin = "$ws\helium-windows\build\src\out\Default"; $exe = "$bin\chrome.exe"
$prof = "$ws\testprofile-$Tag"; $log = "$ws\$Tag-run.log"; $trace = "$ws\$Tag-trace.jsonl"
function Fail([string]$why) { "FAIL  I1: $why"; exit 1 }
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" }) { Fail "a fork browser is already running" }

if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
& python -I "$PSScriptRoot\prefs.py" "$prof\Default\Preferences" "helium.browser.layout=2" "helium.workspaces.enabled=true" "vertical_tabs.collapsed_state=false"
if ($LASTEXITCODE -ne 0) { Fail "the preferences were not seeded into $prof" }
Remove-Item -LiteralPath $trace, $log -EA SilentlyContinue
"build: $exe, chrome.dll of $((Get-Item "$bin\chrome.dll").LastWriteTime)"

$p = Start-Process $exe -PassThru -ArgumentList @("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0",
    "--remote-debugging-port=0", "--no-first-run", "--no-default-browser-check")
try {
$t0 = Get-Date
while (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort") -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1 }
if (-not (Test-Path -LiteralPath "$prof\DevToolsActivePort")) { Fail "no DevTools port" }
Start-Sleep 3
$json = "http://127.0.0.1:$((Get-Content -LiteralPath "$prof\DevToolsActivePort" -TotalCount 1).Trim())/json"
$tabs = @(1..100 | ForEach-Object { Invoke-RestMethod -Method Put "$json/new?about:blank" })
Start-Sleep 3
"browser $($p.Id), $($tabs.Count) tabs opened"

$sock = [Net.WebSockets.ClientWebSocket]::new()
$sock.ConnectAsync([Uri](Invoke-RestMethod "$json/version").webSocketDebuggerUrl, [Threading.CancellationToken]::None).Wait()
function WsSend([string]$s) {
    $by = [Text.Encoding]::UTF8.GetBytes($s)
    $sock.SendAsync([ArraySegment[byte]]::new($by), 'Text', $true, [Threading.CancellationToken]::None).Wait()
}
function WsRecv {
    $buf = [byte[]]::new(1MB); $ms = [IO.MemoryStream]::new()
    do {
        # 60 s per message at most: a trace that never completes ends the check instead of hanging it.
        $cts = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds(60))
        $r = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf), $cts.Token).GetAwaiter().GetResult()
        $ms.Write($buf, 0, $r.Count)
    } while (-not $r.EndOfMessage)
    [Text.Encoding]::UTF8.GetString($ms.ToArray())
}
WsSend '{"id":1,"method":"Tracing.start","params":{"traceConfig":{"includedCategories":["toplevel","ui","views","browser"]},"transferMode":"ReportEvents"}}'
while ((WsRecv) -notmatch '"id":1\b') {}
foreach ($i in 0..10) {
    $null = Invoke-RestMethod "$json/activate/$($tabs[$i % 2].id)"
    Start-Sleep -Milliseconds 700
}
WsSend '{"id":2,"method":"Tracing.end"}'
$w = [IO.StreamWriter]::new($trace)
do {
    $m = WsRecv
    if ($m -match '"method":"Tracing.dataCollected"') { $w.WriteLine($m) }
} while ($m -notmatch '"method":"Tracing.tracingComplete"')
$w.Close()
WsSend '{"id":3,"method":"Browser.close"}'
$t0 = Get-Date
while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 30) { Start-Sleep 1 }
} finally {
    # Whatever happened above, no test browser is left behind for the next check.
    Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$bin\*" } | Stop-Process -Force -EA SilentlyContinue
}

$markers = @(Select-String -LiteralPath $log -CaseSensitive -Pattern "Check failed|FATAL|ReentrancyCheck|NOTREACHED|dangling|DanglingPtr").Count
if ($markers) { Fail "$markers crash marker(s) in $log" }
"crash markers in $log`: 0"
& python -I "$PSScriptRoot\grade-i1.py" $trace --tail-themes 50
exit $LASTEXITCODE
