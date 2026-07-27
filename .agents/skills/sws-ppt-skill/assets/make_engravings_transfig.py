# -*- coding: utf-8 -*-
"""고전 판화(engraving/woodcut) 스타일 성경 삽화 생성기 — 샘플: 변형."""
import math, os, cairosvg

INK="#1c1712"; CREAM="#f6f1e4"

def hatch(x0,y0,x1,y1,spacing,angle_deg,width=1.0,color=INK,op=1.0):
    """(x0,y0)-(x1,y1) 사각 영역을 지정 각도의 평행선으로 채운 선분 문자열."""
    a=math.radians(angle_deg); dx,dy=math.cos(a),math.sin(a)
    nx,ny=-dy,dx  # 법선
    cx,cy=(x0+x1)/2,(y0+y1)/2
    diag=math.hypot(x1-x0,y1-y0)
    out=[]
    k=-diag
    while k<=diag:
        px,py=cx+nx*k, cy+ny*k
        xa,ya=px-dx*diag, py-dy*diag
        xb,yb=px+dx*diag, py+dy*diag
        out.append(f'<line x1="{xa:.1f}" y1="{ya:.1f}" x2="{xb:.1f}" y2="{yb:.1f}"/>')
        k+=spacing
    return (f'<g stroke="{color}" stroke-width="{width}" opacity="{op}">'+"".join(out)+'</g>')

