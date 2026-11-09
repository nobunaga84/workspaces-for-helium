"""Made-up test profiles and a made-up Arc sidebar, of the real ones' shape (LOCAL.md 133).

    python -I local/make-test-profiles.py [<out dir>]      (default <local-path>\\Helium-workspace\\made-up-new)
    python -I local/make-test-profiles.py --selftest

Reads the three test bases (testprofile, testprofile-pre-e14c, testprofile-e15b-smoke) and Arc's
StorableSidebar.json, read-only, and writes <out dir>\\<base> for each, plus
<local-path>\\Helium-workspace\\arc-made-up\\StorableSidebar.json for the real-import checks (HELIUM_ARC_SIDEBAR).
Nothing is replaced or deleted: moving the new bases in place is a separate step, on the owner's word.

Every address, page title, folder name, custom title and id becomes a made-up one; the SHAPE stays: the
same workspaces (their guids too: ~40 scripts name them), the same pinned pages per folder, the same tabs
in the same order, a duplicate still a duplicate (one real value -> one made-up value in every file of
one run, so the made-up Arc file still matches testprofile's pins, as the import made them). Times,
counts and flags stay. The mapping lives in memory only and is new each run: nothing on disk links a
made-up value to a real one. Hence one run must read the bases AND Arc's file, before the swap.

A new base holds only what the checks read: First Run, Last Version, Local State, and in Default:
Preferences, Secure Preferences (it keeps "On startup", whose MAC no script can write), Workspace Pins,
Bookmarks, the newest Session_* and (smoke base only) Favicons, cut down to its made-up pins' icons.
Everything else -- History, caches, site storage, Recently Closed (Tabs_*), Snapshots -- the browser
makes empty at the first start. Addresses on 127.0.0.1, localhost, *.test, *.example and example.com
(the checks' own pages) are kept as they are.
"""
import json, os, pathlib, random, re, shutil, sqlite3, struct, sys, uuid
from urllib.parse import urlsplit

WS = pathlib.Path(r"<local-path>\Helium-workspace")
BASES = ("testprofile", "testprofile-pre-e14c", "testprofile-e15b-smoke")
KEEP_PINS = {"testprofile-e15b-smoke"}  # its pins were made up in E15b; ~80 checks name them
ARC = pathlib.Path(os.environ.get("LOCALAPPDATA", "")) / (
    r"Packages\TheBrowserCompany.Arc_ttt1ap7aakyb4\LocalCache\Local\Arc\StorableSidebar.json")
ARC_OUT = WS / "arc-made-up" / "StorableSidebar.json"

UUID_RE = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
LOCAL_HOST = re.compile(r"127\.0\.0\.1|localhost|([a-z0-9-]+\.)+(test|example)|(www\.)?example\.(com|org|net)", re.I)
BARE_PAGE = re.compile(r"(chrome|about|arc):(//)?[a-z0-9-]*/?", re.I)  # chrome://newtab/, about:blank
SCHEME = re.compile(r"^[a-z][a-z0-9+.-]*:", re.I)
# Chromium's and Arc's own names, and the test workspaces' (every user has them; F9 calls them generic).
KEEP_TITLES = {"New Tab", "Untitled", "Arc Basics", "Split View", "Imported From Chrome", "Imported", "Other bookmarks",
               "Bookmarks bar", "Bookmarks", "Mobile bookmarks", "Pinned Tabs", "Home", "Work", "Canary",
               "Private", "Unpin"}
WORDS = ("amber", "basil", "cedar", "delta", "ember", "fjord", "garnet", "harbor", "indigo", "juniper", "kelp",
         "lumen", "maple", "nectar", "onyx", "pebble", "quartz", "russet", "saffron", "thistle", "umber",
         "velvet", "willow", "yarrow", "zephyr", "acorn", "birch", "clover", "dune", "elm", "fennel", "glade",
         "heron", "iris", "jasper", "kestrel", "lark", "moss", "nimbus", "otter", "plover", "quill", "reed",
         "sorrel", "tansy", "upland", "vetch", "wren", "alder", "brook", "cobalt", "dahlia", "egret", "flint",
         "gorse", "hazel", "inlet", "jade", "knoll", "lichen", "marsh", "nettle", "oriel", "pine")


