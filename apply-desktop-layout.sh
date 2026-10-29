#!/usr/bin/env bash
# Re-applies the image's desktop layout (from /etc/skel) to an existing home
# directory, e.g. after rebuilding with a different DESKTOP_LAYOUT while keeping
# the home volume. Run as the desktop user, then restart the container so the
# XFCE session picks the files up:
#   docker compose exec -u <USERNAME> desktop apply-desktop-layout.sh && docker compose restart
set -euo pipefail
if [ ! -f /etc/desktop-layout ]; then
    echo "This image was built headless (CRD_ENABLED=false): there is no desktop layout to apply." >&2
    exit 1
fi
cd "$HOME"
X=.config/xfce4/xfconf/xfce-perchannel-xml
rm -rf "$X/xfce4-panel.xml" "$X/xfwm4.xml" "$X/xsettings.xml" "$X/xfce4-keyboard-shortcuts.xml" \
       "$X/xfce4-desktop.xml" "$X/thunar.xml" "$X/xfce4-terminal.xml" \
       .config/xfce4/panel .config/xfce4/terminal/terminalrc .config/gtk-3.0/gtk.css \
       .config/autostart/desktop-setup.desktop .config/autostart/plank.desktop .config/plank \
       bin/desktop-setup.sh bin/plank-start.sh
cp -a /etc/skel/.config/. .config/
cp -a /etc/skel/bin/. bin/
echo "Desktop layout '$(cat /etc/desktop-layout)' applied to $HOME. Restart the container to use it."
