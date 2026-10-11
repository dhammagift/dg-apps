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

    # The page's own background. Sampled from the top three rows of the window, above the status
    # bar's own icons: it is the surface the page is painted on (and the colour the transparent
    # status bar shows, which is what this whole check is about). A card further down is NOT it —
    # sampling the middle of the screen took a card for the background in runs 19 and 20 and
    # turned the page itself into a "painted strip".
    page_bg = dominant([px[x, y] for y in range(0, 3) for x in range(0, w, 4)])
    dark_page = sum(page_bg[:3]) < 384
    top = dominant([px[x, 1] for x in range(0, w, 4)])
    bottom = dominant([px[x, h - 2] for x in range(0, w, 4)])
    # A painted strip ("борода"): a flat band of rows at an edge in a colour that is NOT the page's
    # own background — the window background showing through, which is what the DgBars plugin and the
    # navy @color/dg_navbar were for. A flat band that IS the page's background is the page itself
    # (an empty top area of a dark theme), so it does not count.
    def strip(edge_y, step, vertical=True):
        edge = dominant([px[x, edge_y] for x in range(0, w, 4)]) if vertical else dominant([px[edge_y, y] for y in range(0, h, 4)])
        if near(edge, page_bg, 32):
            return 0
        n = 0
        y = edge_y
        while 0 <= y < (h if vertical else w) and all(
                near((px[x, y] if vertical else px[y, x]), edge, 12) for x in range(0, (w if vertical else h), 8)):
            n += 1
            y += step
            if n >= 80:
                break
        return n

    frame_top = strip(0, 1)
    frame_bottom = strip(h - 1, -1)
    # Landscape: the camera cutout is on a side, so the left/right edges matter as much.
    frame_left = strip(0, 1, vertical=False)
    frame_right = strip(w - 1, -1, vertical=False)

    # The page's own content: any pixel in the body that is not the page background. A blank page
    # (the WebView before its first paint) would satisfy every edge test, so it is asked about first.
    ink = 0
    total = 0
    for y in range(int(h * 0.08), int(h * 0.92), 6):
        for x in range(0, w, 6):
            total += 1
            if not near(px[x, y], page_bg, 32):
                ink += 1
    ink_ratio = ink / max(1, total)
    empty_page = ink_ratio < 0.005
    # The same, against the body's OWN dominant colour: page_bg is the top rows, which on an app that is not
    # edge to edge are the system bar (#101010), and then a blank white WebView is 100% "ink" (run 562: the
    # dictionary passed "painted" on its bare window background). A flat body is 0 here whatever its colour.
    body = [px[x, y] for y in range(int(h * 0.08), int(h * 0.92), 6) for x in range(0, w, 6)]
    body_bg = dominant(body)
    body_ink = sum(1 for p in body if not near(p, body_bg, 32)) / max(1, len(body))

    # The status bar's own height: the fixed inset Android reserves for it, which is also what the
    # page gets as env(safe-area-inset-top) (~51 px of a 2400 px screen). The window manager's value
    # is the authority; this is the layout one for when there is none, and it only decides WHERE the
    # status bar is, never passes or fails anything by itself (the caller's own checks do that).
    def ink_row(y, step=4):
        row = [px[x, y] for x in range(0, w, step)]
        return sum(1 for p in row if not near(p, page_bg, 32))

    status_rows = int(round(h * 0.024))   # 58 px of 2400: the status bar and its glyphs

    # The first row of the page's own text (the top bar), for the record: ink on the page's own
    # background, below the status bar's area.
    def ink_count(y):
        row = [px[x, y] for x in range(0, w)]
        return sum(1 for p in row if (p[0] < 110 if not dark_page else p[0] > 200))

    text_top = None
    for y in range(status_rows, min(status_rows + 400, h)):
        if ink_count(y) > 8:
            text_top = y
            break

    # The status bar's own furniture on a modern iPhone: the Dynamic Island (or the notch) is a
    # solid black blob at the top centre. Detected by its continuous run (a title's letters are
    # separate glyphs, so they never form one). Everything the PAGE draws must start below it —
    # this is the check for the failure run 444 showed: the page's own top bar under the clock and
    # the island. On a device without a cutout (this Android emulator) nothing is detected and the
    # rule is skipped; there the status bar is an inset the page pads around.
    blob_bottom = None
    blob_x = (0, 0)
    for y in range(0, int(h * 0.15)):
        best = 0
        best_run = (0, 0)
        run = 0
        start = 0
        for x in range(0, w):
            if sum(px[x, y][:3]) < 40:
                if run == 0:
                    start = x
                run += 1
                if run > best:
                    best = run
                    best_run = (start, x)
            else:
                run = 0
        if best > 0.12 * w:
            blob_bottom = y
            blob_x = best_run
    # The page's own ink outside the cutout's columns, in rows wide enough to be a bar rather than
    # the clock's few digits.
    page_text_top = None
    if blob_bottom is not None:
        for y in range(0, min(blob_bottom + int(h * 0.08), h)):
            row = [px[x, y] for x in range(0, w, 3)
                   if not (blob_x[0] - 8 <= x <= blob_x[1] + 8)]
            wide = sum(1 for p in row if not near(p, page_bg, 32) and sum(p[:3]) > 60)
            if wide > (w / 3) * 0.10:
                page_text_top = y
                break
    page_clear_of_status = True if blob_bottom is None else (page_text_top is None or page_text_top >= blob_bottom + 10)

    verdict = {
        # Edge to edge: the page reaches the screen's own edges (no flat painted band there) AND the
        # very first row of the screen is the page's own background, not another colour of the app.
        "edge_to_edge": frame_top == 0 and frame_bottom == 0 and near(top, page_bg, 32),
        "frame_top": frame_top,
        "frame_bottom": frame_bottom,
        "frame_left": frame_left,
        "frame_right": frame_right,
        "landscape": w > h,
        "top_color": "#%02x%02x%02x" % top[:3],
        "bottom_color": "#%02x%02x%02x" % bottom[:3],
        "page_bg": "#%02x%02x%02x" % page_bg[:3],
        "top_matches_page": near(top, page_bg, 32),
        # How uniform the screen's first rows are: page content (a heading, a search field) would
        # break the page background up; the transparent status bar shows nothing but its own icons.
        "top_row_uniform": all(near(px[x, y], top, 48) for y in range(0, max(2, status_rows // 3)) for x in range(0, w, 6)),
        "bottom_matches_page": near(bottom, page_bg, 32),
        "text_top": text_top,
        "status_rows": status_rows,
        "empty_page": empty_page,
        "ink_ratio": round(ink_ratio, 5),
        "body_bg": "#%02x%02x%02x" % body_bg[:3],
        "body_ink": round(body_ink, 5),
        "cutout_bottom": blob_bottom,
        "page_text_top": page_text_top,
        "page_clear_of_status": page_clear_of_status,
        "theme": theme,
        "size": [w, h],
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(verdict, f, indent=2)
    print(json.dumps(verdict))
    for k in ("edge_to_edge", "frame_top", "frame_bottom", "top_color", "bottom_color", "page_bg",
              "top_matches_page", "bottom_matches_page", "frame_left", "frame_right", "text_top", "status_rows",
              "empty_page", "ink_ratio", "body_ink", "top_row_uniform", "cutout_bottom", "page_text_top", "page_clear_of_status"):
        print(f"{k}={verdict[k]}")


if __name__ == "__main__":
    main()
