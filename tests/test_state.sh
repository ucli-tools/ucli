#!/bin/bash
# shellcheck disable=SC2016,SC2012  # test stubs are written as single-quoted scripts; ls is only used to count files
# Installed-state record, update, versions, atomic self-update (slice 8).
# Real git and make against file:// fixture repos inside the sandbox HOME.
. "$(dirname "$0")/helpers.sh"

STATE() { echo "$HOME/.local/state/ucli/installed.tsv"; }
FAILING_MAKEFILE=$'build:\n\t@exit 1\n'

# record_state <name> <commit>: write a state line by hand (as an older build would have).
record_state() {
  mkdir -p "$HOME/.local/state/ucli"
  printf '%s\t%s\t2026-01-01T00:00:00Z\t%s\n' "$1" "$2" "$HOME/.local/bin/$1" >> "$(STATE)"
}

t_state_is_written_only_after_a_successful_build() {
  real_tools
  add_tool good "$(installing_makefile good)"
  add_tool bad "$FAILING_MAKEFILE"
  add_tool nobuild $'help:\n\t@echo hi\n'
  run build good bad nobuild
  assert_rc 1
  assert_file_has "$(STATE)" "good"
  ! grep -q '^bad' "$(STATE)" || fail "failed build was recorded"
  ! grep -q '^nobuild' "$(STATE)" || fail "refused tool was recorded"
  local line
  line="$(grep '^good' "$(STATE)")"
  assert_eq "$(printf '%s' "$line" | cut -f2)" "$(pin_of good)" "recorded commit"
  assert_eq "$(printf '%s' "$line" | cut -f1)" "good" "recorded name"
  case "$(printf '%s' "$line" | cut -f3)" in
    20??-??-??T*Z) ;;
    *) fail "date field malformed: $line" ;;
  esac
  assert_eq "$(printf '%s\n' "$line" | awk -F '\t' '{print NF}')" "4" "field count"
}

t_failed_build_leaves_no_state_file() {
  real_tools
  add_tool bad "$FAILING_MAKEFILE"
  run build bad
  assert_rc 1
  [[ ! -e "$(STATE)" ]] || fail "state file exists after only a failed build"
}

t_rebuild_replaces_the_line_instead_of_adding() {
  real_tools
  add_tool good "$(installing_makefile good)"
  run build good
  bump_tool good
  run build good
  assert_rc 0
  assert_eq "$(grep -c '^good' "$(STATE)")" "1" "lines for good"
  assert_file_has "$(STATE)" "$(pin_of good)"
}

t_legacy_install_is_detected_with_commit_unknown() {
  real_tools
  add_tool good "$(installing_makefile good)"
  printf '#!/bin/sh\necho old\n' > "$HOME/.local/bin/good"; chmod +x "$HOME/.local/bin/good"
  export PATH="$HOME/.local/bin:$PATH"
  run versions good
  assert_rc 0
  assert_out_has "installed, commit unknown"
  assert_out_has "$HOME/.local/bin/good"
  assert_out_has "Update available"
}

t_legacy_tool_is_updated_then_recorded() {
  real_tools
  add_tool good "$(installing_makefile good)"
  printf '#!/bin/sh\necho old\n' > "$HOME/.local/bin/good"; chmod +x "$HOME/.local/bin/good"
  export PATH="$HOME/.local/bin:$PATH"
  run update
  assert_rc 0
  assert_eq "$("$HOME/.local/bin/good")" "good" "tool was rebuilt"
  assert_file_has "$(STATE)" "$(pin_of good)"
  run update
  assert_rc 0
  assert_err_has "good is up to date"
}

t_unrelated_program_elsewhere_on_path_is_ignored() {
  real_tools
  add_tool good "$(installing_makefile good)"
  mkdir -p "$SB/elsewhere"
  printf '#!/bin/sh\necho mine\n' > "$SB/elsewhere/good"; chmod +x "$SB/elsewhere/good"
  export PATH="$SB/elsewhere:$PATH"
  run update
  assert_rc 0
  assert_err_has "No installed tools found to update"
  ! grep -q '^make build' "$SB/calls.log" || fail "a build ran over an unrelated program"
  assert_eq "$("$SB/elsewhere/good")" "mine" "unrelated program untouched"
  run versions good
  assert_out_has "not installed locally"
}

