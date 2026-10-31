#!/usr/bin/env python3
"""Generate Quietude's six desktop wallpapers.

The wallpapers are original, deterministic compositions built from the same
palette and forms as the in-app Canvas scenes. They are rendered at 3840x2160
(4K UHD) and encoded as high-quality JPEG so they stay sharp on common desktop
displays without shipping enormous PNGs.

Run from the repository root:
  python3 Tools/generate_wallpapers.py

Output:
  Assets/Wallpapers/<environment-id>.jpg
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Assets" / "Wallpapers"

W, H = 3840, 2160
GLOW_SCALE = 4


def vertical_gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    ramp = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None, None]
    top_arr = np.array(top, dtype=np.float32)[None, None, :]
    bottom_arr = np.array(bottom, dtype=np.float32)[None, None, :]
    pixels = top_arr * (1.0 - ramp) + bottom_arr * ramp
    pixels = np.repeat(pixels, W, axis=1).astype(np.uint8)
    return Image.fromarray(pixels, "RGB").convert("RGBA")


def radial_glow(
    center: tuple[float, float],
    radius: float,
    color: tuple[int, int, int],
    strength: float,
    power: float = 2.2,
) -> Image.Image:
    sw, sh = W // GLOW_SCALE, H // GLOW_SCALE
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    xx *= GLOW_SCALE
    yy *= GLOW_SCALE
    distance = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    falloff = np.clip(1.0 - distance / radius, 0.0, 1.0) ** power
    alpha = (falloff * strength * 255).astype(np.uint8)
    layer = np.zeros((sh, sw, 4), dtype=np.uint8)
    layer[..., 0] = color[0]
    layer[..., 1] = color[1]
    layer[..., 2] = color[2]
    layer[..., 3] = alpha
    return Image.fromarray(layer, "RGBA").resize((W, H), Image.BILINEAR)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def add_grain(image: Image.Image, sigma: float, seed: int) -> Image.Image:
    rng = np.random.default_rng(seed)
    base = np.array(image.convert("RGB"), dtype=np.float32)
    grain = rng.normal(0.0, sigma, (H, W, 1)).repeat(3, axis=2)
    return Image.fromarray(np.clip(base + grain, 0, 255).astype(np.uint8), "RGB")


def vignette(image: Image.Image, strength: float = 0.42) -> Image.Image:
    sw, sh = W // GLOW_SCALE, H // GLOW_SCALE
    yy, xx = np.mgrid[0:sh, 0:sw].astype(np.float32)
    cx, cy = sw / 2.0, sh / 2.0
    distance = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2) / math.sqrt(2.0)
    falloff = np.clip(distance, 0.0, 1.0) ** 2.0
    multiplier = (1.0 - strength * falloff).astype(np.float32)
    multiplier = np.repeat(multiplier[:, :, None], 3, axis=2)
    mask = Image.fromarray((multiplier * 255).astype(np.uint8), "RGB").resize((W, H), Image.BILINEAR)
    base = np.array(image.convert("RGB"), dtype=np.float32)
    dim = np.array(mask, dtype=np.float32) / 255.0
    return Image.fromarray(np.clip(base * dim, 0, 255).astype(np.uint8), "RGB")


def paste_rounded(
    base: Image.Image,
    layer: Image.Image,
    box: tuple[int, int, int, int],
    radius: int,
) -> None:
    x0, y0, x1, y1 = box
    size = (x1 - x0, y1 - y0)
    base.paste(layer.resize(size, Image.LANCZOS), (x0, y0), rounded_mask(size, radius))


def soft_layer(draw_fn, blur: float = 0.0) -> Image.Image:
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(blur)) if blur > 0 else layer


def rainy_cabin() -> Image.Image:
    image = vertical_gradient((25, 31, 39), (14, 11, 10))
    image.alpha_composite(radial_glow((W * 0.83, H * 0.28), W * 0.52, (246, 174, 99), 0.52))
    image.alpha_composite(radial_glow((W * 0.80, H * 0.93), W * 0.42, (238, 126, 58), 0.32))

    # Wall boards, barely visible.
    def boards(draw):
        for index in range(14):
            x = W * (0.64 + index * 0.026)
            draw.line((x, 0, x, H * 0.82), fill=(0, 0, 0, 26), width=2)

    image.alpha_composite(soft_layer(boards, blur=1.2))

    # Window frame and glass.
    frame = (int(W * 0.055), int(H * 0.075), int(W * 0.625), int(H * 0.745))
    ImageDraw.Draw(image).rounded_rectangle(frame, radius=30, fill=(40, 30, 23, 255))
    glass_box = (frame[0] + 22, frame[1] + 22, frame[2] - 22, frame[3] - 22)
    glass = vertical_gradient((40, 60, 75), (8, 15, 21))
    paste_rounded(image, glass, glass_box, 16)

    gx0, gy0, gx1, gy1 = glass_box
    gw, gh = gx1 - gx0, gy1 - gy0

    def tree_line(draw):
        points = [(gx0, gy1), (gx0, gy0 + gh * 0.62)]
        random.seed(11)
        x = gx0
        while x < gx1:
            step = random.uniform(gw * 0.02, gw * 0.06)
            height = gy0 + gh * random.uniform(0.54, 0.70)
            points.append((x, height))
            x += step
        points.extend([(gx1, gy0 + gh * 0.62), (gx1, gy1)])
        draw.polygon(points, fill=(8, 16, 16, 235))

    image.alpha_composite(soft_layer(tree_line, blur=7))

    # Rain streaks.
    def rain(draw):
        random.seed(12)
        for _ in range(900):
            x = random.uniform(gx0, gx1)
            y = random.uniform(gy0, gy1)
            length = random.uniform(gh * 0.015, gh * 0.055)
            alpha = random.randint(18, 70)
            draw.line((x, y, x - length * 0.16, y + length), fill=(190, 214, 226, alpha), width=random.choice([1, 1, 2]))

    image.alpha_composite(soft_layer(rain, blur=0.5))

    # A few droplets catching the light.
    def droplets(draw):
        random.seed(13)
        for _ in range(46):
            x = random.uniform(gx0, gx1)
            y = random.uniform(gy0, gy1)
            r = random.uniform(2.0, 5.5)
            draw.ellipse((x - r, y - r * 1.5, x + r, y + r * 1.5), fill=(210, 230, 240, random.randint(24, 70)))

    image.alpha_composite(soft_layer(droplets, blur=0.8))

    # Mullions.
    def mullions(draw):
        draw.line((gx0 + gw * 0.50, gy0, gx0 + gw * 0.50, gy1), fill=(34, 26, 21, 255), width=18)
        draw.line((gx0, gy0 + gh * 0.40, gx1, gy0 + gh * 0.40), fill=(34, 26, 21, 255), width=16)

    image.alpha_composite(soft_layer(mullions, blur=0.4))

    # Warm rim on the window frame.
    def rim(draw):
        draw.rounded_rectangle(frame, radius=30, outline=(226, 164, 102, 58), width=5)

    image.alpha_composite(soft_layer(rim, blur=1.4))
    return image




def train() -> Image.Image:
    image = vertical_gradient((44, 32, 26), (9, 8, 7))
    image.alpha_composite(radial_glow((W * 0.50, H * 0.05), W * 0.34, (255, 214, 150), 0.30))

    # Overhead light.
    def lamp(draw):
        draw.rounded_rectangle((W * 0.44, H * 0.020, W * 0.56, H * 0.038), radius=14, fill=(226, 202, 164, 220))

    image.alpha_composite(soft_layer(lamp, blur=1.2))

    # Window frame and glass.
    frame = (int(W * 0.075), int(H * 0.10), int(W * 0.925), int(H * 0.63))
    ImageDraw.Draw(image).rounded_rectangle(frame, radius=56, fill=(64, 46, 34, 255))
    glass_box = (frame[0] + 26, frame[1] + 26, frame[2] - 26, frame[3] - 26)
    glass = vertical_gradient((22, 36, 58), (5, 9, 16))
    paste_rounded(image, glass, glass_box, 34)

    gx0, gy0, gx1, gy1 = glass_box
    gw, gh = gx1 - gx0, gy1 - gy0

    # Everything beyond the glass is clipped to its rounded shape.
    content = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(content)

    moon_cx, moon_cy, moon_r = gx0 + gw * 0.20, gy0 + gh * 0.24, W * 0.030
    cdraw.ellipse((moon_cx - moon_r, moon_cy - moon_r, moon_cx + moon_r, moon_cy + moon_r), fill=(238, 240, 232, 230))

    rng = random.Random(101)
    for _ in range(360):
        x = rng.uniform(gx0, gx1)
        y = rng.uniform(gy0, gy0 + gh * 0.72)
        r = rng.uniform(0.6, 2.0)
        cdraw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, rng.randint(60, 210)))

    hill_points = [(gx0, gy1), (gx0, gy1 - gh * 0.22)]
    for step in range(9):
        x = gx0 + gw * step / 8
        y = gy1 - gh * (0.14 + 0.10 * rng.random())
        hill_points.append((x, y))
    hill_points.extend([(gx1, gy1)])
    cdraw.polygon(hill_points, fill=(8, 16, 20, 250))

    for _ in range(40):
        x = rng.uniform(gx0 + gw * 0.06, gx1 - gw * 0.06)
        y = gy1 - gh * rng.uniform(0.08, 0.18)
        r = rng.uniform(2.0, 5.0)
        cdraw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 204, 122, rng.randint(60, 160)))

    glass_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glass_mask).rounded_rectangle(glass_box, radius=34, fill=255)
    image.alpha_composite(Image.composite(content, Image.new("RGBA", (W, H), (0, 0, 0, 0)), glass_mask))

    # Glass reflection and mullion.
    def glass_detail(draw):
        draw.polygon(
            [
                (gx0 + gw * 0.10, gy1), (gx0 + gw * 0.46, gy0),
                (gx0 + gw * 0.57, gy0), (gx0 + gw * 0.21, gy1),
            ],
            fill=(255, 255, 255, 14),
        )
        draw.rectangle((gx0 + gw * 0.495, gy0, gx0 + gw * 0.505, gy1), fill=(54, 40, 30, 255))

    image.alpha_composite(soft_layer(glass_detail, blur=0.8))
    ImageDraw.Draw(image).rounded_rectangle(frame, radius=56, outline=(146, 108, 76, 80), width=6)

    # Curtains.
    def curtains(draw):
        for x0, x1 in [(frame[0] - W * 0.050, frame[0] + W * 0.030), (frame[2] - W * 0.030, frame[2] + W * 0.050)]:
            draw.rounded_rectangle((x0, frame[1] - H * 0.03, x1, frame[3] + H * 0.05), radius=24, fill=(84, 46, 36, 255))
            for fold in range(4):
                fx = x0 + (x1 - x0) * (0.16 + fold * 0.22)
                draw.line((fx, frame[1], fx, frame[3] + H * 0.04), fill=(0, 0, 0, 40), width=5)

    image.alpha_composite(soft_layer(curtains, blur=1.4))

    # Seats.
    def seats(draw):
        for x0, x1 in [(-W * 0.10, W * 0.38), (W * 0.62, W * 1.10)]:
            draw.rounded_rectangle((x0, H * 0.68, x1, H * 1.10), radius=90, fill=(62, 38, 29, 255))
            draw.rounded_rectangle(
                (x0 + (x1 - x0) * 0.14, H * 0.71, x0 + (x1 - x0) * 0.70, H * 0.82),
                radius=60,
                fill=(255, 240, 220, 18),
            )

    image.alpha_composite(soft_layer(seats, blur=1.2))

    # Table and cup.
    def table(draw):
        draw.rounded_rectangle((W * 0.28, H * 0.795, W * 0.72, H * 0.97), radius=30, fill=(78, 52, 38, 255))
        draw.line((W * 0.28, H * 0.797, W * 0.72, H * 0.797), fill=(188, 148, 108, 120), width=4)
        cx, cy, r = W * 0.56, H * 0.862, W * 0.022
        draw.rounded_rectangle((cx - r, cy - r * 0.7, cx + r, cy + r * 0.9), radius=10, fill=(190, 176, 154, 235))
        draw.ellipse((cx - r, cy - r * 0.86, cx + r, cy - r * 0.52), fill=(70, 46, 32, 255))

    image.alpha_composite(soft_layer(table, blur=1.0))
    return image


def arch_mask(box: tuple[int, int, int, int]) -> Image.Image:
    """A tall window with a semicircular top, used by Cloud Library."""
    mask = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(mask)
    x0, y0, x1, y1 = box
    radius = (x1 - x0) / 2
    draw.rectangle((x0, y0 + radius, x1, y1), fill=255)
    draw.ellipse((x0, y0, x1, y0 + radius * 2), fill=255)
    return mask


def sakura_night() -> Image.Image:
    image = vertical_gradient((10, 8, 26), (62, 24, 40))

    # Moon, low and warm.
    image.alpha_composite(radial_glow((W * 0.560, H * 0.195), W * 0.26, (255, 206, 158), 0.30))
    image.alpha_composite(radial_glow((W * 0.560, H * 0.195), W * 0.085, (255, 240, 208), 0.55))

    def stars(draw):
        rng = random.Random(111)
        for _ in range(620):
            x = rng.uniform(0, W)
            y = rng.uniform(0, H * 0.58)
            r = rng.uniform(0.6, 2.2)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 250, 240, rng.randint(40, 170)))

    image.alpha_composite(soft_layer(stars, blur=0.35))

    def moon(draw):
        cx, cy, r = W * 0.560, H * 0.195, W * 0.060
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 248, 228, 255))
        draw.ellipse(
            (cx - r * 0.42, cy - r * 0.18, cx - r * 0.06, cy + r * 0.12),
            fill=(242, 226, 202, 110),
        )

    image.alpha_composite(soft_layer(moon, blur=2.4))

    # Far hills in two soft bands.
    def hills(draw):
        for index, base in enumerate((0.575, 0.625)):
            points = [(0, H)]
            for step in range(7):
                x = W * step / 6
                lift = H * (0.025 + 0.040 * random.Random(120 + index * 9 + step).random())
                points.append((x, H * base - lift))
            points.extend([(W, H)])
            draw.polygon(points, fill=(24, 12, 28, 240) if index == 0 else (14, 8, 20, 250))

    image.alpha_composite(soft_layer(hills, blur=7))

    # River.
    river_top = int(H * 0.640)
    river = vertical_gradient((34, 19, 38), (6, 5, 15))
    image.paste(river.crop((0, river_top, W, H)), (0, river_top))

    def moon_path(draw):
        rng = random.Random(121)
        for index in range(28):
            progress = index / 28
            y = river_top + (H - river_top) * progress
            width = W * (0.018 + 0.075 * progress) * rng.uniform(0.5, 1.0)
            x = W * 0.560 + rng.uniform(-W * 0.012, W * 0.012)
            draw.line((x - width * 0.5, y, x + width * 0.5, y), fill=(255, 219, 168, rng.randint(12, 42)), width=3)

    image.alpha_composite(soft_layer(moon_path, blur=1.6))

    def ripples(draw):
        rng = random.Random(122)
        for _ in range(90):
            x = rng.uniform(0, W)
            y = rng.uniform(river_top + H * 0.01, H)
            length = W * rng.uniform(0.02, 0.10)
            draw.line((x, y, x + length, y), fill=(219, 158, 184, rng.randint(10, 30)), width=1)

    image.alpha_composite(soft_layer(ripples, blur=0.6))

    # Torii on the far bank.
    def torii(draw):
        cx = W * 0.235
        base = H * 0.655
        width = W * 0.145
        height = H * 0.135
        color = (199, 61, 51, 235)
        for side in (-1, 1):
            x = cx + side * width * 0.36
            draw.polygon(
                [
                    (x - W * 0.006, base), (x - W * 0.004, base - height),
                    (x + W * 0.004, base - height), (x + W * 0.006, base),
                ],
                fill=color,
            )
        draw.line((cx - width * 0.54, base - height, cx + width * 0.54, base - height), fill=color, width=int(H * 0.014))
        draw.line((cx - width * 0.42, base - height * 0.72, cx + width * 0.42, base - height * 0.72), fill=color, width=int(H * 0.009))

    image.alpha_composite(soft_layer(torii, blur=0.8))

    # Strung paper lanterns.
    def lanterns(draw):
        rng = random.Random(123)
        points = []
        for step in range(61):
            t = step / 60
            x = W * (-0.02 + 1.04 * t)
            curve = 4 * t * (1 - t)
            y = H * (0.105 + 0.045 * t + 0.105 * curve)
            points.append((x, y))
        draw.line(points, fill=(0, 0, 0, 120), width=3)
        for index in range(7):
            t = (index + 0.7) / 7.4
            x = W * (-0.02 + 1.04 * t)
            curve = 4 * t * (1 - t)
            y = H * (0.105 + 0.045 * t + 0.105 * curve) + H * 0.028
            lw, lh = W * 0.036, H * 0.052
            draw.line((x, y - H * 0.050, x, y - lh * 0.5), fill=(0, 0, 0, 90), width=2)
            draw.rounded_rectangle(
                (x - lw * 0.5, y - lh * 0.5, x + lw * 0.5, y + lh * 0.5),
                radius=int(lw * 0.35),
                fill=(246, 139, 82, 235),
            )
            draw.ellipse((x - lw * 0.16, y - lh * 0.22, x + lw * 0.16, y + lh * 0.22), fill=(255, 214, 156, 255))
        return points

    lantern_layer = soft_layer(lanterns, blur=0.9)
    image.alpha_composite(lantern_layer)

    def lantern_glow(draw):
        for index in range(7):
            t = (index + 0.7) / 7.4
            x = W * (-0.02 + 1.04 * t)
            curve = 4 * t * (1 - t)
            y = H * (0.105 + 0.045 * t + 0.105 * curve) + H * 0.028
            draw.ellipse((x - W * 0.035, y - W * 0.035, x + W * 0.035, y + W * 0.035), fill=(255, 160, 84, 22))

    image.alpha_composite(soft_layer(lantern_glow, blur=26))

    # Cherry tree entering from the right.
    def tree(draw):
        rng = random.Random(124)
        trunk = [
            (W * 0.980, H * 0.800), (W * 0.945, H * 0.690),
            (W * 0.865, H * 0.520), (W * 0.905, H * 0.430),
            (W * 0.930, H * 0.300), (W * 0.955, H * 0.290),
            (W * 0.935, H * 0.430), (W * 0.900, H * 0.540),
            (W * 1.010, H * 0.700), (W * 1.015, H * 0.800),
        ]
        draw.polygon(trunk, fill=(52, 22, 28, 255))
        draw.line((W * 0.925, H * 0.430, W * 0.545, H * 0.245), fill=(44, 18, 24, 255), width=int(W * 0.010))
        draw.line((W * 0.940, H * 0.330, W * 0.760, H * 0.130), fill=(44, 18, 24, 255), width=int(W * 0.007))
        clusters = [
            (0.955, 0.300, 0.105), (0.900, 0.245, 0.085), (0.835, 0.205, 0.080),
            (0.760, 0.140, 0.075), (0.690, 0.285, 0.090), (0.610, 0.245, 0.072),
            (0.545, 0.235, 0.058), (0.885, 0.370, 0.070), (0.800, 0.330, 0.060),
        ]
        for cx, cy, radius in clusters:
            cx, cy, radius = W * cx, H * cy, W * radius
            for petal in range(18):
                angle = rng.uniform(0, math.tau)
                distance = radius * rng.uniform(0.2, 0.9)
                px = cx + math.cos(angle) * distance
                py = cy + math.sin(angle) * distance * 0.70
                size = radius * rng.uniform(0.14, 0.28)
                color = (255, 199, 209, 210) if petal % 3 == 0 else (240, 140, 173, 210)
                draw.ellipse((px - size, py - size * 0.72, px + size, py + size * 0.72), fill=color)

    image.alpha_composite(soft_layer(tree, blur=1.2))

    # Falling petals.
    def petals(draw):
        rng = random.Random(125)
        for _ in range(90):
            x = rng.uniform(0, W)
            y = rng.uniform(0, H)
            size = W * rng.uniform(0.0035, 0.008)
            draw.ellipse((x - size, y - size * 0.48, x + size, y + size * 0.48), fill=(255, 189, 209, rng.randint(80, 160)))

    image.alpha_composite(soft_layer(petals, blur=0.7))

    # Fireflies along the bank.
    def fireflies(draw):
        rng = random.Random(126)
        for _ in range(46):
            x = rng.uniform(0, W)
            y = rng.uniform(H * 0.52, H * 0.86)
            r = W * rng.uniform(0.0016, 0.0032)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 224, 132, rng.randint(90, 190)))

    image.alpha_composite(soft_layer(fireflies, blur=2.2))
    return image


def cloud_library() -> Image.Image:
    image = vertical_gradient((26, 26, 58), (196, 122, 106))

    def stars(draw):
        rng = random.Random(131)
        for _ in range(420):
            x = rng.uniform(0, W)
            y = rng.uniform(0, H * 0.42)
            r = rng.uniform(0.5, 2.0)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 252, 246, rng.randint(30, 150)))

    image.alpha_composite(soft_layer(stars, blur=0.4))

    # Cloud sea beyond the room.
    def cloud_sea(draw):
        rng = random.Random(132)
        for index, (base, width, height) in enumerate([
            (0.700, 0.50, 0.14), (0.760, 0.62, 0.17), (0.820, 0.72, 0.20),
        ]):
            for blob in range(9):
                cx = W * rng.uniform(-0.05, 1.05)
                cy = H * (base + rng.uniform(-0.02, 0.02))
                rw = W * width * rng.uniform(0.18, 0.34)
                rh = H * height * rng.uniform(0.40, 0.75)
                draw.ellipse((cx - rw, cy - rh, cx + rw, cy + rh), fill=(214, 174, 196, 46 + index * 10))

    image.alpha_composite(soft_layer(cloud_sea, blur=32))

    # Arched window.
    window = (int(W * 0.445), int(H * 0.090), int(W * 0.850), int(H * 0.635))
    mask = arch_mask(window)
    glass = vertical_gradient((14, 20, 46), (128, 74, 92))
    image.paste(glass, (0, 0), mask)

    def window_scene(draw):
        rng = random.Random(133)
        x0, y0, x1, y1 = window
        cx, cy, r = x0 + (x1 - x0) * 0.68, y0 + (y1 - y0) * 0.30, W * 0.026
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 244, 220, 245))
        for _ in range(80):
            x = rng.uniform(x0, x1)
            y = rng.uniform(y0, y0 + (y1 - y0) * 0.55)
            rr = rng.uniform(0.6, 1.8)
            draw.ellipse((x - rr, y - rr, x + rr, y + rr), fill=(255, 255, 255, rng.randint(70, 210)))
        # A small floating island.
        ix, iy = x0 + (x1 - x0) * 0.24, y0 + (y1 - y0) * 0.62
        iw = (x1 - x0) * 0.075
        draw.polygon([(ix - iw, iy), (ix, iy + iw * 0.9), (ix + iw, iy)], fill=(20, 18, 30, 255))
        draw.ellipse((ix - iw * 1.1, iy - iw * 0.16, ix + iw * 1.1, iy + iw * 0.10), fill=(32, 48, 36, 255))
        draw.ellipse((ix - iw * 0.10, iy - iw * 0.55, ix + iw * 0.10, iy - iw * 0.25), fill=(255, 202, 112, 235))

    scene = soft_layer(window_scene, blur=1.4)
    image.paste(scene, (0, 0), mask)

    def glass_rain(draw):
        rng = random.Random(134)
        x0, y0, x1, y1 = window
        for _ in range(260):
            x = rng.uniform(x0, x1)
            y = rng.uniform(y0, y1)
            length = (y1 - y0) * rng.uniform(0.012, 0.045)
            draw.line((x, y, x - W * 0.0018, y + length), fill=(206, 220, 248, rng.randint(22, 62)), width=1)

    rain_layer = soft_layer(glass_rain, blur=0.6)
    image.paste(rain_layer, (0, 0), mask)

    # Window frame and mullions.
    def frame(draw):
        x0, y0, x1, y1 = window
        radius = (x1 - x0) / 2
        draw.arc((x0, y0, x1, y0 + radius * 2), 180, 360, fill=(58, 36, 30, 255), width=18)
        draw.line((x0, y0 + radius, x0, y1), fill=(58, 36, 30, 255), width=18)
        draw.line((x1, y0 + radius, x1, y1), fill=(58, 36, 30, 255), width=18)
        draw.line((x0, y1, x1, y1), fill=(58, 36, 30, 255), width=18)
        draw.line((x0 + (x1 - x0) * 0.50, y0 + radius * 0.10, x0 + (x1 - x0) * 0.50, y1), fill=(58, 36, 30, 255), width=int(W * 0.007))
        draw.line((x0, y0 + (y1 - y0) * 0.56, x1, y0 + (y1 - y0) * 0.56), fill=(58, 36, 30, 255), width=int(W * 0.006))

    image.alpha_composite(soft_layer(frame, blur=0.5))

    # Room walls, ceiling and floor.
    def room(draw):
        draw.polygon([(0, H * 0.115), (W * 0.445, H * 0.115), (W * 0.445, H * 0.700), (0, H * 0.700)], fill=(46, 27, 24, 255))
        draw.polygon([(W * 0.850, H * 0.115), (W, H * 0.115), (W, H * 0.700), (W * 0.850, H * 0.700)], fill=(32, 19, 19, 255))
        draw.rectangle((0, 0, W, H * 0.115), fill=(26, 15, 15, 255))
        draw.rectangle((0, H * 0.700, W, H), fill=(40, 23, 18, 255))
        # Wall below the window, so no sky shows between the sill and the floor.
        draw.rectangle((W * 0.445, H * 0.635, W * 0.850, H * 0.700), fill=(42, 24, 21, 255))

    image.alpha_composite(soft_layer(room, blur=1.0))

    def floorboards(draw):
        for index in range(13):
            x = W * index / 12
            draw.line((x, H * 0.700, W * 0.5 + (x - W * 0.5) * 1.30, H), fill=(0, 0, 0, 50), width=3)

    image.alpha_composite(soft_layer(floorboards, blur=1.0))

    # Left bookcase.
    def bookcase(draw):
        rng = random.Random(135)
        shelf = (W * 0.025, H * 0.145, W * 0.260, H * 0.690)
        draw.rounded_rectangle(shelf, radius=int(W * 0.008), fill=(40, 22, 18, 255))
        x0, y0, x1, y1 = shelf
        for row in range(4):
            row_y = y0 + (y1 - y0) * (0.26 + 0.245 * row)
            draw.rectangle((x0 + W * 0.008, row_y, x1 - W * 0.008, row_y + H * 0.008), fill=(26, 14, 12, 255))
            cursor = x0 + W * 0.012
            for book in range(9):
                width = W * rng.uniform(0.010, 0.022)
                height = (y1 - y0) * rng.uniform(0.13, 0.21)
                if cursor + width > x1 - W * 0.010:
                    break
                color = rng.choice([(122, 59, 48), (69, 92, 79), (92, 69, 112), (158, 120, 66), (79, 79, 99)])
                draw.rectangle((cursor, row_y - height, cursor + width, row_y), fill=(*color, 235))
                cursor += width + W * 0.0015

    image.alpha_composite(soft_layer(bookcase, blur=0.8))

    # Pendant lamp.
    image.alpha_composite(radial_glow((W * 0.390, H * 0.245), W * 0.055, (255, 184, 102), 0.34))

    def lamp(draw):
        cx = W * 0.390
        draw.line((cx, 0, cx, H * 0.150), fill=(0, 0, 0, 130), width=4)
        draw.polygon([(cx - W * 0.052, H * 0.192), (cx, H * 0.130), (cx + W * 0.052, H * 0.192)], fill=(168, 96, 48, 255))
        draw.ellipse((cx - W * 0.018, H * 0.186, cx + W * 0.018, H * 0.198), fill=(255, 235, 184, 235))

    image.alpha_composite(soft_layer(lamp, blur=1.2))

    # Armchair and sleeping cat.
    def chair(draw):
        box = (W * 0.250, H * 0.620, W * 0.495, H * 0.900)
        draw.rounded_rectangle(box, radius=int(W * 0.045), fill=(92, 46, 56, 255))
        draw.rounded_rectangle(
            (box[0] + W * 0.016, box[1] + H * 0.020, box[2] - W * 0.016, box[1] + H * 0.095),
            radius=int(H * 0.035), fill=(110, 59, 69, 235),
        )
        for side in (-1, 1):
            arm_x = box[0] - W * 0.008 if side < 0 else box[2] - W * 0.018
            draw.rounded_rectangle(
                (arm_x, box[1] + H * 0.085, arm_x + W * 0.030, box[1] + H * 0.260),
                radius=int(H * 0.020), fill=(74, 36, 45, 255),
            )
        # A curled cat.
        cx, cy = (box[0] + box[2]) / 2 - W * 0.010, box[1] + H * 0.115
        draw.ellipse((cx - W * 0.052, cy - H * 0.024, cx + W * 0.052, cy + H * 0.026), fill=(34, 30, 34, 255))
        draw.ellipse((cx + W * 0.026, cy - H * 0.040, cx + W * 0.058, cy - H * 0.008), fill=(34, 30, 34, 255))
        draw.polygon(
            [(cx + W * 0.030, cy - H * 0.036), (cx + W * 0.036, cy - H * 0.052), (cx + W * 0.043, cy - H * 0.038)],
            fill=(34, 30, 34, 255),
        )
        draw.polygon(
            [(cx + W * 0.048, cy - H * 0.037), (cx + W * 0.054, cy - H * 0.052), (cx + W * 0.058, cy - H * 0.034)],
            fill=(34, 30, 34, 255),
        )

    image.alpha_composite(soft_layer(chair, blur=1.4))

    # Side table, books, candle.
    image.alpha_composite(radial_glow((W * 0.705, H * 0.700), W * 0.035, (255, 198, 118), 0.26))

    def table(draw):
        rng = random.Random(136)
        x0, y0, x1 = W * 0.585, H * 0.745, W * 0.735
        draw.rounded_rectangle((x0, y0, x1, y0 + H * 0.028), radius=int(W * 0.008), fill=(78, 45, 30, 255))
        for leg in (x0 + W * 0.012, x1 - W * 0.020):
            draw.rectangle((leg, y0 + H * 0.028, leg + W * 0.008, y0 + H * 0.173), fill=(56, 30, 22, 255))
        for index in range(4):
            book_width = W * (0.075 - 0.008 * index)
            y = y0 - H * 0.022 * (index + 1)
            color = [(132, 69, 56), (77, 97, 84), (102, 77, 120), (166, 128, 74)][index]
            draw.rectangle(((x0 + x1) / 2 - book_width * 0.5, y, (x0 + x1) / 2 + book_width * 0.5, y + H * 0.022), fill=(*color, 235))
        cx, cy = x1 - W * 0.020, y0 - H * 0.010
        draw.rectangle((cx - W * 0.007, cy - H * 0.035, cx + W * 0.007, cy), fill=(224, 209, 178, 255))
        draw.ellipse((cx - W * 0.006, cy - H * 0.056, cx + W * 0.006, cy - H * 0.036), fill=(255, 210, 112, 235))

    image.alpha_composite(soft_layer(table, blur=1.0))

    # Rug.
    def rug(draw):
        draw.ellipse((W * 0.180, H * 0.900, W * 0.800, H * 1.000), fill=(79, 41, 49, 190))
        draw.ellipse((W * 0.205, H * 0.912, W * 0.775, H * 0.986), outline=(194, 143, 98, 70), width=4)

    image.alpha_composite(soft_layer(rug, blur=2.0))

    # Potted fern.
    def fern(draw):
        rng = random.Random(137)
        px, py = W * 0.865, H * 0.845
        draw.rounded_rectangle((px - W * 0.030, py - H * 0.055, px + W * 0.030, py + H * 0.005), radius=int(W * 0.010), fill=(107, 56, 41, 255))
        for index in range(13):
            angle = -2.6 + 5.2 * index / 12
            length = H * rng.uniform(0.070, 0.130)
            draw.line(
                (px, py - H * 0.052, px + math.cos(angle) * length * 0.7, py - H * 0.052 + math.sin(angle) * length),
                fill=(41, 77, 56, 235), width=4,
            )

    image.alpha_composite(soft_layer(fern, blur=0.9))

    # Dust and drifting pages in the lamplight.
    def motes(draw):
        rng = random.Random(138)
        for _ in range(90):
            x = rng.uniform(W * 0.24, W * 0.82)
            y = rng.uniform(H * 0.18, H * 0.82)
            r = rng.uniform(0.8, 2.4)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 219, 158, rng.randint(20, 80)))
        for _ in range(14):
            x = rng.uniform(W * 0.32, W * 0.76)
            y = rng.uniform(H * 0.18, H * 0.80)
            size = W * rng.uniform(0.005, 0.012)
            draw.rounded_rectangle((x - size * 0.5, y - size * 0.36, x + size * 0.5, y + size * 0.36), radius=2, fill=(244, 230, 198, 90))

    image.alpha_composite(soft_layer(motes, blur=1.6))
    return image




def sunset_drive() -> Image.Image:
    image = vertical_gradient((28, 34, 70), (255, 184, 122))
    image.alpha_composite(radial_glow((W * 0.66, H * 0.46), W * 0.58, (255, 150, 78), 0.46))
    image.alpha_composite(radial_glow((W * 0.66, H * 0.46), W * 0.20, (255, 220, 160), 0.50))

    horizon = H * 0.615
    sun_x, sun_y = W * 0.66, H * 0.462

    # The sun, soft and low.
    image.alpha_composite(radial_glow((sun_x, sun_y), W * 0.062, (255, 242, 204), 1.0, power=1.35))
    image.alpha_composite(radial_glow((sun_x, sun_y), W * 0.032, (255, 252, 234), 1.0, power=1.6))

    # High, warm clouds.
    def clouds(draw):
        rng = random.Random(301)
        for _ in range(10):
            cx = rng.uniform(W * 0.04, W * 0.96)
            cy = rng.uniform(H * 0.07, H * 0.40)
            cw = rng.uniform(W * 0.10, W * 0.30)
            ch = cw * rng.uniform(0.14, 0.26)
            color = rng.choice([(255, 208, 166, 120), (246, 184, 154, 100), (255, 226, 188, 110)])
            for lobe in range(4):
                lx = cx + cw * (lobe / 3 - 0.5) * 0.72
                ly = cy + ch * rng.uniform(-0.22, 0.22)
                rw = cw * rng.uniform(0.26, 0.46)
                rh = ch * rng.uniform(0.8, 1.35)
                draw.ellipse((lx - rw / 2, ly - rh / 2, lx + rw / 2, ly + rh / 2), fill=color)

    image.alpha_composite(soft_layer(clouds, blur=16))

    # A few gulls.
    def gulls(draw):
        rng = random.Random(305)
        for _ in range(5):
            x = rng.uniform(W * 0.20, W * 0.80)
            y = rng.uniform(H * 0.20, H * 0.40)
            span = rng.uniform(W * 0.004, W * 0.008)
            draw.arc((x - span, y - span * 0.55, x, y + span * 0.25), 200, 340, fill=(60, 44, 48, 110), width=3)
            draw.arc((x, y - span * 0.55, x + span, y + span * 0.25), 200, 340, fill=(60, 44, 48, 110), width=3)

    image.alpha_composite(soft_layer(gulls, blur=0.6))

    # The sea, held between the headlands.
    sea = vertical_gradient((248, 186, 134), (10, 36, 54))
    sea_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(sea_mask).rectangle((0, int(horizon), W, H), fill=255)
    image.paste(sea, (0, 0), sea_mask)

    # Far headlands.
    def headlands(draw):
        draw.polygon(
            [(0, horizon), (0, H * 0.556), (W * 0.10, H * 0.538), (W * 0.22, H * 0.566),
             (W * 0.34, H * 0.592), (W * 0.40, horizon)],
            fill=(78, 50, 60, 225),
        )
        draw.polygon(
            [(W, horizon), (W, H * 0.532), (W * 0.90, H * 0.548), (W * 0.80, H * 0.578), (W * 0.72, horizon)],
            fill=(64, 42, 56, 235),
        )
        draw.polygon(
            [(0, horizon), (0, H * 0.585), (W * 0.06, H * 0.600), (W * 0.14, horizon)],
            fill=(60, 40, 50, 200),
        )

    image.alpha_composite(soft_layer(headlands, blur=2.4))

    # Warm haze along the horizon.
    def horizon_haze(draw):
        draw.rectangle((0, horizon - H * 0.020, W, horizon + H * 0.030), fill=(255, 198, 146, 90))

    image.alpha_composite(soft_layer(horizon_haze, blur=22))

    # Sun path on the water.
    def glints(draw):
        rng = random.Random(302)
        for index in range(80):
            progress = index / 80
            y = horizon + (H * 0.86 - horizon) * progress
            width = W * (0.010 + 0.090 * progress) * rng.uniform(0.35, 1.0)
            x = sun_x + rng.uniform(-W * 0.010, W * 0.010)
            draw.line(
                (x - width / 2, y, x + width / 2, y),
                fill=(255, 226, 178, rng.randint(20, 70)),
                width=max(2, int(2 + 4 * progress)),
            )

    image.alpha_composite(soft_layer(glints, blur=1.6))

    # Broad, slow swells.
    def swells(draw):
        rng = random.Random(306)
        for _ in range(40):
            y = rng.uniform(horizon + H * 0.02, H * 0.90)
            length = rng.uniform(W * 0.03, W * 0.18)
            x = rng.uniform(0, W)
            draw.line((x, y, x + length, y), fill=(220, 240, 244, rng.randint(10, 26)), width=2)

    image.alpha_composite(soft_layer(swells, blur=1.4))

    # A sail far out.
    def boat(draw):
        bx, by = W * 0.318, horizon - H * 0.004
        draw.polygon([(bx - W * 0.006, by), (bx + W * 0.006, by), (bx + W * 0.003, by + H * 0.0032), (bx - W * 0.003, by + H * 0.0032)], fill=(44, 36, 40, 150))
        draw.polygon([(bx, by - H * 0.020), (bx, by - H * 0.001), (bx + W * 0.0075, by - H * 0.001)], fill=(255, 244, 220, 130))

    image.alpha_composite(soft_layer(boat, blur=0.6))

    # Near cliff on the left.
    def cliff(draw):
        draw.polygon(
            [(0, H), (0, H * 0.635), (W * 0.07, H * 0.620), (W * 0.18, H * 0.700),
             (W * 0.25, H * 0.770), (W * 0.30, H * 0.905), (W * 0.20, H)],
            fill=(44, 34, 36, 255),
        )
        draw.line(
            (0, H * 0.635, W * 0.07, H * 0.620, W * 0.18, H * 0.700,
             W * 0.25, H * 0.770, W * 0.30, H * 0.905),
            fill=(255, 188, 112, 95), width=5,
        )

    image.alpha_composite(soft_layer(cliff, blur=1.8))

    # Grass catching the last light.
    def grass(draw):
        rng = random.Random(307)
        for index in range(26):
            t = index / 25
            bx = W * (0.010 + 0.255 * t)
            by = H * (0.648 + 0.240 * t * t)
            hgt = H * rng.uniform(0.006, 0.014)
            lean = rng.uniform(-W * 0.003, W * 0.003)
            draw.line((bx, by, bx + lean, by - hgt), fill=(120, 102, 64, 90), width=2)

    image.alpha_composite(soft_layer(grass, blur=0.6))

    # The coastal road.
    vx, vy = W * 0.550, H * 0.618
    road_points = [(W * 0.090, H), (vx - W * 0.008, vy), (vx + W * 0.008, vy), (W * 0.910, H)]
    road_gradient = vertical_gradient((88, 70, 64), (30, 28, 34))
    road_mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(road_mask).polygon(road_points, fill=255)
    image.paste(road_gradient, (0, 0), road_mask)

    # Warm haze where the road meets the sun.
    road_glow = radial_glow((vx, vy), W * 0.30, (255, 180, 110), 0.42)
    road_glow.putalpha(Image.composite(road_glow.getchannel("A"), Image.new("L", (W, H), 0), road_mask))
    image.alpha_composite(road_glow)

    def road_edges(draw):
        draw.line((vx - W * 0.008, vy, W * 0.090, H), fill=(255, 220, 172, 140), width=5)
        draw.line((vx + W * 0.008, vy, W * 0.910, H), fill=(255, 220, 172, 120), width=4)
        for index in range(18):
            t = index / 18
            depth = t * t
            y = vy + (H * 0.945 - vy) * depth
            cx = vx + (W * 0.500 - vx) * depth
            dw = W * (0.0012 + 0.0085 * depth)
            dh = H * (0.0035 + 0.032 * depth)
            draw.polygon(
                [(cx - dw / 2, y), (cx + dw / 2, y), (cx + dw * 0.7, y + dh), (cx - dw * 0.7, y + dh)],
                fill=(255, 234, 178, int(55 + 175 * depth)),
            )

    image.alpha_composite(soft_layer(road_edges, blur=0.7))

    # A small car ahead, tail lights warm.
    def car(draw):
        depth = 0.16
        cx = vx + (W * 0.500 - vx) * depth
        cy = vy + (H * 0.945 - vy) * depth
        cw = W * (0.010 + 0.030 * depth)
        ch = H * (0.008 + 0.022 * depth)
        draw.polygon(
            [(cx - cw * 0.5, cy), (cx - cw * 0.38, cy - ch), (cx + cw * 0.38, cy - ch), (cx + cw * 0.5, cy)],
            fill=(24, 22, 26, 235),
        )
        for side in (-1, 1):
            lx = cx + side * cw * 0.34
            ly = cy - ch * 0.34
            draw.ellipse((lx - cw * 0.055, ly - ch * 0.10, lx + cw * 0.055, ly + ch * 0.10), fill=(255, 92, 62, 235))

    image.alpha_composite(soft_layer(car, blur=0.5))

    # Guardrail on the sea side.
    def guardrail(draw):
        draw.line((vx + W * 0.012, vy - H * 0.002, W * 0.905, H * 0.900), fill=(226, 214, 190, 90), width=4)
        for index in range(16):
            t = index / 16
            depth = t * t
            y = vy + (H * 0.945 - vy) * depth
            x = vx + (W * 0.905 - vx) * depth
            ph = H * (0.004 + 0.046 * depth)
            draw.line((x, y, x, y - ph), fill=(28, 30, 34, 225), width=max(2, int(2 + 5 * depth)))

    image.alpha_composite(soft_layer(guardrail, blur=0.6))

    # Cypress silhouettes along the land side.
    def cypress(draw):
        rng = random.Random(303)
        for index in range(11):
            t = index / 11
            depth = t * t
            y = vy + (H * 0.955 - vy) * depth
            x = vx + (W * 0.150 - vx) * depth
            th = H * (0.012 + 0.260 * depth)
            tw = th * (0.10 + 0.035 * rng.random())
            draw.polygon(
                [
                    (x, y),
                    (x - tw * 0.52, y - th * 0.10),
                    (x - tw * 0.78, y - th * 0.55),
                    (x, y - th),
                    (x + tw * 0.78, y - th * 0.55),
                    (x + tw * 0.52, y - th * 0.10),
                ],
                fill=(16, 26, 30, 240),
            )
            draw.line(
                (x, y - th, x + tw * 0.78, y - th * 0.55, x + tw * 0.52, y - th * 0.10),
                fill=(255, 180, 100, int(34 + 50 * depth)), width=max(1, int(1 + 3 * depth)),
            )

    image.alpha_composite(soft_layer(cypress, blur=0.7))

    # The dashboard, warm with reflected light.
    def dashboard(draw):
        draw.polygon(
            [(0, H), (0, H * 0.892), (W * 0.20, H * 0.878), (W * 0.50, H * 0.868),
             (W * 0.80, H * 0.878), (W, H * 0.892), (W, H)],
            fill=(26, 24, 30, 255),
        )
        draw.line(
            (W * 0.03, H * 0.892, W * 0.50, H * 0.868, W * 0.97, H * 0.892),
            fill=(255, 178, 104, 110), width=6,
        )

        # Instrument cluster.
        cx0, cy0, cx1, cy1 = W * 0.150, H * 0.905, W * 0.350, H * 0.975
        draw.rounded_rectangle((cx0, cy0, cx1, cy1), radius=int(H * 0.012), fill=(12, 12, 18, 235))
        for index in range(2):
            gx = cx0 + (cx1 - cx0) * (0.30 + 0.40 * index)
            gy = (cy0 + cy1) / 2
            gr = (cy1 - cy0) * 0.36
            draw.arc((gx - gr, gy - gr, gx + gr, gy + gr), 150, 390, fill=(255, 186, 116, 80), width=3)

        # Steering wheel.
        wc = (W * 0.245, H * 1.055)
        wr = W * 0.155
        draw.arc(
            (wc[0] - wr, wc[1] - wr, wc[0] + wr, wc[1] + wr),
            196, 344, fill=(46, 42, 46, 255), width=int(W * 0.024),
        )
        draw.arc(
            (wc[0] - wr * 0.93, wc[1] - wr * 0.93, wc[0] + wr * 0.93, wc[1] + wr * 0.93),
            202, 338, fill=(255, 190, 120, 70), width=3,
        )

        # Stereo.
        sx0, sy0, sx1, sy1 = W * 0.585, H * 0.922, W * 0.795, H * 0.976
        draw.rounded_rectangle((sx0, sy0, sx1, sy1), radius=int(H * 0.012), fill=(12, 12, 18, 255), outline=(255, 184, 108, 70), width=3)
        dx0, dy0, dx1, dy1 = sx0 + W * 0.022, sy0 + H * 0.012, sx1 - W * 0.022, sy1 - H * 0.012
        draw.rounded_rectangle((dx0, dy0, dx1, dy1), radius=int(H * 0.005), fill=(122, 58, 40, 255))
        for index in range(9):
            bx = dx0 + (dx1 - dx0) * (0.10 + 0.80 * index / 8)
            bh = (dy1 - dy0) * (0.20 + 0.55 * ((index * 3) % 5) / 5)
            draw.rounded_rectangle(
                (bx - (dx1 - dx0) * 0.012, (dy0 + dy1) / 2 - bh / 2,
                 bx + (dx1 - dx0) * 0.012, (dy0 + dy1) / 2 + bh / 2),
                radius=2, fill=(255, 220, 158, 210),
            )
        for side in (0, 1):
            kx = sx0 + (sx1 - sx0) * (0.065 + 0.870 * side)
            ky = (sy0 + sy1) / 2
            kr = (sy1 - sy0) * 0.24
            draw.ellipse((kx - kr, ky - kr, kx + kr, ky + kr), fill=(34, 32, 38, 255), outline=(255, 188, 112, 80), width=2)

    image.alpha_composite(soft_layer(dashboard, blur=0.8))

    # Golden motes in the open air.
    def motes(draw):
        rng = random.Random(304)
        for _ in range(120):
            x = rng.uniform(W * 0.05, W * 0.95)
            y = rng.uniform(H * 0.10, H * 0.86)
            r = rng.uniform(0.8, 2.6)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 216, 150, rng.randint(20, 80)))

    image.alpha_composite(soft_layer(motes, blur=1.4))
    return image


def seaside_records() -> Image.Image:
    image = vertical_gradient((58, 42, 34), (22, 19, 18))
    image.alpha_composite(radial_glow((W * 0.30, H * 0.20), W * 0.52, (255, 220, 168), 0.34))
    image.alpha_composite(radial_glow((W * 0.74, H * 0.72), W * 0.36, (255, 176, 108), 0.20))

    # Sea view beyond the window.
    frame = (int(W * 0.055), int(H * 0.105), int(W * 0.585), int(H * 0.660))
    ImageDraw.Draw(image).rounded_rectangle(frame, radius=34, fill=(72, 50, 38, 255))
    glass_box = (frame[0] + 22, frame[1] + 22, frame[2] - 22, frame[3] - 22)
    glass = vertical_gradient((206, 190, 168), (70, 132, 146))
    paste_rounded(image, glass, glass_box, 18)

    gx0, gy0, gx1, gy1 = glass_box
    gw, gh = gx1 - gx0, gy1 - gy0
    horizon = gy0 + gh * 0.46

    def sea(draw):
        rng = random.Random(211)
        # Warm low sun.
        sun_x, sun_y, sun_r = gx0 + gw * 0.72, gy0 + gh * 0.34, W * 0.028
        draw.ellipse((sun_x - sun_r, sun_y - sun_r, sun_x + sun_r, sun_y + sun_r), fill=(255, 238, 198, 235))
        # Sea bands.
        for index in range(6):
            y = horizon + (gy1 - horizon) * (index / 6)
            color = [(96, 146, 154), (84, 132, 144), (72, 118, 132), (62, 104, 120), (52, 90, 108), (42, 76, 96)][index]
            draw.rectangle((gx0, y, gx1, y + (gy1 - horizon) / 5), fill=(*color, 255))
        # Sun path and wave glints.
        for index in range(34):
            progress = index / 34
            y = horizon + (gy1 - horizon) * progress
            width = gw * (0.010 + 0.080 * progress) * rng.uniform(0.4, 1.0)
            x = sun_x + rng.uniform(-gw * 0.010, gw * 0.010)
            draw.line((x - width * 0.5, y, x + width * 0.5, y), fill=(255, 226, 176, rng.randint(18, 58)), width=2)
        # Horizon line and a distant sail.
        draw.line((gx0, horizon, gx1, horizon), fill=(250, 230, 196, 90), width=2)
        sx, sy = gx0 + gw * 0.30, horizon - gh * 0.010
        draw.polygon([(sx, sy - gh * 0.030), (sx, sy), (sx + gw * 0.018, sy)], fill=(250, 242, 226, 210))
        draw.line((sx, sy, sx, sy - gh * 0.034), fill=(40, 38, 34, 180), width=2)

    image.alpha_composite(soft_layer(sea, blur=1.2))

    def window_detail(draw):
        draw.line((gx0 + gw * 0.50, gy0, gx0 + gw * 0.50, gy1), fill=(64, 44, 34, 255), width=16)
        draw.line((gx0, gy0 + gh * 0.52, gx1, gy0 + gh * 0.52), fill=(64, 44, 34, 255), width=14)
        draw.polygon(
            [(gx0 + gw * 0.08, gy1), (gx0 + gw * 0.40, gy0), (gx0 + gw * 0.50, gy0), (gx0 + gw * 0.18, gy1)],
            fill=(255, 255, 255, 12),
        )

    image.alpha_composite(soft_layer(window_detail, blur=0.6))
    ImageDraw.Draw(image).rounded_rectangle(frame, radius=34, outline=(172, 128, 88, 90), width=6)

    # Curtains at the edges of the window.
    def curtains(draw):
        for x0, x1 in [(frame[0] - W * 0.030, frame[0] + W * 0.026), (frame[2] - W * 0.026, frame[2] + W * 0.030)]:
            draw.rounded_rectangle((x0, frame[1] - H * 0.025, x1, frame[3] + H * 0.045), radius=18, fill=(122, 82, 60, 235))
            for fold in range(3):
                fx = x0 + (x1 - x0) * (0.22 + fold * 0.26)
                draw.line((fx, frame[1], fx, frame[3] + H * 0.04), fill=(0, 0, 0, 45), width=4)

    image.alpha_composite(soft_layer(curtains, blur=1.4))

    # Record shelves on the right wall.
    def shelves(draw):
        rng = random.Random(212)
        shelf = (W * 0.625, H * 0.135, W * 0.965, H * 0.690)
        draw.rounded_rectangle(shelf, radius=int(W * 0.008), fill=(54, 34, 26, 255))
        x0, y0, x1, y1 = shelf
        for row in range(4):
            row_y = y0 + (y1 - y0) * (0.245 + 0.235 * row)
            draw.rectangle((x0 + W * 0.008, row_y, x1 - W * 0.008, row_y + H * 0.007), fill=(36, 22, 18, 255))
            cursor = x0 + W * 0.014
            for record in range(11):
                width = W * rng.uniform(0.012, 0.024)
                height = (y1 - y0) * rng.uniform(0.14, 0.20)
                if cursor + width > x1 - W * 0.012:
                    break
                color = rng.choice([(152, 78, 64), (86, 112, 104), (110, 92, 130), (196, 154, 96), (74, 94, 118), (168, 104, 88)])
                draw.rectangle((cursor, row_y - height, cursor + width, row_y), fill=(*color, 235))
                draw.line((cursor + width * 0.5, row_y - height, cursor + width * 0.5, row_y), fill=(0, 0, 0, 28), width=1)
                cursor += width + W * 0.0012

    image.alpha_composite(soft_layer(shelves, blur=0.7))

    # Pendant lamp.
    image.alpha_composite(radial_glow((W * 0.43, H * 0.215), W * 0.060, (255, 196, 118), 0.30))

    def lamp(draw):
        cx = W * 0.43
        draw.line((cx, 0, cx, H * 0.145), fill=(0, 0, 0, 120), width=4)
        draw.polygon([(cx - W * 0.048, H * 0.188), (cx, H * 0.126), (cx + W * 0.048, H * 0.188)], fill=(186, 118, 62, 255))
        draw.ellipse((cx - W * 0.016, H * 0.182, cx + W * 0.016, H * 0.194), fill=(255, 238, 194, 235))

    image.alpha_composite(soft_layer(lamp, blur=1.1))

    # Counter with turntable and records.
    def counter(draw):
        draw.rounded_rectangle((W * 0.045, H * 0.735, W * 0.960, H * 1.02), radius=34, fill=(78, 50, 36, 255))
        draw.line((W * 0.045, H * 0.738, W * 0.960, H * 0.738), fill=(208, 166, 118, 90), width=4)
        # Turntable plinth.
        draw.rounded_rectangle((W * 0.145, H * 0.775, W * 0.430, H * 0.925), radius=22, fill=(38, 34, 32, 255))
        draw.rounded_rectangle((W * 0.152, H * 0.782, W * 0.423, H * 0.918), radius=18, fill=(58, 50, 44, 255))
        # Vinyl disc.
        cx, cy, r = W * 0.272, H * 0.850, W * 0.058
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(16, 16, 18, 255))
        for groove in range(7):
            gr = r * (0.36 + groove * 0.085)
            draw.ellipse((cx - gr, cy - gr, cx + gr, cy + gr), outline=(64, 62, 66, 70), width=2)
        draw.ellipse((cx - r * 0.30, cy - r * 0.30, cx + r * 0.30, cy + r * 0.30), fill=(186, 86, 58, 255))
        draw.ellipse((cx - r * 0.035, cy - r * 0.035, cx + r * 0.035, cy + r * 0.035), fill=(210, 204, 192, 255))
        # Tonearm.
        draw.line((W * 0.400, H * 0.798, W * 0.300, H * 0.842), fill=(196, 196, 190, 230), width=5)
        draw.ellipse((W * 0.392, H * 0.790, W * 0.410, H * 0.806), fill=(120, 118, 112, 255))
        # Record sleeves leaning on the right.
        rng = random.Random(213)
        for index in range(7):
            x = W * (0.520 + index * 0.040)
            top = H * (0.735 - 0.120 - index * 0.010)
            draw.rounded_rectangle((x, top, x + W * 0.038, H * 0.735), radius=3, fill=(*rng.choice([(148, 76, 64), (82, 110, 104), (104, 88, 126), (188, 146, 92)]), 240))
            draw.ellipse((x + W * 0.008, top + H * 0.014, x + W * 0.030, top + H * 0.050), outline=(0, 0, 0, 45), width=2)
        # A mug.
        mx, my = W * 0.815, H * 0.760
        draw.rounded_rectangle((mx - W * 0.020, my, mx + W * 0.020, my + H * 0.060), radius=8, fill=(196, 178, 150, 255))
        draw.arc((mx + W * 0.012, my + H * 0.010, mx + W * 0.040, my + H * 0.048), 270, 90, fill=(196, 178, 150, 255), width=4)
        draw.ellipse((mx - W * 0.017, my - H * 0.004, mx + W * 0.017, my + H * 0.010), fill=(86, 58, 42, 255))

    image.alpha_composite(soft_layer(counter, blur=0.8))

    # A plant in the near corner.
    def plant(draw):
        rng = random.Random(214)
        px, py = W * 0.940, H * 0.700
        draw.rounded_rectangle((px - W * 0.030, py, px + W * 0.030, py + H * 0.070), radius=10, fill=(104, 62, 44, 255))
        for index in range(15):
            angle = -2.7 + 5.4 * index / 14
            length = H * rng.uniform(0.070, 0.145)
            draw.line((px, py, px + math.cos(angle) * length * 0.70, py + math.sin(angle) * length), fill=(44, 86, 62, 235), width=4)

    image.alpha_composite(soft_layer(plant, blur=0.9))

    # Dust in the window light.
    def motes(draw):
        rng = random.Random(215)
        for _ in range(110):
            x = rng.uniform(W * 0.08, W * 0.62)
            y = rng.uniform(H * 0.14, H * 0.82)
            r = rng.uniform(0.8, 2.5)
            draw.ellipse((x - r, y - r, x + r, y + r), fill=(255, 230, 184, rng.randint(22, 82)))

    image.alpha_composite(soft_layer(motes, blur=1.5))
    return image


GENERATORS = {
    "rainy-cabin": (rainy_cabin, 71),
    "train": (train, 79),
    "sakura-night": (sakura_night, 80),
    "cloud-library": (cloud_library, 81),
    "sunset-drive": (sunset_drive, 82),
    "seaside-records": (seaside_records, 83),
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for identifier, (generator, seed) in GENERATORS.items():
        image = generator()
        image = vignette(image, strength=0.38)
        image = add_grain(image, sigma=1.6, seed=seed)
        path = OUT / f"{identifier}.jpg"
        image.save(path, "JPEG", quality=90, subsampling=0, optimize=True, progressive=True)
        print(f"Wrote {path.relative_to(ROOT)} ({path.stat().st_size / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
