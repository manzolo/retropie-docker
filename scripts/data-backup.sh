#!/bin/bash
# data-backup.sh [REASON]: the data directory without ROMs, as backups/data-<date>[-reason].tar.gz.
# Saves, states, configuration and BIOS; ROMs are excluded (large, and an external collection is
# never written anyway). The launcher calls it before the first start of a different image.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
dir=${RETROPIE_BACKUP_DIR:-$ROOT/backups}
[[ -d $RETROPIE_DATA_DIR ]] || { echo "No data directory at $RETROPIE_DATA_DIR: nothing to back up"; exit 0; }
mkdir -p "$dir"
out="$dir/data-$(date +%Y%m%d-%H%M%S)${1:+-$1}.tar.gz"
tar -czf "$out" --exclude='./roms' -C "$RETROPIE_DATA_DIR" .
echo "Data backup: $out ($(du -h "$out" | cut -f1))"
