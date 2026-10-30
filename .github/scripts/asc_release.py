#!/usr/bin/env python3
"""App Store Connect, one step at a time, for one app's version waiting for (or in) review. Run by asc-release.yml with the
ASC key from the GitHub secrets; every step prints what it found and what it did, and changes nothing it does not name.

  asc_release.py <bundle id> status                 the version, its state, its build, the review submission, the texts
  asc_release.py <bundle id> cancel                 take the version out of review (the submission is cancelled)
  asc_release.py <bundle id> set-build <number>     attach that processed build to the version
  asc_release.py <bundle id> set-text <json file>   update the version's texts: {"en-US": {"description": ..,
                                                    "promotionalText": .., "keywords": .., "whatsNew": ..}, "ru": {..}}
  asc_release.py <bundle id> set-version <x.y.z>    rename the version (a rejected 0.6.1 goes back as 0.6.2)
  asc_release.py <bundle id> submit                 send the version for review (again, after a rejection)
  asc_release.py <bundle id> screens [dir]          (read only) the version's screenshots per language and display type,
                                                    each downloaded into dir (default screens/) to be looked at
  asc_release.py <bundle id> beta "<n>|<text>"     TestFlight build n to the external groups and to Apple's beta review, with
                                                    <text> as its "What to Test" (en-US)
  asc_release.py <bundle id> testflight             (read only) the TestFlight groups: public link, its limit, testers,
                                                    which builds each group has and whether Apple let them out to testers
"""
import json, os, sys, time, urllib.error, urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
PLATFORM = os.environ.get("ASC_PLATFORM", "IOS")  # MAC_OS for the Safari extension
TOKEN = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                    "aud": "appstoreconnect-v1"}, os.environ["ASC_KEY_P8"], algorithm="ES256",
                   headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path}: HTTP {e.code}: {e.read().decode()[:800]}")


def app_id(bundle):
    data = call("GET", f"/v1/apps?filter[bundleId]={bundle}&limit=1")["data"]
    if not data:
        sys.exit("no app with bundle id " + bundle)
    return data[0]["id"]


def editable_version(aid):
    """The newest version (iOS, or macOS for Safari) that is not on sale yet (the one being prepared or reviewed)."""
    for v in call("GET", f"/v1/apps/{aid}/appStoreVersions?filter[platform]={PLATFORM}&limit=10")["data"]:
        if v["attributes"]["appStoreState"] != "READY_FOR_SALE":
            return v
    sys.exit(f"no {PLATFORM} version that is not on sale")


def submissions(aid):
    return call("GET", f"/v1/reviewSubmissions?filter[app]={aid}&filter[platform]={PLATFORM}&limit=10")["data"]


def status(bundle):
    aid = app_id(bundle)
    v = editable_version(aid)
    a = v["attributes"]
    print(f"version {a['versionString']} ({v['id']}): appStoreState={a['appStoreState']} appVersionState={a.get('appVersionState')}")
    b = call("GET", f"/v1/appStoreVersions/{v['id']}/build").get("data")
    ba = (b or {}).get("attributes", {})
    print("build:", ba.get("version", "none"), "processing=%s encryption=%s" % (ba.get("processingState"), ba.get("usesNonExemptEncryption")))
    for s in submissions(aid):
        print(f"review submission {s['id']}: state={s['attributes'].get('state')} submitted={s['attributes'].get('submittedDate')}")
        for it in call("GET", f"/v1/reviewSubmissions/{s['id']}/items?include=appStoreVersion").get("data", []):
            print(f"  item {it['id']}: state={it['attributes'].get('state')} version={(it['relationships'].get('appStoreVersion', {}).get('data') or {}).get('id')}")
    for loc in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
        la = loc["attributes"]
        print(f"--- {la['locale']} ({loc['id']})")
        for k in ("promotionalText", "keywords", "whatsNew", "description"):
            print(f"  {k}: {la.get(k)!r}")


def cancel(bundle):
    aid = app_id(bundle)
    live = [s for s in submissions(aid) if s["attributes"].get("state") in ("WAITING_FOR_REVIEW", "IN_REVIEW", "READY_FOR_REVIEW")]
    if not live:
        print("nothing in review to cancel")
        return
    for s in live:
        call("PATCH", f"/v1/reviewSubmissions/{s['id']}",
             {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}})
        print(f"cancelled review submission {s['id']} (was {s['attributes'].get('state')})")


def set_build(bundle, number):
    aid = app_id(bundle)
    v = editable_version(aid)
    builds = call("GET", f"/v1/builds?filter[app]={aid}&filter[version]={number}&limit=5")["data"]
    ok = [b for b in builds if b["attributes"].get("processingState") == "VALID"]
    if not ok:
        sys.exit(f"build {number}: not found or not processed yet ({[b['attributes'].get('processingState') for b in builds]})")
    call("PATCH", f"/v1/appStoreVersions/{v['id']}/relationships/build", {"data": {"type": "builds", "id": ok[0]["id"]}})
    print(f"version {v['attributes']['versionString']}: build {number} attached")
    # Export compliance: a build without the answer (no ITSAppUsesNonExemptEncryption in its Info.plist, the Safari extension)
    # keeps the version "not ready to be submitted". Only HTTPS here, the exempt case.
    if ok[0]["attributes"].get("usesNonExemptEncryption") is None:
        call("PATCH", f"/v1/builds/{ok[0]['id']}", {"data": {"type": "builds", "id": ok[0]["id"], "attributes": {"usesNonExemptEncryption": False}}})
        print(f"build {number}: export compliance set (no non-exempt encryption)")