t_update_skips_current_tools_and_rebuilds_the_one_behind() {
  real_tools
  add_tool uptodate "$(installing_makefile uptodate)"
  add_tool behind "$(installing_makefile behind)"
  run build uptodate behind
  assert_rc 0
  bump_tool behind
  : > "$SB/calls.log"
  run update
  assert_rc 0
  assert_err_has "uptodate is up to date"
  assert_err_lacks "behind is up to date"
  assert_err_has "built: behind; failed: none"
  assert_eq "$(grep -c '^make build$' "$SB/calls.log")" "1" "number of builds"
  assert_file_has "$(STATE)" "$(pin_of behind)"
}

t_update_with_everything_current_builds_nothing() {
  real_tools
  add_tool good "$(installing_makefile good)"
  run build good
  : > "$SB/calls.log"
  run update
  assert_rc 0
  assert_err_has "good is up to date"
  ! grep -q '^make' "$SB/calls.log" || fail "make ran although nothing changed"
}

t_update_exits_1_when_a_rebuild_fails() {
  real_tools
  add_tool good "$(installing_makefile good)"
  run build good
  bump_tool good
  printf 'build:\n\t@exit 1\n' > "$SB/git/ucli-tools/good.git/Makefile"
  "$REAL_GIT" -C "$SB/git/ucli-tools/good.git" -c user.name=t -c user.email=t@example.invalid commit -q -am breakage
  local old new
  old="$(grep -o '[0-9a-f]\{40\}' "$SB/reg.yaml" | head -n 1)"
  new="$(pin_of good)"
  sed "s/$old/$new/" "$SB/reg.yaml" > "$SB/reg.yaml.new" && mv "$SB/reg.yaml.new" "$SB/reg.yaml"
  run update
  assert_rc 1
  assert_err_has "failed: good"
  ! grep -q "$new" "$(STATE)" || fail "state moved to a commit that did not build"
}

t_ms2md_record_is_ignored() {
  real_tools
  add_tool docx2md "$(installing_makefile docx2md)"
  record_state ms2md 1111111111111111111111111111111111111111
  run versions --all
  assert_rc 0
  assert_out_lacks "ms2md"
  assert_out_lacks "docx2md:"
}

t_versions_tool_shows_pin_commit_path_and_status() {
  real_tools
  add_tool good "$(installing_makefile good)"
  run build good
  run versions good
  assert_rc 0
  assert_out_has "Pin:"
  assert_out_has "$(pin_of good)"
  assert_out_has "Path:"
  assert_out_has "$HOME/.local/bin/good"
  assert_out_has "Up to date"
  bump_tool good
  run versions good
  assert_out_has "Update available"
  assert_out_lacks "commit unknown"
}

t_versions_all_lists_installed_registry_tools() {
  real_tools
  add_tool good "$(installing_makefile good)"
  add_tool other "$(installing_makefile other)"
  run build good
  bump_tool good
  run versions --all
  assert_rc 0
  assert_out_has "good:"
  assert_out_has "update available"
  assert_out_lacks "other:"
}

t_install_is_atomic_on_success() {
  ALLOW_SUDO=1
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exec "$@"'
  printf '#!/bin/sh\necho old\n' > "$SB/sysbin/ucli"; chmod +x "$SB/sysbin/ucli"
  run install
  assert_rc 0
  assert_eq "$(cmp -s "$UCLI" "$SB/sysbin/ucli" && echo same)" "same" "installed content"
  [[ -x "$SB/sysbin/ucli" ]] || fail "installed file not executable"
  assert_eq "$(ls -A "$SB/sysbin")" "ucli" "leftovers in the install dir"
  assert_file_has "$SB/sudo.log" "sudo mv -f $SB/sysbin/.ucli.new."
}

t_install_failing_at_the_final_move_leaves_the_old_binary_whole() {
  ALLOW_SUDO=1
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; case "$1" in mv) exit 1 ;; esac; exec "$@"'
  printf '#!/bin/sh\necho old\n' > "$SB/sysbin/ucli"; chmod +x "$SB/sysbin/ucli"
  local before
  before="$(cksum < "$SB/sysbin/ucli")"
  run install
  assert_rc 1
  assert_err_has "Error installing ucli."
  assert_eq "$(cksum < "$SB/sysbin/ucli")" "$before" "old binary"
  assert_eq "$(ls -A "$SB/sysbin")" "ucli" "temp file left behind"
}

