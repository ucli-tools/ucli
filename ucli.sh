#!/bin/bash

# Stamped with the commit by `ucli install`; "dev" when run from a clone.
UCLI_BUILD_ID="dev"

# ANSI colours: only on a terminal, and never when NO_COLOR is set (no-color.org).
# RED/GREEN/YELLOW/NC colour stdout; E_* colour the log functions, which write to stderr.
RED=""; GREEN=""; YELLOW=""; NC=""
E_RED=""; E_GREEN=""; E_YELLOW=""; E_NC=""
if [[ -z "${NO_COLOR:-}" ]]; then
    if [[ -t 1 ]]; then
        RED=$(printf '\033[0;31m'); GREEN=$(printf '\033[0;32m')
        YELLOW=$(printf '\033[0;33m'); NC=$(printf '\033[0m')
    fi
    if [[ -t 2 ]]; then
        E_RED=$(printf '\033[0;31m'); E_GREEN=$(printf '\033[0;32m')
        E_YELLOW=$(printf '\033[0;33m'); E_NC=$(printf '\033[0m')
    fi
fi
ENV_FILE="$HOME/.ucli_env"

# Test seams (defaults are the production values)
UCLI_REGISTRY_URL="${UCLI_REGISTRY_URL:-https://raw.githubusercontent.com/ucli-tools/ucli-registry/main/registry/apps.yaml}"
UCLI_GIT_BASE="${UCLI_GIT_BASE:-https://github.com}"
UCLI_UV_INSTALL_URL="${UCLI_UV_INSTALL_URL:-https://astral.sh/uv/install.sh}"
UCLI_INSTALL_DIR="${UCLI_INSTALL_DIR:-/usr/local/bin}"

# Pause used by the logging functions: only inside the interactive menu
# (UCLI_MENU=1), so a person can read each message; UCLI_NO_SLEEP=1 disables it.
nap() {
    [[ -n "${UCLI_MENU:-}" && -z "${UCLI_NO_SLEEP:-}" ]] || return 0
    sleep 1
}

# Logging functions for consistent output formatting
log() {
    echo -e "${E_GREEN}[UPDATE]${E_NC} $1" >&2
    nap
}

warn() {
    echo -e "${E_YELLOW}[WARNING]${E_NC} $1" >&2
    nap
}

error() {
    echo -e "${E_RED}[ERROR]${E_NC} $1" >&2
    nap
    exit 1
}

# Function to check if a string is a valid repository name (alphanumeric and hyphens)
is_valid_repo_name() {
  [[ "$1" =~ ^[a-zA-Z0-9-]+$ ]]
}

# The version: the stamped commit, or "dev" (with the short commit of a clone).
show_version() {
  local id="$UCLI_BUILD_ID" d c
  if [[ "$id" == "dev" ]]; then
    d="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
    c="$(git -C "$d" rev-parse --short HEAD 2>/dev/null)"
    if [[ "$c" =~ ^[0-9a-f]{7,40}$ ]]; then id="dev ($c)"; fi
  fi
  printf 'ucli %s\n' "$id"
}

# The command list alone (short: this is what a script or a closed stdin gets).
show_commands() {
  printf "${GREEN}UCLI - Universal Command Line Interface Tool${NC}\n"
  printf "Commands:\n"
  printf "  ${GREEN}install${NC}                Install ucli to /usr/local/bin\n"
  printf "  ${GREEN}uninstall${NC}              Remove ucli from /usr/local/bin\n"
  printf "  ${GREEN}login [organization]${NC}   Set GitHub organization (defaults to ucli-tools if not specified)\n"
  printf "                           If already logged in, switches to the specified organization\n"
  printf "  ${GREEN}logout${NC}                 Unset GitHub organization\n"
  printf "  ${GREEN}list${NC}                   List official tools from UCLI Registry\n"
  printf "  ${GREEN}versions [tool]${NC}         Show version information for tools\n"
  printf "                           Use 'versions --all' for all tools, 'versions <tool>' for specific\n"
  printf "  ${GREEN}build repo1 repo2...${NC}   Build tools from specified GitHub repositories\n"
  printf "                           Example: ucli build ucli gits\n"
  printf "  ${GREEN}build-all${NC}              Build all tools listed by 'ucli list'\n"
  printf "  ${GREEN}update${NC}                 Update all installed tools\n"
  printf "  ${GREEN}prereq${NC}                 Install prerequisites (Ubuntu/Debian)\n"
  printf "  ${GREEN}help${NC}                   Show this help message (also --help, -h)\n"
  printf "  ${GREEN}version${NC}                Show the ucli version (also --version)\n"
}

