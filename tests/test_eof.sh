#!/bin/bash
# The menu must not loop when stdin is closed or not a terminal (hotfix 4f28929).
. "$(dirname "$0")/helpers.sh"

lines_of() { wc -l < "$SB/out" | tr -d ' '; }

t_eof_empty_pipe() {
  run -i ''
  assert_rc 2
  [[ "$(lines_of)" -lt 50 ]] || fail "too many output lines: $(lines_of)"
  assert_out_has "UCLI - Universal Command Line Interface Tool"
}

t_eof_dev_null() {
  run
  assert_rc 2
  [[ "$(lines_of)" -lt 50 ]] || fail "too many output lines: $(lines_of)"
  assert_out_has "Commands:"
}

t_eof_login_prompt_without_input() {
  # no org given and no stdin: must stop, not loop
  run login
  assert_rc 1
  assert_out_has "No input; run 'ucli help'."
  [[ "$(lines_of)" -lt 5 ]] || fail "prompt looped: $(lines_of) lines"
}

run_all