t_install_failing_at_the_copy_leaves_the_old_binary_whole() {
  ALLOW_SUDO=1
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; case "$1" in cp) exit 1 ;; esac; exec "$@"'
  printf '#!/bin/sh\necho old\n' > "$SB/sysbin/ucli"; chmod +x "$SB/sysbin/ucli"
  local before
  before="$(cksum < "$SB/sysbin/ucli")"
  run install
  assert_rc 1
  assert_eq "$(cksum < "$SB/sysbin/ucli")" "$before" "old binary"
  assert_eq "$(ls -A "$SB/sysbin")" "ucli" "temp file left behind"
}

# self_update_setup: an installed (older) ucli, registered as a tool whose build installs
# a changed copy of this ucli.sh, plus one ordinary tool that is behind.
self_update_setup() {
  ALLOW_SUDO=1
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exec "$@"'
  real_tools
  { cat "$UCLI"; printf '\n# new release\n'; } > "$SB/ucli-new.sh"
  chmod +x "$SB/ucli-new.sh"
  add_tool ucli $'build:\n\tbash ucli.sh install\n' "$SB/ucli-new.sh"
  add_tool good "$(installing_makefile good)"
  { cat "$UCLI"; printf '\n# old release\n'; } > "$SB/sysbin/ucli"
  chmod +x "$SB/sysbin/ucli"
  record_state ucli 1111111111111111111111111111111111111111
  record_state good 2222222222222222222222222222222222222222
}

t_self_update_replaces_the_running_file_and_continues_with_the_new_one() {
  self_update_setup
  local inode_before inode_after
  inode_before="$(ls -i "$SB/sysbin/ucli" | awk '{print $1}')"
  UCLI="$SB/sysbin/ucli" run update
  assert_rc 0
  inode_after="$(ls -i "$SB/sysbin/ucli" | awk '{print $1}')"
  [[ "$inode_before" != "$inode_after" ]] || fail "install overwrote the file in place (same inode)"
  assert_file_has "$SB/sysbin/ucli" "# new release"
  assert_err_has "Updating ucli itself first"
  assert_err_has "continuing with the new version"
  assert_eq "$("$HOME/.local/bin/good")" "good" "remaining tool rebuilt after the handover"
  assert_file_has "$(STATE)" "$(pin_of good)"
}

t_self_update_records_ucli_version_and_path() {
  self_update_setup
  UCLI="$SB/sysbin/ucli" run update
  assert_rc 0
  local line
  line="$(grep '^ucli' "$(STATE)")"
  assert_eq "$(grep -c '^ucli' "$(STATE)")" "1" "ucli lines"
  assert_eq "$(printf '%s' "$line" | cut -f2)" "$(pin_of ucli)" "ucli commit"
  assert_eq "$(printf '%s' "$line" | cut -f4)" "$SB/sysbin/ucli" "ucli path"
}

t_self_update_runs_before_the_other_tools() {
  self_update_setup
  UCLI="$SB/sysbin/ucli" run update
  assert_rc 0
  local first
  first="$(grep -n 'Updating ucli itself first' "$SB/err" | head -n 1 | cut -d: -f1)"
  local second
  second="$(grep -n 'Rebuilding 1 tool' "$SB/err" | head -n 1 | cut -d: -f1)"
  [[ -n "$first" && -n "$second" && "$first" -lt "$second" ]] || fail "order wrong: self $first, tools $second"
}

t_failed_self_update_keeps_the_old_file_and_still_updates_the_rest() {
  self_update_setup
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; case "$1" in mv) exit 1 ;; esac; exec "$@"'
  local before
  before="$(cksum < "$SB/sysbin/ucli")"
  UCLI="$SB/sysbin/ucli" run update
  assert_rc 1
  assert_eq "$(cksum < "$SB/sysbin/ucli")" "$before" "old ucli"
  assert_eq "$(ls -A "$SB/sysbin")" "ucli" "temp file left behind"
  assert_eq "$("$HOME/.local/bin/good")" "good" "other tool still updated"
  assert_file_has "$(STATE)" "1111111111111111111111111111111111111111"
}

t_current_ucli_is_not_reinstalled() {
  self_update_setup
  UCLI="$SB/sysbin/ucli" run update
  : > "$SB/sudo.log"
  inode_a="$(ls -i "$SB/sysbin/ucli" | awk '{print $1}')"
  UCLI="$SB/sysbin/ucli" run update
  assert_rc 0
  assert_eq "$(ls -i "$SB/sysbin/ucli" | awk '{print $1}')" "$inode_a" "inode after a no-op update"
  assert_err_lacks "Updating ucli itself"
}

run_all
