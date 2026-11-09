# Caddy APT

Signed Debian packages for Linux `amd64` and `arm64`. Choose one build per host.

| Package | Build |
| --- | --- |
| `caddy-stock` | Caddy with standard modules |
| `caddy-cloudflare` | Caddy with the Cloudflare DNS provider |

Both builds use the upstream Caddy systemd units and the shared `caddy-apt-common` package. They conflict with each other and with the upstream `caddy` package.

## Install

Get the public signing key and check its fingerprint.

```sh
curl -fsSLo caddy-apt.gpg https://caddy-apt.rwv.dev/caddy-apt.gpg
gpg --show-keys --with-fingerprint caddy-apt.gpg
sudo install -Dm644 caddy-apt.gpg /etc/apt/keyrings/caddy-apt.gpg
```

The expected fingerprint is `68DA 9A69 7457 A893 5B57 ED7F 376D A478 4ED3 9C81`.

```sh
sudo tee /etc/apt/sources.list.d/caddy-apt.sources >/dev/null <<'SOURCES'
Types: deb
URIs: https://caddy-apt.rwv.dev
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/caddy-apt.gpg
SOURCES
sudo apt update
sudo apt install caddy-cloudflare
```

Use `sudo apt install caddy-stock` to select the standard build. Before migrating from an existing `caddy` package, back up `/etc/caddy` and `/var/lib/caddy`, review APT's removal plan with `apt -s install caddy-cloudflare`, and keep the existing Caddyfile if dpkg prompts. Before switching builds, make sure the Caddyfile uses only modules supported by the target.

For Cloudflare DNS, put the token in a root-owned environment file and use an `EnvironmentFile=` systemd drop-in. Reference it in the Caddyfile as `dns cloudflare {env.CLOUDFLARE_API_TOKEN}`.

## Releases

GitHub Actions checks stable upstream releases daily from the baseline in `packaging/versions.env`. It skips published tags and builds each missing version on native runners. The workflow attests the final Debian packages and verifies them before publishing. It uses the repository's built-in token.

Package versions start with the Caddy version and Debian revision, followed by any compiled plugin versions. Add or update a plugin manifest under `packaging/plugins/` and bump the revision for a rebuild of the same Caddy version. Keep the upstream systemd files pinned to the commit in `packaging/upstream/REVISION`.

```sh
apt-cache madison caddy-cloudflare
apt download caddy-cloudflare
gh attestation verify ./caddy-cloudflare_*.deb --repo rwv/caddy-apt
```

R2 serves versioned packages and hash-addressed APT indexes with immutable cache headers. The publisher uploads these before the signed `InRelease`. Earlier published versions stay indexed. The workflow can rerun the APT publish step from existing GitHub Releases.
