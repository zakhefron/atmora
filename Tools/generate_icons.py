#!/usr/bin/env python3
"""Generate Atmora's original sun-on-horizon icon assets.

Restores the classic mark that suits the app best:
  * Clean sun as an upper semicircle resting on a precise horizon line
  * Warm sun gradient (pale yellow → amber → deeper amber)
  * Soft reflection lines beneath the sun
  * Dark rounded-square background
  * No text — pure symbol, matches BrandLockup wordmark

Emits:
  * Assets/AppIcon.icns          — Dock / Finder / Launchpad
  * Assets/AppIconMenuBar.png    — top menu bar (transparent, colourful)
  * Assets/AppMark.png           — inside app header / menu-bar popover
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
ICONSET = ROOT / "Tools" / "AppIcon.iconset"
OUT_ICNS = ASSETS / "AppIcon.icns"
OUT_MENUBAR = ASSETS / "AppIconMenuBar.png"
OUT_MARK = ASSETS / "AppMark.png"

# Original brand colours (mirror BrandMark.swift).
SUN_TOP = (252, 240, 209)   # pale cream
SUN_MID = (249, 211, 149)   # warm amber
SUN_BOT = (230, 158, 83)    # deeper amber
BG = (26, 22, 20)           # dark near-black brown
HORIZON = (160, 140, 110, 0.60)   # muted horizon line
REFLECTION = (200, 160, 110, 0.45) # softer reflection
INNER_REFLECTION = (220, 180, 130, 0.35)
OUTER_REFLECTION = (180, 150, 100, 0.22)


def squircle_mask(size: int, radius_frac: float = 0.24) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = size * radius_frac
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask


def draw_symbol(size: int) -> Image.Image:
    """Original sun-on-horizon mark on transparent/dark canvas."""
    img = Image.new("RGBA", size, (*BG, 255))
    d = ImageDraw.Draw(img)
    w, h = size
    cx = w / 2
    horizon_y = h * 0.595
    sun_radius = w * 0.19

    # --- soft glow behind sun ---
    glow_r = w * 0.46
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - glow_r, horizon_y - glow_r, cx + glow_r, horizon_y + glow_r],
               fill=(255, 190, 110, 18))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=w * 0.04))
    img.alpha_composite(glow)

    # --- sun: upper semicircle with vertical gradient ---
    sun = Image.new("RGBA", (int(sun_radius * 3), int(sun_radius * 3)), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sun)
    oh = sun.size[1]
    for yy in range(oh):
        t = yy / (oh - 1)
        if t < 0.5:
            s = t / 0.5
            r = int(SUN_TOP[0] + (SUN_MID[0] - SUN_TOP[0]) * s)
            g = int(SUN_TOP[1] + (SUN_MID[1] - SUN_TOP[1]) * s)
            b = int(SUN_TOP[2] + (SUN_MID[2] - SUN_TOP[2]) * s)
        else:
            s = (t - 0.5) / 0.5
            r = int(SUN_MID[0] + (SUN_BOT[0] - SUN_MID[0]) * s)
            g = int(SUN_MID[1] + (SUN_BOT[1] - SUN_MID[1]) * s)
            b = int(SUN_MID[2] + (SUN_BOT[2] - SUN_MID[2]) * s)
        sd.line([(0, yy), (sun.size[0] - 1, yy)], fill=(r, g, b, 255))
    smask = Image.new("L", sun.size, 0)
    sdraw = ImageDraw.Draw(smask)
    sdraw.ellipse([0, 0, sun.size[0] - 1, sun.size[1] - 1], fill=255)
    # upper semicircle only
    top = Image.new("L", sun.size, 0)
    tdraw = ImageDraw.Draw(top)
    tdraw.pieslice([0, 0, sun.size[0] - 1, sun.size[1] - 1], 180, 360, fill=255)
    sun.putalpha(Image.eval(top, lambda a: a))
    # center sun on horizon
    lx = int(cx - sun_radius)
    ly = int(horizon_y - sun_radius)
    img.alpha_composite(sun, dest=(lx, ly))

    # --- horizon line ---
    line_w = max(1, int(w * 0.032))
    hline = Image.new("RGBA", size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(hline)
    hd.line([w * 0.13, horizon_y, w * 0.87, horizon_y],
            fill=(*HORIZON[:3], int(255 * HORIZON[3])),
            width=line_w)
    hline = hline.filter(ImageFilter.GaussianBlur(radius=0.6))
    img.alpha_composite(hline)

    # --- reflection lines beneath sun ---
    refl = Image.new("RGBA", size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(refl)
    # inner brighter line
    rw = max(0.9, w * 0.026)
    rd.line([w * 0.385, h * 0.735, w * 0.615, h * 0.735],
            fill=(*REFLECTION[:3], int(255 * REFLECTION[3])),
            width=int(rw))
    # outer fainter line (only at larger sizes)
    if w >= 24:
        ow = max(0.8, w * 0.022)
        rd.line([w * 0.44, h * 0.815, w * 0.56, h * 0.815],
                fill=(*OUTER_REFLECTION[:3], int(255 * OUTER_REFLECTION[3])),
                width=int(ow))
    refl = refl.filter(ImageFilter.GaussianBlur(radius=0.6))
    img.alpha_composite(refl)

    return img


def make_icns() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    size = 1024
    base = Image.new("RGBA", (size, size), (*BG, 255))
    symbol = draw_symbol((size, size))
    base.alpha_composite(symbol)

    mask = squircle_mask(size)
    container = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    container.paste(base, (0, 0))
    container.putalpha(mask)

    sizes = [16, 32, 128, 256, 512, 1024]
    produced = []
    for s in sizes:
        img = container.resize((s, s), Image.LANCZOS)
        p = ICONSET / f"icon_{s}x{s}.png"
        img.save(p)
        produced.append(p)
        if s < 1024:
            img2 = container.resize((s * 2, s * 2), Image.LANCZOS)
            p2 = ICONSET / f"icon_{s}x{s}@2x.png"
            img2.save(p2)
            produced.append(p2)

    if OUT_ICNS.exists():
        OUT_ICNS.unlink()
    subprocess.run(
        ["iconutil", "-c", "icns", "-o", str(OUT_ICNS), str(ICONSET)], check=True
    )
    for p in produced:
        p.unlink()
    try:
        ICONSET.rmdir()
    except OSError:
        pass
    print(f"Wrote {OUT_ICNS} ({OUT_ICNS.stat().st_size:,} bytes)")


def make_menu_bar() -> None:
    """Transparent-background mark for the menu bar."""
    symbol = draw_symbol((256, 256))
    OUT_MENUBAR.parent.mkdir(parents=True, exist_ok=True)
    symbol.save(OUT_MENUBAR)
    print(f"Wrote {OUT_MENUBAR} ({symbol.size[0]}x{symbol.size[1]})")


def make_app_mark() -> None:
    """High-res mark for BrandLockup inside app + menu-bar popover."""
    symbol = draw_symbol((512, 512))
    OUT_MARK.parent.mkdir(parents=True, exist_ok=True)
    symbol.save(OUT_MARK)
    print(f"Wrote {OUT_MARK} ({symbol.size[0]}x{symbol.size[1]})")


def main() -> int:
    make_icns()
    make_menu_bar()
    make_app_mark()
    return 0


if __name__ == "__main__":
    sys.exit(main())
