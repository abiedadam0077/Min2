"""Generates the VoxelOps launcher icons (mipmaps) and the 1024px master artwork.

The isometric geometry mirrors lib/core/widgets/voxel_logo.dart so the launcher icon
and the in-app logo stay visually identical.

Usage: python3 tool/generate_icons.py   (requires Pillow)
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SIZE = 1024
SS = 2  # supersampling factor for smooth edges
W = SIZE * SS


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def add(p, q):
    return (p[0] + q[0], p[1] + q[1])


def scale(p, k):
    return (p[0] * k, p[1] * k)


def face_point(origin, uvec, vvec, u, v):
    return add(add(origin, scale(uvec, u)), scale(vvec, v))


def face_polygon(origin, uvec, vvec):
    return [origin, add(origin, uvec), add(add(origin, uvec), vvec), add(origin, vvec)]


def gradient_layer(poly, c0, c1):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(layer)
    ys = [p[1] for p in poly]
    y0, y1 = min(ys), max(ys)
    for y in range(int(y0), int(y1) + 1):
        t = (y - y0) / max(1.0, y1 - y0)
        gd.line([(0, y), (W, y)], fill=lerp(c0, c1, t) + (255,))
    return layer


def paste_clipped(base, layer, poly):
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    base.paste(layer, (0, 0), ImageChops.multiply(mask, layer.getchannel("A")))


def build_master():
    bg = Image.new("RGBA", (W, W))
    bd = ImageDraw.Draw(bg)
    for y in range(W):
        bd.line([(0, y), (W, y)], fill=lerp((14, 22, 52), (7, 11, 31), y / (W - 1)) + (255,))

    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([W * 0.20, W * 0.22, W * 0.80, W * 0.82], fill=(61, 123, 255, 120))
    bg = Image.alpha_composite(bg, glow.filter(ImageFilter.GaussianBlur(W * 0.10)))

    # Isometric cube: L = edge length on screen, a/b = horizontal/vertical projection.
    cx, cy = W / 2, W / 2
    L = W * 0.30
    a, b = L * 0.866, L * 0.5
    C = (cx, cy)  # front corner
    faces = {
        # top: origin C, u towards left-top corner, v towards right-top corner
        "top": (C, (-a, -b), (a, -b), ((150, 190, 255), (84, 146, 255))),
        # left: origin C, u towards left-top, v towards bottom
        "left": (C, (-a, -b), (0, L), ((70, 128, 255), (76, 60, 222))),
        # right: origin C, u towards right-top, v towards bottom
        "right": (C, (a, -b), (0, L), ((120, 70, 240), (150, 100, 250))),
    }

    for name, (origin, uvec, vvec, (c0, c1)) in faces.items():
        poly = face_polygon(origin, uvec, vvec)
        paste_clipped(bg, gradient_layer(poly, c0, c1), poly)

        grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        gd = ImageDraw.Draw(grid)
        width = max(2, int(W * 0.0035))
        for k in (1 / 3, 2 / 3):
            p0 = face_point(origin, uvec, vvec, k, 0)
            p1 = face_point(origin, uvec, vvec, k, 1)
            gd.line([p0, p1], fill=(255, 255, 255, 60), width=width)
            q0 = face_point(origin, uvec, vvec, 0, k)
            q1 = face_point(origin, uvec, vvec, 1, k)
            gd.line([q0, q1], fill=(255, 255, 255, 60), width=width)
        paste_clipped(bg, grid, poly)

    # Server-rack slots with status LEDs on the right face (kept fully inside the face).
    origin, uvec, vvec = faces["right"][0], faces["right"][1], faces["right"][2]
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    led_colors = [(52, 211, 153), (52, 211, 153), (125, 211, 252)]
    for i in range(3):
        v0 = 0.22 + i * 0.22
        v1 = v0 + 0.13
        slot = [
            face_point(origin, uvec, vvec, 0.18, v0),
            face_point(origin, uvec, vvec, 0.82, v0),
            face_point(origin, uvec, vvec, 0.82, v1),
            face_point(origin, uvec, vvec, 0.18, v1),
        ]
        ld.polygon(slot, fill=(20, 16, 60, 150))
        led = face_point(origin, uvec, vvec, 0.27, (v0 + v1) / 2)
        r = W * 0.012
        glow_r = r * 2.6
        ld.ellipse([led[0] - glow_r, led[1] - glow_r, led[0] + glow_r, led[1] + glow_r],
                   fill=led_colors[i] + (70,))
        ld.ellipse([led[0] - r, led[1] - r, led[0] + r, led[1] + r], fill=led_colors[i] + (255,))
    paste_clipped(bg, layer, face_polygon(origin, uvec, vvec))

    # Crisp edge highlight around the silhouette.
    hexagon = [
        add(C, (-a, -b)), add(C, (0, -L)), add(C, (a, -b)),
        add(C, (a, b)), add(C, (0, L)), add(C, (-a, b)),
    ]
    ImageDraw.Draw(bg).line(hexagon + [hexagon[0]], fill=(255, 255, 255, 80), width=max(2, int(W * 0.004)))

    return bg.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")


def main():
    master = build_master()
    out_master = ROOT / "assets" / "images"
    out_master.mkdir(parents=True, exist_ok=True)
    master.save(out_master / "voxelops_icon_1024.png", optimize=True)
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for name, px in densities.items():
        folder = ROOT / "android" / "app" / "src" / "main" / "res" / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)
        master.resize((px, px), Image.LANCZOS).save(folder / "ic_launcher.png", optimize=True)
    print("icons generated")


if __name__ == "__main__":
    main()
