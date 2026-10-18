#!/bin/bash
# Registry parsing and fetching by pinned commit (slice 6).
. "$(dirname "$0")/helpers.sh"

SHA_A=1111111111111111111111111111111111111111
SHA_B=2222222222222222222222222222222222222222

# --- registry parsing ------------------------------------------------------

t_registry_with_60_tools_parses() {
  write_big_registry "$SB/reg.yaml" 60
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run -i $'\n' list
  assert_rc 0
  assert_eq "$(grep -c '^tool-' "$SB/out")" "60" "listed tools"
  assert_out_has "tool-1"
  assert_out_has "tool-60"
}

t_registry_tool_past_39_gets_its_own_fields() {
  write_big_registry "$SB/reg.yaml" 60
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run versions tool-58
  assert_rc 0
  assert_out_has "$(printf '%040d' 58)"
  assert_out_has "Tool number 58"
  assert_out_has "github.com/ucli-tools/tool-58"
  assert_out_has "2026-01-01"
}

t_registry_templates_are_never_offered() {
  cat > "$SB/reg.yaml" <<'YAML'
apps:
  official:
  - name: real-one
    repo: github.com/ucli-tools/real-one
    version: 1111111111111111111111111111111111111111
  templates:
  - name: tpl-cli
    repo: github.com/ucli-tools/tpl-cli
    version: 2222222222222222222222222222222222222222
  community: []
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run -i $'\n' list
  assert_rc 0
  assert_out_has "real-one"
  assert_out_lacks "tpl-cli"
  run versions tpl-cli
  assert_rc 1
  assert_out_has "not found in UCLI Registry"
}

t_registry_templates_before_and_after_official() {
  cat > "$SB/reg.yaml" <<'YAML'
apps:
  templates:
  - name: tpl-first
    repo: github.com/ucli-tools/tpl-first
    version: 1111111111111111111111111111111111111111
  official:
  - name: real-one
    repo: github.com/ucli-tools/real-one
    version: 2222222222222222222222222222222222222222
  - name: real-two
    repo: github.com/ucli-tools/real-two
    version: 3333333333333333333333333333333333333333
  templates:
  - name: tpl-last
    repo: github.com/ucli-tools/tpl-last
    version: 4444444444444444444444444444444444444444
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run -i $'\n' list
  assert_eq "$(grep -E '^(real|tpl)-' "$SB/out" | tr '\n' ' ')" "real-one real-two " "listed"
}

t_build_template_is_refused() {
  cat > "$SB/reg.yaml" <<'YAML'
apps:
  official:
  - name: real-one
    repo: github.com/ucli-tools/real-one
    version: 1111111111111111111111111111111111111111
  templates:
  - name: tpl-cli
    repo: github.com/ucli-tools/tpl-cli
    version: 2222222222222222222222222222222222222222
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run build tpl-cli
  assert_rc 1
  assert_err_has "Could not find version for tool: tpl-cli"
  assert_err_lacks "git "
  ! grep -q '^git ' "$SB/calls.log" || fail "git was called for a template"
}

t_prefix_names_do_not_cross_match() {
  cat > "$SB/reg.yaml" <<'YAML'
apps:
  official:
  - name: mdtexpdf
    repo: github.com/ucli-tools/mdtexpdf
    version: 2222222222222222222222222222222222222222
  - name: md
    repo: github.com/ucli-tools/md
    version: 1111111111111111111111111111111111111111
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run versions md
  assert_rc 0
  assert_out_has "$SHA_A"
  assert_out_lacks "$SHA_B"
  run build md
  assert_rc 0
  assert_file_has "$SB/calls.log" "origin $SHA_A"
  ! grep -q "$SHA_B" "$SB/calls.log" || fail "mdtexpdf pin used for md"
}

t_registry_without_official_section_is_an_error() {
  printf '404: Not Found\n' > "$SB/reg.yaml"
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run build tool-1
  assert_rc 1
  assert_err_has "Could not find version for tool: tool-1"
  run -i $'\n' list
  assert_err_has "No tools found in registry"
}

t_unreachable_registry_build_fails() {
  export UCLI_REGISTRY_URL="file://$SB/missing.yaml"
  run build uclitest-alpha
  assert_rc 1
  assert_err_has "Failed to fetch registry data"
}

t_registry_fetched_once_per_build() {
  run build uclitest-alpha uclitest-beta
  assert_rc 0
  assert_eq "$(grep -c '^curl ' "$SB/calls.log" | tr -d ' ')" "1" "registry fetches"
}

# --- fetch by pinned SHA (stub git) ----------------------------------------

t_build_fetches_the_exact_pinned_sha() {
  run build uclitest-alpha
  assert_rc 0
  assert_file_has "$SB/calls.log" "init --quiet"
  assert_file_has "$SB/calls.log" "fetch --quiet --depth 1 origin $SHA_A"
  assert_file_has "$SB/calls.log" "checkout --quiet --detach FETCH_HEAD"
  assert_file_has "$SB/calls.log" "rev-parse HEAD"
  ! grep -q ' clone ' "$SB/calls.log" || fail "cloned instead of fetching the pin"
  assert_file_has "$SB/calls.log" "make "
}

t_build_two_tools_fetches_each_pin() {
  run build uclitest-alpha uclitest-beta
  assert_rc 0
  assert_file_has "$SB/calls.log" "origin $SHA_A"
  assert_file_has "$SB/calls.log" "origin $SHA_B"
}

