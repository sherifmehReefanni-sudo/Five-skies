#!/usr/bin/env python3
"""Draw the Five Skies app icon.

Output: FiveSkies/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
A 1024x1024 opaque RGB PNG (no alpha, no rounded corners; iOS applies the mask).

The sky uses the maghrib gradient stops from FiveSkies/Today/SkyStyle.swift.
Everything is drawn at 4x and downsampled for antialiasing.

Usage (from the repo root):  python3 tools/make_app_icon.py
Requires Pillow (pip install Pillow).
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

FINAL = 1024
SCALE = 4
S = FINAL * SCALE

# Maghrib sky stops from SkyStyle.swift: (hex color, location from top 0..1).
SKY_STOPS = [
    (0x071433, 0.00),
    (0x1B3F7E, 0.22),
    (0x5B5AA6, 0.40),
    (0xC66B7A, 0.54),
    (0xF39A5B, 0.64),
    (0xFBD08A, 0.74),
    (0xFBD08A, 1.00),
]

SILHOUETTE = (12, 14, 34, 255)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_PATH = os.path.join(
    REPO_ROOT, "FiveSkies", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"
)


def rgb(hex_value):
    return ((hex_value >> 16) & 0xFF, (hex_value >> 8) & 0xFF, hex_value & 0xFF)


def lerp(a, b, t):
    return a + (b - a) * t


def sky_color(t):
    for (c0, p0), (c1, p1) in zip(SKY_STOPS, SKY_STOPS[1:]):
        if p0 <= t <= p1:
            local = 0.0 if p1 == p0 else (t - p0) / (p1 - p0)
            a, b = rgb(c0), rgb(c1)
            return tuple(int(round(lerp(a[i], b[i], local))) for i in range(3))
    return rgb(SKY_STOPS[-1][0])


def px(fraction):
    """Fraction of the canvas to pixels at the working (4x) size."""
    return int(round(fraction * S))


def draw_sky():
    image = Image.new("RGBA", (S, S))
    draw = ImageDraw.Draw(image)
    for y in range(S):
        draw.line([(0, y), (S, y)], fill=sky_color(y / (S - 1)) + (255,))
    return image


def radial_glow(center, radius, color, alpha, blur):
    layer = Image.new("RGBA", (S, S), color + (0,))
    draw = ImageDraw.Draw(layer)
    cx, cy = center
    draw.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def draw_sun(image):
    cx, cy = px(0.5), px(0.545)
    # Wide warm haze, then a tighter bright halo, then the disc itself.
    image.alpha_composite(radial_glow((cx, cy), px(0.30), (255, 190, 120), 110, px(0.10)))
    image.alpha_composite(radial_glow((cx, cy), px(0.16), (255, 222, 150), 170, px(0.05)))
    disc = Image.new("RGBA", (S, S), (255, 244, 214, 0))
    ImageDraw.Draw(disc).ellipse(
        [cx - px(0.095), cy - px(0.095), cx + px(0.095), cy + px(0.095)],
        fill=(255, 244, 214, 255),
    )
    image.alpha_composite(disc.filter(ImageFilter.GaussianBlur(px(0.004))))


def star_polygon(cx, cy, outer, inner, points=4, rotation=-math.pi / 2):
    vertices = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        angle = rotation + i * math.pi / points
        vertices.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    return vertices


def draw_stars(image):
    # Five stars, one per daily prayer, in a gentle arc (middle highest).
    xs = [0.20, 0.35, 0.50, 0.65, 0.80]
    glow = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    sharp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    sdraw = ImageDraw.Draw(sharp)
    for x in xs:
        offset = (x - 0.5) / 0.3
        y = 0.13 + 0.055 * offset * offset
        cx, cy = px(x), px(y)
        size = px(0.030 if x == 0.5 else 0.024)
        r = int(size * 0.9)
        gdraw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 248, 225, 120))
        sdraw.polygon(star_polygon(cx, cy, size, size * 0.28), fill=(255, 250, 235, 255))
        dot = int(size * 0.22)
        sdraw.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(255, 255, 255, 255))
    image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(px(0.012))))
    image.alpha_composite(sharp)


def dome(draw, cx, base_y, half_width, height):
    """An onion-ish dome: a half ellipse with a slightly pinched, pointed top."""
    points = []
    steps = 160
    for i in range(steps + 1):
        t = i / steps  # 0 at left base, 1 at right base
        angle = math.pi * (1 - t)
        x = math.cos(angle)
        y = math.sin(angle)
        # Pinch toward the top to suggest an onion profile.
        bulge = 1.0 + 0.10 * math.sin(angle) * (1 - abs(x))
        points.append((cx + half_width * x * bulge, base_y - height * (y ** 1.15)))
    tip = (cx, base_y - height * 1.10)
    mid = len(points) // 2
    points = points[:mid] + [tip] + points[mid + 1:]
    draw.polygon(points, fill=SILHOUETTE)


def minaret(draw, cx, base_y, top_y, width):
    half = width / 2
    # Shaft.
    draw.rectangle([cx - half, top_y, cx + half, base_y], fill=SILHOUETTE)
    # Two balconies.
    for frac in (0.30, 0.62):
        by = top_y + (base_y - top_y) * frac
        draw.rectangle([cx - half * 1.7, by - width * 0.22, cx + half * 1.7, by + width * 0.18], fill=SILHOUETTE)
    # Small cap and pointed spire.
    cap = width * 1.25
    draw.rectangle([cx - cap / 2, top_y - width * 0.35, cx + cap / 2, top_y + width * 0.1], fill=SILHOUETTE)
    draw.polygon(
        [(cx - cap / 2, top_y - width * 0.30), (cx + cap / 2, top_y - width * 0.30), (cx, top_y - width * 2.4)],
        fill=SILHOUETTE,
    )
    # Hair-thin finial.
    draw.line([(cx, top_y - width * 2.3), (cx, top_y - width * 3.0)], fill=SILHOUETTE, width=max(2, int(width * 0.12)))


def draw_skyline(image):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    ground = px(0.86)

    # Ground band across the whole bottom.
    draw.rectangle([0, ground, S, S], fill=SILHOUETTE)

    # Low wall linking the buildings.
    draw.rectangle([px(0.16), px(0.805), px(0.84), ground], fill=SILHOUETTE)

    # Small side domes on drums.
    for cx in (0.315, 0.685):
        draw.rectangle([px(cx - 0.065), px(0.75), px(cx + 0.065), ground], fill=SILHOUETTE)
        dome(draw, px(cx), px(0.755), px(0.058), px(0.062))
        draw.line([(px(cx), px(0.685)), (px(cx), px(0.655))], fill=SILHOUETTE, width=px(0.004))

    # Central prayer hall, drum and large dome.
    draw.rectangle([px(0.37), px(0.715), px(0.63), ground], fill=SILHOUETTE)
    draw.rectangle([px(0.395), px(0.69), px(0.605), px(0.72)], fill=SILHOUETTE)
    dome(draw, px(0.5), px(0.695), px(0.118), px(0.125))

    # Thin finial with a small ball and crescent on the main dome.
    finial_bottom = px(0.695) - px(0.125) * 1.08
    finial_top = px(0.505)
    draw.line([(px(0.5), finial_bottom), (px(0.5), finial_top)], fill=SILHOUETTE, width=px(0.0045))
    ball = px(0.0075)
    by = px(0.535)
    draw.ellipse([px(0.5) - ball, by - ball, px(0.5) + ball, by + ball], fill=SILHOUETTE)
    # Crescent: a dark disc with a sky-colored disc offset over it is hard to color-match,
    # so cut the crescent by compositing a mask instead.
    crescent = Image.new("L", (S, S), 0)
    cdraw = ImageDraw.Draw(crescent)
    cr = px(0.016)
    ccx, ccy = px(0.5), px(0.488)
    cdraw.ellipse([ccx - cr, ccy - cr, ccx + cr, ccy + cr], fill=255)
    off = int(cr * 0.45)
    cdraw.ellipse([ccx - cr + off, ccy - cr - off * 0.4, ccx + cr + off, ccy + cr - off * 0.4], fill=0)
    layer.paste(Image.new("RGBA", (S, S), SILHOUETTE), (0, 0), crescent)

    # Two slim minarets.
    for cx in (0.205, 0.795):
        minaret(draw, px(cx), ground, px(0.50), px(0.034))

    image.alpha_composite(layer)


def main():
    image = draw_sky()
    draw_sun(image)
    draw_stars(image)
    draw_skyline(image)
    final = image.resize((FINAL, FINAL), Image.LANCZOS).convert("RGB")
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    final.save(OUT_PATH, "PNG", optimize=True)

    check = Image.open(OUT_PATH)
    assert check.size == (FINAL, FINAL), check.size
    assert check.mode == "RGB", check.mode
    print("Wrote %s (%dx%d, %s)" % (OUT_PATH, check.size[0], check.size[1], check.mode))


if __name__ == "__main__":
    main()
