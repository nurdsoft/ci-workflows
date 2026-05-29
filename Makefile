.PHONY: setup

## setup : Configure Git hooks from .githooks/
setup:
	@echo "Configuring Git hooks..."
	@git config core.hooksPath .githooks
	@echo "Done. Hooks active."
