#!/bin/bash
# Real Docker integration tests. No host/data writes; no mock GPU successes.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
image=${TEST_IMAGE:-$RETROPIE_IMAGE}
fail() { echo "FAIL: $*" >&2; exit 1; }
echo "Testing image: $image"
docker image inspect "$image" --format 'Image ID: {{.Id}}'
# Force runc even if NVIDIA is the daemon default; do not trust environment alone.
files=$(docker run --rm --runtime=runc --entrypoint /bin/sh "$image" -c \
    'find / -xdev \( -name "libnvidia-*" -o -name nvidia-smi \) -print')
[[ -z $files ]] || fail "Driver files baked into image: $files"
echo 'PASS: clean image, 0 libnvidia-* / nvidia-smi files (runtime=runc)'
# Mesa mode: the image's Mesa must render (EGL without a display) and say it is not NVIDIA.
# The NVIDIA injection tests below need the driver and the toolkit: they run in NVIDIA mode only.
resolve_platform
if [[ $RETROPIE_GPU == mesa ]]; then
    dri=(); [[ -e /dev/dri ]] && dri=(--device /dev/dri)
    out=$(docker run --rm --runtime=runc "${dri[@]}" --entrypoint eglinfo "$image" -B -p surfaceless 2>&1) \
        || fail "Mesa EGL failed: $out"
    renderer=$(grep -m1 'OpenGL core profile renderer' <<<"$out") || fail "Mesa reports no OpenGL renderer: $out"
    echo "PASS: Mesa renders (${renderer#*: })"
    expect=0; docker run --rm --runtime=runc --entrypoint /usr/local/bin/gpu-check "$image" driver >/dev/null 2>&1 || expect=$?
    [[ $expect == 2 ]] || fail "without NVIDIA the driver check must exit 2 (Mesa), got $expect"
    echo 'PASS: Mesa mode, the driver check says Mesa (exit 2), never NVIDIA; NVIDIA tests skipped'
    exit 0
fi
host=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | sort -u)
[[ -n $host ]] || fail 'Cannot read the host NVIDIA driver'
echo "Host driver: $host"
base=(docker run --rm --runtime=nvidia -e NVIDIA_VISIBLE_DEVICES=all
    -e "NVIDIA_DRIVER_CAPABILITIES=graphics,display,video,compute,utility"
    --entrypoint /usr/local/bin/gpu-check)
"${base[@]}" -e "EXPECTED_DRIVER_VERSION=$host" "$image" driver
# Runtime-mounted files plus clean image establish that driver userspace comes from the host.
"${base[@]}" "$image" inventory

expect_failure() {
    local label=$1 expected_rc=$2 expected_text=$3 output rc=0
    shift 3
    output=$("$@" 2>&1) || rc=$?
    echo "$output"
    [[ $rc == "$expected_rc" && $output == *"$expected_text"* ]] || \
        fail "$label: expected exit $expected_rc containing '$expected_text', got exit $rc"
    echo "PASS: deliberate failure rejected ($label, exit $rc)"
}
# Positive NVML query in compute-only mode proves runtime startup itself works.
"${base[@]}" -e NVIDIA_DRIVER_CAPABILITIES=compute,utility -e "EXPECTED_DRIVER_VERSION=$host" "$image" driver
expect_failure 'compute-only graphics' 1 'NVIDIA graphics capabilities missing' \
    "${base[@]}" -e NVIDIA_DRIVER_CAPABILITIES=compute,utility "$image" graphics
expect_failure 'no NVIDIA runtime' 2 'No NVIDIA GPU, falling back to Mesa' \
    docker run --rm --runtime=runc --entrypoint /usr/local/bin/gpu-check "$image" graphics
expect_failure 'fake expected driver' 1 'Driver mismatch: expected 0.0.0-test' \
    "${base[@]}" -e EXPECTED_DRIVER_VERSION=0.0.0-test "$image" driver

[[ -n ${DISPLAY:-} ]] || fail 'DISPLAY missing: run tests from the Wayland desktop (Xwayland required)'
[[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ]] || fail "Wayland socket missing: $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
graphics=(--user "$PUID:$PGID" --network host --device /dev/dri
    -e "DISPLAY=$DISPLAY" -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" -e "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
    -e XAUTHORITY=/tmp/retropie.xauth
    --mount "type=bind,src=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY,dst=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY,readonly"
    --mount "type=bind,src=/tmp/.X11-unix,dst=/tmp/.X11-unix,readonly"
    --mount "type=bind,src=$XAUTHORITY,dst=/tmp/retropie.xauth,readonly")
for device in /dev/dri/*; do
    [[ -c $device ]] && graphics+=(--group-add "$(stat -c '%g' "$device")")
done
"${base[@]}" "${graphics[@]}" "$image" graphics
echo 'PASS: all driver-agnostic integration tests'
