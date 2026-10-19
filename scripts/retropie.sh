#!/bin/bash
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
compose=(docker compose --project-directory "$ROOT" -f "$ROOT/retropie/docker-compose.yml")
if [[ ${1:-} =~ ^(start|stop|enter|logs|config)$ ]]; then
    resolve_platform
    [[ $RETROPIE_GPU == nvidia ]] && compose+=(-f "$ROOT/retropie/docker-compose.nvidia.yml")
    [[ $RETROPIE_SESSION == wayland ]] && compose+=(-f "$ROOT/retropie/docker-compose.wayland.yml")
fi
if [[ $RETROPIE_EXTERNAL_ROMS == 1 ]]; then
    compose+=(-f "$ROOT/retropie/docker-compose.roms.yml")
    # The collection is read-only, but EmulationStation saves favourites, play counts and edits to the
    # gamelist.xml it read, which sits in the collection: mount those files (only those) writable.
    gamelists=$ROOT/retropie/docker-compose.gamelists.yml
    if [[ -d $RETROPIE_ROMS_DIR ]]; then
        python3 - "$RETROPIE_ROMS_DIR" "$gamelists" <<'PY'
import glob, json, os, sys
roms, out = sys.argv[1], sys.argv[2]
mounts = [{"type": "bind", "source": f, "target": "/data/roms/" + os.path.relpath(f, roms), "read_only": False}
          for f in sorted(glob.glob(os.path.join(glob.escape(roms), "*", "gamelist.xml"))) if os.access(f, os.W_OK)]
# JSON is valid YAML for Compose; an empty volume list is fine
open(out, "w").write(json.dumps({"services": {"retropie-service": {"volumes": mounts}}}, indent=1) + "\n")
PY
        compose+=(-f "$gamelists")
    fi
fi
if [[ -f $ROOT/retropie/docker-compose.override.yml ]]; then
    compose+=(-f "$ROOT/retropie/docker-compose.override.yml")
fi
case ${1:-help} in
    build)
        # packages.local (your emulator selection) or packages.update get their own generated Dockerfile
        dockerfile=retropie/Dockerfile
        if [[ -f packages.local || -f packages.update ]]; then
            dockerfile=build/Dockerfile
            ./scripts/packages.sh dockerfile "$dockerfile"
            [[ -f packages.local ]] && echo "Emulators from packages.local: $(./scripts/packages.sh list | tr '\n' ' ')"
            [[ -f packages.update ]] && echo "Updates on top: $(grep -vE '^[[:space:]]*(#|$)' packages.update | tr '\n' ' ')"
        fi
        old=$(./scripts/images.sh current)
        docker build -f "$dockerfile" --build-arg "CONTAINER_USERNAME=$CONTAINER_USERNAME" \
            --build-arg "CONTAINER_UID=$PUID" --build-arg "CONTAINER_GID=$PGID" -t "$RETROPIE_IMAGE" . 
        ./scripts/images.sh after-build "$old" ;;
    start)
        if [[ $RETROPIE_SESSION == wayland && ! -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]]; then
            echo "Missing Wayland socket $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" >&2; exit 1
        fi
        [[ -n ${DISPLAY:-} ]] || { echo 'DISPLAY is required (X11, or Xwayland for Dolphin)' >&2; exit 1; }
        echo "GPU: $RETROPIE_GPU · session: $RETROPIE_SESSION (RETROPIE_GPU / RETROPIE_SESSION in .env to force)"
        if [[ $RETROPIE_EXTERNAL_ROMS == 1 && ! -d $RETROPIE_ROMS_DIR ]]; then
            echo "External ROM directory does not exist: $RETROPIE_ROMS_DIR" >&2; exit 1
        fi
        if [[ -d $RETROPIE_DATA_DIR/opt/retropie/configs && ! -d $RETROPIE_DATA_DIR/configs ]]; then
            echo 'Legacy data layout detected. Migrate to a new data directory using the README before starting.' >&2
            exit 1
        fi
        mkdir -p "$RETROPIE_DATA_DIR"
        # first start of a different image: back the data up before its entrypoint migrates anything
        image_id=$(docker image inspect --format '{{.Id}}' "$RETROPIE_IMAGE" 2>/dev/null || true)
        marker=$RETROPIE_DATA_DIR/.retropie-image
        if [[ -n $image_id && -s $marker && $(cat "$marker") != "$image_id" ]]; then
            ./scripts/data-backup.sh "before-${image_id:7:12}"
        fi
        [[ -n $image_id ]] && printf '%s\n' "$image_id" > "$marker"
        "${compose[@]}" up -d ;;
    stop) "${compose[@]}" down ;;
    enter) "${compose[@]}" exec --user "$PUID:$PGID" retropie-service /bin/bash ;;
    logs) "${compose[@]}" logs -f ;;
    config) "${compose[@]}" config ;;
    push) docker push "$RETROPIE_IMAGE" ;;
    debug-display)
        resolve_platform
        printf 'RETROPIE_GPU=%s\nRETROPIE_SESSION=%s\n' "$RETROPIE_GPU" "$RETROPIE_SESSION"
        printf 'DISPLAY=%s\nWAYLAND_DISPLAY=%s\nXDG_RUNTIME_DIR=%s\nXAUTHORITY=%s\n' "${DISPLAY:-}" "$WAYLAND_DISPLAY" "$XDG_RUNTIME_DIR" "$XAUTHORITY" ;;
    *) echo 'Usage: retropie.sh {build|start|stop|enter|logs|config|push|debug-display}' >&2; exit 1 ;;
esac
