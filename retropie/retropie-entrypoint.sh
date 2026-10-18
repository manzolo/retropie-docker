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
# An existing es_systems.cfg predates emulators added to the image later: append the systems it
# lacks (never touching the ones it has), otherwise EmulationStation never shows the new system.
if [[ -f /data/emulationstation/es_systems.cfg && -f /usr/local/share/retropie-defaults/emulationstation/es_systems.cfg ]]; then
    gosu "$user" python3 - <<'PY' || echo "es_systems.cfg: merge of new systems skipped (see above)" >&2
import xml.etree.ElementTree as ET
dst = '/data/emulationstation/es_systems.cfg'
img = ET.parse('/usr/local/share/retropie-defaults/emulationstation/es_systems.cfg').getroot()
tree = ET.parse(dst); root = tree.getroot()
have = {s.findtext('name') for s in root.findall('system')}
new = [s for s in img.findall('system') if s.findtext('name') not in have]
if new:
    for s in new: root.append(s)
    ET.indent(root, space='  '); tree.write(dst, encoding='utf-8', xml_declaration=True)
    print('es_systems.cfg: added ' + ', '.join(s.findtext('name') for s in new))
PY
fi
# Same for each system's emulators.cfg: an emulator added to the image later (make packages-choose,
# make update) must become selectable even where the file already exists. Missing lines are
# appended; existing lines, including the default you chose, are never changed; the file is backed
# up next to itself before the first change.
gosu "$user" python3 - <<'PY' || echo "emulators.cfg: merge of new emulators skipped (see above)" >&2
import glob, os, re, shutil, time
line_re = re.compile(r'^\s*([^#=\s][^=]*?)\s*=\s*(.*?)\s*$')
def entries(path):
    out = {}
    for line in open(path, errors='replace'):
        m = line_re.match(line)
        if m: out.setdefault(m.group(1), m.group(2))
    return out
stamp = time.strftime('%Y%m%d-%H%M%S')
for src in sorted(glob.glob('/usr/local/share/retropie-defaults/configs/*/emulators.cfg')):
    system = src.split('/')[-2]
    dst = f'/data/configs/{system}/emulators.cfg'
    if not os.path.isfile(dst):
        continue
    have, img = entries(dst), entries(src)
    missing = [(k, v) for k, v in img.items() if k not in have and (k != 'default' or 'default' not in have)]
    if not missing:
        continue
    shutil.copy2(dst, f'{dst}.bak-{stamp}')
    text = open(dst, errors='replace').read()
    with open(dst, 'a') as f:
        if text and not text.endswith('\n'):
            f.write('\n')
        for k, v in missing:
            f.write(f'{k} = {v}\n')
    print(f'emulators.cfg: {system} gained ' + ', '.join(k for k, _ in missing))
PY
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
