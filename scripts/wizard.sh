#!/bin/bash
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
echo 'RetroPie: one image, host-injected NVIDIA driver libraries.'
docker compose version
[[ -f .env ]] || cp .env.example .env
if [[ -z ${BUILD:-} ]]; then
    read -r -p "Data directory [$RETROPIE_DATA_DIR]: " selected
    export RETROPIE_DATA_DIR=${selected:-$RETROPIE_DATA_DIR}
    read -r -p 'Existing external ROM directory (blank: use data/roms): ' selected
    export RETROPIE_ROMS_DIR=$selected
    # Store paths as dotenv values. common.sh does not execute their contents.
    python3 - "$RETROPIE_DATA_DIR" "$RETROPIE_ROMS_DIR" <<'PY'
from pathlib import Path
import sys
p = Path('.env')
lines = [s for s in p.read_text().splitlines() if not s.startswith(('RETROPIE_DATA_DIR=', 'RETROPIE_ROMS_DIR='))]
lines += ['RETROPIE_DATA_DIR=' + sys.argv[1], 'RETROPIE_ROMS_DIR=' + sys.argv[2]]
p.write_text('\n'.join(lines) + '\n')
PY
    echo "Emulators: $(./scripts/packages.sh list | tr '\n' ' ')"
    read -r -p 'Change the emulator selection? [y/N]: ' selected
    [[ ${selected,,} == y* ]] && ./scripts/packages.sh choose
    echo '1) Build and start  2) Build only  3) Start existing image  4) Exit'
    read -r -p 'Choice [1]: ' choice
    case ${choice:-1} in 1) BUILD=full;; 2) BUILD=retropie;; 3) BUILD=skip;; 4) exit 0;; *) exit 1;; esac
fi
case $BUILD in
    full|all) ./scripts/retropie.sh build; ./scripts/retropie.sh start ;;
    retropie|retropie-only) ./scripts/retropie.sh build ;;
    skip|start|none) ./scripts/retropie.sh start ;;
    base|base-image) echo 'The base is now an internal Dockerfile stage. Use BUILD=retropie or BUILD=full.'; exit 1 ;;
    *) echo 'BUILD must be full, retropie or skip' >&2; exit 1 ;;
esac
