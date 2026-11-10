#!/usr/bin/env python3
"""Prepares the cat cut-out parts for the 2-pass rig.

Every body part is drawn twice in the game:
  1. the original sprite (outline + fill)       -> "outline pass"
  2. a fill-only copy without the dark contour  -> "fill pass", drawn above ALL outline sprites
     of the same group.
Where parts of one group overlap, the fill pass covers the inner contours, so knees,
neck and the tail base have no visible seams; the outer contour stays intact.

Input : assets/characters/cat/side/*.png (originals stay untouched)
Output: assets/characters/cat/rig/<name>_fill.png  + rig/anchors.json (measured joint points)

Run: python3 tools/process_cat.py   (numpy, scipy, pillow)
"""
from __future__ import annotations

import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAT = os.path.join(ROOT, "assets", "characters", "cat")
OUT = os.path.join(CAT, "rig")

PARTS = [
    "side_hips_alternate", "side_chest_alternate", "side_head",
    "side_ear_near", "side_ear_far",
    "side_front_near_upper", "side_front_near_paw", "side_front_far_upper", "side_front_far_paw",
    "side_hind_near_upper", "side_hind_near_paw", "side_hind_far_upper", "side_hind_far_paw",
    "side_tail_1",
]


def fill_only(rgba: np.ndarray) -> np.ndarray:
    a = rgba[..., 3].astype(np.float64) / 255.0
    rgb = rgba[..., :3].astype(np.float64)
    inside = a > 0.5
    dist = ndi.distance_transform_edt(inside)
    dark = (rgb[..., 0] < 112) & (rgb[..., 1] < 92)
    outline = dark & (dist <= 13)
    # grow the outline through its anti-aliased inner edge
    outline = ndi.binary_dilation(outline, iterations=2) & inside
    outline |= dist <= 3
    fill = inside & ~outline
    # keep the biggest regions only (drop specks between outline and edge)
    lab, n = ndi.label(fill)
    if n > 1:
        sizes = ndi.sum(fill, lab, range(1, n + 1))
        fill = np.isin(lab, 1 + np.nonzero(sizes > sizes.max() * 0.02)[0])
    core = ndi.binary_erosion(fill, iterations=2)
    # colour bleed: every pixel takes the colour of the nearest core pixel
    _, (iy, ix) = ndi.distance_transform_edt(~core, return_indices=True)
    bled = rgb[iy, ix]
    # slightly grow the fill so it reaches the middle of the outline (soft edge)
    grown = ndi.distance_transform_edt(~fill)
    alpha = np.clip(1.5 - grown, 0, 1) * inside
    alpha = ndi.gaussian_filter(alpha, 0.7) * inside
    out = np.zeros_like(rgba, dtype=np.float64)
    out[..., :3] = bled
    out[..., 3] = alpha * 255
    return np.clip(out + 0.5, 0, 255).astype(np.uint8)


def anchors(rgba: np.ndarray) -> dict:
    a = rgba[..., 3] > 128
    ys, xs = np.nonzero(a)
    h, w = a.shape
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    def band_centre(r0, r1):
        sub = a[r0:r1]
        yy, xx = np.nonzero(sub)
        return float(xx.mean()), float(yy.mean() + r0)
    bh = max(int((y1 - y0) * 0.12), 4)
    top = band_centre(y0, y0 + bh)
    bot = band_centre(y1 - bh, y1 + 1)
    return {"size": [w, h], "bbox": [int(x0), int(y0), int(x1), int(y1)],
            "top": [round(top[0], 1), float(y0)], "bottom": [round(bot[0], 1), float(y1)],
            "centre": [round(float(xs.mean()), 1), round(float(ys.mean()), 1)]}


FRONT = "front"


def _load(folder: str, name: str) -> np.ndarray:
    return np.asarray(Image.open(os.path.join(CAT, folder, name + ".png")).convert("RGBA"))