W,H=640,820
S=[f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">']
S.append(f'<rect width="{W}" height="{H}" fill="{CREAM}"/>')

# ── clip: 그림 영역(테두리 안) ──
S.append(f'<clipPath id="frame"><rect x="46" y="46" width="{W-92}" height="{H-92}"/></clipPath>')
S.append('<g clip-path="url(#frame)">')

cx,cy=320,250
# 방사 광선 (뒤 배경) — 가는 선, 중심에서 방사
rays=[]
n=72
for i in range(n):
    a=2*math.pi*i/n
    r0=70; r1=560 if i%2==0 else 470
    rays.append(f'<line x1="{cx+r0*math.cos(a):.1f}" y1="{cy+r0*math.sin(a):.1f}" x2="{cx+r1*math.cos(a):.1f}" y2="{cy+r1*math.sin(a):.1f}"/>')
S.append(f'<g stroke="{INK}" stroke-width="1" opacity="0.5">'+"".join(rays)+'</g>')

# 모서리 하늘 해칭(광선 위, 중심 원은 비움)
S.append(f'<clipPath id="skyL"><rect x="0" y="0" width="150" height="360"/></clipPath>')
S.append(f'<clipPath id="skyR"><rect x="490" y="0" width="150" height="360"/></clipPath>')
S.append(f'<g clip-path="url(#skyL)">{hatch(0,0,150,360,7,0,1,INK,0.55)}</g>')
S.append(f'<g clip-path="url(#skyR)">{hatch(490,0,640,360,7,0,1,INK,0.55)}</g>')

# ── 땅/산 ──
mtn="M46,760 L46,650 L170,560 L300,620 L440,545 L594,660 L594,760 Z"
S.append(f'<clipPath id="mtn"><path d="{mtn}"/></clipPath>')
S.append(f'<path d="{mtn}" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
S.append(f'<g clip-path="url(#mtn)">{hatch(46,545,594,760,9,25,1,INK,0.8)}{hatch(46,545,594,760,16,-30,1,INK,0.5)}</g>')

def robed_figure(fx,fy,s,shade="R"):
    """간이 로브 인물(정면). fy=머리중심 y, s=스케일."""
    g=[]
    hr=26*s
    # 후광
    g.append(f'<circle cx="{fx}" cy="{fy}" r="{hr+10:.0f}" fill="none" stroke="{INK}" stroke-width="1.5"/>')
    for k in range(16):
        a=2*math.pi*k/16
        g.append(f'<line x1="{fx+(hr+11)*math.cos(a):.1f}" y1="{fy+(hr+11)*math.sin(a):.1f}" x2="{fx+(hr+20)*math.cos(a):.1f}" y2="{fy+(hr+20)*math.sin(a):.1f}" stroke="{INK}" stroke-width="1"/>')
    # 머리
    g.append(f'<ellipse cx="{fx}" cy="{fy+4}" rx="{hr*0.7:.0f}" ry="{hr*0.85:.0f}" fill="{CREAM}" stroke="{INK}" stroke-width="2"/>')
    g.append(f'<path d="M{fx-hr*0.7:.0f},{fy} Q{fx},{fy-hr:.0f} {fx+hr*0.7:.0f},{fy} Q{fx},{fy-hr*0.4:.0f} {fx-hr*0.7:.0f},{fy} Z" fill="{INK}"/>')  # 머리카락
    g.append(f'<path d="M{fx-10*s},{fy+10*s} Q{fx},{fy+22*s} {fx+10*s},{fy+10*s}" fill="none" stroke="{INK}" stroke-width="1.5"/>')  # 수염
    # 로브
    top=fy+hr*0.9; hem=fy+150*s
    robe=(f'M{fx-30*s},{top} C{fx-42*s},{top+80*s} {fx-46*s},{hem-40*s} {fx-52*s},{hem} '
          f'L{fx+52*s},{hem} C{fx+46*s},{hem-40*s} {fx+42*s},{top+80*s} {fx+30*s},{top} '
          f'Q{fx},{top-14*s} {fx-30*s},{top} Z')
    g.append(f'<clipPath id="rb{fx}{fy}"><path d="{robe}"/></clipPath>')
    g.append(f'<path d="{robe}" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
    # 옷주름
    for dxx in (-24,-8,8,24):
        g.append(f'<path d="M{fx+dxx*s},{top+10*s} Q{fx+dxx*s-4},{fy+80*s} {fx+dxx*s-6},{hem-6}" fill="none" stroke="{INK}" stroke-width="1.3" opacity="0.8"/>')
    # 그림자 해칭(한쪽)
    hx0 = fx if shade=="R" else fx-60*s
    g.append(f'<g clip-path="url(#rb{fx}{fy})">{hatch(hx0,top,hx0+60*s,hem,6,70,0.9,INK,0.6)}</g>')
    return "".join(g)

# 좌: 모세 / 우: 엘리야 (무릎 꿇듯 낮게, 작게)
S.append(robed_figure(140,430,0.62,"R"))
S.append(robed_figure(500,430,0.62,"L"))

# ── 중앙 그리스도 (흰 옷, 밝게 유지) ──
hx,hy=cx,205
# 십자 후광
S.append(f'<circle cx="{hx}" cy="{hy}" r="46" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
S.append(f'<path d="M{hx-46},{hy} h92 M{hx},{hy-46} v92" stroke="{INK}" stroke-width="2.5"/>')
for k in range(24):
    a=2*math.pi*k/24
    S.append(f'<line x1="{hx+47*math.cos(a):.1f}" y1="{hy+47*math.sin(a):.1f}" x2="{hx+60*math.cos(a):.1f}" y2="{hy+60*math.sin(a):.1f}" stroke="{INK}" stroke-width="1"/>')
# 머리
S.append(f'<ellipse cx="{hx}" cy="{hy+6}" rx="24" ry="30" fill="{CREAM}" stroke="{INK}" stroke-width="2.5"/>')
S.append(f'<path d="M{hx-24},{hy+2} Q{hx},{hy-28} {hx+24},{hy+2} Q{hx},{hy-12} {hx-24},{hy+2} Z" fill="{INK}"/>')
S.append(f'<path d="M{hx-16},{hy+16} Q{hx},{hy+40} {hx+16},{hy+16}" fill="none" stroke="{INK}" stroke-width="2"/>')
# 몸 흰 예복
top=hy+34; hem=660
robe=(f'M{hx-44},{top} C{hx-62},{top+110} {hx-70},{hem-120} {hx-78},{hem} '
      f'L{hx+78},{hem} C{hx+70},{hem-120} {hx+62},{top+110} {hx+44},{top} '
      f'Q{hx},{top-18} {hx-44},{top} Z')
S.append(f'<clipPath id="crobe"><path d="{robe}"/></clipPath>')
S.append(f'<path d="{robe}" fill="{CREAM}" stroke="{INK}" stroke-width="3"/>')
# 팔
S.append(f'<path d="M{hx-44},{top+6} C{hx-104},{top+70} {hx-120},{top+180} {hx-112},{top+240} L{hx-84},{top+232} C{hx-88},{top+170} {hx-70},{top+96} {hx-30},{top+52} Z" fill="{CREAM}" stroke="{INK}" stroke-width="3"/>')
S.append(f'<path d="M{hx+44},{top+6} C{hx+104},{top+70} {hx+120},{top+180} {hx+112},{top+240} L{hx+84},{top+232} C{hx+88},{top+170} {hx+70},{top+96} {hx+30},{top+52} Z" fill="{CREAM}" stroke="{INK}" stroke-width="3"/>')
# 옷주름 + 은은한 해칭(가장자리만)
for dxx in (-30,-12,6,24,42):
    S.append(f'<path d="M{hx+dxx},{top+16} Q{hx+dxx-6},{hy+300} {hx+dxx-10},{hem-8}" fill="none" stroke="{INK}" stroke-width="1.4" opacity="0.75"/>')
S.append(f'<g clip-path="url(#crobe)">{hatch(hx+40,top,hx+80,hem,7,72,0.8,INK,0.35)}</g>')

S.append('</g>')  # frame clip
# 테두리(이중선)
S.append(f'<rect x="30" y="30" width="{W-60}" height="{H-60}" fill="none" stroke="{INK}" stroke-width="3"/>')
S.append(f'<rect x="42" y="42" width="{W-84}" height="{H-84}" fill="none" stroke="{INK}" stroke-width="1.4"/>')
S.append('</svg>')

svg="".join(S)
open("/tmp/art/engrave_transfig.svg","w").write(svg)
cairosvg.svg2png(bytestring=svg.encode(),write_to="/tmp/art/engrave_transfig.png",output_width=W,output_height=H)
print("ok")
