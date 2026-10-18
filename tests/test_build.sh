#!/bin/bash
# Build contract, exit codes, per-user build directory, uv (slice 7).
# Uses real git and real make against file:// fixture repos inside the sandbox HOME.
. "$(dirname "$0")/helpers.sh"

# real_tools: use the real git and make (the default stubs only record calls).
real_tools() {
  REAL_GIT="$(PATH="$ORIG_PATH" command -v git)"
  REAL_MAKE="$(PATH="$ORIG_PATH" command -v make)"
  make_stub git 'echo "git $*" >> "'"$SB"'/calls.log"; exec "'"$REAL_GIT"'" "$@"'
  make_stub make 'echo "make $*" >> "'"$SB"'/calls.log"; exec "'"$REAL_MAKE"'" "$@"'
  export UCLI_GIT_BASE="file://$SB/git"
  : > "$SB/reg.yaml"
  printf 'apps:\n  official:\n' > "$SB/reg.yaml"
  export UCLI_REGISTRY_URL="file://$SB/reg.yaml"
}

# add_tool <name> <Makefile text or "-" for none>: one-commit repo, listed in the registry.
add_tool() {
  local name="$1" mk="$2"
  local r="$SB/git/ucli-tools/$name.git"
  mkdir -p "$r"
  local g=("$REAL_GIT" -C "$r" -c user.name=test -c user.email=test@example.invalid)
  "${g[@]}" init --quiet
  "${g[@]}" symbolic-ref HEAD refs/heads/main
  echo "$name" > "$r/README"
  if [[ "$mk" != "-" ]]; then printf '%s' "$mk" > "$r/Makefile"; fi
  "${g[@]}" add -A
  "${g[@]}" commit --quiet -m init
  printf '  - name: %s\n    repo: github.com/ucli-tools/%s\n    version: %s\n' \
    "$name" "$name" "$("${g[@]}" rev-parse HEAD)" >> "$SB/reg.yaml"
}

# A Makefile whose first target is help and whose build target installs a script.
installing_makefile() { # name
  printf 'help:\n\t@echo help-ran > "$(HOME)/help_ran"\n\nbuild:\n\t@mkdir -p "$(HOME)/.local/bin"\n\t@printf "#!/bin/sh\\necho %s\\n" > "$(HOME)/.local/bin/%s"\n\t@chmod +x "$(HOME)/.local/bin/%s"\n' "$1" "$1" "$1"
}

t_help_first_makefile_installs_through_build() {
  real_tools
  add_tool helpfirst "$(installing_makefile helpfirst)"
  run build helpfirst
  assert_rc 0
  [[ -x "$HOME/.local/bin/helpfirst" ]] || fail "helpfirst not installed"
  [[ ! -e "$HOME/help_ran" ]] || fail "the help target ran"
  assert_err_has "built: helpfirst; failed: none"
}

t_only_the_build_goal_is_passed_to_make() {
  real_tools
  add_tool helpfirst "$(installing_makefile helpfirst)"
  run build helpfirst
  assert_rc 0
  assert_file_has "$SB/calls.log" "make build"
  ! grep -Ev '^make (-n )?build$' "$SB/calls.log" | grep -q '^make ' || fail "make got a goal other than build"
}

t_makefile_without_build_target_is_refused() {
  real_tools
  add_tool nobuild $'help:\n\t@echo ran > "$(HOME)/help_ran"\n\nall:\n\t@echo ran > "$(HOME)/all_ran"\n'
  run build nobuild
  assert_rc 1
  assert_err_has "nobuild does not follow the ucli contract (no build target)"
  [[ ! -e "$HOME/help_ran" && ! -e "$HOME/all_ran" ]] || fail "a make target ran in the refused repo"
  assert_err_has "failed: nobuild"
}

t_repo_without_makefile_is_refused() {
  real_tools
  add_tool nomake -
  run build nomake
  assert_rc 1
  assert_err_has "nomake does not follow the ucli contract (no build target)"
  ! grep -q '^make ' "$SB/calls.log" || fail "make was run in a repo without a Makefile"
}

t_refusal_does_not_depend_on_the_language() {
  real_tools
  add_tool nobuild $'help:\n\t@echo ran > "$(HOME)/help_ran"\n'
  LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 LANGUAGE=de run build nobuild
  assert_rc 1
  assert_err_has "does not follow the ucli contract"
  [[ ! -e "$HOME/help_ran" ]] || fail "the help target ran"
}

t_one_failed_tool_exits_1_and_the_good_one_installs() {
  real_tools
  add_tool bad $'help:\n\t@true\n'
  add_tool good "$(installing_makefile good)"
  run build good bad
  assert_rc 1
  [[ -x "$HOME/.local/bin/good" ]] || fail "good was not installed"
  assert_err_has "built: good; failed: bad (no build target)"
}

t_failing_make_build_exits_1() {
  real_tools
  add_tool broken $'build:\n\t@exit 3\n'
  run build broken
  assert_rc 1
  assert_err_has "failed: broken (make build failed)"
}

t_all_tools_built_exits_0() {
  real_tools
  add_tool one "$(installing_makefile one)"
  add_tool two "$(installing_makefile two)"
  run build one two
  assert_rc 0
  assert_err_has "built: one two; failed: none"
}

# --- build directory --------------------------------------------------------

