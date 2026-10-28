#!/usr/bin/env python3
"""Generates the placeholder pixel art for Forge & Fortune.

    python3 tools/gen_pixel_assets.py

Writes:
  assets/sprites/<name>.png   character sheets, 32x40 px frames
                              rows:    front, back, side (facing right)
                              columns: idle0, idle1, walk0, walk1, walk2, walk3
  assets/sprites/tree.png, bush.png
  assets/textures/<name>.png  32x32 tiling textures (16 px = 1 m in game)

These are stand-ins drawn in code so the game has a consistent pixel style
today. Replace any PNG with hand-made art of the same layout (Aseprite,
a pixel artist, an asset pack) and the game picks it up automatically.
"""
import os
import random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "assets", "sprites")
TEXTURES = os.path.join(ROOT, "assets", "textures")

FW, FH = 32, 40
OUTLINE = (28, 20, 32, 255)


def hexc(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        self.px = self.img.load()

    def dot(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[x, y] = c

    def rect(self, x, y, w, h, c, shaded=False):
        """Filled rect. shaded=True darkens the right column + bottom row."""
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                col = c
                if shaded and (xx == x + w - 1 or yy == y + h - 1):
                    col = shade(c, 0.78)
                self.dot(xx, yy, col)

    def outline(self):
        src = self.img.copy().load()
        for y in range(self.h):
            for x in range(self.w):
                if src[x, y][3] == 0:
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < self.w and 0 <= ny < self.h and src[nx, ny][3] > 0 and src[nx, ny] != OUTLINE:
                            self.px[x, y] = OUTLINE
                            break


# --- Characters ----------------------------------------------------------------

SKIN = hexc("f2c08a")

CHARACTERS = {
    "smith": dict(skin=SKIN, hair=hexc("6b3b1f"), hair_style="short", beard=hexc("6b3b1f"),
                  torso=hexc("e8e2d0"), legs=hexc("4a3b52"), boots=hexc("3a2a20"),
                  apron=hexc("8a5a2e"), weapon="hammer"),
    "warrior": dict(skin=SKIN, hair=hexc("c9a14a"), hair_style="short", head="helmet", metal=hexc("a8b0ba"),
                    torso=hexc("b5483b"), legs=hexc("5a4636"), boots=hexc("3a2a20"),
                    plate=hexc("8f98a3"), weapon="sword"),
    "ranger": dict(skin=hexc("e8b483"), hair=hexc("8a5a2e"), hair_style="short", head="hood", hood=hexc("3f7a35"),
                   torso=hexc("5f9e4a"), legs=hexc("6b4a2b"), boots=hexc("4a3020"),
                   belt=hexc("6b4a2b"), weapon="bow"),
    "mage": dict(skin=SKIN, hair=hexc("d8d8e8"), hair_style="short", beard=hexc("d8d8e8"), head="wizard",
                 hat=hexc("3f4ca8"), trim=hexc("ffd27a"),
                 torso=hexc("4f5fbf"), legs=hexc("4f5fbf"), boots=hexc("2e2638"), robe=True, weapon="staff"),
    "rogue": dict(skin=hexc("e0b090"), hair=hexc("2a2030"), hair_style="short", head="hood", hood=hexc("4a3560"),
                  mask=hexc("2a2030"), torso=hexc("6b4f86"), legs=hexc("2e2638"), boots=hexc("1e1828"),
                  belt=hexc("3a2a20"), weapon="dagger"),
    # Villagers
    "barkeep": dict(skin=hexc("e8b483"), hair=hexc("8a3b1f"), hair_style="short", beard=hexc("b5542a"),
                    torso=hexc("8a5a2e"), legs=hexc("3a2a20"), boots=hexc("2a1e18"),
                    apron=hexc("efe8d8"), weapon="none"),
    "merchant": dict(skin=hexc("c98a5a"), hair=hexc("2a2030"), hair_style="short", head="hood", hood=hexc("e08a2e"),
                     torso=hexc("7a3e8a"), legs=hexc("7a3e8a"), boots=hexc("3a2a20"), robe=True,
                     trim=hexc("ffd27a"), belt=hexc("ffd27a"), weapon="none"),
    "guard": dict(skin=SKIN, hair=hexc("4a3020"), hair_style="short", head="helmet", metal=hexc("9aa3ad"),
                  torso=hexc("3e5a9a"), legs=hexc("3a3040"), boots=hexc("2a1e18"),
                  plate=hexc("8f98a3"), weapon="sword"),
}

# Frame -> (upper body bob, left leg lift, right leg lift, arm swing)
FRAMES = [
    (0, 0, 0, 0),    # idle0
    (1, 0, 0, 0),    # idle1 (breathe: upper body sinks 1px)
    (0, 0, 0, 0),    # walk0 contact
    (-1, 1, 0, 1),   # walk1 passing, left leg up
    (0, 0, 0, 0),    # walk2 contact
    (-1, 0, 1, -1),  # walk3 passing, right leg up
]
SIDE_STRIDE = [0, 0, 2, 0, -2, 0]  # side-view leg spread per frame


def draw_weapon(cv, kind, hx, hy, mirror=False):
    """Weapon held in a hand whose top-left pixel is (hx, hy)."""
    d = -1 if mirror else 1
    wood, steel, gold = hexc("7a5230"), hexc("d7dde4"), hexc("c8862f")
    x = hx + (2 if not mirror else -1)
    if kind == "sword":
        for y in range(hy - 13, hy - 1):
            cv.dot(x, y, steel)
        cv.dot(x, hy - 14, shade(steel, 0.85))
        cv.rect(x - 1, hy - 1, 3, 1, gold)
        cv.rect(x, hy, 1, 2, wood)
    elif kind == "staff":
        for y in range(hy - 22, hy + 8):
            cv.dot(x, y, wood)
        cv.rect(x - 1, hy - 25, 3, 3, hexc("6fe3ff"))
        cv.dot(x - 1, hy - 25, hexc("e8ffff"))
    elif kind == "hammer":
        for y in range(hy - 5, hy + 3):
            cv.dot(x, y, wood)
        cv.rect(x - 2 if d > 0 else x - 1, hy - 8, 4, 3, hexc("9aa3ad"), shaded=True)
    elif kind == "dagger":
        for y in range(hy - 4, hy):
            cv.dot(x, y, steel)
        cv.dot(x, hy, gold)
    elif kind == "bow":
        bx = hx + (2 if not mirror else -1)
        pts = [(0, -8), (1, -7), (1, -6), (2, -5), (2, -4), (2, -3), (2, -2), (2, -1), (2, 0), (2, 1), (2, 2), (1, 3), (1, 4), (0, 5)]
        for dx, dy in pts:
            cv.dot(bx + dx * d, hy + dy, hexc("8b5a2b"))
        for dy in range(-7, 5):
            cv.dot(bx, hy + dy, hexc("e8e2d0"))


def draw_head(cv, s, view, oy):
    skin, hair = s["skin"], s["hair"]
    hx, hy = (10, 9 + oy) if view != "side" else (11, 9 + oy)
    hw = 12 if view != "side" else 11
    cv.rect(hx, hy, hw, 13, skin, shaded=True)
    head = s.get("head")

    if view == "front":
        cv.rect(13, 15 + oy, 1, 2, OUTLINE)
        cv.rect(18, 15 + oy, 1, 2, OUTLINE)
        cv.rect(12, 18 + oy, 2, 1, shade(skin, 0.9))  # cheeks
        cv.rect(18, 18 + oy, 2, 1, shade(skin, 0.9))
        if s.get("beard"):
            cv.rect(11, 18 + oy, 10, 4, s["beard"], shaded=True)
            cv.rect(14, 19 + oy, 4, 1, shade(skin, 0.7))  # mouth
        else:
            cv.rect(15, 19 + oy, 2, 1, shade(skin, 0.7))
        if s.get("mask"):
            cv.rect(10, 17 + oy, 12, 5, s["mask"], shaded=True)
        if head is None:
            cv.rect(10, 8 + oy, 12, 4, hair, shaded=True)
            cv.rect(10, 12 + oy, 2, 3, hair)
            cv.rect(20, 12 + oy, 2, 3, hair)
            cv.rect(13, 12 + oy, 3, 1, hair)
    elif view == "back":
        cv.rect(10, 8 + oy, 12, 12, hair, shaded=True)
        for x in (10, 21):  # round off the top corners
            cv.px[x, 8 + oy] = (0, 0, 0, 0)
        cv.rect(11, 19 + oy, 10, 1, shade(hair, 0.85))
        if s.get("beard"):
            cv.rect(10, 20 + oy, 1, 1, s["beard"])
            cv.rect(21, 20 + oy, 1, 1, s["beard"])
    else:  # side, facing right
        cv.rect(19, 15 + oy, 1, 2, OUTLINE)
        cv.rect(21, 17 + oy, 1, 1, shade(skin, 0.85))  # nose
        if s.get("beard"):
            cv.rect(16, 18 + oy, 6, 4, s["beard"], shaded=True)
        if s.get("mask"):
            cv.rect(16, 17 + oy, 6, 5, s["mask"], shaded=True)
        if head is None:
            cv.rect(11, 8 + oy, 11, 4, hair, shaded=True)
            cv.rect(11, 12 + oy, 5, 7, hair, shaded=True)

    if head == "helmet":
        m = s["metal"]
        if view == "front":
            cv.rect(9, 7 + oy, 14, 7, m, shaded=True)
            cv.rect(9, 14 + oy, 2, 6, m, shaded=True)
            cv.rect(21, 14 + oy, 2, 6, m, shaded=True)
            cv.rect(15, 13 + oy, 2, 4, shade(m, 0.85))
            cv.rect(11, 10 + oy, 10, 1, shade(m, 1.15))
        elif view == "back":
            cv.rect(9, 7 + oy, 14, 14, m, shaded=True)
        else:
            cv.rect(10, 7 + oy, 13, 7, m, shaded=True)
            cv.rect(10, 14 + oy, 6, 6, m, shaded=True)
        cv.rect(15, 4 + oy, 2, 3, hexc("b5483b"))  # plume
    elif head == "hood":
        h = s["hood"]
        if view == "front":
            cv.rect(9, 7 + oy, 14, 6, h, shaded=True)
            cv.rect(9, 13 + oy, 2, 9, h, shaded=True)
            cv.rect(21, 13 + oy, 2, 9, h, shaded=True)
            cv.rect(11, 13 + oy, 10, 1, shade(h, 0.6))  # shadow under the hood
        elif view == "back":
            cv.rect(9, 7 + oy, 14, 15, h, shaded=True)
            cv.rect(14, 22 + oy, 4, 3, h)  # hood tail
        else:
            cv.rect(10, 7 + oy, 12, 6, h, shaded=True)
            cv.rect(10, 13 + oy, 7, 9, h, shaded=True)
    elif head == "wizard":
        hat, trim = s["hat"], s["trim"]
        bx = 7 if view != "side" else 8
        cv.rect(bx, 10 + oy, 18 if view != "side" else 17, 2, hat, shaded=True)
        cv.rect(10, 9 + oy, 12, 1, trim)
        widths = [10, 9, 8, 7, 6, 5, 4, 3, 2]
        for i, w in enumerate(widths):
            y = 8 + oy - i
            lean = i // 3
            cv.rect(16 - w // 2 + lean, y, w, 1, hat if w > 2 else shade(hat, 0.85))
        cv.dot(16 + 3, 0 + oy, trim)


def draw_character(s, view, frame):
    cv = Canvas(FW, FH)
    bob, lift_l, lift_r, swing = FRAMES[frame]
    torso, legs, boots, skin = s["torso"], s["legs"], s["boots"], s["skin"]
    robe = s.get("robe", False)

    if view in ("front", "back"):
        # Legs (left/right as seen on screen)
        for lx, lift in ((12, lift_l), (17, lift_r)):
            cv.rect(lx, 32, 3, 5 - lift, legs, shaded=True)
            cv.rect(lx, 37 - lift, 3, 2, boots, shaded=True)
        # Torso / robe
        cv.rect(11, 22 + bob, 10, 10 - bob, torso, shaded=True)
        if robe:
            cv.rect(10, 30 + bob, 12, 7 - bob, torso, shaded=True)
            cv.rect(10, 36, 12, 1, s.get("trim", shade(torso, 0.7)))
        if s.get("plate") and view == "front":
            cv.rect(12, 23 + bob, 8, 5, s["plate"], shaded=True)
        if s.get("apron"):
            if view == "front":
                cv.rect(12, 24 + bob, 8, 10 - bob, s["apron"], shaded=True)
            else:
                cv.rect(13, 22 + bob, 1, 7, s["apron"])  # straps
                cv.rect(18, 22 + bob, 1, 7, s["apron"])
                cv.rect(11, 29 + bob, 10, 1, s["apron"])
        if s.get("belt"):
            cv.rect(11, 29 + bob, 10, 1, s["belt"])
        # Arms
        for ax, sw in ((9, swing), (21, -swing)):
            cv.rect(ax, 22 + bob + sw, 2, 7, torso, shaded=True)
            cv.rect(ax, 29 + bob + sw, 2, 2, skin)
        draw_head(cv, s, view, bob)
        hand_x, hand_y = (21, 29 + bob - swing) if view == "front" else (9, 29 + bob + swing)
        draw_weapon(cv, s["weapon"], hand_x, hand_y, mirror=(view == "back"))
    else:
        stride = SIDE_STRIDE[frame]
        bob_s = bob
        # back leg (darker) then front leg
        cv.rect(14 - stride, 32, 3, 5, shade(legs, 0.75))
        cv.rect(14 - stride, 37, 3, 2, shade(boots, 0.75))
        cv.rect(14 + stride, 32, 3, 5, legs, shaded=True)
        cv.rect(14 + stride, 37, 3, 2, boots, shaded=True)
        cv.rect(12, 22 + bob_s, 8, 10 - bob_s, torso, shaded=True)
        if robe:
            cv.rect(11, 30 + bob_s, 10, 7 - bob_s, torso, shaded=True)
            cv.rect(11, 36, 10, 1, s.get("trim", shade(torso, 0.7)))
        if s.get("apron"):
            cv.rect(18, 24 + bob_s, 2, 10 - bob_s, s["apron"])
        if s.get("plate"):
            cv.rect(16, 23 + bob_s, 4, 5, s["plate"], shaded=True)
        if s.get("belt"):
            cv.rect(12, 29 + bob_s, 8, 1, s["belt"])
        draw_head(cv, s, "side", bob_s)
        arm_x = 15 + stride // 2 * -1
        cv.rect(arm_x, 22 + bob_s, 2, 7, shade(torso, 0.9), shaded=True)
        cv.rect(arm_x, 29 + bob_s, 2, 2, skin)
        draw_weapon(cv, s["weapon"], arm_x, 29 + bob_s)
    cv.outline()
    return cv.img


def make_sheet(name, s):
    sheet = Image.new("RGBA", (FW * 6, FH * 3), (0, 0, 0, 0))
    for row, view in enumerate(["front", "back", "side"]):
        for col in range(6):
            sheet.paste(draw_character(s, view, col), (col * FW, row * FH))
    sheet.save(os.path.join(SPRITES, name + ".png"))


# --- Foliage -----------------------------------------------------------------------

def make_tree():
    rnd = random.Random(3)
    cv = Canvas(48, 64)
    trunk = hexc("6b4a2b")
    cv.rect(21, 40, 6, 23, trunk, shaded=True)
    cv.rect(18, 60, 12, 3, trunk)
    leaves = [hexc("2f6b34"), hexc("3f8a3f"), hexc("5aa84a"), hexc("7cc45a")]
    for (cx, cy, r) in [(24, 22, 17), (14, 30, 11), (34, 30, 11), (24, 12, 11)]:
        for y in range(cy - r, cy + r):
            for x in range(cx - r, cx + r):
                dx, dy = x - cx, y - cy
                if dx * dx + dy * dy <= r * r:
                    light = (-dx - dy) / (2 * r) + rnd.uniform(-0.25, 0.25)
                    idx = 0 if light < -0.3 else 1 if light < 0.1 else 2 if light < 0.45 else 3
                    cv.dot(x, y, leaves[idx])
    cv.outline()
    cv.img.save(os.path.join(SPRITES, "tree.png"))


def make_bush():
    rnd = random.Random(5)
    cv = Canvas(24, 16)
    leaves = [hexc("2f6b34"), hexc("3f8a3f"), hexc("5aa84a")]
    for (cx, cy, r) in [(8, 10, 6), (16, 10, 6), (12, 7, 6)]:
        for y in range(cy - r, cy + r):
            for x in range(cx - r, cx + r):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and y < 16:
                    v = (cx - x + cy - y) / (2 * r) + rnd.uniform(-0.3, 0.3)
                    cv.dot(x, y, leaves[0 if v < -0.2 else 1 if v < 0.3 else 2])
    for _ in range(4):
        cv.dot(rnd.randint(4, 19), rnd.randint(4, 12), hexc("f2d14a"))
    cv.outline()
    cv.img.save(os.path.join(SPRITES, "bush.png"))


# --- Tiling textures (32x32 = 2m x 2m) ------------------------------------------

def tex(name, fn, seed):
    rnd = random.Random(seed)
    img = Image.new("RGBA", (32, 32))
    px = img.load()
    for y in range(32):
        for x in range(32):
            px[x, y] = fn(x, y, rnd)
    img.save(os.path.join(TEXTURES, name + ".png"))


def pick(rnd, cols, weights):
    return rnd.choices(cols, weights)[0]


def wood_floor():
    rnd = random.Random(11)
    offsets = [rnd.randint(0, 31) for _ in range(4)]
    tones = [rnd.uniform(0.9, 1.08) for _ in range(8)]
    base = hexc("8a6242")

    def f(x, y, r):
        plank = y // 8
        if y % 8 == 7:
            return shade(base, 0.55)
        seg = ((x + offsets[plank]) % 32) // 16
        if (x + offsets[plank]) % 16 == 0:
            return shade(base, 0.6)
        c = shade(base, tones[plank * 2 + seg] * r.uniform(0.95, 1.03))
        if (y % 8) in (2, 5) and r.random() < 0.25:
            c = shade(c, 0.9)
        return c
    return f


def plaster(x, y, r):
    return shade(hexc("d8c49e"), r.choices([0.93, 0.97, 1.0, 1.03], [1, 3, 14, 2])[0])


def stone(x, y, r):
    row = y // 8
    off = 8 if row % 2 else 0
    if y % 8 == 7 or (x + off) % 16 == 15:
        return hexc("4a4540")
    return shade(hexc("7d7770"), r.uniform(0.88, 1.06))


def grass(x, y, r):
    # Mostly one flat colour with sparse variation, so it reads as pixel art
    # rather than TV static.
    return pick(r, [hexc("5f8f46"), hexc("57863f"), hexc("6e9e4f"), hexc("4a7638")], [30, 6, 3, 1])


def dirt(x, y, r):
    return pick(r, [hexc("9a7e58"), hexc("917650"), hexc("a88b62"), hexc("6f5a40")], [30, 6, 3, 1])


def roof(x, y, r):
    if y % 6 == 5:
        return hexc("5c2418")
    off = 4 if (y // 6) % 2 else 0
    if (x + off) % 8 == 0:
        return hexc("6a2a1c")
    return shade(hexc("a3412c"), r.uniform(0.9, 1.05))


def dark_wood(x, y, r):
    if x % 8 == 0:
        return hexc("4a3020")
    return shade(hexc("7a5231"), r.uniform(0.88, 1.05) * (0.93 if (y + x // 8 * 5) % 11 == 0 else 1.0))


def iron(x, y, r):
    if x % 16 == 0 or y % 16 == 0:
        return hexc("2e2c2a")
    return shade(hexc("4f4c48"), r.uniform(0.85, 1.1))


def main():
    os.makedirs(SPRITES, exist_ok=True)
    os.makedirs(TEXTURES, exist_ok=True)
    for name, spec in CHARACTERS.items():
        make_sheet(name, spec)
    make_tree()
    make_bush()
    tex("wood_floor", wood_floor(), 1)
    tex("plaster", plaster, 2)
    tex("stone", stone, 3)
    tex("grass", grass, 4)
    tex("dirt", dirt, 5)
    tex("roof", roof, 6)
    tex("dark_wood", dark_wood, 7)
    tex("iron", iron, 8)
    print("pixel assets written to", SPRITES, "and", TEXTURES)


if __name__ == "__main__":
    main()
