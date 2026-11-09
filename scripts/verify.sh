#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
origin=https://caddy-apt.rwv.dev
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
curl -fsS "$origin/caddy-apt.gpg" | cmp - "$root/caddy-apt.gpg"

curl -fsS -D headers -o InRelease "$origin/dists/stable/InRelease"
grep -Eiq '^cache-control:.*(no-cache|no-store)' headers
gpgv --keyring "$root/caddy-apt.gpg" --output Release InRelease
for arch in amd64 arm64; do
    dir=main/binary-$arch
    digest=$(awk -v path="$dir/Packages.gz" '/^SHA256:/{sha=1;next} /^[^ ]/{sha=0} sha && $3==path{print $1}' Release)
    curl -fsS -D headers -o Packages.gz "$origin/dists/stable/$dir/by-hash/SHA256/$digest"
    grep -Eiq '^cache-control:.*immutable' headers
    printf '%s  Packages.gz\n' "$digest" | sha256sum --check
    gzip -dc Packages.gz > Packages
    for manifest in "$root"/packaging/plugins/*; do
        package=caddy-${manifest##*/}
        read -r path digest < <(awk -v package="$package" 'BEGIN{RS="";FS="\n"} $0 ~ "(^|\n)Package: " package "(\n|$)" {for(i=1;i<=NF;i++){if($i~/^Filename: /) file=substr($i,11); if($i~/^SHA256: /) hash=substr($i,9)} print file,hash; exit}' Packages)
        curl -fsS -D headers -o package.deb "$origin/$path"
        grep -Eiq '^cache-control:.*immutable' headers
        printf '%s  package.deb\n' "$digest" | sha256sum --check
        test "$(dpkg-deb -f package.deb Architecture)" = "$arch"
    done
done
