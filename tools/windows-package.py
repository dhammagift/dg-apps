#!/usr/bin/env python3
"""A PWA of ours as a Windows package (MSIX) for the Microsoft Store, built by Microsoft's PWABuilder service.

PWABuilder wraps the site's address into a package (nothing of ours is compiled): the app is the site in its own window and
changes with the site. The package is rebuilt only when what is written INTO it changes: the name, the icon, the start address,
the list of widgets.

Uposatha: Windows shows a widget only when a PACKAGE declares it (AppExtension com.microsoft.windows.widgets); a PWA installed
from the browser has no package, so its widgets never reach the Widgets Board (dg-apps#65). The three widgets of the site's
manifest are written into the package.

  windows-package.py <app: uposatha | dg | dict> <out.zip> <package id> <publisher CN=...> <publisher display name> [version] [origin]

The three identity values are the app's own in Partner Center (Product identity: Package/Identity/Name, Package/Identity/Publisher,
Package/Properties/PublisherDisplayName). The zip holds *.msixbundle (for the Store) and *.sideload.msix + utils/pwainstaller.exe
(to try it on a machine with Developer Mode: the probe uposatha/test/windows/widget-board.ps1 installs it and pins the widgets).
For a try-out any identity works, e.g. DhammaGift.UposathaTest "CN=3a54a224-05dd-42aa-85bd-3f3c1478fdca" "Dhamma.Gift".
"""
import json, sys, urllib.request

SERVICE = "https://pwabuilder-windows-docker.azurewebsites.net/msix/generatezip"   # PWABuilder's own (its site calls the same)

# name in the Store / the site / its manifest / its icon (512 px) / the start address when the manifest names none
APPS = {
    "uposatha": ("Uposatha by the Suttas", "https://dhamma.gift", "/uposatha-calendar.webmanifest", "/assets/img/uposatha-512.png", "/uposatha-calendar"),
    "dg": ("Dhamma.Gift", "https://dhamma.gift", "/manifest.json", "/assets/img/pwa-bold-monocolor-512.png", "/"),
    "dict": ("Dict.Dhamma.Gift", "https://dict.dhamma.gift", "/static/manifest.json", "/static/icon-512.png", "/"),
}

def main():
    if len(sys.argv) < 6 or sys.argv[1] not in APPS:
        sys.exit(__doc__)
    name, site, manifest_path, icon, start = APPS[sys.argv[1]]
    out, package_id, publisher, display = sys.argv[2:6]
    version = sys.argv[6] if len(sys.argv) > 6 else "1.0.1"
    origin = (sys.argv[7] if len(sys.argv) > 7 else site).rstrip("/")
    manifest_url = origin + manifest_path
    manifest = json.load(urllib.request.urlopen(manifest_url, timeout=30))
    widgets = manifest.get("widgets") or []
    if sys.argv[1] == "uposatha" and not widgets:
        sys.exit("the manifest at %s declares no widgets" % manifest_url)
    url = origin + manifest.get("start_url", start)
    options = {
        "name": name, "packageId": package_id, "url": url, "version": version, "allowSigning": True,
        "publisher": {"displayName": display, "commonName": publisher},
        "generateModernPackage": True, "classicPackage": {"generate": False, "version": "1.0.0", "url": url},
        "edgeHtmlPackage": {"generate": False}, "manifestUrl": manifest_url, "manifest": manifest,
        "images": {"baseImage": origin + icon, "backgroundColor": "transparent", "padding": 0.0},
        "resourceLanguage": "EN-US", "targetDeviceFamilies": ["Desktop"],
        "enableWebAppWidgets": bool(widgets),   # the widgets of the manifest go into the package, one bundle per processor
    }
    req = urllib.request.Request(SERVICE, data=json.dumps(options).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        body = r.read()
    if body[:2] != b"PK":
        sys.exit("PWABuilder answered something that is not a zip: " + body[:300].decode(errors="replace"))
    open(out, "wb").write(body)
    print("%s: %d bytes, %d widgets (%s), opens %s" % (out, len(body), len(widgets), ", ".join(w["tag"] for w in widgets), url))

if __name__ == "__main__":
    main()
