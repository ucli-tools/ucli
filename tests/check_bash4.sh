#!/bin/bash
# Fails when a script uses a bash 4+ feature. macOS ships /bin/bash 3.2, and
# neither `bash -n` nor shellcheck can catch these. Usage:
#   tests/check_bash4.sh [file...]    (default: ucli.sh and tests/*.sh)
# Exit status: 0 clean, 1 hits found.
here="$(cd "$(dirname "$0")/.." && pwd)"
self="check_bash4.sh"
files=("$@")
if [[ ${#files[@]} -eq 0 ]]; then
  files=("$here/ucli.sh")
  for f in "$here"/tests/*.sh; do
    [[ "$(basename "$f")" == "$self" ]] || files+=("$f")
  done
fi

W='[A-Za-z0-9_]'
labels=(
  "associative array (declare/local/typeset -A)"
  "mapfile/readarray"
  "case conversion \${x,,} \${x^^}"
  "|& pipe"
  ";& or ;;& case terminator"
  "negative array index"
  "namerefs (declare/local -n)"
  "&>> redirect"
  "\${x@Q} style transform"
  "EPOCHSECONDS/EPOCHREALTIME"
  "coproc"
  "[[ -v ]]"
)
patterns=(
  "(declare|local|typeset|readonly)[[:space:]]+-[a-zA-Z]*A"
  "(^|[^A-Za-z0-9_])(mapfile|readarray)($|[^A-Za-z0-9_])"
  "\\\$\\{$W+(,,?|\\^\\^?)[^}]*\\}"
  "\\|&"
  ";;?&"
  "$W\\[[[:space:]]*-[0-9]+[[:space:]]*\\]"
  "(declare|local|typeset)[[:space:]]+-[a-zA-Z]*n"
  "&>>"
  "\\\$\\{$W+@[QEPAaKk]\\}"
  "EPOCHSECONDS|EPOCHREALTIME"
  "(^|[^A-Za-z0-9_])coproc($|[^A-Za-z0-9_])"
  "\\[\\[[[:space:]]+-v[[:space:]]"
)

hits=0
for f in "${files[@]}"; do
  # drop comment-only lines but keep line numbers
  code="$(grep -n . "$f" | grep -vE '^[0-9]+:[[:space:]]*#')"
  i=0
  while [[ $i -lt ${#patterns[@]} ]]; do
    out="$(printf '%s\n' "$code" | grep -E -e "${patterns[$i]}")"
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out" | while IFS= read -r line; do
        echo "BANNED bash-4 feature [${labels[$i]}] in $f:$line"
      done
      hits=$((hits + 1))
    fi
    i=$((i + 1))
  done
done
if [[ $hits -gt 0 ]]; then
  echo "check_bash4: $hits banned feature kind(s) found" >&2
  exit 1
fi
echo "check_bash4: clean (${#files[@]} files)"
