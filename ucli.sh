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
  printf "  ${GREEN}install${NC}             Install ucli to /usr/local/bin\n"
  printf "  ${GREEN}uninstall${NC}           Remove ucli from /usr/local/bin\n"
  printf "  ${GREEN}login${NC}               Set GitHub organization\n"
  printf "  ${GREEN}logout${NC}              Unset GitHub organization\n"
  printf "  ${GREEN}list${NC}                List organization repositories\n"
  printf "  ${GREEN}build repo1 repo2${NC}   Build tools from specified GitHub repositories\n"
  printf "  ${GREEN}help${NC}                Show this help message\n\n"
  printf "${YELLOW}Interactive mode: Run 'ucli' without arguments\n\n${NC}"
  printf "License: Apache 2.0\n"
  printf "Repository: https://github.com/mik-tf/ucli\n\n"
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
  if [[ -f "$ENV_FILE" ]]; then
    # Try to read the ORG variable, handle potential errors
    if read -r ORG < "$ENV_FILE" && [[ -n "$ORG" ]]; then
      log "Already logged in as $ORG"
      return 0
    else
      warn "Existing $ENV_FILE is corrupted.  Overwriting..."
    fi
  fi

  while true; do
    read -r -p "User/Organization (required): " ORG
    if [[ -z "$ORG" ]]; then
      warn "Organization name cannot be empty."
    else
      # Use printf to ensure proper file writing, even with special characters
      printf "%s\n" "$ORG" > "$ENV_FILE"
      log "Logged in as $ORG"
      return 0
    fi
  done
}

# Check login
check_login() {
  if [[ ! -f "$ENV_FILE" ]]; then
    warn "Please login first using 'ucli login'."
    return 1
  fi

  if ! read -r ORG < "$ENV_FILE" || [[ -z "$ORG" ]]; then
    warn "Error reading or invalid organization in $ENV_FILE. Please login again."
    rm -f "$ENV_FILE" # Remove the corrupted file
    return 1
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

# Function to fetch repositories from GitHub API
fetch_repos() {
    if ! check_login; then
        return 1
    fi

    if ! command -v curl &> /dev/null; then
        error "curl is required but not installed."
    fi

    local repos=$(curl -s "https://api.github.com/users/${ORG}/repos" |
                 grep '"name":' |
                 sed -E 's/.*"name": "([^"]+)".*/\1/' |
                 grep -v "Apache License 2.0" |
                 sort)

    if [[ -z "$repos" ]]; then
        return 1
    fi

    echo "$repos"
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
        if ! is_valid_repo_name "$repo"; then
            error "Invalid repository name: $repo. Only alphanumeric characters and hyphens are allowed."
        fi

        log "Cloning repository ${org}/${repo}..."
        cd "$original_dir" || error "Error changing to original directory"

        if ! git clone --depth 1 "https://github.com/$org/$repo.git" "$tmpdir/$repo"; then
            warn "Error cloning repository ${org}/${repo}. Skipping..."
            continue
        fi

        cd "$tmpdir/$repo" || {
            error "Error changing to directory $tmpdir/$repo"
        }

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

# Main function
main() {
  if [[ -z "$1" ]]; then # Interactive mode
    while true; do
      clear
      printf "${GREEN}Welcome to UCLI, the Universal Command Line Interface Tool!${NC}\n\n"
      printf "${YELLOW}Select an option by entering its number or name:${NC}\n\n"
      printf "  1. ${GREEN}login${NC}   - Set your GitHub organization\n"
      printf "  2. ${GREEN}build${NC}   - Build a tool from a GitHub repository\n"
      printf "  3. ${GREEN}list${NC}    - List organization repositories\n"
      printf "  4. ${GREEN}logout${NC}  - Unset your GitHub organization\n"
      printf "  5. ${GREEN}help${NC}    - Show help information\n"
      printf "  6. ${GREEN}update${NC}  - Update all installed tools\n"
      printf "  7. ${GREEN}prereq${NC}  - Install prerequisites (Ubuntu/Debian)\n"
      printf "  8. ${GREEN}exit${NC}    - Exit ucli\n\n"

      read -r -p "Enter your choice: " choice

      case "$choice" in
        1|login) login ;;
        2|build)
          read -r -p "Repository names (space-separated): " repos
          fetch_and_run $repos ;;
        3|list) list_repos ;;
        4|logout) logout ;;
        5|help) show_help ;;
        6|update) update_tools ;;
        7|prereq) install_prerequisites ;;
        8|exit) exit 0 ;;
        *) printf "${RED}Invalid choice. Try 'help' for more information.${NC}\n" ;;
      esac
    done
  else # Command-line mode
    case "$1" in
      install) install ;;
      uninstall) uninstall ;;
      login) login ;;
      logout) logout ;;
      list) list_repos ;;
      build) fetch_and_run "$@" ;; # Pass all arguments to fetch_and_run
      help) show_help ;;
      *) printf "${RED}Invalid command. Use 'ucli help' for usage information.\n${NC}"; exit 1 ;;
    esac
  fi
}

main "$@"
