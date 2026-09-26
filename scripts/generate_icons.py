#!/usr/bin/env python3
"""Renders the Escrow Pay app icon and writes every launcher size.

Pure standard library on purpose: this machine has no ImageMagick, no Pillow
and very little free disk, and an icon generator is not worth a toolchain. PNG
is simple enough to emit directly, and shapes are drawn from signed distance
fields so edges stay smooth without supersampling a 4K buffer.

    python3 scripts/generate_icons.py

Writes brand/ masters, the five Android mipmaps, and the iOS AppIcon set.
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# --- palette, matching lib/theme/palette.dart -------------------------------

VOID = (0x0A, 0x0A, 0x12)
VIOLET = (0x8B, 0x5C, 0xF6)
INDIGO = (0x63, 0x66, 0xF1)
CYAN = (0x22, 0xD3, 0xEE)

MASTER = 1024


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def ramp(t: float) -> tuple[float, float, float]:
    """The accent gradient: violet -> indigo -> cyan."""
    t = min(max(t, 0.0), 1.0)
    if t < 0.5:
        u = t / 0.5
        lo, hi = VIOLET, INDIGO
    else:
        u = (t - 0.5) / 0.5
        lo, hi = INDIGO, CYAN
    return tuple(lerp(lo[i], hi[i], u) for i in range(3))


def sd_round_rect(px, py, cx, cy, hw, hh, r) -> float:
    """Signed distance to a rounded rectangle. Negative inside."""
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def coverage(d: float, aa: float = 1.0) -> float:
    """Distance to alpha, with one pixel of anti-aliasing."""
    return min(max(0.5 - d / aa, 0.0), 1.0)


def render(size: int, *, rounded: bool) -> bytearray:
    """Draws the icon at `size`.

    `rounded` controls the tile corners: Android legacy mipmaps are used as
    supplied so they need their own rounding, while iOS masks the icon itself
    and must be handed a full-bleed square.
    """
    s = size / MASTER  # everything below is authored against a 1024 grid
    px = bytearray(size * size * 4)

    # The mark: a geometric E whose middle arm floats free of the spine. The
    # gap is the point — value held between two parties, touched by neither.
    # Every stroke is 76 units wide with fully rounded ends, so the arms read
    # as one family rather than a spine with decoration.
    spine = (358 * s, 512 * s, 38 * s, 212 * s, 38 * s)
    top = (512 * s, 338 * s, 192 * s, 38 * s, 38 * s)
    middle = (550 * s, 512 * s, 90 * s, 38 * s, 38 * s)
    bottom = (512 * s, 686 * s, 192 * s, 38 * s, 38 * s)

    # The gradient is mapped across the mark's own bounds, not the tile's.
    # Spanning the tile leaves the mark sitting in the middle of the ramp,
    # where it never reaches either end and reads as flat blue.
    mark_x0, mark_span_x = 320 * s, 384 * s
    mark_y0, mark_span_y = 300 * s, 424 * s

    tile_r = 228 * s
    glow_cx, glow_cy = 470 * s, 470 * s
    glow_radius = 430 * s

    for y in range(size):
        fy = y + 0.5
        row = y * size * 4
        for x in range(size):
            fx = x + 0.5

            # Tile.
            if rounded:
                a_tile = coverage(
                    sd_round_rect(fx, fy, size / 2, size / 2,
                                  size / 2, size / 2, tile_r)
                )
            else:
                a_tile = 1.0

            if a_tile <= 0.0:
                row += 4
                continue

            r, g, b = VOID

            # A cool wash behind the mark so the tile is not a flat black
            # square, and the mark has something to sit against.
            gd = math.hypot(fx - glow_cx, fy - glow_cy) / glow_radius
            if gd < 1.0:
                fall = (1.0 - gd) ** 2.2
                r = lerp(r, 0x2A, fall * 0.55)
                g = lerp(g, 0x1E, fall * 0.55)
                b = lerp(b, 0x5C, fall * 0.55)

            # Mark, as the union of its parts.
            a_mark = 0.0
            for shape in (spine, top, middle, bottom):
                a_mark = max(a_mark, coverage(sd_round_rect(fx, fy, *shape)))

            if a_mark > 0.0:
                mt = (((fx - mark_x0) / mark_span_x)
                      + ((fy - mark_y0) / mark_span_y)) / 2
                mr, mg, mb = ramp(mt)
                r = lerp(r, mr, a_mark)
                g = lerp(g, mg, a_mark)
                b = lerp(b, mb, a_mark)

            # A gradient rim, so the icon keeps an edge on a dark wallpaper.
            if rounded:
                d_edge = sd_round_rect(fx, fy, size / 2, size / 2,
                                       size / 2, size / 2, tile_r)
                rim = coverage(abs(d_edge + 1.5 * s * 4) - 1.2 * s * 4)
                if rim > 0.0:
                    er, eg, eb = ramp(((fx / size) + (fy / size)) / 2)
                    r = lerp(r, er, rim * 0.5)
                    g = lerp(g, eg, rim * 0.5)
                    b = lerp(b, eb, rim * 0.5)

            px[row] = int(r)
            px[row + 1] = int(g)
            px[row + 2] = int(b)
            px[row + 3] = int(a_tile * 255)
            row += 4

    return px


def downsample(src: bytearray, src_size: int, dst_size: int) -> bytearray:
    """Box filter. Rendering each size directly would alias the thin rim."""
    if src_size == dst_size:
        return src
    out = bytearray(dst_size * dst_size * 4)
    step = src_size / dst_size
    for y in range(dst_size):
        y0, y1 = int(y * step), max(int((y + 1) * step), int(y * step) + 1)
        for x in range(dst_size):
            x0, x1 = int(x * step), max(int((x + 1) * step), int(x * step) + 1)
            acc = [0, 0, 0, 0]
            n = 0
            for sy in range(y0, y1):
                base = sy * src_size * 4
                for sx in range(x0, x1):
                    i = base + sx * 4
                    # Premultiply so transparent corners do not darken edges.
                    a = src[i + 3] / 255
                    acc[0] += src[i] * a
                    acc[1] += src[i + 1] * a
                    acc[2] += src[i + 2] * a
                    acc[3] += src[i + 3]
                    n += 1
            o = (y * dst_size + x) * 4
            alpha = acc[3] / n
            if alpha > 0:
                scale = 255 / alpha
                out[o] = min(int(acc[0] / n * scale), 255)
                out[o + 1] = min(int(acc[1] / n * scale), 255)
                out[o + 2] = min(int(acc[2] / n * scale), 255)
            out[o + 3] = int(alpha)
    return out


def write_png(path: Path, size: int, px: bytearray) -> None:
    raw = b"".join(
        b"\x00" + bytes(px[y * size * 4:(y + 1) * size * 4]) for y in range(size)
    )

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(
            ">I", zlib.crc32(body) & 0xFFFFFFFF
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


ANDROID = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

IOS = [
    ("Icon-App-20x20@1x.png", 20), ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60), ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58), ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40), ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120), ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180), ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152), ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]


def main() -> None:
    print("rendering masters at 1024 ...")
    master_round = render(MASTER, rounded=True)
    master_square = render(MASTER, rounded=False)

    write_png(ROOT / "brand/icon-master.png", MASTER, master_round)
    write_png(ROOT / "brand/icon-master-square.png", MASTER, master_square)
    print("  brand/icon-master.png, brand/icon-master-square.png")

    for bucket, size in ANDROID.items():
        target = ROOT / f"android/app/src/main/res/mipmap-{bucket}/ic_launcher.png"
        write_png(target, size, downsample(master_round, MASTER, size))
        print(f"  android {bucket} {size}px")

    ios_dir = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if ios_dir.is_dir():
        for name, size in IOS:
            # iOS forbids alpha in app icons and masks the corners itself.
            write_png(ios_dir / name, size,
                      downsample(master_square, MASTER, size))
        print(f"  ios {len(IOS)} sizes")

    print("done")


if __name__ == "__main__":
    main()
