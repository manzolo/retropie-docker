#!/bin/bash
# Diagnose the runtime, never select an image based on the driver's version.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
if [[ ${1:-} == --driver-only ]]; then
    expected=${EXPECTED_DRIVER_VERSION:-$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | sort -u)}
    exec docker run --rm --runtime=nvidia -e NVIDIA_VISIBLE_DEVICES=all \
        -e NVIDIA_DRIVER_CAPABILITIES=graphics,display,video,compute,utility \
        -e "EXPECTED_DRIVER_VERSION=$expected" --entrypoint /usr/local/bin/gpu-check "$RETROPIE_IMAGE" driver
fi
exec "$ROOT/scripts/test-driver-agnostic.sh"
