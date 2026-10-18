#!/bin/bash
# shellcheck disable=SC2016,SC2012  # test stubs are written as single-quoted scripts; ls is only used to count files
# Install without sudo, in-place update of a system copy, opt-in move, remove, uninstall (slice 14).
# The old system copy is a fixture file named by UCLI_LEGACY_BIN; nothing touches /usr/local/bin.
. "$(dirname "$0")/helpers.sh"

STATE() { echo "$HOME/.local/state/ucli/installed.tsv"; }

# user_mode: no forced system dir; the legacy path points at a fixture (absent unless a test makes it).
user_mode() {
  unset UCLI_INSTALL_DIR UCLI_PREFIX
  export UCLI_LEGACY_BIN="$SB/legacy/ucli"
}

record_state() { # name commit
  mkdir -p "$HOME/.local/state/ucli"
  printf '%s\t%s\t2026-01-01T00:00:00Z\t%s\n' "$1" "$2" "$HOME/.local/bin/$1" >> "$(STATE)"
}

t_fresh_install_goes_to_local_bin_without_sudo() {
  user_mode
  run install
  assert_rc 0
  [[ -x "$HOME/.local/bin/ucli" ]] || fail "ucli not in ~/.local/bin"
  assert_eq "$(cmp -s "$UCLI" "$HOME/.local/bin/ucli" && echo same)" "same" "installed content"
  [[ ! -e "$SB/legacy/ucli" ]] || fail "wrote the legacy path"
  assert_eq "$(wc -c < "$SB/sudo.log" | tr -d ' ')" "0" "sudo log size"
  assert_err_has "installed to $HOME/.local/bin"
}

t_install_creates_the_bin_dir() {
  user_mode
  rm -rf "${HOME:?}/.local"
  run install
  assert_rc 0
  [[ -x "$HOME/.local/bin/ucli" ]] || fail "ucli not installed into a fresh ~/.local/bin"
}

t_install_honours_ucli_prefix() {
  user_mode
  export UCLI_PREFIX="$SB/prefix"
  run install
  assert_rc 0
  [[ -x "$SB/prefix/bin/ucli" ]] || fail "ucli not in \$UCLI_PREFIX/bin"
  [[ ! -e "$HOME/.local/bin/ucli" ]] || fail "also wrote ~/.local/bin"
}

t_path_hint_for_bash_zsh_fish_when_dir_not_on_path() {
  user_mode
  run install
  assert_rc 0
  assert_err_has "is not on your PATH"
  assert_err_has "bash:"
  assert_err_has "zsh:"
  assert_err_has "fish_add_path"
  assert_err_has '$HOME/.local/bin'
}

t_no_path_hint_when_dir_is_on_path() {
  user_mode
  PATH="$HOME/.local/bin:$PATH" run install
  assert_rc 0
  assert_err_lacks "is not on your PATH"
}

t_existing_system_copy_is_updated_in_place_without_sudo() {
  user_mode
  mkdir -p "$SB/legacy"
  printf '#!/bin/sh\necho old\n' > "$SB/legacy/ucli"; chmod +x "$SB/legacy/ucli"
  run install
  assert_rc 0
  assert_eq "$(cmp -s "$UCLI" "$SB/legacy/ucli" && echo same)" "same" "legacy copy content"
  [[ ! -e "$HOME/.local/bin/ucli" ]] || fail "a second copy appeared in ~/.local/bin"
  assert_eq "$(wc -c < "$SB/sudo.log" | tr -d ' ')" "0" "sudo log size"
  assert_err_has "install --move"
}

t_self_update_of_a_system_copy_stays_in_place_without_sudo() {
  user_mode
  real_tools
  mkdir -p "$SB/legacy"
  { cat "$UCLI"; printf '\n# new release\n'; } > "$SB/ucli-new.sh"; chmod +x "$SB/ucli-new.sh"
  add_tool ucli $'build:\n\tbash ucli.sh install\n' "$SB/ucli-new.sh"
  { cat "$UCLI"; printf '\n# old release\n'; } > "$SB/legacy/ucli"; chmod +x "$SB/legacy/ucli"
  mkdir -p "$HOME/.local/state/ucli"
  printf 'ucli\t1111111111111111111111111111111111111111\t2026-01-01T00:00:00Z\t%s\n' "$SB/legacy/ucli" > "$(STATE)"
  UCLI="$SB/legacy/ucli" run update
  assert_rc 0
  assert_file_has "$SB/legacy/ucli" "# new release"
  [[ ! -e "$HOME/.local/bin/ucli" ]] || fail "a second copy appeared in ~/.local/bin"
  assert_eq "$(wc -c < "$SB/sudo.log" | tr -d ' ')" "0" "sudo log size"
  assert_eq "$(cut -f4 "$(STATE)")" "$SB/legacy/ucli" "recorded path"
}