t_build_dir_is_a_per_user_cache_dir_and_is_removed() {
  real_tools
  add_tool where $'build:\n\t@pwd > "$(HOME)/build_pwd"\n'
  run build where
  assert_rc 0
  case "$(cat "$HOME/build_pwd")" in
    *"$HOME/.cache/ucli/build."*"/where") ;;
    *) fail "built in $(cat "$HOME/build_pwd"), not under \$HOME/.cache/ucli/build.*" ;;
  esac
  assert_eq "$(ls "$HOME/.cache/ucli" | wc -l | tr -d ' ')" "0" "leftovers in the cache dir"
}

t_build_dir_follows_xdg_cache_home() {
  real_tools
  add_tool where $'build:\n\t@pwd > "$(HOME)/build_pwd"\n'
  XDG_CACHE_HOME="$SB/xdg" run build where
  assert_rc 0
  case "$(cat "$HOME/build_pwd")" in
    *"$SB/xdg/ucli/build."*) ;;
    *) fail "XDG_CACHE_HOME ignored: $(cat "$HOME/build_pwd")" ;;
  esac
  assert_eq "$(ls "$SB/xdg/ucli" | wc -l | tr -d ' ')" "0" "leftovers in the cache dir"
}

t_build_dir_is_removed_after_a_failure() {
  real_tools
  add_tool broken $'build:\n\t@exit 1\n'
  run build broken
  assert_rc 1
  assert_eq "$(ls "$HOME/.cache/ucli" | wc -l | tr -d ' ')" "0" "leftovers in the cache dir"
}

t_build_dir_is_removed_when_ucli_exits_on_error() {
  real_tools
  add_tool good "$(installing_makefile good)"
  run build good 'bad name'
  assert_rc 1
  assert_err_has "Invalid repository name"
  assert_eq "$(ls "$HOME/.cache/ucli" | wc -l | tr -d ' ')" "0" "leftovers in the cache dir"
}

t_two_builds_do_not_share_a_directory() {
  real_tools
  add_tool where $'build:\n\t@sleep 0 ; pwd >> "$(HOME)/build_pwd"\n'
  run build where
  run build where
  assert_eq "$(sort -u "$HOME/build_pwd" | wc -l | tr -d ' ')" "2" "distinct build directories"
}

t_traversal_org_is_rejected() {
  real_tools
  add_tool good "$(installing_makefile good)"
  printf '%s\n' '../../escape' > "$HOME/.ucli_env"
  run build good
  assert_rc 1
  assert_err_has "Invalid organization name"
  [[ ! -e "$HOME/.local/bin/good" ]] || fail "built with an invalid org"
  [[ ! -e "$HOME/.cache/escape" && ! -e "$SB/escape" ]] || fail "wrote outside the build dir"
}

t_nothing_is_written_to_tmp_ucli() {
  real_tools
  add_tool where $'build:\n\t@pwd > "$(HOME)/build_pwd"\n'
  run build where
  assert_rc 0
  case "$(cat "$HOME/build_pwd")" in
    /tmp/*) fail "built under /tmp: $(cat "$HOME/build_pwd")" ;;
  esac
}

# --- uv ---------------------------------------------------------------------

t_missing_uv_fails_that_tool_with_the_install_line() {
  real_tools
  add_tool docx2md "$(installing_makefile docx2md)"
  add_tool plain "$(installing_makefile plain)"
  run build docx2md plain
  assert_rc 1
  assert_err_has "docx2md needs uv"
  assert_err_has "curl -LsSf https://astral.sh/uv/install.sh | sh"
  [[ ! -e "$HOME/.local/bin/docx2md" ]] || fail "docx2md built without uv"
  [[ -x "$HOME/.local/bin/plain" ]] || fail "the other tool was not built"
  assert_err_has "built: plain; failed: docx2md (uv missing)"
}

t_mdaudiobook_also_needs_uv() {
  real_tools
  add_tool mdaudiobook "$(installing_makefile mdaudiobook)"
  run build mdaudiobook
  assert_rc 1
  assert_err_has "mdaudiobook needs uv"
}

t_uv_present_lets_docx2md_build() {
  real_tools
  make_stub uv 'exit 0'
  add_tool docx2md "$(installing_makefile docx2md)"
  run build docx2md
  assert_rc 0
  [[ -x "$HOME/.local/bin/docx2md" ]] || fail "docx2md not built"
}

t_uv_in_local_bin_counts_even_when_not_on_path() {
  real_tools
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/uv"
  chmod +x "$HOME/.local/bin/uv"
  add_tool docx2md "$(installing_makefile docx2md)"
  run build docx2md
  assert_rc 0
}

t_prereq_installs_uv_when_absent() {
  ALLOW_SUDO=1
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exec "$@"'
  printf '#!/bin/sh\nmkdir -p "$HOME/.local/bin"\nprintf "#!/bin/sh\\nexit 0\\n" > "$HOME/.local/bin/uv"\nchmod +x "$HOME/.local/bin/uv"\n' > "$SB/uv-install.sh"
  UCLI_UV_INSTALL_URL="file://$SB/uv-install.sh" run prereq
  assert_rc 0
  [[ -x "$HOME/.local/bin/uv" ]] || fail "uv was not installed by prereq"
  assert_err_has "uv installed"
}

run_all
