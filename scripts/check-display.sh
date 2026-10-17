#!/bin/bash
# Check display configuration for RetroPie Docker

set -e

echo "=== Display Configuration Check ==="
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

# Check X11
echo "--- X11 Configuration ---"
if [ -n "$DISPLAY" ]; then
    check_pass "DISPLAY is set: $DISPLAY"

    if [ -d "/tmp/.X11-unix" ]; then
        check_pass "X11 socket directory exists"
        ls -la /tmp/.X11-unix/ | grep -q "X" && check_pass "X11 socket files found" || check_fail "No X11 socket files found"
    else
        check_fail "X11 socket directory not found"
    fi

    if command -v xhost >/dev/null 2>&1; then
        check_pass "xhost command available"
        xhost | grep -q "LOCAL" && check_pass "X11 access configured for local connections" || check_warn "X11 access may not be configured (run: xhost local:docker)"
    else
        check_warn "xhost command not found (install x11-xserver-utils)"
    fi

    if command -v xdpyinfo >/dev/null 2>&1; then
        if xdpyinfo >/dev/null 2>&1; then
            check_pass "X11 connection successful"
        else
            check_fail "Cannot connect to X11 display"
        fi
    else
        check_warn "xdpyinfo not available for testing"
    fi
else
    check_fail "DISPLAY not set"
fi

echo ""

# Check Wayland
echo "--- Wayland Configuration ---"
if [ -n "$WAYLAND_DISPLAY" ]; then
    check_pass "WAYLAND_DISPLAY is set: $WAYLAND_DISPLAY"

    if [ -n "$XDG_RUNTIME_DIR" ]; then
        check_pass "XDG_RUNTIME_DIR is set: $XDG_RUNTIME_DIR"

        WAYLAND_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
        if [ -S "$WAYLAND_SOCKET" ]; then
            check_pass "Wayland socket exists: $WAYLAND_SOCKET"
            ls -la "$WAYLAND_SOCKET"
        else
            check_fail "Wayland socket not found: $WAYLAND_SOCKET"
        fi
    else
        check_fail "XDG_RUNTIME_DIR not set"
    fi
else
    check_warn "WAYLAND_DISPLAY not set (X11-only configuration?)"
fi

echo ""

# Check XDG Session
echo "--- Session Information ---"
if [ -n "$XDG_SESSION_TYPE" ]; then
    check_pass "Session type: $XDG_SESSION_TYPE"
else
    check_warn "XDG_SESSION_TYPE not set"
fi

if [ -n "$XDG_CURRENT_DESKTOP" ]; then
    echo -e "Current desktop: $XDG_CURRENT_DESKTOP"
fi

echo ""

# Recommendations
echo "--- Recommendations ---"
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    echo -e "${RED}ERROR: No display server detected!${NC}"
    echo "Please ensure you have X11 or Wayland running"
elif [ -n "$WAYLAND_DISPLAY" ] && [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
    echo -e "${YELLOW}Wayland socket not accessible. Try:${NC}"
    echo "  - Check compositor is running"
    echo "  - Verify XDG_RUNTIME_DIR permissions"
elif [ -n "$DISPLAY" ]; then
    echo -e "${GREEN}Configuration looks good!${NC}"
    echo "If you still have issues, try:"
    echo "  - Run: xhost local:docker"
    echo "  - Check docker-compose.yml mounts /tmp/.X11-unix"
fi

echo ""
echo "=== Check Complete ==="
