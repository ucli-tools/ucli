#!/bin/bash
# shellcheck disable=SC2016  # test stubs are written as single-quoted scripts
# Test helpers for ucli. Plain bash, bash 3.2 compatible (macOS /bin/bash).
# Every test:
#  - runs ./ucli.sh through its own #!/bin/bash line, never `bash ucli.sh`;
#  - gets a fresh HOME inside tests/.sandbox/ (git-ignored), not a system temp dir;
#  - gets stub git, make, curl, sudo, apt and sleep first on PATH: no network, no sudo;
#  - fails if the real HOME changed, if a stub reported network use, or if sudo ran
#    (unless the test says ALLOW_SUDO=1).

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
UCLI="$ROOT/ucli.sh"
FIXTURE_REGISTRY="file://$TESTS_DIR/fixtures/apps.yaml"
SANDBOX_BASE="$TESTS_DIR/.sandbox"
REAL_HOME="$HOME"
ORIG_PATH="$PATH"

PASS=0
FAIL=0
T_FAILED=0
T_NAME=""
ALLOW_SUDO=0

# Fingerprint of what ucli could touch in the real HOME.
real_home_state() {
  if [[ -e "$REAL_HOME/.ucli_env" ]]; then
    printf 'present:%s\n' "$(cksum < "$REAL_HOME/.ucli_env")"
  else
    echo absent
  fi
}
REAL_STATE_BEFORE="$(real_home_state)"

fail() {
  T_FAILED=1
  echo "    FAIL: $*"
}

assert_rc() { # expected
  [[ "$RC" -eq "$1" ]] || fail "exit code $RC, expected $1 (stderr: $(head -c 300 "$SB/err"))"
}
assert_out_has() { grep -qF -e "$1" "$SB/out" || fail "stdout lacks: $1"; }
assert_out_lacks() { ! grep -qF -e "$1" "$SB/out" || fail "stdout has: $1"; }
assert_err_has() { grep -qF -e "$1" "$SB/err" || fail "stderr lacks: $1"; }
assert_err_lacks() { ! grep -qF -e "$1" "$SB/err" || fail "stderr has: $1"; }
assert_file_has() { # file text
  grep -qF -e "$2" "$1" || fail "$1 lacks: $2"
}
assert_eq() { # actual expected label
  [[ "$1" == "$2" ]] || fail "${3:-value}: got '$1', expected '$2'"
}

make_stub() { # name body
  printf '#!/bin/bash\n%s\n' "$2" > "$SB/bin/$1"
  chmod +x "$SB/bin/$1"
}

setup() {
  T_NAME="$1"
  T_FAILED=0
  ALLOW_SUDO=0
  SB="$SANDBOX_BASE/$T_NAME"
  rm -rf "${SB:?}"
  mkdir -p "$SB/home/.local/bin" "$SB/bin"
  : > "$SB/calls.log"
  : > "$SB/net.log"
  : > "$SB/sudo.log"
  : > "$SB/sleep.log"
  # curl: file:// URLs are served from disk, anything else counts as network use.
  make_stub curl 'url=""
for a in "$@"; do case "$a" in http*|file://*) url="$a" ;; esac; done
echo "curl $*" >> "'"$SB"'/calls.log"
case "$url" in
  file://*) f="${url#file://}"; [ -f "$f" ] && cat "$f" || exit 37 ;;
  *) echo "$url" >> "'"$SB"'/net.log"; exit 6 ;;
esac'
  cp "$TESTS_DIR/fixtures/stub_git.sh" "$SB/bin/git"
  export UCLI_TEST_SB="$SB"
  make_stub make 'echo "make $*" >> "'"$SB"'/calls.log"; exit 0'
  make_stub sudo 'echo "sudo $*" >> "'"$SB"'/sudo.log"; exit 1'
  make_stub apt 'exit 0'
  make_stub sleep 'echo "sleep $*" >> "'"$SB"'/sleep.log"; exit 0'
  export HOME="$SB/home"
  export PATH="$SB/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  export UCLI_REGISTRY_URL="$FIXTURE_REGISTRY"
  export UCLI_GIT_BASE="file://$SB/no-such-git-base"
  export UCLI_NO_SLEEP=1
  mkdir -p "$SB/sysbin"
  export UCLI_INSTALL_DIR="$SB/sysbin"
  unset ORG UCLI_FORCE_FULL_CLONE UCLI_INDEX_URL
}

