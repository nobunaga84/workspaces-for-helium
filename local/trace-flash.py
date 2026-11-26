"""Patch 115's review, finding 2 (2026-11-26): with the sidebar shown, is a frame committed between a space switch and
the pinned section's Rebuild? check-zen-scroll.ps1 -Rows F writes the trace (DevTools Tracing, one
Tracing.dataCollected message per line); this reads it.

  python -I trace-flash.py <trace.jsonl> <browser pid> [--dump]

Per Rebuild (the task WorkspacePinnedSectionView::ScheduleRebuild posted, on CrBrowserMain): the task that posted it
-- the switch, found by its "toplevel.flow" id -- then what the main thread ran between that task's end and the
Rebuild's start. A SingleThreadProxy::DoCommit there, or a main frame's task (ScheduledActionSendBeginMainFrame's:
layout and paint, its commit perhaps a task later), means the window's compositor took the list as the switch left
it -- scrolled against the old space's rows (ActivateTabAt) -- and its DoComposite draws that: the one-frame flash.
Patch 115 restores the place only in the Rebuild.
Exit 0: no frame between, for every Rebuild (at least one found); 1: a frame between, at least once; 2: nothing to
grade (no Rebuild, or one whose posting task was not found).
--dump: the main thread's tasks around each Rebuild, for reading by eye.
"""
import json
import sys

COMMIT = "SingleThreadProxy::DoCommit"
DRAW = "SingleThreadProxy::DoComposite"
# The main frame's task (layout and paint): SingleThreadProxy::ScheduledActionSendBeginMainFrame posts it. Counted
# apart from the commit, so a main frame whose commit came in a later task is not missed (review, 11-27).
MAIN_FRAME = ("single_thread_proxy.cc", "ScheduledActionSendBeginMainFrame")


def load(path):
    events = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                events.extend(json.loads(line).get("params", {}).get("value", []))
    return events


def slices(events):
    """Complete slices: "X" as they are, "B"/"E" paired per thread. Each a dict with ts, end (us), name, args, raw."""
    out, stacks = [], {}
    for e in sorted((e for e in events if e.get("ph") in ("X", "B", "E")), key=lambda e: e.get("ts", 0)):
        key = (e.get("pid"), e.get("tid"))
        if e["ph"] == "X":
            out.append(dict(e, end=e["ts"] + e.get("dur", 0)))
        elif e["ph"] == "B":
            stacks.setdefault(key, []).append(e)
        elif stacks.get(key):
            b = stacks[key].pop()
            out.append(dict(b, end=e["ts"], args={**b.get("args", {}), **e.get("args", {})}))
    return out


def func(s):
    a = s.get("args") or {}
    return "%s:%s" % (str(a.get("src_file", "")).replace("\\", "/").split("/")[-1], a.get("src_func", "")) \
        if a.get("src_func") else ""


def is_rebuild(s):
    a = s.get("args") or {}
    f = str(a.get("src_func", ""))
    return s.get("name") == "ThreadControllerImpl::RunTask" and \
        str(a.get("src_file", "")).replace("\\", "/").endswith("workspace_pinned_section_view.cc") and \
        (f == "ScheduleRebuild" or f.endswith("::ScheduleRebuild"))


def is_main_frame(s):
    a = s.get("args") or {}
    return s.get("name") == "ThreadControllerImpl::RunTask" and \
        str(a.get("src_file", "")).replace("\\", "/").endswith(MAIN_FRAME[0]) and a.get("src_func") == MAIN_FRAME[1]


def flow_ids(e, direction):
    """The flow id an event carries in `direction` ("in"/"out"), the JSON's v2 form: bind_id + flow_in/flow_out."""
    if e.get("bind_id") is not None and e.get("flow_" + direction):
        return {str(e["bind_id"])}
    return set()


