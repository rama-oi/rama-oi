#!/bin/sh
set -eu

REPO="rama-oi/rama-x11"
BRANCH="main"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BASE="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

echo "==> Downloading Rama-OI"

if command -v curl >/dev/null 2>&1; then
    curl -fLsS "$BASE" -o "$TMP/repo.tar.gz"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$TMP/repo.tar.gz" "$BASE"
else
    echo "Error: curl or wget is required." >&2
    exit 1
fi

mkdir "$TMP/repo"
tar -xzf "$TMP/repo.tar.gz" \
    -C "$TMP/repo" \
    --strip-components=1

cd "$TMP/repo"

if ! command -v lua5.4 >/dev/null 2>&1; then
    echo "==> Installing Lua 5.4"
    doas apk add lua5.4
fi

exec lua5.4 ./install_alpine.lua install