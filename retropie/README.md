# RetroPie image

Build from the repository root with `make build`; the context must be the root,
not this directory. The compatibility Makefile forwards common commands there.
See the [main README](../README.md) for GPU injection, data paths and verification.

The launcher explicitly loads `docker-compose.yml`, adds `docker-compose.roms.yml`
when external ROMs are configured, and then an optional local
`docker-compose.override.yml`. Use service name `retropie-service` in overrides.
