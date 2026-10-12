#!/usr/bin/env python3
"""The Google Play store listing of one app, read or written through the Play Developer API (an edit opened, the listing
changed, the edit committed; nothing else in the edit). Run by play-listing.yml with the service account from the secrets.

  play_listing.py <package> status                 the listing in every language: title, short and full description
  play_listing.py <package> set <json file> <lang>  shortDescription / fullDescription (and title, if given) for that language,
                                                    from {"play": {"title": .., "shortDescription": .., "fullDescription": ..}}
  play_listing.py <package> notes <json file> <lang> <track>  "What's new" of the newest release on that track, for that
                                                    language, from {"play": {"releaseNotes": ..}} (the release itself is untouched)
"""
import json, os, sys

from google.oauth2 import service_account
from googleapiclient.discovery import build

creds = service_account.Credentials.from_service_account_info(json.loads(os.environ["PLAY_JSON"]),
                                                              scopes=["https://www.googleapis.com/auth/androidpublisher"])
api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
pkg, action, *rest = sys.argv[1:]
edit = api.edits().insert(packageName=pkg, body={}).execute()["id"]
try:
    if action == "status":
        for l in api.edits().listings().list(packageName=pkg, editId=edit).execute().get("listings", []):
            print(f"--- {l['language']}\n  title: {l.get('title')!r}\n  short: {l.get('shortDescription')!r}\n  full: {l.get('fullDescription')!r}")
    elif action == "set":
        path, lang = rest
        want = {k: v for k, v in json.load(open(path))["play"].items() if v and k != "releaseNotes"}
        for k, limit in (("title", 30), ("shortDescription", 80), ("fullDescription", 4000)):
            if k in want and len(want[k]) > limit:
                sys.exit(f"{k}: {len(want[k])} characters, Play allows {limit}")
        api.edits().listings().patch(packageName=pkg, editId=edit, language=lang, body=want).execute()
        api.edits().commit(packageName=pkg, editId=edit).execute()
        edit = None
        print(f"{lang}: {sorted(want)} updated and committed")
    elif action == "notes":
        path, lang, track = rest
        text = json.load(open(path))["play"]["releaseNotes"]
        if len(text) > 500:
            sys.exit(f"releaseNotes: {len(text)} characters, Play allows 500")
        t = api.edits().tracks().get(packageName=pkg, editId=edit, track=track).execute()
        if not t.get("releases"):
            sys.exit(f"no release on the {track} track")
        rel = max(t["releases"], key=lambda r: max([int(c) for c in r.get("versionCodes", [])] or [0]))
        rel["releaseNotes"] = [n for n in rel.get("releaseNotes", []) if n.get("language") != lang] + [{"language": lang, "text": text}]
        api.edits().tracks().update(packageName=pkg, editId=edit, track=track, body={"track": track, "releases": t["releases"]}).execute()
        api.edits().commit(packageName=pkg, editId=edit).execute()
        edit = None
        print(f"{track}: release {rel.get('name')} ({rel.get('versionCodes')}, {rel.get('status')}): What's new set for {lang} and committed")
    else:
        sys.exit("unknown action " + action)
finally:
    if edit:
        api.edits().delete(packageName=pkg, editId=edit).execute()
