# syntax=docker/dockerfile:1

ARG DEBIAN_VERSION=trixie-slim
ARG DANTE_VERSION=1.4.4
ARG DANTE_SHA256=1973c7732f1f9f0a4c0ccf2c1ce462c7c25060b25643ea90f9b98f53a813faec

# ---------- build stage ----------
FROM debian:${DEBIAN_VERSION} AS build

ARG DANTE_VERSION
ARG DANTE_SHA256

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        libpam0g-dev; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN set -eux; \
    curl -fsSL -o dante.tar.gz "https://www.inet.no/dante/files/dante-${DANTE_VERSION}.tar.gz"; \
    echo "${DANTE_SHA256}  dante.tar.gz" | sha256sum -c -; \
    tar xzf dante.tar.gz --strip-components=1; \
    ./configure \
        --prefix=/usr/local \
        --sysconfdir=/etc \
        --disable-client \
        --without-libwrap \
        --without-upnp \
        --without-gssapi \
        --without-ldap \
        --without-sasl; \
    make -j"$(nproc)"; \
    make install DESTDIR=/out; \
    strip /out/usr/local/sbin/sockd

# ---------- runtime stage ----------
FROM debian:${DEBIAN_VERSION}

ARG DANTE_VERSION
LABEL org.opencontainers.image.title="dante" \
      org.opencontainers.image.description="Dante SOCKS5 proxy server" \
      org.opencontainers.image.version="${DANTE_VERSION}" \
      org.opencontainers.image.source="https://github.com/Showfom/dante"

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends libpam0g; \
    rm -rf /var/lib/apt/lists/*; \
    useradd -r -M -s /usr/sbin/nologin -u 8964 sockd

COPY --from=build /out/usr/local/sbin/sockd /usr/local/sbin/sockd
COPY sockd.conf /etc/sockd.conf
COPY --chmod=755 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

EXPOSE 1080
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["sockd", "-f", "/etc/sockd.conf"]
