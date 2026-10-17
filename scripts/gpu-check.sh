#!/bin/bash
# In-container assertions. Exit 2 means Mesa fallback, never NVIDIA success.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
case ${1:-graphics} in
    driver)
        command -v nvidia-smi >/dev/null || { echo 'No NVIDIA GPU, falling back to Mesa'; exit 2; }
        actual=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | sort -u)
        [[ -n $actual ]] || fail 'NVIDIA driver query returned no GPUs'
        echo "Container driver: $actual"
        if [[ -n ${EXPECTED_DRIVER_VERSION:-} && $actual != "$EXPECTED_DRIVER_VERSION" ]]; then
            fail "Driver mismatch: expected $EXPECTED_DRIVER_VERSION, got $actual"
        fi
        ;;
    inventory)
        python3 - <<'PY'
import glob, json, os, subprocess
cache = subprocess.check_output(["ldconfig", "-p"], text=True)
def check_library(library):
    path = library
    if not os.path.isabs(path):
        paths = [line.split(" => ")[1] for line in cache.splitlines()
                 if line.strip().startswith(library + " ") and " => " in line]
        if not paths:
            raise RuntimeError("library missing from loader cache: " + library)
        path = paths[0]
    result = subprocess.run(["ldd", path], text=True, capture_output=True)
    if result.returncode or "not found" in result.stdout:
        raise RuntimeError("unresolved dependencies for " + path + ": " + result.stdout + result.stderr)
patterns = [
    '/usr/share/glvnd/egl_vendor.d/10_nvidia.json',
    '/usr/share/egl/egl_external_platform.d/*nvidia*wayland*.json',
    '/usr/share/egl/egl_external_platform.d/*nvidia*gbm*.json',
    '/etc/vulkan/icd.d/*nvidia*.json',
]
try:
    for library in ['libGLX_nvidia.so.0', 'libEGL_nvidia.so.0']:
        check_library(library)
        print('RESOLVE:', library)
    for pattern in patterns:
        paths = glob.glob(pattern)
        if not paths:
            raise RuntimeError('missing injected graphics manifest: ' + pattern)
        for path in paths:
            library = json.load(open(path))['ICD']['library_path']
            check_library(library)
            print('RESOLVE:', path, '->', library)
    backends = glob.glob('/usr/lib/*/gbm/nvidia-drm_gbm.so')
    if not backends:
        raise RuntimeError('missing injected NVIDIA GBM backend')
    for path in backends:
        check_library(path)
        print('RESOLVE:', path, '->', os.path.realpath(path))
except (OSError, ValueError, KeyError, RuntimeError) as error:
    raise SystemExit('FAIL: NVIDIA graphics injection incomplete: ' + str(error))
PY
        ;;
    wayland)
        [[ -S ${XDG_RUNTIME_DIR:-/nonexistent}/${WAYLAND_DISPLAY:-wayland-0} ]] || fail 'Wayland socket unavailable'
        # eglinfo probes other platforms too; their failures are not Wayland failures.
        output=$(timeout 30 eglinfo -B 2>&1) || true
        wayland=$(printf '%s\n' "$output" | awk '/^Wayland platform:/{on=1;next} /^[^ ]+ platform:/{on=0} on')
        printf '%s\n' "$wayland" | sed -n '1,18p'
        [[ $wayland =~ EGL\ vendor\ string:.*NVIDIA ]] || fail 'Native Wayland EGL vendor is not NVIDIA'
        echo 'PASS: native Wayland EGL vendor NVIDIA'
        ;;
    graphics)
        "$0" driver
        # Toolkit 1.20 auto uses JIT-CDI and may inject all libraries even with
        # compute-only capabilities. Reject that configuration explicitly.
        caps=,${NVIDIA_DRIVER_CAPABILITIES:-compute,utility},
        if [[ $caps != *,all,* && ( $caps != *,graphics,* || $caps != *,display,* ) ]]; then
            fail 'NVIDIA graphics capabilities missing: graphics,display required (compute-only is not a graphics configuration)'
        fi
        # Also test actual files: a valid capability string alone proves nothing.
        "$0" inventory
        "$0" wayland
        output=$(timeout 30 glxinfo -B 2>&1) || { echo "$output"; fail 'GLX/Xwayland query failed'; }
        echo "$output"
        [[ $output =~ OpenGL\ vendor\ string:.*NVIDIA ]] || fail 'GLX vendor is not NVIDIA'
        output=$(timeout 30 vulkaninfo --summary 2>&1) || { echo "$output"; fail 'Vulkan query failed'; }
        echo "$output"
        [[ $output =~ vendorID[[:space:]]*=[[:space:]]*0x10de ]] || fail 'Vulkan has no NVIDIA device (vendorID 0x10de)'
        echo 'PASS: Wayland EGL, Xwayland GLX and Vulkan report NVIDIA'
        ;;
    *) fail 'Usage: gpu-check {driver|inventory|wayland|graphics}' ;;
esac
