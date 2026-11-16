#!/usr/bin/env python3
"""Google is Google, Apple is Apple, and one app never holds another (owner 2026-11-16: «нажал выкладка в Store, и выкладка
пошла… никаких бабочек»; Trello xjIPdV8a, 05.11). Reads build-app.yml and fails when anything of the other store or of
another app can stop a store upload:

- every store job's chain of `needs` holds only its own app's jobs and the shared plan/unit, and no job of the other
  platform (a macOS runner for Play, an emulator job for TestFlight);
- in the shared build job of an app (it makes the web bundle both stores ship), a step of either platform must not fail
  the job: continue-on-error, or an if: always()/failure() report;
- the store job's `if` asks the build job's own verdict for its platform (android_ok / ios_web_ok) where there is one;
- tools/check-build-run.sh (play-upload.yml, ios-upload.yml) leaves out the other platform's and the other apps' jobs.

Run by the unit job: a new step or job that breaks the rule stops the run here, before any store is asked.
"""
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
wf = yaml.safe_load((ROOT / '.github/workflows/build-app.yml').read_text())
jobs = wf['jobs']

RELEASES = {  # store job -> (app, platform)
    'android-release': ('dg', 'android'), 'ios-release': ('dg', 'ios'),
    'dict-release': ('dict', 'android'), 'dict-ios-release': ('dict', 'ios'),
    'uposatha-release': ('uposatha', 'android'), 'uposatha-ios-release': ('uposatha', 'ios'),
}
SHARED = {'plan', 'unit'}
BUILD = {'dg': 'build', 'dict': 'dict-build', 'uposatha': 'uposatha-build'}
VERDICT = {'android': 'android_ok', 'ios': 'ios_web_ok'}
KEYWORDS = {
    'android': re.compile(r'Android|APK|AAB|gradle|keystore|Capacitor|Play bundle|instrumentation|build outputs', re.I),
    'ios': re.compile(r'\biOS\b|Apple|Xcode|WebKit|TestFlight|\bIPA\b|Safari|macOS', re.I),
}


def needs(job):
    n = jobs[job].get('needs') or []
    return [n] if isinstance(n, str) else list(n)


def chain(job):
    seen, todo = set(), needs(job)
    while todo:
        j = todo.pop()
        if j not in seen:
            seen.add(j)
            todo += needs(j)
    return seen


def app_of(job):
    name = jobs[job].get('name') or job
    if job in SHARED:
        return None
    if job.startswith('dict') or name.startswith('Dictionary'):
        return 'dict'
    if job.startswith('uposatha') or name.startswith('Uposatha'):
        return 'uposatha'
    return 'dg'


def platform_of(job):
    if job in SHARED or job in BUILD.values():
        return None   # shared: checked step by step below
    runs_on = str(jobs[job].get('runs-on', ''))
    uses = str(jobs[job].get('uses', ''))
    name = jobs[job].get('name') or job
    if 'macos' in runs_on or KEYWORDS['ios'].search(name):
        return 'ios'
    if 'launch-check' in uses or re.search(r'emulator|Android', name):
        return 'android'
    return None


def non_blocking(step):
    return step.get('continue-on-error') is True or re.search(r'always\(\)|failure\(\)', str(step.get('if', '')))


errors = []
for rel, (app, plat) in RELEASES.items():
    other = 'ios' if plat == 'android' else 'android'
    for j in sorted(chain(rel)):
        if app_of(j) not in (None, app):
            errors.append(f'{rel}: waits for {j}, a job of another app ({app_of(j)})')
        if platform_of(j) == other:
            errors.append(f'{rel}: waits for {j}, a job of the other platform ({other})')
    build = BUILD[app]
    if build in chain(rel):
        for step in jobs[build]['steps']:
            name = str(step.get('name', step.get('uses', '')))
            if KEYWORDS[other].search(name) and not non_blocking(step):
                errors.append(f'{rel}: {build} step "{name}" is {other}-only and can fail the shared job')
        out = VERDICT[plat]
        if out in (jobs[build].get('outputs') or {}) and f'needs.{build}.outputs.{out}' not in str(jobs[rel].get('if', '')):
            errors.append(f"{rel}: its if does not ask needs.{build}.outputs.{out}")

gate = (ROOT / 'tools/check-build-run.sh').read_text()
for app in ('dg', 'dict', 'uposatha'):
    if f'{app})' not in gate.split('# per app', 1)[-1]:
        errors.append(f'tools/check-build-run.sh: no per-app filter for {app} (another app\'s failed job would hold its upload)')

if errors:
    print('Platform split broken - a store upload could be stopped by the other store or another app:')
    print('\n'.join('  - ' + e for e in errors))
    sys.exit(1)
print(f'platform split: {len(RELEASES)} store jobs, each waits only for its own app and platform')
