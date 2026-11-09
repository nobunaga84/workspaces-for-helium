param([Parameter(Mandatory = $true)][string]$Chunk)   # log prefix, e.g. r5
# The overnight chain after a rebase: out\Default (chrome, chromedriver, workspaces_unittests),
# then the unit tests, then out\Dcheck (chrome). Stops at the first failure so
# the log it names is the one to read. One log per step in <local-path>\Helium-workspace.
$ws  = "<local-path>\Helium-workspace"
$src = "$ws\helium-windows\build\src"
Set-Location $ws

function Stamp { (Get-Date).ToString("HHmmss") }

# 0. Tripwire (LOCAL.md 1, 41): 37-strip-bulk-layout is correct only while LayoutImpl() recomputes
#    the target first. Upstream's TODO (crbug.com/490964477) wants that call gone, and the patch
#    would still apply and compile -- leaving the strip stale after every restore.
$lm = Get-Content -Raw "$src\chrome\browser\ui\views\tabs\common\tab_collection_animating_layout_manager.cc"
if ($lm -notmatch '(?s)::LayoutImpl\(\) \{(?:(?!\n\}).)*?RecalculateTarget\(\);') {
    Write-Host "STOP: LayoutImpl() no longer calls RecalculateTarget() -- 37-strip-bulk-layout would leave the strip stale (LOCAL.md 41)"; exit 1
}
#    And (LOCAL.md 138, R2-5): 104 drops hidden tabs where a shift-click range is made; a selection made in the
#    classic layout, where every tab is drawn, never reaches vertical only because Chromium's own
#    OnVerticalTabStripModeChanged() resets the selection to the tab in front first.
$bv = Get-Content -Raw "$src\chrome\browser\ui\views\frame\browser_view.cc"
if ($bv -notmatch '(?s)::OnVerticalTabStripModeChanged\([^)]*\) \{(?:(?!\n\}).)*?SetSelectionFromModel\(') {
    Write-Host "STOP: OnVerticalTabStripModeChanged() no longer resets the selection -- a classic-layout selection would carry other workspaces' hidden tabs into vertical (LOCAL.md 138, R2-5)"; exit 1
}
#    And (LOCAL.md 143, R2-21): 109's rail replaces the bottom container's flex rule once, keeping Helium's aside; a
#    second place in Helium that sets that rule (a collapse change, say) would silently undo the column's scrolling.
$rv = Get-Content -Raw "$src\chrome\browser\ui\views\frame\vertical_tab_strip_region_view.cc"
if (([regex]::Matches($rv, 'bottom_button_container_->SetProperty\(\s*views::kFlexBehaviorKey')).Count -ne 1) {
    Write-Host "STOP: Helium sets the bottom container's flex rule in more than one place (or none) -- 109's collapsed bar may run off the window again (LOCAL.md 143, R2-21)"; exit 1
}
#    And (LOCAL.md 144, I1): 110's Today list remembers its layouts until UnpinnedTabContainerViewLayout's
#    OnLayoutChanged(), which hears every invalidation only while the animating manager OWNS that layout and
#    LayoutManagerBase passes invalidations on to owned layouts. Either change compiles and leaves the list stale.
$base = Get-Content -Raw "$src\ui\views\layout\layout_manager_base.cc"
if ($base -notmatch '(?s)::PropagateInvalidateLayout\(\) \{(?:(?!\n\}).)*?owned_layout->PropagateInvalidateLayout\(\);(?:(?!\n\}).)*?OnLayoutChanged\(\);') {
    Write-Host "STOP: LayoutManagerBase no longer passes invalidations to owned layouts -- 110's remembered list layouts would go stale (LOCAL.md 144)"; exit 1
}
if ($lm -notmatch 'AddOwnedLayout\(std::move\(target_layout_manager\)\)') {
    Write-Host "STOP: the animating manager no longer owns its target layout -- 110's remembered list layouts would go stale (LOCAL.md 144)"; exit 1
}

# 1. the browser and the fork's tests, one graph walk
$log = "$ws\$Chunk-$(Stamp).log"
Write-Host "STEP 1 Default -> $log"
& "$ws\resume-build.ps1" -Targets chrome, chromedriver, workspaces_unittests *>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { Write-Host "STOP: Default build exit $LASTEXITCODE ($log)"; exit 1 }

# 2. workspaces_unittests
$tlog = "$ws\$Chunk-unittests.log"
Write-Host "STEP 2 unit tests -> $tlog"
& "$src\out\Default\workspaces_unittests.exe" *>&1 | Tee-Object -FilePath $tlog
if ($LASTEXITCODE -ne 0) { Write-Host "STOP: unit tests exit $LASTEXITCODE ($tlog)"; exit 1 }

# 3. LOCAL.md 5.8: the first build leaves midl.py's 0-byte updater .tlb
#    placeholders behind; the second output dir dies on them unless deleted.
Get-ChildItem "$src\third_party\win_build_output\midl\chrome\updater\app\server\win\x64" -Recurse -Filter *.tlb -ErrorAction SilentlyContinue |
  Where-Object Length -eq 0 | ForEach-Object { Write-Host "deleting 0-byte $($_.FullName)"; Remove-Item $_.FullName }

# 4. the DCHECK build
$dlog = "$ws\$Chunk-dcheck-$(Stamp).log"
Write-Host "STEP 4 Dcheck -> $dlog"
& "$ws\resume-build.ps1" -OutDir Dcheck -Targets chrome *>&1 | Tee-Object -FilePath $dlog
if ($LASTEXITCODE -ne 0) { Write-Host "STOP: Dcheck build exit $LASTEXITCODE ($dlog)"; exit 1 }
Write-Host "ALL DONE"
