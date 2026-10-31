#!/usr/bin/env python3
"""Generate premium Atmora icon assets — fresh minimalist approach.

Design philosophy:
  * ONE focal element — a soft atmospheric orb (sun/moon/atmosphere)
  * Deep calm gradient background, no text, no waves, no letters
  * Thin horizon line for grounding
  * Plenty of negative space — reads instantly at 16×16, premium at 1024×1024
  * Apple Weather-style simplicity: single shape, harmonious colour

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

# Premium atmospheric palette.
BG_TOP = (14, 18, 30)      # deep midnight indigo
BG_MID = (34, 44, 68)      # soft slate
BG_BOT = (66, 78, 108)     # warm horizon slate
ORB_CORE = (255, 247, 228) # warm cream centre
ORB_MID = (253, 208, 156)  # soft amber
ORB_EDGE = (236, 162, 102) # deeper amber edge
ORB_GLOW = (255, 200, 130, 34)  # soft outer glow
HORIZON = (128, 144, 168, 55)   # faint horizon line


def squircle_mask(size: int, radius_frac: float = 0.24) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    r = size * radius_frac
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=255)
    return mask


def gradient(size, stops):
    w, h = size
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            y0, c0 = stops[i]
            y1, c1 = stops[i + 1]
            if y0 <= t <= y1:
                s = (t - y0) / (y1 - y0)
                r = int(c0[0] + (c1[0] - c0[0]) * s)
                g = int(c0[1] + (c1[1] - c0[1]) * s)
                b = int(c0[2] + (c1[2] - c0[2]) * s)
                d.line([(0, y), (w - 1, y)], fill=(r, g, b))
                break
    return img.convert("RGBA")


def draw_orb(size: int) -> Image.Image:
    """Single soft atmospheric orb on transparent canvas."""
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w, h = size
    cx = w / 2
    cy = h * 0.44   # orb sits slightly above centre, leaving breathing room

    # --- outer glow (large, soft) ---
    glow_r = w * 0.34
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - glow_r, cy - glow_r, cx + glow_r, cy + glow_r],
               fill=ORB_GLOW)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=w * 0.06))
    img.alpha_composite(glow)

    # --- mid glow ---
    mid_r = w * 0.20
    mid = Image.new("RGBA", size, (0, 0, 0, 0))
    md = ImageDraw.Draw(mid)
    md.ellipse([cx - mid_r, cy - mid_r, cx + mid_r, cy + mid_r],
               fill=(*ORB_GLOW[:3], 18))
    mid = mid.filter(ImageFilter.GaussianBlur(radius=w * 0.03))
    img.alpha_composite(mid)

    # --- the orb itself — three-layer gradient circle ---
    orb_r = w * 0.17
    orb = Image.new("RGBA", (int(orb_r * 3), int(orb_r * 3)), (0, 0, 0, 0))
    od = ImageDraw.Draw(orb)
    oh = orb.size[1]
    for yy in range(oh):
        t = yy / (oh - 1)
        if t < 0.45:
            s = t / 0.45
            r = int(ORB_CORE[0] + (ORB_MID[0] - ORB_CORE[0]) * s)
            g = int(ORB_CORE[1] + (ORB_MID[1] - ORB_CORE[1]) * s)
            b = int(ORB_CORE[2] + (ORB_MID[2] - ORB_CORE[2]) * s)
        else:
            s = (t - 0.45) / 0.55
            r = int(ORB_MID[0] + (ORB_EDGE[0] - ORB_MID[0]) * s)
            g = int(ORB_MID[1] + (ORB_EDGE[1] - ORB_MID[1]) * s)
            b = int(ORB_MID[2] + (ORB_EDGE[2] - ORB_MID[2]) * s)
        od.line([(0, yy), (orb.size[0] - 1, yy)], fill=(r, g, b, 255))
    omask = Image.new("L", orb.size, 0)
    odraw = ImageDraw.Draw(omask)
    odraw.ellipse([0, 0, orb.size[0] - 1, orb.size[1] - 1], fill=255)
    orb.putalpha(omask)
    orb = orb.filter(ImageFilter.GaussianBlur(radius=max(0.5, w * 0.004)))
    lx = int(cx - orb_r * 1.5)
    ly = int(cy - orb_r * 1.5)
    img.alpha_composite(orb, dest=(lx, ly))

    # --- subtle inner highlight on orb (premium sheen) ---
    sheen = Image.new("RGBA", size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sheen_r = orb_r * 0.45
    sd.ellipse([cx - sheen_r, cy - orb_r * 0.55, cx + sheen_r * 0.9, cy - orb_r * 0.15],
               fill=(255, 255, 255, 22))
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=w * 0.01))
    img.alpha_composite(sheen)

    # --- thin horizon line (grounding, minimal) ---
    line_y = cy + orb_r * 1.10
    line = Image.new("RGBA", size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    ld.line([w * 0.18, line_y, w * 0.82, line_y],
            fill=HORIZON, width=max(1, int(w * 0.014)))
    line = line.filter(ImageFilter.GaussianBlur(radius=0.6))
    img.alpha_composite(line)

    return img


def make_icns() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    size = 1024
    base = gradient((size, size), [
        (0.0, BG_TOP), (0.42, BG_MID), (1.0, BG_BOT),
    ])
    symbol = draw_orb((size, size))
    base.alpha_composite(symbol)

    mask = squircle_mask(size)
    container = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    container.paste(base, (0, 0))
    container.putalpha(mask)

    # subtle top sheen for premium depth
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.ellipse([size * 0.12, size * 0.03, size * 0.88, size * 0.34],
               fill=(255, 255, 255, 9))
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=size * 0.02))
    container.alpha_composite(highlight)

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
    """Transparent-background orb for the menu bar."""
    symbol = draw_orb((256, 256))
    OUT_MENUBAR.parent.mkdir(parents=True, exist_ok=True)
    symbol.save(OUT_MENUBAR)
    print(f"Wrote {OUT_MENUBAR} ({symbol.size[0]}x{symbol.size[1]})")


def make_app_mark() -> None:
    """High-res orb mark for BrandLockup inside app + menu-bar popover."""
    symbol = draw_orb((512, 512))
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
