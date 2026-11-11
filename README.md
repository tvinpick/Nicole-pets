# Nicole Pets

Android-игра для ребёнка 6 лет (Godot 4.7.2, GDScript с типами, рендерер Compatibility,
горизонтальная ориентация, полный экран).

Сейчас в проекте **комната, кошка и щенок**.

## Структура
- `scenes/main.tscn` — комната, кошка, камера, FPS (только debug).
- `scripts/room.gd` — бесшовные стена/пол, окно с заглушкой неба (`sky_placeholder.gdshader`).
- `scripts/camera_rig.gd` — свайп = прокрутка, щипок/колесо = плавный зум, короткое касание = tap.
- `scripts/cat/cat_rig.gd` — кошка только из целых кадров: ходьба боком/к нам/от нас, еда, радость, позы `pose/`; смена — плавный переход.
- `scripts/cat/cat_frames.gd` — таблица кадров (генерируется `tools/process_cat.py`).
- `scripts/dog/dog_rig.gd`, `scripts/dog/dog.gd` — щенок из целых кадров (`assets/characters/dog/`), те же правила, что у кошки; `scripts/dog/dog_frames.gd` генерирует `tools/process_dog.py` (масштабы листов — `tools/dog_scale.txt`).
- `scripts/pet_space.gd` — питомцы обходят друг друга; мячиком играет только один.
- `scripts/food_bowl_placeholder.gd`, `scripts/ball_placeholder.gd` — ВРЕМЕННЫЕ миска и мячик (заглушки).
- `scripts/cat/cat.gd` — поведение (гуляет, сидит, лежит, спит, реагирует на касания).
- `tools/process_room.py`, `tools/process_cat.py` — подготовка текстур (numpy, scipy, pillow).
  Исходники (`kids_room_*.png`, `kitten_cutout_pngs.zip`, `side/`, `pose/`) не меняются.

## Масштаб персонажей
`scripts/world_scale.gd`: высота стены (пол → карниз) = 647 px, девочка 115 см ≈ 45% стены,
отсюда `PX_PER_CM`. Кошка: реалистично 33 см (≈13% стены), в игре ×2 (`CAT_SIZE_FACTOR`). `CHARACTER_SCALE` — одна
ручка для всех персонажей. Перспектива: 90% у стены → 100% у нижнего края.

## Сборка
GitHub Actions (`.github/workflows/android-debug.yml`) на каждый push собирает debug APK
(артефакт `nicole-pets-debug-apk`). Подпись — постоянный debug keystore из `keystore/`
(пароль `android`), поэтому новые версии ставятся поверх старых. Только для debug!

## Скриншоты для разработки
`godot --path . --fixed-fps 30 -- --shot=out.png --frames=40 [--zoom=2] [--walk|--back|--happy|--pose=sit]`
