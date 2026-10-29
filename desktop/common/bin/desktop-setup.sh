#!/usr/bin/env bash
# Runs once per XFCE session (autostart). Applies settings that cannot be
# shipped as static files: the wallpaper, whose xfconf key embeds the monitor
# name that only exists once the virtual display is up. xfdesktop does not
# create that key by itself, so the monitor names come from xrandr and the
# properties are created here.
set -u
LAYOUT="$(cat /etc/desktop-layout 2>/dev/null || echo mac)"
WALLPAPER=/usr/share/backgrounds/desktop-wallpaper.jpg

# Wait for xfdesktop to be up and initialised (it writes the migration marker
# at the end of its start-up). Settings written before that point are lost to
# its defaults; written afterwards they are applied at once.
xfdesktop_ready() {
    pgrep -x xfdesktop >/dev/null && xfconf-query -c xfce4-desktop -p /last-settings-migration-version >/dev/null 2>&1
}
for _ in $(seq 1 60); do
    xfdesktop_ready && break
    sleep 1
done
sleep 1

# Connected monitors; the xfconf key embeds the name (DUMMY0 on the CRD host).
monitors=""
for _ in $(seq 1 30); do
    monitors="$(xrandr --query 2>/dev/null | awk '/ connected/ {print $1}')"
    [ -n "$monitors" ] && break
    sleep 1
done
[ -n "$monitors" ] || exit 0

for m in $monitors; do
    base="/backdrop/screen0/monitor$m/workspace0"
    if [ "$LAYOUT" = "mac" ] && [ -f "$WALLPAPER" ]; then
        xfconf-query -c xfce4-desktop -p "$base/last-image" -n -t string -s "$WALLPAPER"
        xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 5   # zoomed
    else
        # Windows layout: plain light-blue backdrop, no image.
        xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 0
        xfconf-query -c xfce4-desktop -p "$base/color-style" -n -t int -s 0
        xfconf-query -c xfce4-desktop -p "$base/rgba1" -n -t double -s 0.80 -t double -s 0.89 -t double -s 0.97 -t double -s 1.0 -a
    fi
done
xfdesktop --reload >/dev/null 2>&1 || true
