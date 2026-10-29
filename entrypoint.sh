#!/usr/bin/env bash
# Root-side start-up: applies the account settings from .env, then drops to the
# unprivileged user and runs services.sh, which supervises the remote-access
# services. Runs as root only for this short setup.
set -euo pipefail

USERNAME="${USERNAME:?USERNAME not baked into the image}"
USER_HOME="/home/$USERNAME"
USER_UID="$(id -u "$USERNAME")"
USER_GID="$(id -g "$USERNAME")"

log() { echo "[entrypoint] $*"; }

# Password for the user: used by sudo inside the container.
if [ -n "${USER_PASSWORD:-}" ]; then
    echo "$USERNAME:$USER_PASSWORD" | chpasswd
    rm -f "/etc/sudoers.d/$USERNAME"            # sudo asks for the password
    log "Password set for '$USERNAME'; sudo requires it"
else
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USERNAME" > "/etc/sudoers.d/$USERNAME"
    chmod 0440 "/etc/sudoers.d/$USERNAME"
    log "WARNING: USER_PASSWORD is empty; '$USERNAME' has passwordless sudo"
fi

# Bind-mounted workspace may arrive owned by root on a Linux host.
if [ -d "$USER_HOME/workspace" ]; then
    chown "$USER_UID:$USER_GID" "$USER_HOME/workspace"
fi

# A system D-Bus keeps XFCE and polkit quiet. Only in a desktop (CRD) build;
# harmless if it fails. /run survives a container restart, so a stale pid file
# and socket from the previous run are cleared first.
if [ "$(cat /etc/crd-enabled 2>/dev/null)" = true ]; then
    mkdir -p /run/dbus && rm -f /run/dbus/pid /run/dbus/system_bus_socket
    dbus-daemon --system --fork >/dev/null 2>&1 || log "system dbus not started (continuing)"
fi

# Per-user runtime directory (normally made by systemd-logind, absent here).
# PipeWire, which the Chrome Remote Desktop host starts for remote audio,
# refuses to create its socket without one, which leaves the session muted.
RUNTIME_DIR="/run/user/$USER_UID"
mkdir -p "$RUNTIME_DIR" && chmod 0700 "$RUNTIME_DIR" && chown "$USER_UID:$USER_GID" "$RUNTIME_DIR"

# Drop privileges (no fork, so signals reach services.sh directly).
exec setpriv --reuid="$USER_UID" --regid="$USER_GID" --init-groups \
    env HOME="$USER_HOME" USER="$USERNAME" LOGNAME="$USERNAME" SHELL=/bin/bash \
        XDG_RUNTIME_DIR="$RUNTIME_DIR" \
    /usr/local/bin/services.sh
