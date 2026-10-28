#!/usr/bin/env bash
# Runs once per XFCE session (autostart). Applies settings that cannot be
# shipped as static files: the wallpaper, whose xfconf key embeds the monitor
# name that only exists once the virtual display is up.
set -u
LAYOUT="$(cat /etc/desktop-layout 2>/dev/null || echo mac)"
WALLPAPER=/usr/share/backgrounds/desktop-wallpaper.jpg

# Wait for xfdesktop to create its per-monitor properties.
for _ in $(seq 1 30); do
    props="$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '^/backdrop/screen0/monitor.*/workspace0/last-image$')"
    [ -n "$props" ] && break
    sleep 1
done

for p in $props; do
    base="${p%/last-image}"
    if [ "$LAYOUT" = "mac" ] && [ -f "$WALLPAPER" ]; then
        xfconf-query -c xfce4-desktop -p "$p" -n -t string -s "$WALLPAPER"
        xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 5   # zoomed
    else
        # Windows layout: plain light-blue backdrop, no image.
        xfconf-query -c xfce4-desktop -p "$base/image-style" -n -t int -s 0
        xfconf-query -c xfce4-desktop -p "$base/color-style" -n -t int -s 0
        xfconf-query -c xfce4-desktop -p "$base/rgba1" -n \
            -t double -s 0.80 -t double -s 0.89 -t double -s 0.97 -t double -s 1.0 -a
    fi
done
xfdesktop --reload >/dev/null 2>&1 || true
