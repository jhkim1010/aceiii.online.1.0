# -*- coding: utf-8 -*-
"""발로통풍 미니멀 선화 3종(오리지널) → 스킬 자산에 저장."""
import cairosvg, os, shutil
INK="#1a1a1a"
import os as _os
OUT=_os.path.join(_os.path.dirname(_os.path.abspath(__file__)),"illustrations")
os.makedirs(OUT,exist_ok=True)
W,H=680,720
def P(d,w=7): return f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'
def L(x1,y1,x2,y2,w=6): return f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{INK}" stroke-width="{w}" stroke-linecap="round"/>'
def C(cx,cy,r,w=7): return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{INK}" stroke-width="{w}"/>'
def doc(body): return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}"><rect width="{W}" height="{H}" fill="#ffffff"/>{body}</svg>'
def save(name, body):
    svg=doc(body); open(f"/tmp/art/{name}.svg","w").write(svg)
    cairosvg.svg2png(bytestring=svg.encode(),write_to=f"{OUT}/{name}.png",output_width=W,output_height=H)

# ── 1) transfiguracion ──
s=[]
s.append(P("M70 560 Q340 500 610 560",6))
cx=340
for dx,dy in [(-70,-30),(-40,-55),(0,-66),(40,-55),(70,-30)]: s.append(L(cx,150,cx+dx,150+dy,5))
s.append(C(cx,185,26))
s.append(P(f"M{cx-30} 218 C {cx-58} 330, {cx-60} 450, {cx-70} 555",8))
s.append(P(f"M{cx+30} 218 C {cx+58} 330, {cx+60} 450, {cx+70} 555",8))
s.append(P(f"M{cx-70} 555 Q {cx} 585, {cx+70} 555",7))
s.append(P(f"M{cx} 224 C {cx-6} 360, {cx-4} 470, {cx-8} 548",5))
s.append(P(f"M{cx-26} 250 C {cx-80} 250, {cx-108} 230, {cx-120} 210",7))
s.append(P(f"M{cx+26} 250 C {cx+80} 250, {cx+108} 230, {cx+120} 210",7))
def side(fx,t):
    g=[C(fx,360,18,6)]
    g.append(P(f"M{fx-24} 540 C {fx-30} 450, {fx-14+t} 405, {fx+t} 384",7))
    g.append(P(f"M{fx+24} 540 C {fx+30} 450, {fx+14+t} 405, {fx+t} 384",7))
    g.append(P(f"M{fx-24} 540 Q {fx} 558, {fx+24} 540",6)); return "".join(g)
s.append(side(150,8)); s.append(side(530,-8))
save("transfiguracion","".join(s))

# ── 2) dos_figuras : 모세(돌판)·엘리야(불꽃) 마주 봄 ──
s=[P("M60 560 Q340 505 620 560",6)]
# 좌: 모세
mx=235
s.append(C(mx,220,30))
s.append(P(f"M{mx-34} 256 C {mx-52} 360, {mx-54} 470, {mx-60} 560",8))
s.append(P(f"M{mx+34} 256 C {mx+40} 360, {mx+44} 470, {mx+50} 560",8))
s.append(P(f"M{mx-60} 560 Q {mx-5} 585, {mx+50} 560",7))
# 돌판(모세가 든)
s.append(P(f"M{mx-96} 360 h54 v66 a27 27 0 0 1 -54 0 Z",6))
s.append(L(mx-84,384,mx-58,384,4)); s.append(L(mx-84,402,mx-58,402,4)); s.append(L(mx-84,420,mx-58,420,4))
s.append(P(f"M{mx-30} 300 C {mx-70} 320, {mx-88} 345, {mx-94} 366",6))  # 팔→돌판
# 우: 엘리야
ex=445
s.append(C(ex,220,30))
s.append(P(f"M{ex-34} 256 C {ex-40} 360, {ex-44} 470, {ex-50} 560",8))
s.append(P(f"M{ex+34} 256 C {ex+52} 360, {ex+54} 470, {ex+60} 560",8))
s.append(P(f"M{ex-50} 560 Q {ex+5} 585, {ex+60} 560",7))
# 불꽃(엘리야 곁)
s.append(P(f"M{ex+96} 470 C {ex+112} 440, {ex+104} 420, {ex+96} 404 C {ex+114} 424, {ex+124} 452, {ex+108} 486 A22 22 0 0 1 {ex+74} 470 C {ex+70} 452, {ex+84} 448, {ex+88} 436 C {ex+90} 452, {ex+96} 452, {ex+96} 470 Z",5))
save("dos_figuras","".join(s))

# ── 3) nube_voz : 구름의 음성 + 엎드린 세 제자 ──
s=[]
# 구름 (물결 한 획)
s.append(P("M180 210 q-38 0 -38 34 q0 30 34 30 h250 q40 0 40 -36 q0 -34 -40 -34 q-4 -40 -56 -40 q-40 0 -54 26 q-30 -14 -50 4 q-18 6 -30 26 Z",7))
# 내려오는 광선
for dx in (-120,-60,0,60,120):
    s.append(L(340,286, 340+dx, 470, 4))
# 언덕
s.append(P("M60 560 Q340 512 620 560",6))
# 엎드린 세 제자 (낮게 웅크린 획)
for bx in (200,340,480):
    s.append(P(f"M{bx-40} 545 q40 -34 80 0",7))
    s.append(C(bx-40,540,11,6))
save("nube_voz","".join(s))

print("vallotton saved:", os.listdir(OUT).__len__(), "files in dir")
