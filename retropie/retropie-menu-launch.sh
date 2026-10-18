#!/bin/bash
# EmulationStation's RetroPie menu entries (RetroPie-Setup, configuration editor, file manager, ...)
# are terminal programs: in the container their terminal is invisible and EmulationStation waits for
# them forever. Open them in a full-screen xterm on the desktop instead; without a display, run as
# RetroPie does. The keyboard always works; the controller only where the kernel allows joy2key's
# TIOCSTI (dev.tty.legacy_tiocsti).
cmd=(sudo "/home/$USER/RetroPie-Setup/retropie_packages.sh" retropiemenu launch "$@")
if [[ -n ${DISPLAY:-} ]] && command -v xterm >/dev/null; then
    exec xterm -fullscreen -title RetroPie -fa 'DejaVu Sans Mono' -fs 14 -bg black -fg white -e "${cmd[@]}"
fi
exec "${cmd[@]}"
