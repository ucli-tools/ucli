#!/bin/bash
# The script itself and the guards around it.
. "$(dirname "$0")/helpers.sh"

t_shebang_is_bin_bash() {
  assert_eq "$(head -n 1 "$UCLI")" "#!/bin/bash" "shebang"
}

t_ucli_is_executable_in_git() {
  [[ -x "$UCLI" ]] || fail "ucli.sh not executable on disk"
  if PATH="$ORIG_PATH" git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    local mode
    mode="$(PATH="$ORIG_PATH" git -C "$ROOT" ls-files -s ucli.sh | cut -d' ' -f1)"
    assert_eq "$mode" "100755" "git mode of ucli.sh"
  fi
}

t_bash4_scan_is_clean_on_repo() {
  "$TESTS_DIR/check_bash4.sh" > "$SB/out" 2> "$SB/err"
  RC=$?
  assert_rc 0
}

t_bash4_scan_catches_every_banned_feature() {
  "$TESTS_DIR/check_bash4.sh" "$TESTS_DIR/fixtures/bash4_bad.txt" > "$SB/out" 2> "$SB/err"
  RC=$?
  assert_rc 1
  # one hit kind per banned feature in the fixture: 12 patterns
  assert_err_has "12 banned feature kind(s) found"
}

t_real_home_untouched_and_no_network_across_commands() {
  run help; run versions uclitest-alpha; run login x-org; run logout
  # finish() asserts: real HOME unchanged, no network use
  [[ "$HOME" == "$SB/home" ]] || fail "HOME is not the sandbox"
}

run_all
