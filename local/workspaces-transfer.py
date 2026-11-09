"""C19: export / import everything of ours as ONE file -- for a second PC, or a rescue.

What is ours, and so what the file holds (ideas.md C19; LOCAL.md 102):
  prefs.json        the `helium.workspaces` subtree of Preferences: the workspace list (names, icons, colours, order),
                    the Tab style, the toolbar order, the archive timer, ...
  Workspace Pins    every pinned page and folder, per workspace
  Workspace Archive the Archive
  manifest.json     the format, when and from where, the size and SHA-256 of every member above, and counts.
NOT in it: Today tabs and their workspace tags (Chromium's session), history, bookmarks, passwords, settings that are
Chromium's or Helium's own. There is no sync in this browser; these three are the part only this fork knows.

    python local/workspaces-transfer.py export <profile> <file.json | file.zip | file.csv>
    python local/workspaces-transfer.py import <file.json | file.zip> <profile> [--dry-run] [--yes]
    python local/workspaces-transfer.py show <file.json | file.zip>
    python local/workspaces-transfer.py --selftest

The file's extension picks what export writes:
  .json  ONE json file: the manifest, then each member's raw text with its size and SHA-256 ("files": {name: {bytes,
         sha256, content}}). The format the browser's own Export / Import (the "+" menu) reads and writes.
  .zip   the same members and manifest as a zip (C19's first form; still read by import).
  .csv   the pinned pages as a readable list -- workspace, folder, title, address, last used -- for a spreadsheet.
         EXPORT ONLY: a flat list cannot carry folders' colours and open state, splits, the workspace list or the
         Archive, so it can never be restored from.

<profile> is a browser's "User Data" folder or its "Default" folder (the one holding Preferences), e.g.
"%LOCALAPPDATA%\\Helium Workspaces\\User Data".

EXPORT reads only, so it may run while the browser is open. The browser writes the pins a couple of seconds after a
change and Preferences (the workspace list) at its own pace and at exit: export after a pause, or after quitting, to be
sure the last change is in.

IMPORT REPLACES, it does not merge: the profile gets the file's workspace list, pins and archive. It
  - refuses while a browser holds the profile (Chrome keeps <User Data>\\lockfile open),
  - leaves the profile's own "enabled" and "arc_imported_at" (state, not content) as they are,
  - refuses a file whose checksums, format or versions do not hold, BEFORE it writes anything,
  - writes all three files or none (profile_write.py), keeping <name>.transfer.bak (the file as it was the first time
    this script touched it) and <name>.transfer.prev (as it was just before this run),
  - asks to type YES unless --yes (--dry-run asks nothing and writes nothing: it prints what would change).
Tabs the profile already has keep the workspace tags they carry; a tag the new list does not know shows under Home (the
browser's own rule for a deleted workspace), and comes back if that workspace ever exists again.
"""

import argparse
import datetime
import hashlib
import json
import os
import pathlib
import sys
import tempfile
import time
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from profile_write import write_json_atomically  # noqa: E402

FORMAT = "helium-workspaces-export"
VERSION = 1
PINS, ARCHIVE, PREFS = "Workspace Pins", "Workspace Archive", "Preferences"
PREFS_MEMBER = "prefs.json"
MEMBERS = (PREFS_MEMBER, PINS, ARCHIVE)
# The newest file versions this script understands (the browser's own: kPinFileVersion, the archive's version).
MAX_PINS_VERSION = 2
MAX_ARCHIVE_VERSION = 1
# State, not content, and this PC's settings: an import leaves the profile's own value of these, as the browser's
# Import does (workspace_prefs.cc ApplyImportedValues; transfer F2).
KEPT_PREFS = ("enabled", "arc_imported_at", "arc_imported_ids", "toolbar_order", "little_window",
              "archive_after_minutes", "tab_row_height", "smooth_scrolling", "wide_sidebar")
# The workspace list's schema the browser reads (workspace_prefs.h kSchemaVersion; transfer F9).
LIST_SCHEMA_VERSION = 1


def foreign_address(url):
    """Transfer F8, as the browser's workspace_transfer.cc IsForeignAddress: a script, or a file on another computer
    (Windows would connect to it), judged as the browser's parser reads the text on Windows (R2-16): spaces and control
    characters trimmed, tabs and newlines dropped, a backslash a slash, a file address that is neither a drive nor
    three slashes a computer; a view-source page loads the address inside it. Every other address the browser keeps."""
    low = "".join(c for c in str(url) if c not in "\t\r\n").strip("".join(map(chr, range(33)))).lower()
    if low.startswith("view-source:"):
        low = low[len("view-source:"):]
    if low.startswith("javascript:"):
        return True
    if not low.startswith("file:"):
        return False
    rest = low[len("file:"):]
    path = rest.lstrip("/\\")
    drive = len(path) >= 2 and path[0].isalpha() and path[1] in ":|" and path[2:3] in ("", "/", "\\")
    return bool(path) and not drive and len(rest) - len(path) != 3


