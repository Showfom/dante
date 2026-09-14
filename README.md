# Dante SOCKS5 Proxy (Docker)

A Docker image for the [Dante](https://www.inet.no/dante/) SOCKS5 server, built from source on `debian:trixie-slim`.

## Background

Debian Trixie doesn't ship a `dante-server` package, so there is no `apt install` route on current Debian. This repo builds Dante from the upstream source tarball and packages it as a Docker image instead.

- Multi-stage build: compilers stay in the build stage, the runtime image only has `sockd` and `libpam0g`
- The Dante version is a build argument, and the source tarball is checked against a SHA-256 checksum
- Username/password auth by default; the login is created from environment variables when the container starts
- An IP whitelist config is included for setups without a password

## Images

Built for linux/amd64 and linux/arm64 and published to both registries:

| Registry   | Image                                                                             |
| ---------- | --------------------------------------------------------------------------------- |
| Docker Hub | [`showfom/dante:latest`](https://hub.docker.com/r/showfom/dante)                 |
| GHCR       | [`ghcr.io/showfom/dante:latest`](https://github.com/Showfom/dante/pkgs/container/dante) |

## Quick start

```bash
git clone git@github.com:showfom/dante.git
cd dante
# edit PROXY_USER and PROXY_PASSWORD in compose.yaml first
docker compose up -d
```

To pull from GHCR instead of Docker Hub, change the image in `compose.yaml`:

```yaml
image: ghcr.io/showfom/dante:latest
```

Test it:

```bash
curl -x socks5h://proxy_user:change-me@YOUR_SERVER_IP:1080 https://ip.sb
```

## Files

| File                   | Purpose                                                        |
| ---------------------- | -------------------------------------------------------------- |
| `Dockerfile`           | Multi-stage build that compiles and packages `sockd`           |
| `docker-entrypoint.sh` | Creates or updates the proxy user from env vars at startup     |
| `.github/workflows/docker.yml` | Builds and pushes multi-arch images when a tag is pushed |
| `compose.yaml`         | Docker Compose setup using `showfom/dante:latest`              |
| `sockd.conf`           | Default config (username/password), mounted read-only          |
| `sockd-whitelist.conf` | Alternative config: IP whitelist, no authentication            |
| `sockd.conf.example`   | Upstream sample config (from the Debian package), fully commented |

## Configuration

### Environment variables

Set these under `environment` in `compose.yaml`:

| Variable         | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `PROXY_USER`     | Proxy login name. Created inside the container at startup.   |
| `PROXY_PASSWORD` | Password for `PROXY_USER`. Reset on every container start.   |

These are runtime settings, not part of the image: the published image contains no proxy user. If either one is empty, no user is created. With the default `socksmethod: username`, nobody can then use the proxy.

For more than one user, add them in the running container:

```bash
docker exec -it dante sh -c 'useradd -M -s /usr/sbin/nologin bob && passwd bob'
```

Users added this way are lost when the container is recreated. To keep them, extend `docker-entrypoint.sh`.

### Build arguments

Defined at the top of the `Dockerfile`:

| Argument         | Default                  | Description                          |
| ---------------- | ------------------------ | ------------------------------------ |
| `DANTE_VERSION`  | current Dante release    | Dante release to build               |
| `DANTE_SHA256`   | checksum of that release | SHA-256 of `dante-<version>.tar.gz`  |
| `DEBIAN_VERSION` | `trixie-slim`            | Debian base image tag                |

To upgrade Dante, get the new tarball's checksum:

```bash
curl -fsSL https://www.inet.no/dante/files/dante-<version>.tar.gz | sha256sum
```

Update `DANTE_VERSION` and `DANTE_SHA256` in the `Dockerfile` and build it yourself. The build fails if the checksum doesn't match:

```bash
docker build -t showfom/dante:latest .
```

Without Compose:

```bash
docker run -d --name dante --init -p 1080:1080 \
  -e PROXY_USER=proxy_user -e PROXY_PASSWORD=change-me \
  showfom/dante:latest
```

### Releasing images

`.github/workflows/docker.yml` runs on every pushed tag. It builds linux/amd64 and linux/arm64 and pushes both Docker Hub and GHCR. A tag like `<version>` or `v<version>` produces the image tags `<version>` and `latest`; pre-release tags such as `<version>-rc1` don't move `latest`.

One-time setup: in the GitHub repo under Settings → Environments, create an environment named `Docker Hub` and add these secrets to it (the job runs in that environment):

| Secret               | Value                                                  |
| -------------------- | ------------------------------------------------------ |
| `DOCKERHUB_USERNAME` | Docker Hub username                                    |
| `DOCKERHUB_TOKEN`    | Docker Hub access token with Read & Write permission   |

GHCR uses the built-in `GITHUB_TOKEN`, so it needs no secret. After the first push, the GHCR package is private by default; make it public under the package's settings if you want anonymous pulls.

To release, bump the version in the `Dockerfile` if needed, then:

```bash
git tag -m "Dante <version>" <version>
git push origin <version>
```

### sockd.conf

Compose mounts `sockd.conf` read-only at `/etc/sockd.conf`, so config changes only need a restart, not a rebuild:

```bash
docker compose restart
```

The default config:

- listens on `0.0.0.0:1080` and sends traffic out through `eth0`
- requires username/password (`socksmethod: username`)
- blocks connections to the container's own loopback (`127.0.0.0/8`)
- allows TCP `connect` and UDP `udpassociate`

To limit which client IPs can connect, narrow the `client pass` rule:

```
client pass {
    from: 192.0.2.0/24 to: 0.0.0.0/0
    log: error
}
```

### IP whitelist instead of username/password

`sockd-whitelist.conf` turns off authentication (`socksmethod: none`) and only accepts clients from listed IPs. Everyone else is dropped.

1. Edit the `client pass` blocks in `sockd-whitelist.conf`, one block per IP or CIDR range:

   ```
   client pass {
       from: 192.0.2.2/32 to: 0.0.0.0/0
       log: error
   }
   ```

2. Mount it instead of `sockd.conf` in `compose.yaml`. `PROXY_USER` / `PROXY_PASSWORD` can be removed:

   ```yaml
   volumes:
     - ./sockd-whitelist.conf:/etc/sockd.conf:ro
   ```

3. Restart: `docker compose up -d`

Before relying on the whitelist, make sure the container sees real client IPs. Connect once from a non-listed IP and check `docker compose logs`: the blocked line must show the client's public IP. If it shows a Docker gateway address such as `172.17.0.1` instead, which happens with Docker's userland proxy and some IPv6 setups, use `network_mode: host` and remove the `ports:` section. Never whitelist Docker's internal ranges (`172.16.0.0/12`); that would effectively allow everyone.

See `sockd.conf.example` and the official docs for more: <https://www.inet.no/dante/doc/1.4.x/config/server.html>

## Security notes

- Don't expose port 1080 to the internet with `socksmethod: none`. Open proxies get found and abused quickly.
- SOCKS5 username/password auth is sent in plain text. Use a strong password you don't use anywhere else, and restrict source IPs with a firewall or the `client pass` rule where you can.
- `user.privileged: root` is required because Dante reads `/etc/shadow` to check passwords. Proxied traffic is handled as the unprivileged `sockd` user.

## Logs

```bash
docker compose logs -f
```
