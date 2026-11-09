"""Edit the Workspaces prefs in a profile, safely -- or check one is ready to test.

The enabled pref has a settings toggle since E9e part 3, but the workspace LIST
still has no UI outside the rail, and chrome://prefs-internals only reads, so
editing the profile is still how a test profile gets set up. Hand-editing that
file is a bad idea: it is one long line of minified JSON, and a stray character
makes Chrome discard the profile silently.

    python local/set-workspaces-pref.py <profile-dir> --show
    python local/set-workspaces-pref.py <profile-dir> true
    python local/set-workspaces-pref.py <profile-dir> false
    python local/set-workspaces-pref.py <profile-dir> --list default:Home,work:Work
    python local/set-workspaces-pref.py <profile-dir> --clear-list
    python local/set-workspaces-pref.py <profile-dir> --layout vertical
    python local/set-workspaces-pref.py <profile-dir> --zen-sidebar-pinned true|false|unset

--list takes guid:title pairs, comma separated, in cycling order; the title is
optional (`--list default,work`). --clear-list removes the stored list so the
registered default applies again, which is how you get back to a clean baseline.

--layout takes `vertical` or `classic`. It is not a Workspaces pref, but every
owner-verification list in LOCAL.md begins by requiring vertical, and until
E9e.4 --show could REPORT the layout while nothing here could SET it -- so a
profile left in classic (which testing the classic-switch does, deliberately)
could only be repaired by clicking through the browser. That is how E9e.4's
first DCHECK run came to grep clean over a Reconcile() that had never once
executed: the profile was classic, so every workspace path correctly declined.

--show writes nothing. It prints the three pieces of profile state every
owner-verification list in LOCAL.md assumes, and exits non-zero when the profile
cannot answer the question being asked of it -- a classic-layout profile shows no
rail, no toggle and no hidden tabs, which reads on screen exactly like a broken
build. Run it BEFORE a test, not after a confusing result.

CLOSE THE BROWSER FIRST. Chrome holds prefs in memory and rewrites the file on
exit, so an edit made while it runs is overwritten with no warning -- which reads
exactly like the pref having no effect.

The write is all-or-nothing (local/profile_write.py): a .bak copy is kept from the first
run and never overwritten, and a .prev copy from just before each run.
"""

import json
import pathlib
import sys

from profile_write import write_json_atomically

# Must match kSchemaVersion in workspace_prefs.h. A value this build does not
# recognise is ignored wholesale, so a mismatch here reads on screen as the list
# silently falling back to the default workspace.
SCHEMA_VERSION = 1

# HeliumLayoutType::kVertical, from helium_layout_state_controller.h. The gate
# (design 2.8) is shut in every other layout, so a profile storing anything else
# has nothing to show -- see --show.
LAYOUT_VERTICAL = 2
LAYOUT_CLASSIC = 0


def parse_layout(spec):
    spec = spec.strip().lower()
    if spec == "vertical":
        return LAYOUT_VERTICAL
    if spec == "classic":
        return LAYOUT_CLASSIC
    sys.exit("--layout takes 'vertical' or 'classic'")

# kDefaultWorkspaceGuid, from workspace_stamping.h. The parser guarantees this
# entry exists, so a list containing only it is a one-workspace profile, in
# which switching is correctly a no-op (LOCAL.md 15).
DEFAULT_GUID = "default"


def parse_items(spec):
    items = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        guid, _, title = part.partition(":")
        guid = guid.strip()
        if not guid:
            sys.exit(f"empty guid in {part!r}")
        entry = {"guid": guid}
        if title.strip():
            entry["title"] = title.strip()
        items.append(entry)
    if not items:
        sys.exit("--list needs at least one guid")
    return items


if len(sys.argv) < 3:
    sys.exit(__doc__)

profile = pathlib.Path(sys.argv[1])
verb = sys.argv[2]

if verb in ("true", "false"):
    mode = "enabled"
elif verb == "--list" and len(sys.argv) == 4:
    mode, items = "list", parse_items(sys.argv[3])
elif verb == "--clear-list":
    mode = "clear"
elif verb == "--layout" and len(sys.argv) == 4:
    mode, layout_value = "layout", parse_layout(sys.argv[3])
elif verb == "--zen-sidebar-pinned" and len(sys.argv) == 4 and sys.argv[3] in ("true", "false", "unset"):
    mode, zen_value = "zen", sys.argv[3]
elif verb == "--show":
    mode = "show"
else:
    sys.exit(__doc__)

prefs = profile / "Default" / "Preferences"
if not prefs.exists():
    prefs = profile / "Preferences"          # some scratch profiles have no Default
if not prefs.exists():
    sys.exit(f"no Preferences file under {profile}")

