#!/bin/sh
set -eu

# Optionally create/update a proxy login user from environment variables.
# The user has no shell and no home directory; it only exists for SOCKS auth.
if [ -n "${PROXY_USER:-}" ] && [ -n "${PROXY_PASSWORD:-}" ]; then
    if ! id "$PROXY_USER" >/dev/null 2>&1; then
        useradd -M -s /usr/sbin/nologin "$PROXY_USER"
    fi
    echo "${PROXY_USER}:${PROXY_PASSWORD}" | chpasswd
fi

exec "$@"