def is_local(url):
    """The checks' own pages: judged by the HOST alone (a real address may carry 127.0.0.1 in its query)."""
    if BARE_PAGE.fullmatch(url):
        return True
    try:
        p = urlsplit(url)
        return p.scheme in ("http", "https") and bool(LOCAL_HOST.fullmatch(p.hostname or ""))
    except ValueError:
        return False


def local_site(pattern):
    """A content-settings key ("https://[*.]host:443,*") of one of the checks' own pages."""
    site = pattern.split(",")[0].replace("[*.]", "")
    return site in ("*", "") or is_local(site if "://" in site else "http://" + site)  # "*": a global setting


class Fake:
    """One real value -> one made-up value, per kind, for the whole run."""

    def __init__(self):
        self.rnd = random.Random()  # unseeded: no key to re-derive the mapping from
        self.ids, self.hosts, self.urls, self.titles = {}, {}, {}, {}
        self.used = set(KEEP_TITLES)

    def text(self, n, sep=" ", cap=True):
        """Words, exactly n characters (at least 1); a new string unless 50 tries found none (short ones)."""
        for _ in range(50):
            out = ""
            while len(out) < n:
                w = self.rnd.choice(WORDS)
                out += (sep if out else "") + (w.capitalize() if cap and not out else w)
            out = out[:max(n, 1)].rstrip(sep) or "x"
            out += "x" * (n - len(out))
            if out not in self.used:
                break
        self.used.add(out)
        return out

    def uuid(self, s):
        if s.lower().startswith("00000000-0000-4000-a000-"):  # Bookmarks' permanent folders
            return s
        new = self.ids.setdefault(s.lower(), str(uuid.uuid4()))
        return new.upper() if s != s.lower() else new

    def host(self, h):
        i = self.hosts.setdefault(h, len(self.hosts))
        return f"{WORDS[i % 64]}-{WORDS[i // 64 % 64]}{i // 4096 or ''}.test"

    def url(self, s):
        if not s or is_local(s):
            return s
        if s not in self.urls:
            try:
                p = urlsplit(s)
                host = p.hostname
            except ValueError:  # "http://[::1" -- mapped like any other non-web address
                p, host = urlsplit(s.split(":", 1)[0] + ":"), None
            scheme = p.scheme.lower()
            if scheme in ("http", "https") and host:
                h = p.hostname.lower()
                www = h.startswith("www.")
                rest = s.split("//", 1)[1][len(p.netloc):]
                path = rest if rest in ("", "/") else "/" + self.text(len(rest) - 1, "-", False)
                self.urls[s] = f"{scheme}://{'www.' if www else ''}{self.host(h[4:] if www else h)}{path}"
            else:  # file:, chrome-extension:, data:, ... -- keep the scheme (the importer skips them by it)
                self.urls[s] = f"{scheme}://{self.text(12, '-', False)}.test/{len(self.urls)}"
        return self.urls[s]

    def spaces(self, arc_doc):
        """Arc's spaces named "<test workspace> <more>" (the test profiles renamed one so, LOCAL.md 132) become
        that workspace's name, so the made-up Arc file's spaces match the test workspaces as the import does."""
        def walk(o):
            if isinstance(o, dict):
                t = o.get("title")
                if "containerIDs" in o and isinstance(t, str) and t not in KEEP_TITLES and t.split()[:1] and \
                        t.split()[0] in KEEP_TITLES:
                    self.titles[t] = t.split()[0]
                for v in o.values():
                    walk(v)
            elif isinstance(o, list):
                for v in o:
                    walk(v)
        walk(arc_doc)

    def title(self, s):
        if not s or s.strip() in KEEP_TITLES:
            return s
        if SCHEME.match(s) and "//" in s[:12]:
            return self.url(s)
        if s not in self.titles:
            self.titles[s] = self.text(len(s))
        return self.titles[s]


