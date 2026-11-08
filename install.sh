#!/bin/sh
# Install bg-vncPrivacy system-wide. Run from the repo: sudo ./install.sh
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

SRC=$(cd "$(dirname "$0")" && pwd)
WRAPPER=/usr/local/bin/x11vnc-console   # x11vnc launcher (see README)
MARK="# bg-vncPrivacy"

echo "== packages"
missing=""
for p in ddcutil python3-gi gir1.2-glib-2.0 gir1.2-gdkpixbuf-2.0 librsvg2-common iproute2; do
    dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
done
if [ -n "$missing" ]; then apt-get install -y $missing; else echo "all present"; fi

echo "== files"
install -m 755 "$SRC/bg-vncPrivacy" /usr/local/bin/bg-vncPrivacy
install -d /usr/local/share/bg-vncPrivacy/icons
install -m 644 "$SRC"/icons/*.svg /usr/local/share/bg-vncPrivacy/icons/
install -m 644 "$SRC/bg-vncPrivacy.desktop" /etc/xdg/autostart/bg-vncPrivacy.desktop
install -D -m 644 "$SRC/bg-vncPrivacy.1" /usr/local/share/man/man1/bg-vncPrivacy.1
mandb -q 2>/dev/null || true
if [ -e /etc/bg-vncPrivacy.conf ]; then
    echo "keeping existing /etc/bg-vncPrivacy.conf"
else
    install -m 644 "$SRC/bg-vncPrivacy.conf" /etc/bg-vncPrivacy.conf
fi

echo "== x11vnc hooks"
if [ ! -f "$WRAPPER" ]; then
    echo "WARNING: $WRAPPER not found. Add these options to your x11vnc command:"
    echo "  -afteraccept '/usr/local/bin/bg-vncPrivacy vncSessionStart'"
    echo "  -gone '/usr/local/bin/bg-vncPrivacy vncSessionEnd'"
elif grep -q "$MARK" "$WRAPPER"; then
    echo "already hooked"
else
    cp -p "$WRAPPER" "$WRAPPER.pre-bg-vncPrivacy"
    sed -i \
        -e '/^[[:space:]]*exec setpriv/i\
    set -- -afteraccept "/usr/local/bin/bg-vncPrivacy vncSessionStart" -gone "/usr/local/bin/bg-vncPrivacy vncSessionEnd"  # bg-vncPrivacy' \
        -e 's/-noxdamage -repeat$/-noxdamage -repeat "$@"  # bg-vncPrivacy/' \
        "$WRAPPER"
    if [ "$(grep -c "$MARK" "$WRAPPER")" != 2 ] || ! sh -n "$WRAPPER"; then
        cp -p "$WRAPPER.pre-bg-vncPrivacy" "$WRAPPER"
        echo "ERROR: could not add hooks to $WRAPPER (layout not recognised); left it unchanged" >&2
        exit 1
    fi
    echo "hooks added (backup: $WRAPPER.pre-bg-vncPrivacy)"
    echo "restarting x11vnc-console (open VNC sessions will disconnect)"
    systemctl restart x11vnc-console.service
fi

# Per-user steps for the user running sudo: remove the earlier prototype and
# start the tray now if they are logged in to a desktop.
U=${SUDO_USER:-}
if [ -n "$U" ] && [ "$U" != root ]; then
    echo "== user $U"
    H=$(getent passwd "$U" | cut -d: -f6)
    N=$(id -u "$U")
    as_user() {
        runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$N" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$N/bus" "$@"
    }
    as_user systemctl --user stop vnc-privacy-tray.service 2>/dev/null || true
    rm -f "$H/.local/bin/vnc-privacy-tray" "$H/.config/autostart/vnc-privacy-tray.desktop"
    rm -rf "$H/.local/state/vnc-privacy"
    if pgrep -u "$U" -x gnome-shell >/dev/null; then
        as_user systemctl --user stop bg-vncPrivacy-tray.service 2>/dev/null || true
        as_user systemd-run --user --quiet --collect --unit=bg-vncPrivacy-tray \
            /usr/local/bin/bg-vncPrivacy tray && echo "tray started"
    else
        echo "tray will start at next desktop login"
    fi
fi
echo "installed"