def set_text(bundle, path):
    aid = app_id(bundle)
    v = editable_version(aid)
    want = json.load(open(path))
    locs = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]}
    for locale, fields in want.items():
        if locale == "play":
            continue
        fields = {k: v2 for k, v2 in fields.items() if v2 is not None}
        if locale in locs:
            call("PATCH", f"/v1/appStoreVersionLocalizations/{locs[locale]['id']}",
                 {"data": {"type": "appStoreVersionLocalizations", "id": locs[locale]["id"], "attributes": fields}})
            print(f"{locale}: updated {sorted(fields)}")
        else:
            call("POST", "/v1/appStoreVersionLocalizations",
                 {"data": {"type": "appStoreVersionLocalizations", "attributes": {"locale": locale, **fields},
                           "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
            print(f"{locale}: created with {sorted(fields)}")


def delete_locale(bundle, locale):
    v = editable_version(app_id(bundle))
    for l in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
        if l["attributes"]["locale"] == locale:
            call("DELETE", f"/v1/appStoreVersionLocalizations/{l['id']}")
            print(f"{locale}: localization removed")
            return
    print(f"{locale}: no such localization")


def testflight(bundle):
    """The external TestFlight groups and the builds each one can install (newest first), with each build's beta review state."""
    aid = app_id(bundle)
    groups = call("GET", f"/v1/apps/{aid}/betaGroups?limit=50")["data"]
    for g in groups:
        ga = g["attributes"]
        if ga.get("isInternalGroup"):
            continue
        print(f"group {ga['name']!r}: public link {'on' if ga.get('publicLinkEnabled') else 'off'} {ga.get('publicLink') or ''}")
        builds = call("GET", f"/v1/betaGroups/{g['id']}/builds?limit=10&sort=-uploadedDate"
                             "&include=preReleaseVersion,buildBetaDetail&fields[preReleaseVersions]=version")
        inc = {(i["type"], i["id"]): i["attributes"] for i in builds.get("included", [])}
        for b in builds["data"]:
            ba, rel = b["attributes"], b["relationships"]
            ver = inc.get(("preReleaseVersions", (rel["preReleaseVersion"]["data"] or {}).get("id")), {}).get("version", "?")
            det = inc.get(("buildBetaDetails", (rel["buildBetaDetail"]["data"] or {}).get("id")), {})
            print(f"  {ver} ({ba['version']}) uploaded {ba['uploadedDate'][:10]} expired={ba.get('expired')} "
                  f"external={det.get('externalBuildState')}")
    if not any(not g["attributes"].get("isInternalGroup") for g in groups):
        print("no external groups")


def set_version(bundle, name):
    v = editable_version(app_id(bundle))
    call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"versionString": name}}})
    print(f"version {v['attributes']['versionString']} renamed to {name}")


