"""Add Arc's own archive to a fork profile's Workspace Archive (E14e).

"Import from Arc" brings Arc's spaces, pinned pages and Today tabs into the
fork, but not Arc's ARCHIVE -- the tabs Arc closed for you (its "Archived Tabs").
This script adds those, each under the workspace its Arc space became, so the
fork's Archive screen shows them and a restore opens them in the right place.

    python local/import-arc-archive.py <user-data-dir>              dry run: writes nothing
    python local/import-arc-archive.py <user-data-dir> --write      really write
    python local/import-arc-archive.py <user-data-dir> --arc-dir <folder> [--write]
    python local/import-arc-archive.py --verify <user-data-dir>     check the file, read-only
    python local/import-arc-archive.py --selftest

<user-data-dir> is the folder that HOLDS "Default" (the one given to the browser
as --user-data-dir), not Default itself.

--arc-dir is the folder holding Arc's StorableArchiveItems.json AND
StorableSidebar.json (default: Arc's live folder, %LOCALAPPDATA%\\Packages\\
TheBrowserCompany.Arc_*\\LocalCache\\Local\\Arc). Only those two exact names are
read -- never one of the dated copies Arc keeps beside them. A dry run may read
Arc's live folder while Arc is open (Arc's save can fail for the moment of the
read).

Where each entry goes: its Arc space -> that space's title, as the importer gave
it (an empty title is "Space") -> the FIRST workspace with exactly that title,
which is the one "Import from Arc" used. An entry with no space (Little Arc),
a space no longer in Arc's sidebar, or a title no workspace has goes to Home.

Left out, each counted: not a web page (only http:// and https:// -- what the
importer takes); archived more than 60 days ago minus an hour (the browser drops
entries older than 60 days when it loads the file; the hour keeps its load count
equal to the file's); a reason other than manual / auto or no archivedAt time
("unreadable"); already in the file (a re-run adds nothing).

It REFUSES, writing nothing, when: the profile has no readable Preferences;
"Import from Arc" has not run in it (run that first -- it creates the
workspaces this script files the entries under); an existing Workspace Archive
is one the browser would not load (it would set the file aside and start empty)
or is from a newer version; Arc's files are missing or not in the shape this
script knows; and while the profile is in use -- its lockfile is there, or a
chrome.exe runs with this folder on its command line, or that could not be
checked (a dry run too: the browser would change the numbers under it). CLOSE THE BROWSER FIRST: it rewrites the archive 2.5 s after any
change and at exit, which would undo the write.

The file after: every entry already in it kept exactly, in its order, the new
ones merged in oldest first (the browser's order). The result is checked against
the browser's own rules (ArchiveFromValue, workspace_archive.cc) before anything
is written, and written all-or-nothing (profile_write.py): a copy of the file as
it was is kept as "Workspace Archive.arc-archive.bak" (the first time, never
overwritten) and ".arc-archive.prev" (just before this run).

Privacy: prints counts, guids and file paths only -- never an address or a page
title. Workspace names appear on the console only. The last line is:
    RESULT arc=<n> added=<n> already=<n> not_web=<n> too_old=<n> bad=<n> home=<n> file_total=<n> written=yes|no
(a dry run: written=no, file_total as it WOULD be; exit 0).

--verify prints "VERIFY entries=<n> ok=yes|no" (the first problem on the line
before it) and exits 0 only when the browser would load the file; a missing file
is "entries=0 ok=no". It only reads, so it is safe while a browser runs.

Arc's format is undocumented and can change with any Arc update.
"""

import argparse
import base64
import collections
import contextlib
import heapq
import io
import json
import math
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

from profile_write import write_json_atomically

FILE_NAME = "Workspace Archive"             # ArchiveStore::kFileName
REASONS = ("manual", "window", "auto")      # ReasonName(), workspace_archive.cc
ARC_REASONS = ("manual", "auto")            # the two Arc writes
# Copied from make-archive-fixture.py (its hyphenated name cannot be imported):
# base::Time::kMicrosecondsFromWindowsToUnixEpoch.
WINDOWS_EPOCH_US = 11644473600000000
ARC_EPOCH_S = 978307200                     # Arc counts seconds from 2001-01-01 UTC
# kKeepFor (60 days) minus an hour, so nothing added is pruned at the next load.
KEEP_US = (60 * 86400 - 3600) * 1_000_000
INT64 = 2 ** 63
HOME = "default"                            # kDefaultWorkspaceGuid
# Why an entry went to Home, in the order the report lists them.
HOME_CAUSES = ("no space (Little Arc or unknown)", "a space no longer in Arc's sidebar",
               "a space with no workspace of its name")


