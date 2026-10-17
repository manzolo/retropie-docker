SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: start stop enter logs help packages packages-choose packages-check build build-stack retropie-build wizard test test-desktop test-static check-public check-nvidia check-env status retropie-start retropie-stop retropie-enter retropie-logs retropie-debug-display retropie-push
help:
	@echo 'make build / retropie-build   Build the single driver-agnostic :latest image'
	@echo 'make wizard                  Configure, build and start interactively'
	@echo 'make packages                List the emulators the next build installs (packages.local or packages.default)'
	@echo 'make packages-choose         Pick emulators from a checklist (writes packages.local)'
	@echo 'make packages-check          Validate package names against the pinned RetroPie-Setup'
	@echo 'make retropie-start/stop/enter/logs'
	@echo 'make test                    Verify clean image, GPU injection and deliberate failures'
	@echo 'make test-static             Syntax, shellcheck, Dockerfile and compose checks (what CI runs)'
	@echo 'make check-nvidia            Diagnose runtime graphics'
	@echo 'make check-public            Refuse game data, secrets or private hosts anywhere in git history'
	@echo 'make status                  List current and legacy images (never remove them)'
build build-stack retropie-build:
	@./scripts/retropie.sh build
packages:
	@./scripts/packages.sh list
packages-choose:
	@./scripts/packages.sh choose
packages-check:
	@./scripts/packages.sh check
wizard:
	@BUILD='$(BUILD)' ./scripts/wizard.sh
test:
	@./scripts/test-driver-agnostic.sh
	@./scripts/test-data.sh
test-desktop:
	@./scripts/test-desktop.sh
test-static:
	@./scripts/test-static.sh
check-public:
	@./scripts/check-public.sh --self-test
	@./scripts/check-public.sh
check-nvidia:
	@./scripts/check-nvidia.sh
check-env:
	@./scripts/retropie.sh config
status:
	@docker image ls --filter reference='*/retropie:*' --filter reference='*/ubuntu-nvidia:*'
retropie-start retropie-stop retropie-enter retropie-logs retropie-debug-display retropie-push:
	@./scripts/retropie.sh $(@:retropie-%=%)
# Keep obsolete commands discoverable without building/pushing/deleting old images.
# GNU make patterns allow only one wildcard: catch every old name explicitly by prefix.
base-build-nvidia-% base-push-nvidia-% retropie-build-nvidia-% retropie-push-nvidia-% build-stack-nvidia-% push-stack-nvidia-% retropie-start-nvidia-% retropie-enter-nvidia-% build-nvidia-% push-nvidia-% start-nvidia-% enter-nvidia-%:
	@echo '$@ is retired: NVIDIA libraries now come from the host runtime. Use make build / retropie-start / retropie-push (:latest).'
base-build base-push base-clean base-build-all base-push-all retropie-build-all retropie-push-all retropie-clean build-all-stack push-all-stack clean-all build-all push-all:
	@echo '$@ is retired. There is one image, :latest. Use make build or make retropie-push. Legacy images are left untouched.'
start: retropie-start
stop: retropie-stop
enter: retropie-enter
logs: retropie-logs
