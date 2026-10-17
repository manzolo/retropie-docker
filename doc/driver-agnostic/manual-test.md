# Manual acceptance test

Use legally obtained test ROMs, a connected controller and the Wayland desktop.
Automated GPU probes do not establish gameplay, audible sound or working controls.

1. Set `RETROPIE_DATA_DIR` to the migrated/new data folder, optionally set
   `RETROPIE_ROMS_DIR`, and run `make test`. Expect all GPU assertions and all
   deliberate-failure checks to pass.
2. Put a known SNES ROM in `roms/snes` and a GameCube ROM in `roms/gc` (or use your
   external collection). Run `make retropie-start`, then `make retropie-logs`.
   Expect EmulationStation on the desktop; configure the controller if prompted.
3. Launch the SNES ROM using **lr-snes9x**. Confirm picture, stereo sound,
   directional controls and buttons. Save in-game and create a save state. Exit,
   stop/start the container, reload both, and check files under `saves`/`states`.
4. Launch the GameCube ROM using **dolphin-gui**. Confirm the Xwayland window,
   picture, sound and mapped controller. Save to the virtual memory card, exit,
   restart the container and reload it. Dolphin data must persist in `configs/gc`.
5. Run `make retropie-stop`. Keep game names, image ID (`docker image inspect
   manzolo/retropie:latest --format '{{.Id}}'`) and observed results with your notes.
   After a future host driver upgrade, repeat `make test` and these two games
   using the same image ID; that is the direct cross-upgrade acceptance test.
