# Get the script name dynamically based on sole script in repo
SCRIPT_NAME := $(wildcard *.sh)
INSTALL_NAME := $(basename $(SCRIPT_NAME))

build:
	bash $(SCRIPT_NAME) install

rebuild: build

delete:
	bash $(SCRIPT_NAME) uninstall

# Tests (plain bash, run through ucli.sh's own #!/bin/bash line)
test:
	tests/run.sh

# shellcheck: default severity, every finding blocks (version pinned in CI)
lint:
	shellcheck ucli.sh tests/*.sh

.PHONY: build rebuild delete test lint
