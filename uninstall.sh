#!/bin/sh
# Undo install.sh. Run: sudo ./uninstall.sh
# Packages installed as dependencies (ddcutil, ...) are left in place.
set -eu
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }

WRAPPER=/usr/local/bin/x11vnc-console
MARK="# bg-vncPrivacy"

U=${SUDO_USER:-}
if [ -n "$U" ] && [ "$U" != root ]; then
    echo "== user $U"
    N=$(id -u "$U")
    as_user() {
        runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$N" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$N/bus" "$@"
    }
    if [ "$(cat "/run/user/$N/bg-vncPrivacy/privacy" 2>/dev/null)" = on ] \
        && [ -x /usr/local/bin/bg-vncPrivacy ]; then
        echo "switching the monitor back to its desk input"
        as_user /usr/local/bin/bg-vncPrivacy off || true
    fi
    as_user systemctl --user stop bg-vncPrivacy-tray.service 2>/dev/null || true
    rm -rf "/run/user/$N/bg-vncPrivacy"
fi
pkill -f "/usr/local/bin/bg-vncPrivacy tray" 2>/dev/null || true

echo "== x11vnc hooks"
if [ -f "$WRAPPER" ] && grep -q "$MARK" "$WRAPPER"; then
    sed -i \
        -e '/^[[:space:]]*set -- -afteraccept .*# bg-vncPrivacy$/d' \
        -e 's/ "\$@"  # bg-vncPrivacy$//' \
        "$WRAPPER"
    if grep -q "$MARK" "$WRAPPER" || ! sh -n "$WRAPPER"; then
        echo "ERROR: could not remove hooks cleanly; restore $WRAPPER.pre-bg-vncPrivacy by hand" >&2
        exit 1
    fi
    rm -f "$WRAPPER.pre-bg-vncPrivacy"
    echo "hooks removed; restarting x11vnc-console (open VNC sessions will disconnect)"
    systemctl restart x11vnc-console.service
else
    echo "no hooks present"
fi

echo "== files"
rm -f /usr/local/bin/bg-vncPrivacy /etc/xdg/autostart/bg-vncPrivacy.desktop /etc/bg-vncPrivacy.conf
rm -f /usr/local/share/man/man1/bg-vncPrivacy.1
mandb -q 2>/dev/null || true
rm -rf /usr/local/share/bg-vncPrivacy
echo "uninstalled (ddcutil and other packages left installed)"
