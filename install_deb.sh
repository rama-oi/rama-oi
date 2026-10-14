#!/usr/bin/env bash
set -Eeuo pipefail

# Rama-OI bootstrap
# Debian 12 / X11

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/install_deb.lua"

if [[ "${EUID}" -eq 0 ]]; then
    printf 'Error: Run this installer as your normal user.\n' >&2
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    printf 'Error: Cannot identify the operating system.\n' >&2
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "debian" || "${VERSION_ID:-}" != "12" ]]; then
    printf 'Error: Rama-OI currently targets Debian 12.\n' >&2
    exit 1
fi

if [[ ! -f "${INSTALLER}" ]]; then
    printf 'Error: install_deb.lua was not found beside install_deb.sh.\n' >&2
    exit 1
fi

if ! command -v lua5.4 >/dev/null 2>&1; then
    printf 'Installing Lua 5.4...\n'

    sudo apt-get update
    sudo apt-get install -y --no-install-recommends lua5.4
fi

exec lua5.4 "${INSTALLER}" install "$@"