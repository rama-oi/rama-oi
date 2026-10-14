#!/bin/sh
set -eu

# ============================================================
# Rama-OI bootstrap
# Alpine Linux | x86 | Lua 5.4
# ============================================================

REPO="rama-oi/rama-x11"
BRANCH="main"
ARCHIVE="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

log() {
    printf '\n==> %s\n' "$1"
}

die() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

# ------------------------------------------------------------
# Validate Alpine
# ------------------------------------------------------------

[ -f /etc/alpine-release ] ||
    die "This installer requires Alpine Linux."

ARCH="$(apk --print-arch)"

[ "$ARCH" = "x86" ] ||
    die "Expected Alpine x86 (32-bit); detected: $ARCH"

# ------------------------------------------------------------
# Determine execution mode
# ------------------------------------------------------------

if [ "$(id -u)" -eq 0 ]; then
    MODE="root"

    printf 'Enter the existing normal username: '
    read -r TARGET_USER

    [ -n "$TARGET_USER" ] ||
        die "Username cannot be empty."

    id "$TARGET_USER" >/dev/null 2>&1 ||
        die "User does not exist: $TARGET_USER"

    [ "$TARGET_USER" != "root" ] ||
        die "The target must be a normal user."
else
    MODE="user"
    TARGET_USER="$(id -un)"
fi

# ------------------------------------------------------------
# Bootstrap prerequisites
# ------------------------------------------------------------

log "Updating Alpine package indexes"
apk update

log "Installing bootstrap prerequisites"
apk add --no-cache \
    ca-certificates \
    curl \
    tar \
    lua5.4 \
    doas

update-ca-certificates

# ------------------------------------------------------------
# Configure privilege escalation for a fresh installation
# ------------------------------------------------------------

if [ "$MODE" = "root" ]; then
    log "Preparing doas for $TARGET_USER"

    addgroup "$TARGET_USER" wheel 2>/dev/null || true

    mkdir -p /etc/doas.d

    if [ ! -f /etc/doas.d/doas.conf ] ||
       ! grep -Fq 'permit persist :wheel' /etc/doas.d/doas.conf; then
        printf '\npermit persist :wheel\n' >> /etc/doas.d/doas.conf
    fi

    chmod 600 /etc/doas.d/doas.conf

    # Confirm the generated configuration is valid.
    doas -C /etc/doas.d/doas.conf ||
        die "Invalid doas configuration."
fi

# ------------------------------------------------------------
# Download repository
# ------------------------------------------------------------

TMP="$(mktemp -d)"
chmod 755 "$TMP"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

log "Downloading Rama-OI"

curl -fLsS "$ARCHIVE" -o "$TMP/rama-oi.tar.gz"

mkdir "$TMP/repo"
tar -xzf "$TMP/rama-oi.tar.gz" \
    -C "$TMP/repo" \
    --strip-components=1

[ -f "$TMP/repo/install_alpine.lua" ] ||
    die "install_alpine.lua was not found in the repository."

chmod -R a+rX "$TMP/repo"

# ------------------------------------------------------------
# Launch Lua as the normal user
# ------------------------------------------------------------

log "Starting Rama-OI as $TARGET_USER"

if [ "$MODE" = "root" ]; then
    # su starts a login session and picks up the user's new groups.
    su - "$TARGET_USER" -c \
        "lua5.4 '$TMP/repo/install_alpine.lua' install"
else
    if command -v doas >/dev/null 2>&1; then
        doas apk add --no-cache \
            ca-certificates curl tar lua5.4
    elif command -v sudo >/dev/null 2>&1; then
        sudo apk add --no-cache \
            ca-certificates curl tar lua5.4
    else
        die "Configure doas or sudo before running as a normal user."
    fi

    lua5.4 "$TMP/repo/install_alpine.lua" install
fi

log "Rama-OI completed"