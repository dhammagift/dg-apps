#!/usr/bin/env python3
"""The sample of the picker previews (debug assets/widget-preview-sample.json): the English sample moved 16 days on, so that the
moon is full (a preview with a new moon would be a dark disc), kala till 12:00, and the month has its Uposathas marked.
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
keep = d['uposathas']   # all of them: the calendar widget's preview shows the month with its marks
d['uposathas'] = keep
json.dump(d, open(OUT, 'w'), ensure_ascii=False)
print(OUT, len(keep), 'uposathas')
