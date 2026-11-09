"""Wish 6a hands-free check: the toolbar follows the saved order, and Settings' Toolbar list reorders it.

Starts out\\<out>\\chrome.exe on a throwaway profile (<local-path>\\Helium-workspace\\testprofile-w6a, made fresh each run,
two Chrome buttons pinned: Downloads and Task manager). No real mouse or keyboard: the toolbar's buttons are read
through Chromium's UI DevTools (the views' own bounds), the Toolbar list is opened the way Settings opens it and
driven through the DevTools protocol (a keyboard Alt+Up and a row drag, as the page's own handlers see them; 5g's
click and keys go through the protocol's Input domain, so the focus lands where a mouse and keyboard put it).

  python -I check-w6a.py [--out Default|Dcheck] [--zen]

--zen: a copy of testprofile-e15b-smoke (vertical tabs, workspaces) in zen mode with the sidebar unpinned -- how the
daily browser runs -- instead of a fresh profile.

Steps (each prints PASS or FAIL; the exit code is the number of FAILs):
  1 nothing saved: Helium's own toolbar (Reload | address bar | extensions | pinned group | menu); 1b the New tab
    button shows in this layout too (wish 6c, the owner's choice: Helium showed it in Dynamic only)
  2 the list: one list in that order, "Address and search bar" a row of its own; 2b Space twice on Task manager's
    switch: the focus follows it as the list re-sorts, so the second Space pins it back
  3 Alt+Up x6 on the address bar row: the address bar is first -> every button sits right of it
  4 drag Menu to the top: the menu is left of the address bar
  5 drag Downloads above the address bar: Downloads ALONE left of it (6b), Task manager stays right; Alt+Up /
    Alt+Down on the address bar row pass one row; Task manager dragged left too; Copy link switched on appears
    where its row sits; 5g a click on Downloads' name selects its row, its switch untouched, and Alt+Up / Alt+Down
    move it (the owner's way, 11-02)
  6 the saved list, read back from the Preferences file after a clean quit
  7 restart: the order is still there
  7c Unpin from a Chrome button's own right-click menu (posted right-click, MSAA press): it leaves, no crash
  8 the list's Reset to default: Helium's own toolbar again, nothing saved (Chrome's buttons go back to Helium's
    defaults too: that part is Chromium's own reset)
"""
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

WS = r"<local-path>\Helium-workspace"
PROFILE = os.path.join(WS, "testprofile-w6a")
LOCAL = os.path.dirname(os.path.abspath(__file__))

spec = importlib.util.spec_from_file_location("ui_tree", os.path.join(LOCAL, "ui-tree.py"))
ui_tree = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui_tree)

FAILS = []


def check(name, ok, detail=""):
    print(("PASS " if ok else "FAIL ") + name + (f"  ({detail})" if detail else ""), flush=True)
    if not ok:
        FAILS.append(name)


def wait_file(path, seconds=60):
    end = time.time() + seconds
    while time.time() < end:
        if os.path.exists(path) and os.path.getsize(path) > 0:
            return open(path, encoding="utf-8").read().splitlines()
        time.sleep(0.25)
    sys.exit(f"no {path} after {seconds} s")


def seed_profile(zen):
    if os.path.exists(PROFILE):
        shutil.rmtree(PROFILE)
    prefs_path = os.path.join(PROFILE, "Default", "Preferences")
    if zen:
        shutil.copytree(os.path.join(WS, "testprofile-e15b-smoke"), PROFILE)
        shutil.rmtree(os.path.join(PROFILE, "Default", "Sessions"), ignore_errors=True)
        with open(prefs_path, encoding="utf-8") as f:
            prefs = json.load(f)
        browser = prefs.setdefault("helium", {}).setdefault("browser", {})
        browser["zen_mode"] = True
        browser["zen_mode_sidebar_pinned"] = False
        prefs.get("helium", {}).get("workspaces", {}).pop("toolbar_order", None)
    else:
        os.makedirs(os.path.join(PROFILE, "Default"))
        prefs = {"browser": {"has_seen_welcome_page": True}}
    prefs.setdefault("toolbar", {})["pinned_actions"] = ["kActionShowDownloads", "kActionTaskManager"]
    with open(prefs_path, "w", encoding="utf-8") as f:
        json.dump(prefs, f)


