# -*- coding: utf-8 -*-
"""선형(line-art) 일러스트 생성기.
각 모티프를 stroke 기반 SVG로 정의하고 투명 PNG로 렌더한다.
스킬의 assets/illustrations/ 에 .svg(원본)과 .png(사용본)을 함께 저장."""
import os, cairosvg

NAVY = "#142A5A"
GOLD = "#B8860B"

# (color, inner_svg) — viewBox 0 0 240 240, stroke 기반, fill none
MOTIFS = {
 # 십자가 (선형)
 "cross": (NAVY, '<line x1="120" y1="34" x2="120" y2="206"/><line x1="70" y1="90" x2="170" y2="90"/>'),
 # 해/광채 (변형 — resplandeció como el sol)
 "sun": (GOLD, '<circle cx="120" cy="120" r="40"/>' +
        ''.join(f'<line x1="{120+56*_c[0]:.0f}" y1="{120+56*_c[1]:.0f}" x2="{120+80*_c[0]:.0f}" y2="{120+80*_c[1]:.0f}"/>'
                for _c in [(0,-1),(0.707,-0.707),(1,0),(0.707,0.707),(0,1),(-0.707,0.707),(-1,0),(-0.707,-0.707)])),
 # 산 + 광채 (Transfiguración: monte alto + gloria)
 "mountain": (NAVY,
   '<circle cx="120" cy="58" r="20" stroke="%s"/>' % GOLD +
   ''.join('<line x1="%.0f" y1="%.0f" x2="%.0f" y2="%.0f" stroke="%s"/>' %
           (120+28*_c[0],58+28*_c[1],120+40*_c[0],58+40*_c[1],GOLD)
           for _c in [(0,-1),(0.8,-0.6),(-0.8,-0.6),(1,0),(-1,0)]) +
   '<path d="M28 200 L92 118 L128 162 L172 96 L212 200"/>'),
 # 구름 + 음성(광선) — nube de luz / voz desde la nube
 "cloud_voice": (NAVY,
   '<path d="M64 150 h112 a30 30 0 0 0 3 -59 a37 37 0 0 0 -64 -20 a32 32 0 0 0 -55 22 a29 29 0 0 0 4 57 z"/>' +
   ''.join('<line x1="%d" y1="168" x2="%d" y2="202"/>' % (x,x) for x in (86,120,154))),
 # 두 사람 (Moisés y Elías / la comunión de los santos)
 "two_figures": (NAVY,
   '<circle cx="88" cy="86" r="20"/><path d="M56 196 C56 132 120 132 120 196"/>'
   '<circle cx="152" cy="86" r="20"/><path d="M120 196 C120 132 184 132 184 196"/>'),
 # 비둘기 (Espíritu / paz)
 "dove": (NAVY,
   '<path d="M40 150 C90 96 150 92 196 78 C176 104 150 116 120 120 '
   'C150 124 172 120 190 112 C168 150 120 160 86 148 '
   'C74 172 58 176 44 172 C56 166 58 158 56 150 Z"/><circle cx="182" cy="88" r="3" fill="%s"/>' % NAVY),
 # 펼친 성경
 "book": (NAVY,
   '<path d="M120 72 C96 58 58 58 42 64 L42 176 C58 170 96 170 120 184 '
   'C144 170 182 170 198 176 L198 64 C182 58 144 58 120 72 Z"/><line x1="120" y1="72" x2="120" y2="184"/>'),
 # 빈 무덤 (resurrección — El Señor resucitó)
 "empty_tomb": (NAVY,
   '<path d="M70 202 L70 122 a50 50 0 0 1 100 0 L170 202"/>'
   '<path d="M92 202 L92 138 a28 28 0 0 1 56 0 L148 202"/>'
   '<circle cx="196" cy="176" r="26"/>'),
 # 왕관 (Rey / gloria)
 "crown": (GOLD,
   '<path d="M52 172 L42 92 L88 126 L120 74 L152 126 L198 92 L188 172 Z"/><line x1="52" y1="188" x2="188" y2="188"/>'),
 # 불꽃 (Elías / Espíritu)
 "flame": (GOLD,
   '<path d="M120 36 C150 88 176 108 156 158 A44 44 0 1 1 84 158 '
   'C74 132 96 122 100 104 C108 122 118 120 118 108 C118 86 108 66 120 36 Z"/>'),
 # 하트 (amor)
 "heart": (NAVY,
   '<path d="M120 190 C36 132 52 58 104 76 C116 80 120 90 120 98 '
   'C120 90 124 80 136 76 C188 58 204 132 120 190 Z"/>'),
 # 별
 "star": (GOLD,
   '<path d="M120 46 L139 102 L198 102 L150 138 L168 194 L120 160 L72 194 L90 138 L42 102 L101 102 Z"/>'),
}

# 스페인어/영어 별칭 → 파일명
ALIASES = {
 "cruz":"cross","luz":"sun","sol":"sun","monte":"mountain","transfiguracion":"mountain",
 "nube":"cloud_voice","voz":"cloud_voice","moises":"two_figures","elias":"two_figures",
 "comunion":"two_figures","santos":"two_figures","paloma":"dove","espiritu":"dove",
 "biblia":"book","libro":"book","tumba":"empty_tomb","resurreccion":"empty_tomb",
 "corona":"crown","rey":"crown","fuego":"flame","llama":"flame","corazon":"heart",
 "amor":"heart","estrella":"star",
}

def svg_doc(color, inner):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" '
            f'fill="none" stroke="{color}" stroke-width="7" '
            f'stroke-linecap="round" stroke-linejoin="round">{inner}</svg>')

def main():
    outdir = os.path.join(os.path.dirname(__file__), "illustrations")
    os.makedirs(outdir, exist_ok=True)
    for name,(color,inner) in MOTIFS.items():
        svg = svg_doc(color, inner)
        with open(os.path.join(outdir, name+".svg"),"w",encoding="utf-8") as f:
            f.write(svg)
        cairosvg.svg2png(bytestring=svg.encode("utf-8"),
                         write_to=os.path.join(outdir, name+".png"),
                         output_width=900, output_height=900)
    # 별칭 안내 파일
    with open(os.path.join(outdir,"_aliases.txt"),"w",encoding="utf-8") as f:
        for k,v in sorted(ALIASES.items()):
            f.write(f"{k} -> {v}\n")
    print("생성:", ", ".join(sorted(MOTIFS)))

if __name__ == "__main__":
    main()
