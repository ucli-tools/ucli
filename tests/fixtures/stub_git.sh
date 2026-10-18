#!/bin/bash
# Stub git for the tests: records every call in $UCLI_TEST_SB/calls.log and pretends
# to fetch/checkout. Switch files in $UCLI_TEST_SB: git_fail_fetch (fetch by SHA fails),
# git_fail_clone (clone fails), git_missing_pin (checkout of a SHA fails).
sb="$UCLI_TEST_SB"
echo "git $*" >> "$sb/calls.log"
last=""
for a in "$@"; do last="$a"; done
case " $* " in
  *" fetch "*)
    [ -f "$sb/git_fail_fetch" ] && exit 1
    echo "$last" > "$sb/git_head" ;;
  *" clone "*)
    [ -f "$sb/git_fail_clone" ] && exit 1
    mkdir -p "$last" ;;
  *" checkout "*)
    if [ "$last" != "FETCH_HEAD" ]; then
      [ -f "$sb/git_missing_pin" ] && exit 1
      echo "$last" > "$sb/git_head"
    fi ;;
  *" rev-parse "*)
    cat "$sb/git_head" 2>/dev/null ;;
esac
exit 0