class TransferError(Exception):
    pass


def profile_paths(arg):
    """(User Data dir, Default dir) from either one."""
    p = pathlib.Path(arg)
    if (p / PREFS).is_file():
        return p.parent, p
    if (p / "Default" / PREFS).is_file():
        return p, p / "Default"
    raise TransferError(f"no {PREFS} in {p} or {p / 'Default'}: not a browser profile")


def browser_running(user_data):
    """True while a browser holds the profile: Chrome opens <User Data>\\lockfile with no sharing."""
    lock = user_data / "lockfile"
    if not lock.exists():
        return False
    try:
        with open(lock, "r+b"):
            return False
    except OSError:
        return True


def count_pages(nodes):
    """(pages, folders) under a list of pin rows, any depth; a split is its two items."""
    pages = folders = 0
    for n in nodes:
        if n.get("type") == "item":
            pages += 1
        elif n.get("type") == "folder":
            folders += 1
        p, f = count_pages(n.get("children", []))
        pages, folders = pages + p, folders + f
    return pages, folders


def summarize(members):
    """Counts for the manifest and the plan, from the three members' parsed JSON."""
    out = {}
    prefs = members.get(PREFS_MEMBER)
    if prefs is not None:
        items = prefs.get("helium", {}).get("workspaces", {}).get("list", {}).get("items", [])
        out["workspaces"] = len(items)
    pins = members.get(PINS)
    if pins is not None:
        pages = folders = 0
        for rows in pins.get("workspaces", {}).values():
            p, f = count_pages(rows)
            pages, folders = pages + p, folders + f
        out["pinned_pages"], out["folders"] = pages, folders
    archive = members.get(ARCHIVE)
    if archive is not None:
        out["archive_entries"] = len(archive.get("entries", []))
    return out


def validate(members):
    """Raises TransferError unless each present member is a file this script, and so the browser, accepts."""
    prefs = members.get(PREFS_MEMBER)
    if prefs is None:
        raise TransferError(f"the file has no {PREFS_MEMBER}")
    ws = prefs.get("helium", {}).get("workspaces") if isinstance(prefs, dict) else None
    if not isinstance(ws, dict):
        raise TransferError(f"{PREFS_MEMBER} has no helium.workspaces")
    pins = members.get(PINS)
    if pins is not None:
        v = pins.get("version") if isinstance(pins, dict) else None
        if not isinstance(v, int) or not 1 <= v <= MAX_PINS_VERSION:
            raise TransferError(f"{PINS}: version {v!r} is not one this script knows (1-{MAX_PINS_VERSION})")
        w = pins.get("workspaces")
        if not isinstance(w, dict) or not all(isinstance(r, list) for r in w.values()):
            raise TransferError(f"{PINS}: 'workspaces' is not a table of lists")
    archive = members.get(ARCHIVE)
    if archive is not None:
        v = archive.get("version") if isinstance(archive, dict) else None
        if not isinstance(v, int) or not 1 <= v <= MAX_ARCHIVE_VERSION:
            raise TransferError(f"{ARCHIVE}: version {v!r} is not one this script knows (1-{MAX_ARCHIVE_VERSION})")
        if not isinstance(archive.get("entries"), list):
            raise TransferError(f"{ARCHIVE}: 'entries' is not a list")
    lst = ws.get("list")
    schema = lst.get("schema_version") if isinstance(lst, dict) else None
    # The browser reads it as an int (FindInt): 1.0 or true is not 1 there.
    if schema is not None and (type(schema) is not int or schema != LIST_SCHEMA_VERSION):
        raise TransferError(f"the workspace list's schema_version {schema!r} is not this browser's "
                            f"({LIST_SCHEMA_VERSION})")


