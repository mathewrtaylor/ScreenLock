# ScreenLock

A small Ubuntu/GNOME utility that watches for the screen locking and automatically
suspends the machine 5 minutes later — but only if it's still locked when the timer
runs out. Useful for laptops/desktops that are set to never dim/sleep on their own but
should still suspend after being left locked and unattended for a while.

## How it works

- `bin/lock-suspend-timer.sh` runs as a systemd user service. It uses `dbus-monitor` to
  watch the session bus for the GNOME screensaver's `ActiveChanged` signal
  (`org.gnome.ScreenSaver`).
- When a lock event (`boolean true`) is seen, it starts a 300-second countdown in the
  background and keeps watching for further signals. A relock partway through cancels the
  in-flight countdown and starts a fresh 300s timer; an unlock (`boolean false`) cancels it
  outright, so rapid lock/unlock cycles are always tracked correctly instead of the outcome
  depending on whichever countdown happened to start first.
- When a countdown runs to completion, it re-checks the *current* lock state via
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

## Power management settings

This does not require any GNOME power settings to be changed — it just listens for the
lock signal and layers on top of whatever's already configured. The one real
prerequisite is that locking still has to happen somehow (manual `Super+L`, or GNOME's
own idle-triggered auto-lock); if lock is fully disabled and you never lock manually
either, there's never an event for the script to react to.

That said, most stock Ubuntu/GNOME installs also ship GNOME's own idle-based
**Automatic Suspend** (`Settings → Power → Automatic Suspend`, i.e.
`org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type` /
`sleep-inactive-battery-type`) turned on by default. That's a second, independent
suspend trigger — harmless to run alongside this script (`systemctl suspend` is
idempotent, so there's no conflict), but since GNOME's timer counts from the start of
overall inactivity while this script counts from the lock event, this script's timer
usually fires first once locked, so the machine may end up suspending sooner than
GNOME's own power settings suggest.

If you want this script's "suspend 5 minutes after lock" rule to be the actual,
predictable suspend policy rather than a redundant second timer, turn off GNOME's
Automatic Suspend (or set `sleep-inactive-ac-type`/`sleep-inactive-battery-type` to
`nothing`) so this is the only thing putting the machine to sleep. Screen blanking
(`idle-delay`) is unaffected either way — auto-lock-on-idle fires the same signal as a
manual lock, so it works identically regardless of that setting.

## Install

```bash
./install.sh
```

This symlinks `bin/lock-suspend-timer.sh`, `systemd/lock-suspend.service`, and
`desktop/restart-screenlock.desktop` into `~/.local/bin`, `~/.config/systemd/user`, and
`~/.local/share/applications` respectively (backing up any existing non-symlink file
first), then reloads and (re)starts the service. Safe to re-run any time.

Because the installed files are symlinks *into this clone* rather than copies, there's
nothing to keep in sync by hand — see [Update](#update) below.

## Update

```bash
./update.sh
```

Runs `git pull` and then `install.sh` again — the equivalent of `apt update && apt
full-upgrade` for this repo. Since install uses symlinks, there's no copying involved;
this just pulls the latest code and restarts the service so it picks it up.

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

(These are symlinks if installed via `install.sh`, so `rm` just removes the link — the
repo clone itself is untouched.)

