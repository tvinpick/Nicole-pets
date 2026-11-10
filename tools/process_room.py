#!/usr/bin/env python3
"""Builds seamless room textures and the window cut-out from the source room art.

Inputs  (kept untouched):
    assets/rooms/kids/kids_room_side.png    - room without window
    assets/rooms/kids/kids_room_center.png  - same room with a #FF00FF window
Outputs (lossless PNG):
    assets/rooms/kids/wall_tile.png   - wallpaper + cornice + baseboard, tiles horizontally
    assets/rooms/kids/floor_tile.png  - floor planks, tiles horizontally
    assets/rooms/kids/window.png      - window frame + sill with transparent glass

Run:  python3 tools/process_room.py   (needs numpy, scipy, pillow)
"""
from __future__ import annotations

import os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIDS = os.path.join(ROOT, "assets", "rooms", "kids")

FLOOR_Y = 701          # first floor row (same in both source images)
WALLPAPER_Y = (56, 676)  # rows with star wallpaper (between cornice and baseboard)
OVERLAP = 256          # columns used for the wrap-around blend
CROP = (64, 1472)      # drop the darkest outer columns of the source
# plank row boundaries in the source (horizontal dark lines)
PLANK_ROWS = [701, 728, 764, 799, 840, 882, 927, 973, 1024]


def load(name: str) -> np.ndarray:
    return np.asarray(Image.open(os.path.join(KIDS, name)).convert("RGB")).astype(np.float64)


def save(arr: np.ndarray, name: str) -> None:
    mode = "RGBA" if arr.shape[2] == 4 else "RGB"
    Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), mode).save(
        os.path.join(KIDS, name), optimize=True)
    print("wrote", name, arr.shape[1], "x", arr.shape[0])


def star_mask(img: np.ndarray) -> np.ndarray:
    r, b = img[..., 0], img[..., 2]
    m = (r - b) > 100
    m[: WALLPAPER_Y[0]] = False
    m[WALLPAPER_Y[1]:] = False
    m = ndi.binary_opening(m, iterations=1)
    lab, _ = ndi.label(m)
    keep = np.zeros(lab.max() + 1, bool)
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        hh, ww = sl[0].stop - sl[0].start, sl[1].stop - sl[1].start
        keep[i] = 6 <= hh <= 45 and 6 <= ww <= 45   # star-sized blobs only
    m = keep[lab]
    return ndi.binary_dilation(m, iterations=6)


def masked_blur(img: np.ndarray, valid: np.ndarray, sigma) -> np.ndarray:
    w = ndi.gaussian_filter(valid.astype(np.float64), sigma)
    out = np.empty_like(img)
    for c in range(img.shape[2]):
        out[..., c] = ndi.gaussian_filter(img[..., c] * valid, sigma) / np.maximum(w, 1e-6)
    return out


def flatten_vignette(img: np.ndarray, ignore: np.ndarray, sigma) -> np.ndarray:
    """Divides out the low-frequency horizontal brightness falloff (vignette).

    The reference brightness of every row is the mean of its central part, so the
    designed vertical shading (cornice shadow etc.) is kept.
    """
    valid = ~ignore
    prof = masked_blur(img, valid, sigma)
    h, w = img.shape[:2]
    centre = slice(int(w * 0.3), int(w * 0.7))
    target = prof[:, centre].mean(axis=1, keepdims=True)
    return img * (target / np.maximum(prof, 1.0))