fake = Fake()
URL_KEYS = {"url", "savedURL"}
TITLE_KEYS = {"title", "custom_title", "savedTitle", "name"}
DROP_KEYS = {"meta_info", "unsynced_meta_info", "checksum"}  # Bookmarks' extras, and its hash of the real content


def scrub(o, key=""):
    if isinstance(o, dict):
        return {k: scrub(v, k) for k, v in o.items() if k not in DROP_KEYS}
    if isinstance(o, list):
        return [scrub(v, key) for v in o]
    if isinstance(o, str):
        if UUID_RE.fullmatch(o):
            return fake.uuid(o)
        if key in URL_KEYS:
            return fake.url(o)
        if key in TITLE_KEYS:
            return fake.title(o)
    return o


# --- Chromium's session file (SNSS): base::Pickle payloads, 4-byte aligned, zero padded -----------------
class Reader:
    def __init__(self, b):
        self.d, self.p = b[4:4 + struct.unpack_from("<I", b)[0]], 0

    def _take(self, fmt):
        v = struct.unpack_from(fmt, self.d, self.p)[0]
        self.p += struct.calcsize(fmt)
        return v

    def int(self):
        return self._take("<i")

    def i64(self):
        return self._take("<q")

    def bytes(self, unit=1):
        n = self.int() * unit
        v = self.d[self.p:self.p + n]
        self.p += (n + 3) & ~3
        return v

    def rest(self):
        return self.d[self.p:]


