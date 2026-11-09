"""Demo data for UI screenshots (design review, LOCAL.md 60): realistic workspace names and icons, pinned
rows and folders, and an archive, written into a throwaway profile (a copy of testprofile-e15b-smoke, whose
four non-Home guids it keeps), whose copied history and bookmarks it deletes. Nothing personal; every address
is a public site. Run with the browser CLOSED.

    python local/demo-profile.py <profile-dir> [--scheme system|light|dark] [--zen] [--row-height N]

--scheme writes Chromium's appearance setting (browser.theme.color_scheme2: 0 system, 1 light, 2 dark).
--zen turns on Helium's zen mode with the sidebar NOT pinned, so it floats (seeded as check-e16-auto.ps1 does).
--row-height writes E18's helium.workspaces.tab_row_height (30 compact .. 48; 42 roomy); absent, nothing is
written (compact).
"""
import json
import shutil
import sys
import time
from pathlib import Path

WINDOWS_EPOCH_US = 11644473600000000
WORK, RESEARCH, PERSONAL, SIDE = ("2ab592d4-a80b-4a1d-aeaa-6acd51c12134", "1e3d7c57-09e3-4b83-b510-5b2ccaad0b56",
                                  "c9990cf0-c141-42fd-bb39-de33171ad078", "d7ba2239-6fc1-4d07-9750-7b250403ba4f")
# (guid, title, identity keys). E17a's identity: a preset symbol (Work), an emoji with its own colour (Research),
# a preset symbol with its own colour (Side project); Home and Personal are left to the default rule (Home grey
# with its house, Personal a free colour with its emoji).
WORKSPACES = [("default", "Home", {}), (WORK, "Work", {"symbol": "work"}),
              (RESEARCH, "Research", {"icon": "\U0001F52C", "color": 6}),
              (PERSONAL, "Personal", {"icon": "\U0001F33F"}), (SIDE, "Side project", {"symbol": "launch", "color": 8})]


def item(i, title, url):
    return {"type": "item", "id": i, "title": title, "url": url}


def folder(i, title, is_open, children):
    return {"type": "folder", "id": i, "title": title, "open": is_open, "children": children}


PINS = {
    "default": [item("h1", "Gmail", "https://mail.google.com/"),
                item("h2", "Calendar", "https://calendar.google.com/"),
                folder("hf1", "Reading", True, [item("h3", "Wikipedia", "https://en.wikipedia.org/"),
                                                item("h4", "The Verge", "https://www.theverge.com/")]),
                folder("hf2", "Recipes", False, [item("h5", "Serious Eats", "https://www.seriouseats.com/")]),
                item("h6", "YouTube", "https://www.youtube.com/")],
    WORK: [item("w1", "GitHub", "https://github.com/"),
           folder("wf1", "Docs", True, [item("w2", "Chromium Code Search", "https://source.chromium.org/"),
                                        item("w3", "MDN Web Docs", "https://developer.mozilla.org/")]),
           item("w4", "Stack Overflow", "https://stackoverflow.com/")],
    RESEARCH: [item("r1", "arXiv", "https://arxiv.org/"), item("r2", "Wikipedia", "https://en.wikipedia.org/")],
    PERSONAL: [item("p1", "Weather", "https://weather.com/")],
    SIDE: [],
}

ARCHIVE = [  # (title, url, workspace, reason, hours ago)
    ("Arc (web browser) - Wikipedia", "https://en.wikipedia.org/wiki/Arc_(web_browser)", "default", "manual", 0.3),
    ("Hacker News", "https://news.ycombinator.com/", "default", "auto", 5),
    ("Chromium Blog", "https://blog.chromium.org/", "default", "manual", 26),
    ("The Verge", "https://www.theverge.com/", "default", "window", 30),
    ("Serious Eats", "https://www.seriouseats.com/", "default", "auto", 80),
    ("Weather forecast", "https://weather.com/", "default", "auto", 200),
    ("Rust Blog", "https://blog.rust-lang.org/", "default", "auto", 40 * 24),  # a month heading (E17c)
    ("Helium releases", "https://github.com/imputnet/helium/releases", WORK, "manual", 2),
    ("Chromium Code Search", "https://source.chromium.org/", WORK, "auto", 50),
]

