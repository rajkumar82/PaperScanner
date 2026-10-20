"""Generates the launcher icon art in the shared app theme (blue->violet gradient + emoji):
  assets/icon/icon.png        full-bleed gradient + glyph (legacy icon)
  assets/icon/background.png  gradient only (adaptive icon background layer)
  assets/icon/foreground.png  glyph on transparent (adaptive icon foreground layer)
Then run: dart run flutter_launcher_icons
Needs Pillow and Windows' Segoe UI Emoji font. Usage: python tool/gen_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

EMOJI, C1, C2, SIZE = "📄", "#1a73e8", "#7c4dff", 1024
FONT = "C:/Windows/Fonts/seguiemj.ttf"
out = Path(__file__).resolve().parent.parent / "assets" / "icon"
out.mkdir(parents=True, exist_ok=True)


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient():
    a, b = rgb(C1), rgb(C2)
    img = Image.new("RGB", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            t = (x + y) / (2 * SIZE - 2)
            px[x, y] = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))
    return img.convert("RGBA")


def glyph(scale):
    big = 136
    layer = Image.new("RGBA", (big * 2, big * 2), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((big, big), EMOJI, font=ImageFont.truetype(FONT, big), anchor="mm", embedded_color=True)
    layer = layer.crop(layer.getbbox())
    r = SIZE * scale / max(layer.size)
    return layer.resize((round(layer.width * r), round(layer.height * r)), Image.LANCZOS)


def with_glyph(base, scale):
    g = glyph(scale)
    base.alpha_composite(g, ((SIZE - g.width) // 2, (SIZE - g.height) // 2))
    return base


gradient().save(out / "background.png")
with_glyph(gradient(), 0.55).save(out / "icon.png")
with_glyph(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), 0.5).save(out / "foreground.png")
print("wrote", out)
