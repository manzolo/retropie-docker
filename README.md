# RetroPie Docker

> **Disclaimer:** unofficial hobby project, not affiliated with or endorsed by RetroPie,
> RetroArch/libretro, Dolphin, Flycast, ScummVM or EmulationStation. Use as-is, no support.

[RetroPie](https://retropie.org.uk/) on a Linux desktop (Wayland or X11), confined to a container:
**one image built on your machine, one portable data directory, nothing installed on the host.**
With an NVIDIA GPU the host's driver is injected at start (no driver inside the image, so a driver
update never needs a rebuild); with Intel, AMD or no GPU at all the image's own Mesa draws.

**No games, ROMs, BIOS files or artwork are included, ever.** They are copyrighted: you supply
your own, in the data directory.

**Status: experimental.** Two tested setups:

| Mode | Tested on |
|---|---|
| NVIDIA + Wayland | Ubuntu 26.04, niri compositor (Xwayland), NVIDIA RTX with driver 615, NVIDIA Container Toolkit 1.20.1, PS3 controller |
| Mesa + X11 | Lubuntu 22.04 (LXQt) in a virtual machine without GPU acceleration: software rendering |

The mode is picked automatically (`RETROPIE_GPU`, `RETROPIE_SESSION` in `.env` to force it). Intel
and AMD GPUs go through Mesa with hardware acceleration and should work, but are not tested;
non-Linux hosts are not supported. Run `make doctor` first: it checks every requirement, says
which mode it will use and what is missing.

## Quick start

The same steps for every GPU: the graphics mode is chosen at each start, nothing to configure.