t_clone_url_comes_from_the_repo_field() {
  cat > "$SB/reg.yaml" <<'YAML'
apps:
  official:
  - name: short
    repo: github.com/other-org/long-repo-name
    version: 1111111111111111111111111111111111111111
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run build short
  assert_rc 0
  assert_file_has "$SB/calls.log" "remote add origin $UCLI_GIT_BASE/other-org/long-repo-name.git"
}

t_fetch_by_sha_refused_falls_back_to_full_clone() {
  : > "$SB/git_fail_fetch"
  run build uclitest-alpha
  assert_rc 0
  assert_err_has "trying a full clone"
  assert_file_has "$SB/calls.log" " clone --quiet "
  assert_file_has "$SB/calls.log" "checkout --quiet --detach $SHA_A"
  assert_file_has "$SB/calls.log" "make "
}

t_forced_full_clone_switch() {
  UCLI_FORCE_FULL_CLONE=1 run build uclitest-alpha
  assert_rc 0
  ! grep -q ' fetch ' "$SB/calls.log" || fail "fetch used despite UCLI_FORCE_FULL_CLONE"
  assert_file_has "$SB/calls.log" " clone --quiet "
}

t_pin_missing_on_remote_fails_clearly() {
  : > "$SB/git_fail_fetch"
  : > "$SB/git_missing_pin"
  run build uclitest-alpha
  assert_rc 1
  assert_err_has "Pinned commit $SHA_A does not exist"
  assert_err_has "Error fetching uclitest-alpha at $SHA_A"
  ! grep -q '^make ' "$SB/calls.log" || fail "make ran although the pin was not fetched"
}

t_failed_tool_does_not_stop_the_next_but_exit_is_1() {
  cat > "$SB/reg.yaml" <<'YAML'
apps:
  official:
  - name: bad
    repo: github.com/ucli-tools/bad
    version: not-a-commit
  - name: good
    repo: github.com/ucli-tools/good
    version: 1111111111111111111111111111111111111111
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  run build bad good
  assert_rc 1
  assert_err_has "not a full 40-character commit hash"
  assert_file_has "$SB/calls.log" "origin $SHA_A"
  assert_file_has "$SB/calls.log" "make "
}

t_unknown_tool_exits_1() {
  run build no-such-tool
  assert_rc 1
  assert_err_has "Could not find version for tool: no-such-tool"
}

# --- real git: a pin that is behind main -----------------------------------

# make_remote: repo at $SB/git/ucli-tools/uclitest-alpha.git with two commits; sets
# OLD_SHA (the pin) and NEW_SHA (main). A wrapper around the real git logs each call.
make_remote() {
  REAL_GIT="$(PATH="$ORIG_PATH" command -v git)"
  local r="$SB/git/ucli-tools/uclitest-alpha.git"
  mkdir -p "$r"
  local g=("$REAL_GIT" -C "$r" -c user.name=test -c user.email=test@example.invalid)
  "${g[@]}" init --quiet
  "${g[@]}" symbolic-ref HEAD refs/heads/main
  echo one > "$r/file.txt"
  "${g[@]}" add file.txt
  "${g[@]}" commit --quiet -m one
  OLD_SHA="$("${g[@]}" rev-parse HEAD)"
  echo two > "$r/file.txt"
  "${g[@]}" commit --quiet -a -m two
  NEW_SHA="$("${g[@]}" rev-parse HEAD)"
  printf 'apps:\n  official:\n  - name: uclitest-alpha\n    repo: github.com/ucli-tools/uclitest-alpha\n    version: %s\n' "$OLD_SHA" > "$SB/reg.yaml"
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
  export UCLI_GIT_BASE="file://$SB/git"
  make_stub git 'echo "git $*" >> "'"$SB"'/calls.log"; exec "'"$REAL_GIT"'" "$@"'
  make_stub make 'echo "make $*" >> "'"$SB"'/calls.log"; "'"$REAL_GIT"'" rev-parse HEAD > "'"$SB"'/make_head"; cat file.txt > "'"$SB"'/make_file"; exit 0'
}

t_real_git_pin_behind_main_builds_the_pin() {
  make_remote
  [[ "$OLD_SHA" != "$NEW_SHA" ]] || fail "fixture has one commit"
  run build uclitest-alpha
  assert_rc 0
  assert_eq "$(cat "$SB/make_head")" "$OLD_SHA" "HEAD seen by make"
  assert_eq "$(cat "$SB/make_file")" "one" "file content at the pin"
}

t_real_git_forced_full_clone_builds_the_pin() {
  make_remote
  UCLI_FORCE_FULL_CLONE=1 run build uclitest-alpha
  assert_rc 0
  assert_eq "$(cat "$SB/make_head")" "$OLD_SHA" "HEAD seen by make"
  assert_file_has "$SB/calls.log" " clone --quiet "
}

t_real_git_wrong_pin_fails_clearly() {
  make_remote
  printf 'apps:\n  official:\n  - name: uclitest-alpha\n    repo: github.com/ucli-tools/uclitest-alpha\n    version: %s\n' "$(printf 'f%.0s' $(seq 1 40))" > "$SB/reg.yaml"
  run build uclitest-alpha
  assert_rc 1
  assert_err_has "does not exist"
  [[ ! -e "$SB/make_head" ]] || fail "make ran for a pin that does not exist"
}

run_all
