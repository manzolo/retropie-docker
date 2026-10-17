#!/bin/bash
# Healthcheck script for RetroPie Docker container

# Check if EmulationStation process is running
if ! pgrep -f /usr/bin/emulationstation > /dev/null 2>&1; then
    # EmulationStation not running - could be intentional (bash mode) or a crash
    # Check if we're in bash mode (tty attached)
    if [ -t 0 ]; then
        # Interactive mode - healthy
        exit 0
    fi

    # Not interactive and EmulationStation not running - unhealthy
    echo "EmulationStation not running and not in interactive mode"
    exit 1
fi

# EmulationStation is running - check if it's responsive
# Look for the log file to ensure it's actually started
if [ -f "${RETROPIE_LOG}" ]; then
    # Check if log was modified recently (within last 5 minutes)
    LOG_AGE=$(( $(date +%s) - $(stat -c %Y "${RETROPIE_LOG}" 2>/dev/null || echo 0) ))
    if [ "$LOG_AGE" -gt 300 ]; then
        echo "Warning: Log file hasn't been updated in ${LOG_AGE} seconds"
        # Not failing on this, just warning
    fi
fi

# Check if display is accessible (basic test)
if [ -n "$DISPLAY" ]; then
    # X11 mode - check if display socket is accessible
    if [ ! -e "/tmp/.X11-unix" ]; then
        echo "Warning: X11 socket directory not found"
    fi
elif [ -n "$WAYLAND_DISPLAY" ]; then
    # Wayland mode - check if socket exists
    WAYLAND_SOCKET="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    if [ ! -S "$WAYLAND_SOCKET" ]; then
        echo "Warning: Wayland socket not found at $WAYLAND_SOCKET"
    fi
fi

# All checks passed
exit 0
