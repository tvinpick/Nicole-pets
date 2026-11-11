#!/usr/bin/env python3
"""Cuts the puppy sheets (assets/characters/dog/dog_*.png) into aligned frames.

* The faint semi-transparent haze around some sheets is removed: very low alpha is
  dropped and low-alpha pixels far from the drawing are cleared. Motion lines and
  landing dust are separate opaque strokes and stay.
* Frames are split into N equal cells; each border is moved to the emptiest column
  near it (frames may touch each other).
* Frames are aligned on a common canvas: the paw line (lowest pixel) at the canvas
  bottom, x by the body centre. Frames whose lowest pixel is clearly above the sheet's
  floor line are airborne (run / jump) and keep their height above the floor.
* k = sheet px -> reference px, matched by the puppy's BODY in its standing/neutral
  frame (measured visually, see SHEETS), not by the picture size.

Originals are not modified. Output: assets/characters/dog/frames/<name>_<n>.png and
scripts/dog/dog_frames.gd.  Run: python3 tools/process_dog.py
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOG = os.path.join(ROOT, "assets", "characters", "dog")
OUT = os.path.join(DOG, "frames")
MARGIN = 8
AIRBORNE_GAP = 25

# name: (sheet file, frames, k, centre mode). Reference = dog_wag frame 1 (standing side).
# A missing sheet is skipped (the game falls back, see DogRig.FALLBACK).
SHEETS = {
    "walk_side": ("dog_walk_side.png", 4, 1.0, "torso"),
    "walk_front": ("dog_walk_front.png", 4, 1.0, "head"),
    "walk_back": ("dog_walk_back.png", 6, 1.0, "head"),
    "run": ("dog_run.png", 6, 1.0, "torso"),
    "eat": ("dog_eat.png", 6, 1.0, "torso"),
    "happy": ("dog_happy.png", 6, 1.0, "torso"),
    "wag": ("dog_wag.png", 6, 1.0, "torso"),
    "sit": ("dog_sit.png", 1, 1.0, "torso"),
    "lie": ("dog_lie.png", 1, 1.0, "torso"),
    "sleep": ("dog_sleep.png", 2, 1.0, "torso"),
    "stretch": ("dog_stretch.png", 3, 1.0, "torso"),
    "playbow": ("dog_playbow.png", 6, 1.0, "torso"),
    "jump": ("dog_jump.png", 6, 1.0, "torso"),
    "bark": ("dog_bark.png", 2, 1.0, "torso"),
    "scratch": ("dog_scratch.png", 3, 1.0, "torso"),
}
K_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dog_scale.txt")


def load_k() -> dict:
    """Optional per-sheet body-matched scale overrides: lines 'name k'."""
    ks = {}
    if os.path.exists(K_FILE):
        for line in open(K_FILE):
            line = line.split("#")[0].strip()
            if line:
                n, v = line.split()
                ks[n] = float(v)
    return ks


def clean(rgba: np.ndarray) -> np.ndarray:
    out = rgba.copy()
    a = out[..., 3].astype(np.int32)
    a[a < 14] = 0
    solid = a >= 128
    near = ndi.binary_dilation(solid, iterations=6)
    a[(a < 90) & ~near] = 0
    # drop tiny isolated specks (<12 px) that are not part of any drawing
    lab, n = ndi.label(a > 0)
    if n:
        sizes = ndi.sum(np.ones_like(a), lab, range(1, n + 1))
        tiny = np.isin(lab, 1 + np.nonzero(sizes < 12)[0])
        a[tiny] = 0
    out[..., 3] = a.astype(np.uint8)
    out[out[..., 3] == 0, :3] = 0
    return out


def cut(alpha: np.ndarray, n: int) -> list:
    occ = (alpha > 40).sum(axis=0).astype(float)
    w = alpha.shape[1]
    cols = np.nonzero(occ > 0)[0]
    x0, x1 = cols.min(), cols.max() + 1
    cell = (x1 - x0) / n
    bounds = [x0]
    for i in range(1, n):
        c = x0 + cell * i
        lo, hi = int(c - cell * 0.3), int(c + cell * 0.3)
        seg = occ[lo:hi]
        best = lo + int(np.argmin(seg + np.abs(np.arange(lo, hi) - c) * 0.02))
        bounds.append(best)
    bounds.append(x1)
    return [(bounds[i], bounds[i + 1]) for i in range(n)]


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    ks = load_k()
    info = {}
    for name, (src, n, k, mode) in SHEETS.items():
        path = os.path.join(DOG, src)
        if not os.path.exists(path):
            print("missing sheet, skipped:", src)
            continue
        sheet = clean(np.asarray(Image.open(path).convert("RGBA")))
        a = sheet[..., 3] > 40
        frames = []
        for x0, x1 in cut(sheet[..., 3], n):
            sub = a[:, x0:x1].copy()
            # only the frame's own drawing (+ strokes near it) decides the box
            ys, xs = np.nonzero(sub)
            top, bottom = ys.min(), ys.max()
            h = bottom - top
            if mode == "head":
                band = sub[top:top + int(h * 0.35)]
            else:
                band = sub[top + int(h * 0.45):top + int(h * 0.8)]
            cx = x0 + np.nonzero(band)[1].mean()
            frames.append((x0, x1, top, bottom, cx))
        floor = max(f[3] for f in frames)
        half = int(np.ceil(max(max(cx - x0, x1 - cx) for x0, x1, t, b, cx in frames))) + MARGIN
        height = int(max(floor - t for x0, x1, t, b, cx in frames)) + 2 * MARGIN
        cw, ch = 2 * half, height
        heights = []
        for i, (x0, x1, top, bottom, cx) in enumerate(frames, start=1):
            out = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            ground = bottom if floor - bottom < AIRBORNE_GAP else floor
            out.alpha_composite(Image.fromarray(sheet[:, x0:x1].copy(), "RGBA"),
                                (x0 + int(round(half - cx)), int(ch - MARGIN - 1 - ground)))
            out.save(os.path.join(OUT, f"{name}_{i}.png"), optimize=True)
            heights.append(int(floor - top))
        info[name] = (len(frames), cw, ch, ch - MARGIN, half, heights[0], ks.get(name, k))
        print(f"{name}: {len(frames)} frames, canvas {cw}x{ch}, heights {heights}")
    lines = ["class_name DogFrames", "extends RefCounted",
             "## GENERATED by tools/process_dog.py - do not edit by hand.",
             "## name -> [frame count, canvas size, paw line y, centre x, frame-1 height, k]",
             "## k = sheet px -> reference px (dog_wag frame 1), matched by the body.",
             "", "const SETS: Dictionary = {"]
    for name, (cnt, cw, ch, paw, cx, h1, k) in info.items():
        lines.append(f'\t"{name}": [{cnt}, Vector2({cw}, {ch}), {paw}.0, {cx}.0, {h1}.0, {k}],')
    lines.append("}")
    os.makedirs(os.path.join(ROOT, "scripts", "dog"), exist_ok=True)
    with open(os.path.join(ROOT, "scripts", "dog", "dog_frames.gd"), "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
