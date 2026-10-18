#!/bin/bash
# Characterisation tests: they record what ucli.sh does today, quirks included.
. "$(dirname "$0")/helpers.sh"

t_help() {
  run help
  assert_rc 0
  assert_out_has "UCLI - Universal Command Line Interface Tool"
  local c
  for c in "Install ucli to ~/.local/bin" "Remove ucli, ~/.ucli_env" "Set GitHub organization" \
    "Unset GitHub organization" "List official tools from UCLI Registry" "Show version information for tools" \
    "Build tools from specified GitHub repositories" "Build all tools listed by" "Update all installed tools" \
    "Install prerequisites (apt, dnf, pacman, brew)" "Show this help message"; do
    assert_out_has "$c"
  done
  assert_out_has "License: Apache 2.0"
}

t_no_args_non_tty_shows_help() {
  run
  assert_rc 2
  assert_out_has "Commands:"
}

t_unknown_command() {
  run frobnicate
  assert_rc 1
  assert_out_has "Invalid command. Use 'ucli help' for usage information."
}

t_list_prints_fixture_tools_sorted() {
  run -i $'\n' list
  assert_rc 0
  assert_eq "$(grep '^uclitest-' "$SB/out" | tr '\n' ' ')" "uclitest-alpha uclitest-beta uclitest-gamma " "tool lines"
  assert_err_has "Fetching repositories for"
  assert_err_has "Repository list displayed"
}

t_list_without_stdin_exits_0() {
  # the "Press ENTER" pause is for the interactive menu only
  run list
  assert_rc 0
  assert_out_has "uclitest-alpha"
  assert_out_lacks "No input"
}

t_list_creates_default_login_only_in_sandbox() {
  # list does not call check_login; no env file is written
  run -i $'\n' list
  [[ ! -e "$HOME/.ucli_env" ]] || fail ".ucli_env created by list"
}

t_versions_without_args_prints_usage() {
  run versions
  assert_rc 1
  assert_out_has "Usage: ucli versions <tool-name> or ucli versions --all"
}

t_versions_tool_prints_pin_and_details() {
  run versions uclitest-alpha
  assert_rc 0
  assert_out_has "Version Information for 'uclitest-alpha':"
  assert_out_has "1111111111111111111111111111111111111111"
  assert_out_has "production"
  assert_out_has "github.com/ucli-tools/uclitest-alpha"
  assert_out_has "Alpha fixture tool"
  assert_out_has "2026-01-02"
  assert_out_has "Alpha commit message"
  assert_out_has "https://example.invalid/alpha/commit/1111"
  assert_out_has "Tool is not installed locally"
  assert_out_has "ucli build uclitest-alpha"
}

t_versions_tool_without_version_info() {
  run versions uclitest-beta
  assert_rc 0
  assert_out_has "2222222222222222222222222222222222222222"
  assert_out_lacks "Commit Date:"
  assert_out_lacks "Last Commit:"
}

t_versions_unknown_tool() {
  run versions no-such-tool
  assert_rc 1
  assert_out_has "Tool 'no-such-tool' not found in UCLI Registry."
  assert_out_has "ucli list"
}

t_versions_prefix_is_not_an_official_name() {
  run versions uclitest
  assert_rc 1
  assert_out_has "not found in UCLI Registry"
}

t_versions_all_without_official_tools_installed() {
  run versions --all
  assert_rc 0
  assert_out_has "Installed UCLI Tools and Versions:"
  assert_out_lacks "uclitest-"
}

t_versions_with_unreachable_registry() {
  UCLI_REGISTRY_URL="file://$SB/missing.yaml" run versions uclitest-alpha
  assert_rc 1
  assert_out_has "not found in UCLI Registry"
}

t_login_writes_env_file() {
  run login test-org
  assert_rc 0
  assert_eq "$(cat "$HOME/.ucli_env")" "test-org" ".ucli_env"
  assert_err_has "Logged in as test-org"
}

t_login_same_org_again() {
  run login test-org
  run login test-org
  assert_rc 0
  assert_err_has "Already logged in as test-org"
}

t_login_switches_org() {
  run login org-one
  run login org-two
  assert_rc 0
  assert_err_has "Switching from org-one to org-two"
  assert_eq "$(cat "$HOME/.ucli_env")" "org-two" ".ucli_env"
}

t_login_overwrites_corrupted_env() {
  : > "$HOME/.ucli_env"
  run login fresh-org
  assert_rc 0
  assert_err_has "is corrupted. Overwriting..."
  assert_eq "$(cat "$HOME/.ucli_env")" "fresh-org" ".ucli_env"
}

t_login_prompts_for_org_on_stdin() {
  run -i $'prompted-org\n' login
  assert_rc 0
  assert_eq "$(cat "$HOME/.ucli_env")" "prompted-org" ".ucli_env"
}

t_login_when_logged_in_and_enter_keeps_org() {
  run login keep-org
  run -i $'\n' login
  assert_rc 0
  assert_err_has "Currently logged in as keep-org"
  assert_err_has "Keeping current login as keep-org"
}

t_logout_removes_env_file() {
  run login some-org
  run logout
  assert_rc 0
  assert_err_has "Successfully logged out."
  [[ ! -e "$HOME/.ucli_env" ]] || fail ".ucli_env still present"
}

t_logout_when_not_logged_in() {
  run logout
  assert_rc 0
  assert_err_has "You are not currently logged in."
}

t_install_needs_sudo_and_fails_safely() {
  ALLOW_SUDO=1
  run install
  assert_rc 1
  assert_err_has "Error installing ucli."
  assert_file_has "$SB/sudo.log" "sudo cp"
}

t_uninstall_when_not_installed() {
  if [[ -f /usr/local/bin/ucli ]]; then
    echo "    (skipped: /usr/local/bin/ucli exists on this machine)"
    return 0
  fi
  run uninstall
  assert_rc 0
  assert_err_has "No ucli file found in"
}

t_prereq_uses_sudo_apt() {
  ALLOW_SUDO=1
  run prereq
  assert_rc 1
  assert_err_has "Failed to install prerequisites"
  assert_file_has "$SB/sudo.log" "sudo apt update"
}

t_update_with_no_tools_installed() {
  run update
  assert_rc 0
  assert_err_has "No installed tools found to update"
}

t_logging_sleeps_unless_disabled() {
  # sleeping is for the interactive menu (UCLI_MENU=1) only
  UCLI_MENU=1 run help
  assert_eq "$(wc -c < "$SB/sleep.log" | tr -d ' ')" "0" "sleep log size with UCLI_NO_SLEEP=1"
  UCLI_NO_SLEEP='' run help
  assert_eq "$(wc -c < "$SB/sleep.log" | tr -d ' ')" "0" "sleep log size in command-line mode"
  UCLI_MENU=1 UCLI_NO_SLEEP='' run list
  [[ -s "$SB/sleep.log" ]] || fail "sleep not called when UCLI_NO_SLEEP is empty"
}

t_registry_url_seam_is_used() {
  run -i $'\n' list
  assert_file_has "$SB/calls.log" "curl -s $FIXTURE_REGISTRY"
}

run_all
