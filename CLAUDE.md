# CLAUDE.md

Guidance for Claude Code (claude.ai/code) in this repository.

## What this is

A Docker recipe for RetroPie on a Linux Wayland desktop with an NVIDIA GPU: one image
(`manzolo/retropie:latest`), built locally from the official RetroPie-Setup scripts, and one
portable data directory. The README is the reference for users; this file is for maintainers.

## Rules that must not be broken

- **Never commit game data.** No ROMs, BIOS files, saves, states or scraped artwork, in any
  commit. `data/` and `retropie/mount/` are ignored; `make check-public` scans the whole
  history and must pass before any push. The repository is public.
- **No driver in the image.** `retropie/Dockerfile` must not install `libnvidia-*`; the
  NVIDIA Container Toolkit injects the host driver at container creation (`runtime: nvidia`,
  capabilities `graphics,display,video,compute,utility`). The build test checks this.
- **Never touch the host.** Scripts do not run apt, do not write `/etc` or udev rules, do not
  call `xhost`, and never recursively `chown` a bind mount.
- **One image, one tag** (`latest`). Driver-version matrices and base images are gone; old
  `make *-nvidia-XXX` targets only print what replaced them.

## Build

- `retropie/Dockerfile`: stages `graphics` (loaders + Mesa), `diagnostics` (adds
  `gpu-check`), `retropie` (final). The build context is the repository root.
- `RETROPIE_SETUP_REF` pins RetroPie-Setup to a commit. Bump it on purpose, rebuild, run
  `make test`. `make outdated` (`scripts/outdated.sh`, read-only) shows what a bump, a new base
  digest or `make update` would bring; both pins invalidate every layer after them.
  RetroPie-Setup master can break (2026-10: `lr-flycast`'s stale gcc14 patch; `lr-flycast-dev`
  is used instead, as recommended by the RetroPie maintainers).
- One `RUN` per package after `basic_install`, so a failing package keeps the layers already
  built. A full build compiles from source and takes hours; run it in the background.
- RetroPie-Setup compiles with `-march=native`: the image is tied to the CPU family that built
  it. That is documented, not hidden.

## Runtime

- `scripts/common.sh` reads `.env` as data (never sourced as shell), resolves
  `RETROPIE_DATA_DIR` (default `./data`) and optional `RETROPIE_ROMS_DIR` (read-only).
- `retropie/retropie-entrypoint.sh` maps the container user to `PUID`/`PGID`, seeds
  `/data` from `/usr/local/share/retropie-defaults` only where files are missing, adds device
  groups, and falls back to Xwayland when NVIDIA EGL-Wayland is unavailable.
- `scripts/prepare-data.sh` runs at build time: moves defaults out of the mounted paths and
  symlinks them to `/data`.

## Tests

`make test` (`scripts/test-driver-agnostic.sh`, `scripts/test-data.sh`), `make test-desktop`,
`make check-public` (with its own self-test that injects a fake BIOS and expects rejection),
and the manual gameplay test in `doc/driver-agnostic/manual-test.md`. Tests use throwaway
fixtures in `/tmp`, never the configured data directory. Keep the deliberate-failure cases:
a test that cannot fail proves nothing.
