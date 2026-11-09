"""Writes a browser profile's JSON files so an interruption cannot leave one half-written.

Used by import-arc-archive.py and set-workspaces-pref.py. Each new file is written in full to
"<name>.tmp" and flushed to disk first; only when EVERY file is staged are the originals
swapped out, each by one os.replace. If a swap fails -- on Windows, another program holding
the file open refuses it -- the files this run already swapped are put back, so the profile is
left as it was, never half-applied. Before the swap, two backups per existing file, both named
after the calling script's suffix so two scripts never overwrite each other's:
  <name><suffix>.bak   the file as it was the first time that script touched it, never
                       overwritten (what these scripts always kept);
  <name><suffix>.prev  the file as it was just before THIS run, replaced each run, and
                       removed if the file did not exist before this run.

Run this file directly for its self-test.
"""

import json
import os
import pathlib
import shutil
import tempfile


def _replace_with_copy(src, dst):
    """A copy that is never seen half-written either: to dst.tmp, flushed, then swapped in."""
    tmp = dst.with_suffix(dst.suffix + ".tmp")
    shutil.copyfile(src, tmp)
    with open(tmp, "rb+") as f:
        os.fsync(f.fileno())
    os.replace(tmp, dst)


def write_json_atomically(files, suffix=""):
    """files: a list of (pathlib.Path, data). Writes all of them, or changes none.

    `suffix` names this caller's backups (".arc-import" -> Bookmarks.arc-import.bak)."""
    staged = []
    try:
        for path, data in files:
            tmp = path.with_suffix(path.suffix + ".tmp")
            # Recorded BEFORE it is opened: open() creates the file, so a write that
            # then fails must still find it here to clean it up.
            staged.append((tmp, path))
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(json.dumps(data, separators=(",", ":")))
                f.flush()
                os.fsync(f.fileno())

        for _, path in staged:
            prev = path.with_suffix(path.suffix + suffix + ".prev")
            if not path.exists():
                prev.unlink(missing_ok=True)   # a .prev must never describe a file that was not there
                continue
            pristine = path.with_suffix(path.suffix + suffix + ".bak")
            if not pristine.exists():
                _replace_with_copy(path, pristine)
                print(f"backup written: {pristine}")
            _replace_with_copy(path, prev)

        swapped = []
        try:
            for tmp, path in staged:
                os.replace(tmp, path)
                swapped.append(path)
        except BaseException:
            # Undo this run's swaps from the .prev it just took, so a refused second swap
            # cannot leave the first file new and the second old (E13 review).
            for path in swapped:
                prev = path.with_suffix(path.suffix + suffix + ".prev")
                if prev.exists():
                    shutil.copyfile(prev, path)
                else:
                    path.unlink(missing_ok=True)
            print("write refused -- nothing changed. Close whatever has the profile open, "
                  "then run again.")
            raise
    finally:
        for tmp, _ in staged:
            tmp.unlink(missing_ok=True)


def _selftest():
    d = pathlib.Path(tempfile.mkdtemp())
    a, b = d / "Bookmarks", d / "Preferences"
    a.write_text('{"v": 1}', encoding="utf-8")
    b.write_text('{"v": 1}', encoding="utf-8")
    load = lambda p: json.loads(p.read_text(encoding="utf-8"))

    write_json_atomically([(a, {"v": 2}), (b, {"v": 2})], ".x")
    assert load(a) == {"v": 2} and load(b) == {"v": 2}
    assert load(d / "Bookmarks.x.bak") == {"v": 1}    # pristine
    assert load(d / "Bookmarks.x.prev") == {"v": 1}   # before this run

    write_json_atomically([(a, {"v": 3})], ".x")
    assert load(d / "Bookmarks.x.bak") == {"v": 1}    # never overwritten
    assert load(d / "Bookmarks.x.prev") == {"v": 2}   # rolled forward

    # Another caller's backups are its own: they do not touch .x's.
    write_json_atomically([(b, {"v": 5})], ".y")
    assert load(d / "Preferences.x.prev") == {"v": 1} and load(d / "Preferences.y.prev") == {"v": 2}
    write_json_atomically([(b, {"v": 2})], ".y")

    # A failure while staging the SECOND file changes neither. A set is not
    # JSON-serialisable, so json.dumps raises.
    try:
        write_json_atomically([(a, {"v": 4}), (b, {"bad": {1}})], ".x")
        raise AssertionError("expected a failure")
    except TypeError:
        pass
    assert load(a) == {"v": 3} and load(b) == {"v": 2}

    # A refused SWAP of the second file -- Windows will not replace a file another
    # process holds open without delete sharing -- rolls the first one back.
    if os.name == "nt":
        with open(b, "rb"):
            try:
                write_json_atomically([(a, {"v": 6}), (b, {"v": 6})], ".x")
                raise AssertionError("expected the swap to be refused")
            except PermissionError:
                pass
        assert load(a) == {"v": 3} and load(b) == {"v": 2}, "a refused swap left a half-applied pair"

    # A file that did not exist: no backups, and a stale .prev is removed.
    c = d / "New"
    (d / "New.x.prev").write_text("stale", encoding="utf-8")
    write_json_atomically([(c, {"v": 1})], ".x")
    assert load(c) == {"v": 1} and not (d / "New.x.prev").exists() and not (d / "New.x.bak").exists()

    assert not list(d.glob("*.tmp")), "no run may leave .tmp files"
    shutil.rmtree(d)
    print("profile_write selftest: PASS")


if __name__ == "__main__":
    _selftest()