# Help function. "menu" as the first argument pauses afterwards (interactive menu only).
show_help() {
  printf "\n"
  show_commands
  printf "\n${YELLOW}Features:${NC}\n"
  printf "  - Registry-based tool discovery via ${GREEN}registry.ucli.tools${NC}\n"
  printf "  - Default login to ${GREEN}ucli-tools${NC} organization\n"
  printf "  - Command-line interface for all operations\n"
  printf "  - Interactive menu mode\n"
  printf "  - Automatic tool building from GitHub repositories\n\n"

  printf "${YELLOW}Examples:${NC}\n"
  printf "  ${GREEN}ucli${NC}                   Run in interactive mode\n"
  printf "  ${GREEN}ucli login ucli-tools${NC}  Log in to ucli-tools organization\n"
  printf "  ${GREEN}ucli build ucli${NC}        Build the ucli tool itself\n"
  printf "  ${GREEN}ucli list${NC}              List official tools from registry\n\n"

  printf "${YELLOW}Interactive mode: Run 'ucli' without arguments\n\n${NC}"
  printf "License: Apache 2.0\n"
  printf "Registry: https://registry.ucli.tools\n"
  printf "Repository: https://github.com/ucli-tools/ucli\n\n"
  if [[ "${1:-}" == "menu" ]]; then
    read -r -p "${YELLOW}Press ENTER to return to main menu...${NC}" || true
  fi
}

# Install script. Atomic: the new file is written next to the target (same
# directory, so the final mv is a rename) and moved into place; the running script
# is never overwritten in place, and a failed step leaves the old binary untouched.
install() {
  local dir="$UCLI_INSTALL_DIR" tmp id sd
  if [[ ! -d "$dir" ]]; then
    if sudo mkdir -p "$dir"; then
      log "Directory $dir created successfully."
    else
      error "Error creating directory $dir."
    fi
  fi
  tmp="$dir/.ucli.new.$$"
  # Stamp the commit when run from a git clone (a checkout of the pinned commit).
  sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  id="$(git -C "$sd" rev-parse HEAD 2>/dev/null)"
  [[ "$id" =~ ^[0-9a-f]{7,40}$ ]] || id=""
  if sudo cp "$0" "$tmp" \
     && { [[ -z "$id" ]] || sed "s/^UCLI_BUILD_ID=.*/UCLI_BUILD_ID=\"$id\"/" "$0" | sudo tee "$tmp" > /dev/null; } \
     && sudo chmod +x "$tmp" && sudo mv -f "$tmp" "$dir/ucli"; then
      log "ucli installed to $dir."
  else
      sudo rm -f "$tmp" > /dev/null 2>&1
      error "Error installing ucli."
  fi
}

# Uninstall script
uninstall() {
  if [[ -f "/usr/local/bin/ucli" ]]; then
    if sudo rm /usr/local/bin/ucli; then
      log "ucli successfully uninstalled."
    else
      error "Error uninstalling ucli."
    fi
  else
    warn "ucli is not installed in /usr/local/bin."
  fi
}

# Login
login() {
  # Check if an organization name was provided as an argument
  local new_org="$1"
  local current_org=""
  
  # If we have an existing login, read it
  if [[ -f "$ENV_FILE" ]]; then
    if read -r current_org < "$ENV_FILE" && [[ -n "$current_org" ]]; then
      # We have a valid current login
      if [[ -n "$new_org" ]]; then
        # If a new org was specified and it's different, switch to it
        if [[ "$current_org" != "$new_org" ]]; then
          log "Switching from $current_org to $new_org"
          printf "%s\n" "$new_org" > "$ENV_FILE"
          log "Logged in as $new_org"
          return 0
        else
          # Already logged in to the requested org
          log "Already logged in as $new_org"
          return 0
        fi
      fi
      # No new org specified, but we're already logged in
      log "Currently logged in as $current_org"
      read -r -p "Enter new organization (or press ENTER to keep $current_org): " new_org || { echo "No input; run 'ucli help'."; exit 1; }
      if [[ -z "$new_org" ]]; then
        log "Keeping current login as $current_org"
        return 0
      fi
    else
      warn "Existing $ENV_FILE is corrupted. Overwriting..."
      # Continue to prompt for a new org
    fi
  fi

  # If we get here, either there's no login file, it's corrupted, or user wants to change
  if [[ -z "$new_org" ]]; then
    # No org provided as argument, prompt for one
    while true; do
      read -r -p "User/Organization (required): " new_org || { echo "No input; run 'ucli help'."; exit 1; }
      if [[ -z "$new_org" ]]; then
        warn "Organization name cannot be empty."
      else
        break
      fi
    done
  fi
  
  # Use printf to ensure proper file writing, even with special characters
  printf "%s\n" "$new_org" > "$ENV_FILE"
  log "Logged in as $new_org"
  return 0
}

