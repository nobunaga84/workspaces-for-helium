"""F4: Workspaces for Helium's branding files, drawn from the three SVGs in local/branding/.

  python -I local/make-branding.py                       writes resources/branding/ in this repo
  python -I local/make-branding.py --apply <build/src>   also copies them into a prepared Chromium tree, by
                                                         Helium's own resource step (helium-windows' build.py
                                                         runs the same two lists on a fresh build)
Needs Pillow and the Segoe UI Semibold font (C:/Windows/Fonts/seguisb.ttf) for the wordmark.

The SVGs use only <rect> (x y width height rx fill fill-opacity stroke stroke-width) and <circle> (cx cy r fill).
Each is drawn 8 times larger and shrunk by area averaging, so edges stay sharp; 16 and 32 px come from their own
pixel-aligned drawings, never from the big one.
"""
import pathlib
import shutil
import sys
import xml.etree.ElementTree as ET

from PIL import Image, ImageDraw, ImageFont

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "local" / "branding"
OUT = REPO / "resources" / "branding"
MASTER, ICON32, ICON16 = (SRC / f"workspaces-for-helium{s}.svg" for s in ("", "-32", "-16"))
FONT = pathlib.Path("C:/Windows/Fonts/seguisb.ttf")
WORDMARK = "Workspaces for Helium"
SS = 8  # supersampling


def shapes(svg):
    root = ET.parse(svg).getroot()
    side = float(root.get("viewBox").split()[2])
    return side, [(el.tag.split("}")[-1], el.attrib) for el in root if el.tag.split("}")[-1] in ("rect", "circle")]


def rgba(hex_color, opacity=1.0):
    h = hex_color.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), round(255 * opacity)


def argb(hex_color, opacity=1.0):
    """A .icon file's colour command."""
    r, g, b, a = rgba(hex_color, opacity)
    return f"PATH_COLOR_ARGB, 0x{a:02X}, 0x{r:02X}, 0x{g:02X}, 0x{b:02X}"


def render(svg, size):
    """The SVG at size x size pixels."""
    side, items = shapes(svg)
    s = size * SS / side
    img = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))

    def box(draw, x, y, w, h, r, fill):
        draw.rounded_rectangle([x * s, y * s, (x + w) * s - 1, (y + h) * s - 1], radius=max(r, 0) * s, fill=fill)

    for tag, a in items:
        layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        fill = rgba(a["fill"], float(a.get("fill-opacity", 1)))
        if tag == "circle":
            cx, cy, r = (float(a[k]) for k in ("cx", "cy", "r"))
            draw.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s - 1, (cy + r) * s - 1], fill=fill)
        else:
            x, y, w, h = (float(a[k]) for k in ("x", "y", "width", "height"))
            r = float(a.get("rx", 0))
            sw = float(a.get("stroke-width", 0)) if a.get("stroke") else 0
            if sw:  # an SVG stroke is centred on the edge: outer box in the stroke colour, inner in the fill
                box(draw, x - sw / 2, y - sw / 2, w + sw, h + sw, r + sw / 2, rgba(a["stroke"]))
                box(draw, x + sw / 2, y + sw / 2, w - sw, h - sw, r - sw / 2, fill)
            else:
                box(draw, x, y, w, h, r, fill)
        img = Image.alpha_composite(img, layer)
    return img.resize((size, size), Image.BOX)


def icon(size):
    return render(ICON16 if size == 16 else ICON32 if size == 32 else MASTER, size)


def mono_boxes():
    """The one-colour drawing (22 px PNG, the theme-coloured vector icon): back and middle cards cut apart, the
    front card as an outline with its three dots. In the master's 256-unit grid: (kind, x, y, w, h, r)."""
    _, items = shapes(MASTER)
    rects = [a for t, a in items if t == "rect"]
    dots = [a for t, a in items if t == "circle"]
    back, middle, front = ([float(r[k]) for k in ("x", "y", "width", "height", "rx")] for r in rects[:3])
    gap, line = 16, 22

    def grow(b, d):
        return [b[0] - d, b[1] - d, b[2] + 2 * d, b[3] + 2 * d, b[4] + d]

    out = [("fill", back), ("clear", grow(middle, gap)), ("fill", middle), ("clear", grow(front, gap)),
           ("fill", front), ("clear", grow(front, -line))]
    out += [("dot", [float(d["cx"]), float(d["cy"]), float(d["r"]) + 3]) for d in dots]
    return out


def render_mono(size):
    s = size * SS / 256
    mask = Image.new("L", (size * SS, size * SS), 0)
    draw = ImageDraw.Draw(mask)
    for kind, b in mono_boxes():
        if kind == "dot":
            cx, cy, r = b
            draw.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s - 1, (cy + r) * s - 1], fill=255)
        else:
            x, y, w, h, r = b
            draw.rounded_rectangle([x * s, y * s, (x + w) * s - 1, (y + h) * s - 1], radius=max(r, 0) * s,
                                   fill=255 if kind == "fill" else 0)
    img = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    img.putalpha(mask)
    return img.resize((size, size), Image.BOX)


