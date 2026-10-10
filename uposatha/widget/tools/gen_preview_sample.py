#!/usr/bin/env python3
"""The sample of the picker previews (debug assets/widget-preview-sample.json): the English sample moved 16 days on, so that the
15th day of a full moon is on (the moon is full, "ends in 9 h", kala till 12:00), and a list that reaches "in 28 d".
Run from uposatha/: python3 widget/tools/gen_preview_sample.py"""
import json, datetime
SRC = 'android/app/src/debug/assets/widget-sample-en.json'
OUT = 'android/app/src/debug/assets/widget-preview-sample.json'
SHIFT = 16
MS = SHIFT * 86400000
d = json.load(open(SRC))

def day(s): return (datetime.date.fromisoformat(s) + datetime.timedelta(days=SHIFT)).isoformat()
def mo(o):
    o['ms'] += MS; o['ymd'] = day(o['ymd'])
for x in d['days']:
    x['date'] = day(x['date'])
    for k in ('sunrise', 'noon', 'sunset', 'aruna'): mo(x[k])
g = datetime.datetime.fromisoformat(d['generatedAt'].replace('Z', '+00:00')) + datetime.timedelta(days=SHIFT)
d['generatedAt'] = g.isoformat(timespec='milliseconds').replace('+00:00', 'Z')
d['today'] = {'ymd': day(d['today']['ymd']), 'moon': 0.47}   # 0.5 a day later, when the preview "now" is
keep = []
for u in d['uposathas']:   # the one that is on (25 Oct), then three that make the list nice: 1 Nov (in 6 d), 16 Nov (in 21 d), 23 Nov (in 28 d)
    if u['start']['ymd'] in ('2026-10-25', '2026-11-01', '2026-11-16', '2026-11-23'): keep.append(u)
d['uposathas'] = keep
json.dump(d, open(OUT, 'w'), ensure_ascii=False)
print(OUT, len(keep), 'uposathas')
