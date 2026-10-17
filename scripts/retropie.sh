#!/bin/bash
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
compose=(docker compose --project-directory "$ROOT" -f "$ROOT/retropie/docker-compose.yml")
if [[ $RETROPIE_EXTERNAL_ROMS == 1 ]]; then
    compose+=(-f "$ROOT/retropie/docker-compose.roms.yml")
fi
if [[ -f $ROOT/retropie/docker-compose.override.yml ]]; then
    compose+=(-f "$ROOT/retropie/docker-compose.override.yml")
fi
case ${1:-help} in
    build)
        docker build -f retropie/Dockerfile --build-arg "CONTAINER_USERNAME=$CONTAINER_USERNAME" \
            --build-arg "CONTAINER_UID=$PUID" --build-arg "CONTAINER_GID=$PGID" -t "$RETROPIE_IMAGE" . ;;
    start)
        [[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || { echo 'Missing Wayland socket' >&2; exit 1; }
        [[ -n ${DISPLAY:-} ]] || { echo 'DISPLAY is required for Dolphin/Xwayland' >&2; exit 1; }
        if [[ $RETROPIE_EXTERNAL_ROMS == 1 && ! -d $RETROPIE_ROMS_DIR ]]; then
            echo "External ROM directory does not exist: $RETROPIE_ROMS_DIR" >&2; exit 1
        fi
        if [[ -d $RETROPIE_DATA_DIR/opt/retropie/configs && ! -d $RETROPIE_DATA_DIR/configs ]]; then
            echo 'Legacy data layout detected. Migrate to a new data directory using the README before starting.' >&2
            exit 1
        fi
        mkdir -p "$RETROPIE_DATA_DIR"
        "${compose[@]}" up -d ;;
    stop) "${compose[@]}" down ;;
    enter) "${compose[@]}" exec --user "$PUID:$PGID" retropie-service /bin/bash ;;
    logs) "${compose[@]}" logs -f ;;
    config) "${compose[@]}" config ;;
    push) docker push "$RETROPIE_IMAGE" ;;
    debug-display)
        printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nXAUTHORITY=%s\n' "${DISPLAY:-}" "$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR" "$XAUTHORITY" ;;
    *) echo 'Usage: retropie.sh {build|start|stop|enter|logs|config|push|debug-display}' >&2; exit 1 ;;
esac
