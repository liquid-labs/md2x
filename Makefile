SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:
.PHONY: all clean lint lint-fix qa smoke-test test test-cli test-node

# Dev tools resolve only to the lockfile-pinned binaries installed by 'bun install'. They are
# deliberately NOT run through 'bunx', which would fetch an unpinned latest version from the
# registry when node_modules is missing; with node_modules absent these fail closed instead.
BIN_DIR:=node_modules/.bin
BASH_ROLLUP:=$(BIN_DIR)/bash-rollup
BATS:=$(BIN_DIR)/bats
ESLINT:=$(BIN_DIR)/eslint

NODE_SRC=src/node
NODE_FILES:=$(shell find $(NODE_SRC) -name "*.js" -not -path "*/test/*" -not -name "*.test.js")
NODE_DIST:=dist/md2x.js

CLI_LIB_SRC:=$(shell find src/cli/lib -type f)
CLI_SRC:=src/cli/md2x.sh $(CLI_LIB_SRC)
CLI_BIN:=bin/md2x
	
CLI_TEST_DIR:=src/cli/test
CLI_BATS_DIR:=$(CLI_TEST_DIR)/bats
CLI_TEST_FILES:=$(shell find $(CLI_TEST_DIR) -type f)

# The interactive, macOS-only visual check. Opt in via 'make smoke-test'; nothing in
# the default 'test' path may depend on it.
SMOKE_TEST_SRC:=./$(CLI_TEST_DIR)/manual/visual-smoke-test.sh
SMOKE_TEST_OUT:=./test-out/visual-smoke-test.sh

BUILD_TARGETS:=$(NODE_DIST) $(CLI_BIN)
	
all: $(BUILD_TARGETS)

# build recipes
$(NODE_DIST): package.json $(NODE_FILES)
	mkdir -p $(dir $@)
	bun build $(NODE_SRC)/index.js --target=node --format=cjs --packages=external --sourcemap=inline --outfile=$@

$(CLI_BIN): $(CLI_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

# test recipes
#
# 'test' is non-interactive and self-contained: the CLI cases run the built bin/md2x
# against stub pandoc/gs/pdftk executables, so no working Pandoc PDF pipeline is
# needed. 'make smoke-test' is the opt-in interactive complement.
test: test-cli test-node

# The bats cases exercise the built CLI, so they depend on the build.
test-cli: all $(CLI_TEST_FILES)
	$(BATS) --print-output-on-failure $(CLI_BATS_DIR)

test-node:
	bun test ./$(NODE_SRC) --coverage --coverage-reporter=text --coverage-reporter=lcov --coverage-dir=coverage

# smoke test recipes (interactive; opt in)
$(SMOKE_TEST_OUT): $(SMOKE_TEST_SRC) $(CLI_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

smoke-test: all $(SMOKE_TEST_OUT)
	rm -f ./test-out/tiny-doc.*
	$(SMOKE_TEST_OUT)

# lint rules
lint:
	$(ESLINT) $(NODE_SRC)

lint-fix:
	$(ESLINT) --fix $(NODE_SRC)

qa: test lint
	
clean:
	rm -rf $(BUILD_TARGETS)