# Check login
check_login() {
  if [[ ! -f "$ENV_FILE" ]]; then
    # Set default login to ucli-tools if no login exists
    log "No login found. Setting default organization to ucli-tools."
    printf "%s\n" "ucli-tools" > "$ENV_FILE"
    ORG="ucli-tools"
    return 0
  fi

  if ! read -r ORG < "$ENV_FILE" || [[ -z "$ORG" ]]; then
    warn "Error reading or invalid organization in $ENV_FILE. Setting default to ucli-tools."
    rm -f "$ENV_FILE" # Remove the corrupted file
    printf "%s\n" "ucli-tools" > "$ENV_FILE"
    ORG="ucli-tools"
    return 0
  fi
  return 0
}

# Logout function
logout() {
  if [[ -f "$ENV_FILE" ]]; then
    rm "$ENV_FILE"
    log "Successfully logged out."
  else
    warn "You are not currently logged in."
  fi
}

# Function to clean up temporary directories
cleanup() {
    local tmpdir="$1"
    if [[ -d "$tmpdir" ]]; then
        rm -rf "$tmpdir"
        if [[ $? -ne 0 ]]; then
            warn "Failed to clean up $tmpdir. You may need to remove it manually."
        fi
    fi
}

# Registry access. The registry is fetched once per command (REGISTRY_CACHE) and
# parsed by one awk pass that only looks inside the `official:` list: `community:`,
# `templates:` and anything else is never offered, and tool names match exactly.
REGISTRY_CACHE=""