class Refused(Exception):
    """Why the script stops without writing; main() prints it and exits 1."""


def now_us():
    """Now as base::Time counts it: microseconds since 1601-01-01 UTC."""
    return time.time_ns() // 1000 + WINDOWS_EPOCH_US


def parse_time(value):
    """base::ValueToTime: an int64 written as a decimal STRING -> the int, else
    None. A JSON number is refused, as the browser refuses it."""
    if isinstance(value, str) and re.fullmatch(r"[+-]?[0-9]+", value):
        n = int(value)
        if -INT64 <= n < INT64:
            return n
    return None


def arc_time(seconds):
    """Arc's float seconds since 2001 -> our time string, or None when it is not
    a usable number (true/false are JSON booleans, not numbers)."""
    if (isinstance(seconds, bool) or not isinstance(seconds, (int, float))
            or not math.isfinite(seconds)):
        return None
    us = round((seconds + ARC_EPOCH_S) * 1_000_000) + WINDOWS_EPOCH_US
    return str(us) if -INT64 <= us < INT64 else None


def dig(value, *keys):
    """value[k1][k2]..., or None where a step is missing or not a JSON object."""
    for key in keys:
        value = value.get(key) if isinstance(value, dict) else None
    return value


def string_or(d, key, fallback):
    """StringOr (arc_import_plan.cc): an empty string counts as missing."""
    value = d.get(key) if isinstance(d, dict) else None
    return value if isinstance(value, str) and value else fallback


def is_web_url(url):
    """IsWebUrl (arc_import_plan.cc): http:// or https://, ASCII case-insensitive."""
    return isinstance(url, str) and re.match(r"https?://", url, re.I | re.A) is not None


def archive_problem(data):
    """None when ArchiveFromValue (workspace_archive.cc) would load `data`, else
    why not. The browser refuses the WHOLE file for one bad entry, so this is
    checked before every write."""
    if not isinstance(data, dict):
        return "it is not a JSON object"
    version = data.get("version")
    if type(version) is not int or version != 1:    # FindInt: 1.0 or true is not 1
        return "its version is not 1"
    entries = data.get("entries")
    if not isinstance(entries, list):
        return "it has no list of entries"
    ids = set()
    for n, entry in enumerate(entries, 1):
        if not isinstance(entry, dict):
            return f"entry {n} is not a JSON object"
        for key in ("id", "url"):
            if not isinstance(entry.get(key), str) or not entry[key]:
                return f"entry {n} has no {key}"
        if entry.get("reason") not in REASONS:
            return f"entry {n} has an unknown reason"
        if parse_time(entry.get("archived_at")) is None:
            return f"entry {n} has no archived_at time the browser can read"
        if "last_active" in entry and parse_time(entry["last_active"]) is None:
            return f"entry {n} has a last_active time the browser cannot read"
        if entry["id"] in ids:
            return f"entry {n} repeats an id used before it"
        ids.add(entry["id"])
    return None


def _no_constant(name):
    """json accepts NaN and Infinity; the browser's strict reader does not."""
    raise ValueError(name)


def read_archive(path):
    """Reads our archive as ArchiveStore::ReadFile does -> (entries, problem).
    problem is None when the browser would load the file (a missing file loads
    as empty); entries is the file's list whenever it has one, for counting."""
    if not path.exists():
        return [], None
    try:
        data = json.loads(path.read_bytes().decode("utf-8-sig"),
                          parse_constant=_no_constant)
    except OSError as e:
        return [], f"it could not be read ({e.strerror})"
    except ValueError:               # not UTF-8, or not JSON
        return [], "it is not valid JSON"
    entries = dig(data, "entries")
    entries = entries if isinstance(entries, list) else []
    version = dig(data, "version")
    if type(version) is int and version > 1:
        # The browser keeps such a file read-only; writing it would lose it.
        return entries, f"it is from a newer version of the browser (version {version})"
    return entries, archive_problem(data)


