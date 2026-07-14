#!/bin/bash

# Check required dependencies up front so failures are clear rather than
# surfacing as a cryptic dbus-monitor or loginctl error mid-run.
for cmd in dbus-monitor loginctl systemctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' not found. This script needs a GNOME (or GNOME-compatible) Ubuntu desktop session." >&2
        exit 1
    fi
done

echo "Lock-suspend service started. Monitoring D-Bus for screen lock signals..."

# Force path safety and handle standard user session bus
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"

dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" | while read -r line; do
    if echo "$line" | grep -q "boolean true"; then
        echo "Lock screen detected! Starting 5-minute (300s) countdown..."
        sleep 300

        # Get the actual session ID for the current user instead of using 'self'
        USER_SESSION=$(loginctl list-sessions | grep "$(id -un)" | awk '{print $1}' | head -n 1)

        # Pull the absolute session lock status using the explicit session ID
        IS_LOCKED=$(loginctl show-session "$USER_SESSION" --property=LockedHint | cut -d= -f2)
        echo "Countdown finished. Current lock state check returned: $IS_LOCKED"

        if [ "$IS_LOCKED" = "yes" ]; then
            echo "Device is still locked. Triggering system suspend now."
            systemctl suspend
        else
            echo "Device was unlocked before the timer finished. Aborting suspend."
        fi
    fi
done
