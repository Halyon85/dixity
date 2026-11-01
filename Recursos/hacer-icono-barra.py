# Arma Recursos/BarraMenu.png y BarraMenu@2x.png (ícono de la barra de menú) a partir de AppIcon.png:
# toma la "d" con la onda y el punto (lo claro y lo coral sobre el fondo negro) y lo deja negro sobre transparente,
# que es como macOS quiere los íconos de la barra (los pinta solo en claro u oscuro).
# Uso: python3 Recursos/hacer-icono-barra.py
from PIL import Image
import os
aqui = os.path.dirname(os.path.abspath(__file__))
im = Image.open(os.path.join(aqui, "AppIcon.png")).convert("RGBA")
w, h = im.size
px = im.load()
glifo = Image.new("L", (w, h), 0)
g = glifo.load()
for y in range(h):
    for x in range(w):
        r, gr, b, a = px[x, y]
        if a < 200:
            continue
        claro = (r + gr + b) / 3            # la "d" es blanca; el fondo, casi negro
        coral = r - b                       # el punto es coral
        v = max(0, min(255, int((claro - 60) * 255 / 150)), min(255, max(0, (coral - 60) * 3)))
        g[x, y] = v
caja = glifo.getbbox()
glifo = glifo.crop(caja)
for nombre, alto in (("BarraMenu.png", 18), ("BarraMenu@2x.png", 36)):
    cw, ch = glifo.size
    ancho = round(cw * alto / ch)
    chico = glifo.resize((ancho, alto), Image.LANCZOS)
    salida = Image.new("RGBA", (ancho, alto), (0, 0, 0, 0))
    salida.putalpha(chico)
    salida.save(os.path.join(aqui, nombre))
    print(nombre, salida.size)
