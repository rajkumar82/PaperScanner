"""Generates the launcher icon art in the shared app theme (blue->violet gradient + drawn art):
  assets/icon/icon.png        full-bleed gradient + art (legacy icon)
  assets/icon/background.png  gradient only (adaptive icon background layer)
  assets/icon/foreground.png  art on transparent (adaptive icon foreground layer)
Then run: dart run flutter_launcher_icons
Needs Pillow. Usage: python tool/gen_icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

C1, C2, SIZE = "#1a73e8", "#7c4dff", 1024
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


def art():
    """A paper with a camera badge, drawn 2x supersampled on a transparent layer."""
    k = 2
    S = SIZE * k
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def R(x0, y0, x1, y1):
        return [v * k for v in (x0, y0, x1, y1)]

    # soft shadow under the page
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(R(290, 230, 670, 750), radius=40 * k, fill=(20, 20, 70, 90))
    layer.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18 * k)))
    d = ImageDraw.Draw(layer)

    # page with rounded corners and a folded top-right corner
    x0, y0, x1, y1, fold = 270, 200, 650, 720, 110
    page = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    pd = ImageDraw.Draw(page)
    pd.rounded_rectangle(R(x0, y0, x1, y1), radius=36 * k, fill="white")
    pd.polygon([((x1 - fold) * k, (y0 - 1) * k), ((x1 + 1) * k, (y0 - 1) * k), ((x1 + 1) * k, (y0 + fold) * k)], fill=(0, 0, 0, 0))
    layer.alpha_composite(page)
    d = ImageDraw.Draw(layer)
    d.polygon([((x1 - fold) * k, y0 * k), (x1 * k, (y0 + fold) * k), ((x1 - fold) * k, (y0 + fold) * k)], fill=(205, 210, 235, 255))
    for i, w in enumerate((250, 250, 250, 160)):
        y = 330 + i * 70
        d.rounded_rectangle(R(330, y, 330 + w, y + 24), radius=12 * k, fill=(176, 184, 215, 255))

    # camera badge, bottom-right, overlapping the page
    cx0, cy0, cx1, cy1 = 440, 520, 800, 790
    d.rounded_rectangle(R(cx0 + 20, cy0 - 40, cx0 + 140, cy0 + 20), radius=18 * k, fill=(27, 31, 42, 255))
    d.rounded_rectangle(R(cx0 - 6, cy0 - 6, cx1 + 6, cy1 + 6), radius=62 * k, fill="white")
    d.rounded_rectangle(R(cx0, cy0, cx1, cy1), radius=56 * k, fill=(27, 31, 42, 255))
    mx, my = (cx0 + cx1) // 2, (cy0 + cy1) // 2 + 6
    for r, col in ((98, "white"), (80, (45, 52, 80, 255)), (58, (26, 115, 232, 255)), (30, (124, 77, 255, 255))):
        d.ellipse([(mx - r) * k, (my - r) * k, (mx + r) * k, (my + r) * k], fill=col)
    d.ellipse([(mx - 36) * k, (my - 40) * k, (mx - 14) * k, (my - 18) * k], fill=(255, 255, 255, 200))
    d.ellipse(R(cx1 - 62, cy0 + 22, cx1 - 36, cy0 + 48), fill=(255, 255, 255, 255))

    out = layer.resize((SIZE, SIZE), Image.LANCZOS)
    shifted = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shifted.alpha_composite(out, (-26, 14))  # centre the art's bounding box
    return shifted


def with_art(base):
    base.alpha_composite(art())
    return base


gradient().save(out / "background.png")
with_art(gradient()).save(out / "icon.png")
with_art(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))).save(out / "foreground.png")
print("wrote", out)