def wordmark(height, text_rgb):
    """The icon, then the name: what Helium's 140x32 "* Helium" picture is for (chrome://version)."""
    font = ImageFont.truetype(str(FONT), round(height * 0.6))
    left, top, right, bottom = font.getbbox(WORDMARK)
    gap = round(height * 0.3)
    img = Image.new("RGBA", (height + gap + (right - left) + 2, height), (0, 0, 0, 0))
    img.alpha_composite(icon(height))
    ImageDraw.Draw(img).text((height + gap - left, (height - (bottom - top)) // 2 - top), WORDMARK,
                             font=font, fill=text_rgb + (255,))
    return img


def vector_icon(color):
    """Chromium's .icon text for the in-browser logo (omnibox, menus, notifications), on the master's grid."""
    lines = ["// Copyright 2026 The Helium Authors", "// You can use, redistribute, and/or modify this source code under",
             "// the terms of the GPL-3.0 license that can be found in the LICENSE file.",
             "// Workspaces for Helium: made by local/make-branding.py from local/branding/*.svg.", "",
             "CANVAS_DIMENSIONS, 256,"]
    first = True

    def path(*cmds):
        nonlocal first
        lines.append(("" if first else "NEW_PATH,\n") + ",\n".join(cmds) + ",")
        first = False

    if color:
        _, items = shapes(MASTER)
        for tag, a in items:
            op = float(a.get("fill-opacity", 1))
            if tag == "circle":
                path(argb(a["fill"], op), f"CIRCLE, {a['cx']}, {a['cy']}, {a['r']}")
                continue
            x, y, w, h, r = (float(a[k]) for k in ("x", "y", "width", "height", "rx"))
            sw = float(a.get("stroke-width", 0)) if a.get("stroke") else 0
            if sw:
                path(argb(a["stroke"]), f"ROUND_RECT, {x - sw / 2:g}, {y - sw / 2:g}, {w + sw:g}, {h + sw:g}, {r + sw / 2:g}")
                x, y, w, h, r = x + sw / 2, y + sw / 2, w - sw, h - sw, r - sw / 2
            path(argb(a["fill"], op), f"ROUND_RECT, {x:g}, {y:g}, {w:g}, {h:g}, {r:g}")
    else:
        for kind, b in mono_boxes():
            if kind == "dot":
                path("CIRCLE, {:g}, {:g}, {:g}".format(*b))
            else:
                cmd = "ROUND_RECT, {:g}, {:g}, {:g}, {:g}, {:g}".format(*b)
                path(*(["PATH_MODE_CLEAR", cmd] if kind == "clear" else [cmd]))
    return "\n".join(lines) + "\n"


def main():
    (OUT / "app_icon").mkdir(parents=True, exist_ok=True)
    render(MASTER, 1024).save(OUT / "app_icon" / "raw.png", optimize=True)
    render(MASTER, 512).save(OUT / "app_icon" / "file.png", optimize=True)  # documents use the app icon
    icon(32).save(OUT / "app_icon" / "raw_32.png", optimize=True)
    icon(16).save(OUT / "app_icon" / "raw_16.png", optimize=True)
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    frames = [icon(n) for n in sizes]
    frames[-1].save(OUT / "app_icon" / "app.ico", format="ICO", sizes=[(n, n) for n in sizes], append_images=frames[:-1])
    wordmark(32, (0, 0, 0)).save(OUT / "product_logo.png", optimize=True)
    wordmark(64, (0, 0, 0)).save(OUT / "product_logo_200.png", optimize=True)
    wordmark(32, (255, 255, 255)).save(OUT / "product_logo_white.png", optimize=True)
    wordmark(64, (255, 255, 255)).save(OUT / "product_logo_white_200.png", optimize=True)
    render_mono(22).save(OUT / "product_logo_22_mono.png", optimize=True)
    shutil.copyfile(MASTER, OUT / "product_logo.svg")
    (OUT / "product_logo.icon").write_text(vector_icon(False), encoding="utf-8", newline="\n")
    (OUT / "product_logo_color.icon").write_text(vector_icon(True), encoding="utf-8", newline="\n")
    print("wrote", sorted(str(p.relative_to(OUT)) for p in OUT.rglob("*") if p.is_file()))

    if "--apply" in sys.argv:
        tree = pathlib.Path(sys.argv[sys.argv.index("--apply") + 1])
        sys.path.insert(0, str(REPO / "utils"))
        import generate_resources, replace_resources  # Helium's own resource step
        generate_resources.generate_resources(REPO / "resources" / "generate_resources.txt", REPO / "resources")
        replace_resources.copy_resources(REPO / "resources" / "helium_resources.txt", REPO / "resources", tree)
        print("copied into", tree)


if __name__ == "__main__":
    main()
