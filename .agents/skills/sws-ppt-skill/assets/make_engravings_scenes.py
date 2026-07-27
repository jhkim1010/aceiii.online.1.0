# -*- coding: utf-8 -*-
"""판화 스타일 추가 장면: dos_figuras(모세와 엘리야), nube_voz(구름의 음성)."""
import math, os, cairosvg
INK="#1c1712"; CREAM="#f6f1e4"
OUT=os.path.join(os.path.dirname(os.path.abspath(__file__)),"illustrations")
os.makedirs(OUT,exist_ok=True)
W,H=640,820

def hatch(x0,y0,x1,y1,spacing,angle_deg,width=1.0,op=1.0):
    a=math.radians(angle_deg); dx,dy=math.cos(a),math.sin(a); nx,ny=-dy,dx
    cx,cy=(x0+x1)/2,(y0+y1)/2; diag=math.hypot(x1-x0,y1-y0); out=[]; k=-diag
    while k<=diag:
        px,py=cx+nx*k,cy+ny*k
        out.append(f'<line x1="{px-dx*diag:.1f}" y1="{py-dy*diag:.1f}" x2="{px+dx*diag:.1f}" y2="{py+dy*diag:.1f}"/>'); k+=spacing
    return f'<g stroke="{INK}" stroke-width="{width}" opacity="{op}">'+"".join(out)+'</g>'

def frame_open(extra_defs=""):
    s=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">',
       f'<rect width="{W}" height="{H}" fill="{CREAM}"/>',
       extra_defs,
       f'<clipPath id="fr"><rect x="46" y="46" width="{W-92}" height="{H-92}"/></clipPath>',
       '<g clip-path="url(#fr)">']
    return s
def frame_close(s):
    s.append('</g>')
    s.append(f'<rect x="30" y="30" width="{W-60}" height="{H-60}" fill="none" stroke="{INK}" stroke-width="3"/>')
    s.append(f'<rect x="42" y="42" width="{W-84}" height="{H-84}" fill="none" stroke="{INK}" stroke-width="1.4"/>')
    s.append('</svg>')
    return "".join(s)

