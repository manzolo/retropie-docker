#!/bin/bash
# shellcheck disable=SC2016
# Single-quoted scripts intentionally expand inside the container.
# Persistence tests use only fresh /tmp fixtures, never the configured data/ROM tree.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
image=${TEST_IMAGE:-$RETROPIE_IMAGE}
# set -e alone stops without a word (that hid a broken check once): say where it stopped
trap 'echo "FAIL: scripts/test-data.sh line $LINENO" >&2' ERR
fixture=$(mktemp -d /tmp/retropie-data-test.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT
mkdir "$fixture/data" "$fixture/external-roms"
printf 'known read-only ROM fixture\n' > "$fixture/external-roms/fixture.sfc"
mkdir "$fixture/external-roms/snes"
printf '<gameList><game><path>./a.sfc</path><name>A</name></game></gameList>\n' > "$fixture/external-roms/snes/gamelist.xml"
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
    has() { grep -qx "$1" /etc/retropie-docker/packages; }
    if has dolphin; then
        test "$(readlink -f "$HOME/.config/dolphin-emu")" = /data/configs/gc/Config
        test "$(readlink -f "$HOME/.local/share/dolphin-emu")" = /data/configs/gc/local
    fi
    grep -Fx "savefile_directory = \"/data/saves\"" /data/configs/all/retroarch.cfg
    grep -Fx "savestate_directory = \"/data/states\"" /data/configs/all/retroarch.cfg
    printf "known-save" > /data/saves/probe.srm
    printf "known-state" > /data/states/probe.state
    printf "known-config" > /data/configs/probe.cfg
    mkdir -p "$HOME/.local/share/dolphin-emu/GC"
    printf "known-card" > "$HOME/.local/share/dolphin-emu/GC/probe.raw"
    printf "# retained custom setting\n" >> /data/configs/all/retroarch.cfg
    for p in $(cat /etc/retropie-docker/packages); do
        ls -d /opt/retropie/*/"$p" >/dev/null 2>&1 || { echo "FAIL: package $p is listed but not installed"; exit 1; }
    done
    if has lr-snes9x; then test -s /opt/retropie/libretrocores/lr-snes9x/snes9x_libretro.so; fi
    if has dolphin; then test -x /opt/retropie/emulators/dolphin/bin/dolphin-emu; fi
    echo "PASS: defaults, user mapping and emulator paths"
'
# An es_systems.cfg from an older image must gain the systems the image has now, and keep its own.
# The victim is the last system: whatever the package selection, the image has it.
victim=$(python3 - "$fixture/data/emulationstation/es_systems.cfg" <<'PY'
import sys, xml.etree.ElementTree as ET
p = sys.argv[1]; tree = ET.parse(p); root = tree.getroot()
victim = root.findall('system')[-1]
print(victim.findtext('name'))
root.remove(victim)
keep = ET.SubElement(root, 'system'); ET.SubElement(keep, 'name').text = 'test-kept'; ET.SubElement(keep, 'path').text = '/tmp'
tree.write(p, encoding='utf-8', xml_declaration=True)
PY
)
"${run[@]}" -e "VICTIM=$victim" "$image" /bin/bash -euc '
    grep -q "<name>$VICTIM</name>" /etc/emulationstation/es_systems.cfg
    grep -q "<name>test-kept</name>" /etc/emulationstation/es_systems.cfg
    echo "PASS: es_systems.cfg gained the missing $VICTIM system and kept its own entries"
'
# As the launcher does (docker-compose.gamelists.yml): the collection read-only, its gamelists writable,
# because EmulationStation saves favourites and play counts into the gamelist.xml it read.
"${run[@]}" -e RETROPIE_EXTERNAL_ROMS=1 \
    --mount "type=bind,src=$fixture/external-roms,dst=/data/roms,readonly" \
    --mount "type=bind,src=$fixture/external-roms/snes/gamelist.xml,dst=/data/roms/snes/gamelist.xml" \
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
    if touch /data/roms/snes/other.xml 2>/dev/null; then
        echo "FAIL: a non-gamelist file in the collection is writable"; exit 1
    fi
    # in place, as EmulationStation does (pugixml save_file): no temporary file next to it
    updated=$(sed "s|<name>A</name>|<name>A</name><favorite>true</favorite>|" /data/roms/snes/gamelist.xml)
    printf "%s\n" "$updated" > /data/roms/snes/gamelist.xml
    echo "PASS: persistence across recreation; external ROMs read-only except their gamelists"
'
[[ $(sha256sum "$fixture/external-roms/fixture.sfc") == "$rom_before" ]]
grep -q "<favorite>true</favorite>" "$fixture/external-roms/snes/gamelist.xml" \
    || { echo 'FAIL: a favourite saved in the container did not reach the gamelist on the host'; exit 1; }
echo 'PASS: gamelist edits made in the container reach the collection'
# nothing else appeared in the collection: just the ROM and the gamelist it was given
extra=$(find "$fixture/external-roms" -type f ! -path "$fixture/external-roms/fixture.sfc" ! -path "$fixture/external-roms/snes/gamelist.xml")
[[ -z $extra ]] || { echo "FAIL: files appeared in the read-only collection: $extra"; exit 1; }
echo 'PASS: external ROM fixture unchanged; all portable-data tests'