def read_json(path, what):
    """A JSON file's content, or Refused with a plain reason."""
    try:
        return json.loads(path.read_bytes().decode("utf-8-sig"))
    except FileNotFoundError:
        raise Refused(f"{what} is missing: {path}")
    except OSError as e:
        raise Refused(f"{what} could not be read ({e.strerror}): {path}")
    except ValueError:
        raise Refused(f"{what} is not valid JSON (if it is Arc's, Arc may have "
                      f"been rewriting it -- run again): {path}")


# Counts chrome.exe processes whose command line holds the folder (children carry
# --user-data-dir too), and those whose command line Windows would not show.
_PS_IN_USE = r"""
$d = $env:IMPORT_ARC_ARCHIVE_UD.TrimEnd('\').ToLowerInvariant()
$p = @(Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" -ErrorAction Stop)
$hit = @($p | Where-Object { $_.CommandLine -and
  $_.CommandLine.ToLowerInvariant().Replace('/', '\').Contains($d) }).Count
$unread = @($p | Where-Object { -not $_.CommandLine }).Count
"$hit $unread"
"""


def profile_in_use(ud):
    """Why a browser may be using `ud`, or None. The lockfile exists only while
    a browser runs on the folder; the command lines catch one starting up."""
    if (ud / "lockfile").exists():
        return "its lockfile is there, so a browser is using it"
    # -EncodedCommand: no quoting of the script survives Windows' command line.
    encoded = base64.b64encode(_PS_IN_USE.encode("utf-16-le")).decode("ascii")
    try:
        r = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
            capture_output=True, text=True, timeout=60, check=True,
            env=dict(os.environ, IMPORT_ARC_ARCHIVE_UD=os.path.abspath(ud)))
        hits, unread = map(int, r.stdout.split())
    except (OSError, subprocess.SubprocessError, ValueError):
        return ("it could not be checked whether a browser is using it (asking "
                "Windows for the running chrome.exe processes failed)")
    if hits:
        return f"{hits} chrome.exe process(es) run with this folder on their command line"
    if unread:
        return (f"{unread} chrome.exe process(es) run whose command line Windows will "
                "not show (run as administrator?), so it cannot be told whether "
                "they use this folder")
    return None


def arc_live_dir():
    """Arc's live data folder. Its package name ends in a publisher hash, so it is
    looked up rather than typed; two matches are refused rather than guessed."""
    found = sorted(pathlib.Path(os.environ.get("LOCALAPPDATA", "")).glob(
        "Packages/TheBrowserCompany.Arc_*/LocalCache/Local/Arc"))
    if len(found) != 1:
        raise Refused(f"Arc's data folder was found {len(found)} times under "
                      "%LOCALAPPDATA%\\Packages -- give it with --arc-dir")
    return found[0]


def main_container(sidebar):
    """MainContainer (arc_import_plan.cc): in sidebar.containers, the element
    right after the dict that has the key "global" -- never a Little Arc window."""
    containers = dig(sidebar, "sidebar", "containers")
    if isinstance(containers, list):
        for key, container in zip(containers, containers[1:]):
            if isinstance(key, dict) and "global" in key:
                return container if isinstance(container, dict) else None
    return None


def space_titles(main):
    """Arc space id -> the title the importer gave its workspace."""
    titles = {}
    spaces = main.get("spaces")
    for space in spaces if isinstance(spaces, list) else []:
        if isinstance(space, dict):     # the list alternates id strings and dicts
            titles.setdefault(string_or(space, "id", ""),
                              string_or(space, "title", "Space"))
    return titles


def workspace_list(prefs):
    """[(guid, title)] in rail order -- ParseWorkspaces()' rule: an entry with a
    missing, empty or repeated guid is skipped (as make-archive-fixture.py reads it)."""
    items = dig(prefs, "helium", "workspaces", "list", "items")
    out, seen = [], set()
    for item in items if isinstance(items, list) else []:
        guid = dig(item, "guid")
        if isinstance(guid, str) and guid and guid not in seen:
            seen.add(guid)
            title = item.get("title")
            out.append((guid, title if isinstance(title, str) else ""))
    return out


def arc_pairs(archive):
    """Arc's {"version":1,"items":[id, entry, id, entry, ...]} -> [(id, entry)]."""
    items, version = dig(archive, "items"), dig(archive, "version")
    if type(version) is not int or version != 1:
        raise Refused("Arc's archive is not version 1 -- Arc has changed its format; "
                      "this script needs updating")
    if (not isinstance(items, list) or len(items) % 2
            or not all(isinstance(i, str) for i in items[::2])
            or not all(isinstance(e, dict) for e in items[1::2])):
        raise Refused("Arc's archive items do not alternate an id and an entry -- Arc "
                      "has changed its format; this script needs updating")
    return list(zip(items[::2], items[1::2]))