def describe(s):
    a = s.get("args") or {}
    extra = func(s) or ", ".join("%s=%s" % (k, v) for k, v in list(a.items())[:2])
    return "%s%s" % (s.get("name"), " (%s)" % extra if extra else "")


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    path, pid, dump = argv[1], int(argv[2]), "--dump" in argv
    events = load(path)
    main_tids = {e.get("tid") for e in events if e.get("ph") == "M" and e.get("name") == "thread_name" and
                 e.get("pid") == pid and (e.get("args") or {}).get("name") == "CrBrowserMain"}
    if not main_tids:
        print("INCONCLUSIVE: no CrBrowserMain thread of pid %d in %d events" % (pid, len(events)))
        return 2
    on_main = sorted((s for s in slices(events) if s.get("pid") == pid and s.get("tid") in main_tids),
                     key=lambda s: (s["ts"], -s["end"]))
    # Top-level: not inside another slice of the main thread (a task, a native message).
    top, open_end = [], -1
    for s in on_main:
        if s["ts"] >= open_end:
            top.append(s)
            open_end = s["end"]
    top_ids = {id(s) for s in top}  # "s in top" would compare whole events, field by field
    # Where each flow id leaves (the posting, inside the task that posted): every event of the browser, slices and
    # instants alike, on the main thread.
    # The v1 form too: an "s" event where it is posted, an "f" where it runs (inside the task that runs it). Every
    # posting of an id is kept: a Rebuild takes the latest one before it, should an id come round again (review).
    posted_at, arrives = {}, []
    for e in events:
        if e.get("pid") == pid and e.get("tid") in main_tids:
            for fid in flow_ids(e, "out"):
                posted_at.setdefault(fid, []).append(e.get("ts"))
            if e.get("ph") == "s":
                posted_at.setdefault(str(e.get("id")), []).append(e.get("ts"))
            elif e.get("ph") == "f":
                arrives.append((e.get("ts"), str(e.get("id"))))
    rebuilds = [s for s in on_main if is_rebuild(s)]
    print("trace: %d events, %d on the browser's main thread (%d top-level), %d flow posting(s), %d Rebuild(s)" %
          (len(events), len(on_main), len(top), len(posted_at), len(rebuilds)))
    if not rebuilds:
        print("INCONCLUSIVE: no Rebuild task in the trace (no switch traced?)")
        return 2
    t0 = rebuilds[0]["ts"]
    flashes, unknown = 0, 0
    for r in rebuilds:
        ids = flow_ids(r, "in") | {fid for ts, fid in arrives if r["ts"] <= ts <= r["end"]}
        at = max((ts for i in ids for ts in posted_at.get(i, []) if ts <= r["ts"]), default=None)
        poster = next((t for t in top if at is not None and t["ts"] <= at <= t["end"]), None)
        when = "Rebuild at %+.1f ms (%.1f ms long)" % ((r["ts"] - t0) / 1000, (r["end"] - r["ts"]) / 1000)
        if poster is None:
            unknown += 1
            print("  %s: its posting task NOT found (flow ids %s) -- cannot grade" % (when, sorted(ids) or "none"))
            continue
        between = [t for t in top if t["ts"] >= poster["end"] and t["end"] <= r["ts"]]
        frames = [s for s in on_main if poster["end"] <= s["ts"] < r["ts"] and s["name"] in (COMMIT, DRAW)]
        commits = sum(1 for s in frames if s["name"] == COMMIT)
        draws = sum(1 for s in frames if s["name"] == DRAW)
        main_frames = sum(1 for t in between if is_main_frame(t))
        flash = commits > 0 or main_frames > 0
        flashes += flash
        print("  %s: posted by %s (%.1f ms long), %.1f ms before; between: %d task(s) [%s]; main frames %d, commits %d, "
              "draws %d -> %s" %
              (when, describe(poster), (poster["end"] - poster["ts"]) / 1000, (r["ts"] - poster["end"]) / 1000,
               len(between), "; ".join(describe(t) for t in between[:8]) + (" ..." if len(between) > 8 else ""),
               main_frames, commits, draws, "FLASH (a frame of the switch's scroll)" if flash else "no frame"))
        if dump:
            for s in on_main:
                if poster["ts"] - 50000 <= s["ts"] <= r["end"] and (id(s) in top_ids or s["name"] in (COMMIT, DRAW)):
                    print("      %+9.1f ms %7.1f ms  %s%s" % ((s["ts"] - r["ts"]) / 1000, (s["end"] - s["ts"]) / 1000,
                                                       "" if id(s) in top_ids else "    ", describe(s)))
    graded = len(rebuilds) - unknown
    print("RESULT flash: a frame (main frame or commit) between the switch and its Rebuild in %d of %d graded "
          "switch(es) (%d not graded); the trace's main frames: %d" %
          (flashes, graded, unknown, sum(1 for t in top if is_main_frame(t))))
    if flashes:
        return 1
    return 2 if unknown or not graded else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
