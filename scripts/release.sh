#!/usr/bin/env bash
set -euo pipefail
package=$1
tag=$2
artifact_id=${tag//\//-}
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/pool/main"
if [[ $package == caddy-apt-common ]]; then
    architectures=(all)
else
    architectures=(amd64 arm64)
fi
for arch in "${architectures[@]}"; do
    files=(artifacts/"$artifact_id-$arch"/*.deb)
    deb=${files[0]}
    if [[ ${#files[@]} != 1 || ! -f $deb ]]; then
        echo "Missing unique $arch artifact for $tag" >&2
        exit 1
    fi
    test "$(dpkg-deb -f "$deb" Package)" = "$package"
    test "$(dpkg-deb -f "$deb" Architecture)" = "$arch"
    gh attestation verify "$deb" --repo "$GITHUB_REPOSITORY" --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"
    cp "$deb" "$stage/pool/main/"
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
    gh release create "$tag" --verify-tag --draft --title "$package $(dpkg-deb -f "$deb" Version)" --notes "Build provenance is available for each Debian package." "$stage"/pool/main/*.deb "$stage/Packages" "$stage/SHA256SUMS"
fi
gh release edit "$tag" --draft=false