def submit(bundle):
    aid = app_id(bundle)
    v = editable_version(aid)
    # A rejected version stays in its submission (UNRESOLVED_ISSUES): that one is sent again, a new one would be refused.
    old = [s for s in submissions(aid) if s["attributes"].get("state") == "UNRESOLVED_ISSUES"]
    if old:
        # Its rejected item is marked as dealt with first, or the version reads "not ready to be submitted".
        for it in call("GET", f"/v1/reviewSubmissions/{old[0]['id']}/items").get("data", []):
            if it["attributes"].get("state") == "REJECTED":
                call("PATCH", f"/v1/reviewSubmissionItems/{it['id']}",
                     {"data": {"type": "reviewSubmissionItems", "id": it["id"], "attributes": {"resolved": True}}})
                print(f"item {it['id']}: marked resolved")
        call("PATCH", f"/v1/reviewSubmissions/{old[0]['id']}",
             {"data": {"type": "reviewSubmissions", "id": old[0]["id"], "attributes": {"submitted": True}}})
        print(f"version {v['attributes']['versionString']} sent for review again (submission {old[0]['id']})")
        return
    sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": PLATFORM},
                                                          "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
    call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    call("PATCH", f"/v1/reviewSubmissions/{sub['id']}",
         {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print(f"version {v['attributes']['versionString']} submitted for review (submission {sub['id']})")


def beta(bundle, arg):
    number, _, text = arg.partition("|")
    aid = app_id(bundle)
    builds = call("GET", f"/v1/builds?filter[app]={aid}&filter[version]={number}&limit=5")["data"]
    ok = [b for b in builds if b["attributes"].get("processingState") == "VALID"]
    if not ok:
        sys.exit(f"build {number}: not found or not processed yet")
    bid = ok[0]["id"]
    if text:
        loc = [l for l in call("GET", f"/v1/builds/{bid}/betaBuildLocalizations")["data"] if l["attributes"].get("locale") == "en-US"]
        if loc:
            call("PATCH", f"/v1/betaBuildLocalizations/{loc[0]['id']}",
                 {"data": {"type": "betaBuildLocalizations", "id": loc[0]["id"], "attributes": {"whatsNew": text}}})
        else:
            call("POST", "/v1/betaBuildLocalizations", {"data": {"type": "betaBuildLocalizations",
                 "attributes": {"locale": "en-US", "whatsNew": text}, "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print(f"build {number}: What to Test set")
    for g in call("GET", f"/v1/betaGroups?filter[app]={aid}&limit=50")["data"]:
        if not g["attributes"].get("isInternalGroup"):
            call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
            print(f"build {number}: added to group {g['attributes'].get('name')!r}")
    call("POST", "/v1/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions",
         "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print(f"build {number}: sent to Apple's beta review")


def certs():
    """Read only: when the account's signing certificates and provisioning profiles expire (owner 2026-10-30: the
    deadlines that break a build without warning). Sorted by date; the soonest first."""
    rows = []
    for c in call("GET", "/v1/certificates?limit=200&fields[certificates]=certificateType,displayName,name,expirationDate")["data"]:
        a = c["attributes"]
        rows.append((a.get("expirationDate") or "", "certificate", a.get("certificateType"), a.get("displayName") or a.get("name")))
    for pr in call("GET", "/v1/profiles?limit=200&fields[profiles]=name,profileType,profileState,expirationDate")["data"]:
        a = pr["attributes"]
        rows.append((a.get("expirationDate") or "", "profile", f'{a.get("profileType")} {a.get("profileState")}', a.get("name")))
    for exp, kind, typ, name in sorted(rows):
        print(f"{exp[:10]}  {kind:11} {typ:28} {name}")


def screens(bundle, out="screens"):
    v = editable_version(app_id(bundle))
    os.makedirs(out, exist_ok=True)
    for loc in call("GET", f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]:
        locale = loc["attributes"]["locale"]
        for st in call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?limit=50")["data"]:
            kind = st["attributes"]["screenshotDisplayType"]
            shots = call("GET", f"/v1/appScreenshotSets/{st['id']}/appScreenshots?limit=50")["data"]
            print(f"{locale} {kind}: {len(shots)}")
            for i, sh in enumerate(shots, 1):
                a = sh["attributes"]
                img = a.get("imageAsset") or {}
                print(f"  {i}. {a.get('fileName')} {img.get('width')}x{img.get('height')} {(a.get('assetDeliveryState') or {}).get('state')}")
                if img.get("templateUrl"):
                    url = img["templateUrl"].replace("{w}", str(img["width"])).replace("{h}", str(img["height"])).replace("{f}", "png")
                    with urllib.request.urlopen(url, timeout=60) as r, open(f"{out}/{locale}-{kind}-{i}.png", "wb") as f:
                        f.write(r.read())


def testflight(bundle):
    aid = app_id(bundle)
    for g in call("GET", f"/v1/betaGroups?filter[app]={aid}&limit=50")["data"]:
        a = g["attributes"]
        testers = call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200")["data"]
        print(f"--- group {a.get('name')!r} internal={a.get('isInternalGroup')} publicLinkEnabled={a.get('publicLinkEnabled')} "
              f"link={a.get('publicLink')} limitEnabled={a.get('publicLinkLimitEnabled')} limit={a.get('publicLinkLimit')} "
              f"testers={len(testers)}")
        for b in call("GET", f"/v1/builds?filter[betaGroups]={g['id']}&sort=-uploadedDate&limit=5")["data"]:
            ba = b["attributes"]
            d = call("GET", f"/v1/builds/{b['id']}/buildBetaDetail").get("data", {}).get("attributes", {})
            r = call("GET", f"/v1/builds/{b['id']}/betaAppReviewSubmission").get("data") or {}
            print(f"  build {ba.get('version')} uploaded={ba.get('uploadedDate')} expired={ba.get('expired')} "
                  f"processing={ba.get('processingState')} internal={d.get('internalBuildState')} external={d.get('externalBuildState')} "
                  f"betaReview={(r.get('attributes') or {}).get('betaReviewState')}")


if __name__ == "__main__":
    bundle, action, *rest = sys.argv[1:]
    {"status": lambda: status(bundle), "cancel": lambda: cancel(bundle), "set-build": lambda: set_build(bundle, rest[0]),
     "set-version": lambda: set_version(bundle, rest[0]),
     "set-text": lambda: set_text(bundle, rest[0]), "delete-locale": lambda: delete_locale(bundle, rest[0]),
     "testflight": lambda: testflight(bundle), "beta": lambda: beta(bundle, rest[0]),
     "submit": lambda: submit(bundle), "testflight": lambda: testflight(bundle),
     "screens": lambda: screens(bundle, *rest), "certs": certs}[action]()
