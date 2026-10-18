# Shared graphics stage, also usable for fast runtime diagnostics (no published tag).
# Base pinned by digest: the ubuntu:24.04 tag moves; bump the digest deliberately (docker pull, inspect).
FROM ubuntu:24.04@sha256:66460d557b25769b102175144d538d88219c077c678a49af4afca6fbfc1b5252 AS graphics
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates sudo tini gosu locales tzdata git python3 \
    libglvnd0 libgl1 libegl1 libgles2 libvulkan1 libgbm1 \
    libgl1-mesa-dri libegl-mesa0 mesa-vulkan-drivers mesa-utils vulkan-tools \
    libwayland-client0 libwayland-server0 libwayland-egl1 wayland-protocols \
    libxcb-dri3-0 libxcb-present0 libxcb-xfixes0 libxcb-sync1 libx11-xcb1 \
    libdecor-0-plugin-1-cairo qt6-wayland pulseaudio-utils libnotify-bin \
    xauth procps joystick && \
    rm -rf /var/lib/apt/lists/*

FROM graphics AS diagnostics
COPY --chmod=755 scripts/gpu-check.sh /usr/local/bin/gpu-check

# One final image. Driver libraries are supplied exclusively at container creation.
FROM graphics AS retropie
ARG DEBIAN_FRONTEND=noninteractive
ARG CONTAINER_USERNAME=manzolo
ARG CONTAINER_UID=1000
ARG CONTAINER_GID=1000
ENV CONTAINER_USERNAME=${CONTAINER_USERNAME} \
    HOME=/home/${CONTAINER_USERNAME} \
    XDG_CONFIG_HOME=/home/${CONTAINER_USERNAME}/.config \
    XDG_DATA_HOME=/home/${CONTAINER_USERNAME}/.local/share \
    XDG_CACHE_HOME=/home/${CONTAINER_USERNAME}/.cache \
    RETROPIE_LOG=/data/retropie-docker.log \
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
LABEL org.opencontainers.image.source="https://github.com/manzolo/retropie-docker" \
      org.opencontainers.image.description="RetroPie with runtime-injected NVIDIA graphics and Mesa fallback"
RUN userdel -r ubuntu && \
    groupadd --gid ${CONTAINER_GID} ${CONTAINER_USERNAME} && \
    useradd -m -s /bin/bash -u ${CONTAINER_UID} -g ${CONTAINER_GID} \
        -G video,audio ${CONTAINER_USERNAME} && \
    locale-gen en_US.UTF-8 && \
    apt-get update && apt-get install -y --no-install-recommends \
        iproute2 gpg-agent build-essential python3-pip python3-dev libxml2-dev libxslt1-dev \
        zlib1g-dev libsdl2-dev libasound2-dev libudev-dev libusb-1.0-0-dev && \
    rm -rf /var/lib/apt/lists/* && \
    echo "${CONTAINER_USERNAME} ALL=(ALL) NOPASSWD:SETENV: /home/${CONTAINER_USERNAME}/RetroPie-Setup/retropie_packages.sh, /home/${CONTAINER_USERNAME}/RetroPie-Setup/retropie_setup.sh" \
        > /etc/sudoers.d/retropie && chmod 440 /etc/sudoers.d/retropie
USER ${CONTAINER_USERNAME}
WORKDIR /home/${CONTAINER_USERNAME}
# RetroPie-Setup is pinned to a known-good commit: its master moves and can break the build
# (2026-10: lr-flycast's stale gcc14 patch). Bump RETROPIE_SETUP_REF deliberately, then rebuild.
ARG RETROPIE_SETUP_REF=15b002c616204e370c67729f4e052a34d761efee
RUN git init -q RetroPie-Setup && cd RetroPie-Setup && \
    git remote add origin https://github.com/RetroPie/RetroPie-Setup.git && \
    git fetch -q --depth=1 origin "${RETROPIE_SETUP_REF}" && \
    git checkout -q FETCH_HEAD && \
    sudo ./retropie_packages.sh setup basic_install
# >>> packages (generated from packages.default by scripts/packages.sh: edit that file, not this block)
# One layer per package: a package that fails to build does not discard the ones already built.
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-snes9x
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh dolphin
# lr-flycast-dev: upstream flyinghead/flycast; lr-flycast (the libretro fork) no longer builds (RetroPie-Setup #4236)
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-flycast-dev
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-mame2003
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-mame2015
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-mame2016
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-pcsx-rearmed
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-quicknes
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-parallel-n64
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-mupen64plus-next
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh scummvm
# lr-vice: Commodore 64, 128, VIC-20, Plus/4: not part of basic_install on x86
RUN cd RetroPie-Setup && sudo ./retropie_packages.sh lr-vice
USER root
RUN mkdir -p /etc/retropie-docker && printf '%s\n' lr-snes9x dolphin lr-flycast-dev lr-mame2003 lr-mame2015 lr-mame2016 lr-pcsx-rearmed lr-quicknes lr-parallel-n64 lr-mupen64plus-next scummvm lr-vice > /etc/retropie-docker/packages
# <<< packages

USER root
COPY --chmod=755 scripts/prepare-data.sh /usr/local/bin/prepare-data
RUN /usr/local/bin/prepare-data && \
    test -x /usr/bin/emulationstation && \
    for p in $(cat /etc/retropie-docker/packages); do \
        ls -d /opt/retropie/*/"$p" >/dev/null 2>&1 || { echo "package $p did not install"; exit 1; }; \
    done && \
    test -z "$(find /usr /opt -name 'libnvidia-*' -o -name nvidia-smi)"
# The RetroPie menu's terminal programs open in a visible xterm (retropie-menu-launch); kept after
# the packages so adding it does not rebuild them.
RUN apt-get update && apt-get install -y --no-install-recommends xterm fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/*
COPY --chmod=755 retropie/retropie-menu-launch.sh /usr/local/bin/retropie-menu-launch
RUN f=/usr/local/share/retropie-defaults/emulationstation/es_systems.cfg && \
    sed -i 's|<command>sudo /home/[^/]*/RetroPie-Setup/retropie_packages.sh retropiemenu launch %ROM% *</command>|<command>retropie-menu-launch %ROM%</command>|' "$f" && \
    grep -q '<command>retropie-menu-launch %ROM%</command>' "$f"
COPY --from=diagnostics /usr/local/bin/gpu-check /usr/local/bin/gpu-check
COPY --chmod=755 retropie/retropie-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY --chmod=755 retropie/healthcheck.sh /usr/local/bin/healthcheck.sh
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["/usr/bin/emulationstation"]
