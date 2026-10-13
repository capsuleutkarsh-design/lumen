"""Renders every Lumen brand file from assets/brand/lumen.svg.

Writes the Windows .ico, the Android launcher icons, the in-app logo PNG, the installer images
and the README banner. Run it again after changing the SVG:

    python tool/brand/build_brand.py      (needs PySide6 and Pillow)
"""
import io
import os
import sys

from PIL import Image
from PySide6.QtCore import QByteArray, QRectF, Qt
from PySide6.QtGui import QColor, QFont, QGuiApplication, QImage, QLinearGradient, QPainter, QRadialGradient
from PySide6.QtSvg import QSvgRenderer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SVG = open(os.path.join(ROOT, "assets", "brand", "lumen.svg"), encoding="utf-8").read()
CORAL = QColor("#FF6B4A")


def svg_image(size, svg=SVG):
    img = QImage(size, size, QImage.Format_ARGB32)
    img.fill(Qt.transparent)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    QSvgRenderer(QByteArray(svg.encode())).render(p, QRectF(0, 0, size, size))
    p.end()
    return img


def to_pil(img):
    buf = QByteArray()
    from PySide6.QtCore import QBuffer
    b = QBuffer(buf)
    b.open(QBuffer.WriteOnly)
    img.save(b, "PNG")
    return Image.open(io.BytesIO(bytes(buf))).convert("RGBA")


def save(img, *parts):
    path = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def windows_ico():
    sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
    imgs = [to_pil(svg_image(s)) for s in sizes]           # each size drawn sharp, not shrunk
    path = os.path.join(ROOT, "windows", "runner", "resources", "app_icon.ico")
    imgs[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=imgs[:-1])
    print("wrote", os.path.relpath(path, ROOT))


def android_icons():
    for folder, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        save(svg_image(size), "android", "app", "src", "main", "res", f"mipmap-{folder}", "ic_launcher.png")


def installer_images():
    # Inno Setup: the big image on the welcome page (164x314) and the small one at the top right (55x55),
    # each also at 2x for high-DPI screens
    for scale in (1, 2):
        w, h = 164 * scale, 314 * scale
        img = QImage(w, h, QImage.Format_RGB32)
        p = QPainter(img)
        p.setRenderHint(QPainter.Antialiasing)
        g = QLinearGradient(0, 0, 0, h)
        g.setColorAt(0, QColor("#141416"))
        g.setColorAt(1, QColor("#000000"))
        p.fillRect(0, 0, w, h, g)
        glow = QRadialGradient(w / 2, h * 0.42, w * 0.9)
        glow.setColorAt(0, QColor(255, 107, 74, 90))
        glow.setColorAt(1, QColor(255, 107, 74, 0))
        p.fillRect(0, 0, w, h, glow)
        s = int(w * 0.62)
        p.drawImage(int((w - s) / 2), int(h * 0.42 - s / 2), svg_image(s))
        p.setPen(QColor("#F4F4F5"))
        p.setFont(QFont("Segoe UI", 15 * scale, QFont.DemiBold))
        p.drawText(QRectF(0, h * 0.68, w, 40 * scale), Qt.AlignHCenter, "Lumen")
        p.end()
        save(img, "installer", f"wizard{'' if scale == 1 else '@2x'}.bmp")
        small = QImage(55 * scale, 55 * scale, QImage.Format_RGB32)
        small.fill(QColor("#FFFFFF"))
        p = QPainter(small)
        p.setRenderHint(QPainter.Antialiasing)
        p.drawImage(4 * scale, 4 * scale, svg_image(47 * scale))
        p.end()
        save(small, "installer", f"wizard_small{'' if scale == 1 else '@2x'}.bmp")


def banner():
    w, h = 1280, 400
    img = QImage(w, h, QImage.Format_ARGB32)
    img.fill(QColor("#000000"))
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    glow = QRadialGradient(330, 200, 520)
    glow.setColorAt(0, QColor(255, 107, 74, 70))
    glow.setColorAt(1, QColor(255, 107, 74, 0))
    p.fillRect(0, 0, w, h, glow)
    p.drawImage(150, 80, svg_image(240))
    p.setPen(QColor("#F4F4F5"))
    p.setFont(QFont("Segoe UI", 64, QFont.Bold))
    p.drawText(450, 190, "Lumen")
    p.setPen(QColor("#A1A1AA"))
    p.setFont(QFont("Segoe UI", 22))
    p.drawText(454, 245, "A beautiful, fast player for your lossless music")
    p.end()
    save(img, "docs", "images", "banner.png")


def main():
    QGuiApplication(sys.argv)
    save(svg_image(256), "assets", "brand", "lumen_256.png")
    save(svg_image(1024), "assets", "brand", "lumen_1024.png")
    windows_ico()
    android_icons()
    installer_images()
    banner()


main()
