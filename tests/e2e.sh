#!/bin/bash
# End to end: the real install path and a real tool build, against real GitHub.
# Not part of `make test` (it needs the network). Run nightly by .github/workflows/e2e.yml.
#
#   HOME must be a scratch directory (the workflow sets one) and E2E_SCRATCH_HOME=1 says so; prerequisite: git, make, curl, uv.
#   E2E_TOOLS    tools to build, space separated (default: mdtexpdf docx2md)
#   E2E_REMOVE   the tool to remove again at the end (default: the last of E2E_TOOLS)
#   E2E_STRICT_PIN=1  also fail when the installed ucli is not the registry's ucli pin, and when
#                `update` fails while moving ucli to that pin. Off until the registry pins a
#                ucli that installs without sudo (the old installer clones main).
#   E2E_INSTALL_URL  the installer (default https://install.ucli.tools/install.sh)
# shellcheck disable=SC2015  # `test && ok || bad`: ok never fails, so bad runs only when the test fails
set -uo pipefail

tools="${E2E_TOOLS:-mdtexpdf docx2md}"
last="${tools##* }"
remove="${E2E_REMOVE:-$last}"
install_url="${E2E_INSTALL_URL:-https://install.ucli.tools/install.sh}"
index_url="${UCLI_E2E_INDEX_URL:-https://raw.githubusercontent.com/ucli-tools/ucli-registry/main/registry/index.tsv}"
fails=0

ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
step() { printf '\n== %s\n' "$1"; }
die()  { bad "$1"; exit 1; }

[[ -n "${E2E_SCRATCH_HOME:-}" ]] || die "refusing to run in HOME=$HOME: set E2E_SCRATCH_HOME=1 to say it is a scratch directory"
export PATH="$HOME/.local/bin:$PATH"
export NO_COLOR=1
# A scratch HOME has no system copy of ucli; make sure a real one on this machine is not used.
export UCLI_LEGACY_BIN="${UCLI_LEGACY_BIN:-$HOME/.no-system-ucli}"
for c in git make curl uv; do command -v "$c" >/dev/null 2>&1 || die "missing prerequisite: $c"; done

index="$(curl -fsSL "$index_url")" || die "cannot read the registry index"
pin_of() { printf '%s\n' "$index" | awk -F '\t' -v n="$1" '$1 == n { print $3 }'; }

step "1. install through the real install path"
curl -fsSL "$install_url" | bash || die "installer failed"
command -v ucli >/dev/null 2>&1 || die "ucli is not on PATH after the install"
[[ -x "$HOME/.local/bin/ucli" ]] && ok "ucli is in \$HOME/.local/bin" || bad "ucli is not in \$HOME/.local/bin"
ver="$(ucli --version 2>&1)"; echo "$ver"
ucli_pin="$(pin_of ucli)"
if [[ -n "$ucli_pin" && "$ver" == *"${ucli_pin:0:7}"* ]]; then
  ok "ucli --version matches the registry pin ${ucli_pin:0:7}"
elif [[ -n "${E2E_STRICT_PIN:-}" ]]; then
  bad "ucli --version ($ver) does not match the registry pin ${ucli_pin:0:7}"
else
  echo "note: ucli --version does not match the registry pin ${ucli_pin:0:7} (not enforced yet)"
fi

step "2. ucli list"
out="$(ucli list 2>&1)" || bad "ucli list failed"
for t in mdtexpdf mdaudiobook docx2md; do
  grep -q "$t" <<<"$out" && ok "list shows $t" || bad "list lacks $t"
done

step "3. ucli build $tools"
# shellcheck disable=SC2086  # one argument per tool
ucli build $tools; rc=$?
[[ $rc -eq 0 ]] && ok "build exited 0" || bad "build exited $rc"
for t in $tools; do
  [[ -x "$HOME/.local/bin/$t" ]] && ok "$t is in \$HOME/.local/bin" || bad "$t is not in \$HOME/.local/bin"
done
vout="$(ucli versions --all 2>&1)"; echo "$vout"
for t in $tools; do
  p="$(pin_of "$t")"
  if grep -q "$t" <<<"$vout" && grep -q "${p:0:12}" <<<"$vout"; then ok "versions --all shows $t at ${p:0:12}"; else bad "versions --all lacks $t at its pin ${p:0:12}"; fi
done

step "4. ucli update"
uout="$(ucli update 2>&1)"; rc=$?; echo "$uout"
if [[ $rc -eq 0 ]]; then
  ok "update exited 0"
elif [[ -z "${E2E_STRICT_PIN:-}" && "$uout" == *"Updating ucli itself"* ]]; then
  # Until the registry pins a ucli that installs without sudo, the self-update step builds
  # the old pinned ucli, which asks for sudo. Not enforced until E2E_STRICT_PIN=1.
  echo "note: update exited $rc while moving ucli to its registry pin (not enforced yet)"
else
  bad "update exited $rc"
fi
for t in $tools; do
  grep -qi "$t.*up to date\|up to date.*$t" <<<"$uout" && ok "$t is up to date" || bad "update does not say $t is up to date"
done

step "5. ucli remove $remove, ucli uninstall"
ucli remove "$remove"; rc=$?
[[ $rc -eq 0 ]] && ok "remove exited 0" || bad "remove exited $rc"
[[ ! -e "$HOME/.local/bin/$remove" ]] && ok "$remove is gone" || bad "$remove is still there"
for t in $tools; do
  [[ "$t" == "$remove" ]] || ucli remove "$t" >/dev/null 2>&1 || true
done
ucli uninstall; rc=$?
[[ $rc -eq 0 ]] && ok "uninstall exited 0" || bad "uninstall exited $rc"
[[ ! -e "$HOME/.local/bin/ucli" ]] && ok "ucli is gone" || bad "ucli is still there"

echo
[[ $fails -eq 0 ]] && echo "E2E PASSED" || echo "E2E FAILED: $fails check(s)"
[[ $fails -eq 0 ]]
