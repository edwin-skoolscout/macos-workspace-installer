SHELL := /bin/bash
SH_FILES := $(shell find . -type f -name '*.sh' -not -path './.git/*' -not -path './tests/tmp/*' | sort)

.PHONY: lint test list dry-run smoke-linux

lint:
	shellcheck -x $(SH_FILES)

test:
	bats --recursive tests

## Run the real step list / dry-run with macOS's stock bash 3.2 to catch bashisms
list:
	/bin/bash ./install.sh --list

dry-run:
	/bin/bash ./install.sh --dry-run --yes

smoke-linux:
	./tests/smoke-linux.sh
