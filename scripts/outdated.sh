#!/bin/bash
# What changed upstream since the image was built, without building anything (make outdated).
#   emulators       the commit each retropie.pkg in the image records vs the head of its branch upstream
#   RetroPie-Setup  commits after the one the image was built from, and the installed modules they touch
#   base            the ubuntu digest pinned in the Dockerfile vs the one the registry serves now
# Read-only: the image is created (never started) to copy those files out; upstream is asked with
# git ls-remote and a blob-less fetch of RetroPie-Setup into .cache/. Nothing is pulled or built.
set -euo pipefail
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
cd "$ROOT"
setup_url=${RETROPIE_SETUP_URL:-https://github.com/RetroPie/RetroPie-Setup.git}
export GIT_TERMINAL_PROMPT=0
docker image inspect "$RETROPIE_IMAGE" >/dev/null 2>&1 || { echo "No image $RETROPIE_IMAGE: build it first (make build)" >&2; exit 1; }

tmp=$(mktemp -d); cid=
trap '[[ -n $cid ]] && docker rm "$cid" >/dev/null; rm -rf -- "$tmp"' EXIT
cid=$(docker create "$RETROPIE_IMAGE" true)
mkdir -p "$tmp/pkg" "$tmp/res"
docker cp "$cid:/opt/retropie" - | tar -x -C "$tmp/pkg" --wildcards '*/retropie.pkg'
image_ref=$(docker cp "$cid:/home/$CONTAINER_USERNAME/RetroPie-Setup/.git/HEAD" - 2>/dev/null | tar -xO || true)
docker cp "$cid:/etc/retropie-docker/packages" - 2>/dev/null | tar -xO > "$tmp/listed" || true

# retropie.pkg is shell assignments written by RetroPie-Setup: read it as data, never source it
field() { sed -nE "s/^$1=\"(.*)\"$/\1/p" "$2"; }

check() {   # check NAME PKGFILE: one line "status<TAB>name<TAB>detail" into res/NAME
    local name=$1 f=$2 type url branch commit refs head want
    type=$(field pkg_repo_type "$f"); url=$(field pkg_repo_url "$f")
    branch=$(field pkg_repo_branch "$f"); commit=$(field pkg_repo_commit "$f")
    if [[ $type != git || -z $url || -z $commit ]]; then
        printf 'unchecked\t%s\t%s\n' "$name" "not built from one git repository ($(field pkg_origin "$f")${type:+ $type})"; return
    fi
    if [[ $branch =~ ^[0-9a-f]{40}$ ]]; then printf 'pinned\t%s\t%s\n' "$name" "commit ${branch:0:8}"; return; fi
    want=(HEAD); [[ -n $branch ]] && want=("refs/heads/$branch" "refs/tags/$branch")
    if ! refs=$(timeout 30 git ls-remote "$url" "${want[@]}" 2>/dev/null); then
        printf 'unchecked\t%s\t%s\n' "$name" "$url not reachable"; return
    fi
    head=$(awk -v r="refs/heads/$branch" -v b="$branch" '$2 == r || (b == "" && $2 == "HEAD") { print $1; exit }' <<<"$refs")
    if [[ -n $head ]]; then
        if [[ $head == "$commit"* ]]; then printf 'current\t%s\t%s\n' "$name" "${branch:-HEAD} ${commit:0:8}"
        else printf 'newer\t%s\t%s\n' "$name" "${branch:-HEAD} ${commit:0:8} -> ${head:0:8}"; fi
    elif grep -q "refs/tags/$branch" <<<"$refs"; then
        printf 'pinned\t%s\t%s\n' "$name" "tag $branch"
    else
        printf 'unchecked\t%s\t%s\n' "$name" "$branch not found upstream"
    fi
}

while IFS= read -r f; do
    name=$(basename "$(dirname "$f")")
    check "$name" "$f" > "$tmp/res/$name" &
done < <(find "$tmp/pkg" -name retropie.pkg | sort)
wait
cat "$tmp/res"/* > "$tmp/all" 2>/dev/null || true

listed() { grep -qx -- "$1" "$tmp/listed"; }
in_list() { ./scripts/packages.sh list | grep -qx -- "$1"; }
show() {   # show STATUS TITLE
    grep -q "^$1	" "$tmp/all" || return 0
    echo "  $2"
    grep "^$1	" "$tmp/all" | sort -k2 | while IFS=$'\t' read -r _ name detail; do
        origin=basic_install; listed "$name" && origin=list
        printf '    %-22s %-16s %s\n' "$name" "($origin)" "$detail"
    done
}

echo "Image: $RETROPIE_IMAGE, built $(docker image inspect -f '{{.Created}}' "$RETROPIE_IMAGE" | cut -c1-16 | tr T ' ')"
echo
echo "Emulators ($(wc -l < "$tmp/all") installed; commit in the image -> upstream)"
show newer 'Newer upstream: make update rebuilds them in minutes'
show pinned 'Pinned by RetroPie-Setup (a tag or a commit): they move only with a RetroPie-Setup bump'
show unchecked 'Not checked'
echo "  Up to date: $(grep -c '^current	' "$tmp/all" || true)"

echo
pin=$(sed -nE 's/^ARG RETROPIE_SETUP_REF=([0-9a-f]{40})$/\1/p' retropie/Dockerfile)
image_ref=${image_ref:-$pin}
echo "RetroPie-Setup (image ${image_ref:0:8}, Dockerfile pin ${pin:0:8})"
[[ $image_ref == "$pin" ]] || echo "  The Dockerfile pins another commit than the image was built from: the next build changes it."
if ! master=$(timeout 30 git ls-remote "$setup_url" refs/heads/master 2>/dev/null | cut -f1) || [[ -z $master ]]; then
    echo "  Not checked: $setup_url not reachable"
elif [[ $master == "$image_ref" ]]; then
    echo "  Up to date with master"
else
    cache=.cache/retropie-setup.git
    [[ -d $cache ]] || git init -q --bare "$cache"
    git -C "$cache" remote add origin "$setup_url" 2>/dev/null || git -C "$cache" remote set-url origin "$setup_url"
    # trees and commits only: enough to name the changed modules, no file content is downloaded
    if ! err=$(git -C "$cache" fetch -q --filter=blob:none origin +refs/heads/master:refs/heads/master 2>&1); then
        echo "  Not checked: fetch failed: $err"
    elif ! git -C "$cache" merge-base --is-ancestor "$image_ref" master 2>/dev/null; then
        echo "  master ${master:0:8} does not contain ${image_ref:0:8} (history rewritten?): compare by hand"
    else
        echo "  master is $(git -C "$cache" rev-list --count "$image_ref..master") commit(s) ahead (${master:0:8}):"
        git -C "$cache" log --format='    %h %s' "$image_ref..master" | head -10
        touched=$(git -C "$cache" diff --name-only "$image_ref" master -- scriptmodules \
            | sed -nE 's|^scriptmodules/[^/]+/([^/]+)\.sh$|\1|p' | sort -u)
        installed=$(cut -f2 "$tmp/all" | sort -u)
        hit=$(comm -12 <(echo "$touched") <(echo "$installed") | paste -sd ' ')
        other=$(comm -23 <(echo "$touched") <(echo "$installed") | paste -sd ' ')
        core=$(git -C "$cache" diff --name-only "$image_ref" master | grep -cvE '^scriptmodules/[^/]+/[^/]+\.sh$' || true)
        echo "  Installed modules changed: ${hit:-none}"
        [[ -n $other ]] && echo "  Other modules changed (not installed): $other"
        ((core)) && echo "  $core file(s) outside the modules changed (shared helpers: affect every package)"
        echo "  Taking it: bump RETROPIE_SETUP_REF in retropie/Dockerfile and rebuild everything (hours)."
    fi
fi

echo
from=$(sed -nE 's/^FROM ([^ ]+)@(sha256:[0-9a-f]{64}) AS graphics$/\1 \2/p' retropie/Dockerfile)
base=${from% *} digest=${from#* }
echo "Base image ($base ${digest:7:12})"
if [[ ${OUTDATED_BASE:-1} == 0 ]]; then
    echo "  Not checked (OUTDATED_BASE=0)"
elif ! now=$(timeout 30 docker buildx imagetools inspect "$base" 2>/dev/null | sed -nE 's/^Digest:[[:space:]]+(sha256:[0-9a-f]{64})$/\1/p') || [[ -z $now ]]; then
    echo "  Not checked: the registry did not answer (docker buildx imagetools inspect $base)"
elif [[ $now == "$digest" ]]; then
    echo "  Up to date"
else
    echo "  The registry serves a newer $base (${now:7:12}): Ubuntu updates, security fixes included."
    echo "  Taking it: replace the digest in retropie/Dockerfile and rebuild everything (hours)."
fi

echo
update=() rest=()
while IFS=$'\t' read -r _ name _; do
    if in_list "$name"; then update+=("$name"); else rest+=("$name"); fi
done < <(grep '^newer	' "$tmp/all" || true)
if ((${#update[@]})); then echo "Suggested: make update PKG=\"${update[*]}\""; fi
if ((${#rest[@]})); then
    echo "Newer but not in your package list (they come with basic_install): ${rest[*]}"
    echo "  append them to your package list (packages.local) to build them on top, or wait for the next full rebuild"
fi
((${#update[@]} + ${#rest[@]})) || echo 'Nothing to update with make update.'
