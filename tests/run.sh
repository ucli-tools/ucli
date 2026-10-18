#!/bin/bash
# Runs every tests/test_*.sh (plus the bash-4 grep) and prints a total.
here="$(cd "$(dirname "$0")" && pwd)"
total=0
failed=0
for t in "$here"/test_*.sh; do
  echo "== $(basename "$t")"
  out="$("$t")"; rc=$?
  printf '%s\n' "$out"
  n="$(printf '%s\n' "$out" | sed -n 's/^RESULT \([0-9]*\) passed.*/\1/p')"
  total=$((total + ${n:-0}))
  [[ $rc -eq 0 ]] || failed=$((failed + 1))
done
echo "== check_bash4.sh"
"$here/check_bash4.sh" || failed=$((failed + 1))
echo "TOTAL $total tests passed, $failed failing file(s)"
[[ $failed -eq 0 ]]
