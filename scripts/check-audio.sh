#!/bin/bash
# Check audio configuration for RetroPie Docker

set -e

echo "=== Audio Configuration Check ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check functions
check_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Check PulseAudio
echo "--- PulseAudio ---"
if command -v pulseaudio >/dev/null 2>&1; then
    check_pass "PulseAudio installed"

    if pulseaudio --check 2>/dev/null; then
        check_pass "PulseAudio is running"
    else
        check_warn "PulseAudio not running - attempting to start..."
        pulseaudio --start 2>/dev/null && check_pass "PulseAudio started" || check_fail "Could not start PulseAudio"
    fi
else
    check_fail "PulseAudio not installed"
    echo "  Install with: sudo apt install pulseaudio"
fi

echo ""

# Check PulseAudio socket
echo "--- PulseAudio Socket ---"
if [ -n "$XDG_RUNTIME_DIR" ]; then
    check_pass "XDG_RUNTIME_DIR is set: $XDG_RUNTIME_DIR"

    PULSE_SOCKET="$XDG_RUNTIME_DIR/pulse/native"
    if [ -S "$PULSE_SOCKET" ]; then
        check_pass "PulseAudio socket exists: $PULSE_SOCKET"
        ls -la "$PULSE_SOCKET"
    else
        check_fail "PulseAudio socket not found: $PULSE_SOCKET"
        echo "  Try restarting PulseAudio: pulseaudio --kill && pulseaudio --start"
    fi

    # Check socket directory permissions
    if [ -d "$XDG_RUNTIME_DIR/pulse" ]; then
        PERMS=$(stat -c %a "$XDG_RUNTIME_DIR/pulse" 2>/dev/null)
        if [ "$PERMS" = "700" ] || [ "$PERMS" = "755" ]; then
            check_pass "PulseAudio directory permissions OK ($PERMS)"
        else
            check_warn "PulseAudio directory permissions: $PERMS (may cause issues)"
        fi
    fi
else
    check_fail "XDG_RUNTIME_DIR not set"
fi

echo ""

# Check ALSA devices
echo "--- ALSA Devices ---"
if [ -e "/dev/snd" ]; then
    check_pass "/dev/snd exists"

    DEV_COUNT=$(ls -1 /dev/snd/ 2>/dev/null | wc -l)
    if [ "$DEV_COUNT" -gt 0 ]; then
        check_pass "Found $DEV_COUNT ALSA device(s)"
        ls -la /dev/snd/ | head -10
    else
        check_fail "No devices found in /dev/snd"
    fi
else
    check_fail "/dev/snd not found"
fi

echo ""

# Check audio playback capability
echo "--- Audio Playback Test ---"
if command -v pactl >/dev/null 2>&1; then
    check_pass "pactl command available"

    # List sinks
    SINK_COUNT=$(pactl list short sinks 2>/dev/null | wc -l)
    if [ "$SINK_COUNT" -gt 0 ]; then
        check_pass "Found $SINK_COUNT audio sink(s)"
        echo ""
        echo "Available sinks:"
        pactl list short sinks
    else
        check_fail "No audio sinks found"
    fi
else
    check_warn "pactl not available (install pulseaudio-utils)"
fi

echo ""

# Check machine-id
echo "--- System Configuration ---"
if [ -f "/etc/machine-id" ]; then
    check_pass "/etc/machine-id exists"
else
    check_fail "/etc/machine-id not found (required for PulseAudio)"
    echo "  Generate with: sudo dbus-uuidgen --ensure=/etc/machine-id"
fi

if [ -f "/var/lib/dbus/machine-id" ]; then
    check_pass "/var/lib/dbus/machine-id exists"
else
    check_warn "/var/lib/dbus/machine-id not found"
fi

echo ""

# D-Bus check
if [ -S "/run/dbus/system_bus_socket" ]; then
    check_pass "D-Bus system socket exists"
else
    check_warn "D-Bus system socket not found"
fi

if [ -n "$DBUS_SESSION_BUS_ADDRESS" ]; then
    check_pass "D-Bus session address set"
else
    check_warn "DBUS_SESSION_BUS_ADDRESS not set"
fi

echo ""

# Recommendations
echo "--- Recommendations ---"
if ! command -v pulseaudio >/dev/null 2>&1; then
    echo -e "${RED}Install PulseAudio first!${NC}"
    echo "  sudo apt install pulseaudio"
elif ! pulseaudio --check 2>/dev/null; then
    echo -e "${YELLOW}Start PulseAudio:${NC}"
    echo "  pulseaudio --start"
elif [ ! -S "$XDG_RUNTIME_DIR/pulse/native" ]; then
    echo -e "${YELLOW}PulseAudio socket not found. Try:${NC}"
    echo "  pulseaudio --kill && pulseaudio --start"
else
    echo -e "${GREEN}Audio configuration looks good!${NC}"
    echo ""
    echo "If you still have audio issues in the container:"
    echo "  1. Check docker-compose.yml mounts $XDG_RUNTIME_DIR/pulse"
    echo "  2. Verify /dev/snd is mounted"
    echo "  3. Check volume levels: pavucontrol"
fi

echo ""
echo "=== Check Complete ==="
