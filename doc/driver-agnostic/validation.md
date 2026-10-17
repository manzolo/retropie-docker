# Driver-agnostic validation — 2026-10-17

Environment: Docker 29.9.1, NVIDIA Container Toolkit/libnvidia-container 1.20.1,
host driver 615.71.09, NVIDIA GeForce RTX 3080 Ti, Wayland `wayland-1` and Xwayland
`:0`. All image builds/installations happened inside Docker. Native RetroPie,
host driver packages, `/etc`, udev rules and home symlinks were not changed.

## Graphics stage

Exact commands:

```bash
docker build --progress=plain --target diagnostics --iidfile /tmp/retropie-graphics.iid -f retropie/Dockerfile .
TEST_IMAGE=$(cat /tmp/retropie-graphics.iid) ./scripts/test-driver-agnostic.sh
```

Both exited 0. [Complete test output](graphics-stage-tests.txt) records the image ID,
zero baked-in driver files, host/container equality, dependency resolution and
NVIDIA vendor output for native Wayland EGL, Xwayland GLX and Vulkan. It also
records the expected failures for compute-only graphics, runc/Mesa and a fake
expected driver version. This run tested the diagnostics stage; final-image
validation is recorded separately.

## Observed toolkit behavior

A disposable `ubuntu:24.04` container with `--runtime=nvidia`, visible devices `all`
and capabilities `graphics,display,video,compute,utility` exposed:

- GLX/EGL libraries with version 615.71.09 and the GLVND NVIDIA manifest.
- `libnvidia-egl-wayland.so.1.1.21`, `libnvidia-egl-wayland2.so.1.0.2` and both manifests.
- `libnvidia-egl-gbm.so.1.1.3`, its manifest and `gbm/nvidia-drm_gbm.so`.
- `/etc/vulkan/icd.d/nvidia_icd.json`, referencing `libGLX_nvidia.so.0`.

The unchanged host runtime config has `mode = "auto"`. Toolkit 1.20.1's
[mode resolver](https://github.com/NVIDIA/nvidia-container-toolkit/blob/v1.20.1/internal/info/auto.go)
selects JIT-CDI on this platform. In a separate compute-only probe, GLX/EGL
libraries were still present. The test explicitly rejects missing graphics/display
capabilities as invalid configuration; it does **not** claim JIT-CDI removed those
libraries. The positive tests independently exercise actual rendering APIs.
No static CDI files or host configuration changes were needed.

## Failures found and corrected

[Verbatim failed-run output](initial-failures.txt) includes:

1. The first complete build failed with RetroPie's "Not connected to the Internet"
   because `iproute2` was missing. `git clone` and apt worked; RetroPie's network
   detection needed the `ip` command. Added `iproute2` and `gpg-agent` in the image.
2. The first inventory test used ctypes to load every EGL/GBM plugin into one
   Python process and crashed at shutdown (exit 134). The test now resolves
   dependencies with `ldd`; actual API tools perform the functional loading.
3. The first compute-only assertion incorrectly expected missing graphics files.
   The JIT-CDI observation above changed the test to validate the capability
   contract explicitly, with a matching diagnostic and exit status.

## Static checks and Compose

[Exact commands and output](static-checks.txt) cover Bash syntax, ShellCheck,
legacy targets, rendered Compose and whitespace. All exited 0.
[External-ROM Compose output](external-roms-config.txt) checks root-relative paths
with spaces and a read-only nested ROM bind with `create_host_path: false`.
No Compose service was started by these rendering checks.

## Legacy images retained

Command (exit 0):

```bash
docker image ls --filter 'reference=manzolo/retropie:latest-nvidia*' --filter 'reference=manzolo/ubuntu-nvidia:*' --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'
```

[Exact image list](legacy-images.txt). All twelve images were left intact. Removal
is a separate manual action for Andrea. No registry push was performed.

## Manual limits

The host driver was not upgraded/downgraded during this task. The clean-image plus
injection tests establish the current mechanism, not compatibility with every
future driver/host ABI. The source-built emulators retain RetroPie's CPU tuning;
move the same image only to a compatible CPU/architecture, or rebuild there.

No actual SNES/GameCube gameplay, audible sound or physical controller input has
been accepted automatically. Follow the [manual test](manual-test.md). The desktop
probe successfully contacted PulseAudio on PipeWire 1.6.2 and found `/dev/input/js0`,
`/dev/uinput` and both audio control devices; that alone is not a gameplay test.
