#!/usr/bin/env python3
"""Writes the scene, config and English texts of the arcade minigames (plugins/minigames/<name>).

    python tools/arcade_builder/gen_minigames.py

The game logic lives in plugins/minigames/<name>/minigame.gd and common/scripts/arcade; this script only
produces the small files around it, so the list of games, their types and their texts are in one place.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

MOVE = {"actions": ["spacer", "up", "spacer", "left", "down", "right"], "text": "MINIGAME_ACTION_MOVEMENT"}

GAMES = {
    "cookie_catch": dict(
        title="Cookie Catch", node="CookieCatch", types=["FFA", "Duel", "2v2"], score=True, duration=30.0,
        positions=[(-3, -3), (3, -3), (-3, 3), (3, 3)],
        controls=[MOVE],
        description="Cookies rain from the sky! Run around and catch as many as you can.\n\nGolden cookies are worth three. "
                    "Do not catch a bomb: it stuns you and costs you two cookies.\n\nWho has the most cookies after 30 seconds wins!",
        extra={}),
    "hot_bomb": dict(
        title="Hot Bomb", node="HotBomb", types=["FFA"], score=False, duration=90.0,
        positions=[(3, 0), (0, 3), (-3, 0), (0, -3)],
        controls=[MOVE],
        description="One player holds a lit bomb. Touch another player to pass it on!\n\nWhen the fuse is burnt up, "
                    "the player with the bomb is out. The last one standing wins.",
        extra={}),
    "jump_rope": dict(
        title="Jump Rope", node="JumpRope", types=["FFA", "Duel"], score=False, duration=55.0,
        positions=[(-3.4, -1.5), (3.4, -1.5), (-3.4, 2.5), (3.4, 2.5)],
        controls=[MOVE, {"actions": ["action1"], "text": "MINIGAME_ACTION_JUMP"}],
        description="A rope sweeps around the pole in the middle, faster and faster. Jump over it!\n\n"
                    "Watch out: the rope turns around now and then, and more ropes join in. The last player who is not hit wins.",
        extra={}),
    "tug_of_war": dict(
        title="Tug of War", node="TugOfWar", types=["2v2", "1v3", "Duel"], score=False, duration=26.0,
        positions=[(-4.6, -0.8), (-4.6, 0.8), (4.6, -0.8), (4.6, 0.8)],
        controls=[{"actions": ["action1"], "text": "MINIGAME_ACTION_PULL"}],
        description="Two teams pull on a rope. Mash the button as fast as you can!\n\nThe team that drags the other one "
                    "over the line wins. In the 1 vs 3 version the single player pulls as hard as two players.",
        extra={}),
}

TSCN = '''[gd_scene load_steps={steps} format=3]

[ext_resource type="Script" path="res://plugins/minigames/{dir}/minigame.gd" id="1"]
[ext_resource type="PackedScene" path="res://common/scenes/arcade/arcade_player.tscn" id="2"]
[ext_resource type="PackedScene" path="res://common/scenes/countdown/countdown.tscn" id="3"]
[ext_resource type="PackedScene" path="res://common/scenes/overlays/score_overlay.tscn" id="4"]
[ext_resource type="Texture2D" path="res://common/scenes/board_logic/controller/icons/cookie.png" id="5"]

[node name="{node}" type="Node3D"]
script = ExtResource("1")
duration = {duration}
'''


def write_game(dir_name, g):
    folder = os.path.join(ROOT, "plugins", "minigames", dir_name)
    os.makedirs(os.path.join(folder, "translations"), exist_ok=True)
    text = TSCN.format(steps=6, dir=dir_name, node=g["node"], duration=g["duration"])
    for i, (x, z) in enumerate(g["positions"]):
        text += '\n[node name="Player%d" parent="." instance=ExtResource("2")]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, 0.05, %s)\n' % (i + 1, x, z)
    text += '\n[node name="Countdown" parent="." instance=ExtResource("3")]\n'
    text += '''
[node name="Screen" type="Control" parent="."]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
'''
    if g["score"]:
        text += '''
[node name="ScoreOverlay" parent="Screen" instance=ExtResource("4")]
layout_mode = 1
grow_horizontal = 2
grow_vertical = 2
icon = ExtResource("5")
'''
    if dir_name != "hot_bomb":
        text += '''
[node name="Time" type="Label" parent="Screen"]
layout_mode = 0
anchor_left = 0.5
anchor_right = 0.5
offset_left = -60.0
offset_top = 16.0
offset_right = 60.0
offset_bottom = 74.0
theme_type_variation = &"HeaderLarge"
text = "30"
horizontal_alignment = 1
vertical_alignment = 1
'''
    with open(os.path.join(folder, "minigame.tscn"), "w") as f:
        f.write(text)
    config = {
        "name": "MINIGAME_NAME",
        "scene_path": "res://plugins/minigames/%s/minigame.tscn" % dir_name,
        "image_path": "res://plugins/minigames/%s/screenshot.png" % dir_name,
        "translation_directory": "res://plugins/minigames/%s/translations" % dir_name,
        "type": g["types"],
        "description": "MINIGAME_DESCRIPTION",
        "controls": g["controls"],
    }
    with open(os.path.join(folder, "minigame.json"), "w") as f:
        json.dump(config, f, indent="\t")
    texts = {"MINIGAME_NAME": g["title"], "MINIGAME_DESCRIPTION": g["description"],
             "MINIGAME_ACTION_JUMP": "Jump", "MINIGAME_ACTION_PULL": "Pull (press as fast as you can)"}
    po = '''# English texts of the minigame {title}.
msgid ""
msgstr ""
"Project-Id-Version: 1.0\\n"
"MIME-Version: 1.0\\n"
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Language: en\\n"
'''.format(title=g["title"])
    for key, value in texts.items():
        po += '\nmsgid "%s"\nmsgstr "%s"\n' % (key, value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    with open(os.path.join(folder, "translations", "en.po"), "w") as f:
        f.write(po)
    print("wrote", dir_name)


if __name__ == "__main__":
    for name, game in GAMES.items():
        write_game(name, game)
