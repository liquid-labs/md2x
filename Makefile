SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:
.PHONY: all clean lint lint-fix qa test

NPM_BIN:=npm exec
CATALYST_SCRIPTS:=$(NPM_BIN) catalyst-scripts
BASH_ROLLUP:=$(NPM_BIN) bash-rollup

NODE_SRC=src/node
NODE_FILES:=$(shell find $(NODE_SRC) -name "*.js" -not -path "*/test/*" -not -name "*.test.js")
# NODE_TEST_SRC_FILES:=$(shell find $(NODE_SRC) -name "*.js")
# NODE_TEST_BUILT_FILES=$(patsubst $(NODE_SRC)/%, test-staging/%, $(NODE_TEST_SRC_FILES))
NODE_DIST:=dist/md2x.js

CLI_LIB_SRC:=$(shell find src/cli/lib -type f)
CLI_SRC:=src/cli/md2x.sh $(CLI_LIB_SRC)
CLI_BIN:=bin/md2x
	
CLI_TEST_SRC:=./src/cli/test/test.sh
CLI_TEST_OUT:=./test-out/test.sh
CLI_TEST_DATA:=$(shell find src/cli/test -type f)
	
BUILD_TARGETS:=$(NODE_DIST) $(CLI_BIN)
	
all: $(BUILD_TARGETS)

# build recipes
$(NODE_DIST): package.json $(NODE_FILES)
	mkdir -p $(dir $@)
	JS_SRC=$(NODE_SRC) $(CATALYST_SCRIPTS) build

$(CLI_BIN): $(CLI_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

# test receipes
$(CLI_TEST_OUT): $(CLI_TEST_SRC) $(CLI_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

test: all $(CLI_TEST_OUT) $(CLI_TEST_DATA)
	mkdir -p $(dir $(CLI_TEST_OUT))
	rm -f ./test-out/tiny-doc.*
	$(CLI_TEST_OUT)

# lint rules
lint:
	JS_SRC=$(NODE_SRC) $(CATALYST_SCRIPTS) lint

lint-fix:
	JS_SRC=$(NODE_SRC) $(CATALYST_SCRIPTS) lint-fix

qa: test lint
	
clean:
	rm -rf $(BUILD_TARGETS)