def leave_out_foreign(members):
    """Transfer F8 on import, as the browser's ParseExport (R2-17): every pinned page and archived tab foreign_address
    names is left out and the rest read, rather than the file refused. A split left with one page is that page again,
    one left with none goes. Returns how many were left out."""
    def prune(nodes):
        kept, gone = [], 0
        for n in nodes:
            if isinstance(n, dict) and n.get("type") == "item" and foreign_address(n.get("url", "")):
                gone += 1
                continue
            if isinstance(n, dict) and isinstance(n.get("children"), list):
                n["children"], g = prune(n["children"])
                gone += g
                if n.get("type") == "split" and len(n["children"]) < 2:
                    kept.extend(n["children"])
                    continue
            kept.append(n)
        return kept, gone
    gone = 0
    pins = members.get(PINS)
    if pins is not None:
        for guid, rows in pins["workspaces"].items():
            pins["workspaces"][guid], g = prune(rows)
            gone += g
    archive = members.get(ARCHIVE)
    if archive is not None:
        entries = archive["entries"]
        archive["entries"] = [e for e in entries if not (isinstance(e, dict) and foreign_address(e.get("url", "")))]
        gone += len(entries) - len(archive["entries"])
    return gone


def orphan_workspaces(members):
    """Workspaces the pins file keeps rows for that the list does not name (they show under Home)."""
    prefs, pins = members.get(PREFS_MEMBER), members.get(PINS)
    if prefs is None or pins is None:
        return []
    known = {i.get("guid") for i in prefs["helium"]["workspaces"].get("list", {}).get("items", [])}
    known.add("default")
    return sorted(g for g in pins.get("workspaces", {}) if g not in known)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def _raw_members(default):
    """{member name: bytes} of this profile's three members, and the parsed JSON of each."""
    prefs = json.loads((default / PREFS).read_text(encoding="utf-8"))
    ws = prefs.get("helium", {}).get("workspaces")
    if not isinstance(ws, dict):
        raise TransferError("this profile has no Workspace settings (helium.workspaces): nothing to export")
    raw = {PREFS_MEMBER: json.dumps({"helium": {"workspaces": ws}}, ensure_ascii=False, indent=1).encode("utf-8")}
    for name in (PINS, ARCHIVE):
        f = default / name
        if f.is_file():
            raw[name] = f.read_bytes()
    parsed = {k: json.loads(v.decode("utf-8")) for k, v in raw.items()}
    validate(parsed)
    return raw, parsed


def _manifest(default, raw, parsed):
    return {
        "format": FORMAT,
        "version": VERSION,
        "exported_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        # Not the profile's folder: it holds the Windows user name.
        "source": "workspaces-transfer.py",
        "files": {k: {"bytes": len(v), "sha256": sha256(v)} for k, v in raw.items()},
        "counts": summarize(parsed),
    }


def _write_atomically(out, write):
    out = pathlib.Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".tmp")
    write(tmp)
    os.replace(tmp, out)


