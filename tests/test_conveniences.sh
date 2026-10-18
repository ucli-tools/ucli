#!/bin/bash
# shellcheck disable=SC2016  # test stubs are written as single-quoted scripts
# Small conveniences (slice 18): login note, `requires:` key, prereq on dnf/pacman/brew.
. "$(dirname "$0")/helpers.sh"

t_login_with_org_notes_that_pins_come_from_ucli_tools() {
  run login my-org
  assert_rc 0
  assert_err_has "Logged in as my-org"
  assert_err_has "pinned versions always come from the ucli-tools registry"
}

t_login_without_org_has_no_note() {
  run -i $'some-org\n' login
  assert_rc 0
  assert_err_lacks "pinned versions always come from"
}

# add a requires: line to the last tool in the fixture registry
set_requires() { # value
  printf '    requires: %s\n' "$1" >> "$SB/reg.yaml"
}

t_requires_missing_program_fails_that_tool_only() {
  real_tools
  add_tool needy "$(installing_makefile needy)"
  set_requires "[no-such-prog-xyz, uv]"
  add_tool plain "$(installing_makefile plain)"
  run build needy plain
  assert_rc 1
  assert_err_has "needy needs no-such-prog-xyz"
  assert_err_has "failed: needy (no-such-prog-xyz"
  [[ ! -e "$HOME/.local/bin/needy" ]] || fail "needy built with a missing requirement"
  [[ -x "$HOME/.local/bin/plain" ]] || fail "the other tool was not built"
}

t_requires_present_program_builds() {
  real_tools
  make_stub pandoc 'exit 0'
  make_stub uv 'exit 0'
  add_tool needy "$(installing_makefile needy)"
  set_requires "uv, pandoc"
  run build needy
  assert_rc 0
  [[ -x "$HOME/.local/bin/needy" ]] || fail "needy not built"
}

t_requires_plain_scalar_form_is_checked() {
  real_tools
  add_tool needy "$(installing_makefile needy)"
  set_requires "no-such-prog-xyz"
  run build needy
  assert_rc 1
  assert_err_has "needy needs no-such-prog-xyz"
}

t_no_requires_key_changes_nothing() {
  real_tools
  add_tool plain "$(installing_makefile plain)"
  run build plain
  assert_rc 0
}

# --- prereq on other package managers ----------------------------------------

prereq_with() { # manager
  ALLOW_SUDO=1
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exec "$@"'
  make_stub "$1" 'echo "'"$1"' $*" >> "'"$SB"'/pm.log"; exit 0'
  make_stub uv 'exit 0'
  : > "$SB/pm.log"
  UCLI_PKG_MANAGER="$1" run prereq
}

t_prereq_dnf() {
  prereq_with dnf
  assert_rc 0
  assert_file_has "$SB/pm.log" "dnf install -y make git curl file tree"
  assert_err_has "Prerequisites installed successfully"
}

t_prereq_pacman() {
  prereq_with pacman
  assert_rc 0
  assert_file_has "$SB/pm.log" "pacman -S --needed --noconfirm make git curl file tree"
}

t_prereq_brew_runs_without_sudo() {
  prereq_with brew
  assert_rc 0
  assert_file_has "$SB/pm.log" "brew install make git curl tree"
  [[ ! -s "$SB/sudo.log" ]] || fail "brew path called sudo"
}

t_prereq_unknown_manager_is_refused() {
  UCLI_PKG_MANAGER=zypper run prereq
  assert_rc 1
  assert_err_has "Unsupported package manager: zypper"
}

run_all
