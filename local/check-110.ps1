# I1 / patch 110: a tab switch in a window of ~3,240 tabs (3,163 pinned pages open). check-108's T1 row -- two Today
# tabs shown in turn 10 times under Chrome's trace -- on its own throwaway profile (-Tag p110, so p108's files stay),
# then grade-i1.py grades that trace: median switch (TabStripModel::ActivateTab) <= 250 ms and the vertical strip's
# relayout in it <= 100 ms. Red (108 + 109, 2026-11-08 21:25): 482.8 ms and 340.0 ms (grade-i1.py: FAIL).
# GUI: only on the owner's word that the PC is free (check-108 opens windows and clicks Open all).
#   pwsh -NoProfile -File <local-path>\Helium-workspace\helium\local\check-110.ps1
$trace = "<local-path>\Helium-workspace\p110-t1-trace-change.jsonl"
Remove-Item -LiteralPath $trace -ErrorAction SilentlyContinue   # never grade a previous run's trace
& pwsh -NoProfile -File "$PSScriptRoot\check-108.ps1" -Tag p110 -IdleMinutes 0 -Against p108-red -Rows T1 -Trace ui,views,browser |
    Tee-Object -Variable c108
if (-not ($c108 -match 'RESULT .* verdict=PASS')) { "FAIL  I1: check-108 did not pass (S0, T1 or crash markers)"; exit 1 }
& python -I "$PSScriptRoot\grade-i1.py" $trace
exit $LASTEXITCODE
