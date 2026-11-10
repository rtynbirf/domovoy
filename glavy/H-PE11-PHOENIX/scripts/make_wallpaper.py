#!/usr/bin/env python3
# PHOENIX-11 v1.3 // Обои: жар-птица из углей (winpe.jpg 1920x1080 + background.bmp 1024x768)
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
import os

BRAND = "/tmp/my-project/build/v13/brand"
ART = os.path.join(BRAND, "phoenix_art.png")

F_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
if not os.path.exists(F_BOLD):
    F_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

TITLE = "PHOENIX-11"
SUB = "Встаёт из пепла. Поднимает другие."

def cover(im, W, H):
    s = max(W / im.width, H / im.height)
    nw, nh = round(im.width * s), round(im.height * s)
    im2 = im.resize((nw, nh), Image.LANCZOS)
    l = (nw - W) // 2
    t = (nh - H) // 2
    return im2.crop((l, t, l + W, t + H))

def bottom_grad(W, H, y0, frac_max):
    """Маска затемнения снизу (L, W x H)."""
    grad = Image.new("L", (1, H))
    for y in range(H):
        if y < y0:
            v = 0
        else:
            v = int(255 * min(1.0, (y - y0) / (H - y0)) * frac_max)
        grad.putpixel((0, y), v)
    return grad.resize((W, H))

def glow_text(base, xy, text, size, fill=(255, 243, 226), glow=(255, 150, 40), blur=10, anchor=None):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(F_BOLD, size)
    d.text(xy, text, font=font, fill=(255, 255, 255, 255), anchor=anchor)
    glow_layer = layer.filter(ImageFilter.GaussianBlur(blur))
    # раскрасить свечение
    solid = Image.new("RGBA", base.size, glow + (255,))
    glow_layer = Image.composite(solid, Image.new("RGBA", base.size, (0, 0, 0, 0)), glow_layer.split()[3])
    base.alpha_composite(glow_layer)
    base.alpha_composite(layer)

def make_winpe_jpg():
    base = cover(Image.open(ART).convert("RGB"), 1920, 1080)
    base = ImageEnhance.Brightness(base).enhance(0.96)
    dark = Image.new("RGB", base.size, (0, 0, 0))
    base = Image.composite(dark, base, bottom_grad(1920, 1080, 560, 0.72))
    out = base.convert("RGBA")
    glow_text(out, (64, 828), TITLE, 104)
    glow_text(out, (70, 952), SUB, 44, fill=(255, 224, 190), glow=(255, 120, 20), blur=8)
    glow_text(out, (72, 1022), "H-PE11 // WinPE 11 // v1.3 PHOENIX EDITION", 26,
              fill=(210, 210, 210), glow=(255, 90, 10), blur=6)
    final = out.convert("RGB")
    p = os.path.join(BRAND, "winpe.jpg")
    final.save(p, "JPEG", quality=92)
    print("[x] winpe.jpg", final.size, os.path.getsize(p), "B")

def make_background_bmp():
    base = cover(Image.open(ART).convert("RGB"), 1024, 768)
    base = ImageEnhance.Brightness(base).enhance(0.82)
    dark = Image.new("RGB", base.size, (0, 0, 0))
    base = Image.composite(dark, base, bottom_grad(1024, 768, 380, 0.66))
    out = base.convert("RGBA")
    glow_text(out, (40, 608), TITLE, 58, blur=8)
    glow_text(out, (44, 690), SUB, 26, fill=(255, 224, 190), glow=(255, 120, 20), blur=6)
    final = out.convert("RGB")
    p = os.path.join(BRAND, "background.bmp")
    final.save(p, "BMP")
    print("[x] background.bmp", final.size, os.path.getsize(p), "B")

def make_brand_png():
    """Плоская версия для репы/README (без затемнения)."""
    im = Image.open(ART).convert("RGB")
    out = im.convert("RGBA")
    glow_text(out, (40, 640), TITLE, 84, blur=10)
    glow_text(out, (44, 742), SUB, 34, fill=(255, 224, 190), glow=(255, 120, 20), blur=7)
    final = out.convert("RGB")
    p = os.path.join(BRAND, "PHOENIX-11_wallpaper.png")
    final.save(p, "PNG")
    print("[x] PHOENIX-11_wallpaper.png", final.size, os.path.getsize(p), "B")

make_winpe_jpg()
make_background_bmp()
make_brand_png()
print("Обои ФЕНИКСА готовы:", BRAND)
