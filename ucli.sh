#!/bin/bash

# ANSI color codes
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[0;33m')
NC=$(printf '\033[0m')
ENV_FILE="$HOME/.ucli_env"

# Logging functions for consistent output formatting
log() {
    echo -e "${GREEN}[UPDATE]${NC} $1"
    sleep 1
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    sleep 1
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    sleep 1
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
  read -r -p "${YELLOW}Press ENTER to return to main menu (interactive mode) or exit (command-line mode)...${NC}"
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
      read -r -p "Enter new organization (or press ENTER to keep $current_org): " new_org
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
      read -r -p "User/Organization (required): " new_org
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

# Function to fetch repositories from UCLI Registry
fetch_repos() {
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed."
    fi

    # Fetch from UCLI Registry API
    local registry_url="https://raw.githubusercontent.com/ucli-tools/ucli-registry/main/registry/apps.yaml"

    log "Fetching tools from UCLI Registry..."

    # Fetch and parse YAML to extract official tool names
    local yaml_content=$(curl -s "$registry_url" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$yaml_content" ]]; then
        error "Failed to fetch registry data"
    fi

    # Extract official app names from YAML (simple parsing)
    local repos=$(echo "$yaml_content" | grep -A 1000 "official:" | grep -B 1000 "community:" | grep "^  - name:" | sed 's/.*name: //' | sort)

    if [[ -z "$repos" ]]; then
        warn "No tools found in registry"
        return 1
    fi

    echo "$repos"
    return 0
}

# Function to get tool version from registry
get_tool_version() {
    local tool_name="$1"
    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed."
    fi

    local registry_url="https://raw.githubusercontent.com/ucli-tools/ucli-registry/main/registry/apps.yaml"
    local yaml_content=$(curl -s "$registry_url")

    if [[ $? -ne 0 ]] || [[ -z "$yaml_content" ]]; then
        error "Failed to fetch registry data"
    fi

    # Extract version for specific tool (simple parsing)
    local version=$(echo "$yaml_content" | grep -A 20 "name: $tool_name" | grep "version:" | head -1 | sed 's/.*version: //' | tr -d ' ')

    if [[ -z "$version" ]]; then
        error "Could not find version for tool: $tool_name"
    fi

    echo "$version"
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
}

# Function to list repositories
list_repos() {
    log "Fetching repositories for $ORG..."
    local repos=$(fetch_repos)

    if [[ $? -ne 0 ]]; then
        warn "Failed to fetch repository data"
        read -n 1 -s -r -p "Press ENTER to return to main menu..."
        return 1
    fi

    echo "$repos"
    log "Repository list displayed"
    log "Press ENTER to return to main menu..."
    read -r
}

# Function to fetch and run (modified to handle multiple repos)
fetch_and_run() {
    if ! check_login; then
        return 1
    fi

    local original_dir=$(pwd)
    local org="$ORG"
    local tmpdir="/tmp/ucli/$org"

    # Set trap for cleanup
    trap 'cleanup "$tmpdir"' EXIT

    # Clean up existing temporary directory if it exists
    if [[ -d "$tmpdir" ]]; then
        cleanup "$tmpdir"
    fi

    if ! mkdir -p "$tmpdir"; then
        error "Error creating temporary directory $tmpdir"
    fi

    for repo in "$@"; do
        if [[ "$repo" == .* ]]; then
            warn "Repository '$repo' starts with a dot and will be skipped."
            continue # Skip to the next repository
        fi

        if ! is_valid_repo_name "$repo"; then
            error "Invalid repository name: $repo. Only alphanumeric characters and hyphens are allowed."
        fi

        cd "$original_dir" || error "Error changing to original directory"

        # Get the specific version (commit hash) from registry
        local version=$(get_tool_version "$repo")

        # Clone specific commit quietly for reproducible builds
        if ! git clone --quiet --depth 1 --branch main "https://github.com/$org/$repo.git" "$tmpdir/$repo" 2>/dev/null; then
            warn "Error cloning repository ${org}/${repo}. Skipping..."
            continue
        fi

        cd "$tmpdir/$repo" || {
            error "Error changing to directory $tmpdir/$repo"
        }

        # Checkout the specific commit for reproducible builds (quietly)
        if ! git checkout --quiet "$version" 2>/dev/null; then
            warn "Error checking out version $version for ${org}/${repo}. Skipping..."
            continue
        fi

        log "Building ${repo} (v${version:0:8})..."

        log "Running make in $repo..."
        if ! make; then
            warn "Error executing Makefile in $repo. Skipping..."
            continue
        fi

        log "Build successful for $repo!"
    done

    # Clean up at the end
    cd "$original_dir" || error "Error returning to original directory"
    cleanup "$tmpdir"

    # Remove trap
    trap - EXIT
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
    local repos=$(fetch_repos)

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
    local repos=$(fetch_repos)

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
        local official_tools=$(fetch_repos 2>/dev/null)

        if [[ -z "$installed_tools" ]]; then
            printf "${YELLOW}No UCLI tools are currently installed.${NC}\n"
            printf "Use ${GREEN}ucli build <tool>${NC} to install tools.\n"
            return 0
        fi

        local found_any=false
        for tool in $installed_tools; do
            # Check if this tool is in our official registry
            if echo "$official_tools" | grep -q "^${tool}$"; then
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
        local official_tools=$(fetch_repos 2>/dev/null)
        if ! echo "$official_tools" | grep -q "^${tool_arg}$"; then
            printf "${RED}Tool '${tool_arg}' not found in UCLI Registry.${NC}\n"
            printf "Use ${GREEN}ucli list${NC} to see available tools.\n"
            return 1
        fi

        # Get detailed version info from registry
        if ! command -v curl &> /dev/null; then
            error "curl is required but not installed."
        fi

        local registry_url="https://raw.githubusercontent.com/ucli-tools/ucli-registry/main/registry/apps.yaml"
        local yaml_content=$(curl -s "$registry_url")

        if [[ $? -ne 0 ]] || [[ -z "$yaml_content" ]]; then
            error "Failed to fetch registry data"
        fi

        # Extract tool information (simple parsing)
        local tool_section=$(echo "$yaml_content" | grep -A 50 "name: $tool_arg" | head -50)
        local version=$(echo "$tool_section" | grep "version:" | head -1 | sed 's/.*version: //' | tr -d ' ')
        local description=$(echo "$tool_section" | grep "description:" | head -1 | sed 's/.*description: //' | sed 's/^"//' | sed 's/"$//')
        local repo=$(echo "$tool_section" | grep "repo:" | head -1 | sed 's/.*repo: //' | tr -d ' ')
        local status=$(echo "$tool_section" | grep "status:" | head -1 | sed 's/.*status: //' | tr -d ' ')

        # Extract version_info if available
        local commit_date=""
        local commit_message=""
        local commit_url=""

        if echo "$tool_section" | grep -q "version_info:"; then
            local version_info_section=$(echo "$tool_section" | grep -A 10 "version_info:" | head -10)
            commit_date=$(echo "$version_info_section" | grep "commit_date:" | head -1 | sed 's/.*commit_date: //' | tr -d ' ')
            commit_message=$(echo "$version_info_section" | grep "commit_message:" | head -1 | sed 's/.*commit_message: //' | sed 's/^"//' | sed 's/"$//')
            commit_url=$(echo "$version_info_section" | grep "commit_url:" | head -1 | sed 's/.*commit_url: //' | tr -d ' ')
        fi

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

      read -r -p "Enter your choice: " choice

      case "$choice" in
        1|login)
          read -r -p "Organization name (leave empty to be prompted): " org_name
          login "$org_name" ;;
        2|build)
          read -r -p "Repository names (space-separated): " repos
          fetch_and_run $repos ;;
        3|build-all) build_all_repos ;;
        4|list) list_repos ;;
        5|logout) logout ;;
        6|help) show_help ;;
        7|update) update_tools ;;
        8|prereq) install_prerequisites ;;
        9|versions)
          read -r -p "Tool name (or --all for all installed tools): " tool_name
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
