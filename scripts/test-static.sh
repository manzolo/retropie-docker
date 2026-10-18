#!/bin/bash
# Static checks: no Docker daemon, no GPU, no desktop. What CI can always run.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
fail() { echo "FAIL: $*" >&2; exit 1; }
scripts=(scripts/*.sh retropie/retropie-entrypoint.sh retropie/healthcheck.sh)

bash -n "${scripts[@]}" && echo "PASS: bash syntax (${#scripts[@]} scripts)"
if command -v shellcheck >/dev/null; then
    shellcheck -x "${scripts[@]}" || fail 'shellcheck'
    echo "PASS: shellcheck"
else
    echo "SKIP: shellcheck not installed"
fi

# The image must never install driver libraries: the host injects them.
grep -nE 'install.*(libnvidia|nvidia-driver|nvidia-utils)' retropie/Dockerfile && fail 'retropie/Dockerfile installs NVIDIA driver packages'
echo 'PASS: Dockerfile installs no NVIDIA driver package'
grep -q 'RETROPIE_SETUP_REF=[0-9a-f]\{40\}' retropie/Dockerfile || fail 'RETROPIE_SETUP_REF is not pinned to a full commit'
echo 'PASS: RetroPie-Setup pinned to a commit'

# The emulator selection: the committed Dockerfile is exactly what packages.default generates, a
# custom list lands in its own Dockerfile with the same cache-friendly prefix, and bad input fails.
tmpd=$(mktemp -d); trap 'rm -rf -- "$tmpd"' EXIT
diff <(PACKAGES_FILE=packages.default ./scripts/packages.sh dockerfile) retropie/Dockerfile \
    || fail 'retropie/Dockerfile is out of sync with packages.default: run scripts/packages.sh sync'
echo 'PASS: Dockerfile package block matches packages.default'
cp -a "$ROOT"/{packages.default,packages.catalog,scripts} "$tmpd/"; mkdir -p "$tmpd/retropie"; cp retropie/Dockerfile "$tmpd/retropie/"
printf 'lr-snes9x  # kept first\nlr-genesis-plus-gx\n' > "$tmpd/packages.local"
out=$("$tmpd/scripts/packages.sh" dockerfile)
if ! grep -q 'retropie_packages.sh lr-genesis-plus-gx$' <<<"$out" || grep -q 'retropie_packages.sh dolphin' <<<"$out" \
    || ! grep -q "^# lr-snes9x: kept first$" <<<"$out" || ! grep -qF "printf '%s\\n' lr-snes9x lr-genesis-plus-gx >" <<<"$out"; then
    fail "packages.local does not drive the generated Dockerfile: $out"
fi
echo 'PASS: packages.local generates its own package block'
printf 'lr-snes9x; rm -rf /\n' > "$tmpd/packages.local"
"$tmpd/scripts/packages.sh" dockerfile >/dev/null 2>&1 && fail 'a package line with shell metacharacters was accepted'
printf '# nothing\n' > "$tmpd/packages.local"
"$tmpd/scripts/packages.sh" dockerfile >/dev/null 2>&1 && fail 'an empty package list was accepted'
echo 'PASS: invalid or empty package lists are refused'
# make update: a package rebuilt on top, after the whole list, keeps the cached prefix; never in the
# committed Dockerfile; only packages of the list; a second update of the same package moves it last.
rm -f "$tmpd/packages.local"
(cd "$tmpd" && ./scripts/packages.sh update lr-quicknes >/dev/null && ./scripts/packages.sh update dolphin >/dev/null \
    && ./scripts/packages.sh update lr-quicknes >/dev/null) || fail 'packages.sh update failed'
out=$(cd "$tmpd" && ./scripts/packages.sh dockerfile)
last_pkg=$(grep -n 'retropie_packages.sh lr-vice$' <<<"$out" | cut -d: -f1)
upd=$(grep -n '^RUN : update .*retropie_packages.sh' <<<"$out")
if [[ $(wc -l <<<"$upd") != 2 ]] || [[ ${upd%%:*} -le $last_pkg ]] || ! tail -1 <<<"$upd" | grep -q 'lr-quicknes$' \
    || ! grep -q '> /etc/retropie-docker/updates$' <<<"$out"; then
    fail "update layers are not appended after the package list: $upd"
fi
diff <(cd "$tmpd" && PACKAGES_FILE=packages.default ./scripts/packages.sh dockerfile) "$tmpd/retropie/Dockerfile" >/dev/null \
    || fail 'packages.update leaked into the packages.default rendering'
(cd "$tmpd" && ./scripts/packages.sh update lr-not-in-the-list >/dev/null 2>&1) && fail 'an update of a package outside the list was accepted'
echo 'not-a-name; rm -rf / 2026-10-18T00:00:00' >> "$tmpd/packages.update"
(cd "$tmpd" && ./scripts/packages.sh dockerfile >/dev/null 2>&1) && fail 'a malformed packages.update line was accepted'
if ! (cd "$tmpd" && ./scripts/packages.sh update-clear >/dev/null) || [[ -e $tmpd/packages.update ]]; then
    fail 'update-clear left packages.update'
fi
echo 'PASS: make update appends rebuild layers after the list and stays out of the committed Dockerfile'
if [[ ${SKIP_NETWORK:-0} != 1 ]] && git ls-remote -q https://github.com/RetroPie/RetroPie-Setup.git HEAD >/dev/null 2>&1; then
    ./scripts/packages.sh check packages.default packages.catalog
    printf 'lr-not-a-package\n' > "$tmpd/bogus.list"
    ./scripts/packages.sh check "$tmpd/bogus.list" >/dev/null && fail 'an unknown package name passed the check'
    echo 'PASS: an unknown package name is rejected'
else
    echo 'SKIP: package names against RetroPie-Setup (no network)'
fi

# Retired targets must explain themselves and exit 0, never build or delete anything.
out=$(make -s base-build-nvidia-615 retropie-build-nvidia-595 start-nvidia-580 clean-all 2>&1)
[[ $out == *retired* ]] || fail "retired make targets do not say so: $out"
echo 'PASS: retired make targets explain their replacement'

# Compose must render with the defaults and with an external ROM directory.
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    tmp=$(mktemp -d); trap 'rm -rf -- "$tmp" "$tmpd"' EXIT
    mkdir -p "$tmp/data" "$tmp/roms with spaces/c64"
    touch "$tmp/roms with spaces/c64/gamelist.xml" "$tmp/roms with spaces/c64/game.tap"
    export DISPLAY=${DISPLAY:-:0} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp} HOME=${HOME:-/tmp}
    RETROPIE_DATA_DIR="$tmp/data" ./scripts/retropie.sh config >/dev/null && echo 'PASS: compose renders with defaults'
    rendered=$(RETROPIE_DATA_DIR="$tmp/data" RETROPIE_ROMS_DIR="$tmp/roms with spaces" ./scripts/retropie.sh config)
    grep -q 'read_only: true' <<<"$rendered" || fail 'external ROM mount is not read-only'
    grep -q 'target: /data/roms/c64/gamelist.xml' <<<"$rendered" || fail 'the gamelist of an external collection is not mounted writable'
    grep -q 'game.tap' <<<"$rendered" && fail 'a ROM file got its own writable mount'
    echo 'PASS: compose mounts the gamelists of an external collection writable, nothing else'
    echo 'PASS: compose renders a read-only external ROM mount'
    # GPU and session overrides: forced modes render exactly their pieces, nothing NVIDIA under Mesa.
    mode() { RETROPIE_DATA_DIR="$tmp/data" RETROPIE_GPU=$1 RETROPIE_SESSION=$2 ./scripts/retropie.sh config; }
    rendered=$(mode mesa x11)
    grep -qiE 'runtime: nvidia|NVIDIA_' <<<"$rendered" && fail 'Mesa mode still asks for the NVIDIA runtime'
    grep -qE 'WAYLAND_DISPLAY|wayland-' <<<"$rendered" && fail 'X11 session mounts or names a Wayland socket'
    grep -q 'SDL_VIDEODRIVER: x11' <<<"$rendered" || fail 'X11 session does not set SDL to x11'
    rendered=$(mode nvidia wayland)
    if ! grep -q 'runtime: nvidia' <<<"$rendered" || ! grep -q 'NVIDIA_DRIVER_CAPABILITIES: graphics,display' <<<"$rendered"; then
        fail 'NVIDIA mode lacks the runtime or the graphics capabilities'
    fi
    if ! grep -q 'SDL_VIDEODRIVER: wayland,x11' <<<"$rendered" || ! grep -q "target: /run/user/.*/${WAYLAND_DISPLAY}" <<<"$rendered"; then
        fail 'Wayland session lacks the socket mount or the SDL default'
    fi
    RETROPIE_DATA_DIR="$tmp/data" RETROPIE_SESSION=x11 SDL_VIDEODRIVER=dummy ./scripts/retropie.sh config | grep -q 'SDL_VIDEODRIVER: dummy' \
        || fail 'an explicit SDL_VIDEODRIVER is overridden'
    mode bogus x11 >/dev/null 2>&1 && fail 'RETROPIE_GPU=bogus was accepted'
    echo 'PASS: compose renders Mesa/X11 without NVIDIA or Wayland, NVIDIA/Wayland with both; bad values refused'
else
    echo 'SKIP: docker compose not available'
fi
# Image versions and rollback, on throwaway empty images (no build): two "builds", rollback both
# ways, pruning of old dated tags, and the data backup before the first start of a new image.
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
    repo=retropie-imgtest/x
    export RETROPIE_IMAGE=$repo:latest RETROPIE_KEEP_IMAGES=2
    cleanup_images() { docker image ls "$repo" --format '{{.Repository}}:{{.Tag}}' | xargs -r docker rmi -f >/dev/null 2>&1 || true; }
    cleanup_images
    fake_build() { tar -cf - --files-from /dev/null | docker import -c "LABEL n=$1" - "$repo:latest" >/dev/null; }
    ./scripts/images.sh before-build; fake_build one; ./scripts/images.sh after-build >/dev/null
    first=$(docker image inspect -f '{{.Id}}' "$repo:latest")
    sleep 1; ./scripts/images.sh before-build; fake_build two; ./scripts/images.sh after-build >/dev/null
    second=$(docker image inspect -f '{{.Id}}' "$repo:latest")
    [[ $(docker image inspect -f '{{.Id}}' "$repo:previous") == "$first" ]] || fail 'build did not keep the old image as :previous'
    ./scripts/images.sh rollback >/dev/null
    [[ $(docker image inspect -f '{{.Id}}' "$repo:latest") == "$first" && $(docker image inspect -f '{{.Id}}' "$repo:previous") == "$second" ]] \
        || fail 'rollback did not swap :latest and :previous'
    ./scripts/images.sh rollback >/dev/null
    [[ $(docker image inspect -f '{{.Id}}' "$repo:latest") == "$second" ]] || fail 'a second rollback did not come back'
    for n in 3 4; do sleep 1; ./scripts/images.sh before-build; fake_build "$n"; ./scripts/images.sh after-build >/dev/null; done
    dated=$(docker image ls "$repo" --format '{{.Tag}}' | grep -cE '^[0-9]{8}-[0-9]{6}-')
    [[ $dated == 2 ]] || fail "expected the newest 2 dated versions, found $dated"
    echo 'PASS: builds keep :previous and dated versions, rollback swaps both ways, old versions pruned'
    data=$(mktemp -d); mkdir -p "$data/saves" "$data/roms/snes"; echo save > "$data/saves/a.srm"; echo rom > "$data/roms/snes/b.sfc"
    out=$(RETROPIE_DATA_DIR=$data RETROPIE_BACKUP_DIR=$data-bk ./scripts/data-backup.sh test)
    archive=$(ls "$data-bk"/data-*-test.tar.gz)
    tar -tzf "$archive" | grep -q 'saves/a.srm' || fail "data backup misses the saves: $out"
    tar -tzf "$archive" | grep -q 'roms' && fail 'data backup contains ROMs'
    rm -rf "$data" "$data-bk"; cleanup_images; unset RETROPIE_IMAGE RETROPIE_KEEP_IMAGES
    echo 'PASS: data backup keeps saves and leaves ROMs out'
else
    echo 'SKIP: image versions (no docker daemon)'
fi
# doctor: no desktop session at all must block, with the reason; a forced Wayland without socket too
if out=$(env -u WAYLAND_DISPLAY -u DISPLAY XDG_RUNTIME_DIR=/nonexistent NO_COLOR=1 ./scripts/doctor.sh 2>&1); then
    fail "doctor passed without a desktop session: $out"
fi
grep -q 'no desktop session' <<<"$out" || fail "doctor did not say the desktop session is missing: $out"
out=$(env -u WAYLAND_DISPLAY DISPLAY=:9 XDG_RUNTIME_DIR=/nonexistent RETROPIE_SESSION=wayland NO_COLOR=1 ./scripts/doctor.sh 2>&1) \
    && fail "doctor passed a forced Wayland session without socket: $out"
grep -q 'no Wayland socket' <<<"$out" || fail "doctor did not name the missing Wayland socket: $out"
echo 'PASS: doctor blocks without a desktop session and says why'
echo 'PASS: all static checks'
