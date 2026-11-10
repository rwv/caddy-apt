#!/usr/bin/env bash
set -euo pipefail
source packaging/versions.env
published=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[] | select(.draft == false and .prerelease == false) | {tag: .tag_name, assets: [.assets[].name]}' | jq -s '.')
if [[ -n ${REQUESTED_VERSION:-} ]]; then
    [[ $REQUESTED_VERSION =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
    candidates=$REQUESTED_VERSION
else
    candidates=$(gh api --paginate 'repos/caddyserver/caddy/releases?per_page=100' --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' | sort -Vu)
fi

queue_package() {
    local package=$1 upstream=$2 tag=$3 version=$4
    shift 4
    if [[ -n ${REQUESTED_PACKAGE:-} && $package != "$REQUESTED_PACKAGE" ]]; then
        return 0
    fi
    local arch
    if jq -e --arg tag "$tag" 'any(.[]; .tag == $tag)' <<< "$published" >/dev/null; then
        return 0
    fi
    for arch; do
        if ! jq -e --arg asset "${package}_${version}_$arch.deb" --arg prefix "${package}_${version%%+*}+" \
            --arg suffix "_$arch.deb" 'any(.[]; any(.assets[]; . == $asset or (startswith($prefix) and endswith($suffix))))' <<< "$published" >/dev/null; then
            jq -nc --arg package "$package" --arg upstream "$upstream" --arg tag "$tag" \
                '{package: $package, upstream: $upstream, tag: $tag}'
            return
        fi
    done
}

{
    queue_package caddy-apt-common '' "caddy-apt-common/v$COMMON_VERSION" "$COMMON_VERSION" all
    while read -r upstream; do
        [[ $upstream =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
        dpkg --compare-versions "${upstream#v}" ge "${CADDY_VERSION#v}" || continue
        for manifest in packaging/plugins/*; do
            package=caddy-${manifest##*/}
            {
                read -r revision revision_upstream
                [[ $upstream == "$revision_upstream" ]] || revision=1
                version=${upstream#v}-$revision
                separator=+
                while read -r label module pinned id; do
                    version+="$separator$label${pinned#v}"
                    separator=.
                done
            } < "$manifest"
            queue_package "$package" "$upstream" "$package/$upstream-$revision" "$version" amd64 arm64
        done
    done <<< "$candidates"
} | jq -cs '{releases: ., builds: [ .[] as $job | (if $job.package == "caddy-apt-common" then ["all"] else ["amd64", "arm64"] end)[] as $arch | $job + {arch: $arch, runner: (if $arch == "arm64" then "ubuntu-24.04-arm" else "ubuntu-24.04" end)}]}'