t_opt_in_move_leaves_exactly_one_ucli() {
  if [[ "$(id -u)" == "0" ]]; then echo "    (skipped: root can write anywhere)"; return 0; fi
  ALLOW_SUDO=1
  user_mode
  mkdir -p "$SB/legacy"
  printf '#!/bin/sh\necho old\n' > "$SB/legacy/ucli"; chmod +x "$SB/legacy/ucli"
  chmod 555 "$SB/legacy"
  # The system dir is not writable, so removing the old copy needs sudo: the shim records it
  # and makes the directory writable before running the command as the same user.
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; chmod u+w "'"$SB"'/legacy"; exec "$@"'
  run install --move
  chmod 755 "$SB/legacy"
  assert_rc 0
  [[ -x "$HOME/.local/bin/ucli" ]] || fail "new copy missing"
  [[ ! -e "$SB/legacy/ucli" ]] || fail "old copy still there"
  assert_file_has "$SB/sudo.log" "sudo rm -f $SB/legacy/ucli"
  assert_eq "$(grep -c 'sudo cp\|sudo mv\|sudo tee' "$SB/sudo.log")" "0" "sudo used for the new copy"
  assert_eq "$(cut -f4 "$(STATE)")" "$HOME/.local/bin/ucli" "recorded path"
}

t_move_without_a_system_copy_is_refused() {
  user_mode
  run install --move
  assert_rc 1
  assert_err_has "no system copy"
  [[ ! -e "$HOME/.local/bin/ucli" ]] || fail "installed anyway"
}

t_install_rejects_unknown_options() {
  user_mode
  run install --bogus
  assert_rc 1
  assert_err_has "Unknown option"
}

t_shadow_warning_only_from_an_installed_copy() {
  user_mode
  mkdir -p "$SB/other" "$SB/stamped"
  printf '#!/bin/sh\necho other\n' > "$SB/other/ucli"; chmod +x "$SB/other/ucli"
  sed 's/^UCLI_BUILD_ID=.*/UCLI_BUILD_ID="0123456789abcdef0123456789abcdef01234567"/' "$UCLI" > "$SB/stamped/ucli"
  chmod +x "$SB/stamped/ucli"
  # from a clone: no warning
  PATH="$SB/other:$PATH" run list
  assert_rc 0
  assert_err_lacks "shadows"
  # installed copy, another ucli first on PATH: warning
  UCLI="$SB/stamped/ucli" PATH="$SB/other:$PATH" run list
  assert_rc 0
  assert_err_has "Another ucli shadows this file"
  # installed copy and it is the one on PATH: no warning
  UCLI="$SB/stamped/ucli" PATH="$SB/stamped:$PATH" run list
  assert_err_lacks "shadows"
}

# A tool whose build installs a script and whose delete removes it.
deletable_makefile() { # name
  printf 'build:\n\t@mkdir -p "$(HOME)/.local/bin"\n\t@printf "#!/bin/sh\\necho %s\\n" > "$(HOME)/.local/bin/%s"\n\t@chmod +x "$(HOME)/.local/bin/%s"\n\ndelete:\n\t@rm -f "$(HOME)/.local/bin/%s"\n' "$1" "$1" "$1" "$1"
}

t_remove_runs_delete_and_updates_the_state_file() {
  user_mode
  real_tools
  add_tool good "$(deletable_makefile good)"
  add_tool keep "$(deletable_makefile keep)"
  run build good keep
  assert_rc 0
  [[ -x "$HOME/.local/bin/good" ]] || fail "good not installed"
  run remove good
  assert_rc 0
  [[ ! -e "$HOME/.local/bin/good" ]] || fail "good still installed"
  [[ -x "$HOME/.local/bin/keep" ]] || fail "keep was removed too"
  ! grep -q '^good' "$(STATE)" || fail "state line for good kept"
  grep -q '^keep' "$(STATE)" || fail "state line for keep lost"
  [[ -z "$(ls -A "$HOME/.cache/ucli" 2>/dev/null)" ]] || fail "build dir left behind"
}

