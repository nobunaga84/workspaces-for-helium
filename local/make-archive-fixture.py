"""Write a generated archive into a test profile: the Archive screen's gate.

Design 5 ("The Archive screen", E14d.2): 1,750 entries -- the size of the
owner's Arc archive -- open in <= 1 s, and a keystroke filters in well under
that. check-e14d2-auto.ps1 row H writes this file into its throwaway copy and
times the screen on it.

    python local/make-archive-fixture.py <profile-dir> [--count 1750]
        [--days 59] [--workspaces guid,guid,...] [--split arc|even]
    python local/make-archive-fixture.py <profile-dir> --ages 30m,5h,3d,10d
        [--merge]
    python local/make-archive-fixture.py --selftest

Writes <profile-dir>\\Default\\Workspace Archive the way the browser writes it
(workspace_archive.cc, EntryToValue): {"version":1,"entries":[...]}, OLDEST
first (the store's order), compact. Entry n (1-based, zero-padded to 4):
  id "fixture-0001", url "http://127.0.0.1:8767/fixture/0001.html",
  title "Fixture page 0001", workspace by --split over --workspaces (default:
  helium.workspaces.list in the profile's Preferences, read as
  set-workspaces-pref.py reads it, the first workspace that is not Home moved
  to the front), reason cycling manual / window / auto,
  archived_at spread evenly over the last --days days (the newest a minute
  ago, so it is under "Today"), last_active 5 minutes before it.
--split arc (the default) shares the entries as the owner's Arc archive shares
its spaces (design 5: 1,406 / 297 / 44 / 9 / 1 of 1,757), the first workspace
the biggest share, a sixth or later none, each workspace's entries spread over
the days. So the screen opened from Work shows about 1,400 rows, as the
owner's biggest space would (E14d.2 review: round-robin showed 350). --split
even is the round-robin of before.
--ages writes one entry per age instead, archived that long ago (m, h or d),
all in the first workspace, fixture-0001 the first age: check-e14d3-auto.ps1
row G puts one entry in each of the Archive screen's Clear ranges. --merge
keeps the entries already in the file (the run's own closes) and adds these,
oldest first; it refuses a file that is not a version-1 archive or already
holds a fixture id.
Times are base::TimeToValue's (base/json/values_util.cc): int64 microseconds
since the Windows epoch, as a STRING. A number, or Unix time, is refused by
ArchiveFromValue and the store sets the whole file aside as .bad.

CLOSE THE BROWSER FIRST: the store rewrites the file 2.5 s after a change and at
exit. Refuses while a fork chrome.exe runs or the profile's lockfile is there,
and a --days of 60 or more (the store drops entries older than kKeepFor, 60
days, at the load, so "opened, 1750 entr(ies)" would never be seen). The write
is all-or-nothing (profile_write.py); a file already there is kept as
"Workspace Archive.fixture.bak" (the first time, never overwritten) and
".fixture.prev" (just before this run). Exits non-zero on every refusal.
"""

import argparse
import json
import pathlib
import subprocess
import sys
import time

from profile_write import write_json_atomically

FILE_NAME = "Workspace Archive"      # ArchiveStore::kFileName
KEEP_DAYS = 60                       # kKeepFor, workspace_archive.h
REASONS = ("manual", "window", "auto")
# Entries per space in the owner's Arc archive, biggest first (design 5).
ARC_SPLIT = (1406, 297, 44, 9, 1)
PORT = 8767                          # check-e14d2-auto.ps1's page server
# base::Time::kMicrosecondsFromWindowsToUnixEpoch (base/time/time.h).
WINDOWS_EPOCH_US = 11644473600000000
US_PER_S = 1000000


def now_us():
    """Now as base::Time counts it: microseconds since 1601-01-01 UTC."""
    return time.time_ns() // 1000 + WINDOWS_EPOCH_US


def workspaces_from_prefs(profile):
    """The profile's workspace guids in rail order -- ParseWorkspaces()'s rule,
    as set-workspaces-pref.py --show applies it: a missing, empty or repeated
    guid is skipped. Only the default one when no list is stored."""
    prefs = profile / "Default" / "Preferences"
    if not prefs.exists():
        sys.exit(f"no Preferences at {prefs} -- give --workspaces")
    state = json.loads(prefs.read_text(encoding="utf-8")).get("helium", {})
    items = (state.get("workspaces", {}).get("list") or {}).get("items", [])
    guids = []
    for item in items:
        guid = item.get("guid")
        if guid and guid not in guids:
            guids.append(guid)
    return guids or ["default"]


def owners(count, workspaces, split):
    """Each entry's workspace, oldest first. "even": round-robin. "arc":
    ARC_SPLIT's shares by largest remainder, in `workspaces` order; each
    workspace's k-th of n entries sits at (k + 0.5) / n of the list, so every
    workspace's entries are spread evenly over the list."""
    if split == "even":
        return [workspaces[i % len(workspaces)] for i in range(count)]
    weights = [ARC_SPLIT[i] if i < len(ARC_SPLIT) else 0
               for i in range(len(workspaces))]
    exact = [count * w / sum(weights) for w in weights]
    shares = [int(x) for x in exact]
    by_remainder = sorted(range(len(shares)),
                          key=lambda i: shares[i] - exact[i])
    for i in by_remainder[:count - sum(shares)]:
        shares[i] += 1
    slots = sorted(((k + 0.5) / n, i)
                   for i, n in enumerate(shares) for k in range(n))
    return [workspaces[i] for _, i in slots]