def make_wall(side: np.ndarray) -> np.ndarray:
    wall = side[:FLOOR_Y].copy()
    stars = star_mask(wall)
    wall = flatten_vignette(wall, stars, (6.0, 90.0))[:, CROP[0]:CROP[1]]
    stars = stars[:, CROP[0]:CROP[1]]
    h, w = wall.shape[:2]
    # vertical brightness: keep the designed look but remove the extra darkening
    # towards the very top of the wallpaper band (flat across x after flattening).
    wall_px = wall
    bg = wall.copy()
    filled = masked_blur(wall, ~stars, 5.0)
    bg[stars] = filled[stars]

    n = w - OVERLAP
    t = np.linspace(0.0, 1.0, OVERLAP)
    t = t * t * (3 - 2 * t)
    out = bg[:, :n].copy()
    out[:, :OVERLAP] = bg[:, n:] * (1 - t)[None, :, None] + bg[:, :OVERLAP] * t[None, :, None]

    # re-place stars as whole objects (no ghosting), wrapping around the tile
    lab, cnt = ndi.label(stars)
    objs = ndi.find_objects(lab)
    placed: list[tuple[float, float]] = []
    soft_all = ndi.gaussian_filter(stars.astype(np.float64), 1.2)
    cand = []
    for i, sl in enumerate(objs, start=1):
        ys, xs = sl
        cy = (ys.start + ys.stop) / 2
        cx = (xs.start + xs.stop) / 2
        if cx >= n:
            ox = cx - n
            if ox / OVERLAP >= 0.5:
                continue
            shift = -n
        elif cx < OVERLAP:
            if cx / OVERLAP < 0.5:
                continue
            shift = 0
        else:
            shift = 0
        cand.append((i, sl, cx + shift, cy, shift))
    for i, sl, ox, oy, shift in cand:
        if any((ox - px) ** 2 + (oy - py) ** 2 < 40 ** 2 for px, py in placed):
            continue
        placed.append((ox, oy))
        ys, xs = sl
        y0, y1 = max(ys.start - 3, 0), min(ys.stop + 3, h)
        x0, x1 = max(xs.start - 3, 0), min(xs.stop + 3, w)
        a = soft_all[y0:y1, x0:x1] * (lab[y0:y1, x0:x1] == i).astype(np.float64)
        a = np.clip(ndi.gaussian_filter((lab[y0:y1, x0:x1] == i).astype(np.float64), 1.0) * 1.6, 0, 1)
        src = wall_px[y0:y1, x0:x1]
        for dx in range(x1 - x0):
            ox_col = (x0 + dx + shift) % n
            col = out[y0:y1, ox_col]
            out[y0:y1, ox_col] = col * (1 - a[:, dx, None]) + src[:, dx] * a[:, dx, None]
    return out


def make_floor(side: np.ndarray) -> np.ndarray:
    floor = side[FLOOR_Y:].copy()
    none = np.zeros(floor.shape[:2], bool)
    floor = flatten_vignette(floor, none, (2.0, 220.0))[:, CROP[0]:CROP[1]]
    h, w = floor.shape[:2]
    n = w - OVERLAP
    out = floor[:, :n].copy()
    # per plank band: a hard cut drawn as a new plank joint, placed away from
    # the existing joints of both copies and staggered against the previous band
    lum = floor.mean(axis=2)
    prev = prev2 = -1000
    pref = [60, 200, 120, 30, 170, 90, 220, 140]
    for bi in range(len(PLANK_ROWS) - 1):
        y0, y1 = PLANK_ROWS[bi] - FLOOR_Y, PLANK_ROWS[bi + 1] - FLOOR_Y
        prof = lum[y0 + 4:y1 - 3].mean(axis=0)
        local = ndi.uniform_filter1d(prof, 15)
        joints = np.nonzero(prof < local - 8)[0]
        best, best_score = 128, -1.0
        for c in range(24, OVERLAP - 24, 2):
            out_joints = [j for j in joints if c <= j < n] + [j - n for j in joints if n <= j < n + c]
            dmin = min([abs(c - j) for j in out_joints] + [abs(c - (j - n)) for j in joints if j >= n] + [999])
            # distance to joints across the wrap as well
            dmin = min(dmin, min([abs(c - j) for j in joints if j < OVERLAP] + [999]))
            score = (min(dmin, 120) + min(abs(c - prev), 90) * 0.7 + min(abs(c - prev2), 60) * 0.5
                     - abs(c - pref[bi % len(pref)]) * 0.15)
            if score > best_score:
                best, best_score = c, score
        c = best
        prev2, prev = prev, c
        out[y0:y1, :c] = floor[y0:y1, n:n + c]
        for k in range(-2, 3):
            tt = (k + 2.5) / 5.0
            out[y0:y1, c + k] = floor[y0:y1, n + c + k] * (1 - tt) + floor[y0:y1, c + k] * tt
        line_y = slice(y0 + 2, y1 - 1)
        out[line_y, c - 1] *= 0.80
        out[line_y, c] *= 0.62
        out[line_y, c + 1] *= 0.85
    return out