def run(ud, arc_dir, write):
    """The import (or its dry run). Prints the report and the RESULT line;
    returns the counts. Raises Refused before writing anything."""
    ud = pathlib.Path(ud)
    prefs = read_json(ud / "Default" / "Preferences", "the profile's Preferences")
    if not parse_time(dig(prefs, "helium", "workspaces", "arc_imported_at")):
        raise Refused("\"Import from Arc\" has not run in this profile -- run it "
                      "first (it creates the workspaces the archive is filed under)")
    workspaces = workspace_list(prefs)
    by_title = {}
    for guid, title in workspaces:
        by_title.setdefault(title, guid)            # EnsureWorkspaceForImport: the first
    # A dry run refuses too: its numbers would be stale the moment the browser
    # rewrites the file.
    why = profile_in_use(ud)
    if why:
        raise Refused(f"the profile is in use: {why}. Close the browser using "
                      f"{ud}, then run again")

    path = ud / "Default" / FILE_NAME
    existing, problem = read_archive(path)
    if problem:
        raise Refused(f"the Workspace Archive already there cannot be added to: "
                      f"{problem}. It is left as it is: {path}")

    arc_dir = pathlib.Path(arc_dir) if arc_dir else arc_live_dir()
    pairs = arc_pairs(read_json(arc_dir / "StorableArchiveItems.json", "Arc's archive"))
    main = main_container(read_json(arc_dir / "StorableSidebar.json", "Arc's sidebar"))
    if main is None:
        raise Refused("Arc's sidebar has no main window (no \"global\" container) -- "
                      "Arc has changed its format; this script needs updating")
    titles = space_titles(main)

    skipped, home, per_workspace, per_reason = (collections.Counter() for _ in range(4))
    ids = {e["id"] for e in existing}
    oldest = now_us() - KEEP_US
    new = []
    for arc_id, item in pairs:
        side = item.get("sidebarItem")
        tab = dig(side, "data", "tab")
        url = dig(tab, "savedURL")
        at = arc_time(item.get("archivedAt"))
        entry_id = "arc-" + arc_id
        if item.get("reason") not in ARC_REASONS or at is None:
            skipped["bad"] += 1
        elif not is_web_url(url):
            skipped["not_web"] += 1
        elif int(at) < oldest:
            skipped["too_old"] += 1
        elif entry_id in ids:
            skipped["already"] += 1
        else:
            space = dig(item, "source", "space", "_0")
            guid = by_title.get(titles.get(space)) if isinstance(space, str) else None
            if guid is None:
                guid = HOME
                home[HOME_CAUSES[0 if not isinstance(space, str)
                                 else 1 if space not in titles else 2]] += 1
            title = string_or(tab, "savedTitle", "")
            typed = string_or(side, "title", "")
            # EntryToValue's key order; custom_title omitted when empty.
            entry = {"id": entry_id, "url": url, "title": title}
            if typed and typed != title:
                entry["custom_title"] = typed
            entry.update(workspace=guid, reason=item["reason"], archived_at=at)
            last = arc_time(dig(tab, "timeLastActiveAt")) or arc_time(dig(side, "createdAt"))
            if last:
                entry["last_active"] = last
            new.append(entry)
            ids.add(entry_id)
            per_workspace[guid] += 1
            per_reason[item["reason"]] += 1

    # Merged, not re-sorted: the file's own entries keep their order among
    # themselves; with the file oldest first this equals a stable sort.
    key = lambda e: parse_time(e["archived_at"])
    merged = list(heapq.merge(existing, sorted(new, key=key), key=key))
    data = {"version": 1, "entries": merged}
    problem = archive_problem(data)
    if problem:
        raise Refused(f"the result would not load in the browser ({problem}); "
                      "nothing was written")
    had_file = path.exists()
    written = bool(write and new)
    if written:
        write_json_atomically([(path, data)], ".arc-archive")

    names = dict(workspaces)
    print(f"Arc's archive:  {arc_dir / 'StorableArchiveItems.json'} ({len(pairs)} entries)")
    print(f"This profile:   {ud} ({len(workspaces)} workspaces; \"Import from Arc\" ran here)")
    print(f"Our archive:    {path} "
          f"({f'{len(existing)} entries before this run' if had_file else 'no file before this run'})")
    print()
    if written:
        print(f"Added {len(new)} entries")
    elif write:
        print("Nothing new to add: the file was left as it is")
    else:
        print(f"Would add {len(new)} entries (a dry run: nothing is written; add "
              "--write to write them)")
    for guid, n in per_workspace.most_common():
        print(f"  {n:>6}  {guid}  ({names.get(guid) or ('Home' if guid == HOME else 'no name')})")
    print(f"  by reason: {per_reason['manual']} manual, {per_reason['auto']} auto")
    print(f"  left out: {skipped['already']} already in the file, {skipped['not_web']} "
          f"not a web page, {skipped['too_old']} archived 60 days ago or more, "
          f"{skipped['bad']} unreadable (no archivedAt time, or a reason other than "
          "manual/auto)")
    print("  put under Home: " + ", ".join(f"{home[c]} with {c}" for c in HOME_CAUSES))
    if written:
        print(f"Written: {path}. Open the browser; the Archive (the rail's +) shows them.")
    elif not write:
        print("To write them: close the browser using this profile, then run the same "
              "command with --write.")
    result = {"arc": len(pairs), "added": len(new), "already": skipped["already"],
              "not_web": skipped["not_web"], "too_old": skipped["too_old"],
              "bad": skipped["bad"], "home": sum(home.values()),
              "file_total": len(merged), "written": "yes" if written else "no"}
    print("RESULT " + " ".join(f"{k}={v}" for k, v in result.items()))
    return result


