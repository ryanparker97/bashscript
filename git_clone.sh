#!/bin/bash

# Function to extract hosts from SSH config
get_ssh_hosts() {
  if [[ ! -f ~/.ssh/config ]]; then
    echo "Error: ~/.ssh/config not found"
    exit 1
  fi

  # Extract Host entries (excluding wildcards)
  grep -i "^Host " ~/.ssh/config | awk '{print $2}' | grep -v "\*"
}

# Function to display menu and get selection
select_host() {
  local hosts=("$@")

  if [[ ${#hosts[@]} -eq 0 ]]; then
    echo "Error: No hosts found in ~/.ssh/config" >&2
    exit 1
  fi

  echo "Available SSH profiles:" >&2
  echo "=======================" >&2
  for i in "${!hosts[@]}"; do
    echo "$((i + 1)). ${hosts[$i]}" >&2
  done
  echo "" >&2

  while true; do
    read -p "Select profile number (1-${#hosts[@]}): " selection >&2

    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "${#hosts[@]}" ]]; then
      echo "${hosts[$((selection - 1))]}"
      return 0
    else
      echo "Invalid selection. Please try again." >&2
    fi
  done
}

# Main function
ssh_clone() {
  if [[ $# -ne 1 ]]; then
    echo "Usage: git-clone <git-url>"
    echo "Example: git-clone git@gitlab.com:securitybankph/edo/fincon/cdp_regrep_gl_recon.git"
    return 1
  fi

  local git_url="$1"

  # Validate it's a git SSH URL
  if [[ ! "$git_url" =~ ^git@.+:.+\.git$ ]]; then
    echo "Error: Invalid git SSH URL format"
    echo "Expected format: git@domain:path/to/repo.git"
    return 1
  fi

  # Extract the domain from the URL
  local original_domain=$(echo "$git_url" | sed -n 's/git@\([^:]*\):.*/\1/p')
  echo "Original domain: $original_domain"
  echo ""

  # Get available hosts (compatible with older bash)
  local hosts=()
  while IFS= read -r line; do
    hosts+=("$line")
  done < <(get_ssh_hosts)

  # Let user select
  local selected_host=$(select_host "${hosts[@]}")

  # Replace the domain with selected host (escape special chars)
  local escaped_domain=$(echo "$original_domain" | sed 's/[.]/\\./g')
  local new_url=$(echo "$git_url" | sed "s/$escaped_domain/$selected_host/")

  echo ""
  echo "Cloning git url: $new_url"
  echo ""
  git clone "$new_url"
}

# Run the function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  ssh_clone "$@"
fi