def _paste(canvas: Image.Image, arr: np.ndarray, centre_x: float, top: float, flip: bool = False) -> None:
    im = Image.fromarray(arr, "RGBA")
    if flip:
        im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    canvas.alpha_composite(im, (int(round(centre_x - im.width / 2)), int(round(top))))


# Front view: (part, centre x, top y) on a canvas whose floor line is FRONT_GROUND.
# Groups are drawn outline pass -> fill pass, so legs/neck/ears merge without seams.
FRONT_W, FRONT_H, FRONT_GROUND = 760, 1000, 975
FRONT_LAYOUT = [
    # hind legs peek out behind the body (further away -> a little higher)
    [("front_hind_far_paw", 512, 782, True), ("front_hind_near_paw", 248, 782, False)],
    # front legs come out from under the chest bib
    [("front_front_near_upper", 322, 560, False), ("front_front_far_upper", 438, 560, False),
     ("front_front_near_paw", 316, 795, False), ("front_front_far_paw", 444, 795, False),
     ("front_chest", 380, 445, False)],
    # ears behind the head
    [("front_ear_near", 268, 105, False), ("front_ear_far", 492, 107, False),
     ("front_head", 380, 170, False)],
]
FRONT_FACE = [
    ("front_blush_near", 285, 350), ("front_blush_far", 475, 350),
    ("front_eyes_open", 380, 265),
    ("front_whiskers_near", 255, 373), ("front_whiskers_far", 505, 373),
    ("front_nose", 380, 357), ("front_mouth_closed", 380, 405),
]


def make_front_view() -> dict:
    canvas = Image.new("RGBA", (FRONT_W, FRONT_H), (0, 0, 0, 0))
    for group in FRONT_LAYOUT:
        arrs = [(_load(FRONT, n), x, y, f) for n, x, y, f in group]
        for a, x, y, f in arrs:
            _paste(canvas, a, x, y, f)
        for a, x, y, f in arrs:
            _paste(canvas, fill_only(a), x, y, f)
    for n, x, y in FRONT_FACE:
        _paste(canvas, _load(FRONT, n), x, y)
    out = np.asarray(canvas)
    ys, xs = np.nonzero(out[..., 3] > 128)
    canvas.save(os.path.join(OUT, "front_view.png"), optimize=True)
    return {"size": [FRONT_W, FRONT_H], "ground_y": FRONT_GROUND,
            "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]}


# Frame sheets: frames are cut by the transparent gaps and aligned on a common canvas:
# the paw line (lowest pixel) at the canvas bottom, x by the head centre ("head") or by
# the body centre ("torso" = centroid of the 45..80% height band).
# k = sheet px -> walk-side sheet px (matched by the cat's BODY, not the picture size;
# the eating cat has its head down, so its picture is lower but the cat is the same).
SHEETS = {
    # name: (source, mode, k)
    "walk_front": ("cat_walk_front.png", "head", None),   # sized by ear height in game
    "walk_back": ("cat_walk_back.png", "head", None),
    "walk_side": ("cat_walk_side.png", "torso", 1.0),
    "eat_side": ("cat_eat_side.png", "torso", 1.0),
    "happy_sit": ("cat_happy_sit.png", "torso", 0.62),
    "pose_sit": ("pose/pose_sit.png", "torso", 1.0),
    "pose_lie": ("pose/pose_lie.png", "torso", 0.98),
    "pose_sleep": ("pose/pose_sleep.png", "torso", 0.91),
}
FRAME_MARGIN = 8


def _cut(sheet_a: np.ndarray) -> list:
    col = sheet_a.any(axis=0)
    runs, start = [], None
    for x, v in enumerate(col):
        if v and start is None:
            start = x
        elif not v and start is not None:
            if x - start > 15:
                runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, len(col)))
    return runs


