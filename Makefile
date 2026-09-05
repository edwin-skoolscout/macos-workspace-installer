SHELL := /bin/bash
SH_FILES := $(shell find . -type f -name '*.sh' -not -path './.git/*' -not -path './node_modules/*' -not -path './tests/tmp/*' | sort)

.PHONY: lint test check list dry-run smoke-linux

lint:
	shellcheck -x $(SH_FILES)

## The TypeScript tools (tools/*) need their dependencies once
node_modules: package.json package-lock.json
	npm ci --no-fund --no-audit
	@touch node_modules

## bats for the shell, node --test for tools/*
test: node_modules
	bats --recursive tests
	npm test

## Type-check tools/*
check: node_modules
	npm run check

## Run the real step list / dry-run with macOS's stock bash 3.2 to catch bashisms
list:
	/bin/bash ./install.sh --list

dry-run:
	/bin/bash ./install.sh --dry-run --yes

smoke-linux:
	./tests/smoke-linux.sh
