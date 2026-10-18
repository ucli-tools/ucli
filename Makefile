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

# shellcheck: only errors block
lint:
	shellcheck -S error ucli.sh tests/*.sh

.PHONY: build rebuild delete test lint