def make_frame_sets() -> dict:
    info = {}
    for name, (src, mode, k) in SHEETS.items():
        sheet = np.asarray(Image.open(os.path.join(CAT, src)).convert("RGBA"))
        a = sheet[..., 3] > 20
        runs = _cut(a)
        if src.startswith("pose/"):
            runs = [(runs[0][0], runs[-1][1])]
        frames = []
        for x0, x1 in runs:
            sub = a[:, x0:x1]
            ys, xs = np.nonzero(sub)
            top, bottom = ys.min(), ys.max()
            h = bottom - top
            if mode == "head":
                band = sub[top:top + int(h * 0.35)]
                b0 = top
            else:
                b0 = top + int(h * 0.45)
                band = sub[b0:top + int(h * 0.8)]
            cx = x0 + np.nonzero(band)[1].mean()
            frames.append((x0, x1, top, bottom, cx))
        left = max(cx - x0 for x0, x1, t, b, cx in frames)
        right = max(x1 - cx for x0, x1, t, b, cx in frames)
        half = int(np.ceil(max(left, right))) + FRAME_MARGIN
        height = int(max(b - t for x0, x1, t, b, cx in frames)) + 2 * FRAME_MARGIN
        cw, ch = 2 * half, height
        heights = []
        for i, (x0, x1, top, bottom, cx) in enumerate(frames, start=1):
            out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            dx = int(round(half - cx))
            dy = int(ch - FRAME_MARGIN - 1 - bottom)
            out.alpha_composite(Image.fromarray(sheet[:, x0:x1].copy(), "RGBA"), (x0 + dx, dy))
            out.save(os.path.join(OUT, f"{name}_{i}.png"), optimize=True)
            heights.append(int(bottom - top))
        info[name] = {"frames": len(frames), "canvas": [cw, ch], "paw_line_y": ch - FRAME_MARGIN,
                      "centre_x": half, "frame_heights": heights, "k": k}
    _write_gd(info)
    return info


def _write_gd(info: dict) -> None:
    """Frame-set table for the game (scripts/cat/cat_frames.gd)."""
    lines = ["class_name CatFrames", "extends RefCounted",
             "## GENERATED by tools/process_cat.py - do not edit by hand.",
             "## name -> [frame count, canvas size, paw line y, centre x, frame-1 height, k]",
             "## k = sheet px -> walk-side sheet px (body-matched); 0 = sized by its own height.",
             "", "const SETS: Dictionary = {"]
    for name, d in info.items():
        cw, ch = d["canvas"]
        lines.append(f'\t"{name}": [{d["frames"]}, Vector2({cw}, {ch}), {d["paw_line_y"]}.0, '
                     f'{d["centre_x"]}.0, {d["frame_heights"][0]}.0, {d["k"] or 0.0}],')
    lines.append("}")
    with open(os.path.join(ROOT, "scripts", "cat", "cat_frames.gd"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    info = {}
    for name in PARTS:
        src = np.asarray(Image.open(os.path.join(CAT, "side", name + ".png")).convert("RGBA"))
        Image.fromarray(fill_only(src), "RGBA").save(os.path.join(OUT, name + "_fill.png"), optimize=True)
        info[name] = anchors(src)
    for name in ["pose_sit", "pose_lie", "pose_sleep", "pose_stand"]:
        src = np.asarray(Image.open(os.path.join(CAT, "pose", name + ".png")).convert("RGBA"))
        info[name] = anchors(src)
    # front/back walking rigs: fill copies of their parts as well
    for folder in ("front", "back"):
        for fn in sorted(os.listdir(os.path.join(CAT, folder))):
            if not fn.endswith(".png") or any(k in fn for k in ("eyes", "mouth", "nose", "whisker", "blush", "tongue", "tail_")):
                continue
            src = np.asarray(Image.open(os.path.join(CAT, folder, fn)).convert("RGBA"))
            Image.fromarray(fill_only(src), "RGBA").save(os.path.join(OUT, fn[:-4] + "_fill.png"), optimize=True)
            info[fn[:-4]] = anchors(src)
    info["front_view"] = make_front_view()
    info.update(make_frame_sets())
    with open(os.path.join(OUT, "anchors.json"), "w") as f:
        json.dump(info, f, indent=1)
    print("ok", len(PARTS), "fill textures")


if __name__ == "__main__":
    main()