t_remove_uses_the_recorded_commit() {
  user_mode
  real_tools
  add_tool good "$(deletable_makefile good)"
  local old
  old="$(pin_of good)"
  run build good
  bump_tool good
  run remove good
  assert_rc 0
  assert_file_has "$SB/calls.log" "$old"
  ! grep -q "$(pin_of good)" "$SB/calls.log" || fail "fetched the new pin instead of the recorded commit"
}

t_remove_refuses_a_tool_without_a_delete_target() {
  user_mode
  real_tools
  add_tool nodel "$(installing_makefile nodel)"
  run build nodel
  assert_rc 0
  run remove nodel
  assert_rc 1
  assert_err_has "no 'delete' target"
  [[ -x "$HOME/.local/bin/nodel" ]] || fail "tool was removed"
  grep -q '^nodel' "$(STATE)" || fail "state line dropped"
}

t_remove_keeps_the_record_when_delete_fails() {
  user_mode
  real_tools
  add_tool bad $'build:\n\t@mkdir -p "$(HOME)/.local/bin"; echo x > "$(HOME)/.local/bin/bad"\n\ndelete:\n\t@exit 1\n'
  run build bad
  run remove bad
  assert_rc 1
  grep -q '^bad' "$(STATE)" || fail "state line dropped after a failed delete"
}

t_remove_rejects_unknown_and_ucli() {
  user_mode
  real_tools
  run remove nothing-here
  assert_rc 1
  assert_err_has "is not installed"
  run remove ucli
  assert_rc 1
  assert_err_has "ucli uninstall"
  run remove ../x
  assert_rc 1
  assert_err_has "Invalid tool name"
}

t_uninstall_removes_exactly_the_listed_paths() {
  user_mode
  # ucli's own file and residue
  mkdir -p "$HOME/.local/bin" "$HOME/.local/state/ucli" "$HOME/.ucli" "$HOME/.cache/ucli/build.abc"
  printf '#!/bin/sh\n' > "$HOME/.local/bin/ucli"; chmod +x "$HOME/.local/bin/ucli"
  record_state ucli 1111111111111111111111111111111111111111
  echo org > "$HOME/.ucli_env"
  echo x > "$HOME/.ucli/file"
  echo x > "$HOME/.cache/ucli/build.abc/f"
  # things that must survive
  mkdir -p "$HOME/.local/state/other" "$HOME/.cache/other" "$HOME/.config"
  printf '#!/bin/sh\n' > "$HOME/.local/bin/sometool"; chmod +x "$HOME/.local/bin/sometool"
  echo keep > "$HOME/.bashrc"
  echo keep > "$HOME/.local/state/other/s"
  echo keep > "$HOME/.cache/other/c"
  run uninstall
  assert_rc 0
  local left expected
  left="$(cd "$HOME" && find . | sort)"
  expected="$(printf '%s\n' . ./.bashrc ./.cache ./.cache/other ./.cache/other/c ./.config ./.local ./.local/bin ./.local/bin/sometool ./.local/state ./.local/state/other ./.local/state/other/s | sort)"
  assert_eq "$left" "$expected" "what is left in HOME"
  assert_eq "$(wc -c < "$SB/sudo.log" | tr -d ' ')" "0" "sudo log size"
}

t_uninstall_leaves_tools_and_says_how_to_remove_them() {
  user_mode
  real_tools
  add_tool good "$(deletable_makefile good)"
  run build good
  record_state ucli 1111111111111111111111111111111111111111
  printf '#!/bin/sh\n' > "$HOME/.local/bin/ucli"; chmod +x "$HOME/.local/bin/ucli"
  run uninstall
  assert_rc 0
  [[ -x "$HOME/.local/bin/good" ]] || fail "tool was removed"
  [[ ! -e "$HOME/.local/bin/ucli" ]] || fail "ucli still there"
  assert_err_has "still installed"
  assert_err_has "ucli remove <tool>"
}

t_uninstall_removes_a_system_copy_in_place() {
  user_mode
  mkdir -p "$SB/legacy"
  printf '#!/bin/sh\n' > "$SB/legacy/ucli"; chmod +x "$SB/legacy/ucli"
  run uninstall
  assert_rc 0
  [[ ! -e "$SB/legacy/ucli" ]] || fail "system copy kept"
  assert_eq "$(wc -c < "$SB/sudo.log" | tr -d ' ')" "0" "sudo log size (writable fixture dir)"
}

run_all
