# E19: seeds a TEST profile's pins with the owner's Arc pinned splits the way
# every import before E19 left them -- two plain items each, side by side -- at
# the end of workspace Work, in a version-1 file, so the browser's one-time
# repair (WorkspaceArcImporter::RepairSplits) has the real case to pair.
# Read-only on Arc's file and on the source profile; writes the copy's pins only.
#   python e19-seed-splits.py <profile-copy> [--source <profile>] [--arc <file>]
# Prints ids only, never a URL or a title.
import argparse
import json
import os
import sys

WORK = "2ab592d4-a80b-4a1d-aeaa-6acd51c12134"  # "Work" in testprofile-e15b-smoke

ap = argparse.ArgumentParser()
ap.add_argument("profile")
ap.add_argument("--workspace", default=WORK, help="the guid to seed into")
ap.add_argument("--source", default=r"<local-path>\Helium-workspace\testprofile")
# The made-up Arc file (make-test-profiles.py, LOCAL.md 133): its ids match testprofile's pins.
ap.add_argument("--arc", default=r"<local-path>\Helium-workspace\arc-made-up\StorableSidebar.json")
args = ap.parse_args()

# Arc's split views: the main sidebar is the container after {"global":{}}, its
# items a flat [id, item, id, item, ...] list (LOCAL.md 39).
with open(args.arc, encoding="utf-8") as f:
    containers = json.load(f)["sidebar"]["containers"]
main = next(containers[i + 1] for i in range(len(containers) - 1)
            if isinstance(containers[i], dict) and "global" in containers[i])
flat = main["items"]
items = {flat[i]: flat[i + 1] for i in range(0, len(flat) - 1, 2)
         if isinstance(flat[i], str) and isinstance(flat[i + 1], dict)}
pairs = [item["childrenIds"] for item in items.values()
         if "splitView" in (item.get("data") or {})
         and len(item.get("childrenIds") or []) == 2]

# The halves as the source profile's pins hold them (rows, any depth).
def walk(rows, found):
    for row in rows:
        found[row["id"]] = row
        walk(row.get("children", []), found)

with open(os.path.join(args.source, "Default", "Workspace Pins"), encoding="utf-8") as f:
    source = {}
    for rows in json.load(f)["workspaces"].values():
        walk(rows, source)

target_path = os.path.join(args.profile, "Default", "Workspace Pins")
with open(target_path, encoding="utf-8") as f:
    target = json.load(f)
taken = {}
walk([r for rows in target["workspaces"].values() for r in rows], taken)
# The bases' pins are version 2 (LOCAL.md 133: no launch of a copy reads an Arc file). Version 1 is the repair's
# cue: set here, on a copy with no split row to lose by it.
assert not any(r.get("type") == "split" for r in taken.values()), "the copy already holds a split row"
target["version"] = 1

added = 0
for pair in pairs:
    if not all(i in source and source[i]["type"] == "item" and i not in taken for i in pair):
        print("skipped a pair:", [i[:8] for i in pair])
        continue
    for i in pair:
        target["workspaces"].setdefault(args.workspace, []).append(source[i])
    added += 1
    print("seeded pair:", [i[:8] for i in pair])

with open(target_path, "w", encoding="utf-8") as f:
    json.dump(target, f, indent=3)
print(f"{added} of {len(pairs)} Arc split(s) seeded into {args.workspace} as two items each")
sys.exit(0 if added else 1)
