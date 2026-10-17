#!/bin/bash
set -euo pipefail
user=${CONTAINER_USERNAME}
uid=${PUID:-1000}
gid=${PGID:-1000}
[[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ && $uid -ne 0 ]] || {
    echo "Invalid PUID/PGID (PUID must be nonzero)" >&2; exit 1;
}
# Only change container account metadata, never recursively chown host mounts.
groupmod -o -g "$gid" "$user"
usermod -o -u "$uid" -g "$gid" "$user"
export HOME="/home/$user" USER="$user" LOGNAME="$user"
mkdir -p /data "${XDG_RUNTIME_DIR:=/run/user/$uid}" "$HOME/.cache"
chown "$uid:$gid" /data "$HOME" "$HOME/.cache"
chmod 700 "$XDG_RUNTIME_DIR"
chown "$uid:$gid" "$XDG_RUNTIME_DIR"
for source in /usr/local/share/retropie-defaults/*; do
    name=${source##*/}
    # External ROMs are mounted read-only; do not seed or change ownership.
    if [[ $name == roms && ${RETROPIE_EXTERNAL_ROMS:-0} == 1 ]]; then
        continue
    fi
    if [[ ! -e /data/$name ]]; then
        mkdir "/data/$name"
        chown "$uid:$gid" "/data/$name"
    fi
    gosu "$user" cp -r --update=none "$source/." "/data/$name/"
done
# Add device groups within the container; leave host permissions untouched.
while read -r device_gid; do
    [[ -n $device_gid ]] || continue
    group=$(getent group "$device_gid" | cut -d: -f1) || group=''
    if [[ -z $group ]]; then
        group="device-$device_gid"
        groupadd -g "$device_gid" "$group"
    fi
    usermod -aG "$group" "$user"
done < <(find /dev/input /dev/dri /dev/snd /dev/uinput -type c -printf '%G\n' 2>/dev/null | sort -u)
if ! nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null; then
    echo "No NVIDIA GPU, falling back to Mesa"
elif [[ ${SDL_VIDEODRIVER:-wayland,x11} != x11 ]]; then
    # A working NVIDIA Wayland EGL display is required for native Wayland.
    if ! gosu "$user" /usr/local/bin/gpu-check wayland; then
        echo "NVIDIA EGL-Wayland unavailable; using Xwayland (SDL/GTK)"
        export SDL_VIDEODRIVER=x11 GDK_BACKEND=x11
    fi
fi
# RetroPie's EmulationStation wrapper otherwise forces SDL back to Wayland.
if [[ ${SDL_VIDEODRIVER:-} == x11 ]]; then
    unset WAYLAND_DISPLAY
fi
gosu "$user" touch "$RETROPIE_LOG"
exec gosu "$user" "$@"
