#!/bin/bash
# Optional hardware smoke test; no sound playback or controller events required.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
fixture=$(mktemp -d /tmp/retropie-desktop-test.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
docker run --rm --runtime=runc \
    -e "PUID=$PUID" -e "PGID=$PGID" -e SDL_VIDEODRIVER=x11 \
    --device /dev/input --device /dev/uinput --device /dev/snd \
    --mount "type=bind,src=$fixture,dst=/data" \
    --mount "type=bind,src=$XDG_RUNTIME_DIR/pulse,dst=/run/user/$PUID/pulse,readonly" \
    -e "PULSE_SERVER=unix:/run/user/$PUID/pulse/native" \
    "${TEST_IMAGE:-$RETROPIE_IMAGE}" /bin/bash -euc '
    id
    pactl info
    python3 -c '\''import os; fd = os.open("/dev/input/js0", os.O_RDONLY | os.O_NONBLOCK); os.close(fd); print("PASS: non-root user can open /dev/input/js0")'\''
    echo "PASS: PulseAudio connection and controller device permissions"
'
