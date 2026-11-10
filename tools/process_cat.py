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
    with open(os.path.join(OUT, "anchors.json"), "w") as f:
        json.dump(info, f, indent=1)
    print("ok", len(PARTS), "fill textures")


if __name__ == "__main__":
    main()
