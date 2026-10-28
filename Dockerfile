# syntax=docker/dockerfile:1
#
# Debian 13 (trixie) desktop reachable from anywhere through
#   - Chrome Remote Desktop (XFCE session on a virtual X display)
#   - VS Code tunnel (the `code` CLI)
#
# Google only ships the Chrome Remote Desktop host for amd64, so the image is
# pinned to linux/amd64. On an Apple Silicon or other arm64 host it runs under
# emulation (slow); run it on an amd64 server for real use.

FROM --platform=linux/amd64 debian:trixie-slim

ARG USERNAME=remote
ARG USER_UID=1000
ARG USER_GID=1000
# Space-separated extra apt packages, e.g. "firefox-esr chromium"
ARG EXTRA_PACKAGES=""
# Desktop layout baked into the image: "mac" or "windows" (see desktop/).
ARG DESKTOP_LAYOUT=mac
# Developer toolchain versions.
ARG NVM_VERSION=v0.40.8
ARG NODE_DEFAULT=22
# .NET SDK release channels installed side by side (latest patch of each).
ARG DOTNET_CHANNELS="8.0 10.0"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_GB.UTF-8 \
    LC_ALL=en_GB.UTF-8

# Base tools, XFCE desktop and the Chrome Remote Desktop host's dependencies.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg sudo locales tzdata procps psmisc less nano \
        git git-lfs openssh-client build-essential pkg-config unzip \
        python3-pip python3-venv python3-dev pipx \
        libicu76 libgssapi-krb5-2 \
        dbus-x11 xfce4 xfce4-terminal thunar mousepad \
        xserver-xorg-video-dummy xvfb xbase-clients x11-xserver-utils \
        fonts-dejavu fonts-inter \
        arc-theme breeze-icon-theme adwaita-icon-theme gtk-update-icon-cache \
        xfce4-whiskermenu-plugin xfce4-appfinder xfce4-notifyd xfce4-docklike-plugin \
        fonts-jetbrains-mono \
        python3 python3-dbus python3-packaging python3-psutil python3-xdg \
        xdg-utils gsettings-desktop-schemas pkexec libgbm1 \
        ${EXTRA_PACKAGES} \
    && sed -i 's/^# *en_GB.UTF-8 UTF-8/en_GB.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && rm -rf /var/lib/apt/lists/*

# Chrome Remote Desktop host (amd64 only).
RUN curl -fsSL -o /tmp/crd.deb \
        https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/crd.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/crd.deb

# VS Code CLI (provides `code tunnel`).
RUN curl -fsSL -o /tmp/vscode_cli.tar.gz \
        "https://update.code.visualstudio.com/latest/cli-linux-x64/stable" \
    && tar -xzf /tmp/vscode_cli.tar.gz -C /usr/local/bin \
    && rm /tmp/vscode_cli.tar.gz \
    && code --version

# Developer toolchain.
#  - nvm lives system-wide in /opt/nvm (made user-writable below) with Node
#    NODE_DEFAULT installed and set as default; /opt/node-default points at that
#    version so non-interactive processes (VS Code tasks, launchers) see node too.
#  - .NET SDKs for each channel in DOTNET_CHANNELS go to /usr/share/dotnet via
#    Microsoft's dotnet-install.sh; `dotnet --list-sdks` shows them all.
#  - Python 3, pip, venv and pipx come from Debian (pip is "externally managed":
#    use `python3 -m venv` or `pipx`, see README).
ENV NVM_DIR=/opt/nvm \
    DOTNET_ROOT=/usr/share/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_NOLOGO=1 \
    PATH=/opt/node-default/bin:/usr/share/dotnet:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN set -eu; \
    git clone --depth 1 --branch "$NVM_VERSION" https://github.com/nvm-sh/nvm.git "$NVM_DIR"; \
    rm -rf "$NVM_DIR/.git"; \
    bash -c ". $NVM_DIR/nvm.sh && nvm install $NODE_DEFAULT && nvm alias default $NODE_DEFAULT && nvm cache clear && corepack enable"; \
    ln -s "$(ls -d $NVM_DIR/versions/node/v* | sort -V | tail -1)" /opt/node-default; \
    /opt/node-default/bin/node --version; \
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh; \
    for ch in $DOTNET_CHANNELS; do bash /tmp/dotnet-install.sh --channel "$ch" --install-dir "$DOTNET_ROOT"; done; \
    rm /tmp/dotnet-install.sh; \
    dotnet --list-sdks; \
    printf '%s\n' 'export NVM_DIR=/opt/nvm' '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"' 'export PATH="$PATH:$HOME/.dotnet/tools:$HOME/.local/bin"' > /etc/profile.d/dev-toolchain.sh; \
    printf '\n# Developer toolchain (nvm, .NET tools, pipx) for interactive shells\n. /etc/profile.d/dev-toolchain.sh\n' >> /etc/bash.bashrc

