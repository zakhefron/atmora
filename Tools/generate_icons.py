#!/usr/bin/env python3
"""Generate Atmora icon assets from the reference Docs/appicon.png.

Uses the checked-in reference icon as the master source and emits:
  * Assets/AppIcon.icns          — Dock / Finder / Launchpad (all sizes)
  * Assets/AppIconMenuBar.png    — top menu bar (transparent bg, colourful)
  * Assets/AppMark.png           — inside app header / menu-bar popover
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
ICONSET = ROOT / "Tools" / "AppIcon.iconset"
OUT_ICNS = ASSETS / "AppIcon.icns"
OUT_MENUBAR = ASSETS / "AppIconMenuBar.png"
OUT_MARK = ASSETS / "AppMark.png"

SRC = ROOT / "Docs" / "appicon.png"

# macOS .icns sizes (base + @2x retina).
SIZES = [16, 32, 128, 256, 512, 1024]


def make_transparent(img: Image.Image) -> Image.Image:
    """Make the near-black background transparent for menu-bar use."""
    img = img.convert("RGBA")
    pixels = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if r < 30 and g < 30 and b < 30:
                pixels[x, y] = (r, g, b, 0)
    return img


def make_icns() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    src = Image.open(SRC).convert("RGBA")
    produced = []
    for s in SIZES:
        img = src.resize((s, s), Image.LANCZOS)
        p = ICONSET / f"icon_{s}x{s}.png"
        img.save(p)
        produced.append(p)
        if s < 1024:
            img2 = src.resize((s * 2, s * 2), Image.LANCZOS)
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
    src = Image.open(SRC).convert("RGBA")
    img = make_transparent(src)
    # One high-res source is enough; NSImage downsamples sharply.
    img = img.resize((256, 256), Image.LANCZOS)
    OUT_MENUBAR.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_MENUBAR)
    print(f"Wrote {OUT_MENUBAR} ({img.size[0]}x{img.size[1]})")


def make_app_mark() -> None:
    src = Image.open(SRC).convert("RGBA")
    img = make_transparent(src)
    img = img.resize((512, 512), Image.LANCZOS)
    OUT_MARK.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT_MARK)
    print(f"Wrote {OUT_MARK} ({img.size[0]}x{img.size[1]})")


def main() -> int:
    make_icns()
    make_menu_bar()
    make_app_mark()
    return 0


if __name__ == "__main__":
    sys.exit(main())