# Load the registry into REGISTRY_CACHE. Returns 1 (and prints nothing) on failure,
# so callers decide how to report it. Call it in the main shell, not in $(...).
registry_load() {
    [[ -n "$REGISTRY_CACHE" ]] && return 0
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed."
    fi
    local yaml_content
    yaml_content=$(curl -s "$UCLI_REGISTRY_URL" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$yaml_content" ]]; then
        return 1
    fi
    REGISTRY_CACHE="$yaml_content"
    return 0
}

# registry_awk names | registry_awk field <tool> <key>
# Reads REGISTRY_CACHE. Only entries of the `official:` list are considered; an
# entry's own keys are the ones one level inside its `- name:` line.
registry_awk() {
    printf '%s\n' "$REGISTRY_CACHE" | awk -v mode="$1" -v tool="$2" -v key="$3" '
    function clean(v) {
        sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
        if (v ~ /^".*"$/ || v ~ /^'"'"'.*'"'"'$/) v = substr(v, 2, length(v) - 2)
        return v
    }
    {
        sub(/\r$/, "")
        if ($0 ~ /^[ \t]*#/) next
        match($0, /^ */); ind = RLENGTH
        rest = substr($0, ind + 1)
        if (rest == "") next
        if (!insec) {
            if (rest ~ /^official:[ \t]*$/) { insec = 1; secind = ind; cur = "" }
            next
        }
        if (ind <= secind && rest !~ /^-/) { insec = 0; cur = ""; next }
        if (rest ~ /^-[ \t]*name:/) {
            v = rest; sub(/^-[ \t]*name:/, "", v)
            cur = clean(v); dashind = ind
            if (mode == "names") print cur
            next
        }
        if (mode == "field" && cur == tool) {
            if (ind == dashind + 2) {
                parent = rest; sub(/:.*/, "", parent)
                if (index(key, ".") == 0 && index(rest, key ":") == 1) {
                    v = rest; sub(/^[^:]*:/, "", v)
                    print clean(v)
                    exit
                }
            } else if (ind > dashind + 2 && index(key, ".") > 0 && (parent "." ) == substr(key, 1, length(parent) + 1) \
                       && index(rest, substr(key, length(parent) + 2) ":") == 1) {
                v = rest; sub(/^[^:]*:/, "", v)
                print clean(v)
                exit
            }
        }
    }'
}

# Function to fetch repositories from UCLI Registry
fetch_repos() {
    log "Fetching tools from UCLI Registry..."

    if ! registry_load; then
        error "Failed to fetch registry data"
    fi

    local repos
    repos=$(registry_awk names | sort)

    if [[ -z "$repos" ]]; then
        warn "No tools found in registry"
        return 1
    fi

    echo "$repos"
    return 0
}

# registry_field <tool> <key>: first value of <key> in the tool's official entry.
registry_field() {
    is_valid_repo_name "$1" || return 1
    registry_awk field "$1" "$2"
}

# Function to get tool version (the pinned commit) from registry
get_tool_version() {
    local tool_name="$1"
    if ! registry_load; then
        warn "Failed to fetch registry data"
        return 1
    fi

    local version
    version=$(registry_field "$tool_name" version)

    if [[ -z "$version" ]]; then
        warn "Could not find version for tool: $tool_name (not an official tool in the registry)"
        return 1
    fi
    if ! [[ "$version" =~ ^[0-9a-f]{40}$ ]]; then
        warn "Registry pin for $tool_name is not a full 40-character commit hash: $version"
        return 1
    fi

    echo "$version"
}

# Clone URL for a tool, built from the `repo:` field of its registry entry.
get_tool_clone_url() {
    local repo_field
    repo_field=$(registry_field "$1" repo)
    if [[ -z "$repo_field" ]]; then
        warn "Registry entry for $1 has no repo: field"
        return 1
    fi
    repo_field="${repo_field#https://}"
    repo_field="${repo_field#http://}"
    repo_field="${repo_field%.git}"
    repo_field="${repo_field%/}"
    if [[ "$repo_field" == github.com/* ]]; then
        echo "$UCLI_GIT_BASE/${repo_field#github.com/}.git"
    else
        echo "https://$repo_field.git"
    fi
}

# fetch_pinned <dir> <url> <sha>: leave <dir> checked out (detached) at exactly <sha>.
# Fast path: git init + fetch --depth 1 of the SHA. If that fails (git older than
# 2.26, or a server that refuses a fetch by SHA), fall back to a full clone.
# UCLI_FORCE_FULL_CLONE=1 forces the fallback (used by the tests).
fetch_pinned() {
    local dir="$1" url="$2" sha="$3"
    if [[ -z "${UCLI_FORCE_FULL_CLONE:-}" ]]; then
        rm -rf "${dir:?}"
        mkdir -p "$dir" || return 1
        if git -C "$dir" init --quiet 2>/dev/null \
            && git -C "$dir" remote add origin "$url" 2>/dev/null \
            && git -C "$dir" fetch --quiet --depth 1 origin "$sha" 2>/dev/null \
            && git -C "$dir" checkout --quiet --detach FETCH_HEAD 2>/dev/null \
            && [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" == "$sha" ]]; then
            return 0
        fi
        warn "Fetching $sha directly failed; trying a full clone instead."
    fi
    rm -rf "${dir:?}"
    if ! git clone --quiet "$url" "$dir" 2>/dev/null; then
        warn "Could not clone $url"
        return 1
    fi
    if ! git -C "$dir" checkout --quiet --detach "$sha" 2>/dev/null; then
        warn "Pinned commit $sha does not exist in $url"
        return 1
    fi
    if [[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$sha" ]]; then
        warn "Checked out commit does not match the pin $sha"
        return 1
    fi
    return 0
}

# Function to install prerequisites
install_prerequisites() {
    log "Installing prerequisites..."
    if ! command -v apt &> /dev/null; then
        error "This function only works on Debian/Ubuntu systems"
    fi

    if sudo apt update && sudo apt install -y make git curl file tree; then
        log "Prerequisites installed successfully"
    else
        error "Failed to install prerequisites"
    fi

    # uv (needed by docx2md and mdaudiobook), installed for the user, no sudo
    if have_uv; then
        log "uv is already installed"
    elif curl -LsSf "$UCLI_UV_INSTALL_URL" | sh; then
        log "uv installed"
    else
        warn "Could not install uv. Install it yourself: curl -LsSf $UCLI_UV_INSTALL_URL | sh"
    fi
}

# Function to list repositories. "menu" as the first argument pauses afterwards.
list_repos() {
    local menu="${1:-}"
    log "Fetching repositories for $ORG..."
    registry_load || error "Failed to fetch registry data"
    local repos
    repos=$(fetch_repos)

    if [[ $? -ne 0 ]]; then
        warn "Failed to fetch repository data"
        if [[ "$menu" == "menu" ]]; then
            read -n 1 -s -r -p "Press ENTER to return to main menu..." || { echo "No input; run 'ucli help'."; exit 1; }
        fi
        return 1
    fi

    echo "$repos"
    log "Repository list displayed"
    if [[ "$menu" == "menu" ]]; then
        log "Press ENTER to return to main menu..."
        read -r || { echo "No input; run 'ucli help'."; exit 1; }
    fi
    return 0
}

# Tools that need uv before they can be built
tool_needs_uv() {
    case "$1" in
        docx2md|mdaudiobook) return 0 ;;
        *) return 1 ;;
    esac
}

# uv may sit in ~/.local/bin or ~/.cargo/bin without being on PATH yet
have_uv() {
    command -v uv > /dev/null 2>&1 || [[ -x "$HOME/.local/bin/uv" ]] || [[ -x "$HOME/.cargo/bin/uv" ]]
}

# Build directory of the running command (global: the EXIT trap cannot see locals)
UCLI_BUILD_DIR=""

# Build one or more tools. Each tool is fetched at its registry pin and built with
# `make build` (never any other make goal). Exit 0 only if every tool built.
fetch_and_run() {
    if ! check_login; then
        return 1
    fi
    if ! is_valid_repo_name "$ORG"; then
        error "Invalid organization name: $ORG. Only alphanumeric characters and hyphens are allowed."
    fi

    local original_dir
    original_dir=$(pwd)
    local rc=0 built="" failed="" reason

    # Per-user cache dir, unique per run, removed when the command ends (even on error)
    local cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/ucli"
    if ! mkdir -p "$cache_root"; then
        error "Error creating build directory $cache_root"
    fi
    UCLI_BUILD_DIR=$(mktemp -d "$cache_root/build.XXXXXX") || error "Error creating a build directory in $cache_root"
    trap 'cleanup "$UCLI_BUILD_DIR"' EXIT

    # One registry fetch for the whole command
    registry_load || error "Failed to fetch registry data"

    local repo
    for repo in "$@"; do
        if [[ "$repo" == .* ]]; then
            warn "Repository '$repo' starts with a dot and will be skipped."
            continue # Skip to the next repository
        fi

        if ! is_valid_repo_name "$repo"; then
            error "Invalid repository name: $repo. Only alphanumeric characters and hyphens are allowed."
        fi

        cd "$original_dir" || error "Error changing to original directory"

        if tool_needs_uv "$repo" && ! have_uv; then
            warn "$repo needs uv, which is not installed. Install it with: curl -LsSf $UCLI_UV_INSTALL_URL | sh   (or run: ucli prereq)"
            failed="$failed $repo (uv missing)"
            rc=1
            continue
        fi

        # Pinned commit and clone URL come from the registry entry
        local version url
        if ! version=$(get_tool_version "$repo") || ! url=$(get_tool_clone_url "$repo"); then
            warn "Cannot build ${repo}. Skipping..."
            failed="$failed $repo (not in registry or bad entry)"
            rc=1
            continue
        fi

        # Fetch exactly the pinned commit (not whatever main is today)
        if ! fetch_pinned "$UCLI_BUILD_DIR/$repo" "$url" "$version"; then
            warn "Error fetching ${repo} at ${version}. Skipping..."
            failed="$failed $repo (fetch failed)"
            rc=1
            continue
        fi

        cd "$UCLI_BUILD_DIR/$repo" || {
            error "Error changing to directory $UCLI_BUILD_DIR/$repo"
        }

        log "Building ${repo} (v${version:0:8})..."

        # The contract is `make build`: a Makefile must exist and know the target.
        # Decided by exit status, never by reading make's message.
        reason=""
        if [[ ! -f Makefile && ! -f makefile && ! -f GNUmakefile ]]; then
            reason="no Makefile"
        elif ! LC_ALL=C make -n build > /dev/null 2>&1; then
            reason="no build target"
        fi
        if [[ -n "$reason" ]]; then
            warn "$repo does not follow the ucli contract (no build target): $reason. Nothing was run."
            failed="$failed $repo ($reason)"
            rc=1
            continue
        fi

        log "Running make build in $repo..."
        if ! make build; then
            warn "Error executing make build in $repo. Skipping..."
            failed="$failed $repo (make build failed)"
            rc=1
            continue
        fi

        log "Build successful for $repo!"
        local where
        if [[ "$repo" == "ucli" ]]; then where="$UCLI_INSTALL_DIR/ucli"; else where=$(tool_path "$repo" || echo "$(user_bin_dir)/$repo"); fi
        state_record "$repo" "$version" "$where"
        built="$built $repo"
    done

    # Clean up at the end
    cd "$original_dir" || error "Error returning to original directory"
    cleanup "$UCLI_BUILD_DIR"
    trap - EXIT

    log "built:${built:- none}; failed:${failed:- none}"
    return $rc
}

# Installed-state record: name<TAB>commit<TAB>date<TAB>path, one line per tool.
ucli_state_file() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/ucli/installed.tsv"
}

user_bin_dir() {
    echo "${XDG_BIN_HOME:-$HOME/.local/bin}"
}

# state_has <name>: 0 when the tool has a record.
state_has() {
    local f
    f=$(ucli_state_file)
    [[ -f "$f" ]] && awk -F '\t' -v n="$1" '$1 == n { found = 1 } END { exit !found }' "$f"
}

# state_field <name> <column>: the field of the tool's record (empty if none).
state_field() {
    local f
    f=$(ucli_state_file)
    [[ -f "$f" ]] || return 0
    awk -F '\t' -v n="$1" -v c="$2" '$1 == n { print $c; exit }' "$f"
}

# state_record <name> <commit> [path]: replace the tool's line. The file is
# rewritten through a temp file in the same directory and mv'd into place.
state_record() {
    local name="$1" commit="$2" path="${3:-}" f dir tmp
    f=$(ucli_state_file)
    dir=$(dirname "$f")
    mkdir -p "$dir" || { warn "Could not create $dir to record $name"; return 1; }
    tmp=$(mktemp "$dir/.installed.XXXXXX") || { warn "Could not record $name"; return 1; }
    {
        [[ -f "$f" ]] && awk -F '\t' -v n="$name" '$1 != n && $1 != "ms2md"' "$f"
        printf '%s\t%s\t%s\t%s\n' "$name" "$commit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$path"
    } > "$tmp" && mv -f "$tmp" "$f" || { rm -f "$tmp"; warn "Could not record $name"; return 1; }
}

# legacy_tool_path <name>: path of a pre-existing install, found with command -v
# only when it lives in the system bin dir or the user bin dir.
legacy_tool_path() {
    local found
    found=$(command -v "$1" 2>/dev/null) || return 1
    [[ "$found" == /* ]] || return 1
    if [[ "$found" == "$UCLI_INSTALL_DIR/$1" || "$found" == "$(user_bin_dir)/$1" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

# Function to check if a tool is installed: listed in the state file, or an older
# install found in an allowed directory (never an unrelated program elsewhere).
is_tool_installed() {
    state_has "$1" || legacy_tool_path "$1" > /dev/null
}

# tool_path <name>: where the tool lives (best effort, may be empty).
tool_path() {
    local p
    if p=$(legacy_tool_path "$1"); then echo "$p"; return 0; fi
    p=$(state_field "$1" 4)
    [[ -n "$p" ]] && { echo "$p"; return 0; }
    return 1
}

# Installed official tools, one per line. Needs the registry loaded.
get_installed_tools() {
    local tool
    registry_awk names | sort | while IFS= read -r tool; do
        if is_tool_installed "$tool"; then echo "$tool"; fi
    done
}

# installed_commit <name>: recorded commit, or empty when unknown.
installed_commit() {
    state_field "$1" 2
}

# Update: ucli updates itself first (and hands over to the new file), then only
# tools whose recorded commit differs from the registry pin are rebuilt.
update_tools() {
    log "Fetching repository list..."
    registry_load || error "Failed to fetch registry data"
    local repos
    repos=$(fetch_repos)

    if [[ $? -ne 0 ]]; then
        error "Failed to fetch repository data"
    fi

    local rc=0 tool pin rec
    local to_build=()

    # Self-update first
    if [[ -z "${UCLI_SELF_UPDATED:-}" ]] && printf '%s\n' "$repos" | grep -Fxq -- ucli \
        && is_tool_installed ucli; then
        pin=$(get_tool_version ucli) || pin=""
        rec=$(installed_commit ucli)
        if [[ -n "$pin" && "$pin" != "$rec" ]]; then
            log "Updating ucli itself first..."
            if fetch_and_run ucli; then
                log "ucli updated; continuing with the new version."
                UCLI_SELF_UPDATED=1 exec "$UCLI_INSTALL_DIR/ucli" update
            fi
            rc=1
        fi
    fi

    local found=0
    for tool in $repos; do
        [[ "$tool" == "ucli" ]] && continue
        is_tool_installed "$tool" || continue
        found=$((found + 1))
        pin=$(get_tool_version "$tool") || { rc=1; continue; }
        rec=$(installed_commit "$tool")
        if [[ "$pin" == "$rec" ]]; then
            log "$tool is up to date (${pin:0:8})."
        else
            to_build+=("$tool")
        fi
    done

    if [[ $found -eq 0 && $rc -eq 0 ]]; then
        warn "No installed tools found to update"
        return 0
    fi

    if [[ ${#to_build[@]} -gt 0 ]]; then
        log "Rebuilding ${#to_build[@]} tool(s): ${to_build[*]}"
        fetch_and_run "${to_build[@]}" || rc=1
    fi

    log "Update completed!"
    return $rc
}

# Function to build all repositories
build_all_repos() {
    log "Fetching repository list..."
    registry_load || error "Failed to fetch registry data"
    local repos
    repos=$(fetch_repos)

    if [[ $? -ne 0 ]]; then
        error "Failed to fetch repository data"
    fi

    if [[ -z "$repos" ]]; then
        warn "No repositories found to build"
        return 0
    fi

    local repo_count=$(echo "$repos" | wc -l)
    log "Found $repo_count repositories. Starting build process..."

    # Convert newline-separated list to space-separated for fetch_and_run
    repos=$(echo "$repos" | tr '\n' ' ')
    
    fetch_and_run $repos
    
    log "Build-all completed!"
}

# Function to show version information
show_versions() {
    local tool_arg="$1"

    if [[ "$tool_arg" == "--all" ]]; then
        # Show all installed tools with their versions
        printf "${GREEN}Installed UCLI Tools and Versions:${NC}\n"
        printf "==================================\n\n"

        registry_load || true
        local installed_tools
        installed_tools=$(get_installed_tools 2>/dev/null)

        if [[ -z "$installed_tools" ]]; then
            printf "${YELLOW}No UCLI tools are currently installed.${NC}\n"
            printf "Use ${GREEN}ucli build <tool>${NC} to install tools.\n"
            return 0
        fi

        local tool pin rec note
        for tool in $installed_tools; do
            pin=$(get_tool_version "$tool" 2>/dev/null || echo "unknown")
            rec=$(installed_commit "$tool")
            if [[ -z "$rec" ]]; then
                note="installed, commit unknown; update available"
            elif [[ "$rec" == "$pin" ]]; then
                note="installed ${rec:0:12}; up to date"
            else
                note="installed ${rec:0:12}; update available"
            fi
            printf "${GREEN}%-15s${NC} pin %s  %s\n" "$tool:" "${pin:0:12}" "$note"
        done

    elif [[ -n "$tool_arg" ]]; then
        # Show specific tool version info
        printf "${GREEN}Version Information for '${tool_arg}':${NC}\n"
        printf "=====================================\n\n"

        # Check if tool exists in registry
        registry_load || true
        local official_tools
        official_tools=$(fetch_repos 2>/dev/null)
        if ! echo "$official_tools" | grep -Fxq -- "${tool_arg}"; then
            printf "${RED}Tool '${tool_arg}' not found in UCLI Registry.${NC}\n"
            printf "Use ${GREEN}ucli list${NC} to see available tools.\n"
            return 1
        fi

        # Get detailed version info from registry (already loaded by fetch_repos)
        local version description repo status
        version=$(registry_field "$tool_arg" version)
        description=$(registry_field "$tool_arg" description)
        repo=$(registry_field "$tool_arg" repo)
        status=$(registry_field "$tool_arg" status)

        # Extract version_info if available
        local commit_date commit_message commit_url

        commit_date=$(registry_field "$tool_arg" version_info.commit_date)
        commit_message=$(registry_field "$tool_arg" version_info.commit_message)
        commit_url=$(registry_field "$tool_arg" version_info.commit_url)

        printf "${YELLOW}Name:${NC}         ${tool_arg}\n"
        printf "${YELLOW}Version:${NC}      ${version:-unknown}\n"
        printf "${YELLOW}Status:${NC}       ${status:-unknown}\n"
        printf "${YELLOW}Repository:${NC}   ${repo:-unknown}\n"

        if [[ -n "$description" ]]; then
            printf "${YELLOW}Description:${NC}  ${description}\n"
        fi

        if [[ -n "$commit_date" ]]; then
            printf "${YELLOW}Commit Date:${NC}  ${commit_date}\n"
        fi

        if [[ -n "$commit_message" ]]; then
            printf "${YELLOW}Last Commit:${NC}  ${commit_message}\n"
        fi

        if [[ -n "$commit_url" ]]; then
            printf "${YELLOW}Commit URL:${NC}   ${commit_url}\n"
        fi

        printf "\n"

        # Check if tool is installed locally
        if is_tool_installed "$tool_arg"; then
            local irec ipath
            irec=$(installed_commit "$tool_arg")
            ipath=$(tool_path "$tool_arg" || true)
            printf "${GREEN}✓ Tool is installed locally${NC}\n"
            printf "${YELLOW}Pin:${NC}          ${version:-unknown}\n"
            if [[ -z "$irec" ]]; then
                printf "${YELLOW}Installed:${NC}    installed, commit unknown\n"
            else
                printf "${YELLOW}Installed:${NC}    ${irec}\n"
            fi
            printf "${YELLOW}Path:${NC}         ${ipath:-unknown}\n"
            if [[ "$irec" != "$version" ]]; then
                printf "${YELLOW}Update available:${NC} yes (run: ucli update)\n"
            else
                printf "${GREEN}Up to date${NC}\n"
            fi
        else
            printf "${YELLOW}⚠ Tool is not installed locally${NC}\n"
            printf "   Install with: ${GREEN}ucli build ${tool_arg}${NC}\n"
        fi

    else
        printf "${RED}Usage: ucli versions <tool-name> or ucli versions --all${NC}\n"
        printf "Examples:\n"
        printf "  ${GREEN}ucli versions gits${NC}     - Show version info for gits\n"
        printf "  ${GREEN}ucli versions --all${NC}    - Show all installed tools\n"
        return 1
    fi
}

# Main function
main() {
  if [[ -z "$1" ]]; then # Interactive mode
    if [[ ! -t 0 ]]; then
      show_commands
      printf "Run 'ucli help' for details.\n"
      exit 2
    fi
    UCLI_MENU=1
    while true; do
      clear
      printf "${GREEN}Welcome to UCLI, the Universal Command Line Interface Tool!${NC}\n\n"
      printf "${YELLOW}Select an option by entering its number or name:${NC}\n\n"
      printf "  1. ${GREEN}login${NC}     - Set your GitHub organization (default: ucli-tools)\n"
      printf "  2. ${GREEN}build${NC}     - Build a tool from a GitHub repository\n"
      printf "  3. ${GREEN}build-all${NC} - Build all tools listed by 'ucli list'\n"
      printf "  4. ${GREEN}list${NC}      - List official tools from registry\n"
      printf "  5. ${GREEN}logout${NC}    - Unset your GitHub organization\n"
      printf "  6. ${GREEN}help${NC}      - Show help information\n"
      printf "  7. ${GREEN}update${NC}    - Update all installed tools\n"
      printf "  8. ${GREEN}prereq${NC}    - Install prerequisites (Ubuntu/Debian)\n"
      printf "  9. ${GREEN}versions${NC}  - Show version information for tools\n"
      printf "  10. ${GREEN}exit${NC}     - Exit ucli\n\n"

      read -r -p "Enter your choice: " choice || { echo "No input; run 'ucli help'."; exit 1; }

      case "$choice" in
        1|login)
          read -r -p "Organization name (leave empty to be prompted): " org_name || { echo "No input; run 'ucli help'."; exit 1; }
          login "$org_name" ;;
        2|build)
          read -r -p "Repository names (space-separated): " repos || { echo "No input; run 'ucli help'."; exit 1; }
          fetch_and_run $repos ;;
        3|build-all) build_all_repos ;;
        4|list) list_repos menu ;;
        5|logout) logout ;;
        6|help) show_help menu ;;
        7|update) update_tools ;;
        8|prereq) install_prerequisites ;;
        9|versions)
          read -r -p "Tool name (or --all for all installed tools): " tool_name || { echo "No input; run 'ucli help'."; exit 1; }
          show_versions "$tool_name" ;;
        10|exit) exit 0 ;;
        *) printf "${RED}Invalid choice. Try 'help' for more information.${NC}\n" ;;
      esac
    done
  else # Command-line mode
    case "$1" in
      install) install ;;
      uninstall) uninstall ;;
      login) login "$2" ;;
      logout) logout ;;
      list) list_repos ;;
      versions) show_versions "$2" ;;
      build) shift; fetch_and_run "$@" ;; # Remove 'build' and pass remaining args
      build-all) build_all_repos ;;
      update) update_tools ;;
      prereq) install_prerequisites ;;
      help|--help|-h) show_help ;;
      version|--version|-V) show_version ;;
      *) printf "${RED}Invalid command. Use 'ucli help' for usage information.\n${NC}"; exit 1 ;;
    esac
  fi
}

main "$@"; exit $?
