# Caddy APT

Signed Debian packages for Linux `amd64` and `arm64`. Choose one build per host.

| Package | Build |
| --- | --- |
| `caddy-stock` | Caddy with standard modules |
| `caddy-cloudflare` | Caddy with the Cloudflare DNS provider |
| `caddy-cloudflare-s3` | Cloudflare DNS and [S3 certificate storage](https://github.com/rkl110/certmagic-s3) |
| `caddy-nuln-alidns` | Caddy with Alibaba Cloud DNS and ESA providers from [nuln/caddy-plugins](https://pkg.go.dev/github.com/nuln/caddy-plugins/alidns) |

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

Use `sudo apt install caddy-stock` to select the standard build. Before migrating from an existing `caddy` package, back up `/etc/caddy` and `/var/lib/caddy`, review APT's removal plan with `apt -s install caddy-cloudflare`, and keep the existing Caddyfile if dpkg prompts. The upstream package's purge script deletes the Caddy user and shared data and config directories. After an APT replacement, leave the old package in the removed state. Before switching builds, make sure the Caddyfile uses only modules supported by the target.

For Cloudflare DNS, put the token in a root-owned environment file and use an `EnvironmentFile=` systemd drop-in. Reference it in the Caddyfile as `dns cloudflare {env.CLOUDFLARE_API_TOKEN}`.

With `caddy-cloudflare-s3`, set `storage s3` in the global Caddyfile block. Use a private bucket for Caddy data, including certificate private keys. See the [S3 configuration reference](https://github.com/rkl110/certmagic-s3#configuration) for endpoints and credentials. Use one Caddy instance per storage prefix because the plugin's lock acquisition is not atomic.

## Releases

GitHub Actions checks stable upstream releases daily from the baseline in `packaging/versions.env`. It skips published package versions and builds each missing package on native runners. Releases use package-scoped tags such as `caddy-cloudflare/v2.11.9-2` or `caddy-apt-common/v2`. The first combined release remains in the APT index. The workflow attests the final Debian packages and verifies them before publishing. It uses the repository's built-in token.

Package versions start with the Caddy version and Debian revision, followed by any compiled plugin versions. Each manifest under `packaging/plugins/` starts with `1` for new upstream versions. To rebuild one package for an existing Caddy release, set the first line to the new revision and its upstream tag, for example `2 v2.11.9`. The remaining lines pin the plugins included in that build. Bump `COMMON_VERSION` when the shared package changes. Keep the upstream systemd files pinned to the commit in `packaging/upstream/REVISION`.

```sh
apt-cache madison caddy-cloudflare
apt download caddy-cloudflare
gh attestation verify ./caddy-cloudflare_*.deb --repo rwv/caddy-apt
```

R2 serves versioned packages and hash-addressed APT indexes with immutable cache headers. The publisher uploads these before the signed `InRelease`. Earlier published versions stay indexed. The separate **Publish APT index** workflow runs after the main-branch release workflow completes and reads published GitHub Releases. Bot-triggered releases dispatch it explicitly because GitHub suppresses the follow-on event. To resync the index independently, run `gh workflow run publish-apt.yml --ref main`.

R2 Bucket Lock protects `pool/` and both architectures' `by-hash/` paths indefinitely. Mutable APT indexes and the signing key remain writable.

## Unattended updates

The APT workflow also reconciles daily at 05:47 UTC. Two consecutive failed runs open one issue assigned to the repository owner. A successful run closes it. The workflow also opens an issue 30 days before the signing key expires.

The plugin workflow checks the Go module pins in each plugin package daily. It proposes one PR per affected package, builds the exact candidate on native amd64 and arm64 runners, and checks module registration and Caddyfile parsing. It squash-merges the tested commit and dispatches a release scoped to that package. A failed build leaves the PR open for the next run. The `verify_current` manual input exercises both build runners with the existing pins.
