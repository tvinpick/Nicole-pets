# Nicole Pets

Android-игра для ребёнка 6 лет (Godot 4.7.2, GDScript с типами, рендерер Compatibility,
горизонтальная ориентация, полный экран).

Сейчас в проекте только **комната и кошка** — проверка движения.

## Структура
- `scenes/main.tscn` — комната, кошка, камера, FPS (только debug).
- `scripts/room.gd` — бесшовные стена/пол, окно с заглушкой неба (`sky_placeholder.gdshader`).
- `scripts/camera_rig.gd` — свайп = прокрутка, щипок/колесо = плавный зум, короткое касание = tap.
- `scripts/cat/cat_rig.gd` — риг кошки из деталей `side/` + готовые позы `pose/`.
- `scripts/cat/cat.gd` — поведение (гуляет, сидит, лежит, спит, реагирует на касания).
- `tools/process_room.py`, `tools/process_cat.py` — подготовка текстур (numpy, scipy, pillow).
  Исходники (`kids_room_*.png`, `kitten_cutout_pngs.zip`, `side/`, `pose/`) не меняются.

## Сборка
GitHub Actions (`.github/workflows/android-debug.yml`) на каждый push собирает debug APK
(артефакт `nicole-pets-debug-apk`). Подпись — постоянный debug keystore из `keystore/`
(пароль `android`), поэтому новые версии ставятся поверх старых. Только для debug!

## Скриншоты для разработки
`godot --path . --fixed-fps 30 -- --shot=out.png --frames=40 [--zoom=2] [--walk|--back|--happy|--pose=sit]`
