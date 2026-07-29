SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:
.PHONY: all clean lint lint-fix qa smoke-test test test-cli test-node

NPM_BIN:=npm exec
CATALYST_SCRIPTS:=$(NPM_BIN) catalyst-scripts
BASH_ROLLUP:=$(NPM_BIN) bash-rollup
# '--' so npm hands the runner's own flags through instead of parsing them itself.
BATS:=$(NPM_BIN) -- bats

NODE_SRC=src/node
NODE_FILES:=$(shell find $(NODE_SRC) -name "*.js" -not -path "*/test/*" -not -name "*.test.js")
# NODE_TEST_SRC_FILES:=$(shell find $(NODE_SRC) -name "*.js")
# NODE_TEST_BUILT_FILES=$(patsubst $(NODE_SRC)/%, test-staging/%, $(NODE_TEST_SRC_FILES))
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
	JS_SRC=$(NODE_SRC) $(CATALYST_SCRIPTS) build

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
	JS_SRC=$(NODE_SRC) $(CATALYST_SCRIPTS) pretest
	JS_SRC=$(NODE_SRC) $(CATALYST_SCRIPTS) test

# smoke test recipes (interactive; opt in)
$(SMOKE_TEST_OUT): $(SMOKE_TEST_SRC) $(CLI_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

smoke-test: all $(SMOKE_TEST_OUT)
	rm -f ./test-out/tiny-doc.*
	$(SMOKE_TEST_OUT)

# lint rules
lint:
	JS_LINT_TARGET=$(NODE_SRC) $(CATALYST_SCRIPTS) lint

lint-fix:
	JS_LINT_TARGET=$(NODE_SRC) $(CATALYST_SCRIPTS) lint-fix

qa: test lint
	
clean:
	rm -rf $(BUILD_TARGETS)
