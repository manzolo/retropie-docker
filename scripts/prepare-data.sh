#!/bin/bash
# Runs only while building the image; retain defaults outside all bind mounts.
set -euo pipefail
seed=/usr/local/share/retropie-defaults
mkdir -p "$seed" /data "$HOME/.local/share"
move_data() {
    local source=$1 name=$2
    mkdir -p "$source"
    mv "$source" "$seed/$name"
    ln -s "/data/$name" "$source"
}
move_data /opt/retropie/configs configs
move_data /etc/emulationstation emulationstation
move_data "$HOME/RetroPie/roms" roms
move_data "$HOME/RetroPie/BIOS" BIOS
move_data "$HOME/.config" home-config
move_data "$HOME/.local/share" home-data
# RetroPie normally creates these links. Use the actual config directory.
ln -sfn /opt/retropie/configs/all/emulationstation "$HOME/.emulationstation"
ln -sfn /opt/retropie/configs/gc "$HOME/.dolphin-emu"
# Modern Dolphin also uses XDG locations; route both versions to persistent data.
mkdir -p "$seed/configs/gc/Config" "$seed/configs/gc/local"
ln -sfn /opt/retropie/configs/gc/Config "$seed/home-config/dolphin-emu"
ln -sfn /opt/retropie/configs/gc/local "$seed/home-data/dolphin-emu"
mkdir -p "$seed/saves" "$seed/states"
# Keep saves outside the ROM directory, including with read-only external ROMs.
sed -i -E 's|^[# ]*savefile_directory =.*|savefile_directory = "/data/saves"|; s|^[# ]*savestate_directory =.*|savestate_directory = "/data/states"|' "$seed/configs/all/retroarch.cfg"
