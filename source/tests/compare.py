import csv,sys
a=list(csv.DictReader(open(sys.argv[1],encoding='utf-8-sig')));b=list(csv.DictReader(open(sys.argv[2],encoding='utf-8-sig')))
print('rows',len(a),len(b),'order identical:',[r['old_path'] for r in a]==[r['old_path'] for r in b])
bm={r['old_path']:r for r in b};diff=0
for r in a:
    o=bm.get(r['old_path'])
    if o!=r:
        diff+=1
        if diff<=15: print('PY ',r,'\nPS ',o,'\n')
print('differing rows:',diff)
