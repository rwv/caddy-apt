#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source packaging/versions.env
CADDY_VERSION=${1:-$CADDY_VERSION}
arch=$(dpkg --print-architecture)
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
mkdir -p out
export CGO_ENABLED=0 GOBIN="$build"
go install "github.com/caddyserver/xcaddy/cmd/xcaddy@$XCADDY_VERSION"

for manifest in packaging/plugins/*; do
    variant=${manifest##*/}
    package=caddy-$variant
    root=$build/$package
    args=()
    while read -r label module version id; do
        args+=(--with "$module@$version")
    done < "$manifest"

    install -d "$root/usr/bin" "$root/DEBIAN" "$root/usr/share/doc/$package"
    "$build/xcaddy" build "$CADDY_VERSION" "${args[@]}" --output "$root/usr/bin/caddy"
    binary=$root/usr/bin/caddy
    build_info=$(go version -m "$binary")
    actual_caddy=$(awk '$1 == "dep" && $2 == "github.com/caddyserver/caddy/v2" {print $3}' <<< "$build_info")
    test "$actual_caddy" = "$CADDY_VERSION"
    version=${CADDY_VERSION#v}-$REVISION
    separator=+
    modules=$("$binary" list-modules)
    while read -r label module pinned id; do
        actual=$(awk -v module="$module" '$1 == "dep" && $2 == module {print $3}' <<< "$build_info")
        test "$actual" = "$pinned"
        grep -Fxq "$id" <<< "$modules"
        version+="$separator$label${actual#v}"
        separator=.
    done < "$manifest"
    if [[ $variant == stock ]]; then
        ! grep -Fxq dns.providers.cloudflare <<< "$modules" || exit 1
    fi
    printf '%s\n' "$build_info" | sed '1d' > "$root/usr/share/doc/$package/build-info"
    install -m644 packaging/upstream/LICENSE "$root/usr/share/doc/$package/copyright"
    cat > "$root/DEBIAN/control" <<CONTROL
Package: $package
Version: $version
Architecture: $arch
Maintainer: rwv <rwv@users.noreply.github.com>
Depends: caddy-apt-common (>= $COMMON_VERSION), ca-certificates
Provides: caddy-apt-binary
Conflicts: caddy, caddy-apt-binary
Description: Caddy web server ($variant build)
CONTROL
    install -m755 packaging/binary.postinst "$root/DEBIAN/postinst"
    install -m755 packaging/binary.prerm "$root/DEBIAN/prerm"
    dpkg-deb --root-owner-group --build "$root" "out/${package}_${version}_$arch.deb"
done

if [[ $arch == amd64 ]]; then
    root=$build/common
    install -d "$root/DEBIAN" "$root/usr/lib/systemd/system" "$root/etc/caddy" "$root/usr/share/caddy" "$root/usr/share/doc/caddy-apt-common"
    install -m644 packaging/upstream/*.service "$root/usr/lib/systemd/system/"
    install -m644 packaging/upstream/Caddyfile "$root/etc/caddy/Caddyfile"
    install -m644 packaging/upstream/index.html "$root/usr/share/caddy/index.html"
    install -m644 packaging/upstream/LICENSE "$root/usr/share/doc/caddy-apt-common/copyright"
    install -m755 packaging/common.postinst "$root/DEBIAN/postinst"
    printf '/etc/caddy/Caddyfile\n' > "$root/DEBIAN/conffiles"
    cat > "$root/DEBIAN/control" <<CONTROL
Package: caddy-apt-common
Version: $COMMON_VERSION
Architecture: all
Maintainer: rwv <rwv@users.noreply.github.com>
Depends: passwd, init-system-helpers
Conflicts: caddy
Replaces: caddy
Description: Shared configuration and official systemd units for Caddy APT
CONTROL
    SOURCE_DATE_EPOCH=1700000000 dpkg-deb --root-owner-group --build "$root" "out/caddy-apt-common_${COMMON_VERSION}_all.deb"
fi