# registry_with_tools <file> <count>: write a registry with tools tool-1..tool-N
# (pin = 40 hex digits made of the tool number, repo github.com/ucli-tools/tool-N).
write_big_registry() {
  local f="$1" n="$2" i pin
  {
    echo "apps:"
    echo "  official:"
    i=1
    while [[ $i -le $n ]]; do
      pin="$(printf '%040d' "$i")"
      printf '  - name: tool-%s\n    repo: github.com/ucli-tools/tool-%s\n    description: Tool number %s\n    status: production\n    version: %s\n    version_info:\n      commit_date: 2026-01-01\n' "$i" "$i" "$i" "$pin"
      i=$((i + 1))
    done
    echo "  community: []"
  } > "$f"
}

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
  if [[ -n "${3:-}" ]]; then cp "$3" "$r/ucli.sh"; fi
  "${g[@]}" add -A
  "${g[@]}" commit --quiet -m init
  printf '  - name: %s\n    repo: github.com/ucli-tools/%s\n    version: %s\n' \
    "$name" "$name" "$("${g[@]}" rev-parse HEAD)" >> "$SB/reg.yaml"
}

# A Makefile whose first target is help and whose build target installs a script.
installing_makefile() { # name
  printf 'help:\n\t@echo help-ran > "$(HOME)/help_ran"\n\nbuild:\n\t@mkdir -p "$(HOME)/.local/bin"\n\t@printf "#!/bin/sh\\necho %s\\n" > "$(HOME)/.local/bin/%s"\n\t@chmod +x "$(HOME)/.local/bin/%s"\n' "$1" "$1" "$1"
}

# bump_tool <name>: add a commit to the tool's repo and move its registry pin to it.
bump_tool() {
  local name="$1"
  local r="$SB/git/ucli-tools/$name.git"
  local g=("$REAL_GIT" -C "$r" -c user.name=test -c user.email=test@example.invalid)
  local old new
  old="$("${g[@]}" rev-parse HEAD)"
  echo "bump" >> "$r/README"
  "${g[@]}" add -A
  "${g[@]}" commit --quiet -m bump
  new="$("${g[@]}" rev-parse HEAD)"
  sed "s/$old/$new/" "$SB/reg.yaml" > "$SB/reg.yaml.new" && mv "$SB/reg.yaml.new" "$SB/reg.yaml"
}

# pin_of <name>: the tool's current registry pin.
pin_of() {
  "$REAL_GIT" -C "$SB/git/ucli-tools/$1.git" rev-parse HEAD
}

# run [-i stdin-text] args...   runs ./ucli.sh; sets RC; output in $SB/out and $SB/err.
# stdin is /dev/null unless -i is given. A watchdog kills a hang after 20 s.
run() {
  local input=""
  local have_input=0
  if [[ "$1" == "-i" ]]; then have_input=1; input="$2"; shift 2; fi
  (
    if [[ $have_input -eq 1 ]]; then
      printf '%s' "$input" | "$UCLI" "$@" > "$SB/out" 2> "$SB/err"
    else
      "$UCLI" "$@" > "$SB/out" 2> "$SB/err" < /dev/null
    fi
  ) &
  local pid=$!
  ( command -p sleep 20; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watchdog=$!
  wait "$pid"
  RC=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  if [[ $RC -eq 137 ]]; then fail "timed out (hang)"; fi
  return 0
}

finish() {
  [[ -s "$SB/net.log" ]] && fail "network attempted: $(head -n 3 "$SB/net.log" | tr '\n' ' ')"
  if [[ $ALLOW_SUDO -eq 0 && -s "$SB/sudo.log" ]]; then fail "sudo was called: $(head -n 1 "$SB/sudo.log")"; fi
  [[ "$(real_home_state)" == "$REAL_STATE_BEFORE" ]] || fail "real HOME changed"
  if [[ $T_FAILED -eq 0 ]]; then
    PASS=$((PASS + 1)); echo "ok   $T_NAME"
    rm -rf "${SB:?}"
  else
    FAIL=$((FAIL + 1)); echo "FAIL $T_NAME (sandbox kept: $SB)"
  fi
}

# Run every function whose name starts with t_ in the sourcing file.
run_all() {
  local fn
  for fn in $(compgen -A function | grep '^t_' | sort); do
    setup "${fn#t_}"
    "$fn"
    finish
  done
  rmdir "$SANDBOX_BASE" 2>/dev/null
  echo "RESULT $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]]
}
