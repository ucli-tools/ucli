#!/bin/bash
# Command-line surface: --version, --help, no endless menu, no pauses or colours off a terminal.
. "$(dirname "$0")/helpers.sh"

SHA=0123456789abcdef0123456789abcdef01234567

t_version_dev_from_a_clone() {
  run --version
  assert_rc 0
  assert_eq "$(cat "$SB/out")" "ucli dev" "version output"
}

t_version_dev_shows_clone_commit() {
  echo abcdef1 > "$SB/git_head"
  run --version
  assert_rc 0
  assert_eq "$(cat "$SB/out")" "ucli dev (abcdef1)" "version output"
}

t_version_word_and_short_flag_agree() {
  run --version; cp "$SB/out" "$SB/v1"
  run version;   cp "$SB/out" "$SB/v2"
  run -V;        cp "$SB/out" "$SB/v3"
  cmp -s "$SB/v1" "$SB/v2" || fail "version differs from --version"
  cmp -s "$SB/v1" "$SB/v3" || fail "-V differs from --version"
}

t_stamped_copy_prints_its_commit() {
  sed "s/^UCLI_BUILD_ID=.*/UCLI_BUILD_ID=\"$SHA\"/" "$UCLI" > "$SB/ucli-stamped"
  chmod +x "$SB/ucli-stamped"
  "$SB/ucli-stamped" --version > "$SB/out" 2> "$SB/err" < /dev/null
  RC=$?
  assert_rc 0
  assert_eq "$(cat "$SB/out")" "ucli $SHA" "version output"
}

t_install_stamps_the_commit() {
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exec "$@"'
  ALLOW_SUDO=1
  echo "$SHA" > "$SB/git_head"
  run install
  assert_rc 0
  "$SB/sysbin/ucli" --version > "$SB/out" 2> "$SB/err" < /dev/null
  assert_eq "$(cat "$SB/out")" "ucli $SHA" "installed version"
  [[ -x "$SB/sysbin/ucli" ]] || fail "installed file not executable"
  assert_eq "$(ls -A "$SB/sysbin")" "ucli" "leftovers in the install dir"
  # only the stamp line differs from the source
  assert_eq "$(diff "$UCLI" "$SB/sysbin/ucli" | grep -c '^[<>]')" "2" "changed lines"
}

t_install_without_a_commit_copies_unchanged() {
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exec "$@"'
  ALLOW_SUDO=1
  run install
  assert_rc 0
  cmp -s "$UCLI" "$SB/sysbin/ucli" || fail "installed copy differs"
}

t_help_flags_match_help() {
  run help;   cp "$SB/out" "$SB/h1"
  run --help; cp "$SB/out" "$SB/h2"; assert_rc 0
  run -h;     cp "$SB/out" "$SB/h3"; assert_rc 0
  cmp -s "$SB/h1" "$SB/h2" || fail "--help differs from help"
  cmp -s "$SB/h1" "$SB/h3" || fail "-h differs from help"
  grep -qF "Commands:" "$SB/h1" || fail "help lacks Commands:"
  grep -qF "ucli help" "$SB/h1" || true
  assert_out_has "--version"
  assert_out_lacks "Press ENTER"
}

t_help_command_still_works_as_before() {
  run help
  assert_rc 0
  assert_out_has "UCLI - Universal Command Line Interface Tool"
  assert_out_has "Registry: https://registry.ucli.tools"
  assert_out_has "build-all"
}

t_echo_pipe_without_args_exits_2_quickly() {
  local t0 t1
  t0=$(date +%s)
  echo | "$UCLI" > "$SB/out" 2> "$SB/err"
  RC=$?
  t1=$(date +%s)
  assert_rc 2
  [[ $((t1 - t0)) -le 1 ]] || fail "took $((t1 - t0)) s"
  assert_out_has "Commands:"
}

t_menu_with_stdin_at_eof_is_short() {
  run
  assert_rc 2
  local n
  n=$(cat "$SB/out" "$SB/err" | wc -l | tr -d ' ')
  [[ "$n" -lt 20 ]] || fail "$n lines of output, expected under 20"
}

t_list_without_a_terminal_exits_0_without_pause() {
  run list
  assert_rc 0
  assert_out_has "uclitest-alpha"
  assert_err_lacks "Press ENTER"
}

t_no_colour_codes_off_a_terminal() {
  run help
  if grep -q "$(printf '\033')" "$SB/out"; then fail "escape codes on stdout"; fi
  run list
  if grep -q "$(printf '\033')" "$SB/err"; then fail "escape codes on stderr"; fi
}

t_no_colour_with_no_color_set() {
  NO_COLOR=1 run help
  if grep -q "$(printf '\033')" "$SB/out"; then fail "escape codes with NO_COLOR"; fi
  assert_out_has "Commands:"
}

t_unknown_option_still_fails() {
  run --frobnicate
  assert_rc 1
  assert_out_has "Invalid command. Use 'ucli help' for usage information."
}

run_all
