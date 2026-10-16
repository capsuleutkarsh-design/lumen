"""Renders every Gleo brand file from assets/brand/gleo.svg and the gleo_wordmark SVGs.

Writes the Windows .ico (app and tray), the Android launcher icons (adaptive vectors plus PNGs), the
Android splash wordmark, the in-app logo PNGs, the installer images, the README banner and the GitHub
social preview. Run make_logo.py first if the letters change, then:

    python tool/brand/build_brand.py      (needs PySide6 and Pillow)
"""
import io
import os
import re
import sys

from PIL import Image
from PySide6.QtCore import QBuffer, QByteArray, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QLinearGradient, QPainter, QRadialGradient
from PySide6.QtSvg import QSvgRenderer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BRAND = os.path.join(ROOT, "assets", "brand")
SVG = open(os.path.join(BRAND, "gleo.svg"), encoding="utf-8").read()
WORD = open(os.path.join(BRAND, "gleo_wordmark.svg"), encoding="utf-8").read()
WORD_LIGHT = open(os.path.join(BRAND, "gleo_wordmark_light.svg"), encoding="utf-8").read()
BG = QColor("#0D0F14")  # the app's dark background (midnight)


def render(svg, w, h):
    img = QImage(w, h, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    QSvgRenderer(QByteArray(svg.encode())).render(p, QRectF(0, 0, w, h))
    p.end()
    return img


def svg_image(size, svg=SVG):
    return render(svg, size, size)


def word_image(width, svg=WORD):
    vb = QSvgRenderer(QByteArray(svg.encode())).viewBoxF()
    return render(svg, width, round(width * vb.height() / vb.width()))


def to_pil(img):
    buf = QByteArray()
    b = QBuffer(buf)
    b.open(QBuffer.WriteOnly)
    img.save(b, "PNG")
    return Image.open(io.BytesIO(bytes(buf))).convert("RGBA")


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def write(text, *parts):
    path = os.path.join(ROOT, *parts)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote", os.path.relpath(path, ROOT))


def windows_ico():
    sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    imgs = [to_pil(svg_image(s)) for s in sizes]  # each size drawn sharp, not shrunk
    for parts in (("windows", "runner", "resources", "app_icon.ico"), ("assets", "brand", "gleo.ico")):  # app, tray
        path = os.path.join(ROOT, *parts)
        imgs[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=imgs[:-1])
        print("wrote", os.path.relpath(path, ROOT))


# The taskbar thumbnail buttons (windows/runner/media_controls.cpp): Lucide icons (ISC), white, like the app's
# own transport (and android/app/src/main/res/drawable/widget_*.xml).
THUMB = {
    "prev": '<path d="M17.971 4.285A2 2 0 0 1 21 6v12a2 2 0 0 1-3.029 1.715l-9.997-5.998a2 2 0 0 1-.003-3.432z"/><path d="M3 20V4"/>',
    "play": '<path d="M5 5a2 2 0 0 1 3.008-1.728l11.997 6.998a2 2 0 0 1 .003 3.458l-12 7A2 2 0 0 1 5 19z"/>',
    "pause": '<rect x="14" y="3" width="5" height="18" rx="1"/><rect x="5" y="3" width="5" height="18" rx="1"/>',
    "next": '<path d="M21 4v16"/><path d="M6.029 4.285A2 2 0 0 0 3 6v12a2 2 0 0 0 3.029 1.715l9.997-5.998a2 2 0 0 0 .003-3.432z"/>',
}


def thumb_icons():
    sizes = [16, 20, 24, 32, 40]
    for name, body in THUMB.items():
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" '
               f'stroke-linecap="round" stroke-linejoin="round">{body}</svg>')
        imgs = [to_pil(svg_image(s, svg)) for s in sizes]
        path = os.path.join(ROOT, "windows", "runner", "resources", f"thumb_{name}.ico")
        imgs[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=imgs[:-1])
        print("wrote", os.path.relpath(path, ROOT))


def svg_path(svg):
    """(a, tx, ty, d) of the single <path transform="matrix(a 0 0 -a tx ty)" d="..."> in svg."""
    m = re.search(r'matrix\(([-\d.]+) 0 0 -[\d.]+ ([-\d.]+) ([-\d.]+)\)" d="([^"]+)"', svg)
    return float(m[1]), float(m[2]), float(m[3]), m[4]


