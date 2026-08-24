import zlib, sys, json, os
PATH=os.environ.get('ACE_BACKUP', os.path.expanduser('~/Dropbox/앱/aceiii_2.0_backups/kandente4_20260812_160643.backup'))
f=open(PATH,'rb')
assert f.read(5)==b'PGDMP'
vmaj,vmin,vrev=f.read(1)[0],f.read(1)[0],f.read(1)[0]
intSize=f.read(1)[0]; offSize=f.read(1)[0]; fmt=f.read(1)[0]
ver=vmaj*256+vmin
def RI(fh=None):
    fh=fh or f
    b=fh.read(1)[0]; v=0
    for i in range(intSize): v |= fh.read(1)[0]<<(i*8)
    return -v if b else v
def RS(fh=None):
    fh=fh or f
    l=RI(fh)
    return None if l<0 else fh.read(l).decode('utf8','replace')
comp=f.read(1)[0] if ver>=271 else RI()
[RI() for _ in range(7)]
db=RS(); rv=RS(); pv=RS()
n=RI()
toc={}
for i in range(n):
    dumpId=RI(); hasData=RI(); tableoid=RS(); oid=RS(); tag=RS(); desc=RS(); section=RI()
    defn=RS(); drop=RS(); copy=RS(); ns=RS(); tblsp=RS()
    tableam=RS() if ver>=270 else None
    relkind=RI() if ver>=272 else None
    owner=RS()
    deps=[]
    while True:
        d=RS()
        if d is None: break
        deps.append(d)
    fl=f.read(1)[0]; off=int.from_bytes(f.read(offSize),'little')
    toc[dumpId]={'tag':tag,'desc':desc,'defn':defn,'copy':copy,'off':off,'flag':fl}

def read_data(dumpId):
    e=toc[dumpId]
    fh=open(PATH,'rb'); fh.seek(e['off'])
    blktype=fh.read(1)[0]; did=RI(fh)
    d=zlib.decompressobj()
    out=[]
    while True:
        ln=RI(fh)
        if ln<=0: break
        out.append(d.decompress(fh.read(ln)))
    out.append(d.flush())
    fh.close()
    return b''.join(out)

if __name__=='__main__':
    mode=sys.argv[1]
    if mode=='ddl':
        for dumpId,e in toc.items():
            if e['desc']=='TABLE' and e['tag'] in sys.argv[2:]:
                print(e['defn'])
    elif mode=='count':
        for dumpId,e in toc.items():
            if e['desc']=='TABLE DATA':
                try:
                    b=read_data(dumpId)
                    c=b.count(b'\n')
                    print(f"{e['tag']:30s} rows~{c-1 if c else 0:>10,}  bytes={len(b):,}")
                except Exception as ex:
                    print(f"{e['tag']:30s} ERR {ex}")
    elif mode=='head':
        t=sys.argv[2]; k=int(sys.argv[3]) if len(sys.argv)>3 else 5
        for dumpId,e in toc.items():
            if e['desc']=='TABLE DATA' and e['tag']==t:
                print(e['copy'])
                b=read_data(dumpId).decode('utf8','replace')
                for line in b.split('\n')[:k]: print(line)
