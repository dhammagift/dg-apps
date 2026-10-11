#!/usr/bin/env bash
# Firebase Test Lab runs used today on project dg-sync-data, virtual and physical, against the Spark plan's daily
# limit (10 virtual + 5 physical, one device = one run). Every session runs this BEFORE starting a Test Lab run and
# says in its message what it is about to spend (owner, 2026-10-11: "активно мониторьте все вместе ... физические
# вообще не трогайте, только для финальных прогонов"). GitHub-runner emulators (CI jobs) do not count here.
#
#   bash tools/testlab-usage.sh            (gcloud authorised with the testlab key, as on f1 and f3)
#
# ponytail: the day is taken as midnight to midnight Pacific time (where Google's daily quotas usually roll over);
# if Test Lab refuses a run while this shows room left, the boundary is different - fix DAY_TZ.
set -eu
DAY_TZ=${DAY_TZ:-America/Los_Angeles}
PATH=/opt/google-cloud-sdk/bin:$PATH
TOKEN=$(gcloud auth print-access-token 2>/dev/null)
MODELS=$(gcloud firebase test android models list --format='value(id,form)' 2>/dev/null)
TOKEN="$TOKEN" MODELS="$MODELS" DAY_TZ="$DAY_TZ" python3 - <<'PY'
import json, os, urllib.request, datetime, zoneinfo
B = 'https://toolresults.googleapis.com/toolresults/v1beta3/projects/dg-sync-data'
H = {'Authorization': 'Bearer ' + os.environ['TOKEN']}
get = lambda u: json.load(urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=30))
form = dict(l.split()[:2] for l in os.environ['MODELS'].splitlines() if len(l.split()) >= 2)
tz = zoneinfo.ZoneInfo(os.environ['DAY_TZ'])
now = datetime.datetime.now(tz)
start = now.replace(hour=0, minute=0, second=0, microsecond=0)
used = {'VIRTUAL': [], 'PHYSICAL': []}
for h in get(B + '/histories?pageSize=100').get('histories', []):
    for e in get(B + '/histories/%s/executions?pageSize=100' % h['historyId']).get('executions', []):
        t = datetime.datetime.fromtimestamp(int(e['creationTime']['seconds']), tz)
        if t < start: continue
        steps = get(B + '/histories/%s/executions/%s/steps?pageSize=20' % (h['historyId'], e['executionId'])).get('steps', [])
        for m in {d['value'] for s in steps for d in s.get('dimensionValue', []) if d['key'] == 'Model'} or {'?'}:
            used.setdefault(form.get(m, '?'), []).append('%s %s %s' % (t.strftime('%H:%M'), h.get('name', '?'), m))
nxt = start + datetime.timedelta(days=1)
print('Test Lab, day %s (%s), next reset in %dh%02dm' % (start.date(), os.environ['DAY_TZ'], *divmod(int((nxt - now).total_seconds()) // 60, 60)))
for k, limit in (('VIRTUAL', 10), ('PHYSICAL', 5)):
    print('  %-8s used %2d of %d, left %d' % (k.lower(), len(used.get(k, [])), limit, max(0, limit - len(used.get(k, [])))))
    for r in sorted(used.get(k, [])): print('      ' + r)
PY
