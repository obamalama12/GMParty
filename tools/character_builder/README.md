# Character builder

Builds the characters (Bolt, Businessman, Emo, Kit, Mushi, Timber) in `plugins/characters/`, the board cake topper and the game icon, and renders previews.

## Rebuild the characters

Needs Python with `bpy` (Blender as a module), `pillow` and `numpy`, plus a Godot 4.7 binary.

```sh
python -m venv .venv && .venv/bin/pip install bpy pillow numpy
.venv/bin/python tools/character_builder/build_all.py \
    --bpy-python .venv/bin/python --godot /path/to/godot --project .
```

What it does:
1. `blender/build_characters.py` models each character (chibi proportions, a 8x8 colour
   palette texture, a simple skeleton, 12 animations named like the game expects) and
   exports a `.glb`. Edit the part lists in that file to change a character.
2. The `.glb` files are imported in a temporary Godot project with the same folder layout
   and the animation loop flags are written into the `.glb.import` files.
3. `write_scenes.py` writes `Material.tres` (toon shading plus a black outline pass) and `character.tscn` for each character.

Pass `--keep-blend` to also copy the `.blend` files next to the models (they are tracked by
Git LFS in this repo).

## Previews and portraits

```sh
godot --path . --script res://tools/character_builder/render_characters.gd
```

Needs a display (or `xvfb-run`, with `--rendering-driver opengl3 --audio-driver Dummy`).
Writes a turnaround and an animation strip per character plus a lineup next to the original
characters. `SHOTS_DIR=<dir>` sets the output folder. `WRITE_ICONS=1` also writes
`icon.png` and `splash.png` into the character folders; import them in Godot afterwards.

## Other scripts

- `import_images.py` creates the Godot `.import` files for new PNGs (headless `godot --import`
  skips new files in a big project).
- `draw_portraits.py` draws the 2D portraits (`icon.png`, `splash.png`) of the characters and Mayor Pixel with Pillow.
- `make_title.py` draws the title logo `assets/textures/title/Title.png` with Pillow.
- `make_game_icon.py` builds `assets/icons/icon*.png` and `icon.ico` from a 1024 px render.
- `blender/cake_topper.py <cake.blend> <cake.glb>` replaces the figure on the board cake with a
  star and cherries (needs the original `cake.blend`, which is stored in Git LFS upstream).
