#!/usr/bin/env bash
set -euo pipefail
source packaging/versions.env
published=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[] | select(.draft == false) | .tag_name')
if [[ -n ${REQUESTED_VERSION:-} ]]; then
    candidates=$REQUESTED_VERSION
else
    candidates=$(gh api --paginate 'repos/caddyserver/caddy/releases?per_page=100' --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' | sort -Vu)
fi
versions=()
while read -r version; do
    [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    dpkg --compare-versions "${version#v}" ge "${CADDY_VERSION#v}" || continue
    grep -Fxq "$version-$REVISION" <<< "$published" && continue
    versions+=("$version")
done <<< "$candidates"
if (("${#versions[@]}" > 0)); then
    printf '%s\n' "${versions[@]}" | jq -Rsc 'split("\n")[:-1]'
else
    echo '[]'
fi
