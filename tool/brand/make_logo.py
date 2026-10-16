"""Draws the Gleo logo from Outfit (weight 500) as plain SVG paths, so nothing needs the font installed.

Writes assets/brand/gleo.svg (the app icon: a gold g on midnight), gleo_wordmark.svg (gold, for dark
backgrounds) and gleo_wordmark_light.svg (deeper gold, for light ones). Then run build_brand.py.

    python tool/brand/make_logo.py      (needs fontTools; the font is tool/brand/fonts/Outfit[wght].ttf, SIL OFL)
"""
import os

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "brand")
GOLD, DEEP_GOLD, NIGHT = "#E8B04B", "#8C5C00", "#141416"  # DEEP_GOLD = the light theme's accent
f = instantiateVariableFont(TTFont(os.path.join(HERE, "fonts", "Outfit[wght].ttf")), {"wght": 500})
gs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f["hmtx"]


def word(text, track=0):
    """Path data (font units, y up) and bounds for text, letters placed by advance width."""
    sp, bp, x = SVGPathPen(gs), BoundsPen(gs), 0
    for ch in text:
        g = cmap[ord(ch)]
        gs[g].draw(TransformPen(sp, (1, 0, 0, 1, x, 0)))
        gs[g].draw(TransformPen(bp, (1, 0, 0, 1, x, 0)))
        x += hmtx[g][0] + track
    return sp.getCommands(), bp.bounds


def placed(text, cx, cy, height, track=0):
    """A <path> with text's ink box centred on (cx, cy), scaled to the given ink height."""
    d, (x0, y0, x1, y1) = word(text, track)
    s = height / (y1 - y0)
    tx, ty = cx - (x0 + x1) / 2 * s, cy + (y0 + y1) / 2 * s
    return f'<path transform="matrix({s:.5f} 0 0 {-s:.5f} {tx:.2f} {ty:.2f})" d="{d}"/>', (x1 - x0) * s


def write(name, text):
    with open(os.path.join(OUT, name), "w", newline="\n") as out:
        out.write(text)
    print("wrote", name)


g_path, _ = placed("g", 256, 256, 300)
write("gleo.svg", f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <!-- Gleo app icon: a gold g (Outfit 500, drawn as a path) on midnight. (c) 2026 Utkarsh Tripathi -->
  <rect x="16" y="16" width="480" height="480" rx="116" fill="{NIGHT}"/>
  <g fill="{GOLD}">{g_path}</g>
</svg>
''')
w_path, w = placed("gleo", 0, 0, 100, track=-10)
for name, colour in (("gleo_wordmark.svg", GOLD), ("gleo_wordmark_light.svg", DEEP_GOLD)):
    write(name, f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-w/2-4:.1f} -54 {w+8:.1f} 108">
  <!-- Gleo wordmark (Outfit 500, drawn as paths). (c) 2026 Utkarsh Tripathi -->
  <g fill="{colour}">{w_path}</g>
</svg>
''')