# Desktop layout: XFCE config files for the chosen layout go into /etc/skel so
# the user account created below starts with them. Both layouts share the light
# Arc theme, Inter and JetBrains Mono fonts and a GTK stylesheet. Icons are
# platform-matched: WhiteSur (macOS-style) for "mac", Fluent (Windows-style) for
# "windows", both pinned to a release tag and falling back to Breeze for any
# icon they lack. "mac" also gets a docklike Dock and the soft light gradient
# wallpaper shipped in desktop/wallpaper/; the Dock pins whichever of the
# listed apps are installed.
COPY desktop/ /opt/desktop-layouts/
RUN set -eu; \
    case "$DESKTOP_LAYOUT" in mac|windows) ;; *) echo "DESKTOP_LAYOUT must be mac or windows" >&2; exit 1;; esac; \
    cp -a /opt/desktop-layouts/common/. /etc/skel/; \
    cp -a "/opt/desktop-layouts/$DESKTOP_LAYOUT/." /etc/skel/; \
    if [ "$DESKTOP_LAYOUT" = mac ]; then layout="close,minimize,maximize:menu"; else layout="menu:minimize,maximize,close"; fi; \
    sed -i "s|@DECORATION_LAYOUT@|$layout|" /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml; \
    echo "$DESKTOP_LAYOUT" > /etc/desktop-layout; \
    mkdir -p /tmp/icons && cd /tmp/icons; \
    if [ "$DESKTOP_LAYOUT" = mac ]; then \
        curl -fsSL https://github.com/vinceliuice/WhiteSur-icon-theme/archive/refs/tags/2026-09-10.tar.gz | tar -xz; \
        bash WhiteSur-icon-theme-*/install.sh -d /usr/share/icons; icon=WhiteSur; \
    else \
        curl -fsSL https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/2026-07-27.tar.gz | tar -xz; \
        bash Fluent-icon-theme-*/install.sh -d /usr/share/icons; icon=Fluent-light; \
        [ -d "/usr/share/icons/$icon" ] || icon=Fluent; \
    fi; \
    cd / && rm -rf /tmp/icons; \
    test -f "/usr/share/icons/$icon/index.theme"; \
    sed -i "s/^Inherits=.*/Inherits=breeze,hicolor/" "/usr/share/icons/$icon/index.theme"; \
    gtk-update-icon-cache -f -q "/usr/share/icons/$icon"; \
    sed -i "s|@ICON_THEME@|$icon|" /etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml; \
    if [ "$DESKTOP_LAYOUT" = mac ]; then \
        mkdir -p /usr/share/backgrounds; \
        cp /opt/desktop-layouts/wallpaper/mac.jpg /usr/share/backgrounds/desktop-wallpaper.jpg; \
        pinned=""; \
        for app in xfce4-appfinder thunar xfce4-terminal mousepad firefox-esr chromium xfce4-settings-manager; do \
            [ -f "/usr/share/applications/$app.desktop" ] && pinned="$pinned$app.desktop;"; \
        done; \
        sed -i "s|@PINNED@|$pinned|" /etc/skel/.config/xfce4/panel/docklike-20.rc; \
    fi

# Non-root user: the Chrome Remote Desktop host refuses to run as root, and
# the VS Code tunnel is happier as a normal user too. Its password and sudo
# policy are applied at start-up by entrypoint.sh from USER_PASSWORD, so no
# secret is baked into the image. Also writes the session script the host
# launches on its virtual display (/etc/chrome-remote-desktop-session).
RUN groupadd -f chrome-remote-desktop \
    && groupadd -g ${USER_GID} ${USERNAME} \
    && useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash \
        -G sudo,chrome-remote-desktop ${USERNAME} \
    && printf 'exec /etc/X11/Xsession /usr/bin/xfce4-session\n' \
        > /etc/chrome-remote-desktop-session \
    && mkdir -p /home/${USERNAME}/workspace \
    && chown -R ${USER_UID}:${USER_GID} /home/${USERNAME} /opt/nvm

COPY --chmod=0755 entrypoint.sh services.sh apply-desktop-layout.sh /usr/local/bin/

# Starts as root (entrypoint.sh applies the password, then drops to USERNAME).
ENV USERNAME=${USERNAME}
WORKDIR /home/${USERNAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