def make_window(center: np.ndarray) -> np.ndarray:
    h, w = center.shape[:2]
    r, g, b = center[..., 0], center[..., 1], center[..., 2]
    # magenta-ness: 1 for #FF00FF, 0 for normal colours
    mag = np.clip((np.minimum(r, b) - g + 30) / 285.0, 0, 1)
    glass = ndi.binary_closing(mag > 0.5, iterations=2)
    glass = ndi.binary_fill_holes(glass)
    ys, xs = np.nonzero(glass)
    gx0, gx1, gy0, gy1 = xs.min(), xs.max(), ys.min(), ys.max()

    # the frame's dark outer outline: scan each row from outside inwards
    dark = (r < 215) & (g < 165) & (b < 125) & (mag < 0.2)
    left = np.full(h, -1)
    right = np.full(h, -1)
    for y in range(20, 640):
        row = dark[y, 360:gx0 - 5]
        idx = np.nonzero(row)[0]
        if len(idx):
            left[y] = 360 + idx[0]
        row = dark[y, gx1 + 5:1180]
        idx = np.nonzero(row)[0]
        if len(idx):
            right[y] = gx1 + 5 + idx[-1]
    # top arch: per column, first dark pixel from the top below the cornice
    top = np.full(w, 10 ** 6)
    for x in range(360, 1180):
        col = dark[58:gy0 + 40, x]
        idx = np.nonzero(col)[0]
        if len(idx):
            top[x] = 58 + idx[0]
    return glass, mag, (gx0, gx1, gy0, gy1), left, right, top, dark


