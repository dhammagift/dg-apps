#!/usr/bin/env python3
"""The Google Play store listing of one app, read or written through the Play Developer API (an edit opened, the listing
changed, the edit committed; nothing else in the edit). Run by play-listing.yml with the service account from the secrets.

  play_listing.py <package> status                 the listing in every language: title, short and full description
  play_listing.py <package> set <json file> <lang>  shortDescription / fullDescription (and title, if given) for that language,
                                                    from {"play": {"title": .., "shortDescription": .., "fullDescription": ..}}
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
        want = {k: v for k, v in json.load(open(path))["play"].items() if v}
        for k, limit in (("title", 30), ("shortDescription", 80), ("fullDescription", 4000)):
            if k in want and len(want[k]) > limit:
                sys.exit(f"{k}: {len(want[k])} characters, Play allows {limit}")
        api.edits().listings().patch(packageName=pkg, editId=edit, language=lang, body=want).execute()
        api.edits().commit(packageName=pkg, editId=edit).execute()
        edit = None
        print(f"{lang}: {sorted(want)} updated and committed")
    else:
        sys.exit("unknown action " + action)
finally:
    if edit:
        api.edits().delete(packageName=pkg, editId=edit).execute()
