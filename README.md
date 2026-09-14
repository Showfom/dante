# Dante SOCKS5 Proxy (Docker)

Docker Hub: [`showfom/dante`](https://hub.docker.com/r/showfom/dante) (tags `1.4.4`, `latest`, linux/amd64)

A Docker image for the [Dante](https://www.inet.no/dante/) SOCKS5 server, built from source on `debian:trixie-slim`.

- Multi-stage build: compilers stay in the build stage, the runtime image only has `sockd` and `libpam0g`
- The Dante version is a build argument, and the source tarball is checked against a SHA-256 checksum
- Username/password auth by default; the login is created from environment variables when the container starts
- An IP whitelist config is included for setups without a password

## Quick start

```bash
git clone git@github.com:Showfom/dante.git
cd dante
# edit PROXY_USER and PROXY_PASSWORD in compose.yaml first
docker compose up -d
```

Test it:

```bash
curl -x socks5h://proxy_user:change-me@YOUR_SERVER_IP:1080 https://ifconfig.me
```

## Files

| File                   | Purpose                                                        |
| ---------------------- | -------------------------------------------------------------- |
| `Dockerfile`           | Multi-stage build that compiles and packages `sockd`           |
| `docker-entrypoint.sh` | Creates or updates the proxy user from env vars at startup     |
| `compose.yaml`         | Docker Compose setup using `showfom/dante:1.4.4`               |
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

| Argument         | Default          | Description                          |
| ---------------- | ---------------- | ------------------------------------ |
| `DANTE_VERSION`  | `1.4.4`          | Dante release to build               |
| `DANTE_SHA256`   | `1973c773…3faec` | SHA-256 of `dante-<version>.tar.gz`  |
| `DEBIAN_VERSION` | `trixie-slim`    | Debian base image tag                |

To upgrade Dante, get the new tarball's checksum:

```bash
curl -fsSL https://www.inet.no/dante/files/dante-1.4.x.tar.gz | sha256sum
```

Update `DANTE_VERSION` and `DANTE_SHA256` in the `Dockerfile` and build it yourself. The build fails if the checksum doesn't match:

```bash
docker build -t showfom/dante:1.4.4 .
```

Without Compose:

```bash
docker run -d --name dante --init -p 1080:1080 \
  -e PROXY_USER=proxy_user -e PROXY_PASSWORD=change-me \
  showfom/dante:1.4.4
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
    from: 203.0.113.0/24 to: 0.0.0.0/0
    log: error
}
```

### IP whitelist instead of username/password

`sockd-whitelist.conf` turns off authentication (`socksmethod: none`) and only accepts clients from listed IPs. Everyone else is dropped.

1. Edit the `client pass` blocks in `sockd-whitelist.conf`, one block per IP or CIDR range:

   ```
   client pass {
       from: 203.0.113.10/32 to: 0.0.0.0/0
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
