#!/usr/bin/env python3
"""App Store Connect, one step at a time, for one app's version waiting for (or in) review. Run by asc-release.yml with the
ASC key from the GitHub secrets; every step prints what it found and what it did, and changes nothing it does not name.

  asc_release.py <bundle id> status                 the version, its state, its build, the review submission, the texts
  asc_release.py <bundle id> cancel                 take the version out of review (the submission is cancelled)
  asc_release.py <bundle id> set-build <number>     attach that processed build to the version
  asc_release.py <bundle id> set-text <json file>   update the version's texts: {"en-US": {"description": ..,
                                                    "promotionalText": .., "keywords": .., "whatsNew": ..}, "ru": {..}}
  asc_release.py <bundle id> submit                 send the version for review
"""
import json, os, sys, time, urllib.error, urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"
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
    """The newest iOS version that is not on sale yet (the one being prepared or reviewed)."""
    for v in call("GET", f"/v1/apps/{aid}/appStoreVersions?filter[platform]=IOS&limit=10")["data"]:
        if v["attributes"]["appStoreState"] != "READY_FOR_SALE":
            return v
    sys.exit("no iOS version that is not on sale")


def submissions(aid):
    return call("GET", f"/v1/reviewSubmissions?filter[app]={aid}&filter[platform]=IOS&limit=10")["data"]


def status(bundle):
    aid = app_id(bundle)
    v = editable_version(aid)
    a = v["attributes"]
    print(f"version {a['versionString']} ({v['id']}): appStoreState={a['appStoreState']} appVersionState={a.get('appVersionState')}")
    b = call("GET", f"/v1/appStoreVersions/{v['id']}/build").get("data")
    print("build:", (b or {}).get("attributes", {}).get("version", "none"))
    for s in submissions(aid):
        print(f"review submission {s['id']}: state={s['attributes'].get('state')} submitted={s['attributes'].get('submittedDate')}")
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


def submit(bundle):
    aid = app_id(bundle)
    v = editable_version(aid)
    sub = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                                                          "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
    call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": v["id"]}}}}})
    call("PATCH", f"/v1/reviewSubmissions/{sub['id']}",
         {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    print(f"version {v['attributes']['versionString']} submitted for review (submission {sub['id']})")


if __name__ == "__main__":
    bundle, action, *rest = sys.argv[1:]
    {"status": lambda: status(bundle), "cancel": lambda: cancel(bundle), "set-build": lambda: set_build(bundle, rest[0]),
     "set-text": lambda: set_text(bundle, rest[0]), "delete-locale": lambda: delete_locale(bundle, rest[0]),
     "submit": lambda: submit(bundle)}[action]()
