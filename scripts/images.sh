#!/bin/bash
# Image versions and rollback. :latest is what runs; every build also leaves a dated tag
# (<date>-<commit>, the newest RETROPIE_KEEP_IMAGES are kept) and :previous (what :latest was).
#   images.sh before-build   tag the current :latest as :previous
#   images.sh after-build    add the dated tag to the new :latest, prune old dated tags
#   images.sh rollback       swap :latest and :previous (recreate the container afterwards)
#   images.sh list           the versions on this machine
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
repo=${RETROPIE_IMAGE%:latest}
keep=${RETROPIE_KEEP_IMAGES:-3}
exists() { docker image inspect "$1" >/dev/null 2>&1; }
id_of() { docker image inspect --format '{{.Id}}' "$1"; }

case ${1:-list} in
    before-build)
        if exists "$repo:latest"; then docker tag "$repo:latest" "$repo:previous"; fi ;;
    after-build)
        stamp=$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
        docker tag "$repo:latest" "$repo:$stamp"
        echo "Image versions: $repo:latest = $repo:$stamp"
        # dated tags sort by name; untagging never deletes an image another tag still uses
        docker image ls "$repo" --format '{{.Tag}}' | grep -E '^[0-9]{8}-[0-9]{6}-' | sort -r | tail -n +"$((keep + 1))" \
            | while read -r old; do docker rmi "$repo:$old" >/dev/null && echo "Removed old version $repo:$old"; done ;;
    rollback)
        exists "$repo:previous" || { echo "No $repo:previous to go back to (it appears after the next build)" >&2; exit 1; }
        if [[ $(id_of "$repo:previous") == "$(id_of "$repo:latest" 2>/dev/null || true)" ]]; then
            echo ":previous is the same image as :latest: nothing to roll back" >&2; exit 1
        fi
        current=$(id_of "$repo:latest")
        docker tag "$repo:previous" "$repo:latest"
        docker tag "$current" "$repo:previous"
        echo "Rolled back: $repo:latest is the previous image; the one you left is now :previous."
        echo "Recreate the container to use it: make stop && make start" ;;
    list)
        docker image ls "$repo" --format 'table {{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}' ;;
    *) echo 'Usage: images.sh {before-build|after-build|rollback|list}' >&2; exit 1 ;;
esac
