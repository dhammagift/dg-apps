#!/usr/bin/env python3
"""Draws the iOS app's icon and launch image (run from dict/): the dictionary's mark (hook, stair, dot, underline —
the same geometry as src/launch-screens.js's DICT_SVG), matching the Android launcher (res/values/ic_launcher_background.xml).

  ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png   1024x1024, the mark on the dark plate, no transparency
  ios/App/App/Assets.xcassets/Splash.imageset/splash-{light,dark}.png  the mark, centred, on the launch screen's page colour
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'ios', 'App', 'App', 'Assets.xcassets')

# The mark's own geometry (src/launch-screens.js, DICT_SVG), a viewBox of x 240..900, y 262..852.
HOOK = [(410, 381), (282, 381), (282, 600)]                                  # plus a curve to (462, 612), approximated below
STAIR = [(608, 690), (608, 545), (738, 545), (738, 380), (855, 380), (855, 292)]
DOT = (608, 712, 38)
UNDERLINE = [(258, 822), (879, 822)]
STROKE = 48
VB = (240, 262, 900, 852)   # x0, y0, x1, y1


def hook_points():
    # The curved foot of the hook (a cubic Bezier in the source SVG) sampled as a polyline: C282,690 330,721 372,721
    # then C420,721 462,690 462,612 — two cubic segments from (282,600) to (462,612).
    def cubic(p0, p1, p2, p3, n=24):
        pts = []
        for i in range(n + 1):
            t = i / n
            x = (1 - t) ** 3 * p0[0] + 3 * (1 - t) ** 2 * t * p1[0] + 3 * (1 - t) * t ** 2 * p2[0] + t ** 3 * p3[0]
            y = (1 - t) ** 3 * p0[1] + 3 * (1 - t) ** 2 * t * p1[1] + 3 * (1 - t) * t ** 2 * p2[1] + t ** 3 * p3[1]
            pts.append((x, y))
        return pts
    pts = list(HOOK)
    pts += cubic((282, 600), (282, 690), (330, 721), (372, 721))[1:]
    pts += cubic((372, 721), (420, 721), (462, 690), (462, 612))[1:]
    return pts


def draw_mark(size, mark_color, underline_color, fill=0.62):
    """The mark alone, scaled to fill `fill` of a size x size canvas, transparent background."""
    SS = 4
    px = size * SS
    scale = px * fill / max(VB[2] - VB[0], VB[3] - VB[1])
    cx0 = (VB[0] + VB[2]) / 2
    cy0 = (VB[1] + VB[3]) / 2
    ox, oy = px / 2 - cx0 * scale, px / 2 - cy0 * scale

    def tx(pts):
        return [(ox + x * scale, oy + y * scale) for x, y in pts]

    img = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = STROKE * scale
    for pts, col, sw in ((hook_points(), mark_color, w), (STAIR, mark_color, w), (UNDERLINE, underline_color, 22 * scale)):
        p = tx(pts)
        d.line(p, fill=col + (255,), width=int(round(sw)), joint='curve')
        for pt in (p[0], p[-1]):
            r = sw / 2
            d.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=col + (255,))
    dx, dy, dr = DOT
    dx, dy, dr = ox + dx * scale, oy + dy * scale, dr * scale
    d.ellipse([dx - dr, dy - dr, dx + dr, dy + dr], fill=mark_color + (255,))
    return img.resize((size, size), Image.LANCZOS)


def icon():
    plate = Image.new('RGBA', (1024, 1024), (17, 17, 17, 255))
    plate.alpha_composite(draw_mark(1024, (221, 221, 221), (22, 179, 148), fill=0.60))
    plate.convert('RGB').save(os.path.join(ASSETS, 'AppIcon.appiconset', 'AppIcon-512@2x.png'))


def splash(name, page, mark, underline):
    S = 2732
    bg = Image.new('RGBA', (S, S), page + (255,))
    m = draw_mark(1100, mark, underline, fill=0.62)
    bg.alpha_composite(m, ((S - m.width) // 2, (S - m.height) // 2))
    bg.convert('RGB').save(os.path.join(ASSETS, 'Splash.imageset', name))


if __name__ == '__main__':
    icon()
    splash('splash-light.png', (255, 255, 255), (27, 29, 25), (20, 156, 124))    # dg_splash_ink light + teal
    splash('splash-dark.png', (17, 17, 17), (221, 221, 221), (22, 179, 148))     # dg_splash_ink dark + teal
    d = os.path.join(ASSETS, 'Splash.imageset')
    for old in ('splash-2732x2732.png', 'splash-2732x2732-1.png', 'splash-2732x2732-2.png'):
        if os.path.exists(os.path.join(d, old)): os.remove(os.path.join(d, old))
    open(os.path.join(d, 'Contents.json'), 'w').write('''{
  "images" : [
    { "idiom" : "universal", "filename" : "splash-light.png" },
    { "idiom" : "universal", "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "splash-dark.png" }
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
''')
    print('ok')
