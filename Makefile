SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:
.PHONY: all clean lint lint-fix qa smoke-test test test-cli test-node test-pack

# Dev tools resolve only to the lockfile-pinned binaries installed by 'bun install'. They are
# deliberately NOT run through 'bunx', which would fetch an unpinned latest version from the
# registry when node_modules is missing; with node_modules absent these fail closed instead.
BIN_DIR:=node_modules/.bin
BASH_ROLLUP:=$(BIN_DIR)/bash-rollup
BATS:=$(BIN_DIR)/bats
ESLINT:=$(BIN_DIR)/eslint

# Missing-tool guard: an order-only prerequisite on each dev tool a recipe runs. When the tool
# is absent this fails closed (non-zero, no registry fetch) with a message naming the fix.
$(BIN_DIR)/%:
	@echo "error: $@ not found; run 'bun install' to install the dev tools" >&2; exit 1

NODE_SRC=src/node
NODE_FILES:=$(shell find $(NODE_SRC) -name "*.js" -not -path "*/test/*" -not -name "*.test.js")
NODE_DIST_ESM:=dist/md2x.mjs
NODE_DIST_CJS:=dist/md2x.cjs
NODE_DIST_TYPES:=dist/index.d.ts
NODE_DIST:=$(NODE_DIST_ESM) $(NODE_DIST_CJS) $(NODE_DIST_TYPES)

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
# Dual build. The .mjs/.cjs extensions make each format unambiguous to Node regardless of the package
# 'type'. Sourcemaps are omitted: they inflate the published tarball and the bundle is a thin wrapper.
$(NODE_DIST_ESM): package.json $(NODE_FILES)
	mkdir -p $(dir $@)
	bun build $(NODE_SRC)/index.js --target=node --format=esm --packages=external --outfile=$@

$(NODE_DIST_CJS): package.json $(NODE_FILES)
	mkdir -p $(dir $@)
	bun build $(NODE_SRC)/index.js --target=node --format=cjs --packages=external --define import.meta.dirname=module.path --define import.meta.url=undefined --outfile=$@

# The hand-written type declarations ship as-is.
$(NODE_DIST_TYPES): $(NODE_SRC)/index.d.ts
	mkdir -p $(dir $@)
	cp $< $@

# The package.json version is injected into the rolled-up script as a literal, replacing the
# '@MD2X_VERSION@' placeholder in src/cli/md2x.sh. It is read without jq or node, and the
# build fails rather than embed an empty or odd version. package.json is a prerequisite so a
# version bump rebuilds bin/md2x.
$(CLI_BIN): $(CLI_SRC) package.json | $(BASH_ROLLUP)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@
	@v="$$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)"; \
	case "$$v" in ''|*[!0-9A-Za-z.+-]*) echo "error: could not read a valid version from package.json (got '$$v')" >&2; exit 1;; esac; \
	grep -q '@MD2X_VERSION@' $@ || { echo "error: version placeholder missing from $@" >&2; exit 1; }; \
	sed "s/@MD2X_VERSION@/$$v/g" $@ > $@.tmp && cat $@.tmp > $@ && rm -f $@.tmp

# test recipes
#
# 'test' is non-interactive and self-contained: the CLI cases run the built bin/md2x
# against stub pandoc/gs/pdftk executables, so no working Pandoc PDF pipeline is
# needed. 'make smoke-test' is the opt-in interactive complement.
test: test-cli test-node

# The bats cases exercise the built CLI, so they depend on the build.
test-cli: all $(CLI_TEST_FILES) | $(BATS)
	$(BATS) --print-output-on-failure $(CLI_BATS_DIR)

test-node:
	bun test ./$(NODE_SRC) --coverage --coverage-reporter=text --coverage-reporter=lcov --coverage-dir=coverage

# Release-time check (not part of 'qa': it runs npm pack/install and a TypeScript compile, which
# can need the network). Packs the tarball and proves ESM import, CJS require, and the types.
test-pack: all
	bash scripts/test-pack.sh

# smoke test recipes (interactive; opt in)
$(SMOKE_TEST_OUT): $(SMOKE_TEST_SRC) $(CLI_SRC) | $(BASH_ROLLUP)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

smoke-test: all $(SMOKE_TEST_OUT)
	rm -f ./test-out/tiny-doc.*
	$(SMOKE_TEST_OUT)

# lint rules
lint: | $(ESLINT)
	$(ESLINT) .

lint-fix: | $(ESLINT)
	$(ESLINT) --fix .

qa: test lint
	
clean:
	rm -rf $(BUILD_TARGETS)
