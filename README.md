# RetroPie Docker

> **Disclaimer:** unofficial hobby project, not affiliated with or endorsed by RetroPie,
> RetroArch/libretro, Dolphin, Flycast, ScummVM or EmulationStation. Use as-is, no support.

[RetroPie](https://retropie.org.uk/) on a Linux Wayland desktop with an NVIDIA GPU, confined to a
container: **one image built on your machine, one portable data directory, nothing installed on
the host, and no NVIDIA driver inside the image** (the host's is injected at start, so a driver
update never needs a rebuild).

**No games, ROMs, BIOS files or artwork are included, ever.** They are copyrighted: you supply
your own, in the data directory.

## Quick start

```bash
git clone https://github.com/manzolo/retropie-docker.git && cd retropie-docker
make build                      # compiles RetroPie from source inside Docker: hours, not minutes
make test                       # clean image, GPU injection, data persistence, deliberate failures
mkdir -p data/roms/snes data/BIOS   # add your own ROMs and BIOS files here
make retropie-start             # EmulationStation on your desktop · retropie-logs · retropie-stop
```

Needs Docker with Compose v2, a Wayland desktop with Xwayland, an NVIDIA driver plus the
[NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html),
and a controller. `make wizard` does the same interactively; `make help` lists everything.

| Your files | Where |
|---|---|
| ROMs | `data/roms/<system>/` (`snes`, `gc`, `dreamcast`, …), or an existing collection mounted read-only with `RETROPIE_ROMS_DIR=/path` in `.env` |
| BIOS | `data/BIOS/` in RetroPie's layout (e.g. `data/BIOS/dc/` for Dreamcast) |

Everything else (saves, states, configuration) lands in `data/` too. Copy that folder and you
have moved your installation. `data/` is ignored by git and `make check-public` refuses game data
anywhere in the history: keep it that way if you fork.

## Details

<details>
<summary><b>Host requirements</b></summary>

- Linux with a **Wayland** desktop and Xwayland (Dolphin runs through Xwayland). X11-only desktops
  are not tested.
- Docker Engine with Compose v2.
- An NVIDIA GPU with a working host driver and the NVIDIA Container Toolkit (validated with toolkit
  1.20.1 and driver 615). Once, on the host:

  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  ```

  Without an NVIDIA GPU the container starts on Mesa and says so; not a tested configuration.
- PulseAudio, or PipeWire's PulseAudio socket, and a game controller on `/dev/input`.

Run everything from your desktop session: the scripts read `DISPLAY`, `WAYLAND_DISPLAY`,
`XDG_RUNTIME_DIR` and your Xauthority cookie (mounted read-only; `xhost` is never called).
`make retropie-debug-display` shows what was detected; `make retropie-enter` opens a shell in the
running container.
</details>

<details>
<summary><b>The data directory</b></summary>

Set `RETROPIE_DATA_DIR` in `.env` (default `./data`, relative to the repository root). Its contents
are mounted at `/data` in the container:

| Subdirectory | Contents |
|---|---|
| `roms/<system>` | your ROMs |
| `BIOS` | your BIOS files |
| `saves`, `states` | RetroArch saves and save states (kept here even for read-only ROM collections) |
| `configs` | `/opt/retropie/configs`: RetroArch, EmulationStation user settings, Dolphin in `configs/gc` |
| `emulationstation` | `/etc/emulationstation` (systems, themes) |
| `home-config`, `home-data` | XDG settings and application data |

Default configuration is stored in the image and copied on first start, only where a file is
missing: your edits are never overwritten. The container maps its user to your `PUID`/`PGID`
without recursively changing ownership of anything.

**Existing ROM collection:** `RETROPIE_ROMS_DIR=/path/to/roms` in `.env`. Mounted read-only at
`/data/roms`, never copied or modified; saves and states still go to `data/`.

**Moving to another PC:** `make retropie-stop`, copy `data/` (and your ROM collection if it is
external), clone this repository there, `make build`, set `PUID`/`PGID` in `.env` if the user
differs, `make retropie-start`.
</details>

<details>
<summary><b>Migrating from a native RetroPie</b></summary>

Your settings live in `/opt/retropie/configs` on the native install. With the container stopped,
copy them into the data directory, leaving out the emulator lists (the image has its own set):

```bash
rsync -a --exclude 'emulators.cfg' --exclude 'all/emulationstation/themes/' \
      --exclude 'all/emulationstation/es_systems.cfg' --exclude '**/Cache/' --exclude '*.bak' \
      /opt/retropie/configs/ data/configs/
sed -i -E 's|^[# ]*savefile_directory =.*|savefile_directory = "/data/saves"|; s|^[# ]*savestate_directory =.*|savestate_directory = "/data/states"|' data/configs/all/retroarch.cfg
```

That carries over controller mappings (`es_input.cfg`, `retroarch-joypads/`), EmulationStation
settings, gamelists and artwork, RetroArch overrides and Dolphin (`gc/`, including memory cards).
Keep the container username equal to your native one if your configuration contains absolute
home paths (the default, `manzolo`, can be changed with the `CONTAINER_USERNAME` build argument).
The native installation is not modified.

Native RetroPie keeps RetroArch saves and states **next to the ROMs** (`savefile_directory = "default"`);
the container keeps them in `data/saves` and `data/states`, found by game name. Copy them once:

```bash
find /path/to/roms -name '*.srm' -exec cp -pn {} data/saves/ \;
find /path/to/roms -name '*.state*' -exec cp -pn {} data/states/ \;
```

One trap met while migrating: RetroArch only reads pad profiles from `autoconfig/<driver>/`
(`udev/` on Linux) when that subdirectory exists. If your native setup mixed RetroPie's flat
profiles with the libretro autoconfig pack (subdirectories), copy your own profile into
`data/configs/all/retroarch/autoconfig/udev/`, or the stock profile wins and your hotkeys are lost.
`retroarch --verbose` prints which profile was configured.
</details>

<details>
<summary><b>How the GPU works</b></summary>

The image ships only the generic loaders (GLVND, EGL, Vulkan, GBM, Wayland client libraries) plus
Mesa as a fallback, and contains **no `libnvidia-*` file**. Compose starts the container with
`runtime: nvidia` and `NVIDIA_DRIVER_CAPABILITIES=graphics,display,video,compute,utility`; the
toolkit mounts the host's GLX/EGL/Vulkan libraries, the EGL-Wayland and GBM platform plugins and
their manifests at creation time. If the injected EGL-Wayland platform does not work, startup falls
back to Xwayland for SDL/GTK applications and logs it. Dolphin always uses Xwayland. After a host
driver upgrade, recreate the container (`make retropie-stop`, then `make retropie-start`) and run
`make test`.

Details, measured toolkit behaviour and limits:
[doc/driver-agnostic/validation.md](doc/driver-agnostic/validation.md).
</details>

<details>
<summary><b>Portability of the image</b></summary>

RetroPie-Setup compiles with `-march=native`, so the image is optimised for the CPU that built it
and may not run on a different CPU family. Build on the machine that will run it (that is why no
image is published): the data directory is independent of the build.
</details>

<details>
<summary><b>Emulators</b></summary>

`basic_install` from RetroPie-Setup (EmulationStation, RetroArch and the basic cores), then
`lr-snes9x`, `dolphin`, `lr-flycast-dev`, `lr-mame2003`, `lr-mame2015`, `lr-mame2016`,
`lr-pcsx-rearmed`, `lr-quicknes`, `lr-parallel-n64`, `lr-mupen64plus-next` and `scummvm`.
Each package is one `RUN` line in `retropie/Dockerfile`: add or remove lines to taste, and a
package that fails to build does not discard the ones already built. `RETROPIE_SETUP_REF` pins
the RetroPie-Setup commit; bump it deliberately and rebuild. Every system gets a default
emulator (the first listed) so that EmulationStation can launch it.
</details>

<details>
<summary><b>Verification</b></summary>

- `make test` runs disposable containers (never your data): the image contains no driver files,
  the driver version inside the container equals the host's, the injected graphics manifests
  resolve, Wayland EGL, Xwayland GLX and Vulkan report NVIDIA, and defaults, user mapping and
  persistence work across container recreation. It also requires three deliberate failures to be
  rejected: compute-only capabilities, no NVIDIA runtime, a fake expected driver version.
- `make test-desktop` checks the PulseAudio connection and controller device access.
- `make check-public` scans the whole git history for game data, secrets and private hosts,
  after proving on a throwaway repository that an injected BIOS is rejected.
- [doc/driver-agnostic/manual-test.md](doc/driver-agnostic/manual-test.md): the gameplay
  acceptance test (one SNES game, one GameCube game, sound, controller).
</details>

<details>
<summary><b>Repository layout</b></summary>

```
retropie/Dockerfile             graphics, diagnostics and RetroPie stages (one image)
retropie/docker-compose.yml     the service; docker-compose.roms.yml adds a read-only ROM mount
retropie/retropie-entrypoint.sh user mapping, first-start defaults, GPU/Wayland fallback
scripts/                        launcher, wizard, GPU checks, tests, check-public
doc/driver-agnostic/            validation evidence and the manual test
Makefile                        make help lists everything
```
</details>

## Credits and license

Built on [RetroPie](https://retropie.org.uk/) and its setup scripts, [RetroArch and the libretro
cores](https://www.libretro.com/), [Dolphin](https://dolphin-emu.org/),
[Flycast](https://github.com/flyinghead/flycast), [ScummVM](https://www.scummvm.org/) and
[EmulationStation](https://emulationstation.org/), each under its own license. This recipe is
released under the [MIT License](LICENSE).
