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
