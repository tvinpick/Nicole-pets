KITTEN CUTOUT PNG PACK
======================
All exported individual sprites have RGBA transparency, with 10-pixel padding
from the detected alpha bounding box (where source edges allow it).

Folders:
side/  - primary right-facing parts from 10624 and split torso from 10625;
         v2 = alternate earlier sheet 10623;
         pose_variant = additional torso drawings from the pose sheet.
front/ - front-facing cutout parts from 10621.
back/  - rear-facing cutout parts from 10622.
pose/  - finished, uncut sleeping, lying, sitting poses from the pose sheet;
         plus standing reference from 10619.

Whisker strands near each other are grouped into one PNG per cheek.
The front-facing paired eyes are grouped as one asset per expression.
RGB is copied directly from the RGBA originals. Existing alpha is retained
within each connected silhouette; only border-reachable near-transparent
background and stray pixels distant from a solid component are suppressed.
Cream/light fur is NOT color-keyed away.

manifest.json gives original source sheet and its exact crop_box_xyxy coordinates.
For Godot 2D: these PNGs are art components, not complete rigs with bone pivots.
Use the manifest to restore their original positions within the source canvas,
then set rotation pivot/attachment points in the character scene.

IMPORTANT: The split torso in 10625 (side_hips.png and side_chest.png) INCLUDES
attached paws in the artwork; for true independently articulated limbs, use
the leg-free alternate torso pieces in this pack as bases or edit the source
image. Some alternate torso sketches are not anatomically interchangeable.
The different generated sheets may vary slightly in scale and shape; source
size is preserved (no sprite rescaling applied), but pixel-to-pixel alignment
between different sheets is not guaranteed.
