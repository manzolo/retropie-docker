# Compatibility entry point; all configuration is resolved from the repository root.
.DEFAULT_GOAL := help
%:
	@$(MAKE) -C .. $@
build:
	@$(MAKE) -C .. build
debug-display:
	@$(MAKE) -C .. retropie-debug-display
registry_push:
	@$(MAKE) -C .. retropie-push