class Writer:
    def __init__(self):
        self.b = bytearray()

    def int(self, v):
        self.b += struct.pack("<i", v)

    def i64(self, v):
        self.b += struct.pack("<q", v)

    def bytes(self, v, unit=1):
        self.int(len(v) // unit)
        self.b += v + b"\0" * (-len(v) % 4)

    def done(self):
        return struct.pack("<I", len(self.b)) + bytes(self.b)


def u8(b):
    return b.decode("utf-8", "surrogateescape")


def u16(b):
    return b.decode("utf-16-le", "surrogatepass")


def e16(s):
    return s.encode("utf-16-le", "surrogatepass")


def put_fields(w, values, kinds="iisSsiisisiqSii"):
    """A navigation's fields up to its extended info: i int, q int64, s string, S UTF-16 string."""
    for v, kind in zip(values, kinds):
        {"i": w.int, "q": w.i64, "s": w.bytes, "S": lambda b: w.bytes(b, 2)}[kind](v)


def navigation(payload):
    """kCommandUpdateTabNavigation: SerializedNavigationEntry::WriteToPickle's fields, in its order."""
    r = Reader(payload)
    f = [r.int(), r.int(), r.bytes(), r.bytes(2), r.bytes(), r.int(), r.int(), r.bytes(), r.int(), r.bytes(),
         r.int(), r.i64(), r.bytes(2), r.int(), r.int()]
    ext = [(r.bytes(), r.bytes()) for _ in range(r.int())]
    tail = r.rest()  # the task ids

    def enc(f, ext):
        w = Writer()
        put_fields(w, f)
        w.int(len(ext))
        for k, v in ext:
            w.bytes(k)
            w.bytes(v)
        w.b += tail
        return w.done()

    if enc(f, ext) != payload:
        raise SystemExit("ABORT: a navigation is not laid out as serialized_navigation_entry.cc writes it")
    tab, index, url, title, _, trans, _, _, oldpol, orig, ua, ts, _, status, pol = f
    # Page state (form data, scroll, referrers), referrer, POST flag and extended info are dropped:
    # Chromium rebuilds a page state from the address.
    return enc([tab, index, fake.url(u8(url)).encode(), e16(fake.title(u16(title))), b"", trans, 0, b"", oldpol,
                fake.url(u8(orig)).encode(), ua, ts, b"", status, pol], [])


def extra_data(payload):
    """kCommandAddTabExtraData: id, key, value. The workspace tag is a guid the scripts name: kept."""
    r = Reader(payload)
    tab, key, value = r.int(), r.bytes(), u8(r.bytes())
    k = u8(key)
    if k.endswith("url"):
        value = fake.url(value)
    elif k.endswith("title"):
        value = fake.title(value)
    elif UUID_RE.fullmatch(value) and k != "helium.workspace":
        value = fake.uuid(value)
    elif value and k not in ("helium.workspace", "helium.pin_item"):  # Arc's own ids ("gmail") stay, as in the pins
        raise SystemExit(f"ABORT: tab extra data {k!r} holds text this script has no rule for")
    w = Writer()
    w.int(tab)
    w.bytes(key)
    w.bytes(value.encode("utf-8", "surrogateescape"))
    return w.done()


def group_metadata(payload):
    """kCommandSetTabGroupMetadata2: a 16-byte token, then the group's title."""
    r = Reader(payload)
    token = r.d[:16]
    r.p = 16
    title = r.bytes(2)
    w = Writer()
    w.b += token
    w.bytes(e16(fake.title(u16(title))), 2)
    w.b += r.rest()
    return w.done()


NO_TEXT = {0, 2, 5, 7, 8, 9, 11, 12, 14, 16, 17, 19, 20, 21, 23, 24, 25, 28, 32, 34, 35, 36, 37, 255}
REWRITE = {6: navigation, 33: extra_data, 27: group_metadata}


def session(src, dst):
    b = src.read_bytes()
    if b[:4] != b"SNSS":
        raise SystemExit(f"ABORT: {src} is not a session file")
    out, p = bytearray(b[:8]), 8
    while p + 2 <= len(b):
        size = struct.unpack_from("<H", b, p)[0]
        if size == 0 or p + 2 + size > len(b):
            break
        cid, body = b[p + 2], b[p + 3:p + 2 + size]
        p += 2 + size
        if cid in REWRITE:
            body = REWRITE[cid](body)
        elif cid in (15, 31):  # window app name / user title: none of the bases names one
            if Reader(body).rest()[4:].strip(b"\0"):
                raise SystemExit(f"ABORT: command {cid} holds a name")
        elif cid not in NO_TEXT:
            raise SystemExit(f"ABORT: session command {cid} has no rule here (it may hold text)")
        out += struct.pack("<HB", len(body) + 1, cid) + body
    dst.write_bytes(bytes(out))


# --- the files ----------------------------------------------------------------------------------------------
def read_json(f):
    return json.loads(f.read_text(encoding="utf-8"))


def write_json(f, o, **fmt):
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_bytes(json.dumps(o, ensure_ascii=False, **fmt).encode("utf-8"))


def preferences(d):
    ex = d["profile"]["content_settings"]["exceptions"]
    for cat, sites in ex.items():
        if isinstance(sites, dict):
            ex[cat] = {k: v for k, v in sites.items() if local_site(k)}
    d.get("savefile", {}).pop("default_directory", None)
    d["profile"].update(name="Test", exit_type="Normal", exited_cleanly=True)
    return d


def favicons(src, dst, keep_urls):
    shutil.copyfile(src, dst)
    db = sqlite3.connect(dst)
    pages = [u for (u,) in db.execute("SELECT DISTINCT page_url FROM icon_mapping")]
    db.executemany("DELETE FROM icon_mapping WHERE page_url = ?",
                   [(u,) for u in pages if u not in keep_urls and not is_local(u)])
    db.execute("DELETE FROM favicons WHERE id NOT IN (SELECT icon_id FROM icon_mapping)")
    db.execute("DELETE FROM favicon_bitmaps WHERE icon_id NOT IN (SELECT id FROM favicons)")
    db.commit()
    db.execute("VACUUM")
    db.close()


def pin_urls(rows):
    for r in rows:
        if r.get("url"):
            yield r["url"]
        yield from pin_urls(r.get("children", []))


def pair_splits(pins, arc_doc):
    """What the browser's one-time repair does at the first load of a version-1 pins file (patch 65's
    RepairSplits + PinStore::PairAsSplit): each of Arc's split views whose two pages are plain items of one
    list becomes a split row in the left page's place. Done here, and the file written as version 2, so no
    launch of a base's copy reads an Arc file (they read Arc's REAL one before; e19-seed-splits.py sets version 1
    on the copies it seeds, to cue the repair it tests). Returns the number paired."""
    containers = arc_doc["sidebar"]["containers"]
    flat = next(containers[i + 1] for i in range(len(containers) - 1)
                if isinstance(containers[i], dict) and "global" in containers[i])["items"]
    splits = [(flat[i], flat[i + 1]["childrenIds"]) for i in range(0, len(flat) - 1, 2)
              if isinstance(flat[i], str) and isinstance(flat[i + 1], dict)
              and "splitView" in (flat[i + 1].get("data") or {}) and len(flat[i + 1].get("childrenIds") or []) == 2]

    def lists(rows):
        yield rows
        for r in rows:
            yield from lists(r.get("children", []))

    paired = 0
    for split_id, (first, second) in splits:
        for lst in (l for roots in pins["workspaces"].values() for l in lists(roots)):
            ids = [r.get("id") for r in lst]
            if first in ids and second in ids:
                left, right = ids.index(first), ids.index(second)
                if lst[left].get("type") == lst[right].get("type") == "item":
                    lst[left] = {"id": split_id, "title": "", "type": "split", "children": [lst[left], lst[right]]}
                    del lst[right]
                    paired += 1
                break
    pins["version"] = 2
    return paired


def base(name, out, arc_doc):
    src, dst = WS / name, out / name
    if dst.exists():
        raise SystemExit(f"ABORT: {dst} exists (this script never overwrites)")
    (dst / "Default" / "Sessions").mkdir(parents=True)
    for f in ("First Run", "Last Version"):
        if (src / f).exists():
            shutil.copyfile(src / f, dst / f)
    ls = read_json(src / "Local State")
    for info in ls.get("profile", {}).get("info_cache", {}).values():
        info.update(name="Test", gaia_name="", gaia_given_name="", user_name="", hosted_domain="")
    write_json(dst / "Local State", ls, separators=(",", ":"))
    s, d = src / "Default", dst / "Default"
    write_json(d / "Preferences", preferences(read_json(s / "Preferences")), separators=(",", ":"))
    sp = read_json(s / "Secure Preferences")
    sp.pop("pinned_tabs", None)  # a tracked pref: its MAC fails, the browser resets it to empty
    write_json(d / "Secure Preferences", sp, separators=(",", ":"))
    if (s / "Workspace Pins").exists():
        pins = read_json(s / "Workspace Pins")
        pins = pins if name in KEEP_PINS else scrub(pins)
        print(f"{name}: {pair_splits(pins, arc_doc)} Arc split(s) paired, pins version 2")
        write_json(d / "Workspace Pins", pins, indent=3)
    if (s / "Bookmarks").exists():
        write_json(d / "Bookmarks", scrub(read_json(s / "Bookmarks")), indent=3)
    newest = max((s / "Sessions").glob("Session_*"), key=lambda f: int(f.name.split("_")[1]), default=None)
    if newest:
        session(newest, d / "Sessions" / newest.name)
    if name in KEEP_PINS and (s / "Favicons").exists():
        favicons(s / "Favicons", d / "Favicons", set(pin_urls(sum(read_json(s / "Workspace Pins")["workspaces"].values(), []))))
    print(f"{name}: written to {dst}")


def selftest():
    f = Fake()
    assert f.url("https://www.a.com/x?y=1") == f.url("https://www.a.com/x?y=1")  # one real -> one made-up
    assert f.url("https://www.a.com/x?y=1").startswith("https://www.") and f.url("https://a.com/").endswith(".test/")
    assert f.host("a.com") == f.host("a.com") != f.host("b.com")
    for keep in ("http://127.0.0.1:8767/x.html", "https://example.com/", "http://w.test/a", "chrome://newtab/", "about:blank"):
        assert f.url(keep) == keep, keep
    for change in ("https://example.com.evil.org/", "chrome://newtab/?q=secret", "file:///C:/Users/x/a.pdf",
                   "https://a.org/?u=http://127.0.0.1/"):
        assert f.url(change) != change, change
    assert local_site("http://127.0.0.1:8767,*") and local_site("https://[*.]w.test:443,*") and not local_site("https://a.org:443,*")
    assert local_site("*,*") and f.url("http://[::1").startswith("http://")  # a global setting; a malformed address
    arc_doc = {"sidebar": {"containers": [{"global": {}}, {"items": [
        "S", {"data": {"splitView": {}}, "childrenIds": ["R", "L"]}]}]}}
    pins = {"version": 1, "workspaces": {"w": [{"id": "x", "type": "item"}, {"id": "L", "type": "item"},
                                                {"id": "R", "type": "item"}]}}
    assert pair_splits(pins, arc_doc) == 1 and pins["version"] == 2  # Arc's first page (R) on the left, the
    # second (L) above it in the list: as PairAsSplit, the split takes the first's place, moved up by one
    assert [r["id"] for r in pins["workspaces"]["w"]] == ["x", "S"]
    assert [p["id"] for p in pins["workspaces"]["w"][1]["children"]] == ["R", "L"]
    assert len(f.title("A real page title")) == len("A real page title") and f.title("Work") == "Work"
    assert f.title("https://a.com/x?y=1") == f.url("https://a.com/x?y=1")
    f.spaces({"spaces": [{"title": "Work Stuff", "containerIDs": []}, {"title": "Errands", "containerIDs": []}]})
    assert f.title("Work Stuff") == "Work" and f.title("Errands") != "Errands"
    assert f.uuid("62E2D4DF-777F-4CAA-94AA-2137FCD03AEE").isupper() and f.uuid("abcdef01-2345-4678-9abc-def012345678").islower()
    assert f.uuid("00000000-0000-4000-a000-000000000002") == "00000000-0000-4000-a000-000000000002"
    w = Writer()  # a navigation as Chromium lays it out: re-encoding it unchanged must be byte-exact
    put_fields(w, [7, 0, b"https://a.com/", e16("T\U0001F600"), b"\x01\xff", 1, 0, b"", 0, b"", 0, 5, b"", 200, 1])
    w.int(0)
    w.b += b"\0" * 28
    new = Reader(navigation(w.done()))
    assert (new.int(), new.int(), u8(new.bytes())) == (7, 0, fake.url("https://a.com/"))
    w = Writer()  # a named tab group: token and the fields after the title kept, the title replaced, same length
    w.b += bytes(range(16))
    w.bytes(e16("Real group"), 2)
    w.b += b"\3\0\0\0\1\0\0\0"
    new = Reader(group_metadata(w.done()))
    new.p = 16
    title = u16(new.bytes(2))
    assert new.d[:16] == bytes(range(16)) and title != "Real group" and len(title) == 10 and new.rest() == b"\3\0\0\0\1\0\0\0"
    print("selftest: OK")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        selftest()
        sys.exit()
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else WS / "made-up-new"
    for f in [ARC_OUT] + [out / name for name in BASES]:
        if f.exists():
            raise SystemExit(f"ABORT: {f} exists (this script never overwrites)")
    arc_doc = read_json(ARC)
    fake.spaces(arc_doc)
    arc_doc = scrub(arc_doc)  # the same mapping as the bases': its ids and addresses match their pins
    for name in BASES:
        base(name, out, arc_doc)
    write_json(ARC_OUT, arc_doc, indent=2, separators=(",", " : "))
    print(f"Arc's sidebar: made-up copy at {ARC_OUT} ({ARC_OUT.stat().st_size:,} bytes; Arc's: {ARC.stat().st_size:,})")
