#!/bin/bash

# ANSI color codes
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[0;33m')
NC=$(printf '\033[0m')
ENV_FILE="$HOME/.ucli_env"

# Test seams (defaults are the production values)
UCLI_REGISTRY_URL="${UCLI_REGISTRY_URL:-https://raw.githubusercontent.com/ucli-tools/ucli-registry/main/registry/apps.yaml}"
UCLI_GIT_BASE="${UCLI_GIT_BASE:-https://github.com}"
UCLI_UV_INSTALL_URL="${UCLI_UV_INSTALL_URL:-https://astral.sh/uv/install.sh}"

# Pause used by the logging functions; UCLI_NO_SLEEP=1 disables it
nap() {
    [[ -n "${UCLI_NO_SLEEP:-}" ]] || sleep 1
}

# Logging functions for consistent output formatting
log() {
    echo -e "${GREEN}[UPDATE]${NC} $1" >&2
    nap
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
    nap
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    nap
    exit 1
}

# Function to check if a string is a valid repository name (alphanumeric and hyphens)
is_valid_repo_name() {
  [[ "$1" =~ ^[a-zA-Z0-9-]+$ ]]
}

# Help function
show_help() {
  log "Displaying help message"
  printf "\n${GREEN}UCLI - Universal Command Line Interface Tool${NC}\n\n"
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
  printf "  ${GREEN}help${NC}                   Show this help message\n\n"

  printf "${YELLOW}Features:${NC}\n"
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
  read -r -p "${YELLOW}Press ENTER to return to main menu (interactive mode) or exit (command-line mode)...${NC}" || true
}

# Install script
install() {
  if [[ ! -d "/usr/local/bin" ]]; then
    if sudo mkdir -p /usr/local/bin; then
      log "Directory /usr/local/bin created successfully."
    else
      error "Error creating directory /usr/local/bin."
    fi
  fi
  if sudo cp "$0" /usr/local/bin/ucli && sudo chmod +x /usr/local/bin/ucli; then
      log "ucli installed to /usr/local/bin."
  else
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

# Function to list repositories
list_repos() {
    log "Fetching repositories for $ORG..."
    registry_load || error "Failed to fetch registry data"
    local repos
    repos=$(fetch_repos)

    if [[ $? -ne 0 ]]; then
        warn "Failed to fetch repository data"
        read -n 1 -s -r -p "Press ENTER to return to main menu..." || { echo "No input; run 'ucli help'."; exit 1; }
        return 1
    fi

    echo "$repos"
    log "Repository list displayed"
    log "Press ENTER to return to main menu..."
    read -r || { echo "No input; run 'ucli help'."; exit 1; }
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
        built="$built $repo"
    done

    # Clean up at the end
    cd "$original_dir" || error "Error returning to original directory"
    cleanup "$UCLI_BUILD_DIR"
    trap - EXIT

    log "built:${built:- none}; failed:${failed:- none}"
    return $rc
}

# Function to check if a tool is installed
is_tool_installed() {
    local tool="$1"
    [[ -f "/usr/local/bin/$tool" ]]
}

# Function to get installed tools
get_installed_tools() {
    local installed=()
    for tool in /usr/local/bin/*; do
        [[ -f "$tool" ]] && installed+=($(basename "$tool"))
    done
    echo "${installed[@]}"
}

# Update function
update_tools() {
    log "Fetching repository list..."
    registry_load || error "Failed to fetch registry data"
    local repos
    repos=$(fetch_repos)

    if [[ $? -ne 0 ]]; then
        error "Failed to fetch repository data"
    fi

    local installed_tools=()
    for repo in $repos; do
        if is_tool_installed "$repo"; then
            installed_tools+=("$repo")
        fi
    done

    if [[ ${#installed_tools[@]} -eq 0 ]]; then
        warn "No installed tools found to update"
        return 0
    fi

    log "Found ${#installed_tools[@]} installed tools. Starting update..."

    for tool in "${installed_tools[@]}"; do
        log "Updating $tool..."
        fetch_and_run "$tool"
    done

    log "Update completed!"
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

        local installed_tools=$(get_installed_tools)
        registry_load || true
        local official_tools
        official_tools=$(fetch_repos 2>/dev/null)

        if [[ -z "$installed_tools" ]]; then
            printf "${YELLOW}No UCLI tools are currently installed.${NC}\n"
            printf "Use ${GREEN}ucli build <tool>${NC} to install tools.\n"
            return 0
        fi

        local found_any=false
        for tool in $installed_tools; do
            # Check if this tool is in our official registry
            if echo "$official_tools" | grep -Fxq -- "${tool}"; then
                found_any=true
                local version=$(get_tool_version "$tool" 2>/dev/null || echo "unknown")
                printf "${GREEN}%-15s${NC} %s\n" "$tool:" "${version:0:12}"
            fi
        done

        if [[ "$found_any" == "false" ]]; then
            printf "${YELLOW}No official UCLI tools found.${NC}\n"
        fi

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
            printf "${GREEN}✓ Tool is installed locally${NC}\n"
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
      show_help
      exit 0
    fi
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
        4|list) list_repos ;;
        5|logout) logout ;;
        6|help) show_help ;;
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
      help) show_help ;;
      *) printf "${RED}Invalid command. Use 'ucli help' for usage information.\n${NC}"; exit 1 ;;
    esac
  fi
}

main "$@"
