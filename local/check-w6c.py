"""Wish 6c hands-free check: toolbar buttons dragged in the toolbar itself, with a REAL mouse.

OLE drag and drop (DoDragDrop) reads the real mouse, so posted messages cannot drive it: every press here is
SendInput, guarded as check-e15d3-auto.ps1's -- the input desktop must be the user's (not the lock screen), the
test window must be the one under the start and the end point, and nothing is pressed otherwise (the step FAILs).
The window is made topmost for the run; the cursor is put back after each drag. Run it only when the PC is free:
<local-path>\\Helium-workspace\\e17-pc-free.ps1, and the screen left UNLOCKED. Positions come from MSAA (msaa-press.ps1 -Rect).

  python -I check-w6c.py [--out Default|Dcheck] [--list]

Profile: check-w6a's throwaway testprofile-w6a, made fresh (Downloads and Task manager pinned, about:blank).
Steps (each prints PASS or FAIL; the exit code is the number of FAILs):
  1 Reload dragged onto the right half of the address bar: Reload right of it
  2 Forward -- greyed out, nothing to go forward to -- dragged there too: right of the address bar
  3 the menu (three dots) dragged to the far left: first, and no menu opened by the drag
  4 Downloads dragged onto the address bar's left end: left of it, Task manager stays right
  5 the puzzle piece dragged there: the whole extensions block left of the address bar
  6 Task manager dragged left, Escape before letting go: nothing moved
  7 Task manager dragged out of the toolbar onto the page: nothing moved
  8 Task manager dragged to the far left: first; Chrome's own pinned order follows (Task manager, Downloads)
  9 a plain click on the menu still opens it (on release); Escape closes it
 10 the puzzle piece clicked twice: its menu opens, then closes; 10b the same for Profiles (now on release)
 11 Back with history, dragged DOWN: its history menu opens (not a drag), nothing moved
 12 the saved list after a clean quit; 13 restart: the same toolbar; 0 markers in both run logs
"""
import argparse
import ctypes
import ctypes.wintypes as wt
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

LOCAL = os.path.dirname(os.path.abspath(__file__))
WS = r"<local-path>\Helium-workspace"
spec = importlib.util.spec_from_file_location("check_w6a", os.path.join(LOCAL, "check-w6a.py"))
w6a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w6a)
check = w6a.check

user32 = ctypes.WinDLL("user32", use_last_error=True)
user32.SetThreadDpiAwarenessContext.restype = ctypes.c_void_p
user32.SetThreadDpiAwarenessContext(ctypes.c_void_p(-4))  # physical pixels, as MSAA gives them
user32.WindowFromPoint.argtypes = [wt.POINT]
user32.WindowFromPoint.restype = wt.HWND
user32.GetAncestor.restype = wt.HWND
user32.OpenInputDesktop.restype = wt.HANDLE


class MOUSEINPUT(ctypes.Structure):
    _fields_ = [("dx", ctypes.c_long), ("dy", ctypes.c_long), ("data", wt.DWORD), ("flags", wt.DWORD),
                ("time", wt.DWORD), ("extra", ctypes.c_size_t)]


class KEYBDINPUT(ctypes.Structure):
    _fields_ = [("vk", wt.WORD), ("scan", wt.WORD), ("flags", wt.DWORD), ("time", wt.DWORD),
                ("extra", ctypes.c_size_t)]


class INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("mi", MOUSEINPUT), ("ki", KEYBDINPUT)]
    _fields_ = [("type", wt.DWORD), ("u", _U)]


def send(i):
    user32.SendInput(1, ctypes.byref(i), ctypes.sizeof(INPUT))


def move(x, y):
    vx, vy, vw, vh = (user32.GetSystemMetrics(n) for n in (76, 77, 78, 79))
    i = INPUT(type=0)
    i.u.mi.dx = (x - vx) * 65535 // (vw - 1)
    i.u.mi.dy = (y - vy) * 65535 // (vh - 1)
    i.u.mi.flags = 0x0001 | 0x8000 | 0x4000  # MOVE | ABSOLUTE | VIRTUALDESK
    send(i)


def button(flags):
    i = INPUT(type=0)
    i.u.mi.flags = flags
    send(i)


def key(vk):
    for up in (0, 2):
        i = INPUT(type=1)
        i.u.ki.vk, i.u.ki.flags = vk, up
        send(i)


