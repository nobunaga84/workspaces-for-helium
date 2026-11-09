param([switch]$NoLaunch)
# C33 (patch 86): the owner's own try of "Snooze tab" -- the look and feel no automated check can judge: the submenu's
# words and times, the Custom box, the dot on a workspace's button, the Snoozed heading in the Archive. It opens the
# built browser (out\Default) on a FRESH copy of the smoke profile (never the daily browser's profile), with four pages,
# and with the hidden test switch: every snooze comes back 60 SECONDS after it is made, whatever time was chosen.
# -NoLaunch: sets everything up and prints, starts nothing (Claude's rehearsal).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\try-c33.ps1
$ws    = "<local-path>\Helium-workspace"
$here  = $PSScriptRoot
$bin   = "$ws\helium-windows\build\src\out\Default"
$exe   = "$bin\chrome.exe"
$prof  = "$ws\testprofile-c33-owner"
$log   = "$ws\c33-owner-run.log"
$pages = @("https://example.com/", "https://www.iana.org/help/example-domains", "https://www.wikipedia.org/", "https://httpbin.org/html")
if (Get-Process chrome -EA SilentlyContinue | Where-Object { $_.Path -like "$ws\*" }) { Write-Host "A test browser is already open: close it first."; exit 1 }
& python -I -c "import mmap,sys; f=open(sys.argv[1],'rb'); m=mmap.mmap(f.fileno(),0,access=mmap.ACCESS_READ); sys.exit(0 if m.find(sys.argv[2].encode())>=0 else 1)" "$bin\chrome.dll" "snooze: woke "
if ($LASTEXITCODE -ne 0) { Write-Host "This build has no C33 yet (no 'snooze: woke' in out\Default\chrome.dll): tell Claude."; exit 1 }
if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force }
$null = robocopy "$ws\testprofile-e15b-smoke" $prof /E /NFL /NDL /NJH /NP /R:1 /W:1
Get-ChildItem -LiteralPath "$prof\Default\Sessions" -File -EA SilentlyContinue | Remove-Item -Force
Remove-Item -LiteralPath "$prof\Default\Workspace Archive", $log -EA SilentlyContinue
& python -I "$here\prefs.py" "$prof\Default\Preferences" "vertical_tabs.uncollapsed_width=280" "vertical_tabs.collapsed_state=false" "helium.browser.show_dynamic_new_tab_button=false" | Out-Null
if (-not $NoLaunch) {
    Start-Process $exe -ArgumentList (@("--user-data-dir=$prof", "--enable-logging", "--log-file=`"$log`"", "--v=0", "--no-first-run",
                                        "--no-default-browser-check", "--helium-workspaces-snooze-test-seconds=60") + $pages)
}
@"

The test browser is opening on a COPY of the smoke profile (your daily browser is not touched), in its workspace Home,
with four pages: Example Domain, Example Domains (IANA), Wikipedia, and httpbin's "Herman Melville - Moby-Dick".
Words used below:
  - a TODAY TAB is a tab in the sidebar's list UNDER the pinned pages (not a pinned page).
  - the BAR is the row at the bottom of the sidebar: the Archive button, one round button per workspace, and "+".
TEST MODE: every snooze comes back about 60 seconds after you make it, whatever time you pick (so nobody waits hours).
Do every step from HOME unless a step says otherwise.

 1. Right-click the Today tab "Example Domain" > "Snooze tab". PASS: a submenu with "In 2 hours (<time>)", "In 3 hours
    (<time>)", 5, 7 and 11 hours, each time about that many hours from now, then "Custom$([char]0x2026)". Click "In 2 hours".
    PASS: Example Domain leaves the list.
 2. Click the Archive button on the bar. PASS: the first heading is "Snoozed", with Example Domain under it, and its time on
    the right is when it comes back. Press Esc to close the Archive.
 3. Stay in Home and wait about a minute. PASS: Example Domain comes back at the TOP of Home's Today tabs, and the page you
    were looking at stays in front (the woken tab is not opened for you).
 4. Snooze the Today tab "Wikipedia" (In 3 hours), then click the Work button on the bar and wait in Work about a minute.
    PASS: a small dot appears at the corner of the Home button; hover it: the tooltip says "Back from snooze - Wikipedia".
    Then click Home. PASS: Wikipedia is at the top, and the dot is gone.
 5. Snooze "Example Domains" (any time), and at once press Ctrl+Shift+T. PASS: it comes back right away, and nothing else
    comes back a minute later.
 6. Right-click "Herman Melville - Moby-Dick" > Snooze tab > Custom$([char]0x2026). PASS: a box titled "Snooze 1 tab", a "For" box with
    30 and a "Unit" list on Minutes (Minutes, Hours, Days, Weeks). Empty the number and click Snooze. PASS: the box stays
    open. Type 2, choose Hours, click Snooze. PASS: the tab leaves the list (in test mode it comes back in a minute).
 7. Click one Today tab, Ctrl+click a second, right-click one of them > Snooze tab > Custom$([char]0x2026). PASS: the box's title says
    "Snooze 2 tabs". Click Cancel. PASS: both tabs stay.
 8. Right-click a PINNED page (above the Today tabs). PASS: its menu has no "Snooze tab" (only Today tabs snooze).

Close the browser when done and tell Claude which steps passed; Claude grades them from the log too:
   $log
"@
