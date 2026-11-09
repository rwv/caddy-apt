#!/usr/bin/env bash
set -euo pipefail
: "${R2_ENDPOINT:?}" "${AWS_ACCESS_KEY_ID:?}" "${AWS_SECRET_ACCESS_KEY:?}" "${APT_SIGNING_KEY:?}"
repo_root=$(cd "$(dirname "$0")/.." && pwd)
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
cd "$stage"
export GNUPGHOME=$stage/gpg AWS_DEFAULT_REGION=auto AWS_REQUEST_CHECKSUM_CALCULATION=when_required
install -d -m700 "$GNUPGHOME"
printf '%s' "$APT_SIGNING_KEY" | base64 -d | gpg --batch --import
fingerprint=$(gpg --batch --with-colons --show-keys "$repo_root/caddy-apt.gpg" | awk -F: '$1=="fpr" { print $10; exit }')
immutable='public, max-age=31536000, immutable'
mutable='no-cache, max-age=0, must-revalidate'
r2() {
    aws --endpoint-url "$R2_ENDPOINT" s3api "$@" --bucket caddy-apt
}
put() {
    local key=$1 file=$2 cache=$3 type=$4
    shift 4
    r2 put-object --key "$key" --body "$file" --cache-control "$cache" --content-type "$type" "$@" >/dev/null
}
ensure_package() {
    local tag=$1 key=$2 digest=$3 existing
    if existing=$(r2 head-object --key "$key" --query Metadata.sha256 --output text 2>head-error); then
        [[ $existing == "$digest" ]] || { echo "Digest mismatch for immutable object $key" >&2; return 1; }
        return
    fi
    if ! grep -q '(404)' head-error; then
        cat head-error >&2
        return 1
    fi
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern "${key##*/}" --output package.deb --clobber
    printf '%s  package.deb\n' "$digest" | sha256sum --check --status
    gh attestation verify package.deb --repo "$GITHUB_REPOSITORY" --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/release.yml"
    put "$key" package.deb "$immutable" application/vnd.debian.binary-package --if-none-match '*' --metadata "sha256=$digest"
}
tags=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' | sort -Vr)
[[ -n $tags ]]
touch combined
while read -r tag; do
    [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || continue
    gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern Packages --output fragment --clobber
    pairs=$(awk 'BEGIN {RS=""; FS="\n"} {for(i=1;i<=NF;i++){if($i~/^Filename: /) file=substr($i,11); if($i~/^SHA256: /) hash=substr($i,9)} print file,hash}' fragment)
    while read -r path hash; do
        ensure_package "$tag" "$path" "$hash"
    done <<< "$pairs"
    cat fragment >> combined
done <<< "$tags"
[[ -s combined ]]
for arch in amd64 arm64; do
    dir=dists/stable/main/binary-$arch
    mkdir -p "$dir"
    awk -v arch="$arch" 'BEGIN{RS="";ORS="\n\n"} $0 ~ "(^|\n)Architecture: (" arch "|all)(\n|$)" {match($0, /(^|\n)Filename: [^\n]+/); if(!seen[substr($0,RSTART,RLENGTH)]++) print}' combined > "$dir/Packages"
    gzip -n -k "$dir/Packages"
done
apt-ftparchive -o APT::FTPArchive::Release::Origin=Caddy-APT \
    -o APT::FTPArchive::Release::Label=Caddy-APT \
    -o APT::FTPArchive::Release::Suite=stable \
    -o APT::FTPArchive::Release::Codename=stable \
    -o 'APT::FTPArchive::Release::Architectures=amd64 arm64' \
    -o APT::FTPArchive::Release::Components=main \
    -o APT::FTPArchive::Release::Acquire-By-Hash=yes release dists/stable > Release
gpg --batch --local-user "$fingerprint" --clearsign --output InRelease Release
for file in dists/stable/main/binary-*/Packages*; do
    digest=$(sha256sum "$file" | cut -d ' ' -f1)
    key="${file%/*}/by-hash/SHA256/$digest"
    if ! r2 head-object --key "$key" >/dev/null 2>&1; then
        put "$key" "$file" "$immutable" application/octet-stream --if-none-match '*'
    fi
    put "$file" "$file" "$mutable" application/octet-stream
done
put caddy-apt.gpg "$repo_root/caddy-apt.gpg" "$mutable" application/pgp-keys
put dists/stable/InRelease InRelease "$mutable" text/plain
