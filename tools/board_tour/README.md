# Board tour

Starts a local game on a board and takes screenshots.

```sh
BOARD=MarkyValley SHOTS_DIR=/tmp/tour godot --path . res://tools/board_tour/board_tour.tscn
```

- default: an overview from five angles.
- `VIEWS="village:0:0;lake:-20:-85"` adds a gameplay-camera shot and a wider one at the space nearest to each
  x:z position.
- `PLAY=120` plays for that many seconds by pressing the ok button, takes screenshots and logs where the
  players are (it stops making sense once the first minigame screen comes up).
- `WARPTEST=1` triggers every green space event and checks where the player lands.

Needs a display (`xvfb-run -a -s "-screen 0 1280x720x24"` with `--rendering-driver opengl3 --audio-driver Dummy`
works without a GPU).
