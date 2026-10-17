#!/bin/bash
# Refuse to publish game data or private material.
#
# Scans every path reachable from every ref (the whole history, not only HEAD), the text
# content of HEAD, and the untracked files of the working tree. `--self-test` builds a
# throwaway repository, checks that a clean one passes, injects a fake BIOS and checks
# that it is rejected: a scanner that never fails proves nothing.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# Directories and extensions that only ever hold ROMs, BIOS, saves, scraped artwork or secrets.
FORBIDDEN_PATHS='(^|/)(roms|bios|saves|states|downloaded_images|downloaded_media|gamelists?)(/|$)'
FORBIDDEN_PATHS+='|\.(sfc|smc|nes|gba|gbc|gb|n64|z64|v64|gen|sms|gg|pce|iso|chd|cue|bin|img|cso|pbp|rvz|gcm|gcz|wbfs|nds|3ds|zip|7z|rar|srm|sav|dsv|mcr|mcd|state[0-9]*)$'
FORBIDDEN_PATHS+='|(^|/)\.env$|(^|/)id_(rsa|ed25519|ecdsa)(\.pub)?$|\.(pem|key|p12|pfx)$'
# Text that must not appear in committed files: private hosts, LAN addresses, private keys.
FORBIDDEN_TEXT='[a-z0-9-]+\.lan([^a-z0-9.-]|$)|192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY'

scan_repo() {
    local repo=$1 rc=0 hits
    hits=$(git -C "$repo" rev-list --all --objects | awk 'NF>1{print $2}' | sort -u | grep -iE "$FORBIDDEN_PATHS" || true)
    if [[ -n $hits ]]; then
        echo "FAIL: forbidden paths somewhere in the history (rewrite it, do not just delete them):"
        echo "$hits" | head -40 | sed 's/^/  /'
        rc=1
    fi
    hits=$(git -C "$repo" grep -nIE "$FORBIDDEN_TEXT" HEAD -- . ':!scripts/check-public.sh' 2>/dev/null | sed 's/^HEAD://' || true)
    if [[ -n $hits ]]; then
        echo "FAIL: forbidden text in HEAD:"
        echo "$hits" | head -20 | sed 's/^/  /'
        rc=1
    fi
    hits=$(git -C "$repo" ls-files --others --exclude-standard | grep -iE "$FORBIDDEN_PATHS" || true)
    if [[ -n $hits ]]; then
        echo "WARN: untracked files that must never be added:"
        echo "$hits" | head -20 | sed 's/^/  /'
    fi
    [[ $rc -eq 0 ]] && echo "PASS: no game data, secrets or private hosts in $repo (all refs)"
    return $rc
}

self_test() {
    local tmp
    tmp=$(mktemp -d /tmp/check-public.XXXXXX)
    trap 'rm -rf -- "$tmp"' RETURN
    local -a g=(git -C "$tmp" -c user.name=check -c user.email=check@example.invalid -c commit.gpgsign=false)
    git init -q "$tmp"
    printf '# clean\n' > "$tmp/README.md"
    "${g[@]}" add README.md && "${g[@]}" commit -qm clean
    scan_repo "$tmp" >/dev/null || { echo 'self-test FAIL: a clean repository must pass'; return 1; }
    mkdir -p "$tmp/data/BIOS/dc"
    head -c 2048 /dev/urandom > "$tmp/data/BIOS/dc/dc_boot.bin"
    "${g[@]}" add -f data && "${g[@]}" commit -qm 'injected BIOS'
    "${g[@]}" rm -rq data && "${g[@]}" commit -qm 'deleted again (still in history)'
    if scan_repo "$tmp" >/dev/null 2>&1; then
        echo 'self-test FAIL: an injected BIOS, even after deletion, must be rejected'
        return 1
    fi
    printf 'registry: docker-hub.lan\n' > "$tmp/notes.txt"
    "${g[@]}" add notes.txt && "${g[@]}" commit -qm 'private host'
    local out
    out=$(scan_repo "$tmp" 2>&1 || true)
    if [[ $out == *'forbidden text'* ]]; then
        echo 'PASS: self-test (clean passes; injected BIOS in history and private host rejected)'
    else
        echo 'self-test FAIL: a private host name must be rejected'
        return 1
    fi
}

case ${1:-scan} in
    scan) scan_repo "$ROOT" ;;
    --self-test) self_test ;;
    *) echo 'Usage: check-public.sh [--self-test]' >&2; exit 1 ;;
esac