def cursor():
    p = wt.POINT()
    user32.GetCursorPos(ctypes.byref(p))
    return p.x, p.y


class Refused(Exception):
    """A guard said no: the run stops there, nothing is retried."""


def guard(hwnd, x, y):
    """None when input may be sent at (x, y); else why not."""
    d = user32.OpenInputDesktop(0, False, 0x0001)
    if not d:
        return "no input desktop (the screen is locked?)"
    name = ctypes.create_unicode_buffer(256)
    user32.GetUserObjectInformationW(d, 2, name, 512, ctypes.byref(wt.DWORD()))
    user32.CloseDesktop(d)
    if name.value != "Default":
        return f"the input desktop is '{name.value}' (the screen is locked?)"
    if user32.GetAncestor(user32.WindowFromPoint(wt.POINT(x, y)), 2) != hwnd:
        return f"another window is at {x},{y}"
    return None


def drag(hwnd, points, escape=False, while_held=None):
    """Presses at points[0], moves through the rest in small steps, lets go (while_held() and Escape first if
    asked)."""
    for x, y in (points[0], points[-1]):
        if (why := guard(hwnd, x, y)):
            raise Refused(why)
    saved = cursor()
    down = False
    try:
        move(*points[0])
        time.sleep(0.15)
        # Absolute moves are scaled to 0..65535: a pixel off is rounding, not a DPI mismatch.
        if max(abs(c - p) for c, p in zip(cursor(), points[0])) > 2:
            raise Refused(f"the cursor went to {cursor()}, not {points[0]}")
        button(0x0002)  # LEFTDOWN
        down = True
        time.sleep(0.15)
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            for s in range(1, 21):
                move(x0 + (x1 - x0) * s // 20, y0 + (y1 - y0) * s // 20)
                time.sleep(0.025)
        time.sleep(0.4)
        move(points[-1][0], points[-1][1] + 1)
        time.sleep(0.2)
        move(*points[-1])
        time.sleep(0.6)
        if while_held:
            while_held()
        if escape:
            key(0x1B)
            time.sleep(0.4)
    finally:
        if down:
            button(0x0004)  # LEFTUP
            time.sleep(0.4)
        user32.SetCursorPos(*saved)
    return "dragged" + (", Escape, let go" if escape else "")


def click(hwnd, x, y):
    if (why := guard(hwnd, x, y)):
        raise Refused(why)
    saved = cursor()
    try:
        move(x, y)
        time.sleep(0.15)
        button(0x0002)
        time.sleep(0.06)
        button(0x0004)
        time.sleep(0.6)
    finally:
        user32.SetCursorPos(*saved)
    return "clicked"


EnumProc = ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)


def windows(pid):
    """The process's visible top-level Chrome windows: [(hwnd, owned)] -- a menu or bubble is owned, and so is a
    tooltip, which popups() leaves out by its height."""
    found = []

    def each(h, _):
        p = wt.DWORD()
        user32.GetWindowThreadProcessId(h, ctypes.byref(p))
        c = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(h, c, 64)
        if p.value == pid and user32.IsWindowVisible(h) and c.value == "Chrome_WidgetWin_1":
            r = wt.RECT()
            user32.GetWindowRect(h, ctypes.byref(r))
            found.append((h, bool(user32.GetWindow(h, 4)), r.bottom - r.top))  # GW_OWNER
        return True
    user32.EnumWindows(EnumProc(each), 0)
    return found


def popups(pid):
    """Open menus and bubbles. A tooltip (25 px tall) is not one: the test's cursor jump after a drop can leave the
    dragged button's tooltip up."""
    return sum(1 for _, owned, height in windows(pid) if owned and height > 60)


def wait_popups(pid, test, seconds=3.0):
    """The count of open menus and bubbles once test(count) holds, or after `seconds`: a menu may take a while
    to show on a busy PC (0.6 s was too short while a Dcheck link ran)."""
    end = time.time() + seconds
    while not test(count := popups(pid)) and time.time() < end:
        time.sleep(0.2)
    return count


ADDRESS = "Address and search bar"
LINE = re.compile(r"^\s*(.*)\|0x([0-9A-F]+)(\|INVISIBLE)?\|@(-?\d+),(-?\d+),(\d+),(\d+)$")


