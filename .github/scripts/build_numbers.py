#!/usr/bin/env python3
"""The build number of each app for this run: Android's versionCode and iOS's CFBundleVersion.

One counter per app, independent of the other two apps and of the workflow's run number (owner,
2026-10-11: "у каждого свой отдельный"). The rule:

    next = max(build_floor in the app's version.properties,
               the highest versionCode Google Play has for the app's package,
               the highest build App Store Connect has for its bundle id) + 1

So it never goes below what a store already has (Play refuses a lower or equal code), it moves only
when that app is uploaded, and a re-run that reads the stores again gets a fresh number once its
earlier upload went through. Test builds that nobody uploads leave the counter where it is: two of
them in a row carry the same number, which is fine for a sideload (only a LOWER code refuses to
install) and for play-upload.yml / ios-upload.yml (a store refuses a duplicate, loudly).

build_floor is the number already handed out before this rule existed (every app used the run
number, up to 560): a sideloaded test build must never be followed by a lower one.

A store that cannot be read (no secret, an API error) is a warning, unless this run uploads that app
to that store (MUST_READ): then the run stops here rather than an hour later at the upload.

Usage: build_numbers.py              GITHUB_OUTPUT lines: dg_number=N dict_number=N uposatha_number=N
       build_numbers.py --self-test  the rule against fake store answers, no network
Env:   PLAY_JSON, ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8; MUST_READ (plan's tokens: dg_play dict_ios upo_play ...)
Read-only: the Play "edit" is opened to read and deleted, as store_status.py does every three hours.
"""
import json, os, re, sys

# app: (directory with version.properties, Play package, App Store bundle id, plan's token prefix)
APPS = {
    "dg": (".", "gift.dhamma.twa", "gift.dhamma.mobile", "dg"),
    "dict": ("dict", "gift.dhamma.pali", "gift.dhamma.pali", "dict"),
    "uposatha": ("uposatha", "gift.dhamma.uposatha", "gift.dhamma.uposatha", "upo"),
}


def floor_of(text):
    m = re.search(r"^build_floor=(\d+)\s*$", text, re.M)
    if not m:
        raise SystemExit("::error::version.properties has no build_floor=<n>")
    return int(m.group(1))


def next_number(floor, *store_max):
    return max([floor] + [n for n in store_max if n is not None]) + 1


def play_max(pkg):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    creds = service_account.Credentials.from_service_account_info(
        json.loads(os.environ["PLAY_JSON"]), scopes=["https://www.googleapis.com/auth/androidpublisher"])
    svc = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    edit = svc.edits().insert(packageName=pkg, body={}).execute()
    try:
        # Every bundle ever uploaded counts (Play refuses its code again even if it never reached a track),
        # and the tracks cover what older uploads (APKs) put there.
        codes = [int(b["versionCode"]) for b in svc.edits().bundles().list(packageName=pkg, editId=edit["id"]).execute().get("bundles", [])]
        for t in svc.edits().tracks().list(packageName=pkg, editId=edit["id"]).execute().get("tracks", []):
            codes += [int(c) for r in t.get("releases", []) for c in r.get("versionCodes", [])]
    finally:
        svc.edits().delete(packageName=pkg, editId=edit["id"]).execute()
    return max(codes, default=0)


def asc_max(asc, bundle):
    apps = asc(f"/v1/apps?filter[bundleId]={bundle}&limit=1")["data"]
    if not apps:
        return 0
    builds = asc(f"/v1/builds?filter[app]={apps[0]['id']}&sort=-uploadedDate&limit=50&fields[builds]=version")["data"]
    return max((int(b["attributes"]["version"]) for b in builds if b["attributes"]["version"].isdigit()), default=0)


def compute(floors, read_play, read_asc, must_read):
    """floors: {app: n}; read_*: (app) -> highest number or raises; must_read: set of plan tokens."""
    out, problems = {}, []
    for app, (_, _, _, token) in APPS.items():
        found = []
        for store, read in (("play", read_play), ("ios", read_asc)):
            try:
                found.append(read(app))
            except Exception as e:  # noqa: BLE001 - any failure of a store is reported the same way
                msg = f"{app}: {store} not read ({str(e)[:160]})"
                if f"{token}_{store}" in must_read:
                    problems.append("::error::" + msg + " - this run uploads there, and a number not checked against the store may be refused")
                else:
                    print("::warning::" + msg + " - the number is not checked against it", file=sys.stderr)
                found.append(None)
        out[app] = next_number(floors[app], *found)
        print(f"{app}: floor {floors[app]}, play {found[0]}, testflight {found[1]} -> {out[app]}", file=sys.stderr)
    return out, problems


def main():
    floors = {app: floor_of(open(os.path.join(d, "version.properties")).read()) for app, (d, *_) in APPS.items()}
    if os.environ.get("PLAY_JSON"):
        read_play = lambda app: play_max(APPS[app][1])
    else:
        def read_play(app): raise RuntimeError("PLAY_SERVICE_ACCOUNT_JSON is not set")
    asc = None
    if os.environ.get("ASC_KEY_P8"):
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from store_status import asc_client
        asc = asc_client()
    def read_asc(app):
        if asc is None:
            raise RuntimeError("ASC_KEY_P8 is not set")
        return asc_max(asc, APPS[app][2])
    out, problems = compute(floors, read_play, read_asc, set(os.environ.get("MUST_READ", "").split()))
    for p in problems:
        print(p, file=sys.stderr)
    if problems:
        sys.exit(1)
    for app, n in out.items():
        print(f"{app}_number={n}")


def self_test():
    floors = {"dg": 560, "dict": 560, "uposatha": 560}
    stores = {"dg": (533, 530), "dict": (545, 531), "uposatha": (502, 489)}
    out, problems = compute(floors, lambda a: stores[a][0], lambda a: stores[a][1], set())
    assert out == {"dg": 561, "dict": 561, "uposatha": 561} and not problems, out
    # A store ahead of the floor wins; each app moves on its own.
    stores["dict"] = (571, 569)
    out, _ = compute(floors, lambda a: stores[a][0], lambda a: stores[a][1], set())
    assert out == {"dg": 561, "dict": 572, "uposatha": 561}, out
    # After an upload of 561 a re-read gives 562, never 561 again.
    stores["dg"] = (561, 530)
    assert compute(floors, lambda a: stores[a][0], lambda a: stores[a][1], set())[0]["dg"] == 562
    # A store that cannot be read: a warning for a test build, an error when this run uploads there.
    def broken(a): raise RuntimeError("HTTP 500")
    out, problems = compute(floors, broken, lambda a: stores[a][1], set())
    assert out["dict"] == 570 and not problems, (out, problems)
    _, problems = compute(floors, broken, lambda a: stores[a][1], {"upo_play"})
    assert len(problems) == 1 and "uposatha: play" in problems[0], problems
    _, problems = compute(floors, broken, lambda a: stores[a][1], {"upo_ios"})
    assert not problems, problems
    assert floor_of("version=1.0\n# c\nbuild_floor=560\n") == 560
    print("build_numbers: self-test passed")


if __name__ == "__main__":
    self_test() if sys.argv[1:] == ["--self-test"] else main()
