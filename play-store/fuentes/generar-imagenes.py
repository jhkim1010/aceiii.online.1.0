#!/usr/bin/env python3
"""[Phase 106] Imágenes de la ficha de Google Play — ícono 512 y gráfico 1024x500 por app.

Mismo estilo que los íconos existentes (commit 7897588): escudo + letra sobre azul marino oscuro.
  V = Ventas (cian) · A = Admin de tienda (verde) · S = Superadmin (oro)
  D = Despacho (violeta) · T = Talleres (coral)   ← nuevos: estas dos apps tenían el logo de Flutter
Renderiza SVG/HTML con Chrome headless (sin dependencias de Python).

  python3 play-store/fuentes/generar-imagenes.py
"""
import os, subprocess, tempfile, shutil

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

APPS = {
    "mobile-sales-app":    ("V", "#22D3EE", "Ventago Ventas",     "Vendé en el local o en la calle, con el stock al día"),
    "tienda-admin-app":    ("A", "#4ADE80", "Ventago Admin",      "Tu tienda en el bolsillo: ventas, cajas y stock"),
    "despacho-app":        ("D", "#A78BFA", "Ventago Despacho",   "Preparación y despacho de pedidos sin errores"),
    "talleres-vendor-app": ("T", "#FB7A5A", "Ventago Talleres",   "Envíos, recepciones y pagos con tus talleres"),
    "ventago-admin-app":   ("S", "#F5A623", "Ventago Superadmin", "Administración interna de la plataforma"),
}

def escudo(letra, color, tam=1024, fondo=True):
    # coordenadas sobre 1024 — mismas proporciones que app_icon.png
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{tam}" height="{tam}" viewBox="0 0 1024 1024">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#1B1C30"/><stop offset="1" stop-color="#0D0E18"/></linearGradient></defs>
  {'<rect width="1024" height="1024" fill="url(#g)"/>' if fondo else ''}
  <path d="M174 128 H850 V390 C850 690 712 846 512 926 C312 846 174 690 174 390 Z" fill="{color}"/>
  <path d="M215 176 H809 V392 C809 668 690 806 512 878 C334 806 215 668 215 392 Z" fill="#171828"/>
  <path d="M244 212 H779 V400 C779 650 676 772 512 840 C348 772 244 650 244 400 Z" fill="none" stroke="{color}" stroke-width="7"/>
  <text x="512" y="618" text-anchor="middle" font-family="Arial Black, Arial, Helvetica, sans-serif"
        font-weight="900" font-size="390" fill="{color}">{letra}</text>
</svg>'''

def render(html, w, h, out):
    d = tempfile.mkdtemp()
    try:
        f = os.path.join(d, "x.html")
        open(f, "w", encoding="utf-8").write(html)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        f"--window-size={w},{h}", f"--screenshot={out}", "file://" + f],
                       check=True, capture_output=True)
    finally:
        shutil.rmtree(d)

def pagina(cuerpo, w, h):
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;width:{w}px;height:{h}px;overflow:hidden;background:#0D0E18}}</style></head>
<body>{cuerpo}</body></html>'''

for app, (letra, color, nombre, lema) in APPS.items():
    dst = os.path.join(RAIZ, "play-store", app)
    os.makedirs(dst, exist_ok=True)
    # ícono 512 (ficha de Play) y 1024 (fuente para flutter_launcher_icons)
    render(pagina(escudo(letra, color, 512), 512, 512), 512, 512, os.path.join(dst, "icono-512.png"))
    render(pagina(escudo(letra, color, 1024), 1024, 1024), 1024, 1024, os.path.join(dst, "icono-1024.png"))
    # gráfico de funciones 1024x500
    graf = f'''<div style="width:1024px;height:500px;display:flex;align-items:center;gap:56px;
      padding:0 72px;box-sizing:border-box;font-family:Arial,Helvetica,sans-serif;
      background:radial-gradient(circle at 20% 40%, {color}33 0, transparent 55%), linear-gradient(#1B1C30,#0D0E18)">
      <div style="flex:0 0 300px">{escudo(letra, color, 300, fondo=False)}</div>
      <div><div style="color:#fff;font-size:64px;font-weight:900;line-height:1.05">{nombre}</div>
      <div style="color:{color};font-size:30px;margin-top:22px;line-height:1.3">{lema}</div></div></div>'''
    render(pagina(graf, 1024, 500), 1024, 500, os.path.join(dst, "grafico-1024x500.png"))
    print("✓", app)

# Ícono del lanzador (flutter_launcher_icons) para las dos apps que tenían el logo de Flutter.
# app_icon.png = con fondo · app_icon_fg.png = primer plano adaptativo (transparente, escudo al 86 %)
def render_transparente(html, w, h, out):
    d = tempfile.mkdtemp()
    try:
        f = os.path.join(d, "x.html")
        open(f, "w", encoding="utf-8").write(html)
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                        "--default-background-color=00000000",
                        f"--window-size={w},{h}", f"--screenshot={out}", "file://" + f],
                       check=True, capture_output=True)
    finally:
        shutil.rmtree(d)

for app in ("despacho-app", "talleres-vendor-app"):
    letra, color, _, _ = APPS[app]
    dst = os.path.join(RAIZ, app, "assets", "icon")
    os.makedirs(dst, exist_ok=True)
    shutil.copy(os.path.join(RAIZ, "play-store", app, "icono-1024.png"), os.path.join(dst, "app_icon.png"))
    fg = f'''<!doctype html><html><head><style>html,body{{margin:0;width:1024px;height:1024px;
      background:transparent;overflow:hidden}}</style></head><body>
      <div style="transform:scale(.86);transform-origin:50% 50%">{escudo(letra, color, 1024, fondo=False)}</div>
      </body></html>'''
    render_transparente(fg, 1024, 1024, os.path.join(dst, "app_icon_fg.png"))
    print("✓ lanzador", app)
