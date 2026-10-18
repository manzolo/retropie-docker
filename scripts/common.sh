#!/bin/bash
# Shared host-side settings. Read dotenv as data, never execute it as shell code.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -f $ROOT/.env ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^([A-Za-z_][A-Za-z_0-9]*)=(.*)$ ]] || continue
        key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        [[ $value == \"*\" || $value == \'*\' ]] && value=${value:1:${#value}-2}
        # Explicit shell environment overrides the file.
        [[ -v $key ]] || export "$key=$value"
    done < "$ROOT/.env"
fi
export CONTAINER_USERNAME=${CONTAINER_USERNAME:-manzolo}
export CONTAINER_NAME=${CONTAINER_NAME:-retropie-container}
export PUID=${PUID:-$(id -u)} PGID=${PGID:-$(id -g)}
export RETROPIE_IMAGE=${RETROPIE_IMAGE:-${REGISTRY_BASE_URL:-docker.io}/${IMAGE_OWNER:-manzolo}/${IMAGE_NAME:-retropie}:latest}
[[ $RETROPIE_IMAGE == *:latest ]] || { echo 'RETROPIE_IMAGE must use the latest tag' >&2; exit 1; }
absolute_path() {
    local path=$1
    # Match a literal tilde from dotenv, then expand it ourselves.
    # shellcheck disable=SC2088
    [[ $path == '~/'* ]] && path="$HOME/${path:2}"
    [[ $path == /* ]] || path="$ROOT/$path"
    realpath -m -- "$path"
}
RETROPIE_DATA_DIR=$(absolute_path "${RETROPIE_DATA_DIR:-./data}")
export RETROPIE_DATA_DIR RETROPIE_ROMS_DIR
export RETROPIE_EXTERNAL_ROMS=0
if [[ -n ${RETROPIE_ROMS_DIR:-} ]]; then
    RETROPIE_ROMS_DIR=$(absolute_path "$RETROPIE_ROMS_DIR")
    export RETROPIE_EXTERNAL_ROMS=1
fi
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$PUID}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}
# Mount an existing cookie read-only; do not call xhost or modify host authorization.
if [[ -z ${XAUTHORITY:-} ]]; then
    for candidate in "$XDG_RUNTIME_DIR"/xauth_* "$XDG_RUNTIME_DIR"/.mutter-Xwaylandauth.* "$HOME/.Xauthority"; do
        if [[ -f $candidate ]]; then export XAUTHORITY=$candidate; break; fi
    done
fi
export XAUTHORITY=${XAUTHORITY:-/dev/null}
# GPU and desktop session, resolved only by the scripts that need them (docker info is not free).
# RETROPIE_GPU: nvidia (host driver injected by the NVIDIA Container Toolkit) or mesa (the image's
# own Mesa: Intel, AMD, or software rendering); auto = nvidia when both the runtime and a driver work.
# RETROPIE_SESSION: wayland or x11; auto = wayland when its socket exists.
resolve_platform() {
    case ${RETROPIE_GPU:=auto} in
        auto) if nvidia_runtime && nvidia_driver >/dev/null; then RETROPIE_GPU=nvidia; else RETROPIE_GPU=mesa; fi ;;
        nvidia|mesa) ;;
        *) echo "RETROPIE_GPU must be auto, nvidia or mesa (got $RETROPIE_GPU)" >&2; return 1 ;;
    esac
    case ${RETROPIE_SESSION:=auto} in
        auto) if [[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]]; then RETROPIE_SESSION=wayland; else RETROPIE_SESSION=x11; fi ;;
        wayland|x11) ;;
        *) echo "RETROPIE_SESSION must be auto, wayland or x11 (got $RETROPIE_SESSION)" >&2; return 1 ;;
    esac
    # SDL and GTK follow the session unless .env forces them (SDL_VIDEODRIVER=x11 under Wayland)
    if [[ $RETROPIE_SESSION == wayland ]]; then
        export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-wayland,x11} GDK_BACKEND=${GDK_BACKEND:-wayland,x11}
    else
        export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-x11} GDK_BACKEND=${GDK_BACKEND:-x11}
    fi
    export RETROPIE_GPU RETROPIE_SESSION
}
nvidia_runtime() { docker info --format '{{json .Runtimes}}' 2>/dev/null | grep -q '"nvidia"'; }
nvidia_driver() {
    command -v nvidia-smi >/dev/null || return 1
    local v; v=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
    [[ -n $v ]] && echo "$v"
}
