#!/usr/bin/env python3
"""The Uposatha PWA as a Windows package (MSIX) with its widgets, built by Microsoft's PWABuilder service.

Windows shows a widget only when a PACKAGE declares it (AppExtension com.microsoft.windows.widgets): a PWA installed from the browser
has no package, so its widgets never reach the Widgets Board (dg-apps#65). PWABuilder wraps the site's address into a package and
writes the three widgets of the site's manifest into it; nothing of ours is compiled.

  windows-package.py <out.zip> <package id> <publisher CN=...> <publisher display name> [version] [origin]

The three identity values are the app's own in Partner Center (Product identity: Package/Identity/Name, Package/Identity/Publisher,
Package/Properties/PublisherDisplayName). The zip holds *.msixbundle (for the Store) and *.sideload.msix + utils/pwainstaller.exe
(to try it on a machine with Developer Mode: the probe uposatha/test/windows/widget-board.ps1 installs it and pins the widgets).
For a try-out any identity works, e.g. DhammaGift.UposathaTest "CN=3a54a224-05dd-42aa-85bd-3f3c1478fdca" "Dhamma.Gift".
"""
import json, sys, urllib.request

SERVICE = "https://pwabuilder-windows-docker.azurewebsites.net/msix/generatezip"   # PWABuilder's own (its site calls the same)

def main():
    if len(sys.argv) < 5:
        sys.exit(__doc__)
    out, package_id, publisher, display = sys.argv[1:5]
    version = sys.argv[5] if len(sys.argv) > 5 else "1.0.1"
    origin = (sys.argv[6] if len(sys.argv) > 6 else "https://dhamma.gift").rstrip("/")
    manifest_url = origin + "/uposatha-calendar.webmanifest"
    manifest = json.load(urllib.request.urlopen(manifest_url, timeout=30))
    if not manifest.get("widgets"):
        sys.exit("the manifest at %s declares no widgets" % manifest_url)
    url = origin + manifest.get("start_url", "/uposatha-calendar")
    options = {
        "name": "Uposatha by the Suttas", "packageId": package_id, "url": url, "version": version, "allowSigning": True,
        "publisher": {"displayName": display, "commonName": publisher},
        "generateModernPackage": True, "classicPackage": {"generate": False, "version": "1.0.0", "url": url},
        "edgeHtmlPackage": {"generate": False}, "manifestUrl": manifest_url, "manifest": manifest,
        "images": {"baseImage": origin + "/assets/img/uposatha-512.png", "backgroundColor": "transparent", "padding": 0.0},
        "resourceLanguage": "EN-US", "targetDeviceFamilies": ["Desktop"],
        "enableWebAppWidgets": True,   # the widgets of the manifest go into the package, one bundle per processor
    }
    req = urllib.request.Request(SERVICE, data=json.dumps(options).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=300) as r:
        body = r.read()
    if body[:2] != b"PK":
        sys.exit("PWABuilder answered something that is not a zip: " + body[:300].decode(errors="replace"))
    open(out, "wb").write(body)
    print("%s: %d bytes, %d widgets (%s), opens %s" % (out, len(body), len(manifest["widgets"]), ", ".join(w["tag"] for w in manifest["widgets"]), url))

if __name__ == "__main__":
    main()
