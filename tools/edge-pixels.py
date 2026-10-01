#!/usr/bin/env python3
"""Reads an Android screenshot (screencap -p PNG) and says whether the Uposatha app really runs
edge to edge (dg-apps#41): the page reaches the very first and last row of the screen, the status
bar sits ON the page (nothing navy/foreign is painted round it), and the page text starts below the
status bar rather than behind it.

    python3 tools/edge-pixels.py shot.png light|dark <output.json>

Writes the measurements as JSON (also printed, one "key=value" per line, so a shell can grep it):
    top_color, bottom_color, page_bg, frame_top, frame_bottom, text_top, text_color, verdict
where "frame_*" is the thickness of a band at that edge whose colour is neither the page's own
background nor the launcher's, i.e. a painted strip ("борода"); "text_top" is the first row with
enough dark/light contrast to be a glyph of the page's top bar.
"""
import json
import sys

from PIL import Image


def dominant(pixels):
    """The most common colour, quantised to 8 levels a channel (anti-aliasing and JPEG-ish noise)."""
    counts = {}
    for p in pixels:
        k = (p[0] >> 3, p[1] >> 3, p[2] >> 3, p[3] if len(p) > 3 else 255)
        counts[k] = counts.get(k, 0) + 1
    k = max(counts, key=counts.get)
    return (k[0] << 3, k[1] << 3, k[2] << 3)


def near(a, b, tol=24):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) <= tol


def main():
    path, theme, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    img = Image.open(path).convert("RGBA")
    w, h = img.width, img.height
    px = img.load()

    top = dominant([px[x, 1] for x in range(0, w, 4)])
    bottom = dominant([px[x, h - 2] for x in range(0, w, 4)])
    # The page's own background, sampled well inside the page (under the top bar, over the body).
    page_bg = dominant([px[x, y] for x in range(0, w, 4) for y in range(int(h * 0.45), int(h * 0.55), 3)])
    dark_page = sum(page_bg[:3]) < 384

    # A painted strip ("борода"): a flat band of rows at an edge in a colour that is NOT the page's
    # own background — the window background showing through, which is what the DgBars plugin and the
    # navy @color/dg_navbar were for. A flat band that IS the page's background is the page itself
    # (an empty top area of a dark theme), so it does not count.
    def strip(edge_y, step):
        edge = dominant([px[x, edge_y] for x in range(0, w, 4)])
        if near(edge, page_bg, 32):
            return 0
        n = 0
        y = edge_y
        while 0 <= y < h and all(near(px[x, y], edge, 12) for x in range(0, w, 8)):
            n += 1
            y += step
            if n >= 80:
                break
        return n

    frame_top = strip(0, 1)
    frame_bottom = strip(h - 1, -1)

    # The first row of page text: the top bar's dark (light theme) or light (dark theme) glyphs.
    text_top = None
    for y in range(0, min(400, h)):
        row = [px[x, y] for x in range(0, w, 2)]
        ink = sum(1 for p in row if (p[0] < 110 if not dark_page else p[0] > 200))
        if ink >= max(6, w // 60):
            text_top = y
            break

    verdict = {
        # Edge to edge: the page reaches the screen's own edges (no flat painted band there) AND the
        # very first row of the screen is the page's own background, not another colour of the app.
        "edge_to_edge": frame_top == 0 and frame_bottom == 0 and near(top, page_bg, 32),
        "frame_top": frame_top,
        "frame_bottom": frame_bottom,
        "top_color": "#%02x%02x%02x" % top[:3],
        "bottom_color": "#%02x%02x%02x" % bottom[:3],
        "page_bg": "#%02x%02x%02x" % page_bg[:3],
        "top_matches_page": near(top, page_bg, 32),
        "bottom_matches_page": near(bottom, page_bg, 32),
        "text_top": text_top,
        "theme": theme,
        "size": [w, h],
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(verdict, f, indent=2)
    print(json.dumps(verdict))
    for k in ("edge_to_edge", "frame_top", "frame_bottom", "top_color", "bottom_color", "page_bg", "top_matches_page", "bottom_matches_page", "text_top"):
        print(f"{k}={verdict[k]}")


if __name__ == "__main__":
    main()
