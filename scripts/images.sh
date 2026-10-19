#!/bin/bash
# Image versions and rollback. :latest is what runs; every build also leaves a dated tag
# (<date>-<commit>, the newest RETROPIE_KEEP_IMAGES are kept) and :previous (what :latest was).
#   images.sh current        the image ID of :latest, empty if there is none (record it before a build)
#   images.sh after-build ID the build succeeded: ID becomes :previous if :latest changed; dated tag, prune
#   images.sh rollback       swap :latest and :previous (recreate the container afterwards)
#   images.sh list           the versions on this machine
# A failed or interrupted build never reaches after-build, and a build that produced the same image
# leaves :previous alone: either way rollback still goes back to the image before the last real change.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
repo=${RETROPIE_IMAGE%:latest}
keep=${RETROPIE_KEEP_IMAGES:-3}
exists() { docker image inspect "$1" >/dev/null 2>&1; }
id_of() { docker image inspect --format '{{.Id}}' "$1"; }

case ${1:-list} in
    current)
        if exists "$repo:latest"; then id_of "$repo:latest"; fi ;;
    after-build)
        old=${2:-}
        if [[ -n $old && $old != "$(id_of "$repo:latest")" ]] && exists "$old"; then docker tag "$old" "$repo:previous"; fi
        stamp=$(date +%Y%m%d-%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
        docker tag "$repo:latest" "$repo:$stamp"
        echo "Image versions: $repo:latest = $repo:$stamp"
        # dated tags sort by name; untagging never deletes an image another tag still uses
        docker image ls "$repo" --format '{{.Tag}}' | grep -E '^[0-9]{8}-[0-9]{6}-' | sort -r | tail -n +"$((keep + 1))" \
            | while read -r tag; do docker rmi "$repo:$tag" >/dev/null && echo "Removed old version $repo:$tag"; done ;;
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
    *) echo 'Usage: images.sh {current|after-build [OLD_ID]|rollback|list}' >&2; exit 1 ;;
esac
