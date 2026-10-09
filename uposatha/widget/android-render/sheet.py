import sys; sys.path.insert(0,'/tmp/wd/pylib')
from PIL import Image
import os
o='/tmp/wd/out/'
def sheet(names,out,bg,cols=3):
    ims=[Image.open(o+n+'.png').convert('RGBA') for n in names if os.path.exists(o+n+'.png')]
    rows=[ims[i:i+cols] for i in range(0,len(ims),cols)]
    W=max(sum(i.width for i in r)+10*(len(r)+1) for r in rows); H=sum(max(i.height for i in r)+10 for r in rows)+10
    s=Image.new('RGBA',(W,H),bg); y=10
    for r in rows:
        x=10
        for i in r: s.paste(i,(x,y),i); x+=i.width+10
        y+=max(i.height for i in r)+10
    s.convert('RGB').save(out)
sc=sys.argv[1]
for z in ['s','m','l','xl']:
    for th,bg in (('light',(223,227,230,255)),('dark',(0,0,0,255))):
        sheet([f'{sc}-{z}-l{l}-{th}' for l in range(3)],f'/tmp/wd/out/sheet-{sc}-{z}-{th}.png',bg)
