#!/usr/bin/env python3
"""Draws the iOS app's icon and launch image (run from uposatha/): the mark of the Android launcher icon (moon behind clouds).

  ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png   1024x1024, the mark on the navy plate, no transparency (App Store rule)
  ios/App/App/Assets.xcassets/Splash.imageset/splash-{light,dark}.png  the mark, centred, on the launch screen's plain page colour
"""
import importlib.util, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('moon_icons', os.path.join(HERE, 'moon-icons.py'))
mi = importlib.util.module_from_spec(spec); spec.loader.exec_module(mi)

ASSETS = os.path.join(HERE, '..', 'ios', 'App', 'App', 'Assets.xcassets')


def mark(px, moon, cloud):
    mi.MOON, mi.CLOUD = moon, cloud
    return mi.launcher(4, px, False)        # the full moon: 108-unit adaptive canvas, the mark 56% wide, centred


def icon():
    plate = Image.new('RGBA', (1024, 1024), mi.PLATE + (255,))
    plate.alpha_composite(mark(1024, (223, 232, 240), (159, 179, 198)))
    plate.convert('RGB').save(os.path.join(ASSETS, 'AppIcon.appiconset', 'AppIcon-512@2x.png'))


def splash(name, page, moon, cloud):
    S = 2732
    bg = Image.new('RGBA', (S, S), page + (255,))
    m = mark(1100, moon, cloud)
    bg.alpha_composite(m, ((S - m.width) // 2, (S - m.height) // 2))
    bg.convert('RGB').save(os.path.join(ASSETS, 'Splash.imageset', name))


if __name__ == '__main__':
    icon()
    splash('splash-light.png', (255, 255, 255), (47, 74, 99), (110, 113, 106))     # the page's light colours (dg_splash_art.xml)
    splash('splash-dark.png', (17, 17, 17), (169, 196, 220), (124, 124, 124))       # ...and dark
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
