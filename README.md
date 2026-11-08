# bg-vncPrivacy

Keep a computer's physical monitor dark while you work on its desktop over VNC.

"Privacy on" switches the monitor, over DDC/CI, to an input with nothing
connected, so it shows nothing whatever the desktop does. Switching the
display's power state from software doesn't work for this: VNC input counts as
user activity and GNOME wakes the display. The monitor's own input selector
isn't affected by that.

Written for modelnator (NVIDIA DGX Spark, GNOME 46 on Xorg, Dell U4025QW on
USB-C, x11vnc on the console via `x11vnc-console.service`).

## Behaviour

| When | Monitor off (blanked / powered down) | Monitor on |
|---|---|---|
| VNC client connects | privacy turns **on**: stays dark | privacy stays **off**: stays on |
| You click "Turn local monitor on/off" | toggles | toggles |
| Last VNC client disconnects, privacy **on** | screen locks, display powers off, input switched back: monitor stays off | (same) |
| Last VNC client disconnects, privacy **off** | nothing changes | nothing changes: monitor stays on |

The **VNC Privacy** item (monitor icon plus text) appears in the top bar only
while a VNC session is active. The icon has a slash through it while privacy
is on.

- **Single click:** a menu showing `bg-vncPrivacy:`, *A remote session is
  active*, *Local physical monitor is on|off*, and a *Turn local monitor
  off|on* item.
- **Double-click or middle-click:** toggles directly.

GNOME's AppIndicator extension doesn't show hover tooltips, so the status
lines are in the menu instead. The status line is the only bright (not
greyed-out) line, with ON/OFF in capitals and a matching icon.

Ubuntu's build of the extension has the text-label property switched off, so
"VNC Privacy" is drawn into the icon. The extension shows wide icons at their
natural width only for files in user-writable locations, so the tray copies
its panel icons into its runtime directory.

## How it works

- x11vnc runs `bg-vncPrivacy vncSessionStart` (`-afteraccept`) and
  `bg-vncPrivacy vncSessionEnd` (`-gone`) for every client. They keep a
  reference count in `$XDG_RUNTIME_DIR/bg-vncPrivacy/`. x11vnc waits for these
  hooks, so the input switch on connect happens before any VNC input arrives.
- `bg-vncPrivacy tray` (autostarted in the desktop session) is a
  StatusNotifierItem with a D-Bus menu. It watches the state directory with
  inotify. A 2-second check of the established connections on the VNC port
  cleans up if x11vnc goes away without running its `-gone` hook.
- "Monitor off" means GNOME has the screen blanked (screensaver active) or
  the display powered down (mutter `PowerSaveMode` ≠ 0).

## Install / uninstall

On the target machine, from a copy of this repo:

```sh
sudo ./install.sh     # deps, files, x11vnc hooks, starts the tray
sudo ./uninstall.sh   # undoes all of it (leaves ddcutil etc. installed)
```

`install.sh` puts:

| File | Purpose |
|---|---|
| `/usr/local/bin/bg-vncPrivacy` | the program |
| `/etc/bg-vncPrivacy.conf` | monitor serial and input codes (kept if already present) |
| `/usr/local/share/bg-vncPrivacy/icons/` | tray icons |
| `/etc/xdg/autostart/bg-vncPrivacy.desktop` | starts the tray at login |
| `/usr/local/share/man/man1/bg-vncPrivacy.1` | `man bg-vncPrivacy` |

It also adds the two hooks to `/usr/local/bin/x11vnc-console`, marked
`# bg-vncPrivacy`, with a backup at `x11vnc-console.pre-bg-vncPrivacy`, and
restarts `x11vnc-console.service`. That restart drops any open VNC sessions.

DDC access needs no root: the `ddcutil` package grants the logged-in desktop
user access to `/dev/i2c-*`.

## Configuration

`/etc/bg-vncPrivacy.conf`. Find the values with:

```sh
ddcutil detect                     # serial number
ddcutil --sn SERIAL capabilities   # Feature 60 lists the input codes
ddcutil --sn SERIAL getvcp 60      # the input in use now
```

On the Dell U4025QW, USB-C/Thunderbolt is the Dell-specific code `0x19`, which
`ddcutil` reports as "Invalid value". HDMI-1 is `0x11`.

## Commands

```sh
bg-vncPrivacy status   # sessions, privacy, what the desktop reports
bg-vncPrivacy off      # rescue: switch the monitor back to the desk input
bg-vncPrivacy on|toggle
```

Over ssh, `bg-vncPrivacy off` works as long as the user is logged in to the
desktop, because that's when they have DDC access. Failing that, press the
monitor's input button.

## Limitations

- **Login screen:** at the login screen there is no tray, and no GNOME session
  for the hooks to ask, so privacy never turns on automatically there.
- **Monitor-specific:** the input codes and the DDC behaviour are specific to
  the monitor. Test switching with `ddcutil setvcp 60 …` while you're at the
  machine before relying on it.
