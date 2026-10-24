"""Generates the hand-painted style rickshaw art textures used by the game.

Pure Python (no Pillow needed). Run from the project root:

    python tools/generate_textures.py

Writes PNG files into assets/textures/. The art is drawn at 2x size and
downsampled, which gives cheap anti-aliasing.
"""
import math
import os
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")

# Rickshaw-art palette: loud, saturated, cheerful.
RED = (220, 30, 45)
DEEP_RED = (150, 15, 35)
PINK = (245, 80, 150)
ORANGE = (255, 130, 20)
YELLOW = (255, 210, 30)
GREEN = (20, 160, 70)
LEAF = (40, 140, 40)
BLUE = (30, 90, 220)
NAVY = (15, 25, 80)
SKY = (90, 180, 240)
WHITE = (250, 250, 245)
BLACK = (15, 15, 20)
PURPLE = (120, 40, 170)


class Canvas:
    def __init__(self, w, h, color=(0, 0, 0)):
        self.w, self.h = w, h
        self.px = [list(color) for _ in range(w * h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y * self.w + x] = list(c)

    def get(self, x, y):
        return self.px[y * self.w + x]

    def rect(self, x0, y0, x1, y1, c):
        for y in range(max(0, int(y0)), min(self.h, int(y1))):
            for x in range(max(0, int(x0)), min(self.w, int(x1))):
                self.set(x, y, c)

    def vgradient(self, y0, y1, c0, c1):
        for y in range(int(y0), int(y1)):
            t = (y - y0) / max(1, (y1 - y0 - 1))
            c = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
            for x in range(self.w):
                self.set(x, y, c)

    def ellipse(self, cx, cy, rx, ry, c, angle=0.0):
        r = max(rx, ry)
        ca, sa = math.cos(angle), math.sin(angle)
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                u = dx * ca + dy * sa
                v = -dx * sa + dy * ca
                if (u / rx) ** 2 + (v / ry) ** 2 <= 1.0:
                    self.set(x, y, c)

    def circle(self, cx, cy, r, c):
        self.ellipse(cx, cy, r, r, c)

    def flower(self, cx, cy, size, petals, petal_color, inner_color, center_color, rot=0.0):
        """Classic rickshaw-art flower: ring of petals, inner ring, dotted centre."""
        for i in range(petals):
            a = rot + i * 2 * math.pi / petals
            px = cx + math.cos(a) * size * 0.55
            py = cy + math.sin(a) * size * 0.55
            self.ellipse(px, py, size * 0.5, size * 0.24, petal_color, a)
        for i in range(petals):
            a = rot + (i + 0.5) * 2 * math.pi / petals
            px = cx + math.cos(a) * size * 0.32
            py = cy + math.sin(a) * size * 0.32
            self.ellipse(px, py, size * 0.3, size * 0.14, inner_color, a)
        self.circle(cx, cy, size * 0.24, center_color)
        self.circle(cx, cy, size * 0.12, RED if center_color != RED else YELLOW)
        for i in range(8):
            a = i * math.pi / 4
            self.circle(cx + math.cos(a) * size * 0.18, cy + math.sin(a) * size * 0.18,
                        max(1.0, size * 0.03), WHITE)

    def leaf(self, cx, cy, length, angle, c=LEAF):
        self.ellipse(cx, cy, length, length * 0.32, c, angle)
        # vein
        for i in range(int(-length), int(length)):
            x = cx + math.cos(angle) * i * 0.85
            y = cy + math.sin(angle) * i * 0.85
            self.set(int(x), int(y), (120, 200, 90))

    def star(self, cx, cy, r, c):
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                dx, dy = x + 0.5 - cx, y + 0.5 - cy
                d = math.hypot(dx, dy)
                a = math.atan2(dy, dx)
                lim = r * (0.45 + 0.55 * abs(math.cos(2.5 * a)) ** 3)
                if d <= lim:
                    self.set(x, y, c)

    def border_dots(self, inset, spacing, r, c):
        x = inset
        while x < self.w - inset:
            self.circle(x, inset, r, c)
            self.circle(x, self.h - inset, r, c)
            x += spacing
        y = inset
        while y < self.h - inset:
            self.circle(inset, y, r, c)
            self.circle(self.w - inset, y, r, c)
            y += spacing

    def frame(self, thickness, c):
        t = thickness
        self.rect(0, 0, self.w, t, c)
        self.rect(0, self.h - t, self.w, self.h, c)
        self.rect(0, 0, t, self.h, c)
        self.rect(self.w - t, 0, self.w, self.h, c)

    def downsample(self):
        out = Canvas(self.w // 2, self.h // 2)
        for y in range(out.h):
            for x in range(out.w):
                acc = [0, 0, 0]
                for oy in (0, 1):
                    for ox in (0, 1):
                        p = self.get(x * 2 + ox, y * 2 + oy)
                        acc[0] += p[0]
                        acc[1] += p[1]
                        acc[2] += p[2]
                out.set(x, y, (acc[0] // 4, acc[1] // 4, acc[2] // 4))
        return out

    def save_png(self, path):
        raw = bytearray()
        for y in range(self.h):
            raw.append(0)
            for x in range(self.w):
                raw.extend(bytes(self.get(x, y)))

        def chunk(tag, data):
            c = struct.pack(">I", len(data)) + tag + data
            return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

        png = b"\x89PNG\r\n\x1a\n"
        png += chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
        png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        png += chunk(b"IEND", b"")
        with open(path, "wb") as f:
            f.write(png)


def backboard():
    """The painted tin panel at the back of the rickshaw (seen from the chase camera)."""
    c = Canvas(512, 256)
    c.vgradient(0, 256, (40, 120, 230), NAVY)
    # Hills and a little river scene at the bottom, very common in rickshaw art.
    for x in range(512):
        h = 190 + 18 * math.sin(x * 0.03) + 8 * math.sin(x * 0.11)
        for y in range(int(h), 256):
            c.set(x, y, GREEN)
    for x in range(512):
        for y in range(222, 236):
            if (x // 6 + y // 3) % 5 != 0:
                c.set(x, y, SKY)
    # Big centre flower with leaves.
    for a, l in ((-2.5, 42), (-0.65, 42), (2.2, 34), (0.9, 34)):
        c.leaf(256 + math.cos(a) * 70, 112 + math.sin(a) * 60, l, a)
    c.flower(256, 112, 92, 10, RED, PINK, YELLOW)
    # Side flowers.
    c.flower(110, 104, 54, 6, ORANGE, YELLOW, RED, 0.3)
    c.flower(402, 104, 54, 6, PINK, WHITE, ORANGE, 0.1)
    c.leaf(66, 160, 26, 0.6)
    c.leaf(446, 160, 26, 2.5)
    # Stars sprinkled in the sky.
    for (x, y, col) in ((40, 40, YELLOW), (180, 30, WHITE), (330, 30, WHITE), (470, 42, YELLOW),
                        (60, 200, WHITE), (450, 205, YELLOW), (200, 190, YELLOW), (316, 192, WHITE)):
        c.star(x, y, 11, col)
    # Layered border: red band with white dots, then yellow and green lines.
    c.frame(22, RED)
    c.border_dots(11, 22, 4, WHITE)
    for i, col in enumerate((YELLOW, GREEN)):
        t0 = 22 + i * 6
        c.rect(t0, t0, 512 - t0, t0 + 6, col)
        c.rect(t0, 256 - t0 - 6, 512 - t0, 256 - t0, col)
        c.rect(t0, t0, t0 + 6, 256 - t0, col)
        c.rect(512 - t0 - 6, t0, 512 - t0, 256 - t0, col)
    return c.downsample()


def canopy():
    """The curved hood. v=0 (top of image) is the bottom-back edge, v=1 the front edge."""
    c = Canvas(512, 512, (30, 20, 60))
    # Bottom-back band: zig-zag in red and yellow.
    c.rect(0, 0, 512, 70, RED)
    for x in range(512):
        zig = 20 + abs((x % 64) - 32)
        for y in range(18, 18 + zig // 1):
            if y < 70:
                c.set(x, y, YELLOW)
    c.rect(0, 70, 512, 82, GREEN)
    c.border_dots(-100, 1000, 1, WHITE)  # no-op guard for symmetry
    for x in range(16, 512, 32):
        c.circle(x, 76, 4, WHITE)
    # Main navy field with a big medallion and stars.
    c.vgradient(82, 360, (25, 30, 95), (60, 20, 90))
    c.circle(256, 210, 108, YELLOW)
    c.circle(256, 210, 98, RED)
    c.circle(256, 210, 86, (20, 110, 60))
    c.flower(256, 210, 120, 8, PINK, WHITE, YELLOW)
    for (x, y) in ((70, 130), (440, 130), (90, 300), (420, 300)):
        c.flower(x, y, 56, 6, ORANGE, YELLOW, RED, 0.4)
    for (x, y) in ((150, 110), (362, 110), (40, 220), (472, 220), (160, 330), (352, 330)):
        c.star(x, y, 13, WHITE)
    # Vertical rainbow stripes towards the front, like appliqué strips.
    stripes = (RED, ORANGE, YELLOW, GREEN, BLUE, PURPLE, PINK)
    for i in range(16):
        col = stripes[i % len(stripes)]
        c.rect(i * 32, 360, i * 32 + 32, 470, col)
        c.rect(i * 32 + 13, 360, i * 32 + 19, 470, WHITE)
    # Front edge trim.
    c.rect(0, 470, 512, 512, YELLOW)
    for x in range(8, 512, 24):
        c.circle(x, 491, 7, RED)
    return c.downsample()


def seat_back():
    """Passenger backrest: quilted red vinyl with a white stitched diamond pattern."""
    c = Canvas(256, 256, (200, 20, 60))
    for y in range(256):
        for x in range(256):
            u = (x + y) % 64
            v = (x - y) % 64
            if u < 3 or v < 3:
                c.set(x, y, WHITE)
    c.flower(128, 128, 90, 8, YELLOW, ORANGE, GREEN)
    c.frame(14, GREEN)
    c.border_dots(7, 16, 3, YELLOW)
    return c.downsample()


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in (("rickshaw_backboard.png", backboard),
                     ("rickshaw_canopy.png", canopy),
                     ("rickshaw_seat_back.png", seat_back)):
        path = os.path.join(OUT_DIR, name)
        fn().save_png(path)
        print("wrote", os.path.normpath(path))


if __name__ == "__main__":
    main()
