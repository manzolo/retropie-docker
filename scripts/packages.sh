#!/bin/bash
# Emulator selection: packages.local (yours, ignored by git) or packages.default (the shipped set).
#   packages.sh list              effective package names, one per line
#   packages.sh dockerfile [OUT]  retropie/Dockerfile with the package block generated from the list
#   packages.sh sync              rewrite the block in retropie/Dockerfile from packages.default
#   packages.sh check [FILE...]   every name exists in RetroPie-Setup at the pinned commit
#   packages.sh choose            checklist from packages.catalog, writes packages.local
#   packages.sh update PKG...     rebuild these packages from upstream on top of the image (packages.update)
#   packages.sh update-clear      forget the updates (the next full rebuild folds them in anyway)
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
DOCKERFILE=retropie/Dockerfile
BEGIN='# >>> packages (generated from packages.default by scripts/packages.sh: edit that file, not this block)'
END='# <<< packages'

UPDATE_FILE=packages.update

# "name<TAB>stamp" for every update line; only when rendering the effective list (not packages.default)
updates() {
    [[ -z ${PACKAGES_FILE:-} && -f $UPDATE_FILE ]] || return 0
    sed -E 's/\r$//' "$UPDATE_FILE" | while read -r name stamp _; do
        [[ -z $name || $name == \#* ]] && continue
        printf '%s\t%s\n' "$name" "$stamp"
    done
}

source_file() {   # PACKAGES_FILE overrides (the static test renders packages.default on purpose)
    if [[ -n ${PACKAGES_FILE:-} ]]; then echo "$PACKAGES_FILE"
    elif [[ -f packages.local ]]; then echo packages.local; else echo packages.default; fi
}

# "name<TAB>comment" for every package line of a list file.
entries() {
    sed -E 's/\r$//' "$1" | while IFS= read -r line; do
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        name=${line%%#*}; name=${name//[[:space:]]/}
        comment=; [[ $line == *'#'* ]] && comment=$(sed -E 's/^[^#]*#[[:space:]]*//' <<<"$line")
        printf '%s\t%s\n' "$name" "$comment"
    done
}

block() {
    local list=$1 names=()
    echo "$BEGIN"
    echo '# One layer per package: a package that fails to build does not discard the ones already built.'
    while IFS=$'\t' read -r name comment; do
        [[ $name =~ ^[a-z0-9][a-z0-9.+-]*$ ]] || { echo "invalid package name in $list: $name" >&2; exit 1; }
        [[ -n $comment ]] && echo "# $name: $comment"
        echo "RUN cd RetroPie-Setup && sudo ./retropie_packages.sh $name"
        names+=("$name")
    done < <(entries "$list")
    ((${#names[@]})) || { echo "$list lists no package" >&2; exit 1; }
    local upd=()
    while IFS=$'\t' read -r name stamp; do
        [[ $name =~ ^[a-z0-9][a-z0-9.+-]*$ && $stamp =~ ^[0-9T:-]+$ ]] || { echo "invalid line in $UPDATE_FILE: $name $stamp" >&2; exit 1; }
        printf '%s\n' "${names[@]}" | grep -qx -- "$name" || { echo "$UPDATE_FILE: $name is not in $list (add it there instead)" >&2; exit 1; }
        ((${#upd[@]})) || echo "# Updates from $UPDATE_FILE: rebuilt from upstream on top, everything above comes from the cache"
        echo "RUN : update $stamp && cd RetroPie-Setup && sudo ./retropie_packages.sh $name"
        upd+=("$name@$stamp")
    done < <(updates)
    echo 'USER root'
    printf "RUN mkdir -p /etc/retropie-docker && printf '%%s\\\\n' %s > /etc/retropie-docker/packages\n" "${names[*]}"
    ((${#upd[@]})) && printf "RUN printf '%%s\\\\n' %s > /etc/retropie-docker/updates\n" "${upd[*]}"
    echo "$END"
}

render() {   # render LIST: the Dockerfile with its block replaced
    local generated
    generated=$(block "$1")
    # the block goes through the environment: awk -v would turn \n into a newline
    BLOCK=$generated awk -v b="$BEGIN" -v e="$END" '
        $0 == b { print ENVIRON["BLOCK"]; skip = 1; found++; next }
        $0 == e { skip = 0; next }
        !skip { print }
        END { if (found != 1) { print "package markers missing from Dockerfile" > "/dev/stderr"; exit 1 } }' "$DOCKERFILE"
}

pinned_ref() { sed -nE 's/^ARG RETROPIE_SETUP_REF=([0-9a-f]{40})$/\1/p' "$DOCKERFILE"; }

known() {   # every package name of RetroPie-Setup at the pinned commit, cached in .cache/
    local ref list
    ref=$(pinned_ref); list=.cache/retropie-setup-$ref.packages
    if [[ ! -s $list ]]; then
        local dir; dir=$(mktemp -d)
        # names only: a blob-less fetch carries the trees, no file content is downloaded
        git -C "$dir" init -q
        git -C "$dir" fetch -q --depth=1 --filter=blob:none https://github.com/RetroPie/RetroPie-Setup.git "$ref"
        mkdir -p .cache
        git -C "$dir" ls-tree -r --name-only FETCH_HEAD scriptmodules \
            | sed -nE 's|^scriptmodules/[^/]+/([^/]+)\.sh$|\1|p' | sort -u > "$list.tmp"
        rm -rf "$dir"; mv "$list.tmp" "$list"
    fi
    echo "$list"
}

case ${1:-list} in
    list) entries "$(source_file)" | cut -f1 ;;
    dockerfile)
        if [[ -n ${2:-} ]]; then mkdir -p "$(dirname "$2")"; render "$(source_file)" > "$2"; else render "$(source_file)"; fi ;;
    sync)
        tmp=$(mktemp); render packages.default > "$tmp" && mv "$tmp" "$DOCKERFILE" && echo "$DOCKERFILE updated from packages.default" ;;
    check)
        shift; files=("$@"); ((${#files[@]})) || files=(packages.default packages.catalog)
        [[ -f packages.local ]] && (($# == 0)) && files+=(packages.local)
        list=$(known); bad=0
        for f in "${files[@]}"; do
            if [[ $f == *.catalog ]]; then found=$(grep -v '^#' "$f" | cut -d'|' -f1); else found=$(entries "$f" | cut -f1); fi
            for n in $found; do
                grep -qx -- "$n" "$list" || { echo "FAIL: $f: '$n' is not a RetroPie-Setup package at $(pinned_ref | cut -c1-12)"; bad=1; }
            done
        done
        ((bad == 0)) && echo "PASS: package names exist in RetroPie-Setup (${files[*]})"
        exit "$bad" ;;
    choose)
        command -v whiptail >/dev/null || { echo 'whiptail is not installed: copy packages.default to packages.local and edit it' >&2; exit 1; }
        mapfile -t current < <(entries "$(source_file)" | cut -f1)
        items=()
        while IFS='|' read -r name systems note; do
            [[ $name == \#* || -z $name ]] && continue
            state=OFF; for c in "${current[@]}"; do [[ $c == "$name" ]] && state=ON; done
            items+=("$name" "$systems${note:+ · $note}" "$state")
        done < packages.catalog
        chosen=$(whiptail --title 'Emulators in the image' --separate-output --checklist \
            'Space toggles, Enter confirms. Packages you keep stay in their order (no rebuild); new ones are appended.' \
            30 100 22 "${items[@]}" 3>&1 1>&2 2>&3) || { echo 'Cancelled, nothing written.'; exit 0; }
        {
            echo '# Your emulator selection (make packages-choose). Append new packages at the end to keep the build cache.'
            # keep the current order for what stays (cache), then the new ones in catalog order
            # packages written by hand (not in the catalog) are never dropped by the checklist
            for c in "${current[@]}"; do
                if grep -qx -- "$c" <<<"$chosen" || ! cut -d'|' -f1 packages.catalog | grep -qx -- "$c"; then echo "$c"; fi
            done
            while IFS= read -r n; do
                [[ -n $n ]] || continue
                printf '%s\n' "${current[@]}" | grep -qx -- "$n" || echo "$n"
            done <<<"$chosen"
        } > packages.local
        echo "packages.local written ($(entries packages.local | wc -l) packages). make build to apply." ;;
    update)
        shift; (($#)) || { echo 'Usage: packages.sh update PKG...' >&2; exit 1; }
        mapfile -t current < <(entries "$(source_file)" | cut -f1)
        for n in "$@"; do
            printf '%s\n' "${current[@]}" | grep -qx -- "$n" || { echo "$n is not in $(source_file): add it to the list instead of updating it" >&2; exit 1; }
        done
        stamp=$(date +%Y-%m-%dT%H:%M:%S)
        {
            echo '# Packages rebuilt from upstream on top of the image (make update). Order matters like in the'
            echo '# package list: a line rebuilds everything after it. make update-clear forgets them.'
            # a package updated again moves to the end with its new stamp
            [[ -f $UPDATE_FILE ]] && grep -vE '^[[:space:]]*(#|$)' "$UPDATE_FILE" | while read -r name old _; do
                printf '%s\n' "$@" | grep -qx -- "$name" || echo "$name $old"
            done
            for n in "$@"; do echo "$n $stamp"; done
        } > "$UPDATE_FILE.tmp" && mv "$UPDATE_FILE.tmp" "$UPDATE_FILE"
        echo "$UPDATE_FILE: $* at $stamp. make build to apply." ;;
    update-clear) rm -f "$UPDATE_FILE"; echo "$UPDATE_FILE removed: the next build uses the cached layers (a fresh build folds updates in)" ;;
    *) echo 'Usage: packages.sh {list|dockerfile [OUT]|sync|check [FILE...]|choose|update PKG...|update-clear}' >&2; exit 1 ;;
esac
