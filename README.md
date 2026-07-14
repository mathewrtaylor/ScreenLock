# ScreenLock

A small Ubuntu/GNOME utility that watches for the screen locking and automatically
suspends the machine 5 minutes later — but only if it's still locked when the timer
runs out. Useful for laptops/desktops that are set to never dim/sleep on their own but
should still suspend after being left locked and unattended for a while.

## How it works

- `bin/lock-suspend-timer.sh` runs as a systemd user service. It uses `dbus-monitor` to
  watch the session bus for the GNOME screensaver's `ActiveChanged` signal
  (`org.gnome.ScreenSaver`).
- When a lock event (`boolean true`) is seen, it sleeps for 300 seconds.
- When the sleep ends, it re-checks the *current* lock state via
  `loginctl show-session --property=LockedHint` rather than trusting the original event.
  If the session is still locked, it runs `systemctl suspend`. If you unlocked before the
  timer ran out, it does nothing and goes back to watching for the next lock.
- `systemd/lock-suspend.service` is the user-level systemd unit that keeps the script
  running (auto-restarts on crash) and ties its lifecycle to your graphical session.
- `desktop/restart-screenlock.desktop` is an app-launcher icon that restarts the service
  on demand (handy after editing the script, or if it ever gets stuck).

## Requirements

- Ubuntu with a GNOME (or GNOME-compatible) desktop session — the script depends on the
  `org.gnome.ScreenSaver` D-Bus interface, which is not present on non-GNOME sessions
  (e.g. plain Xfce, i3) without a compatible screensaver service.
- `dbus-monitor`, `loginctl`, and `systemctl` available on `PATH` (present by default on
  stock Ubuntu). The script checks for these at startup and exits with a clear error if
  any are missing.

## Install

```bash
# 1. Script
mkdir -p ~/.local/bin
cp bin/lock-suspend-timer.sh ~/.local/bin/
chmod +x ~/.local/bin/lock-suspend-timer.sh

# 2. Systemd user service
mkdir -p ~/.config/systemd/user
cp systemd/lock-suspend.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now lock-suspend.service

# 3. Desktop launcher (optional, lets you restart the service from your app menu)
mkdir -p ~/.local/share/applications
cp desktop/restart-screenlock.desktop ~/.local/share/applications/
```

## Verify it's running

```bash
systemctl --user status lock-suspend.service
journalctl --user -u lock-suspend.service -f
```

Lock your screen and watch the journal — you should see "Lock screen detected!"
immediately, and either a suspend or an "Aborting suspend" message ~5 minutes later
depending on whether you unlocked in time.

## Uninstall

```bash
systemctl --user disable --now lock-suspend.service
rm ~/.config/systemd/user/lock-suspend.service
rm ~/.local/bin/lock-suspend-timer.sh
rm ~/.local/share/applications/restart-screenlock.desktop
systemctl --user daemon-reload
```

## Known limitations

- The script reads `dbus-monitor` output through a single sequential loop, so while a
  300-second countdown is already sleeping, a new lock/unlock/relock cycle won't start a
  *second* concurrent countdown — the pending timer's `loginctl` re-check at expiry is
  what actually decides whether to suspend, so the outcome is always correct, but a new
  visible countdown can be delayed until the current one finishes. This only matters if
  you lock/unlock several times within the same 5-minute window.
