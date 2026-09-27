#!/usr/bin/env python3
"""Uploads a set of PNG screenshots to an App Store Connect version's localization, for a listed display type
(the App Store Connect API's own upload contract: reserve, PUT the bytes, mark uploaded). Never submits anything
for review — this only fills the screenshot sets of an existing, editable version.

Run from uposatha/ (or pass --app-dir):
  ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_P8="$(cat AuthKey.p8)" \
  python3 tools/asc-screenshots.py --app-id 6816601259 --version 1.0 --locale en-US \
    --set APP_IPHONE_69=.tmp/ios-tour-iphone --set APP_IPAD_PRO_3GEN_129=.tmp/ios-tour-ipad
"""
import argparse
import glob
import hashlib
import json
import os
import sys
import time
import urllib.request
import urllib.error

BASE = 'https://api.appstoreconnect.apple.com/v1'


def jwt():
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    import base64

    def b64u(data):
        return base64.urlsafe_b64encode(data).rstrip(b'=')

    key_id, issuer_id, p8 = os.environ['ASC_KEY_ID'], os.environ['ASC_ISSUER_ID'], os.environ['ASC_KEY_P8']
    header = {'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}
    now = int(time.time())
    payload = {'iss': issuer_id, 'iat': now, 'exp': now + 1200, 'aud': 'appstoreconnect-v1'}
    signing_input = b64u(json.dumps(header, separators=(',', ':')).encode()) + b'.' + b64u(json.dumps(payload, separators=(',', ':')).encode())
    private_key = serialization.load_pem_private_key(p8.encode(), password=None)
    der_sig = private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der_sig)
    sig = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
    return (signing_input + b'.' + b64u(sig)).decode()


TOKEN = None


def call(method, path_or_url, body=None, headers=None, raw=False):
    url = path_or_url if path_or_url.startswith('http') else BASE + path_or_url
    data = None
    if body is not None:
        data = body if raw else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    if not raw:
        req.add_header('Content-Type', 'application/json')
    if headers is None:
        headers = {}
    # The upload URL (raw=True) is Apple's own storage (an S3-style presigned URL): its own requestHeaders carry
    # whatever auth its signature needs, and adding OUR App Store Connect bearer token on top breaks that
    # signature (this is what a 400 on the PUT meant the first time). The bearer token is only for api.
    # appstoreconnect.apple.com itself.
    if not raw and not any(h.lower() == 'authorization' for h in headers):
        req.add_header('Authorization', 'Bearer ' + TOKEN)
    for k, v in headers.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as resp:
            b = resp.read()
            return resp.status, (json.loads(b) if b and not raw else b)
    except urllib.error.HTTPError as e:
        b = e.read()
        try:
            return e.code, json.loads(b)
        except Exception:
            return e.code, b


def fail(msg, detail=None):
    print('asc-screenshots: ' + msg, file=sys.stderr)
    if detail is not None:
        print(json.dumps(detail, indent=2)[:2000], file=sys.stderr)
    sys.exit(1)


def main():
    global TOKEN
    ap = argparse.ArgumentParser()
    ap.add_argument('--app-id', required=True)
    ap.add_argument('--version', required=True)
    ap.add_argument('--locale', default='en-US')
    ap.add_argument('--set', action='append', required=True, help='DISPLAY_TYPE=directory-of-pngs, repeatable')
    args = ap.parse_args()

    TOKEN = jwt()

    status, versions = call('GET', '/apps/%s/appStoreVersions?filter[versionString]=%s&limit=50' % (args.app_id, args.version))
    if status != 200 or not versions.get('data'):
        fail('could not find version %s of app %s' % (args.version, args.app_id), versions)
    version_id = versions['data'][0]['id']
    print('version %s -> %s (state %s)' % (args.version, version_id, versions['data'][0]['attributes'].get('appStoreState')))

    status, locs = call('GET', '/appStoreVersions/%s/appStoreVersionLocalizations?filter[locale]=%s' % (version_id, args.locale))
    if status != 200 or not locs.get('data'):
        fail('no %s localization on version %s' % (args.locale, version_id), locs)
    loc_id = locs['data'][0]['id']
    print('localization %s -> %s' % (args.locale, loc_id))

    status, existing_sets = call('GET', '/appStoreVersionLocalizations/%s/appScreenshotSets' % loc_id)
    if status != 200:
        fail('could not list existing screenshot sets', existing_sets)
    by_type = {s['attributes']['screenshotDisplayType']: s['id'] for s in existing_sets.get('data', [])}

    for spec in args.set:
        display_type, directory = spec.split('=', 1)
        files = sorted(glob.glob(os.path.join(directory, '*.png')))
        if not files:
            print('  %s: no PNGs in %s, skipping' % (display_type, directory))
            continue
        set_id = by_type.get(display_type)
        if not set_id:
            body = {'data': {'type': 'appScreenshotSets', 'attributes': {'screenshotDisplayType': display_type},
                              'relationships': {'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': loc_id}}}}}
            status, created = call('POST', '/appScreenshotSets', body)
            if status not in (200, 201):
                fail('could not create a %s screenshot set (check the exact enum value Apple expects)' % display_type, created)
            set_id = created['data']['id']
            print('  %s: created set %s' % (display_type, set_id))
        else:
            print('  %s: using existing set %s' % (display_type, set_id))

        for f in files:
            size = os.path.getsize(f)
            name = os.path.basename(f)
            body = {'data': {'type': 'appScreenshots', 'attributes': {'fileName': name, 'fileSize': size},
                              'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}}}}
            status, reserved = call('POST', '/appScreenshots', body)
            if status not in (200, 201):
                fail('could not reserve upload for %s' % name, reserved)
            shot_id = reserved['data']['id']
            ops = reserved['data']['attributes'].get('uploadOperations') or []
            with open(f, 'rb') as fh:
                raw = fh.read()
            for op in ops:
                offset, length = op.get('offset', 0), op.get('length', len(raw))
                chunk = raw[offset:offset + length]
                hdrs = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
                status2, body2 = call(op.get('method', 'PUT'), op['url'], body=chunk, headers=hdrs, raw=True)
                if status2 not in (200, 201, 204):
                    fail('upload PUT failed for %s (status %s)' % (name, status2), body2 if isinstance(body2, (dict, list)) else (body2 or b'')[:500])
            checksum = hashlib.md5(raw).hexdigest()
            status3, patched = call('PATCH', '/appScreenshots/%s' % shot_id,
                                     {'data': {'type': 'appScreenshots', 'id': shot_id, 'attributes': {'uploaded': True, 'sourceFileChecksum': checksum}}})
            if status3 not in (200, 201):
                fail('could not mark %s uploaded' % name, patched)
            print('    uploaded %s (%d bytes) -> %s' % (name, size, shot_id))

    print('done — nothing was sent for review')


if __name__ == '__main__':
    main()
