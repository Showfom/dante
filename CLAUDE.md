# CLAUDE.md

Docker image for the Dante SOCKS5 server (`sockd`). Debian Trixie has no `dante-server` package, so Dante is built from the upstream tarball.

Published as `showfom/dante` (Docker Hub) and `ghcr.io/showfom/dante` (GHCR), linux/amd64 + linux/arm64, tags `<version>` and `latest`.

## Files

- `Dockerfile`: two stages on `debian:trixie-slim`. The build stage compiles the server only; the runtime stage has `sockd` + `libpam0g`. `DANTE_VERSION` and `DANTE_SHA256` are the `ARG`s at the top, re-declared (without defaults) inside each stage that uses them.
- `docker-entrypoint.sh`: creates or updates a system user from `PROXY_USER` / `PROXY_PASSWORD`, then `exec "$@"`. These are runtime env vars; nothing user-related is baked into the image.
- `sockd.conf`: default config, `socksmethod: username`. Needs `user.privileged: root` to read `/etc/shadow`; `user.unprivileged: sockd`.
- `sockd-whitelist.conf`: alternative config, `socksmethod: none` + `client pass` per allowed IP + `client block` for everyone else.
- `sockd.conf.example`: upstream sample from the Debian package, reference only. Not copied into the image.
- `compose.yaml`: uses the published image (no `build:`), mounts `sockd.conf` read-only, placeholder credentials inline.
- `.github/workflows/docker.yml`: release pipeline, see below.

## Releasing a new Dante version

1. Get the checksum: `curl -fsSL https://www.inet.no/dante/files/dante-<version>.tar.gz | sha256sum`
2. Update `DANTE_VERSION` and `DANTE_SHA256` at the top of `Dockerfile`. The version and checksum stay in the Dockerfile; there is no `.env`.
3. Build and test locally (below), commit, push `main`.
4. Tag and push: `git tag -m "Dante <version>" <version> && git push origin <version>`. Use `-m`: `tag.gpgsign` is enabled, so a lightweight `git tag <version>` fails with "no tag message".
5. Watch the run: `gh run list -R showfom/dante -L 1`, then check both registries:
   `docker buildx imagetools inspect showfom/dante:<version>` and `ghcr.io/showfom/dante:<version>` should each list amd64 and arm64.

Any pushed tag triggers the workflow. The workflow file is read from the tagged commit, so a change to the workflow needs a new tag, or the tag moved to the new commit, before it takes effect.

## CI workflow

- `build` matrix runs natively on `ubuntu-26.04` (amd64) and `ubuntu-26.04-arm` (arm64) and pushes by digest to both registries. `merge` then creates the tagged manifest lists with `docker buildx imagetools create`. Don't go back to QEMU: the emulated arm64 compile took over 16 minutes, native runs take about 2.
- Both jobs use `environment: Docker Hub`. `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` are environment secrets there, not repository secrets. GHCR uses `GITHUB_TOKEN`. The GHCR package is public.
- actionlint flags `ubuntu-26.04` as an unknown runner label because its label list is outdated. GitHub accepts the label.
- `docker/metadata-action` labels override the Dockerfile `LABEL`s in CI builds. `org.opencontainers.image.description` comes from the GitHub repo description.

## Local testing

```bash
docker build -t dante:test .
docker run -d --name dtest -p 11080:1080 -e PROXY_USER=alice -e PROXY_PASSWORD=s3cret dante:test
curl -x socks5h://alice:s3cret@$(hostname -I | awk '{print $1}'):11080 https://ip.sb   # expect success
curl -x socks5h://alice:wrong@...   # expect "User was rejected"
docker rm -f dtest
```

- On the maintainer's WSL2 machine, published ports don't work via `127.0.0.1` (even nginx gets "Connection reset"). Use the host IP from `hostname -I`, or run curl in another container on the same Docker network.
- Use `ip.sb` to check the exit IP, not `ifconfig.me`.
- Whitelist mode needs the real client IP. On a user-defined network, give client containers fixed `--ip`s to test pass and block cases.

## Conventions

- README is in English and uses `latest` or `<version>` rather than hardcoded version numbers.
- Commits go straight to `main`.

## Decided against

- **distroless runtime (`gcr.io/distroless/static-debian13`)**: tested. A fully static `sockd` (`make LDFLAGS=-all-static`, `--without-pam`) runs as nonroot in whitelist mode, but username auth fails with `could not access user ... records in the system password file`. Static glibc can't do `getpwnam`/`getspnam` without the NSS shared libraries. The entrypoint also needs a shell. Staying on `trixie-slim`.
- **Fixed UID for `sockd`**: it owns no files, so the system assigns one.
- **Env-driven `.env` for version or credentials**: dropped at the maintainer's request.