| Your GPU | Before you start | Mode `make doctor` reports |
|---|---|---|
| Intel, AMD, or none (virtual machine) | nothing: Mesa is inside the image | `mesa` (hardware acceleration, or software rendering without `/dev/dri/renderD*`) |
| NVIDIA | the host driver plus the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html), registered in Docker ([below](#details)) | `nvidia` (without the toolkit: `mesa`, software rendering, with a warning) |

```bash
git clone https://github.com/manzolo/retropie-docker.git && cd retropie-docker
make doctor                     # what is missing, and which GPU mode (nvidia/mesa) and desktop (wayland/x11) will be used
make build                      # compiles RetroPie from source inside Docker: hours, not minutes
make test                       # clean image, graphics (NVIDIA injection, or Mesa rendering), data persistence
mkdir -p data/roms/snes data/BIOS   # add your own ROMs and BIOS files here
make start                      # EmulationStation on your desktop · make logs · make stop
```

Needs Docker with Compose v2, a Wayland (with Xwayland) or X11 desktop and a controller (the
keyboard works too). To force a mode, set `RETROPIE_GPU=nvidia|mesa` or
`RETROPIE_SESSION=wayland|x11` in `.env`. `make wizard` does the same steps interactively;
`make help` lists everything.

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

- Linux with a **Wayland** desktop and Xwayland (Dolphin runs through Xwayland), or an **X11**
  desktop.
- Docker Engine with Compose v2 (on Ubuntu: `sudo apt install docker.io docker-compose-v2`, then
  add yourself to the `docker` group and log in again).
- GPU, one of:
  - **Intel or AMD** (or none): nothing to install, Mesa is in the image. Without a render node
    (`/dev/dri/renderD*`, typical in virtual machines) rendering is software: fine for 8- and
    16-bit systems, too slow for GameCube or Dreamcast.
  - **NVIDIA**: a working host driver and the NVIDIA Container Toolkit (validated with toolkit
    1.20.1 and driver 615). Without the toolkit the NVIDIA GPU is unused and rendering is software.
    Once, on the host:

    ```bash
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    ```
- PulseAudio, or PipeWire's PulseAudio socket, and a game controller on `/dev/input`.

Run everything from your desktop session: the scripts read `DISPLAY`, `WAYLAND_DISPLAY`,
`XDG_RUNTIME_DIR` and your Xauthority cookie (mounted read-only; `xhost` is never called).
`make retropie-debug-display` shows what was detected; `make retropie-enter` opens a shell in the
running container.
</details>

<details>
<summary><b>What the container can access, and why</b></summary>

The container confines installation and dependencies, not security: to draw on your desktop and use
your controller it gets a lot of the host. Each item is there for a reason found in testing:

| Access | Why |
|---|---|
| `/dev/dri`, NVIDIA runtime (NVIDIA mode only) | GPU (with NVIDIA the driver comes from the host) |
| `/tmp/.X11-unix`, X authority, Wayland socket (Wayland only), all read-only | drawing; Dolphin and some cores need X11/Xwayland |
| PulseAudio/PipeWire socket | sound |
| `/dev/input`, `/dev/uinput`, `/run/udev/data` | controllers and their hot-plug |
| session and system D-Bus (read-only) | desktop integration of some emulators |
| host network | netplay and RetroArch network commands |
| AppArmor unconfined | the default profile blocks parts of the above |

Do not run games you do not trust in it any more than you would on the desktop itself.
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
missing: your edits are never overwritten. Two files are merged instead, because the image can gain
emulators after your data was created: `emulationstation/es_systems.cfg` gets the systems it lacks,
and each `configs/<system>/emulators.cfg` gets the emulator lines it lacks. Existing lines, including
the `default` you chose, are never changed, and the file is backed up next to itself
(`emulators.cfg.bak-<date>`) before the first change. The container maps its user to your `PUID`/`PGID`
without recursively changing ownership of anything.

**Existing ROM collection:** `RETROPIE_ROMS_DIR=/path/to/roms` in `.env`. Mounted read-only at
`/data/roms`, never copied or modified; saves and states still go to `data/`. The one exception:
each `<system>/gamelist.xml` already in the collection is mounted writable (the launcher generates
`retropie/docker-compose.gamelists.yml` at every start), because EmulationStation saves favourites,
play counts and metadata edits into the gamelist it read; without this they are lost silently
(`Error saving gamelist.xml` in `es_log.txt`).

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
Mesa, and contains **no `libnvidia-*` file**. The launcher resolves two settings at every start
(`make retropie-debug-display` shows them) and adds the matching Compose files:

| Setting | `auto` resolves to | Adds |
|---|---|---|
| `RETROPIE_GPU` | `nvidia` when docker has the `nvidia` runtime and `nvidia-smi` works, else `mesa` | `retropie/docker-compose.nvidia.yml` |
| `RETROPIE_SESSION` | `wayland` when `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` exists, else `x11` | `retropie/docker-compose.wayland.yml` |

With **Mesa**, nothing from the host's graphics stack enters the container: `/dev/dri` is enough
for Intel and AMD, llvmpipe draws when there is no render node. With **NVIDIA**, Compose starts the
container with `runtime: nvidia` and `NVIDIA_DRIVER_CAPABILITIES=graphics,display,video,compute,utility`; the
toolkit mounts the host's GLX/EGL/Vulkan libraries, the EGL-Wayland and GBM platform plugins and
their manifests at creation time. If the injected EGL-Wayland platform does not work, startup falls
back to Xwayland for SDL/GTK applications and logs it. Dolphin always uses Xwayland. After a host
driver upgrade, recreate the container (`make retropie-stop`, then `make retropie-start`) and run
`make test`.

Details, measured toolkit behaviour and limits:
[doc/driver-agnostic/validation.md](doc/driver-agnostic/validation.md).
</details>

<details>
<summary><b>Versions, rollback and data backups</b></summary>

`:latest` is what runs. Every successful build tags the image it replaced as `:previous` and the
new one with its date and commit (`:20261018-123000-7494db3`; the newest three are kept,
`RETROPIE_KEEP_IMAGES` to change). A build that fails, is interrupted or produces the same image
leaves `:previous` where it was. If a new image misbehaves:

```bash
make images                 # versions on this machine
make rollback               # :latest <-> :previous
make stop && make start     # recreate the container on it
```

Before the first start of a different image the launcher archives the data directory without ROMs
into `backups/` (ignored by git); `make data-backup` does it by hand. To restore: stop the
container, extract the archive over the data directory. The base image is pinned by digest and
RetroPie-Setup by commit, but emulator sources and Ubuntu packages are fetched at build time:
a rebuild is not bit-for-bit reproducible, which is why the previous image is kept.
</details>

<details>
<summary><b>Keeping up to date</b></summary>

An update costs what it invalidates. Docker reuses a layer only if it and every layer before it
are unchanged, and the image is stacked: the Ubuntu base, then RetroPie-Setup with
`basic_install`, then one layer per emulator. So there are three kinds of update:

| What changed upstream | How to take it | Cost |
|---|---|---|
| An emulator on a moving branch (`master`) | `make update PKG="dolphin"` | minutes |
| RetroPie-Setup (`RETROPIE_SETUP_REF`) | bump the commit in `retropie/Dockerfile`, `make build` | hours |
| The Ubuntu base (digest in `FROM`) | replace the digest, `make build` | hours |

`make outdated` tells you which of these applies, in seconds and without building or pulling
anything:

```bash
make outdated                 # what is newer upstream than the image
make update PKG="dolphin"     # the line it suggests
```

It compares the commit each emulator was built from (RetroPie-Setup records it in the image) with
its branch upstream, lists the commits RetroPie-Setup gained and which installed modules they
touch, and checks whether the registry serves a newer base. Emulators that RetroPie-Setup pins to
a tag (RetroArch, ScummVM) are shown as pinned: `make update` would rebuild the same version, they
move only with a RetroPie-Setup bump. Cores that come with `basic_install` are not in your package
list, so `make update` refuses them: append them to `packages.local` to build them on top, or let
the next full rebuild take them. Leave the two full rebuilds for when they bring something you
want, a fix in a module you use or Ubuntu security updates, and run them overnight; the previous
image stays available for `make rollback`.
</details>

<details>
<summary><b>Portability of the image</b></summary>

RetroPie-Setup compiles with `-march=native`, so the image is optimised for the CPU that built it
and may not run on a different CPU family. Build on the machine that will run it (that is why no
image is published): the data directory is independent of the build.
</details>

<details>
<summary><b>Emulators: choosing your own set</b></summary>

The image installs `basic_install` from RetroPie-Setup (EmulationStation, RetroArch and the basic
cores) plus the packages listed in [`packages.default`](packages.default): `lr-snes9x`, `dolphin`,
`lr-flycast-dev`, `lr-mame2003`, `lr-mame2015`, `lr-mame2016`, `lr-pcsx-rearmed`, `lr-quicknes`,
`lr-parallel-n64`, `lr-mupen64plus-next`, `scummvm` and `lr-vice` (Commodore 64).

To build a different set:

```bash
make packages-choose    # checklist of common emulators by system, writes packages.local
make packages           # what the next build installs
make packages-check     # every name exists in RetroPie-Setup (seconds, no build)
make build
make update PKG=lr-vice # later: rebuild just that emulator from upstream, minutes
```

`packages.local` (ignored by git) wins over `packages.default`; you can also write it by hand,
one RetroPie-Setup package per line, `#` for comments: any package of RetroPie-Setup works, not
only those offered by the checklist ([`packages.catalog`](packages.catalog)). Each package is one
Docker layer, in the order of the list: **append new packages at the end** and only they are
built; removing or reordering a line rebuilds everything after it. A package that fails to build
does not discard the ones before it. `make wizard` asks about the selection too. The checklist
marks the cores that `basic_install` already builds on x86: listing one of them compiles it again
in its own layer, which costs build time and gains nothing.

The committed `retropie/Dockerfile` is generated from `packages.default` (the block between the
`>>> packages` markers): after editing that file run `scripts/packages.sh sync`; `make test-static`
fails if the two disagree. A `packages.local` build uses its own generated `build/Dockerfile`.
`RETROPIE_SETUP_REF` pins the RetroPie-Setup commit; bump it deliberately and rebuild. Every
system gets a default emulator (the first listed) so that EmulationStation can launch it, and
systems added by a new package appear in an existing `es_systems.cfg` by themselves. BIOS files
go in `data/BIOS/` as the RetroPie documentation of each system says.

**Updating emulators without a rebuild.** RetroPie-Setup builds each core from its upstream source
at build time, so updating one means rebuilding only that layer. `make update PKG="lr-vice dolphin"`
records the packages with a timestamp in `packages.update` (ignored by git) and builds: they are
rebuilt on top of the image while everything else comes from the cache, so it takes minutes.
`make outdated` shows which packages have something new (see *Keeping up to date*).
Later builds keep the updated layers. The image grows by the size of the old copies until a fresh
build (`make update-clear`, then `docker build --no-cache` or a bumped `RETROPIE_SETUP_REF`).
`/etc/retropie-docker/updates` in the image lists what was updated and when. Updating packages
from the RetroPie menu inside the running container is lost when the container is recreated.

The **RetroPie menu inside EmulationStation** is mostly terminal programs (RetroPie-Setup, config
editor, themes, runcommand, file manager, show IP). In the container they open in a full-screen
xterm on your desktop (`retropie-menu-launch`; the entrypoint switches the stock command of an
existing `es_systems.cfg` to it, a customised command is left alone); EmulationStation comes back
when you leave them. The keyboard always works there; the controller only if your kernel still
allows the terminal injection RetroPie's joy2key uses (`dev.tty.legacy_tiocsti`). Packages
installed or updated from RetroPie-Setup live in the container layer and are lost when it is
recreated: to keep an emulator, add it to your package list, to update one use `make update`.
</details>

<details>
<summary><b>Verification</b></summary>

- `make test` runs disposable containers (never your data): the image contains no driver files,
  the driver version inside the container equals the host's, the injected graphics manifests
  resolve, Wayland EGL, Xwayland GLX and Vulkan report NVIDIA, and defaults, user mapping and
  persistence work across container recreation. It also requires three deliberate failures to be
  rejected: compute-only capabilities, no NVIDIA runtime, a fake expected driver version.
  In Mesa mode it checks instead that the image's Mesa renders and that the driver check reports
  Mesa, never NVIDIA.
- `make test-desktop` checks the PulseAudio connection and controller device access.
- `make doctor` checks the host before build or start (Docker and Compose, which GPU mode and
  whether it accelerates, the NVIDIA runtime and toolkit when used, Wayland/Xwayland or X11, audio,
  D-Bus, devices, data ownership, free space).
- `make test-static` runs what CI runs: syntax, shellcheck, the Dockerfile installs no driver and
  pins RetroPie-Setup, its package block matches `packages.default`, a `packages.local` drives
  its own Dockerfile, bad or unknown package names are refused, retired targets explain
  themselves, a failed or unchanged build leaves `:previous` alone, `make outdated` finds the one
  package behind its upstream branch in a fake image, Compose renders, and in Mesa/X11 mode carries nothing NVIDIA and no Wayland socket. The GitHub workflow
  also builds the diagnostics stage and checks that without a GPU the image says so (exit 2),
  and once a month (or on demand) builds the whole image and runs the data tests. GPU tests need
  a real machine: CI has no NVIDIA card and no Wayland desktop.
- `make check-public` scans the whole git history for game data, secrets and private hosts,
  after proving on a throwaway repository that an injected BIOS is rejected.
- [doc/driver-agnostic/manual-test.md](doc/driver-agnostic/manual-test.md): the gameplay
  acceptance test (one SNES game, one GameCube game, sound, controller).
</details>

<details>
<summary><b>Repository layout</b></summary>

```
retropie/Dockerfile             graphics, diagnostics and RetroPie stages (one image)
packages.default                emulators in the image (packages.local overrides, ignored by git)
packages.catalog                what make packages-choose offers
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
