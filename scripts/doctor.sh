#!/bin/bash
# doctor.sh: what the host must provide (docker-compose.yml asks for all of it), checked one by one.
# ✓ fine, ⚠ works but degraded or worth knowing, ✗ blocks build or start. Exit 1 if anything blocks.
# Run it from your desktop session (the display, audio and bus checks read its environment).
set -uo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT" || exit 1
bad=0 warn=0
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' B=$'\e[1m' N=$'\e[0m'; else G='' Y='' R='' B='' N=''; fi
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
meh()  { printf '  %s⚠%s %s\n' "$Y" "$N" "$1"; warn=$((warn + 1)); }
fail() { printf '  %s✗%s %s\n' "$R" "$N" "$1"; bad=$((bad + 1)); }
section() { printf '\n%s%s%s\n' "$B" "$1" "$N"; }

section 'Docker'
if ! command -v docker >/dev/null; then fail 'docker not installed'
elif ! docker info >/dev/null 2>&1; then fail 'docker daemon not reachable (running? your user in the docker group?)'
else
    ok "docker $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
    if docker compose version >/dev/null 2>&1; then ok "$(docker compose version --short 2>/dev/null | sed 's/^/compose /')"
    else fail 'docker compose v2 missing (the docker-compose-plugin package)'; fi
    if docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; then ok 'nvidia runtime registered in docker'
    else fail 'no nvidia runtime in docker: install the NVIDIA Container Toolkit, then sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker'; fi
    root=$(docker info --format '{{.DockerRootDir}}' 2>/dev/null)
    free=$(df -BG --output=avail "$root" 2>/dev/null | tail -1 | tr -dc 0-9)
    if [[ -n $free && $free -lt 15 ]]; then meh "only ${free} GB free under $root: a full build needs about 15 GB"
    elif [[ -n $free ]]; then ok "${free} GB free for images under $root"; fi
    if docker image inspect "$RETROPIE_IMAGE" >/dev/null 2>&1; then ok "image $RETROPIE_IMAGE present"
    else meh "image $RETROPIE_IMAGE not built yet: make build (hours)"; fi
fi

section 'NVIDIA'
if command -v nvidia-smi >/dev/null && v=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1) && [[ -n $v ]]; then
    ok "driver $v"
else fail 'no working NVIDIA driver on the host (nvidia-smi): this project targets NVIDIA GPUs'; fi
if command -v nvidia-ctk >/dev/null; then ok "$(nvidia-ctk --version 2>/dev/null | head -1)"
else fail 'nvidia-ctk missing (NVIDIA Container Toolkit)'; fi

section 'Desktop session'
if [[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]]; then ok "Wayland socket $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
else fail "no Wayland socket at $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY: run from a Wayland desktop session (X11-only desktops are not supported)"; fi
if [[ -n ${DISPLAY:-} ]]; then ok "Xwayland DISPLAY=$DISPLAY (Dolphin and some emulators use it)"
else fail 'DISPLAY is empty: Xwayland is required'; fi
if [[ $XAUTHORITY != /dev/null && -r $XAUTHORITY ]]; then ok "X authority cookie $XAUTHORITY"
else meh 'no X authority cookie found: Xwayland clients may be refused'; fi
if [[ -S $XDG_RUNTIME_DIR/pulse/native ]]; then ok 'PulseAudio/PipeWire socket'
else meh "no audio socket at $XDG_RUNTIME_DIR/pulse/native: no sound"; fi
if [[ -S $XDG_RUNTIME_DIR/bus ]]; then ok 'session D-Bus'
else meh 'no session D-Bus socket'; fi

section 'Devices'
if compgen -G '/dev/input/js*' >/dev/null; then ok "controller: $(printf '%s ' /dev/input/js*)"
else meh 'no game controller (/dev/input/js*) connected now'; fi
for d in /dev/dri /dev/snd /dev/uinput; do
    if [[ -e $d ]]; then ok "$d"; else meh "$d missing"; fi
done

section 'Data'
if [[ -d $RETROPIE_DATA_DIR ]]; then
    owner=$(stat -c %u "$RETROPIE_DATA_DIR")
    if [[ $owner == "$PUID" ]]; then ok "data directory $RETROPIE_DATA_DIR (owned by uid $PUID)"
    else meh "data directory owned by uid $owner, container runs as $PUID: set PUID/PGID in .env or chown it (moving data between users)"; fi
else ok "data directory $RETROPIE_DATA_DIR will be created on first start"; fi
if [[ $RETROPIE_EXTERNAL_ROMS == 1 ]]; then
    if [[ -d $RETROPIE_ROMS_DIR ]]; then ok "ROM collection $RETROPIE_ROMS_DIR (mounted read-only, gamelists writable)"
    else fail "RETROPIE_ROMS_DIR=$RETROPIE_ROMS_DIR does not exist"; fi
fi
if command -v python3 >/dev/null; then ok 'python3 (used by the launcher)'; else fail 'python3 missing (the launcher needs it)'; fi

printf '\n'
if ((bad)); then printf '%s%d blocking, %d warnings%s\n' "$R" "$bad" "$warn" "$N"; exit 1; fi
printf '%sReady%s (%d warnings)\n' "$G" "$N" "$warn"
