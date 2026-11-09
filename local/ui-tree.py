"""Prints the browser's own views (boxes on screen) through Chromium's UI DevTools.

Start the browser with --enable-ui-devtools=0: it picks a free port and writes it to
<user-data-dir>\\UIDevToolsActivePort. This reads that port, asks for the view tree (DOM.getDocument)
and, for every view under each view of class --root, its properties (CSS.getMatchedStylesForNode):
bounds, the Visible flag, a label's text. Read-only: it changes nothing in the browser.

  python -I ui-tree.py <user-data-dir> [--root UnpinnedTabContainerView] [--all-props]

Standard library only (a minimal websocket client below): no package to install.
"""
import argparse
import base64
import json
import os
import socket
import struct
import sys


class WebSocket:
    def __init__(self, port, path="/0"):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=20)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
                           f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\n"
                           "Sec-WebSocket-Version: 13\r\n\r\n").encode())
        self.rest = b""
        while b"\r\n\r\n" not in self.rest:
            self.rest += self._recv()
        head, self.rest = self.rest.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise IOError("no websocket: " + head.decode(errors="replace"))

    def _recv(self):
        chunk = self.sock.recv(1 << 16)
        if not chunk:
            raise IOError("the browser closed the connection")
        return chunk

    def _read(self, n):
        while len(self.rest) < n:
            self.rest += self._recv()
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def send(self, text):
        data, mask = text.encode(), os.urandom(4)
        n = len(data)
        head = bytes([0x81, 0x80 | n]) if n < 126 else (
            bytes([0x81, 0xFE]) + struct.pack(">H", n) if n < 65536 else bytes([0x81, 0xFF]) + struct.pack(">Q", n))
        self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

    def receive(self):
        message = b""
        while True:
            b0, b1 = self._read(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            if b1 & 0x80:
                self._read(4)  # a server never masks; read past it if one did
            payload = self._read(n)
            if b0 & 0x0F == 8:
                raise IOError("the browser closed the connection")
            if b0 & 0x0F in (9, 10):  # ping / pong
                continue
            message += payload
            if b0 & 0x80:
                return message.decode()


class Client:
    def __init__(self, port):
        self.ws, self.last_id = WebSocket(port), 0

    def call(self, method, **params):
        self.last_id += 1
        self.ws.send(json.dumps({"id": self.last_id, "method": method, "params": params}))
        while True:
            reply = json.loads(self.ws.receive())
            if reply.get("id") == self.last_id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply.get("result", {})


def attrs(node):
    a = node.get("attributes") or []
    return dict(zip(a[0::2], a[1::2]))


def cls(node):
    return attrs(node).get("class") or node.get("nodeName", "?")


def props(client, node):
    """[(group, {name: value})] -- a view's properties, one group per class it derives from."""
    try:
        res = client.call("CSS.getMatchedStylesForNode", nodeId=node["nodeId"])
    except RuntimeError as e:
        return [("error", {"": str(e)})]
    out = []
    for rule in res.get("matchedCSSRules", []):
        r = rule.get("rule", rule)
        sel = r.get("selectorList", {})
        group = sel.get("text") or ",".join(s.get("text", "") for s in sel.get("selectors", [])) or "?"
        out.append((group, {p["name"]: p["value"] for p in r.get("style", {}).get("cssProperties", [])}))
    return out


# Views whose children are listed; any other view is one line (a tab's title is printed on its line). The pinned
# section's children (C35): its header, the card, the line under the card, "+ New Tab".
CONTAINERS = ("UnpinnedTabContainerView", "PinnedTabContainerView", "SplitTabView", "TabGroupView",
              "WorkspacePinnedSectionView")


def title(node):
    for child in node.get("children") or []:
        if cls(child) == "TabTitle":
            return child
    return None


def line(client, node):
    f = {}
    for _, kv in props(client, node):
        f.update(kv)
    s = f"{cls(node)} @{f.get('X')},{f.get('Y')} {f.get('Width')}x{f.get('Height')}"
    if f.get("Visible") != "true":
        s += " INVISIBLE"
    if f.get("IsDrawn") != "true":
        s += " not-drawn"
    if cls(node) == "TabView" and (t := title(node)) is not None:
        tf = {}
        for _, kv in props(client, t):
            tf.update(kv)
        s += f'  "{tf.get("Text", "?")}"'
    return s


def show(client, node, depth, all_props, lines):
    if all_props:
        lines.append("  " * depth + cls(node) + "  " + "; ".join(
            f"[{g}] " + ", ".join(f"{k}={v}" for k, v in kv.items()) for g, kv in props(client, node)))
    else:
        lines.append("  " * depth + line(client, node))
    if all_props or cls(node) in CONTAINERS:
        for child in node.get("children") or []:
            show(client, child, depth + 1, all_props, lines)


def find(node, name, found):
    if cls(node) == name:
        found.append(node)
        return
    for child in node.get("children") or []:
        find(child, name, found)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("profile")
    ap.add_argument("--root", default="UnpinnedTabContainerView")
    ap.add_argument("--all-props", action="store_true")
    a = ap.parse_args()
    port_file = os.path.join(a.profile, "UIDevToolsActivePort")
    if not os.path.exists(port_file):
        sys.exit(f"no {port_file}: was the browser started with --enable-ui-devtools=0?")
    port = int(open(port_file, encoding="utf-8").read().strip())
    client = Client(port)
    for domain in ("DOM", "CSS"):
        try:
            client.call(f"{domain}.enable")
        except RuntimeError as e:
            print(f"warning: {e}", file=sys.stderr)
    root = client.call("DOM.getDocument")["root"]
    found = []
    find(root, a.root, found)
    if not found:
        sys.exit(f"no view of class {a.root} in the tree")
    lines = []
    for n in found:
        show(client, n, 0, a.all_props, lines)
    print("\n".join(lines))


if __name__ == "__main__":
    main()
