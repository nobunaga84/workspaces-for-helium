param([ValidateSet("Default", "Dcheck")][string]$Build = "Default", [string]$Tag = "", [switch]$GradeOnly)
# Patch 101 (the polish batch, part E, LOCAL.md 131): the menus review's picks, the owner's "Use your picks"
# (<local-path>\Helium-workspace\polish-menus-proposals.md: 1, 3a, 4a, 5, 6, 7, 8b, 9b, 10, 12a, 13a, 15). One run of
# capture-ui.ps1 -Dump on its made-up demo profile (Windows PowerShell 5.1; the window topmost, real right-clicks
# and one Tab: the PC free, the owner's word), then its ui-shots\p101-<build><Tag>\menus.txt and log graded.
#   pwsh -NoProfile -Command "& '<local-path>\Helium-workspace\helium\local\check-101.ps1' -Build Default"
#   red, on a build without patch 101: ... -Tag -red; -GradeOnly grades a run's menus.txt and log again, no browser
#   E1  #1 #3 #4 #5  Hacker News' tab menu: a divider, "Rename tab...", "Set emoji...", a divider, "Pin to this
#                    workspace", a divider before "Move tab to workspace", then "Always open news.ycombinator.com in
#                    the Home workspace"
#   E2  #6 #7        Gmail's pinned page menu: "Rename..." (the build draws the bookmark bar's three dots as U+2026), a
#                    divider before "Move to workspace", after "New folder", before "Unpin" and before "Delete"
#   E3  #6           the Reading folder's menu: "Color" above a divider and "Move to workspace", a divider after "New
#                    folder" and before "Delete folder"
#   E4  #12 #13      the Work chip's menu: "Hibernate this workspace", "Hibernate other workspaces", "Bookmark all
#                    tabs", no "Unload" or "Save as bookmarks"
#   E5  #10          the + menu: "Find tabs and pages" just above "Tab search"; pressed, the quick search opens
#   E6  #15          Workspace settings opened by a mouse click: no dropdown has the focus (no ring); opened the
#                    keyboard's way (an MSAA press arrives as Enter): the first dropdown has it
#   Z                0 crash markers in the run's log (case-sensitive, DanglingPtr too)
# #9b ("Use current page") shows only on a pinned page that moved: check-c35.ps1's C31 presses it by that name.
$ws    = "<local-path>\Helium-workspace"
$name  = "p101-$($Build.ToLower())$Tag"
$shots = "$ws\ui-shots\$name"
$log   = "$ws\ui-$name.log"
$script:passed = 0; $script:failed = 0
function Verdict($what, $ok) { if ($ok) { Write-Host "PASS  $what"; $script:passed++ } else { Write-Host "FAIL  $what"; $script:failed++ } }

if (-not $GradeOnly) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\capture-ui.ps1" -OutDir $Build -Tag $name -Dump |
        ForEach-Object { Write-Host "  $_" }
}
if (-not (Test-Path -LiteralPath "$shots\menus.txt")) { Write-Host "ABORT: no $shots\menus.txt"; exit 1 }

# menus.txt: "== <state>", then that state's lines.
$menus = @{}; $state = ""
foreach ($l in [IO.File]::ReadAllLines("$shots\menus.txt")) {
    if ($l -match '^== (.*)$') { $state = $Matches[1]; $menus[$state] = @() } else { $menus[$state] += $l }
}
function At($seq, [string]$re) { for ($i = 0; $i -lt $seq.Count; $i++) { if ($seq[$i] -match $re) { return $i } }; -1 }
function Before($seq, [string]$re) { $i = At $seq $re; if ($i -gt 0) { $seq[$i - 1] } }
function After($seq, [string]$re) { $i = At $seq $re; if ($i -ge 0 -and $i + 1 -lt $seq.Count) { $seq[$i + 1] } }
function Says([string]$state) { $s = @($menus[$state]); Write-Host "      ${state}: $($s -join ' / ')"; $s }
$text = if (Test-Path -LiteralPath $log) { [IO.File]::ReadAllText($log) } else { "" }

# The "..." of a label that opens a box is U+2026; MSAA's text round trip may hand it back as '?': any character.
$t = Says "09-tab-menu"
$pin = At $t '^Pin to this workspace$'; $move = At $t '^Move tab to workspace$'
Verdict "E1 #1 #3 #4 #5 the tab menu's three groups and labels" (
    (Before $t '^Rename tab.+$') -eq '|' -and (After $t '^Set emoji') -eq '|' -and $pin -gt 0 -and $t[$pin - 1] -eq '|' -and
    $move -gt $pin -and $t[$move - 1] -eq '|' -and (After $t '^Move tab to workspace$') -eq 'Always open news.ycombinator.com in the Home workspace')

$g = Says "10-pinned-page-menu"
Verdict "E2 #6 #7 the pinned page menu's groups and 'Rename...'" (
    (At $g '^&?Rename(\.\.\.|…)$') -ge 0 -and (Before $g '^Move to workspace$') -eq '|' -and (After $g '^New folder$') -eq '|' -and
    (Before $g '^Unpin$') -eq '|' -and (Before $g '^Delete$') -eq '|')

$f = Says "11-folder-menu"
$color = At $f '^Color$'
Verdict "E3 #6 the folder menu's groups" (
    $color -ge 0 -and $color -lt (At $f '^Move to workspace$') -and (Before $f '^Move to workspace$') -eq '|' -and
    (After $f '^New folder$') -eq '|' -and (Before $f '^Delete folder$') -eq '|')

$w = Says "03-workspace-menu"
Verdict "E4 #12 #13 the workspace menu's Hibernate and Bookmark all tabs" (
    (At $w '^Hibernate this workspace$') -ge 0 -and (At $w '^Hibernate other workspaces$') -ge 0 -and
    (At $w '^Bookmark all tabs$') -ge 0 -and (At $w '^Unload|^Save as bookmarks$') -lt 0)

$p = Says "02-plus-menu"
# The quick search counted only when it opened after the + menu's item was pressed.
$pressed = $text -match 'rail \+ menu: find tabs and pages'; $opened = $text -match '(?s)rail \+ menu: find tabs and pages.*quick search: opened'
Write-Host "      pressed (log): $pressed; the quick search opened (log): $opened"
Verdict "E5 #10 'Find tabs and pages' in the + menu, and it opens the quick search" (
    (After $p '^Find tabs and pages$') -eq 'Tab search' -and $pressed -and $opened)

$mouse = @(Says "12-settings-bubble" | Where-Object { $_ -like 'focus at open:*' })
$keys = @(Says "12k-settings-keyboard" | Where-Object { $_ -like 'focus at open:*' })
Verdict "E6 #15 Workspace settings: by the mouse no dropdown focused, by the keyboard the first one" (
    $mouse.Count -and $mouse[0] -notmatch 'ComboBox' -and $keys.Count -and $keys[0] -match "ComboBox 'Archive tabs after'")

$marks = @([regex]::Matches($text, 'Check failed|FATAL|DanglingPtr|ReentrancyCheck|NOTREACHED')).Count
Verdict "Z 0 crash markers in $log ($marks)" ($marks -eq 0)
Write-Host "RESULT: $script:passed passed, $script:failed failed (shots: $shots)"