def vector(width, height, vw, vh, a, tx, ty, d):
    """An Android vector drawable in gold: path d (font units, y up) placed by x' = a*x + tx, y' = -a*y + ty."""
    return f'''<?xml version="1.0" encoding="utf-8"?>
<!-- Made by tool/brand/build_brand.py from assets/brand (Outfit 500 letters as paths). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{width}dp" android:height="{height}dp"
    android:viewportWidth="{vw:.2f}" android:viewportHeight="{vh:.2f}">
    <group android:scaleX="{a:.6f}" android:scaleY="{-a:.6f}" android:translateX="{tx:.4f}" android:translateY="{ty:.4f}">
        <path android:fillColor="#FFE8B04B" android:pathData="{d}"/>
    </group>
</vector>
'''


def android_icons():
    # minSdk 26: launchers use the adaptive icon (mipmap-anydpi-v26); the PNGs only satisfy @mipmap lookups.
    for folder, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(svg_image(size), "android", "app", "src", "main", "res", f"mipmap-{folder}", "ic_launcher.png")
    # Adaptive foreground: the icon's 480-unit tile maps to the 72 dp visible part of the 108 dp layer, so the
    # g (about 31 x 45 dp) sits well inside the 66 dp safe circle. It is the Android 13 monochrome layer too.
    a, tx, ty, d = svg_path(SVG)
    k = 72 / 480
    write(vector(108, 108, 108, 108, a * k, 54 + (tx - 256) * k, 54 + (ty - 256) * k, d),
          "android", "app", "src", "main", "res", "drawable", "ic_launcher_foreground.xml")
    # The splash wordmark (Android 8-11 draw launch_background.xml; 12+ show the launcher icon).
    a, tx, ty, d = svg_path(WORD)
    x0, y0, vw, vh = map(float, re.search(r'viewBox="([^"]+)"', WORD)[1].split())
    write(vector(round(64 * vw / vh), 64, vw, vh, a, tx - x0, ty - y0, d),
          "android", "app", "src", "main", "res", "drawable", "gleo_wordmark.xml")


def glow(p, w, h, cx, cy, r, alpha):
    g = QRadialGradient(cx, cy, r)
    g.setColorAt(0, QColor(232, 176, 75, alpha))
    g.setColorAt(1, QColor(232, 176, 75, 0))
    p.fillRect(0, 0, w, h, g)


def installer_images():
    # Inno Setup: the big image on the welcome page (164x314) and the small one at the top right (55x55),
    # each also at 2x for high-DPI screens
    for scale in (1, 2):
        w, h = 164 * scale, 314 * scale
        img = QImage(w, h, QImage.Format_RGB32)
        p = QPainter(img)
        p.setRenderHint(QPainter.Antialiasing)
        g = QLinearGradient(0, 0, 0, h)
        g.setColorAt(0, QColor("#1C212C"))
        g.setColorAt(1, BG)
        p.fillRect(0, 0, w, h, g)
        glow(p, w, h, w / 2, h * 0.42, w * 0.9, 60)
        s = int(w * 0.62)
        p.drawImage(int((w - s) / 2), int(h * 0.42 - s / 2), svg_image(s))
        word = word_image(int(w * 0.5))
        p.drawImage(int((w - word.width()) / 2), int(h * 0.68), word)
        p.end()
        save(img, "installer", f"wizard{'' if scale == 1 else '@2x'}.bmp")
        small = QImage(55 * scale, 55 * scale, QImage.Format_RGB32)
        small.fill(QColor("#FFFFFF"))
        p = QPainter(small)
        p.setRenderHint(QPainter.Antialiasing)
        p.drawImage(4 * scale, 4 * scale, svg_image(47 * scale))
        p.end()
        save(small, "installer", f"wizard_small{'' if scale == 1 else '@2x'}.bmp")


def poster(w, h, name):
    """The README banner (1280x400) and the GitHub social preview (1280x640): icon, wordmark, tagline."""
    img = QImage(w, h, QImage.Format_ARGB32)
    img.fill(BG)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    glow(p, w, h, 330, h / 2, 520, 55)
    p.drawImage(150, int(h / 2 - 120), svg_image(240))
    word = word_image(300)
    p.drawImage(450, int(h / 2 - word.height() * 0.62), word)
    p.setPen(QColor("#A3A9B6"))
    p.setFont(QFont("Segoe UI", 22))
    p.drawText(458, int(h / 2 + 100), "A beautiful, fast player for your lossless music")
    p.end()
    save(img, "docs", "images", name)


def main():
    QGuiApplication(sys.argv)
    save(svg_image(256), "assets", "brand", "gleo_256.png")
    save(svg_image(1024), "assets", "brand", "gleo_1024.png")
    save(word_image(480), "assets", "brand", "gleo_wordmark.png")
    save(word_image(480, WORD_LIGHT), "assets", "brand", "gleo_wordmark_light.png")
    windows_ico()
    thumb_icons()
    android_icons()
    installer_images()
    poster(1280, 400, "banner.png")
    poster(1280, 640, "social_preview.png")


main()