def robed(fx,fy,s,shade="R",halo=True):
    g=[]; hr=26*s
    if halo:
        g.append(f'<circle cx="{fx}" cy="{fy}" r="{hr+8:.0f}" fill="none" stroke="{INK}" stroke-width="1.5"/>')
        for k in range(16):
            a=2*math.pi*k/16
            g.append(f'<line x1="{fx+(hr+9)*math.cos(a):.1f}" y1="{fy+(hr+9)*math.sin(a):.1f}" x2="{fx+(hr+18)*math.cos(a):.1f}" y2="{fy+(hr+18)*math.sin(a):.1f}" stroke="{INK}" stroke-width="1"/>')
    g.append(f'<ellipse cx="{fx}" cy="{fy+4}" rx="{hr*0.68:.0f}" ry="{hr*0.82:.0f}" fill="{CREAM}" stroke="{INK}" stroke-width="2"/>')
    g.append(f'<path d="M{fx-hr*0.68:.0f},{fy-2} Q{fx},{fy-hr*1.05:.0f} {fx+hr*0.68:.0f},{fy-2} Q{fx},{fy-hr*0.5:.0f} {fx-hr*0.68:.0f},{fy-2} Z" fill="{INK}"/>')
    g.append(f'<path d="M{fx-9*s},{fy+11*s} Q{fx},{fy+22*s} {fx+9*s},{fy+11*s}" fill="none" stroke="{INK}" stroke-width="1.4"/>')
    top=fy+hr*0.85; hem=fy+150*s
    robe=(f'M{fx-30*s},{top} C{fx-44*s},{top+80*s} {fx-48*s},{hem-40*s} {fx-54*s},{hem} '
          f'L{fx+54*s},{hem} C{fx+48*s},{hem-40*s} {fx+44*s},{top+80*s} {fx+30*s},{top} Q{fx},{top-14*s} {fx-30*s},{top} Z')
    rid=f"r{int(fx)}{int(fy)}"
    g.append(f'<clipPath id="{rid}"><path d="{robe}"/></clipPath>')
    g.append(f'<path d="{robe}" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
    for dxx in (-22,-6,10,26):
        g.append(f'<path d="M{fx+dxx*s},{top+8*s} Q{fx+dxx*s-4},{fy+80*s} {fx+dxx*s-6},{hem-6}" fill="none" stroke="{INK}" stroke-width="1.2" opacity="0.8"/>')
    hx0=fx if shade=="R" else fx-58*s
    g.append(f'<g clip-path="url(#{rid})">{hatch(hx0,top,hx0+58*s,hem,6,70,0.9,0.55)}</g>')
    return "".join(g)

# ── dos_figuras : 모세(돌판)와 엘리야, 마주 봄 ──
s=frame_open()
cx,cy=320,250
rays=[f'<line x1="{cx+70*math.cos(2*math.pi*i/60):.1f}" y1="{cy+70*math.sin(2*math.pi*i/60):.1f}" x2="{cx+560*math.cos(2*math.pi*i/60):.1f}" y2="{cy+560*math.sin(2*math.pi*i/60):.1f}"/>' for i in range(60)]
s.append(f'<g stroke="{INK}" stroke-width="0.9" opacity="0.4">'+"".join(rays)+'</g>')
# 땅
mtn="M46,762 L46,650 L200,590 L440,600 L594,660 L594,762 Z"
s.append(f'<clipPath id="g1"><path d="{mtn}"/></clipPath>')
s.append(f'<path d="{mtn}" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
s.append(f'<g clip-path="url(#g1)">{hatch(46,590,594,762,9,22,1,0.8)}{hatch(46,590,594,762,15,-28,1,0.45)}</g>')
s.append(robed(205,300,1.15,"R"))   # 모세(좌)
# 돌판
s.append(f'<path d="M150,360 h50 v66 a25 25 0 0 1 -50 0 Z" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
for yy in (382,400,418):
    s.append(f'<line x1="163" y1="{yy}" x2="187" y2="{yy}" stroke="{INK}" stroke-width="1.6"/>')
s.append(robed(435,300,1.15,"L"))   # 엘리야(우)
# 엘리야 불꽃(작게)
s.append(f'<path d="M470,352 C486,378 496,392 486,414 A22 22 0 1 1 452,414 C446,398 458,392 460,380 C464,392 470,392 470,386 C470,374 464,364 470,352 Z" fill="{CREAM}" stroke="{INK}" stroke-width="2"/>')
open("/tmp/art/dos_figuras.svg","w").write(frame_close(s))
cairosvg.svg2png(url="/tmp/art/dos_figuras.svg",write_to=f"{OUT}/dos_figuras.png",output_width=W,output_height=H)

# ── nube_voz : 구름의 음성 ──
s=frame_open()
cx=320
# 구름 (스캘럽 외곽)
cloud=("M150,300 "
 "a54 54 0 0 1 20 -104 a70 70 0 0 1 130 -18 a60 60 0 0 1 96 8 "
 "a50 50 0 0 1 14 96 a46 46 0 0 1 -30 18 Z")
s.append(f'<clipPath id="cl"><path d="{cloud}"/></clipPath>')
s.append(f'<path d="{cloud}" fill="{CREAM}" stroke="{INK}" stroke-width="3"/>')
# 구름 밑면 음영 해칭
s.append(f'<g clip-path="url(#cl)">{hatch(150,250,470,320,7,15,1,0.5)}</g>')
# 내려오는 광선 (부채꼴)
apex=(cx,300)
for i in range(19):
    t=i/18.0; ang=math.radians(60+60*t)  # 60~120도(아래방향 부채)
    x2=apex[0]+ (760)*math.cos(ang); y2=apex[1]+760*math.sin(ang)
    w=1.6 if i%3==0 else 0.9
    s.append(f'<line x1="{apex[0]}" y1="{apex[1]+18}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{INK}" stroke-width="{w}" opacity="0.6"/>')
# 산 + 엎드린 세 제자(작게)
mtn="M46,764 L46,690 L230,620 L420,632 L594,700 L594,764 Z"
s.append(f'<clipPath id="g2"><path d="{mtn}"/></clipPath>')
s.append(f'<path d="{mtn}" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
s.append(f'<g clip-path="url(#g2)">{hatch(46,620,594,764,10,24,1,0.7)}</g>')
for dx in (-70,0,70):
    bx=cx+dx
    s.append(f'<path d="M{bx-34},700 q34,-30 68,0 q-34,-14 -68,0 Z" fill="{CREAM}" stroke="{INK}" stroke-width="2"/>')  # 엎드린 몸
    s.append(f'<circle cx="{bx-34}" cy="698" r="9" fill="{CREAM}" stroke="{INK}" stroke-width="2"/>')
open("/tmp/art/nube_voz.svg","w").write(frame_close(s))
cairosvg.svg2png(url="/tmp/art/nube_voz.svg",write_to=f"{OUT}/nube_voz.png",output_width=W,output_height=H)

# transfiguracion : 앞서 만든 샘플을 자산으로 복사
import shutil
shutil.copy("/tmp/art/engrave_transfig.png", f"{OUT}/transfiguracion.png")
shutil.copy("/tmp/art/engrave_transfig.svg", f"{OUT}/transfiguracion.svg")
print("engravings saved to", OUT)