class Browser:
    def __init__(self, out, log):
        for name in ("DevToolsActivePort", "UIDevToolsActivePort"):
            if os.path.exists(os.path.join(PROFILE, name)):
                os.remove(os.path.join(PROFILE, name))
        exe = os.path.join(WS, "helium-windows", "build", "src", "out", out, "chrome.exe")
        self.proc = subprocess.Popen([exe, f"--user-data-dir={PROFILE}", "--enable-ui-devtools=0",
                                      "--remote-debugging-port=0", "--no-first-run",
                                      "--no-default-browser-check", "--enable-logging",
                                      f"--log-file={log}", "--v=0", "--window-size=1400,900",
                                      "--window-position=0,0", "about:blank"])
        self.port = int(wait_file(os.path.join(PROFILE, "DevToolsActivePort"))[0])
        ui_port = int(wait_file(os.path.join(PROFILE, "UIDevToolsActivePort"))[0])
        self.ui = ui_tree.Client(ui_port)
        for domain in ("DOM", "CSS"):
            self.ui.call(f"{domain}.enable")
        time.sleep(3)

    def targets(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/json/list", timeout=10) as r:
            return json.load(r)

    def page(self, url_prefix, seconds=30):
        end = time.time() + seconds
        while time.time() < end:
            for t in self.targets():
                if t.get("url", "").startswith(url_prefix) and t.get("webSocketDebuggerUrl"):
                    path = "/" + t["webSocketDebuggerUrl"].split("/", 3)[3]
                    client = ui_tree.Client.__new__(ui_tree.Client)
                    client.ws, client.last_id = ui_tree.WebSocket(self.port, path), 0
                    return client
            time.sleep(0.5)
        sys.exit(f"no DevTools target for {url_prefix}; targets: "
                 + ", ".join(t.get("url", "?") for t in self.targets()))

    def toolbar(self):
        """[(class, x)] of the toolbar's visible direct children, left to right."""
        root = self.ui.call("DOM.getDocument")["root"]
        found = []
        ui_tree.find(root, "ToolbarView", found)
        if not found:
            sys.exit("no ToolbarView in the views tree")
        out = []
        for child in found[0].get("children") or []:
            f = {}
            for _, kv in ui_tree.props(self.ui, child):
                f.update(kv)
            if f.get("Visible") == "true" and f.get("Width") not in (None, "0"):
                out.append((ui_tree.cls(child), int(float(f.get("X", "0")))))
        return sorted(out, key=lambda c: c[1])

    def quit(self):
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/json/version", timeout=10) as r:
            path = "/" + json.load(r)["webSocketDebuggerUrl"].split("/", 3)[3]
        client = ui_tree.Client.__new__(ui_tree.Client)
        client.ws, client.last_id = ui_tree.WebSocket(self.port, path), 0
        try:
            client.call("Browser.close")
        except Exception:
            pass
        try:
            self.proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        time.sleep(2)


def order(toolbar):
    return [c for c, _ in toolbar]


PINNED = "PinnedActionToolbarButton"  # one per Chrome button the box lent the toolbar (wish 6b)


def pinned_sides(toolbar):
    """(left, right): how many Chrome buttons sit left and right of the address bar."""
    names = order(toolbar)
    if "LocationBarView" not in names:
        return (-1, -1)
    at = names.index("LocationBarView")
    return (names[:at].count(PINNED), names[at:].count(PINNED))


def before(toolbar, a, b):
    names = order(toolbar)
    return a in names and b in names and names.index(a) < names.index(b)


# The list element (the fork's own since the hook shrink, part 5), found through every shadow root; its
# rows by data-index. The page around it keeps the Reset button.
FIND = """
const deep = (root, tag) => {
  const stack = [root];
  while (stack.length) {
    const n = stack.pop();
    if (n.tagName && n.tagName.toLowerCase() === tag) return n;
    if (n.shadowRoot) stack.push(n.shadowRoot);
    for (const c of (n.children || [])) stack.push(c);
  }
  return null;
};
const list = deep(document, 'customize-chrome-workspace-toolbar-list');
const page = deep(document, 'customize-chrome-toolbar');
"""


def evaluate(page, body):
    res = page.call("Runtime.evaluate", expression="(async () => {" + FIND + body + "})()",
                    awaitPromise=True, returnByValue=True)
    if "exceptionDetails" in res:
        raise RuntimeError(json.dumps(res["exceptionDetails"])[:600])
    return res.get("result", {}).get("value")


def rows(page):
    return evaluate(page, """
      if (!list) return null;
      await list.updateComplete;
      return list.actions_.map(a => a.displayName);""")


def alt_up(page, index):
    return evaluate(page, f"""
      const row = list.shadowRoot.querySelector('[data-index="{index}"]');
      row.dispatchEvent(new KeyboardEvent('keydown', {{key: 'ArrowUp', altKey: true,
                                                     bubbles: true, composed: true}}));
      await list.updateComplete;
      return list.actions_.map(a => a.displayName);""")


def alt_key(page, index, key):
    return evaluate(page, f"""
      const row = list.shadowRoot.querySelector('[data-index="{index}"]');
      row.dispatchEvent(new KeyboardEvent('keydown', {{key: '{key}', altKey: true,
                                                     bubbles: true, composed: true}}));
      await list.updateComplete;
      return list.actions_.map(a => a.displayName);""")


def real_click(page, name):
    """A click through the Input domain on a row's name: the focus lands where a mouse puts it."""
    x, y = evaluate(page, f"""
      const i = list.actions_.findIndex(a => a.displayName === {json.dumps(name)});
      const el = list.shadowRoot.querySelector(`[data-index="${{i}}"]`).querySelector('.toggle-title');
      el.scrollIntoView({{block: 'center'}});
      const r = el.getBoundingClientRect();
      return [r.left + r.width / 2, r.top + r.height / 2];""")
    for kind in ("mousePressed", "mouseReleased"):
        page.call("Input.dispatchMouseEvent", type=kind, x=x, y=y, button="left", clickCount=1)


def real_alt(page, key):
    """Alt+<arrow> through the Input domain, to whatever has the focus (alt_key fires at a row instead)."""
    code = {"ArrowUp": 38, "ArrowDown": 40}[key]
    alt = dict(key="Alt", code="AltLeft", windowsVirtualKeyCode=18, nativeVirtualKeyCode=18, modifiers=1)
    arrow = dict(key=key, code=key, windowsVirtualKeyCode=code, nativeVirtualKeyCode=code, modifiers=1)
    page.call("Input.dispatchKeyEvent", type="rawKeyDown", **alt)
    page.call("Input.dispatchKeyEvent", type="rawKeyDown", **arrow)
    page.call("Input.dispatchKeyEvent", type="keyUp", **arrow)
    page.call("Input.dispatchKeyEvent", type="keyUp", **dict(alt, modifiers=0))


def real_space(page):
    """Space through the Input domain, to whatever has the focus (a focused switch flips)."""
    space = dict(key=" ", code="Space", windowsVirtualKeyCode=32, nativeVirtualKeyCode=32)
    page.call("Input.dispatchKeyEvent", type="keyDown", text=" ", **space)
    page.call("Input.dispatchKeyEvent", type="keyUp", **space)


def focused_row(page):
    """The name on the row the focus is on (the row itself or its switch), or None."""
    return evaluate(page, """
      const el = list.shadowRoot.activeElement;
      const row = el && el.closest('[data-index]');
      return row ? list.actions_[Number(row.dataset.index)].displayName : null;""")


def drag(page, src_name, dst_name):
    return evaluate(page, f"""
      const names = list.actions_.map(a => a.displayName);
      const at = n => list.shadowRoot.querySelector(`[data-index="${{names.indexOf(n)}}"]`);
      const src = at({json.dumps(src_name)}), dst = at({json.dumps(dst_name)});
      const dt = new DataTransfer();
      const ev = (type, y) => new DragEvent(type, {{bubbles: true, composed: true, cancelable: true,
                                                   dataTransfer: dt, clientY: y}});
      const r = dst.getBoundingClientRect();
      src.dispatchEvent(ev('dragstart', 0));
      dst.dispatchEvent(ev('dragover', r.top + 1));
      dst.dispatchEvent(ev('drop', r.top + 1));
      src.dispatchEvent(ev('dragend', 0));
      await list.updateComplete;
      return list.actions_.map(a => a.displayName);""")


def saved_order():
    with open(os.path.join(PROFILE, "Default", "Preferences"), encoding="utf-8") as f:
        p = json.load(f)
    return p.get("helium", {}).get("workspaces", {}).get("toolbar_order")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Default")
    ap.add_argument("--zen", action="store_true")
    a = ap.parse_args()
    tag = ("w6a-run" if a.out == "Default" else "w6a-dcheck-run") + ("-zen" if a.zen else "")
    seed_profile(a.zen)

    b = Browser(a.out, os.path.join(WS, f"{tag}1.log"))
    t = b.toolbar()
    print("toolbar:", order(t))
    check("1 nothing saved: Helium's own order, Downloads + Task manager after the extensions",
          before(t, "ReloadButton", "LocationBarView") and before(t, "LocationBarView", "ExtensionsToolbarDesktop")
          and before(t, "ExtensionsToolbarDesktop", PINNED) and before(t, PINNED, "BrowserAppMenuButton")
          and pinned_sides(t) == (0, 2), order(t))
    # The New tab button has no class name of its own: the plain ToolbarButton right after the address bar.
    names = order(t)
    check("1b the New tab button shows (its switch is on by default), right after the address bar",
          names[names.index("LocationBarView") + 1] == "ToolbarButton", names)

    settings_client = b.page("about:blank")
    settings_client.call("Page.navigate", url="chrome://settings/appearance")
    time.sleep(3)
    settings = b.page("chrome://settings")
    settings.call("Runtime.evaluate", expression="chrome.send('openCustomizeChromeToolbarSection')")
    panel = b.page("chrome://customize-chrome-side-panel.top-chrome")
    names = None
    for _ in range(40):
        names = rows(panel)
        if names:
            break
        time.sleep(0.5)
    print("list:", names)
    address = "Address and search bar"
    check("2 the list: one list, the address bar a row of its own",
          bool(names) and address in names and "Downloads" in names
          and names.index("Downloads") > names.index(address), names)
    # Nothing saved, a switch flip re-sorts the list (an unpinned button leaves the toolbar's order). Rows are drawn
    # by index: the focus must follow the button, or the second Space flips whatever moved into its place.
    # Chromium's panel focuses its Back button once the page is open (openToolbarCustomizationPage, after a
    # render). Wait for it: a switch focused first loses the focus to it, and the Space presses Back.
    start = time.time()
    while time.time() - start < 10 and not evaluate(panel, "return page.shadowRoot.activeElement?.id === 'heading';"):
        time.sleep(0.25)
    print(f"the panel's Back button has the focus after {time.time() - start:.2f} s")
    pins = "return list.actions_.filter(a => a.pinned).map(a => a.displayName);"
    was = (names, evaluate(panel, pins))
    evaluate(panel, """
      const i = list.actions_.findIndex(a => a.displayName === 'Task manager');
      list.shadowRoot.querySelector(`[data-index="${i}"] cr-toggle`).focus();
      return true;""")
    real_space(panel)
    time.sleep(1.5)
    first = (focused_row(panel), rows(panel).index("Task manager"))
    real_space(panel)
    time.sleep(1.5)
    names = rows(panel)
    now = (names, evaluate(panel, pins))
    check("2b Space twice on Task manager's switch: the focus follows it as the list re-sorts, the same switch "
          "pinned back", first[0] == "Task manager" and first[1] != was[0].index("Task manager")
          and focused_row(panel) == "Task manager" and now == was, (first, now[1]))

    for _ in range(names.index(address)):
        names = alt_up(panel, names.index(address))
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("3 Alt+Up: the address bar first, every button right of it",
          names[0] == address and before(t, "LocationBarView", "ReloadButton")
          and before(t, "LocationBarView", "BrowserAppMenuButton"), order(t))

    menu = next(n for n in names if "menu" in n.lower() and n != address)
    names = drag(panel, menu, names[0])
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("4 drag the menu to the top: the menu left of the address bar",
          names[0] == menu and before(t, "BrowserAppMenuButton", "LocationBarView"), order(t))

    names = drag(panel, "Downloads", address)
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("5 drag Downloads above the address bar: Downloads ALONE left of it (wish 6b)",
          names.index("Downloads") < names.index(address) and pinned_sides(t) == (1, 1), order(t))
    check("5b Task manager stays right of the address bar, in the list too",
          names.index("Task manager") > names.index(address), names)

    # The keyboard moves one row at a time: the address bar passes Downloads alone.
    alt_key(panel, names.index(address), "ArrowUp")
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("5c Alt+Up on the address bar row passes Downloads: both Chrome buttons right of it",
          names.index(address) + 1 == names.index("Downloads") and pinned_sides(t) == (0, 2), names)
    alt_key(panel, names.index(address), "ArrowDown")
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("5d Alt+Down: Downloads left of it again",
          names.index(address) == names.index("Downloads") + 1 and pinned_sides(t) == (1, 1), names)
    drag(panel, "Task manager", "Downloads")
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("5e drag Task manager in front of Downloads: both left of the address bar",
          names.index("Task manager") + 1 == names.index("Downloads") and pinned_sides(t) == (2, 0), names)
    # A button switched on in the list appears where its row sits (right of the address bar). Its switch: a click
    # on the row only selects it (5g).
    evaluate(panel, f"""
      list.shadowRoot.querySelector('[data-index="{names.index("Copy link")}"] cr-toggle').click();
      return true;""")
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("5f switch Copy link on: it appears right of the address bar, where its row sits",
          names.index("Copy link") > names.index(address) and pinned_sides(t) == (2, 1), order(t))
    # The owner's way (11-02, by hand): a click on a row's name, then Alt+Up. The click flipped the switch and left
    # the focus outside the list, so the keys went nowhere; alt_key above never needed the focus.
    real_click(panel, "Downloads")
    still_on = True
    for _ in range(6):  # a flipped switch shows on the browser's redraw: watch 3 s, not one read
        time.sleep(0.5)
        still_on = still_on and evaluate(panel, "return list.actions_.find(a => a.displayName === 'Downloads').pinned;")
    selected = focused_row(panel)
    real_alt(panel, "ArrowUp")
    time.sleep(1.5)
    names = rows(panel)
    t = b.toolbar()
    print("list:", names, "\ntoolbar:", order(t))
    check("5g a real click on Downloads' name selects its row; a real Alt+Up: it passes Task manager, its switch "
          "untouched", selected == "Downloads" and still_on
          and names.index("Downloads") + 1 == names.index("Task manager") and pinned_sides(t) == (2, 1),
          (selected, still_on, names))
    up = names
    real_alt(panel, "ArrowDown")
    time.sleep(1.5)
    names = rows(panel)
    print("list:", names)
    check("5h a real Alt+Down after 5g's move: Task manager in front again",
          up.index("Downloads") + 1 == up.index("Task manager")
          and names.index("Task manager") + 1 == names.index("Downloads"), names)
    expected = list(names)
    b.quit()

    saved = saved_order()
    print("saved:", saved)
    check("6 the saved list: menu first, Task manager and Downloads before location_bar",
          bool(saved) and saved[0] == "kActionShowAppMenu"
          and saved.index("kActionTaskManager") < saved.index("kActionShowDownloads") < saved.index("location_bar"),
          saved)

    b = Browser(a.out, os.path.join(WS, f"{tag}2.log"))
    t = b.toolbar()
    print("toolbar after restart:", order(t))
    check("7 restart: the order is still there (2 Chrome buttons left, Copy link right)",
          before(t, "BrowserAppMenuButton", "LocationBarView") and pinned_sides(t) == (2, 1)
          and before(t, "LocationBarView", "ReloadButton"), order(t))

    tab = b.page("about:blank")
    tab.call("Page.navigate", url="chrome://settings/appearance")
    time.sleep(3)
    b.page("chrome://settings").call("Runtime.evaluate",
                                     expression="chrome.send('openCustomizeChromeToolbarSection')")
    panel = b.page("chrome://customize-chrome-side-panel.top-chrome")
    names = None
    for _ in range(40):
        names = rows(panel)
        if names:
            break
        time.sleep(0.5)
    check("7b the list after restart reads as it was left", names == expected, names)
    # Unpin from a hosted button's OWN right-click menu, which the button owns (6b review: it was freed under it).
    out = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                          os.path.join(LOCAL, "w6b-unpin-menu.ps1"), "-Profile", PROFILE,
                          "-BrowserPid", str(b.proc.pid), "-Button", "Copy link - pinned"],
                         capture_output=True, text=True, timeout=180)
    print("unpin:", out.stdout.strip())
    time.sleep(2)
    t = b.toolbar()
    check("7c Unpin from Copy link's own right-click menu: it leaves the toolbar, the browser lives",
          b.proc.poll() is None and pinned_sides(t) == (2, 0), (out.stdout.strip(), order(t)))
    evaluate(panel, "page.shadowRoot.querySelector('#resetToDefaultButton').click(); return true;")
    time.sleep(1.5)
    t = b.toolbar()
    names = rows(panel)
    print("list after reset:", names, "\ntoolbar:", order(t))
    # Reset also puts Chrome's buttons back to Helium's defaults (Chromium's own reset): no pinned group to check.
    check("8 Reset to default: Helium's own order again",
          before(t, "ReloadButton", "LocationBarView") and before(t, "LocationBarView", "BrowserAppMenuButton")
          and names and names.index(address) == 6, order(t))
    b.quit()
    check("8b nothing saved after the reset", not saved_order(), saved_order())

    print(f"\n{'ALL PASS' if not FAILS else 'FAILED: ' + ', '.join(FAILS)}")
    sys.exit(len(FAILS))


def close_test_browsers():
    """Every chrome.exe on the throwaway profile -- never another browser."""
    subprocess.run(["powershell.exe", "-NoProfile", "-Command",
                    "Get-CimInstance Win32_Process -Filter \"Name='chrome.exe'\" | Where-Object { $_.CommandLine "
                    "-like '*testprofile-w6a*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"],
                   check=False)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # a page that dies (a bad mojo message kills it) shows up as a socket timeout
        print(f"FAIL the check stopped: {type(e).__name__}: {e}", flush=True)
        close_test_browsers()
        sys.exit(99)