def entry(i, width, at, workspace):
    """The i-th (0-based) fixture entry, archived at `at`."""
    n = str(i + 1).zfill(width)
    return {
        "id": f"fixture-{n}",
        "url": f"http://127.0.0.1:{PORT}/fixture/{n}.html",
        "title": f"Fixture page {n}",
        "workspace": workspace,
        "reason": REASONS[i % len(REASONS)],
        "archived_at": str(at),
        "last_active": str(at - 5 * 60 * US_PER_S),
    }


def make_entries(count, days, workspaces, now, split="even"):
    """`count` entries, oldest first, evenly from `days` days before `now` to a
    minute before it, their workspaces by owners()."""
    width = max(4, len(str(count)))
    newest = now - 60 * US_PER_S
    step = (days * 86400 - 60) * US_PER_S // max(count - 1, 1)
    owner = owners(count, workspaces, split)
    return [entry(i, width, newest - (count - 1 - i) * step, owner[i])
            for i in range(count)]


AGE_UNITS = {"m": 60, "h": 3600, "d": 86400}


def parse_ages(spec):
    """"30m,5h,3d" -> seconds, in the given order."""
    ages = []
    for part in spec.split(","):
        part = part.strip()
        if len(part) < 2 or part[-1] not in AGE_UNITS or not part[:-1].isdigit():
            sys.exit(f"--ages takes numbers ending in m, h or d, not {part!r}")
        ages.append(int(part[:-1]) * AGE_UNITS[part[-1]])
    if max(ages) >= KEEP_DAYS * 86400:
        sys.exit(f"--ages must be under {KEEP_DAYS} days: the store drops "
                 "older entries at the load")
    return ages


def aged_entries(ages, workspace, now):
    """One entry per age (seconds), archived that long before `now`, in the
    given order: fixture-0001 is the first age."""
    return [entry(i, 4, now - age * US_PER_S, workspace)
            for i, age in enumerate(ages)]


def merged(old, new):
    """`old` (a file's parsed JSON) with `new` added, oldest first."""
    if old.get("version") != 1 or not isinstance(old.get("entries"), list):
        sys.exit("the file there is not a version-1 archive: not merged")
    ids = {e["id"] for e in new}
    if any(e.get("id") in ids for e in old["entries"]):
        sys.exit("a fixture id is already in the file: not merged")
    return sorted(old["entries"] + new, key=lambda e: int(e["archived_at"]))