def build_window(center: np.ndarray) -> np.ndarray:
    glass, mag, (gx0, gx1, gy0, gy1), left, right, top, dark = make_window(center)
    h, w = center.shape[:2]
    cx = (gx0 + gx1) / 2.0

    # Geometric model of the outer contour (frame is symmetric):
    # straight jambs + circular arch, sill a rounded box.
    rows = np.arange(h)
    valid = (left > 0) & (right > 0)
    # jamb half-width from the straight part of the frame
    straight = valid & (rows > 330) & (rows < 560)
    half = np.median(np.concatenate([cx - left[straight], right[straight] - cx]))
    # arch: half-ellipse with semi-axis `half` horizontally; y = ay - b*sqrt(1-u^2)
    xs = np.arange(w)
    u = (xs - cx) / half
    sel = (top < 10 ** 6) & (np.abs(u) > 0.3) & (np.abs(u) < 0.92)
    k = np.sqrt(1 - u[sel] ** 2)
    A = np.stack([np.ones_like(k), -k], 1)
    (ay, bax), *_ = np.linalg.lstsq(A, top[sel].astype(float), rcond=None)
    resid = top[sel] - (ay - bax * k)
    print(f"arch fit residual: median {np.median(np.abs(resid)):.2f}px, max {np.abs(resid).max():.1f}px")
    R = bax
    # sill: find from the left contour the rows where the frame is much wider
    sill_rows = valid & (rows > 540) & ((cx - left) > half + 20)
    sy0, sy1 = rows[sill_rows].min(), rows[sill_rows].max()
    sill_half = np.median(cx - left[sill_rows][3:-3])

    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    # signed distance-ish masks with 1px anti-aliasing (outline included)
    pad = 1.0
    jamb = np.clip(half + pad - np.abs(xx - cx) + 0.5, 0, 1) * (yy >= ay)
    ell = np.hypot((xx - cx) / (half + pad), (yy - ay) / (R + pad))
    arch = np.clip((1 - ell) * min(half, R) + 0.5, 0, 1) * (yy < ay)
    # the arch also needs the jamb above ay where the circle is narrower than the jamb
    frame = np.clip(jamb + arch, 0, 1) * (yy <= sy0 + 2)
    sill = np.clip(sill_half + pad - np.abs(xx - cx) + 0.5, 0, 1) * (yy > sy0 - 6) * (yy <= sy1 + 1.5)
    # round the sill corners a little
    alpha = np.clip(np.maximum(frame, sill), 0, 1)

    # glass becomes transparent; un-mix magenta from anti-aliased glass edges
    m = ndi.gaussian_filter(mag, 0.6)
    alpha = alpha * (1 - np.clip(m * 1.15, 0, 1))
    rgb = center.copy()
    frame_col = ndi.median_filter(center, size=(5, 5, 1))
    edge = (m > 0.02) & (m < 0.98)
    rgb[edge] = frame_col[edge]
    # where magenta leaked into frame pixels, recover colour: c = (p - m*M)/(1-m)
    M = np.array([255.0, 0.0, 255.0])
    leak = (mag > 0.0) & (mag < 0.9)
    mm = mag[leak][:, None]
    rgb[leak] = np.clip((center[leak] - mm * M) / np.maximum(1 - mm, 0.1), 0, 255)

    # soft synthetic contact shadow under the sill and beside the jambs
    solid = (alpha > 0.5).astype(np.float64)
    shifted = np.zeros_like(solid)
    shifted[6:, 3:] = solid[:-6, :-3]
    shadow = ndi.gaussian_filter(shifted, 7.0) * 0.28 * (1 - alpha)
    out = np.zeros((h, w, 4))
    out[..., :3] = rgb
    out[..., 3] = alpha * 255
    sh_col = np.array([150.0, 90.0, 55.0])
    sa = shadow * (1 - alpha)
    tot = alpha + sa
    out[..., :3] = np.where(tot[..., None] > 0,
                            (rgb * alpha[..., None] + sh_col * sa[..., None]) / np.maximum(tot, 1e-6)[..., None],
                            rgb)
    out[..., 3] = np.clip(tot, 0, 1) * 255
    # glass mask (for the sky placeholder / future landscape)
    glass_a = np.clip(m * 1.15, 0, 1) * (alpha < 0.999)
    glass_a = np.clip(ndi.gaussian_filter(glass_a, 0.5) * 1.0 + (glass > 0) * 1.0, 0, 1)
    # crop
    y0 = int(max(ay - R - 4, 0))
    y1 = int(min(sy1 + 46, h))
    x0 = int(cx - sill_half - 6)
    x1 = int(cx + sill_half + 7)
    print(f"window: centre x={cx:.1f} arch centre y={ay:.1f} R={R:.1f} jamb half={half:.1f}"
          f" sill rows {sy0}-{sy1} half={sill_half:.1f}; crop x{x0}-{x1} y{y0}-{y1}")
    with open(os.path.join(KIDS, "window_placement.txt"), "w") as f:
        f.write(f"source_crop_x0={x0}\nsource_crop_y0={y0}\nwidth={x1 - x0}\nheight={y1 - y0}\n"
                f"glass_x0={gx0 - x0}\nglass_x1={gx1 - x0}\nglass_y0={gy0 - y0}\nglass_y1={gy1 - y0}\n"
                f"sill_top_y_in_room={sy0}\n")
    gm = np.zeros((h, w, 4))
    gm[..., :3] = 255
    # glass extends 3px under the frame so no gap shows between sky and frame
    gm[..., 3] = ndi.grey_dilation(glass_a, size=(7, 7)) * 255
    save(gm[y0:y1, x0:x1], "window_glass_mask.png")
    return out[y0:y1, x0:x1]


def main() -> None:
    side = load("kids_room_side.png")
    center = load("kids_room_center.png")
    save(make_wall(side), "wall_tile.png")
    save(make_floor(side), "floor_tile.png")
    save(build_window(center), "window.png")


if __name__ == "__main__":
    main()
