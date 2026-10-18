#!/usr/bin/env bash
# Menu must not loop when stdin is closed or not a terminal.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
home="${UCLI_TEST_HOME:-/data/build/tmp_ucli_hotfix/home}"
mkdir -p "$home"
fail=0
check() {
  local name="$1"; shift
  local out rc lines
  out="$(HOME="$home" timeout 5 "$@" 2>&1)"; rc=$?
  lines="$(printf '%s\n' "$out" | wc -l)"
  if [[ $rc -eq 124 ]]; then echo "FAIL $name: timed out"; fail=1
  elif [[ $lines -ge 50 ]]; then echo "FAIL $name: $lines output lines"; fail=1
  else echo "ok   $name (exit $rc, $lines lines)"; fi
}
check "echo -n | ucli.sh" bash -c "echo -n | bash '$here/ucli.sh'"
check "ucli.sh </dev/null" bash -c "bash '$here/ucli.sh' </dev/null"
exit $fail