def verify(ud):
    """--verify: would the browser load <ud>\\Default\\Workspace Archive? Read-only."""
    path = pathlib.Path(ud) / "Default" / FILE_NAME
    entries, problem = read_archive(path)
    if not path.exists():
        problem = f"there is no archive file at {path}"
    if problem:
        print(f"Not ok: {problem}")
    print(f"VERIFY entries={len(entries)} ok={'no' if problem else 'yes'}")
    return 1 if problem else 0


def _selftest():
    assert arc_time(0) == "12622780800000000"       # 2001-01-01 in 1601-microseconds
    assert arc_time(True) is None and arc_time("1") is None and arc_time(float("nan")) is None
    assert parse_time("12622780800000000") == 12622780800000000 and parse_time("+5") == 5
    for bad in (5, " 5", "5.0", "", "-", "9223372036854775808", "١٢"):
        assert parse_time(bad) is None, bad
    assert parse_time("-9223372036854775808") == -INT64
    assert is_web_url("HTTPS://x") and is_web_url("http://x") and not is_web_url("ftp://x")
    assert not is_web_url(None) and not is_web_url("chrome-extension://x/")
    good = {"id": "a", "url": "https://a/", "reason": "manual", "archived_at": "1"}
    assert archive_problem({"version": 1, "entries": [good]}) is None
    for broken in ({"version": 1.0, "entries": []}, {"version": True, "entries": []},
                   {"version": 1, "entries": {}},
                   {"version": 1, "entries": [dict(good, archived_at=1)]},
                   {"version": 1, "entries": [dict(good, url="")]},
                   {"version": 1, "entries": [dict(good, reason="weird")]},
                   {"version": 1, "entries": [dict(good, last_active=None)]},
                   {"version": 1, "entries": [{k: v for k, v in good.items() if k != "archived_at"}]},
                   {"version": 1, "entries": [good, good]}):
        assert archive_problem(broken), broken

    now = now_us()
    day = 86400
    arc_now = (now - WINDOWS_EPOCH_US) / 1e6 - ARC_EPOCH_S
    sidebar = {"sidebar": {"containers": [
        # A Little Arc pair first: its space must not be taken (MainContainer).
        {"littleBrowser": {}}, {"spaces": ["s1", {"id": "s1", "title": "Decoy"}]},
        {"global": {}}, {"items": [], "spaces": [
            "s1", {"id": "s1", "title": "Work"}, "s2", {"id": "s2", "title": ""},
            "s3", {"id": "s3", "title": "Elsewhere"}]}]}}

    def arc(age_days, space="s1", reason="manual", url="https://a.test/", drop=(), **side):
        tab = {"savedURL": url, "savedTitle": "A", "timeLastActiveAt": arc_now - age_days * day - 60}
        for key in drop:
            tab.pop(key)
        return {"archivedAt": arc_now - age_days * day, "reason": reason,
                "sidebarItem": {"id": "?", "createdAt": arc_now - 100 * day, "title": None,
                                "parentID": None, "data": {"tab": tab}, **side},
                "source": {"space": {"_0": space}} if space else {"littleArc": {}}}

    items = {"https": arc(5), "http": arc(3, "s2", "auto", "HTTP://b.test/"),
             "ext": arc(2, url="chrome-extension://abc/"), "nourl": arc(2, drop=["savedURL"]),
             "little": arc(40, None), "gone": arc(20, "s9"), "elsewhere": arc(10, "s3"),
             "old": arc(61), "noactive": arc(4, drop=["timeLastActiveAt"]),
             "notitle": arc(2.5, drop=["savedTitle"]), "custom": arc(1.5, title="Mine"),
             "weird": arc(1, reason="weird")}
    listing = [x for arc_id, e in items.items() for x in (arc_id, e)]
    own = [{"id": "own-old", "url": "https://o.test/", "title": "", "workspace": "w-work",
            "reason": "window", "archived_at": str(now - 30 * day * 10**6),
            "last_active": str(now - 31 * day * 10**6)},
           {"id": "own-new", "url": "https://n.test/", "title": "N", "workspace": HOME,
            "reason": "manual", "archived_at": str(now - 3600 * 10**6)}]

    root = pathlib.Path(tempfile.mkdtemp(prefix="import-arc-archive-selftest-"))
    try:
        arc_dir = root / "arc"
        arc_dir.mkdir()
        (arc_dir / "StorableSidebar.json").write_text(json.dumps(sidebar), encoding="utf-8")
        (arc_dir / "StorableArchiveItems.json").write_text(
            json.dumps({"version": 1, "items": listing}), encoding="utf-8")

        def profile(name, imported=True, archive=None):
            ud = root / name
            (ud / "Default").mkdir(parents=True)
            ws = {"list": {"schema_version": 1, "items": [
                {"title": "Work"},                          # no guid: skipped
                {"guid": HOME, "title": "Home"}, {"guid": "w-work", "title": "Work"},
                {"guid": "w-space", "title": "Space"}, {"guid": "w-work2", "title": "Work"}]}}
            if imported:
                ws["arc_imported_at"] = str(now)
            (ud / "Default" / "Preferences").write_text(
                json.dumps({"helium": {"workspaces": ws}}), encoding="utf-8")
            if archive is not None:
                (ud / "Default" / FILE_NAME).write_text(json.dumps(archive), encoding="utf-8")
            return ud

        def quiet(*args):
            with contextlib.redirect_stdout(io.StringIO()) as out:
                result = run(*args)
            return result, out.getvalue().splitlines()[-1]

        def refused(*args):
            try:
                quiet(*args)
            except Refused:
                return True
            return False

        # A dry run changes nothing and reports what a write would do.
        a = profile("a", archive={"version": 1, "entries": own})
        file = a / "Default" / FILE_NAME
        before = file.read_bytes()
        r, line = quiet(a, arc_dir, False)
        assert line == ("RESULT arc=12 added=8 already=0 not_web=2 too_old=1 bad=1 home=3 "
                        "file_total=10 written=no"), line
        assert file.read_bytes() == before

        r, line = quiet(a, arc_dir, True)
        assert line.endswith("written=yes") and r["added"] == 8, line
        data = json.loads(file.read_text(encoding="utf-8"))
        assert archive_problem(data) is None
        got = data["entries"]
        assert [e for e in got if e["id"].startswith("own-")] == own, "the file's own entries kept"
        assert [e["id"] for e in got] == [   # oldest first, the file's own merged in
            "arc-little", "own-old", "arc-gone", "arc-elsewhere", "arc-https",
            "arc-noactive", "arc-http", "arc-notitle", "arc-custom", "own-new"]
        e = {x["id"]: x for x in got}
        assert e["arc-https"]["workspace"] == "w-work", "the FIRST workspace titled Work"
        assert e["arc-https"]["archived_at"] == arc_time(items["https"]["archivedAt"])
        assert e["arc-https"]["last_active"] == arc_time(
            items["https"]["sidebarItem"]["data"]["tab"]["timeLastActiveAt"])
        assert "custom_title" not in e["arc-https"] and e["arc-https"]["title"] == "A"
        assert (e["arc-http"]["workspace"], e["arc-http"]["reason"]) == ("w-space", "auto")
        assert {e[i]["workspace"] for i in ("arc-little", "arc-gone", "arc-elsewhere")} == {HOME}
        assert e["arc-noactive"]["last_active"] == arc_time(items["noactive"]["sidebarItem"]["createdAt"])
        assert e["arc-notitle"]["title"] == ""
        assert (e["arc-custom"]["custom_title"], e["arc-custom"]["title"]) == ("Mine", "A")
        assert (a / "Default" / (FILE_NAME + ".arc-archive.bak")).exists()

        # A second write adds nothing and leaves the file exactly as it was.
        before = file.read_bytes()
        r, line = quiet(a, arc_dir, True)
        assert (r["added"], r["already"], r["written"]) == (0, 8, "no"), line
        assert file.read_bytes() == before

        # A profile with no archive file yet gets one.
        fresh = profile("fresh")
        r, line = quiet(fresh, arc_dir, True)
        assert r["file_total"] == 8 and r["written"] == "yes", line

        # Refusals write nothing.
        (a / "lockfile").write_text("", encoding="utf-8")
        assert refused(a, arc_dir, True) and refused(a, arc_dir, False), "a lockfile"
        assert file.read_bytes() == before
        (a / "lockfile").unlink()
        newer = {"version": 2, "entries": []}
        b = profile("b", archive=newer)
        assert refused(b, arc_dir, True) and refused(b, arc_dir, False), "a newer file"
        assert json.loads((b / "Default" / FILE_NAME).read_text(encoding="utf-8")) == newer
        assert not list((b / "Default").glob("*.arc-archive.*")), "no backup of a refused run"
        c = profile("c", imported=False)
        assert refused(c, arc_dir, True), "no arc_imported_at must refuse"
        assert not (c / "Default" / FILE_NAME).exists()
        bad_arc = root / "bad-arc"
        shutil.copytree(arc_dir, bad_arc)
        (bad_arc / "StorableArchiveItems.json").write_text(
            json.dumps({"version": 1, "items": ["x"]}), encoding="utf-8")
        assert refused(fresh, bad_arc, False), "Arc's items not alternating"
        (bad_arc / "StorableArchiveItems.json").write_text(
            json.dumps({"version": 1, "items": []}), encoding="utf-8")
        (bad_arc / "StorableSidebar.json").write_text(
            json.dumps({"sidebar": {"containers": [{"spaces": []}]}}), encoding="utf-8")
        assert refused(fresh, bad_arc, False), "no main container"

        # --verify: read-only, and a missing file is not ok.
        with contextlib.redirect_stdout(io.StringIO()) as out:
            assert verify(a) == 0 and verify(c) == 1 and verify(b) == 1
        lines = [x for x in out.getvalue().splitlines() if x.startswith("VERIFY")]
        assert lines == ["VERIFY entries=10 ok=yes", "VERIFY entries=0 ok=no",
                         "VERIFY entries=0 ok=no"], lines
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print("import-arc-archive selftest: PASS")
    return 0


def main():
    p = argparse.ArgumentParser(
        description="Add Arc's archive to a fork profile's Workspace Archive "
                    "(a dry run unless --write).")
    p.add_argument("profile", nargs="?", type=pathlib.Path,
                   help="the fork's user-data dir (the folder that holds Default)")
    p.add_argument("--arc-dir", type=pathlib.Path,
                   help="the folder holding StorableArchiveItems.json and "
                        "StorableSidebar.json (default: Arc's live folder)")
    p.add_argument("--write", action="store_true", help="really write (close the browser first)")
    p.add_argument("--verify", type=pathlib.Path, metavar="USER_DATA_DIR",
                   help="only check that profile's Workspace Archive, read-only")
    p.add_argument("--selftest", action="store_true", help="test this script in a temp folder")
    a = p.parse_args()
    if a.selftest:
        return _selftest()
    if a.verify:
        if a.profile or a.write or a.arc_dir:
            p.error("--verify takes only the user-data dir")
        return verify(a.verify)
    if not a.profile:
        p.error("give the fork's user-data dir (the folder that holds Default)")
    try:
        run(a.profile, a.arc_dir, a.write)
    except Refused as e:
        print(f"REFUSED: {e}")
        print("Nothing was written.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