if mode == "show":
    state = json.loads(prefs.read_text(encoding="utf-8")).get("helium", {})
    workspaces = state.get("workspaces", {})
    layout = state.get("browser", {}).get("layout")
    entries = (workspaces.get("list") or {}).get("items", [])

    # Mirror ParseWorkspaces() in workspace_prefs.cc, which SKIPS any entry whose
    # guid is missing, empty, or a duplicate of one already seen. Listing entries
    # the browser will never load would make this report disagree with the thing
    # it reports on -- and being believed is the only reason this mode exists.
    seen, usable, skipped = set(), [], []
    for entry in entries:
        guid = entry.get("guid")
        if not guid or guid in seen:
            skipped.append(entry)
            continue
        seen.add(guid)
        usable.append(entry)

    others = [e for e in usable if e["guid"] != DEFAULT_GUID]

    print(f"profile: {prefs}")
    print(f"  helium.workspaces.enabled = {workspaces.get('enabled')}")
    print(f"  helium.browser.layout     = {layout}"
          f"  ({'vertical' if layout == LAYOUT_VERTICAL else 'NOT vertical'})")
    print("  helium.workspaces.list    =")
    for entry in usable:
        print(f"      {entry['guid']:<38}{entry.get('title', '')}")
    for entry in skipped:
        # Never formatted with a width specifier -- the guid may be absent, and
        # `None:<38` raises TypeError, which crashed this report mid-print on
        # exactly the malformed profile it is meant to diagnose.
        print(f"      SKIPPED BY THE PARSER (guid missing, empty or duplicate)"
              f"  {entry.get('title', '')}")
    if not entries:
        print("      (none stored -- the registered default applies: one workspace)")

    # Deliberately not a check of `enabled`: the toggle is what a test is often
    # there to flip, and refusing to start because it is currently off would be
    # the script refusing the test it exists to enable.
    problems = []
    if layout != LAYOUT_VERTICAL:
        problems.append("layout is not vertical -- the rail, the toggle and the "
                        "visibility predicate are all switched off (design 2.8)")
    if not others:
        problems.append("no workspace other than the default -- membership and "
                        "switching are both no-ops here (LOCAL.md 16)")
    # The third of the three, and it was PRINTED here without being CHECKED
    # until E9f. A test list that begins "from Home, click W on the rail" needs
    # the feature on, and the state a previous session leaves behind is
    # whatever its last step did -- E9e.4's DCHECK exercise ended on "toggle
    # Workspaces off", so the next run started disabled and this said READY.
    # Printing a value next to a verdict it does not contribute to is the same
    # mistake as counting log lines and not gating on the count (LOCAL.md 24).
    if workspaces.get("enabled") is not True:
        problems.append("the feature is switched off -- nothing is hidden, no "
                        "rail is drawn, and every workspace command is a no-op "
                        "(design 2.8). Turn it on with: "
                        f"set-workspaces-pref.py {profile} true")

    print()
    for problem in problems:
        print(f"NOT READY: {problem}")
    if not problems:
        print("READY: enabled, vertical layout, and a workspace that is not "
              "the default.")
    print("Chrome rewrites this file on exit, so read it with the browser CLOSED.")
    sys.exit(1 if problems else 0)

data = json.loads(prefs.read_text(encoding="utf-8"))
helium = data.setdefault("helium", {})

if mode == "layout":
    # A sibling of "workspaces", not a child: same dotted-path rule as below.
    helium.setdefault("browser", {})["layout"] = layout_value
elif mode == "zen":
    # Helium's zen mode hides the tab list until the mouse reaches the edge, and
    # a hidden view cannot be pressed through MSAA (E14e's switch day pinned it
    # for the import, then put the owner's value back; "unset" = no value).
    browser = helium.setdefault("browser", {})
    if zen_value == "unset":
        browser.pop("zen_mode_sidebar_pinned", None)
    else:
        browser["zen_mode_sidebar_pinned"] = zen_value == "true"
else:
    # "list" is a SIBLING of "enabled" here, never its parent. PrefService
    # stores user values by dotted path, so writing the list at
    # helium.workspaces would replace the node holding the toggle and delete
    # it. See workspace_prefs.h.
    workspaces = helium.setdefault("workspaces", {})
    if mode == "enabled":
        workspaces["enabled"] = verb == "true"
    elif mode == "list":
        workspaces["list"] = {"schema_version": SCHEMA_VERSION, "items": items}
    else:
        workspaces.pop("list", None)

# All-or-nothing, with the first-run .bak kept and a .prev from just before this run
# (profile_write.py): an interrupted write must not leave Preferences half-written.
write_json_atomically([(prefs, data)])

written = json.loads(prefs.read_text(encoding="utf-8"))["helium"]
if mode == "layout":
    value = written["browser"]["layout"]
    print(f"helium.browser.layout = {value}"
          f"  ({'vertical' if value == LAYOUT_VERTICAL else 'NOT vertical'})")
elif mode == "zen":
    print("helium.browser.zen_mode_sidebar_pinned = "
          f"{written.get('browser', {}).get('zen_mode_sidebar_pinned', '(unset)')}")
else:
    print(f"helium.workspaces = {json.dumps(written['workspaces'])}")
print(f"  in {prefs}")
print()
print("Start the browser and confirm at chrome://prefs-internals.")
print("Query a deliberately bogus pref name alongside it (LOCAL.md 8): the page answers")
print("'Preference not found' for one that does not exist, so a page that merely echoes")
print("its input cannot be told from a pass without that control.")
