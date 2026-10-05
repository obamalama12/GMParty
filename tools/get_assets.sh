#!/bin/sh
# Copies the Git LFS assets (textures, models, music, sounds) from a checkout of the
# original Super Tux Party into this project.
#
#   git clone https://gitlab.com/SuperTuxParty/SuperTuxParty.git upstream
#   (cd upstream && git lfs pull)
#   tools/get_assets.sh upstream
#
# Files that already exist here are kept, and the characters and art that were removed
# from Marky Party are not copied. Needs rsync.
set -e
src="${1:?usage: tools/get_assets.sh <path to upstream checkout>}"
[ -d "$src/assets" ] || { echo "$src does not look like a Super Tux Party checkout" >&2; exit 1; }
cd "$(dirname "$0")/.."
rsync -a --ignore-existing \
	--exclude=.git --exclude=.godot \
	--exclude=plugins/characters/Tux \
	--exclude='plugins/characters/Green Tux' \
	--exclude=plugins/characters/Beastie \
	--exclude=plugins/characters/Godette \
	--exclude=assets/tux \
	--exclude='assets/models/cake/tux*' \
	--exclude=assets/icons/icon.xcf \
	--exclude=assets/icons/blender \
	"$src"/ ./
echo "done"
