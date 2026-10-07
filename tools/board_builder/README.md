# Board builder

Generates the Marky Valley board (`plugins/boards/MarkyValley`): a big island with eight themed
areas, a ring of spaces around it and a village in the middle with one-way shortcut roads.

Needs Python with `bpy` (Blender as a module), `numpy` and `pillow`, and a Godot 4.7 binary
(`pip install bpy numpy pillow`). Run from the project root:

```sh
# 1. design the board: spaces, terrain height and colours, scenery placement
python tools/board_builder/layout.py /tmp/marky_layout
python tools/board_builder/preview_layout.py /tmp/marky_layout /tmp/marky_layout.png   # optional top-down picture

# 2. model the landmarks (houses, castle, graveyard, ...) in Blender and import them
python tools/board_builder/build_props_all.py --bpy-python <python> --godot <godot> --project .
godot --path . --script res://tools/board_builder/preview_props.gd                       # optional picture of all props

# 3. build the scene (needs a renderer, the headless dummy renderer drops the scenery data)
DATA_DIR=/tmp/marky_layout xvfb-run -a godot --rendering-driver opengl3 --path . \
    --script res://tools/board_builder/build_board.gd
```

What is where:

- `layout.py` holds the whole design. The areas and their centres are in `AREAS`, the ring of spaces
  in `RING` (x, z, height), the shortcut roads in `ROADS`. The scenery lists use the nature models from
  `assets/models/nature`. It checks that every space is reachable and has a next space.
- `blender/build_props.py` models the landmarks. Edit a function there to change a building.
- `build_board.gd` writes `board.tscn`, the terrain mesh and its colour texture, and the mesh files in
  `meshes/`. Green spaces become warps in pairs (see `plugins/boards/MarkyValley/board.gd`).

`check_board.py <layout dir>` reports spaces that sink into the terrain and scenery that stands on the path
(layout.py already tilts every space to the slope and removes scenery from the path).

Take screenshots of the board with `tools/board_tour`.
