#!/usr/bin/env python3
"""Where every DG app and extension stands in its store, read from the stores' own APIs.

Writes status.json for the owner's private page (dg-node: /apps). Read-only everywhere: a Play
"edit" is opened only to read the tracks and is thrown away. One failing source becomes an entry in
"errors" and a blank cell; it never stops the rest.
"""
import json, os, re, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone

GH = "https://api.github.com"
GH_TOKEN = os.environ.get("GITHUB_TOKEN", "")
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129 Safari/537.36"
errors = []


def get(url, headers=None, raw=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    return body.decode("utf-8", "replace") if raw else json.loads(body)


def gh(path):
    return get(GH + path, {"Authorization": f"Bearer {GH_TOKEN}", "Accept": "application/vnd.github+json"})


def safe(label, fn, default=None):
    try:
        return fn()
    except Exception as e:  # one source down must not hide the others
        errors.append(f"{label}: {str(e)[:200]}")
        return default


# ---------- GitHub: our latest builds ----------

def latest_artifact(repo, prefix):
    """Newest unexpired artifact whose name is prefix-<run number>: (run number, artifact url)."""
    arts = [a for page in (1, 2, 3, 4, 5) for a in gh(f"/repos/{repo}/actions/artifacts?per_page=100&page={page}")["artifacts"]]
    best = None
    for a in arts:
        m = re.fullmatch(re.escape(prefix) + r"-(\d+)", a["name"])
        if m and not a["expired"] and (best is None or int(m.group(1)) > best[0]):
            best = (int(m.group(1)), f"https://github.com/{repo}/actions/runs/{a['workflow_run']['id']}/artifacts/{a['id']}")
    return best


def latest_release(repo):
    r = gh(f"/repos/{repo}/releases/latest")
    apk = next((a["browser_download_url"] for a in r["assets"] if a["name"].endswith(".apk")), "")
    return r["tag_name"].lstrip("v"), r["html_url"], apk


# ---------- Google Play (service account) ----------

def play_tracks(pkgs):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    info = json.loads(os.environ["PLAY_JSON"])
    creds = service_account.Credentials.from_service_account_info(info, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    svc = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    out = {}
    for pkg in pkgs:
        def one():
            edit = svc.edits().insert(packageName=pkg, body={}).execute()
            tracks = {}
            for t in ("internal", "alpha", "beta", "production"):
                rel = [r for r in svc.edits().tracks().get(packageName=pkg, editId=edit["id"], track=t).execute().get("releases", [])
                       if r.get("status") in ("completed", "inProgress") and r.get("versionCodes")]
                if rel:
                    code = max(int(c) for r in rel for c in r["versionCodes"])
                    name = next((r.get("name") for r in rel if str(code) in r["versionCodes"]), "") or ""
                    name = re.sub(r"^\d+ \((.*)\)$", r"\1", name)  # "432 (1.18)" -> "1.18"
                    tracks[t] = {"code": code, "name": name, "status": rel[0]["status"]}
            svc.edits().delete(packageName=pkg, editId=edit["id"]).execute()
            return tracks
        out[pkg] = safe(f"Play {pkg}", one, None)
    return out


def play_public_version(pkg):
    html = get(f"https://play.google.com/store/apps/details?id={pkg}&hl=en", raw=True)
    m = re.search(r'\[\[\["(\d+(?:\.\d+)+)"\]\]', html)
    return m.group(1) if m else ""


# ---------- App Store Connect (API key) ----------

def asc_client():
    import jwt  # PyJWT
    key = os.environ["ASC_KEY_P8"]
    token = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200,
                        "aud": "appstoreconnect-v1"}, key, algorithm="ES256",
                       headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    return lambda path: get("https://api.appstoreconnect.apple.com" + path, {"Authorization": f"Bearer {token}"})


def asc_app(asc, bundle):
    apps = asc(f"/v1/apps?filter[bundleId]={bundle}&limit=1")["data"]
    if not apps:
        return None
    app_id = apps[0]["id"]
    res = {"id": app_id, "live": "", "live_build": "", "review": "", "tf_build": "", "tf_version": "", "public_link": ""}
    for v in asc(f"/v1/apps/{app_id}/appStoreVersions?limit=10")["data"]:
        st, ver = v["attributes"]["appStoreState"], v["attributes"]["versionString"]
        if st == "READY_FOR_SALE" and not res["live"]:
            res["live"] = ver
            b = asc(f"/v1/appStoreVersions/{v['id']}/build").get("data") or {}
            res["live_build"] = (b.get("attributes") or {}).get("version", "")
        if st in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_APP_STORE") and not res["review"]:
            res["review"] = ver
    b = asc(f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=1&include=preReleaseVersion")
    if b["data"]:
        res["tf_build"] = b["data"][0]["attributes"]["version"]
        pre = next((i for i in b.get("included", []) if i["type"] == "preReleaseVersions"), None)
        res["tf_version"] = pre["attributes"]["version"] if pre else ""
    for g in asc(f"/v1/betaGroups?filter[app]={app_id}&limit=20")["data"]:
        if g["attributes"].get("publicLinkEnabled") and g["attributes"].get("publicLink"):
            res["public_link"] = g["attributes"]["publicLink"]
            break
    return res


# ---------- extension stores ----------

def chrome_version(ext_id):
    html = get(f"https://chromewebstore.google.com/detail/{ext_id}?hl=en", raw=True)
    m = re.search(r">Version</div><div[^>]*>([^<]+)", html)
    return m.group(1).strip() if m else ""


def edge_version(crx):
    return get(f"https://microsoftedge.microsoft.com/addons/getproductdetailsbycrxid/{crx}").get("version", "")


def amo_version(slug):
    return get(f"https://addons.mozilla.org/api/v5/addons/addon/{slug}/")["current_version"]["version"]


def plugin_version():
    for item in gh("/repos/dhammagift/dictPlugin/contents/browser-extention"):
        m = re.match(r"dictLookup-extention-([\d.]+)-chrome$", item["name"])
        if m:
            return m.group(1)
    return ""


# ---------- assembling ----------

def fmt(name, code):
    if name and code:
        return f"{name} ({code})"
    return name or (str(code) if code else "")


def row(key, product, platform, store, live, testing, ours, links, waiting=""):
    """status/action are worked out here so the page only draws."""
    lc, tc, oc = live.get("code") or 0, testing.get("code") or 0, ours.get("code") or 0
    if waiting:
        status, action = "на проверке", waiting
    elif oc and oc > max(lc, tc):
        status, action = "не отправлена", f"Сборка {ours.get('label')} ещё никуда не отправлена."
        if tc > lc:
            action = f"{testing.get('label')} в тесте — можно в прод. " + action
    elif tc and tc > lc:
        status, action = "ждёт прода", f"{testing.get('label')} в тесте — можно в прод."
    else:
        status, action = "свежая", "Всё свежее."
    return {"key": key, "product": product, "platform": platform, "store": store,
            "live": live.get("label") or "—", "testing": testing.get("label") or "—", "ours": ours.get("label") or "—",
            "status": status, "action": action, **links}


def main():
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    rows = []
    REPO = "dhammagift/dg-apps"
    PC, ASC_URL = "https://play.google.com/console", "https://appstoreconnect.apple.com/apps"

    play = play_tracks(["gift.dhamma.twa", "gift.dhamma.pali", "gift.dhamma.uposatha", "gift.dhamma.noapp"]) if os.environ.get("PLAY_JSON") else {}
    asc = safe("App Store Connect key", asc_client) if os.environ.get("ASC_KEY_P8") else None

    def play_row(key, product, pkg, aab_prefix, apk_prefix, repo, ours_override=None):
        t = play.get(pkg) or {}
        prod = t.get("production", {})
        test = max((t[k] for k in ("beta", "alpha", "internal") if k in t), key=lambda x: x["code"], default={})
        test_track = next((k for k in ("beta", "alpha", "internal") if t.get(k) is test), "")
        live = {"code": prod.get("code"), "label": fmt(prod.get("name"), prod.get("code"))}
        if not t:
            live = {"code": 0, "label": safe(f"Play page {pkg}", lambda: play_public_version(pkg), "")}
        testing = {"code": test.get("code"), "label": (test_track + " " + fmt(test.get("name"), test.get("code"))).strip()}
        built = safe(f"artifacts {aab_prefix}", lambda: latest_artifact(repo, aab_prefix)) if aab_prefix else None
        apk = safe(f"artifacts {apk_prefix}", lambda: latest_artifact(repo, apk_prefix)) if apk_prefix else None
        ours = ours_override or ({"code": built[0], "label": str(built[0])} if built else {})
        if not t and ours.get("label") and live["label"] and live["label"] != ours["label"]:
            live["code"] = 1  # no track data: a different public version still means ours is newer
        return row(key, product, "Android", "Google Play", live, testing, ours, {
            "store_url": f"https://play.google.com/store/apps/details?id={pkg}", "console_url": PC,
            "repo_url": f"https://github.com/{repo}", "apk_url": apk[1] if apk else "", "testflight_url": ""})

    rows.append(play_row("dg-android", "Dhamma.Gift", "gift.dhamma.twa", "dg-app-full-aab-release", "dg-app-full-apk-release", REPO))
    rows.append(play_row("dict-android", "Словарь", "gift.dhamma.pali", "dg-dict-aab-release", "dg-dict-apk-release", REPO))
    rows.append(play_row("upo-android", "Uposatha", "gift.dhamma.uposatha", "dg-uposatha-aab-release", "dg-uposatha-apk-release", REPO))

    def ios_row(key, product, bundle, ipa_prefix, store_url):
        a = safe(f"App Store Connect {bundle}", lambda: asc_app(asc, bundle)) if asc else None
        a = a or {}
        lb = a.get("live_build", "")
        live = {"code": int(lb) if lb.isdigit() else 0, "label": f"{a['live']} ({lb})" if a.get("live") and lb else a.get("live", "")}
        tf = a.get("tf_build", "")
        testing = {"code": int(tf) if tf.isdigit() else 0, "label": f"TestFlight {tf}" if tf else ""}
        built = safe(f"artifacts {ipa_prefix}", lambda: latest_artifact(REPO, ipa_prefix)) if ipa_prefix else None
        ours = {"code": built[0], "label": str(built[0])} if built else {"code": testing["code"], "label": tf}
        r = row(key, product, "iOS", "App Store", live, testing, ours, {
            "store_url": store_url, "console_url": f"{ASC_URL}/{a['id']}" if a.get("id") else ASC_URL,
            "repo_url": f"https://github.com/{REPO}", "apk_url": "", "testflight_url": a.get("public_link", "")},
            waiting=f"Версия {a['review']} на проверке Apple." if a.get("review") else "")
        return r

    rows.append(ios_row("dg-ios", "Dhamma.Gift", "gift.dhamma.mobile", "dg-app-full-ipa", "https://apps.apple.com/app/id6813706217"))
    rows.append(ios_row("dict-ios", "Словарь", "gift.dhamma.pali", "", ""))
    rows.append(ios_row("upo-ios", "Uposatha", "gift.dhamma.uposatha", "", ""))

    # Not App: Play (notApp's own Play key may be the only one with access; the public page is the fallback)
    rel = safe("notApp release", lambda: latest_release("dhammagift/notApp"), ("", "", ""))
    # notApp's versionCode is major*10000 + minor*100 + patch (app/build.gradle.kts: 0.6.5 -> 605)
    parts = [int(x) for x in rel[0].split(".")] if re.fullmatch(r"\d+\.\d+\.\d+", rel[0] or "") else None
    na_ours = {"code": parts[0] * 10000 + parts[1] * 100 + parts[2], "label": f"{rel[0]} ({parts[0] * 10000 + parts[1] * 100 + parts[2]})"} if parts else {}
    na = play_row("noapp-play", "Not App", "gift.dhamma.noapp", "", "", "dhammagift/notApp", na_ours)
    na["apk_url"] = rel[2]
    rows.append(na)
    rows.append({"key": "noapp-git", "product": "Not App", "platform": "Android", "store": "GitHub", "live": rel[0] or "—",
                 "testing": "—", "ours": rel[0] or "—", "status": "свежая", "action": "Всё свежее.",
                 "store_url": rel[1], "console_url": "https://github.com/dhammagift/notApp/actions",
                 "repo_url": "https://github.com/dhammagift/notApp", "apk_url": rel[2], "testflight_url": ""})
    mr = safe("F-Droid MR", lambda: get("https://gitlab.com/api/v4/projects/fdroid%2Ffdroiddata/merge_requests/51906"), {}) or {}
    def fdroid():
        try:
            return get("https://f-droid.org/api/v1/packages/gift.dhamma.noapp.droid")
        except urllib.error.HTTPError as e:
            if e.code == 404:  # not published yet: expected until the MR is merged
                return {}
            raise
    fd = safe("F-Droid", fdroid, {}) or {}
    fd_live = fd.get("packages", [{}])[0].get("versionName", "") if fd.get("packages") else ""
    rows.append({"key": "noapp-droid", "product": "Not App", "platform": "Android", "store": "F-Droid",
                 "live": fd_live or "—", "testing": f"заявка: {mr.get('state', '?')}" if not fd_live else "—", "ours": rel[0] or "—",
                 "status": "свежая" if fd_live == rel[0] else "на проверке",
                 "action": "Всё свежее." if fd_live == rel[0] else "Заявка в F-Droid, ждём проверку.",
                 "store_url": "https://f-droid.org/packages/gift.dhamma.noapp.droid/" if fd_live else mr.get("web_url", ""),
                 "console_url": "https://gitlab.com/fdroid/fdroiddata/-/merge_requests/51906",
                 "repo_url": "https://github.com/dhammagift/notApp", "apk_url": "", "testflight_url": ""})

    ours = safe("dictPlugin version", plugin_version, "")
    for key, plat, store, fn, surl, curl in [
        ("ext-chrome", "Chrome", "Chrome Web Store", lambda: chrome_version("dnnogjdcmhbiobpnkhdbfnfjnjlikabd"),
         "https://chromewebstore.google.com/detail/dnnogjdcmhbiobpnkhdbfnfjnjlikabd", "https://chrome.google.com/webstore/devconsole"),
        ("ext-edge", "Edge", "Edge Add-ons", lambda: edge_version("aokegkhdaijkikbdocanadeghllhfmhj"),
         "https://microsoftedge.microsoft.com/addons/detail/aokegkhdaijkikbdocanadeghllhfmhj", "https://partner.microsoft.com/dashboard/microsoftedge/overview"),
        ("ext-firefox", "Firefox", "Firefox Add-ons", lambda: amo_version("dhamma-gift"),
         "https://addons.mozilla.org/firefox/addon/dhamma-gift/", "https://addons.mozilla.org/developers/addon/dhamma-gift/versions"),
    ]:
        v = safe(store, fn, "")
        fresh = bool(v) and v == ours
        rows.append({"key": key, "product": "DG Lookup", "platform": plat, "store": store, "live": v or "—", "testing": "—",
                     "ours": ours or "—", "status": "свежая" if fresh else "не отправлена",
                     "action": "Всё свежее." if fresh else f"У нас {ours}, в магазине {v or 'нет'}.",
                     "store_url": surl, "console_url": curl, "repo_url": "https://github.com/dhammagift/dictPlugin",
                     "apk_url": "", "testflight_url": ""})

    out = {"generated_at": now, "run_url": os.environ.get("RUN_URL", ""), "rows": rows, "errors": errors}
    json.dump(out, open(sys.argv[1] if len(sys.argv) > 1 else "status.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps({"rows": len(rows), "errors": errors}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
