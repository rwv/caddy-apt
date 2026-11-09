#!/usr/bin/env bash
set -euo pipefail
source packaging/versions.env
version=$1
tag=$version-$REVISION
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/pool/main"
for package in "artifacts/$version/"*/*.deb; do
    gh attestation verify "$package" --repo "$GITHUB_REPOSITORY" --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"
    cp "$package" "$stage/pool/main/"
done
(
    cd "$stage"
    dpkg-scanpackages --multiversion pool /dev/null > Packages
    sha256sum pool/main/*.deb > SHA256SUMS
)
if gh release view "$tag" >/dev/null 2>&1; then
    gh release upload "$tag" "$stage"/pool/main/*.deb "$stage/Packages" "$stage/SHA256SUMS" --clobber
else
    gh release create "$tag" --draft --target "$GITHUB_SHA" --title "Caddy ${version#v} package revision $REVISION" --notes "Build provenance is available for each Debian package." "$stage"/pool/main/*.deb "$stage/Packages" "$stage/SHA256SUMS"
fi
gh release edit "$tag" --draft=false
