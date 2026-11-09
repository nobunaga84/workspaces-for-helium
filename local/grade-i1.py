"""I1 (patch 110): grade a check-108 T1 trace -- each tab switch, and the vertical tab strip laid out again in it.

  python -I grade-i1.py <trace.jsonl>                    patch 110 (check-110)
  python -I grade-i1.py <trace.jsonl> --tail-themes MAX  patch 111 (check-111)

A switch is a TabStripModel::ActivateTab that reached Browser::OnActiveTabChanged; the strip is the top-level
View::Layout(...) of VerticalTabStripRegionView inside it. Medians over the switches; PASS (exit 0) when at least 5
switches, the switch at most 250 ms and the strip at most 100 ms. Red (108 + 109, 2026-11-08 21:25): 482.8 and 340.0.
--tail-themes: instead, the ThemeService lookups at the end of Browser::OnActiveTabChanged, after its toolbar update
(where every tab's Glic underline recoloured itself: 9,727 = 3 x 3,238 + 13 at 3,238 tabs), at most MAX.
"""
import json
import statistics
import sys

path = sys.argv[1]
max_switch, max_strip = 250.0, 100.0
max_tail = float(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[2] == "--tail-themes" else None

events = []
for line in open(path, encoding="utf-8"):
    events.extend(json.loads(line)["params"]["value"])
spans = [e for e in events if e.get("ph") == "X"]


def named(name, cls=None):
    return [e for e in spans if e["name"] == name and (cls is None or e.get("args", {}).get("class") == cls)]


def inside(e, outer):
    return e["pid"] == outer["pid"] and e["tid"] == outer["tid"] and \
        outer["ts"] <= e["ts"] < outer["ts"] + outer["dur"]


changed = named("Browser::OnActiveTabChanged")
regions = named("View::Layout(set_bounds)", "VerticalTabStripRegionView") + \
    named("View::Layout(bounds_changed)", "VerticalTabStripRegionView")

toolbars = named("BrowserUiController::UpdateToolbar")
themes = [e for e in events if e["name"] == "KeyedServiceFactory::GetServiceForContext" and
          (e.get("args", {}).get("chrome_keyed_service") or {}).get("name") == "ThemeService"]

switch_ms, strip_ms, tail_n = [], [], []
for act in named("TabStripModel::ActivateTab"):
    browser = [b for b in changed if inside(b, act)]
    if not browser:
        continue  # activated the tab already in front: no switch
    switch_ms.append(act["dur"] / 1e3)
    strip_ms.append(sum(r["dur"] for r in regions if inside(r, act)) / 1e3)
    if max_tail is not None:
        b = browser[0]
        ups = [u for u in toolbars if inside(u, b)]
        start = (ups[-1]["ts"] + ups[-1]["dur"]) if ups else b["ts"]
        tail_n.append(sum(1 for t in themes if inside(t, b) and t["ts"] >= start))

if len(switch_ms) < 5:
    print(f"FAIL  I1: {len(switch_ms)} switch(es) in {path} (want at least 5)")
    sys.exit(1)
if max_tail is not None:
    tail = statistics.median(tail_n)
    ok = tail <= max_tail
    print(f"I1 ThemeService lookups after the toolbar update, per switch: {', '.join(str(n) for n in tail_n)}")
    print(f"{'PASS' if ok else 'FAIL'}  I1 {len(switch_ms)} switches: median {tail:.0f} lookups after the toolbar "
          f"update (want <= {max_tail:.0f}); median switch {statistics.median(switch_ms):.1f} ms (recorded)")
    sys.exit(0 if ok else 1)
switch, strip = statistics.median(switch_ms), statistics.median(strip_ms)
print(f"I1 per switch (ms): {', '.join(f'{v:.0f}' for v in switch_ms)}")
print(f"I1 strip relayout per switch (ms): {', '.join(f'{v:.0f}' for v in strip_ms)}")
ok = switch <= max_switch and strip <= max_strip
print(f"{'PASS' if ok else 'FAIL'}  I1 {len(switch_ms)} switches: median switch {switch:.1f} ms (want <= {max_switch:.0f}), "
      f"strip relayout {strip:.1f} ms (want <= {max_strip:.0f}); red 482.8 / 340.0")
sys.exit(0 if ok else 1)
