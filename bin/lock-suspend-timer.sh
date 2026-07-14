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

# Runs as a background job so the main loop stays free to react to further
# lock/unlock events instead of being blocked inside `sleep 300`. Traps TERM
# so a cancellation (see cancel_countdown) also kills the sleep child instead
# of leaving it running as an orphan for the rest of its 300s.
run_countdown() {
    trap 'kill "$SLEEP_PID" 2>/dev/null; exit 0' TERM
    sleep 300 &
    SLEEP_PID=$!
    wait "$SLEEP_PID"

    # Prefer $XDG_SESSION_ID (set by the graphical session this service is
    # bound to) since it can't be mismatched the way username-grepping can
    # when multiple sessions/users are logged in. Fall back to the old
    # lookup only if it's somehow unset.
    USER_SESSION="${XDG_SESSION_ID:-$(loginctl list-sessions | grep "$(id -un)" | awk '{print $1}' | head -n 1)}"

    # Pull the absolute session lock status using the explicit session ID
    IS_LOCKED=$(loginctl show-session "$USER_SESSION" --property=LockedHint | cut -d= -f2)
    echo "Countdown finished. Current lock state check returned: $IS_LOCKED"

    if [ "$IS_LOCKED" = "yes" ]; then
        echo "Device is still locked. Triggering system suspend now."
        systemctl suspend
    else
        echo "Device was unlocked before the timer finished. Aborting suspend."
    fi
}

# Kills any in-flight countdown so a relock can start a fresh one and an
# unlock can drop a pending one immediately, instead of both being stuck
# behind whichever countdown happened to start first.
cancel_countdown() {
    if [ -n "$COUNTDOWN_PID" ] && kill -0 "$COUNTDOWN_PID" 2>/dev/null; then
        kill "$COUNTDOWN_PID" 2>/dev/null
        wait "$COUNTDOWN_PID" 2>/dev/null
    fi
    COUNTDOWN_PID=""
}

COUNTDOWN_PID=""

dbus-monitor --session "type='signal',interface='org.gnome.ScreenSaver'" | while read -r line; do
    if echo "$line" | grep -q "boolean true"; then
        if [ -n "$COUNTDOWN_PID" ] && kill -0 "$COUNTDOWN_PID" 2>/dev/null; then
            echo "Lock screen detected again during an active countdown — restarting the 5-minute timer."
        else
            echo "Lock screen detected! Starting 5-minute (300s) countdown..."
        fi
        cancel_countdown
        run_countdown &
        COUNTDOWN_PID=$!
    elif echo "$line" | grep -q "boolean false"; then
        if [ -n "$COUNTDOWN_PID" ] && kill -0 "$COUNTDOWN_PID" 2>/dev/null; then
            echo "Screen unlocked — cancelling pending suspend countdown."
            cancel_countdown
        fi
    fi
done
