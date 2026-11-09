# Patches 78-79 (pinned pages' icons): seeds a TEST profile copy for check-icons.ps1.
#   python -I icons-seed.py <profile-copy> <pages-dir> <port>
# - <pages-dir>\red.png, blue.png: 32x32 solid icons for the local pages;
# - Favicons: the made-up site icons.test twice -- first an old icon (blue) for
#   http://icons.test/old, then a newer one (green) for https://icons.test/new, so
#   the old mapping has the lower id, as an icon imported years ago does;
# - Workspace Pins: at the top of Home ("default"), "Icon red" (the local page
#   iconred.html, its icon red.png -- never visited, so no icon is known for it)
#   and "Icon site" (https://icons.test/never: never opened, its icon only by
#   the host fallback). The file's version is kept, as check-c3 does.
# Run with the browser closed. Prints what it wrote.
import json
import os
import sqlite3
import struct
import sys
import time
import zlib

profile, pages, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
RED, GREEN, BLUE = (255, 0, 0), (0, 192, 0), (0, 0, 255)


def png(rgb, size=32):
    raw = b"".join(b"\x00" + bytes(rgb) * size for _ in range(size))

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data +
                struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


for name, rgb in (("red", RED), ("blue", BLUE)):
    with open(os.path.join(pages, name + ".png"), "wb") as f:
        f.write(png(rgb))

# Chrome's time: microseconds since 1601-01-01.
now = int((time.time() + 11644473600) * 1_000_000)
db = sqlite3.connect(os.path.join(profile, "Default", "Favicons"))
for page, icon, rgb in (("http://icons.test/old", "http://icons.test/favicon.ico", BLUE),
                        ("https://icons.test/new", "https://icons.test/favicon.png", GREEN)):
    icon_id = db.execute("INSERT INTO favicons (url, icon_type) VALUES (?, 1)", (icon,)).lastrowid
    db.execute("INSERT INTO favicon_bitmaps (icon_id, last_updated, image_data, width, height, "
               "last_requested) VALUES (?, ?, ?, 32, 32, 0)", (icon_id, now, png(rgb)))
    mapping = db.execute("INSERT INTO icon_mapping (page_url, icon_id, page_url_type) "
                         "VALUES (?, ?, 0)", (page, icon_id)).lastrowid
    print("favicons: %s -> %s (icon %d, mapping %d)" % (page, icon, icon_id, mapping))
db.commit()
db.close()

path = os.path.join(profile, "Default", "Workspace Pins")
with open(path, encoding="utf-8") as f:
    pins = json.load(f)
pins["workspaces"]["default"][0:0] = [
    {"type": "item", "id": "icr", "title": "Icon red",
     "url": "http://127.0.0.1:%d/iconred.html" % port},
    {"type": "item", "id": "ics", "title": "Icon site", "url": "https://icons.test/never"},
]
with open(path, "w", encoding="utf-8") as f:
    json.dump(pins, f, ensure_ascii=False)
print("pins: 'Icon red', 'Icon site' at the top of Home")
