SHELL=/bin/bash -o pipefail
.DELETE_ON_ERROR:
.PHONY: all clean qa test

NPM_BIN:=$(shell npm bin)
CATALYST_SCRIPTS:=$(NPM_BIN)/catalyst-scripts
BASH_ROLLUP:=$(NPM_BIN)/bash-rollup

TEST_SRC:=./test/test.sh
TEST_OUT:=./test-out/test.sh
TEST_DATA:=$(shell find src/md2x/test -type f)

MD2X_LIB_SRC:=$(shell find src/md2x/lib -type f)
MD2X_SRC:=src/md2x/md2x.sh $(MD2X_LIB_SRC)
MD2X_BIN:=bin/md2x
	
BUILD_TARGETS:=$(MD2X_BIN)
	
all: $(BUILD_TARGETS)

test: all $(TEST_OUT) $(TEST_DATA)
	mkdir -p $(dir $(TEST_OUT))
	rm -f ./test-out/tiny-doc.*
	$(TEST_OUT)
	
qa: test
	
clean:
	rm -rf $(BUILD_TARGETS)

$(MD2X_BIN): $(MD2X_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@

$(TEST_OUT): $(TEST_SRC) $(MD2X_SRC)
	mkdir -p $(dir $@)
	$(BASH_ROLLUP) $< $@