def export_file(profile, out):
    """Writes `out` -- .json, .zip or .csv by its extension; returns the manifest (counts, for a csv)."""
    user_data, default = profile_paths(profile)
    kind = pathlib.Path(out).suffix.lower()
    if kind == ".csv":
        return export_csv(default, out)
    raw, parsed = _raw_members(default)
    manifest = _manifest(default, raw, parsed)
    if kind == ".json":
        doc = dict(manifest)
        doc["files"] = {k: dict(v, content=raw[k].decode("utf-8")) for k, v in manifest["files"].items()}
        _write_atomically(out, lambda tmp: tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8"))
    elif kind == ".zip":
        def write(tmp):
            with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
                z.writestr("manifest.json", json.dumps(manifest, indent=1))
                for k, v in raw.items():
                    z.writestr(k, v)
        _write_atomically(out, write)
    else:
        raise TransferError(f"{out}: export writes .json, .zip or .csv")
    return manifest


CSV_COLUMNS = ("workspace", "folder", "kind", "title", "url", "last_used")


def readable_time(chromium_us):
    """Chromium time (microseconds since 1601-01-01 UTC, kept as a string) as 'YYYY-MM-DD HH:MM' UTC; '' for none."""
    try:
        us = int(chromium_us)
    except (TypeError, ValueError):
        return ""
    if us <= 0:
        return ""
    when = datetime.datetime(1601, 1, 1) + datetime.timedelta(microseconds=us)
    return when.strftime("%Y-%m-%d %H:%M")


def csv_rows(parsed):
    """The pinned pages as table rows, in the order the workspace list and the rows draw them."""
    ws = parsed[PREFS_MEMBER]["helium"]["workspaces"]
    items = ws.get("list", {}).get("items", [])
    names = {i.get("guid"): (i.get("title") or ("Home" if i.get("guid") == "default" else i.get("guid"))) for i in items}
    names.setdefault("default", "Home")
    order = [i.get("guid") for i in items if i.get("guid") in parsed[PINS]["workspaces"]]
    order += [g for g in parsed[PINS]["workspaces"] if g not in order]
    rows = []

    def walk(guid, nodes, path):
        for n in nodes:
            kind = n.get("type")
            if kind == "folder":
                walk(guid, n.get("children", []), path + [n.get("title", "")])
            elif kind == "split":
                for side, page in zip(("split-left", "split-right"), n.get("children", [])):
                    rows.append((names.get(guid, guid), " / ".join(path), side, page.get("custom_title") or page.get("title", ""),
                                 page.get("url", ""), readable_time(page.get("last_active"))))
            elif kind == "item":
                rows.append((names.get(guid, guid), " / ".join(path), "page", n.get("custom_title") or n.get("title", ""),
                             n.get("url", ""), readable_time(n.get("last_active"))))

    for guid in order:
        walk(guid, parsed[PINS]["workspaces"][guid], [])
    return rows


def csv_safe(cell):
    """A spreadsheet runs a cell that starts with = + - @ (or a tab or carriage return) as a formula, and a page's
    title is the web's to choose: such a cell is made text with a leading quote."""
    return "'" + cell if cell and cell[0] in "=+-@\t\r" else cell


def export_csv(default, out):
    import csv
    raw, parsed = _raw_members(default)
    if PINS not in parsed:
        raise TransferError("this profile has no pinned pages file: nothing to put in a csv")
    rows = [tuple(csv_safe(c) for c in row) for row in csv_rows(parsed)]

    def write(tmp):
        # UTF-8 with a byte-order mark, so Excel reads accents and emoji right.
        with open(tmp, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(CSV_COLUMNS)
            w.writerows(rows)
    _write_atomically(out, write)
    return {"counts": {"rows": len(rows)}}

def _check_member(name, meta, data):
    if name not in MEMBERS:
        raise TransferError(f"the manifest names {name!r}, which this script does not know")
    if len(data) != meta.get("bytes") or sha256(data) != meta.get("sha256"):
        raise TransferError(f"{name}: size or SHA-256 differs from the manifest: the file was changed or damaged")
    try:
        return json.loads(data.decode("utf-8"))
    except ValueError as e:
        raise TransferError(f"{name} is not JSON: {e}")


def _check_manifest(manifest):
    if not isinstance(manifest, dict) or manifest.get("format") != FORMAT:
        raise TransferError(f"format {manifest.get('format') if isinstance(manifest, dict) else None!r}, not {FORMAT!r}")
    if not isinstance(manifest.get("version"), int) or manifest["version"] < 1:
        raise TransferError(f"export version {manifest.get('version')!r} is not one this script knows")
    if manifest["version"] > VERSION:
        raise TransferError(f"export version {manifest.get('version')!r} is newer than this script's {VERSION}")


def read_export(path):
    """(manifest, {member: parsed JSON}) from an export file (.json or .zip, told by its first bytes), every checksum
    verified. Raises TransferError."""
    try:
        with open(path, "rb") as f:
            head = f.read(2)
    except OSError as e:
        raise TransferError(f"{path}: {e}")
    parsed = {}
    if head == b"PK":
        try:
            z = zipfile.ZipFile(path)
        except (OSError, zipfile.BadZipFile) as e:
            raise TransferError(f"{path} is not a zip file: {e}")
        with z:
            try:
                manifest = json.loads(z.read("manifest.json"))
            except (KeyError, ValueError):
                raise TransferError("no readable manifest.json: not an export of this tool")
            _check_manifest(manifest)
            for name, meta in manifest.get("files", {}).items():
                try:
                    data = z.read(name)
                except KeyError:
                    raise TransferError(f"the manifest names {name!r} but the zip has no such member")
                parsed[name] = _check_member(name, meta, data)
    else:
        try:
            manifest = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        except ValueError as e:
            raise TransferError(f"{path} is neither a zip nor a json export: {e}")
        _check_manifest(manifest)
        for name, meta in manifest.get("files", {}).items():
            content = meta.get("content")
            if not isinstance(content, str):
                raise TransferError(f"{name}: the file holds no content for it")
            parsed[name] = _check_member(name, meta, content.encode("utf-8"))
    validate(parsed)
    manifest["left_out"] = leave_out_foreign(parsed)
    for meta in manifest.get("files", {}).values():
        meta.pop("content", None)
    return manifest, parsed

def import_file(path, profile, dry_run=False, yes=False, ask=input, say=print):
    manifest, parsed = read_export(path)
    user_data, default = profile_paths(profile)
    if browser_running(user_data):
        raise TransferError(f"a browser holds {user_data} (lockfile): close it first, then import")
    cur_prefs = json.loads((default / PREFS).read_text(encoding="utf-8"))
    cm = {PREFS_MEMBER: {"helium": {"workspaces": cur_prefs.get("helium", {}).get("workspaces", {})}}}
    for name in (PINS, ARCHIVE):
        f = default / name
        if f.is_file():
            try:
                cm[name] = json.loads(f.read_text(encoding="utf-8"))
            except ValueError:
                pass
    current = summarize(cm)
    incoming = summarize(parsed)
    say(f"export of {manifest.get('exported_at')} from {manifest.get('source')}")
    for key, label in (("workspaces", "workspaces"), ("pinned_pages", "pinned pages"), ("folders", "folders"),
                       ("archive_entries", "archive entries")):
        if key in incoming or key in current:
            say(f"  {label:16} now {current.get(key, '-'):>6}   ->   file {incoming.get(key, 0):>6}")
    if manifest["left_out"]:
        say(f"  left out: {manifest['left_out']} pinned pages or archived tabs at a script or a file on another computer")
    for g in orphan_workspaces(parsed):
        say(f"  note: pins are kept for workspace {g}, which the list does not name: they will show under Home")
    if dry_run:
        say("dry run: nothing written")
        return False
    if not yes:
        if ask(f"Replace the workspace list, pins and archive in {default} with this file? Type YES: ").strip() != "YES":
            say("not confirmed: nothing written")
            return False
    # The profile's own state flags stay: whether Workspaces is on, and whether Arc was imported here.
    old_ws = cur_prefs.get("helium", {}).get("workspaces", {})
    new_ws = dict(parsed[PREFS_MEMBER]["helium"]["workspaces"])
    for key in KEPT_PREFS:
        new_ws.pop(key, None)
        if key in old_ws:
            new_ws[key] = old_ws[key]
    cur_prefs.setdefault("helium", {})["workspaces"] = new_ws
    # A file without its pins or Archive has none (its count said 0), as the browser's Import reads it (transfer F5).
    files = [(default / PREFS, cur_prefs),
             (default / PINS, parsed.get(PINS, {"version": MAX_PINS_VERSION, "workspaces": {}})),
             (default / ARCHIVE, parsed.get(ARCHIVE, {"version": MAX_ARCHIVE_VERSION, "entries": []}))]
    # The YES prompt can wait for ever: a browser opened meanwhile has read the old files (transfer F4).
    if browser_running(user_data):
        raise TransferError(f"a browser holds {user_data} (lockfile): close it first, then import")
    write_json_atomically(files, suffix=".transfer")
    say(f"imported into {default}: " + ", ".join(p.name for p, _ in files))
    return True


# ---------------------------------------------------------------- self-test
def _fake_profile(root, tag, pages):
    d = pathlib.Path(root) / tag / "Default"
    d.mkdir(parents=True)
    items = [{"guid": "default"}, {"guid": f"{tag}-work", "title": f"{tag} Work", "icon": "\U0001f426"}]
    (d / PREFS).write_text(json.dumps({"helium": {"workspaces": {"enabled": True, "list": {"items": items},
                                                                  "tab_row_height": 40}}, "other": {"keep": tag}}), encoding="utf-8")
    rows = [{"type": "item", "id": f"{tag}{i}", "title": f"Page {i}", "url": f"https://example.com/{i}"} for i in range(pages)]
    folder = {"type": "folder", "id": f"{tag}f", "title": "F", "open": True, "children": rows[:2]}
    (d / PINS).write_text(json.dumps({"version": 2, "workspaces": {"default": [folder] + rows[2:], f"{tag}-work": rows[:1]}}),
                          encoding="utf-8")
    (d / ARCHIVE).write_text(json.dumps({"version": 1, "entries": [{"id": "e1", "url": "https://a.example/", "title": "A"}]}),
                             encoding="utf-8")
    return d.parent


def selftest():
    import shutil
    ok = []

    def check(name, cond):
        ok.append(cond)
        print(("PASS  " if cond else "FAIL  ") + name)

    def refuses(fn):
        try:
            fn()
        except TransferError as e:
            return str(e)
        return None

    with tempfile.TemporaryDirectory() as root:
        a = _fake_profile(root, "a", 6)
        b = _fake_profile(root, "b", 3)
        z = pathlib.Path(root) / "x.zip"
        m = export_file(a, z)
        check("export: the manifest counts 2 workspaces, 7 pinned pages, 1 folder, 1 archive entry",
              m["counts"] == {"workspaces": 2, "pinned_pages": 7, "folders": 1, "archive_entries": 1})
        check("export: Preferences' other keys are not in the file", "other" not in json.dumps(read_export(z)[1][PREFS_MEMBER]))
        out = []
        check("dry run writes nothing", import_file(z, b, dry_run=True, say=out.append) is False
              and json.loads((b / "Default" / PINS).read_text())["workspaces"].get("b-work") is not None)
        check("a wrong answer writes nothing", import_file(z, b, ask=lambda _: "yes", say=out.append) is False
              and (b / "Default" / PINS).read_text().count("Page 2") >= 1 and "a-work" not in (b / "Default" / PREFS).read_text())
        check("import --yes writes", import_file(z, b, yes=True, say=out.append) is True)
        same = all(json.loads((a / "Default" / n).read_text()) == json.loads((b / "Default" / n).read_text()) for n in (PINS, ARCHIVE))
        check("round trip: pins and archive equal the source's", same)
        pa = json.loads((a / "Default" / PREFS).read_text())
        pb = json.loads((b / "Default" / PREFS).read_text())
        check("round trip: the workspace list equals the source's and the profile's other prefs are kept",
              pb["helium"]["workspaces"] == pa["helium"]["workspaces"] and pb["other"] == {"keep": "b"})
        d = _fake_profile(root, "d", 2)
        dp = json.loads((d / "Default" / PREFS).read_text())
        dp["helium"]["workspaces"]["enabled"] = False
        dp["helium"]["workspaces"]["arc_imported_at"] = "999"
        (d / "Default" / PREFS).write_text(json.dumps(dp))
        import_file(z, d, yes=True, say=out.append)
        dw = json.loads((d / "Default" / PREFS).read_text())["helium"]["workspaces"]
        check("import keeps the profile's own 'enabled' and 'arc_imported_at', takes the file's list",
              dw["enabled"] is False and dw["arc_imported_at"] == "999" and dw["list"] == pa["helium"]["workspaces"]["list"])
        check(".transfer.bak holds b's file as it was", "b-work" in (b / "Default" / (PINS + ".transfer.bak")).read_text())
        z2 = pathlib.Path(root) / "y.zip"
        export_file(b, z2)
        check("re-export of the imported profile holds the same pins, archive and list as the first export",
              all(read_export(z2)[1][n] == read_export(z)[1][n] for n in MEMBERS))
        # a damaged file
        bad = pathlib.Path(root) / "bad.zip"
        with zipfile.ZipFile(z) as zi, zipfile.ZipFile(bad, "w") as zo:
            for n in zi.namelist():
                data = zi.read(n)
                zo.writestr(n, data.replace(b"Page 2", b"Page X") if n == PINS else data)
        e = refuses(lambda: read_export(bad))
        check("a changed member is refused by its checksum", e is not None and "SHA-256" in e)
        e = refuses(lambda: read_export(pathlib.Path(root) / "nope.zip"))
        check("a missing file is refused", e is not None)
        notmine = pathlib.Path(root) / "other.zip"
        with zipfile.ZipFile(notmine, "w") as zo:
            zo.writestr("manifest.json", json.dumps({"format": "something-else", "version": 1}))
        check("another tool's zip is refused", refuses(lambda: read_export(notmine)) is not None)
        future = pathlib.Path(root) / "future.zip"
        with zipfile.ZipFile(z) as zi, zipfile.ZipFile(future, "w") as zo:
            man = json.loads(zi.read("manifest.json"))
            man["version"] = VERSION + 1
            zo.writestr("manifest.json", json.dumps(man))
            for n in zi.namelist():
                if n != "manifest.json":
                    zo.writestr(n, zi.read(n))
        check("a newer export version is refused", refuses(lambda: read_export(future)) is not None)
        # the json container (C19.1): the browser's own Export / Import reads and writes this one
        j = pathlib.Path(root) / "x.json"
        mj = export_file(a, j)
        check("json export: the same manifest counts as the zip's", mj["counts"] == m["counts"])
        c = _fake_profile(root, "c", 4)
        import_file(j, c, yes=True, say=out.append)
        check("json round trip: pins, archive and workspace list equal the source's",
              all(json.loads((a / "Default" / n).read_text()) == json.loads((c / "Default" / n).read_text())
                  for n in (PINS, ARCHIVE))
              and json.loads((c / "Default" / PREFS).read_text())["helium"]["workspaces"] == pa["helium"]["workspaces"])
        doc = json.loads(j.read_text(encoding="utf-8"))
        doc["files"][PINS]["content"] = doc["files"][PINS]["content"].replace("Page 2", "Page X")
        jbad = pathlib.Path(root) / "bad.json"
        jbad.write_text(json.dumps(doc), encoding="utf-8")
        e = refuses(lambda: read_export(jbad))
        check("a changed json member is refused by its checksum", e is not None and "SHA-256" in e)
        doc2 = json.loads(j.read_text(encoding="utf-8"))
        doc2["files"][PINS].pop("content")
        jbad.write_text(json.dumps(doc2), encoding="utf-8")
        check("a json member without content is refused", refuses(lambda: read_export(jbad)) is not None)
        check("the manifest read from a json export does not carry the content",
              all("content" not in v for v in read_export(j)[0]["files"].values()))
        # the csv: a readable list, export only
        import csv
        cv = pathlib.Path(root) / "x.csv"
        export_file(a, cv)
        with open(cv, encoding="utf-8-sig", newline="") as f:
            table = list(csv.reader(f))
        check("csv: the header, one row per pinned page (7), the workspaces' names, the folder's path",
              tuple(table[0]) == CSV_COLUMNS and len(table) == 1 + 7
              and {r[0] for r in table[1:]} == {"Home", "a Work"} and sum(1 for r in table[1:] if r[1] == "F") == 2)
        check("a csv is not an import file", refuses(lambda: read_export(cv)) is not None)
        check("csv: a cell that starts like a formula is made text; others are left alone",
              csv_safe("=1+1") == "'=1+1" and csv_safe("-5 days") == "'-5 days" and csv_safe("@x") == "'@x"
              and csv_safe("+1") == "'+1" and csv_safe("a = b") == "a = b" and csv_safe("") == "")
        check("csv time: Chromium microseconds since 1601 read as a UTC date; none as empty",
              readable_time("13437074330809987") == "2026-10-21 16:38" and readable_time("0") == ""
              and readable_time(None) == "")
        # The polish batch (LOCAL.md 129): the browser's import rules, mirrored.
        check("export: 'source' names this tool, not the profile's folder (it holds the Windows user name)",
              mj["source"] == "workspaces-transfer.py")
        e2 = _fake_profile(root, "e", 2)
        ep = json.loads((e2 / "Default" / PREFS).read_text())
        ep["helium"]["workspaces"].update({"tab_row_height": 36, "archive_after_minutes": 1440,
                                           "smooth_scrolling": False, "wide_sidebar": False})
        (e2 / "Default" / PREFS).write_text(json.dumps(ep))
        import_file(j, e2, yes=True, say=out.append)
        ew = json.loads((e2 / "Default" / PREFS).read_text())["helium"]["workspaces"]
        check("import keeps this PC's tab style, archive time, scrolling and sidebar width (transfer F2)",
              ew.get("tab_row_height") == 36 and ew.get("archive_after_minutes") == 1440
              and ew.get("smooth_scrolling") is False and ew.get("wide_sidebar") is False)
        noarch = json.loads(j.read_text(encoding="utf-8"))
        noarch["files"].pop(ARCHIVE)
        jna = pathlib.Path(root) / "noarchive.json"
        jna.write_text(json.dumps(noarch), encoding="utf-8")
        f2 = _fake_profile(root, "f", 2)
        import_file(jna, f2, yes=True, say=out.append)
        check("a file without an Archive leaves an empty Archive, as its count said (transfer F5)",
              json.loads((f2 / "Default" / ARCHIVE).read_text())["entries"] == [])

        def with_member(name, edit):
            doc = json.loads(j.read_text(encoding="utf-8"))
            content = json.loads(doc["files"][name]["content"])
            edit(content)
            raw = json.dumps(content).encode("utf-8")
            doc["files"][name] = {"bytes": len(raw), "sha256": sha256(raw), "content": raw.decode("utf-8")}
            p = pathlib.Path(root) / "edited.json"
            p.write_text(json.dumps(doc), encoding="utf-8")
            return p
        for url in ("javascript:alert(1)", "file://host/share/x.html", "JavaScript:x", "file:////host/share/x",
                    "file:\\\\host\\share\\x", "file:host/share/x", " file://host/x", "\nfile://host/x", "java\tscript:x",
                    "view-source:file://host/x"):
            m, p = read_export(with_member(
                PINS, lambda c: c["workspaces"]["default"].append({"type": "item", "id": "zz", "title": "Z", "url": url})))
            check(f"a pinned page at {url!r} is left out, the rest read (transfer F8, R2-16)",
                  m["left_out"] == 1 and "zz" not in json.dumps(p[PINS]) and "a5" in json.dumps(p[PINS]))
        m, p = read_export(with_member(ARCHIVE, lambda c: c["entries"][0].update(url="file://fileserver/r.pdf")))
        check("an archived tab on a network share is left out, the file read (transfer F8, R2-17)",
              m["left_out"] == 1 and p[ARCHIVE]["entries"] == [])
        m, p = read_export(with_member(PINS, lambda c: c["workspaces"]["default"].append({"type": "split", "id": "s",
            "title": "", "children": [{"type": "item", "id": "sl", "title": "L", "url": "https://l.example/"},
                                      {"type": "item", "id": "sr", "title": "R", "url": "file://host/r"}]})))
        check("a split with one half left out is its other half, a page (transfer F8, E19)",
              m["left_out"] == 1 and p[PINS]["workspaces"]["default"][-1].get("id") == "sl")
        check("what the browser itself keeps is imported: a local file, chrome://, an extension's page, data:, about:"
              " (transfer F8)", refuses(lambda: read_export(with_member(
                  PINS, lambda c: c["workspaces"]["default"].extend([
                      {"type": "item", "id": f"y{i}", "title": "Y", "url": u} for i, u in enumerate((
                          "file:///C:/Docs/a.pdf", "chrome://settings/", "chrome-extension://abc/x.html",
                          "data:text/html,x", "about:blank"))])))) is None)
        e = refuses(lambda: read_export(with_member(
            PREFS_MEMBER, lambda c: c["helium"]["workspaces"]["list"].update(schema_version=2))))
        check("a workspace list of another schema is refused (transfer F9)", e is not None and "schema" in e)
        e = refuses(lambda: read_export(with_member(
            PREFS_MEMBER, lambda c: c["helium"]["workspaces"]["list"].update(schema_version=1.0))))
        check("a schema_version of 1.0 is refused: the browser reads it as no version (transfer F9)", e is not None)
        zero = json.loads(j.read_text(encoding="utf-8"))
        zero["version"] = 0
        jz = pathlib.Path(root) / "zero.json"
        jz.write_text(json.dumps(zero), encoding="utf-8")
        e = refuses(lambda: read_export(jz))
        check("an export version below 1 is refused, not called newer (transfer F10)", e is not None and "newer" not in e)
        # the running-browser refusal, with a real exclusive lock as Chrome keeps it
        if os.name == "nt":
            import ctypes
            k32 = ctypes.windll.kernel32
            k32.CreateFileW.restype = ctypes.c_void_p
            lock = b / "lockfile"
            h = k32.CreateFileW(str(lock), 0xC0000000, 0, None, 4, 0, None)
            try:
                check("a held lockfile is detected as a running browser", browser_running(b))
                e = refuses(lambda: import_file(z, b, yes=True, say=out.append))
                check("import refuses while the browser holds the profile", e is not None and "lockfile" in e)
            finally:
                k32.CloseHandle(ctypes.c_void_p(h))
            lock.unlink(missing_ok=True)
            # Transfer F4: a browser opened while the YES prompt waited.
            held = []

            def open_then_yes(_):
                held.append(k32.CreateFileW(str(lock), 0xC0000000, 0, None, 4, 0, None))
                return "YES"
            try:
                e = refuses(lambda: import_file(z, b, ask=open_then_yes, say=out.append))
                check("import checks for the browser again after the YES prompt (transfer F4)",
                      e is not None and "lockfile" in e)
            finally:
                for h in held:
                    k32.CloseHandle(ctypes.c_void_p(h))
            lock.unlink(missing_ok=True)
        check("no lockfile: not running", not browser_running(b))
    print("SELFTEST", "PASS" if all(ok) else "FAIL", f"{sum(ok)}/{len(ok)}")
    return all(ok)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd")
    e = sub.add_parser("export")
    e.add_argument("profile")
    e.add_argument("file")
    i = sub.add_parser("import")
    i.add_argument("file")
    i.add_argument("profile")
    i.add_argument("--dry-run", action="store_true")
    i.add_argument("--yes", action="store_true")
    s = sub.add_parser("show")
    s.add_argument("file")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    try:
        if a.selftest:
            return 0 if selftest() else 1
        if a.cmd == "export":
            m = export_file(a.profile, a.file)
            print(f"exported {a.file}")
            for k, v in m["counts"].items():
                print(f"  {k}: {v}")
            print("  (a change made in the last few seconds may not be in it: the browser saves after a pause)")
        elif a.cmd == "import":
            import_file(a.file, a.profile, dry_run=a.dry_run, yes=a.yes)
        elif a.cmd == "show":
            m, parsed = read_export(a.file)
            print(json.dumps(m, indent=1))
            for g in orphan_workspaces(parsed):
                print(f"note: pins are kept for workspace {g}, which the list does not name")
        else:
            ap.print_help()
            return 2
    except TransferError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
