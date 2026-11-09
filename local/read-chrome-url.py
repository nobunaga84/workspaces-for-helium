"""Read a chrome:// page from the fork build via chromedriver (W3C WebDriver over HTTP).

Headless mode redirects chrome:// URLs to the NTP, and screen-scraping grabs whatever
window is topmost. Driving the real binary with chromedriver avoids both.

Usage: read_pref.py <chrome-url> [<chrome-url> ...]
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

OUT = Path(r"<local-path>\Helium-workspace\helium-windows\build\src\out\Default")
DRIVER = OUT / "chromedriver.exe"
CHROME = OUT / "chrome.exe"
PROFILE = Path(r"<local-path>\Helium-workspace\wdprofile")
PORT = 9515
BASE = f"http://127.0.0.1:{PORT}"


def rpc(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


proc = subprocess.Popen(
    [str(DRIVER), f"--port={PORT}"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
)
session = None
try:
    for _ in range(40):  # wait for the driver to accept connections
        try:
            urllib.request.urlopen(BASE + "/status", timeout=2).read()
            break
        except (urllib.error.URLError, OSError):
            time.sleep(0.5)

    caps = {"capabilities": {"alwaysMatch": {"goog:chromeOptions": {
        "binary": str(CHROME),
        "args": [f"--user-data-dir={PROFILE}", "--no-first-run",
                 "--no-default-browser-check"],
    }}}}
    session = rpc("POST", "/session", caps)["value"]["sessionId"]

    for url in sys.argv[1:]:
        rpc("POST", f"/session/{session}/url", {"url": url})
        time.sleep(1.5)
        body = rpc("POST", f"/session/{session}/execute/sync", {
            "script": "return document.body.innerText;", "args": [],
        })["value"]
        print(f"--- {url}")
        print((body or "<empty>").strip()[:400])
finally:
    if session:
        try:
            rpc("DELETE", f"/session/{session}")
        except Exception:
            pass
    proc.terminate()
