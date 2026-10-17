#!/bin/bash
# shellcheck disable=SC2016
# Single-quoted scripts intentionally expand inside the container.
# Persistence tests use only fresh /tmp fixtures, never the configured data/ROM tree.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
image=${TEST_IMAGE:-$RETROPIE_IMAGE}
fixture=$(mktemp -d /tmp/retropie-data-test.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/data" "$fixture/external-roms"
printf 'known read-only ROM fixture\n' > "$fixture/external-roms/fixture.sfc"
rom_before=$(sha256sum "$fixture/external-roms/fixture.sfc")
run=(docker run --rm --runtime=runc -e "PUID=$PUID" -e "PGID=$PGID"
    -e "EXPECTED_UID=$PUID" -e SDL_VIDEODRIVER=x11
    --mount "type=bind,src=$fixture/data,dst=/data")
"${run[@]}" "$image" /bin/bash -euc '
    test "$(id -u)" = "$EXPECTED_UID"
    test -s /opt/retropie/configs/all/retroarch.cfg
    test -s /etc/emulationstation/es_systems.cfg
    for cfg in /opt/retropie/configs/*/emulators.cfg; do
        grep -q "^default" "$cfg" || { echo "FAIL: no default emulator in $cfg (runcommand would refuse to launch)"; exit 1; }
    done
    test -d "$HOME/RetroPie/roms"
    test -d "$HOME/RetroPie/BIOS"
    test "$(readlink -f "$HOME/.emulationstation")" = /data/configs/all/emulationstation
    test "$(readlink -f "$HOME/.config/dolphin-emu")" = /data/configs/gc/Config
    test "$(readlink -f "$HOME/.local/share/dolphin-emu")" = /data/configs/gc/local
    grep -Fx "savefile_directory = \"/data/saves\"" /data/configs/all/retroarch.cfg
    grep -Fx "savestate_directory = \"/data/states\"" /data/configs/all/retroarch.cfg
    printf "known-save" > /data/saves/probe.srm
    printf "known-state" > /data/states/probe.state
    printf "known-config" > /data/configs/probe.cfg
    mkdir -p "$HOME/.local/share/dolphin-emu/GC"
    printf "known-card" > "$HOME/.local/share/dolphin-emu/GC/probe.raw"
    printf "# retained custom setting\n" >> /data/configs/all/retroarch.cfg
    test -s /opt/retropie/libretrocores/lr-snes9x/snes9x_libretro.so
    test -x /opt/retropie/emulators/dolphin/bin/dolphin-emu
    echo "PASS: defaults, user mapping and emulator paths"
'
# An es_systems.cfg from an older image must gain the systems the image has now, and keep its own.
python3 - "$fixture/data/emulationstation/es_systems.cfg" <<'PY'
import sys, xml.etree.ElementTree as ET
p = sys.argv[1]; tree = ET.parse(p); root = tree.getroot()
victim = next(s for s in root.findall('system') if s.findtext('name') == 'c64')
root.remove(victim)
keep = ET.SubElement(root, 'system'); ET.SubElement(keep, 'name').text = 'test-kept'; ET.SubElement(keep, 'path').text = '/tmp'
tree.write(p, encoding='utf-8', xml_declaration=True)
PY
"${run[@]}" "$image" /bin/bash -euc '
    grep -q "<name>c64</name>" /etc/emulationstation/es_systems.cfg
    grep -q "<name>test-kept</name>" /etc/emulationstation/es_systems.cfg
    echo "PASS: es_systems.cfg gained the missing c64 system and kept its own entries"
'
"${run[@]}" -e RETROPIE_EXTERNAL_ROMS=1 \
    --mount "type=bind,src=$fixture/external-roms,dst=/data/roms,readonly" \
    "$image" /bin/bash -euc '
    test "$(cat /data/saves/probe.srm)" = known-save
    test "$(cat /data/states/probe.state)" = known-state
    test "$(cat /data/configs/probe.cfg)" = known-config
    test "$(cat /data/configs/gc/local/GC/probe.raw)" = known-card
    grep -Fx "# retained custom setting" /data/configs/all/retroarch.cfg
    test "$(cat "$HOME/RetroPie/roms/fixture.sfc")" = "known read-only ROM fixture"
    if touch /data/roms/forbidden 2>/tmp/write-error; then
        echo "FAIL: external ROMs unexpectedly writable"; exit 1
    fi
    grep "Read-only file system" /tmp/write-error
    echo "PASS: persistence across recreation; external ROMs read-only"
'
[[ $(sha256sum "$fixture/external-roms/fixture.sfc") == "$rom_before" ]]
[[ $(find "$fixture/external-roms" -type f | wc -l) == 1 ]]
echo 'PASS: external ROM fixture unchanged; all portable-data tests'
