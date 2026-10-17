#!/bin/bash
# Static checks: no Docker daemon, no GPU, no desktop. What CI can always run.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail() { echo "FAIL: $*" >&2; exit 1; }
scripts=(scripts/*.sh retropie/retropie-entrypoint.sh retropie/healthcheck.sh)

bash -n "${scripts[@]}" && echo "PASS: bash syntax (${#scripts[@]} scripts)"
if command -v shellcheck >/dev/null; then
    shellcheck -x "${scripts[@]}" && echo "PASS: shellcheck"
else
    echo "SKIP: shellcheck not installed"
fi

# The image must never install driver libraries: the host injects them.
grep -nE 'install.*(libnvidia|nvidia-driver|nvidia-utils)' retropie/Dockerfile && fail 'retropie/Dockerfile installs NVIDIA driver packages'
echo 'PASS: Dockerfile installs no NVIDIA driver package'
grep -q 'RETROPIE_SETUP_REF=[0-9a-f]\{40\}' retropie/Dockerfile || fail 'RETROPIE_SETUP_REF is not pinned to a full commit'
echo 'PASS: RetroPie-Setup pinned to a commit'

# Retired targets must explain themselves and exit 0, never build or delete anything.
out=$(make -s base-build-nvidia-615 retropie-build-nvidia-595 start-nvidia-580 clean-all 2>&1)
[[ $out == *retired* ]] || fail "retired make targets do not say so: $out"
echo 'PASS: retired make targets explain their replacement'

# Compose must render with the defaults and with an external ROM directory.
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    tmp=$(mktemp -d); trap 'rm -rf -- "$tmp"' EXIT
    mkdir -p "$tmp/data" "$tmp/roms with spaces"
    export DISPLAY=${DISPLAY:-:0} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp} HOME=${HOME:-/tmp}
    RETROPIE_DATA_DIR="$tmp/data" ./scripts/retropie.sh config >/dev/null && echo 'PASS: compose renders with defaults'
    rendered=$(RETROPIE_DATA_DIR="$tmp/data" RETROPIE_ROMS_DIR="$tmp/roms with spaces" ./scripts/retropie.sh config)
    grep -q 'read_only: true' <<<"$rendered" || fail 'external ROM mount is not read-only'
    echo 'PASS: compose renders a read-only external ROM mount'
else
    echo 'SKIP: docker compose not available'
fi
echo 'PASS: all static checks'
