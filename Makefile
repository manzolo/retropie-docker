SHELL := /bin/bash
.DEFAULT_GOAL := help
.PHONY: start stop enter logs help doctor images rollback data-backup packages packages-choose packages-check outdated update update-clear build build-stack retropie-build wizard test test-desktop test-static check-public check-nvidia check-env status retropie-start retropie-stop retropie-enter retropie-logs retropie-debug-display retropie-push
# Document public targets with ## and sections with ##@; the first target is shown.
help: ## Show this help
	@color=0; \
	if [ -t 1 ] && [ "$${TERM:-dumb}" != dumb ] && [ -z "$${NO_COLOR:-}" ]; then color=1; fi; \
	awk -v color="$$color" 'BEGIN { \
	    if (color) { bold = sprintf("%c[1m", 27); cyan = sprintf("%c[36m", 27); reset = sprintf("%c[0m", 27) } \
	    printf "\n%sRetroPie Docker%s\n", bold, reset; \
	    print "Usage: make <target> [VARIABLE=value]"; \
	} \
	/^##@ / { printf "\n%s%s%s\n", bold, substr($$0, 5), reset; next } \
	/^[a-zA-Z0-9_-][^:]*:.*## / { \
	    split($$0, words, /[ :]+/); \
	    description = $$0; sub(/^.*## /, "", description); \
	    printf "  %s%-30s%s %s\n", cyan, "make " words[1], reset, description; \
	} \
	END { \
	    printf "\n%sExamples%s\n", bold, reset; \
	    print "  First run:        make doctor && make wizard"; \
	    print "  Manual setup:     make packages-choose && make build && make start"; \
	    print "  Update emulators: make outdated, then make update PKG=\"lr-vice dolphin\""; \
	    print "\nTip: set NO_COLOR=1 to disable colors.\n"; \
	}' $(MAKEFILE_LIST)

##@ Setup and build
doctor: ## Check what the host must provide (Docker, GPU, Wayland or X11, audio, devices)
	@./scripts/doctor.sh
wizard: ## Configure, build and start interactively
	@BUILD='$(BUILD)' ./scripts/wizard.sh
build build-stack retropie-build: ## Build the driver-agnostic :latest image (can take hours)
	@./scripts/retropie.sh build

##@ Run (also available as retropie-start/stop/enter/logs)
start: retropie-start ## Start EmulationStation
stop: retropie-stop ## Stop the container
enter: retropie-enter ## Open a shell in the running container
logs: retropie-logs ## Follow container logs (Ctrl-C to leave)

##@ Emulators
packages: ## List packages for the next build (local or default selection)
	@./scripts/packages.sh list
packages-choose: ## Choose emulators interactively; write packages.local
	@./scripts/packages.sh choose
packages-check: ## Validate names against the pinned RetroPie-Setup
	@./scripts/packages.sh check
outdated: ## What changed upstream since the build: emulators, RetroPie-Setup, base (builds nothing)
	@./scripts/outdated.sh
update: ## Rebuild selected packages from upstream; requires PKG="a b"
	@test -n '$(PKG)' || { echo 'Usage: make update PKG="lr-vice dolphin"'; exit 1; }
	@./scripts/packages.sh update $(PKG)
	@./scripts/retropie.sh build
update-clear: ## Clear packages.update; takes effect on the next build
	@./scripts/packages.sh update-clear

##@ Tests and diagnostics
test: ## Check the image, the GPU (NVIDIA injection or Mesa) and data persistence (needs Docker)
	@./scripts/test-driver-agnostic.sh
	@./scripts/test-data.sh
test-desktop: ## Check audio connection and controller permissions (needs hardware)
	@./scripts/test-desktop.sh
test-static: ## Run syntax, shellcheck, Dockerfile and Compose checks (CI)
	@./scripts/test-static.sh
check-public: ## Scan git history for game data, secrets and private hosts
	@./scripts/check-public.sh --self-test
	@./scripts/check-public.sh
check-nvidia: ## Diagnose runtime graphics
	@./scripts/check-nvidia.sh
check-env: ## Print the resolved Compose configuration
	@./scripts/retropie.sh config
retropie-debug-display: ## Show detected display settings

##@ Images
status: ## List current and legacy images without removing them
	@docker image ls --filter reference='*/retropie:*' --filter reference='*/ubuntu-nvidia:*'
images: ## List image versions on this machine (latest, previous, dated)
	@./scripts/images.sh list
rollback: ## Go back to the image before the last build (then make stop && make start)
	@./scripts/images.sh rollback
data-backup: ## Archive the data directory without ROMs into backups/
	@./scripts/data-backup.sh
retropie-push: ## Push the configured image to its registry

# Shared implementation for the retropie-* runtime commands above.
retropie-start retropie-stop retropie-enter retropie-logs retropie-debug-display retropie-push:
	@./scripts/retropie.sh $(@:retropie-%=%)
# Keep obsolete commands discoverable without building/pushing/deleting old images.
# GNU make patterns allow only one wildcard: catch every old name explicitly by prefix.
base-build-nvidia-% base-push-nvidia-% retropie-build-nvidia-% retropie-push-nvidia-% build-stack-nvidia-% push-stack-nvidia-% retropie-start-nvidia-% retropie-enter-nvidia-% build-nvidia-% push-nvidia-% start-nvidia-% enter-nvidia-%:
	@echo '$@ is retired: NVIDIA libraries now come from the host runtime. Use make build / retropie-start / retropie-push (:latest).'
base-build base-push base-clean base-build-all base-push-all retropie-build-all retropie-push-all retropie-clean build-all-stack push-all-stack clean-all build-all push-all:
	@echo '$@ is retired. There is one image, :latest. Use make build or make retropie-push. Legacy images are left untouched.'
