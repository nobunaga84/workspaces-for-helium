"""Read-only: the workspace tags of a Session_* file's tab groups, as JSON (counts only, no addresses).

    python local/session-tags.py <profile>\\Default\\Sessions\\Session_<n>     (the browser closed)

Prints {"groups": {"<title>": {"<tag>": count, ...}}, "loose": {"<tag>": count}, "anchored": {"<title>":
count}, "named": {"<title>": ["<custom title>", ...]}}; an untagged tab counts under "". The last two
hold a group's anchored tabs and renamed tabs (E18.2: they too must survive a reopen). Replays the command log the way session_service_commands.cc does: last write wins,
a closed tab is dropped, and so is every tab of a closed window. Written for E18.1 (LOCAL.md 66): a
saved group reopened from Recently Closed must come back in the workspace it was closed from, and stay
there after a restart.
"""
import collections
import json
import struct
import sys

SET_TAB_WINDOW, TAB_CLOSED, WINDOW_CLOSED, SET_TAB_GROUP, SET_GROUP_METADATA2, ADD_TAB_EXTRA_DATA = 0, 16, 17, 25, 27, 33


class Pickle:
    def __init__(self, data):
        self.d = data[4:4 + struct.unpack_from("<I", data, 0)[0]]
        self.p = 0

    def int(self):
        self.p += 4
        return struct.unpack_from("<i", self.d, self.p - 4)[0]

    def u64(self):
        self.p += 8
        return struct.unpack_from("<Q", self.d, self.p - 8)[0]

    def raw(self, n):
        s = self.d[self.p:self.p + n]
        self.p = (self.p + n + 3) & ~3
        return s

    def string(self):
        return self.raw(self.int()).decode("utf-8", "replace")

    def string16(self):
        return self.raw(2 * self.int()).decode("utf-16-le", "replace")


def records(path):
    """(command id, payload) for each command of a Session_* file, in order (the migration folder's site-icons.py reads them too)."""
    data = open(path, "rb").read()
    if data[:4] != b"SNSS":
        sys.exit(f"not a session file: {path}")
    pos = 8
    while pos + 2 <= len(data):
        size = struct.unpack_from("<H", data, pos)[0]
        pos += 2
        if size == 0 or pos + size > len(data):
            return
        yield data[pos], data[pos + 1:pos + size]
        pos += size


def read(path):
    tabs = collections.defaultdict(lambda: {"window": None, "group": None, "tag": "", "anchor": "", "name": ""})
    titles, closed_windows = {}, set()
    for cid, payload in records(path):
        if cid == SET_TAB_WINDOW:
            window, tab = struct.unpack_from("<ii", payload, 0)
            tabs[tab]["window"] = window
        elif cid == TAB_CLOSED:
            tabs.pop(struct.unpack_from("<i", payload, 0)[0], None)
        elif cid == WINDOW_CLOSED:
            closed_windows.add(struct.unpack_from("<i", payload, 0)[0])
        elif cid == SET_TAB_GROUP:
            tab = struct.unpack_from("<i", payload, 0)[0]
            tabs[tab]["group"] = struct.unpack_from("<QQ", payload, 8) if payload[24] else None
        elif cid == SET_GROUP_METADATA2:
            pk = Pickle(payload)
            token = (pk.u64(), pk.u64())
            titles[token] = pk.string16()
        elif cid == ADD_TAB_EXTRA_DATA:
            pk = Pickle(payload)
            tab, key, value = pk.int(), pk.string(), pk.string()
            field = {"helium.workspace": "tag", "helium.anchor_url": "anchor", "helium.custom_title": "name"}.get(key)
            if field:
                tabs[tab][field] = value
    groups, loose = collections.defaultdict(collections.Counter), collections.Counter()
    anchored, named = collections.Counter(), collections.defaultdict(list)
    for tab in tabs.values():
        if tab["window"] in closed_windows:
            continue
        if tab["group"]:
            title = titles.get(tab["group"], "?")
            groups[title][tab["tag"]] += 1
            anchored[title] += bool(tab["anchor"])
            if tab["name"]:
                named[title].append(tab["name"])
        else:
            loose[tab["tag"]] += 1
    return {"groups": groups, "loose": loose, "anchored": anchored, "named": named}


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    if not path:
        sys.exit("no session file given (in PowerShell: (Get-ChildItem <profile>\\Default\\Sessions\\Session_* | "
                 "Sort-Object LastWriteTime | Select-Object -Last 1).FullName)")
    try:
        print(json.dumps(read(path)))
    except FileNotFoundError:
        sys.exit(f"no such file: {path}")
    except PermissionError:
        sys.exit("the session file is locked: Chrome holds it while the browser runs -- close the browser first")
