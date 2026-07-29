#!/usr/bin/env bats
#
# Behavioural coverage for md2x's non-zero exit paths: a missing required external
# binary (exit 2, naming the binary -- docs/md2x-spec.md's 'General features' and
# 'Exit behavior') and an input path that is neither a file nor a directory (non-zero,
# naming the path -- 'Exit behavior'). 'harness-smoke.bats' exercises the missing-
# 'pandoc' case as part of proving the harness's 'md2x_path_without' helper works;
# these cases are the dedicated behavioural coverage for the CLI's own contract.

load '../helpers/common'

setup() {
  md2x_setup
}

teardown() {
  md2x_teardown
}

@test "a PATH missing 'pandoc' exits 2 and names 'pandoc'" {
  md2x_write_doc 'report.md'
  md2x_path_without pandoc

  md2x_run report.md

  assert_failure 2
  assert_stderr_contains "Required executable 'pandoc' not found"
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

@test "a PATH missing 'gs' exits 2 and names 'gs'" {
  md2x_write_doc 'report.md'
  md2x_path_without gs

  md2x_run report.md

  assert_failure 2
  assert_stderr_contains "Required executable 'gs' not found"
  refute_stub_called gs
  refute_stub_called pandoc
  assert_file_not_exists './report.pdf'
}

@test "an input path that is neither a file nor a directory exits non-zero and names the path" {
  md2x_run no-such-file.md

  assert_failure
  assert_stderr_contains "'no-such-file.md' is neither a file nor a directory"
}
