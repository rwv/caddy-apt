#!/usr/bin/env bash
set -euo pipefail
source packaging/versions.env
version=$1
tag=$version-$REVISION
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/pool/main"
common_asset=caddy-apt-common_${COMMON_VERSION}_all.deb
common_tag=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
    --jq ".[] | select(.draft == false and any(.assets[]; .name == \"$common_asset\")) | .tag_name" | sed -n '1p')
if [[ -n $common_tag ]]; then
    gh release download "$common_tag" --pattern "$common_asset" --dir "$stage/pool/main"
    gh attestation verify "$stage/pool/main/$common_asset" --repo "$GITHUB_REPOSITORY" --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"
fi
for package in "artifacts/$version/"*/*.deb; do
    gh attestation verify "$package" --repo "$GITHUB_REPOSITORY" --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"
    [[ -f $stage/pool/main/${package##*/} ]] || cp "$package" "$stage/pool/main/"
done
(
    cd "$stage"
    dpkg-scanpackages --multiversion pool /dev/null > Packages
    sha256sum pool/main/*.deb > SHA256SUMS
)
if ! tagged_commit=$(git ls-remote origin "refs/tags/$tag" | cut -f1); then
    exit 1
fi
if [[ -z $tagged_commit ]]; then
    gh api -X POST "repos/$GITHUB_REPOSITORY/git/refs" -f ref="refs/tags/$tag" -f sha="$GITHUB_SHA" >/dev/null
elif [[ $tagged_commit != "$GITHUB_SHA" ]]; then
    echo "Release tag $tag points to a different build commit." >&2
    exit 1
fi
if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$stage"/pool/main/*.deb "$stage/Packages" "$stage/SHA256SUMS" --clobber
else
    gh release create "$tag" --verify-tag --draft --title "Caddy ${version#v} package revision $REVISION" --notes "Build provenance is available for each Debian package." "$stage"/pool/main/*.deb "$stage/Packages" "$stage/SHA256SUMS"
fi
gh release edit "$tag" --draft=false
