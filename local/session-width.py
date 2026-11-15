"""The sidebar width each window's record holds in a Session_* file (B1, LOCAL.md 147). The browser closed.

    python -I local/session-width.py <Session_n>              prints {"<window id>": "<width>", ...} as JSON
    python -I local/session-width.py <Session_n> --strip      drops every width record (a Chromium 156 session had none)
    python -I local/session-width.py <Session_n> --set 333    each record's value becomes 333 (same digit count only)

--strip and --set rewrite the file in place: refused outside a testprofile-* copy (or a scratchpad folder).

The record: command 34 (kCommandAddWindowExtraData), a Pickle of the window id and two strings, the key
"vertical_tab_strip_uncollapsed_width" and the width as text (session_service_base.cc). Every other byte of the
file is kept as it was. Version 3 files only: version 5 is encrypted (command_storage_backend.cc).
"""
import json
import os
import struct
import sys

ADD_WINDOW_EXTRA_DATA = 34
KEY = b"vertical_tab_strip_uncollapsed_width"


def records(b):
    """Yields (offset, total length, command id, payload) for each command after the 8-byte header."""
    i = 8
    while i < len(b):
        if i + 3 > len(b):
            sys.exit(f"cut-off command at byte {i}")
        size, = struct.unpack_from("<H", b, i)
        if size < 1 or i + 2 + size > len(b):
            sys.exit(f"bad command size {size} at byte {i}")
        yield i, 2 + size, b[i + 2], b[i + 3:i + 2 + size]
        i += 2 + size


def width_record(payload):
    """(window id, value, value's offset in the payload) for a width record, else None."""
    def string(p):
        if p + 4 > len(payload):
            sys.exit(f"command 34: no string length at payload byte {p} (an unknown layout?)")
        n, = struct.unpack_from("<i", payload, p)
        if n < 0 or p + 4 + n > len(payload):
            sys.exit(f"command 34: string length {n} at payload byte {p} runs past the record (an unknown layout?)")
        return payload[p + 4:p + 4 + n], p + 4, (p + 4 + n + 3) & ~3
    if len(payload) < 8:
        sys.exit(f"command 34: a {len(payload)}-byte record has no window id (an unknown layout?)")
    window, = struct.unpack_from("<i", payload, 4)
    key, _, p = string(8)
    if key != KEY:
        return None
    value, at, _ = string(p)
    return window, value, at


def main():
    path, args = sys.argv[1], sys.argv[2:]
    b = bytearray(open(path, "rb").read())
    sig, version = struct.unpack_from("<II", b, 0)
    if sig != 0x53534E53 or version != 3:
        sys.exit(f"not a version-3 session file (signature {sig:#x}, version {version})")
    found = [(off, n, width_record(pay)) for off, n, cid, pay in records(b) if cid == ADD_WINDOW_EXTRA_DATA]
    found = [(off, n, r) for off, n, r in found if r]
    if not args:
        print(json.dumps({str(r[0]): r[1].decode() for _, _, r in found}))
        return
    # It rewrites the file in place, so only a test copy: never the daily profile's session (B1 is about exactly
    # the state --strip makes).
    where = os.path.abspath(path).lower()
    if "\\testprofile-" not in where and "\\scratchpad\\" not in where:
        sys.exit(f"refused: {path} is not inside a testprofile-* copy (or a scratchpad); --strip/--set edit in place")
    if args == ["--strip"]:
        for off, n, _ in reversed(found):
            del b[off:off + n]
    elif len(args) == 2 and args[0] == "--set" and args[1].isdigit():
        new = args[1].encode()
        for off, _, (_, value, at) in found:
            if len(new) != len(value):
                sys.exit(f"--set {args[1]}: the record holds {value.decode()} ({len(value)} digits); the size must not change")
            start = off + 3 + at
            b[start:start + len(new)] = new
    else:
        sys.exit("usage: session-width.py <Session_n> [--strip | --set <digits>]")
    open(path, "wb").write(b)
    print(json.dumps({"changed": len(found)}))


main()