# Opened as Today tabs by capture-ui.ps1 (and once beforehand, so every pinned row has its favicon).
TODAY = ["https://en.wikipedia.org/wiki/Web_browser", "https://github.com/imputnet/helium",
         "https://news.ycombinator.com/", "https://developer.chrome.com/docs"]

# The base copy came from the daily profile and keeps its history, bookmarks and site-search engines (Web Data):
# the address bar, the New Tab page and Ctrl+H would show those pages. Deleted here; the browser makes empty ones at the start. The Snapshots
# folder holds older copies of them. ponytail: Favicons stays (the made-up pins' icons); it shows no page.
COPIED_HISTORY = ["History", "Top Sites", "Shortcuts", "Network Action Predictor", "Visited Links", "Web Data",
                  "Bookmarks", "Bookmarks.bak", "Bookmarks.arc-import.bak"]


def main():
    args = sys.argv[1:]
    scheme = None
    zen = "--zen" in args
    if zen:
        args.remove("--zen")
    if "--scheme" in args:
        i = args.index("--scheme"); scheme = {"system": 0, "light": 1, "dark": 2}[args[i + 1]]; del args[i:i + 2]
    row_height = None
    if "--row-height" in args:
        i = args.index("--row-height"); row_height = int(args[i + 1]); del args[i:i + 2]
    if len(args) != 1 or args[0] in ("-h", "--help"):
        print(__doc__); return 2
    d = Path(args[0]) / "Default"
    prefs_path = d / "Preferences"
    prefs = json.loads(prefs_path.read_text(encoding="utf-8"))
    items = []
    for guid, title, identity in WORKSPACES:
        items.append({"guid": guid, "title": title, **identity})
    prefs.setdefault("helium", {}).setdefault("workspaces", {})["list"] = {"items": items, "schema_version": 1}
    if scheme is not None:
        prefs.setdefault("browser", {}).setdefault("theme", {})["color_scheme2"] = scheme
    if row_height is not None:
        prefs["helium"]["workspaces"]["tab_row_height"] = row_height
    if zen:
        prefs.setdefault("helium", {}).setdefault("browser", {}).update(
            {"layout": 2, "zen_mode": True, "zen_mode_sidebar_pinned": False})
    prefs_path.write_text(json.dumps(prefs, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    (d / "Workspace Pins").write_text(json.dumps({"version": 1, "workspaces": PINS}, ensure_ascii=False), encoding="utf-8")
    now = time.time_ns() // 1000 + WINDOWS_EPOCH_US
    entries = []
    for n, (title, url, ws, reason, hours) in enumerate(ARCHIVE):
        at = now - int(hours * 3600e6)
        entries.append({"id": f"demo-{n:02d}", "url": url, "title": title, "workspace": ws, "reason": reason,
                        "archived_at": str(at), "last_active": str(at - 300 * 10**6)})
    entries.sort(key=lambda e: int(e["archived_at"]))  # oldest first, as the store writes it
    (d / "Workspace Archive").write_text(json.dumps({"version": 1, "entries": entries}, separators=(",", ":")),
                                         encoding="utf-8")
    for name in COPIED_HISTORY:
        for f in (d / name, d / f"{name}-journal"):
            f.unlink(missing_ok=True)
    shutil.rmtree(Path(args[0]) / "Snapshots", ignore_errors=True)
    pin_urls = sorted({i["url"] for rows in PINS.values() for r in rows
                       for i in ([r] if r["type"] == "item" else r["children"])})
    print("\n".join(["PINS"] + pin_urls + ["TODAY"] + TODAY))
    return 0


if __name__ == "__main__":
    sys.exit(main())