def toolbar():
    """{name: (left, top, width, height)} and the names left to right: the visible nodes in the address bar's row."""
    out = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                          os.path.join(LOCAL, "msaa-press.ps1"), "-Profile", w6a.PROFILE, "-List", "-Rect"],
                         capture_output=True, text=True, timeout=120).stdout
    nodes = []
    for line in out.splitlines():
        m = LINE.match(line)
        if m and not m.group(3) and int(m.group(7)) > 0:
            nodes.append((m.group(1).strip(), *map(int, m.group(4, 5, 6, 7))))
    bar = next((n for n in nodes if n[0] == ADDRESS), None)
    if not bar:
        return {}, []
    middle = bar[2] + bar[4] // 2
    row = {}
    for name, l, t, w, h in nodes:
        if name and name not in row and t <= middle <= t + h and (w < 200 or name == ADDRESS):
            row[name] = (l, t, w, h)
    return row, sorted(row, key=lambda n: row[n][0])


def find(row, prefix):
    return next((n for n in row if n.startswith(prefix)), None)


def centre(box):
    return box[0] + box[2] // 2, box[1] + box[3] // 2


def markers(log):
    if not os.path.exists(log):
        return -1
    text = open(log, encoding="utf-8", errors="replace").read()
    return len(re.findall(r"Check failed|FATAL|DanglingPtr|NOTREACHED", text))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="Default")
    ap.add_argument("--list", action="store_true", help="print the toolbar's MSAA row and stop")
    a = ap.parse_args()
    tag = "w6c-run" if a.out == "Default" else "w6c-dcheck-run"
    logs = [os.path.join(WS, f"{tag}{n}.log") for n in (1, 2)]
    w6a.seed_profile(False)
    b = w6a.Browser(a.out, logs[0])
    pid = b.proc.pid
    hwnd = next((h for h, owned, _ in windows(pid) if not owned), None)
    user32.SetWindowPos(hwnd, wt.HWND(-1), 0, 0, 0, 0, 0x0013)  # topmost, no move/size/activate
    # Helium installs its bundled uBlock on a fresh profile: wait until the row stops changing, so no relayout
    # lands in the middle of the first drag.
    row, names = toolbar()
    for _ in range(10):
        time.sleep(2)
        again = toolbar()
        if again == (row, names):
            break
        row, names = again
    print("toolbar:", names)
    if a.list:
        for n in names:
            print(f"  {n!r}: {row[n]}")
        b.quit()
        return
    # The app menu is named after the product ("Chromium" in this build); Profiles is "You".
    menu, puzzle, avatar = find(row, "Chromium") or find(row, "Helium"), find(row, "Extensions"), find(row, "You")
    downloads, task = find(row, "Downloads"), find(row, "Task manager")
    if not all((menu, puzzle, downloads, task, find(row, "Back"), find(row, "Forward"), find(row, "Reload"))):
        sys.exit(f"a button is missing from the toolbar's row: {names}")

    def after(name_a, name_b):
        return names.index(name_a) > names.index(name_b)

    def dragged(name, x, escape=False):
        """Drags `name` sideways along the toolbar to `x`."""
        nonlocal row, names
        start = centre(row[name])
        r = drag(hwnd, [start, (x, start[1])], escape)
        time.sleep(1.5)
        row, names = toolbar()
        print(f"  {name}: {r}\n  toolbar: {names}")
        return r

    bar = lambda: row[ADDRESS]
    right_half = lambda: bar()[0] + bar()[2] * 3 // 4
    left_end = lambda: bar()[0] + 6

    dragged("Reload", right_half())
    check("1 Reload dragged onto the address bar's right half: right of it", after("Reload", ADDRESS), names)
    dragged("Forward", right_half())
    check("2 greyed-out Forward dragged there too: right of the address bar", after("Forward", ADDRESS), names)
    before_popups = popups(pid)
    dragged(menu, row[names[0]][0] + 2)
    check("3 the menu dragged to the far left: first, no menu opened",
          names[0] == menu and popups(pid) <= before_popups, (names, popups(pid), before_popups))
    dragged(downloads, left_end())
    check("4 Downloads dragged onto the address bar's left end: left of it, Task manager right",
          after(ADDRESS, downloads) and after(task, ADDRESS), names)
    dragged(puzzle, left_end())
    check("5 the puzzle piece dragged there: the extensions block left of the address bar",
          after(ADDRESS, puzzle), names)
    was = list(names)
    dragged(task, left_end(), escape=True)
    check("6 Task manager dragged left, Escape before letting go: nothing moved", names == was, names)
    x, y = centre(row[task])
    r = drag(hwnd, [(x, y), (x - 40, y), (x - 40, y + 300)])
    time.sleep(1.5)
    row, names = toolbar()
    print(f"  {task} out onto the page: {r}\n  toolbar: {names}")
    check("7 Task manager dragged out onto the page: nothing moved", names == was, names)
    dragged(task, row[names[0]][0] + 2)
    check("8 Task manager dragged to the far left: first", names[0] == task, names)

    n = popups(pid)
    more, gone = (lambda c: c > n), (lambda c: c <= n)
    click(hwnd, *centre(row[menu]))
    opened = wait_popups(pid, more) > n
    key(0x1B)
    check("9 a plain click on the menu opens it; Escape closes it", opened and wait_popups(pid, gone) <= n,
          (opened, popups(pid)))
    # Profiles now opens on release (it opened on press): the second click must still close it.
    for step, button_name in (("10", puzzle), ("10b", avatar)):
        if not button_name:
            continue
        click(hwnd, *centre(row[button_name]))
        opened = wait_popups(pid, more) > n
        click(hwnd, *centre(row[button_name]))
        check(f"{step} {button_name} clicked twice: its menu opens, then closes",
              opened and wait_popups(pid, gone) <= n, (opened, popups(pid)))

    tab = b.page("about:blank")
    tab.call("Page.navigate", url="data:text/html,one")
    time.sleep(1.5)
    tab.call("Page.navigate", url="data:text/html,two")
    time.sleep(2)
    row, names = toolbar()
    was = list(names)
    x, y = centre(row[find(row, "Back")])
    # Checked while the button is still down: letting go over the menu would pick a history entry.
    held = []
    r = drag(hwnd, [(x, y), (x, y + 60)], escape=True, while_held=lambda: held.append(wait_popups(pid, more) > n))
    opened = held == [True]
    wait_popups(pid, gone)
    row, names = toolbar()
    print(f"  Back down: {r}\n  toolbar: {names}")
    check("11 Back dragged DOWN: its history menu opens, nothing moved", opened and names == was, names)
    # The toolbar's own buttons and the address bar: the address bar's icons change with the page ("Not secure"
    # on a data: page, "View site information" on about:blank after the restart).
    tracked = {menu, puzzle, downloads, task, avatar, ADDRESS, find(row, "Back"), find(row, "Forward"),
               find(row, "Reload")}
    expected = [n for n in names if n in tracked]
    b.quit()

    saved = w6a.saved_order() or []
    with open(os.path.join(w6a.PROFILE, "Default", "Preferences"), encoding="utf-8") as f:
        pinned = json.load(f).get("toolbar", {}).get("pinned_actions")
    print("saved:", saved, "\npinned:", pinned)
    check("12 the saved list: Task manager, the menu, ... then location_bar, Forward, Reload; pinned order follows",
          bool(saved) and saved.index("kActionTaskManager") < saved.index("kActionShowAppMenu")
          < saved.index("location_bar") < saved.index("kActionForward") < saved.index("kActionReload")
          and pinned.index("kActionTaskManager") < pinned.index("kActionShowDownloads"), (saved, pinned))

    b = w6a.Browser(a.out, logs[1])
    hwnd = next((h for h, owned, _ in windows(b.proc.pid) if not owned), None)
    row, names = toolbar()
    print("toolbar after restart:", names)
    check("13 restart: the same toolbar", [n for n in names if n in tracked] == expected, (names, expected))
    b.quit()
    counts = [markers(log) for log in logs]
    check("0 markers (Check failed / FATAL / DanglingPtr / NOTREACHED) in both run logs",
          counts == [0, 0], counts)

    print(f"\n{'ALL PASS' if not w6a.FAILS else 'FAILED: ' + ', '.join(w6a.FAILS)}")
    sys.exit(len(w6a.FAILS))


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Refused as e:
        print(f"FAIL stopped at a guard refusal (nothing retried): {e}", flush=True)
        w6a.close_test_browsers()
        sys.exit(98)
    except Exception as e:
        print(f"FAIL the check stopped: {type(e).__name__}: {e}", flush=True)
        w6a.close_test_browsers()
        sys.exit(99)
