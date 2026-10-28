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

# A system D-Bus keeps XFCE and polkit quiet. Harmless if it fails.
if [ ! -S /run/dbus/system_bus_socket ]; then
    mkdir -p /run/dbus && rm -f /run/dbus/pid
    dbus-daemon --system --fork >/dev/null 2>&1 || log "system dbus not started (continuing)"
fi

# Drop privileges (no fork, so signals reach services.sh directly).
exec setpriv --reuid="$USER_UID" --regid="$USER_GID" --init-groups \
    env HOME="$USER_HOME" USER="$USERNAME" LOGNAME="$USERNAME" SHELL=/bin/bash \
    /usr/local/bin/services.sh
