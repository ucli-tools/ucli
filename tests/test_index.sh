#!/bin/bash
# ucli prefers registry index.tsv, falls back to apps.yaml (slice 11).
. "$(dirname "$0")/helpers.sh"

TAB="$(printf '\t')"
SHA_1=1111111111111111111111111111111111111111
SHA_2=2222222222222222222222222222222222222222
SHA_9=9999999999999999999999999999999999999999

# make_reg: apps.yaml with alpha and beta in $SB/reg/, registry URL pointed at it.
make_reg() {
  mkdir -p "$SB/reg"
  cat > "$SB/reg/apps.yaml" <<YAML
apps:
  official:
  - name: alpha
    repo: github.com/ucli-tools/alpha
    description: Alpha tool
    version: $SHA_1
  - name: beta
    repo: github.com/ucli-tools/beta
    description: Beta tool
    version: $SHA_2
  community: []
YAML
  export UCLI_REGISTRY_URL="file://$SB/reg/apps.yaml"
}

good_index() {
  printf '#name\trepo\tcommit\tkind\nalpha\tgithub.com/ucli-tools/alpha\t%s\tcli\nbeta\tgithub.com/ucli-tools/beta\t%s\tcli\n' "$SHA_1" "$SHA_2" > "$SB/reg/index.tsv"
}

t_index_is_fetched_and_used() {
  make_reg; good_index
  run -i $'\n' list
  assert_rc 0
  assert_out_has "alpha"
  assert_out_has "beta"
  assert_err_lacks "index.tsv"
  assert_file_has "$SB/calls.log" "index.tsv"
  run versions beta
  assert_rc 0
  assert_out_has "$SHA_2"
}

t_index_missing_falls_back_silently() {
  make_reg
  run -i $'\n' list
  assert_rc 0
  assert_out_has "alpha"
  assert_out_has "beta"
  assert_err_lacks "index.tsv"
}

t_list_identical_with_and_without_index() {
  make_reg
  run -i $'\n' list; cp "$SB/out" "$SB/out_noindex"
  good_index
  run -i $'\n' list
  assert_rc 0
  cmp -s "$SB/out" "$SB/out_noindex" || fail "list differs with index.tsv"
}

t_index_disagreeing_pin_uses_apps_yaml_and_warns() {
  make_reg
  printf '#name\trepo\tcommit\tkind\nalpha\tgithub.com/ucli-tools/alpha\t%s\tcli\nbeta\tgithub.com/ucli-tools/beta\t%s\tcli\n' "$SHA_9" "$SHA_2" > "$SB/reg/index.tsv"
  run versions alpha
  assert_rc 0
  assert_out_has "$SHA_1"
  assert_out_lacks "$SHA_9"
  assert_err_has "disagrees with apps.yaml for 'alpha'"
  assert_err_lacks "for 'beta'"
}

t_index_with_extra_tool_is_not_offered() {
  make_reg
  printf '#name\trepo\tcommit\tkind\nalpha\tgithub.com/ucli-tools/alpha\t%s\tcli\nbeta\tgithub.com/ucli-tools/beta\t%s\tcli\nghost\tgithub.com/ucli-tools/ghost\t%s\tcli\n' "$SHA_1" "$SHA_2" "$SHA_9" > "$SB/reg/index.tsv"
  run -i $'\n' list
  assert_rc 0
  assert_out_has "beta"
  assert_out_lacks "ghost"
  assert_err_has "disagrees with apps.yaml for 'ghost'"
}

t_index_missing_a_tool_still_lists_it() {
  make_reg
  printf '#name\trepo\tcommit\tkind\nalpha\tgithub.com/ucli-tools/alpha\t%s\tcli\n' "$SHA_1" > "$SB/reg/index.tsv"
  run -i $'\n' list
  assert_rc 0
  assert_out_has "alpha"
  assert_out_has "beta"
}

t_index_bad_header_is_ignored() {
  make_reg
  printf 'name,repo,commit,kind\nalpha,x,%s,cli\n' "$SHA_9" > "$SB/reg/index.tsv"
  run versions alpha
  assert_rc 0
  assert_out_has "$SHA_1"
  assert_err_has "Ignoring index.tsv (unexpected header)"
}

t_index_malformed_line_is_ignored() {
  make_reg
  printf '#name\trepo\tcommit\tkind\nalpha\tgithub.com/ucli-tools/alpha\tnot-a-sha\tcli\n' > "$SB/reg/index.tsv"
  run versions alpha
  assert_rc 0
  assert_out_has "$SHA_1"
  assert_err_has "Ignoring index.tsv (malformed line)"
}

t_index_url_can_be_overridden() {
  make_reg; good_index
  mv "$SB/reg/index.tsv" "$SB/reg/other.tsv"
  export UCLI_INDEX_URL="file://$SB/reg/other.tsv"
  run -i $'\n' list
  assert_rc 0
  assert_file_has "$SB/calls.log" "other.tsv"
}

run_all