def fork_browser_running():
    """The .ps1 checks' own test: a chrome.exe under Helium-workspace. True too
    when it cannot be asked -- a write under a running browser is lost."""
    try:
        r = subprocess.run(
            ["powershell.exe", "-NoProfile", "-Command",
             "@(Get-Process chrome -EA SilentlyContinue | Where-Object Path "
             "-like '*Helium-workspace*').Count"],
            capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return True
    return r.returncode != 0 or r.stdout.strip() != "0"


def local(us):
    return time.strftime("%Y-%m-%d %H:%M",
                         time.localtime((us - WINDOWS_EPOCH_US) / US_PER_S))


def main():
    p = argparse.ArgumentParser(
        description="Write a generated Workspace Archive into a test profile.")
    p.add_argument("profile", type=pathlib.Path)
    p.add_argument("--count", type=int, default=1750)
    p.add_argument("--days", type=int, default=59)
    p.add_argument("--workspaces", help="guid,guid,... (default: the "
                   "profile's helium.workspaces.list, its first workspace "
                   "that is not Home first)")
    p.add_argument("--split", choices=("arc", "even"), default="arc",
                   help="arc: the owner's Arc archive's shares, the first "
                   "workspace the biggest (default); even: round-robin")
    p.add_argument("--ages", help="30m,5h,3d,...: one entry archived that "
                   "long ago each, in the first workspace, instead of --count")
    p.add_argument("--merge", action="store_true",
                   help="keep the entries already in the file")
    a = p.parse_args()

    if a.count < 1:
        sys.exit("--count must be at least 1")
    if not 1 <= a.days < KEEP_DAYS:
        sys.exit(f"--days must be 1..{KEEP_DAYS - 1}: the store drops entries "
                 f"older than {KEEP_DAYS} days at the load")
    folder = a.profile / "Default"
    if not folder.is_dir():
        sys.exit(f"no Default folder under {a.profile}")
    if fork_browser_running():
        sys.exit("a fork chrome.exe is running (or could not be checked) -- "
                 "close it first: the store rewrites the file at exit")
    if (a.profile / "lockfile").exists():
        sys.exit(f"{a.profile} is in use (its lockfile is there) -- close the "
                 "browser using it first")
    if a.workspaces:
        workspaces = [g.strip() for g in a.workspaces.split(",") if g.strip()]
        if not workspaces:
            sys.exit("--workspaces names no guid")
    else:
        workspaces = workspaces_from_prefs(a.profile)
        # The biggest share to Work, not Home: the checks open the screen
        # from their non-default workspace (check-e14d2-auto.ps1 row H).
        rest = [g for g in workspaces if g != "default"]
        if rest:
            workspaces.remove(rest[0])
            workspaces.insert(0, rest[0])

    if a.ages:
        entries = aged_entries(parse_ages(a.ages), workspaces[0], now_us())
    else:
        entries = make_entries(a.count, a.days, workspaces, now_us(), a.split)
    path = folder / FILE_NAME
    if a.merge and path.exists():
        entries = merged(json.loads(path.read_text(encoding="utf-8")), entries)
    write_json_atomically([(path, {"version": 1, "entries": entries})],
                          ".fixture")

    print(f"wrote {len(entries)} entries to {path}")
    print(f"  {entries[0]['id']} .. {entries[-1]['id']}, "
          f"{local(int(entries[0]['archived_at']))} .. "
          f"{local(int(entries[-1]['archived_at']))} (local), oldest first")
    for guid in workspaces:
        n = sum(1 for e in entries if e["workspace"] == guid)
        print(f"  {n:>6}  {guid}")
    print(f"  split {a.split}; reasons cycle {' / '.join(REASONS)}; urls "
          f"http://127.0.0.1:{PORT}/fixture/<n>.html")


def _selftest():
    now = now_us()
    # 2026 as base::Time, not Unix microseconds (1.7e15) or seconds.
    assert 13_400_000_000_000_000 < now < 14_000_000_000_000_000, now
    e = make_entries(1750, 59, ["default", "w"], now)
    at = [int(x["archived_at"]) for x in e]
    assert len(e) == 1750 and len({x["id"] for x in e}) == 1750
    assert at == sorted(at), "oldest first"
    assert at[-1] == now - 60 * US_PER_S, "the newest is under Today"
    assert at[0] >= now - 59 * 86400 * US_PER_S, "none past --days"
    # What ArchiveFromValue refuses: an empty id or url, an unknown reason, a
    # time that is not an int64 string.
    for x in e:
        assert x["id"] and x["url"] and x["reason"] in REASONS
        assert isinstance(x["archived_at"], str)
        assert int(x["last_active"]) < int(x["archived_at"])
    assert e[0]["id"] == "fixture-0001" and e[-1]["id"] == "fixture-1750"
    assert e[0]["url"] == "http://127.0.0.1:8767/fixture/0001.html"
    assert e[0]["title"] == "Fixture page 0001"
    assert [x["workspace"] for x in e[:3]] == ["default", "w", "default"]
    assert [x["reason"] for x in e[:4]] == ["manual", "window", "auto",
                                            "manual"]
    assert make_entries(1, 59, ["d"], now)[0]["archived_at"] == str(at[-1])
    assert make_entries(10000, 59, ["d"], now)[-1]["id"] == "fixture-10000"
    # arc: the owner's shares at 1,750, the first workspace the biggest, every
    # workspace on every stretch of the list, the count kept exactly.
    ws = ["w", "default", "a", "b", "c"]
    arc = [x["workspace"] for x in make_entries(1750, 59, ws, now, "arc")]
    shares = [arc.count(g) for g in ws]
    assert shares == [1400, 296, 44, 9, 1], shares
    assert arc[:5].count("w") >= 3 and "w" in arc[-5:], "spread, not a block"
    assert arc[:200].count("default") > 20 and arc[-200:].count("default") > 20
    assert owners(7, ["only"], "arc") == ["only"] * 7
    six = owners(1750, ws + ["sixth"], "arc")
    assert six.count("sixth") == 0 and len(six) == 1750
    for n in (1, 2, 3, 1757, 9999):
        assert len(owners(n, ws, "arc")) == n
    assert owners(1, ws, "arc") == ["w"]
    # --ages: one entry per age, in order, that long ago; --merge keeps the
    # file's own entries and sorts oldest first.
    assert parse_ages("30m,5h,3d,10d") == [1800, 18000, 259200, 864000]
    aged = aged_entries([1800, 864000], "w", now)
    assert [x["id"] for x in aged] == ["fixture-0001", "fixture-0002"]
    assert int(aged[0]["archived_at"]) == now - 1800 * US_PER_S
    assert int(aged[1]["archived_at"]) == now - 864000 * US_PER_S
    assert {x["workspace"] for x in aged} == {"w"}
    own = {"id": "run-1", "url": "http://x/", "title": "", "workspace": "w",
           "reason": "manual", "archived_at": str(now - 60 * US_PER_S)}
    both = merged({"version": 1, "entries": [own]}, aged)
    assert [x["id"] for x in both] == ["fixture-0002", "fixture-0001", "run-1"]
    print("make-archive-fixture selftest: PASS")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        _selftest()
    else:
        main()
