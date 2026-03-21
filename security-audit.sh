#!/bin/bash
#
# security-audit.sh - Security audit script for system and project analysis
# Performs various security checks including malicious patterns, processes, and configurations
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Array to track what was checked
declare -a CHECKS_PERFORMED=()

# Arrays to track findings
declare -a FILES_DELETED=()
declare -a HOOKS_DELETED=()
declare -a PROCESSES_KILLED=()
declare -a SSH_KEYS_REMOVED=()
declare -a WARNINGS_REQUIRING_MANUAL_REVIEW=()

# Malicious patterns to detect in git hooks
declare -a MALICIOUS_PATTERNS=("8-1168-1" "$_$1e42" "rmcej%otb%" "2857687" "LAST_COMMIT_DATE")

# Suspicious processes to monitor
declare -a SUSPICIOUS_PROCS=("node" "python" "curl" "wget")

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_finding() {
    echo -e "${RED}[FINDING]${NC} $1"
}

# Prompt user for action - always waits for input
prompt_user() {
    local prompt="$1"
    local response
    echo -en "${BLUE}${prompt} (Y/n): ${NC}" >&2
    read -r response </dev/tty 2>/dev/null || read -r response
    case "$response" in
        [Yy]|[Yy][Ee][Ss])
            return 0  # Yes
            ;;
        *)
            return 1  # No
            ;;
    esac
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get the target folder
get_target_folder() {
    if [ -n "${1:-}" ] && [ -d "$1" ]; then
        echo "$1"
    elif [ -n "${1:-}" ]; then
        print_error "Directory '$1' does not exist."
        exit 1
    else
        echo -n "Enter the folder path to audit: " >&2
        read -r folder </dev/tty 2>/dev/null || read -r folder
        if [ -d "$folder" ]; then
            echo "$folder"
        else
            print_error "Directory '$folder' does not exist."
            exit 1
        fi
    fi
}

# Check 1: Find package.json files with postinstall scripts
check_postinstall_scripts() {
    print_header "Checking for package.json with postinstall scripts"
    CHECKS_PERFORMED+=("package.json postinstall scripts")

    local target_dir="$1"
    local found=0
    local has_jq=0

    # Check jq availability once before loop
    if command_exists jq; then
        has_jq=1
    fi

    while IFS= read -r -d '' pkg_json; do
        local should_delete=0
        if [ $has_jq -eq 1 ]; then
            if jq -e '.scripts.postinstall' "$pkg_json" >/dev/null 2>&1; then
                print_finding "Found package.json with postinstall: $pkg_json"
                echo "  postinstall: $(jq -r '.scripts.postinstall' "$pkg_json")"
                found=1
                should_delete=1
            fi
        else
            # Fallback if jq not available
            if grep -q '"postinstall"' "$pkg_json" 2>/dev/null; then
                print_finding "Found package.json with postinstall (jq not available): $pkg_json"
                found=1
                should_delete=1
            fi
        fi

        if [ $should_delete -eq 1 ]; then
            if prompt_user "Delete this file?"; then
                if rm -f "$pkg_json"; then
                    print_success "Deleted: $pkg_json"
                    FILES_DELETED+=("$pkg_json")
                else
                    print_error "Failed to delete: $pkg_json"
                fi
            else
                print_info "Skipped deletion of: $pkg_json"
            fi
        fi
    done < <(find "$target_dir" -name "package.json" -type f -print0 2>/dev/null)

    if [ $found -eq 0 ]; then
        print_success "No package.json files with postinstall scripts found"
    fi
    echo
}

# Helper function to check a hook file for malicious patterns
check_hook_file() {
    local hook="$1"
    local found=0

    if [ -f "$hook" ]; then
        for pattern in "${MALICIOUS_PATTERNS[@]}"; do
            if grep -q "$pattern" "$hook" 2>/dev/null; then
                print_finding "Malicious pattern '$pattern' found in: $hook"
                found=1

                # Prompt for deletion
                if prompt_user "Delete this hook?"; then
                    if rm -f "$hook"; then
                        print_success "Deleted hook: $hook"
                        HOOKS_DELETED+=("$hook")
                    else
                        print_error "Failed to delete hook: $hook"
                    fi
                else
                    print_info "Skipped deletion of: $hook"
                fi
            fi
        done
    fi
    return $found
}

# Check 2: Check git hooks for tampering
check_git_hooks() {
    print_header "Checking git hooks for tampering"
    CHECKS_PERFORMED+=("git hooks tampering")

    local target_dir="$1"
    local found=0

    # Find and check all .git/hooks directories
    while IFS= read -r -d '' hook_dir; do
        for hook in "$hook_dir"/*; do
            if check_hook_file "$hook"; then
                found=1
            fi
        done
    done < <(find "$target_dir" -name "hooks" -type d -print0 2>/dev/null)

    if [ $found -eq 0 ]; then
        print_success "No suspicious patterns found in git hooks"
    fi
    echo
}

# Check 3: Display current user's crontab
check_user_crontab() {
    print_header "Current User Crontab"
    CHECKS_PERFORMED+=("user crontab")

    if command_exists crontab; then
        local crontab_output
        if crontab_output=$(crontab -l 2>&1); then
            if [ -n "$crontab_output" ]; then
                print_warning "Current crontab entries:"
                echo "$crontab_output"
                print_warning "Manual review needed - crontab entries require human assessment"
            else
                print_success "No crontab entries for current user"
            fi
        else
            print_success "No crontab for current user"
        fi
    else
        print_warning "crontab command not available"
    fi
    echo
}

# Check 4: Display root crontab (if accessible)
check_root_crontab() {
    print_header "Root Crontab"
    CHECKS_PERFORMED+=("root crontab")

    if command_exists sudo && sudo -n true 2>/dev/null; then
        local root_crontab
        if root_crontab=$(sudo crontab -l 2>&1); then
            if [ -n "$root_crontab" ]; then
                print_warning "Root crontab entries:"
                echo "$root_crontab"
                print_warning "Manual review needed - crontab entries require human assessment"
            else
                print_success "No crontab for root"
            fi
        else
            print_success "No crontab for root"
        fi
    elif [ "$(id -u)" -eq 0 ]; then
        # Already running as root
        if root_crontab=$(crontab -l 2>&1); then
            if [ -n "$root_crontab" ]; then
                print_warning "Root crontab entries:"
                echo "$root_crontab"
                print_warning "Manual review needed - crontab entries require human assessment"
            else
                print_success "No crontab for root"
            fi
        else
            print_success "No crontab for root"
        fi
    else
        print_info "Cannot access root crontab (not root and sudo not available)"
    fi
    echo
}

# Check 5: List suspicious processes
check_suspicious_processes() {
    print_header "Suspicious Processes"
    CHECKS_PERFORMED+=("suspicious processes")

    local found=0

    if command_exists ps; then
        # Run ps aux once and filter for each process type
        local ps_output
        ps_output=$(ps aux 2>/dev/null | grep -v grep)

        for proc in "${SUSPICIOUS_PROCS[@]}"; do
            local proc_lines
            proc_lines=$(echo "$ps_output" | grep -i "$proc" || true)
            if [ -n "$proc_lines" ]; then
                print_warning "Found $proc processes:"
                echo "$proc_lines" | head -20

                # Prompt for each process - use process substitution to avoid subshell issues
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    local pid
                    pid=$(echo "$line" | awk '{print $2}' | head -1)
                    local proc_name
                    proc_name=$(echo "$line" | awk '{print $11}' | xargs basename 2>/dev/null || echo "$proc")

                    if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; then
                        if prompt_user "Kill this process? ($proc_name $pid)"; then
                            if kill "$pid" 2>/dev/null; then
                                print_success "Killed process: $proc_name (PID: $pid)"
                                PROCESSES_KILLED+=("$proc_name:$pid")
                            else
                                print_error "Failed to kill process: $proc_name (PID: $pid)"
                            fi
                        else
                            print_info "Skipped killing: $proc_name (PID: $pid)"
                        fi
                    fi
                done <<< "$proc_lines"
                echo
                found=1
            fi
        done

        if [ $found -eq 0 ]; then
            print_success "No suspicious processes found"
        fi
    else
        print_warning "ps command not available"
    fi
    echo
}

# Check 6: Display SSH authorized_keys
check_ssh_keys() {
    print_header "SSH Authorized Keys"
    CHECKS_PERFORMED+=("SSH authorized_keys")

    local ssh_dir="$HOME/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    if [ -f "$auth_keys" ]; then
        print_warning "Authorized keys found:"
        cat "$auth_keys"

        # Prompt for each key - show a preview of each key
        local temp_file
        temp_file=$(mktemp)
        cp "$auth_keys" "$temp_file"

        local line_num=0
        local keys_removed=0
        while IFS= read -r line || [ -n "$line" ]; do
            line_num=$((line_num + 1))
            [ -z "$line" ] && continue

            # Show abbreviated key for identification
            local key_preview
            key_preview=$(echo "$line" | head -c 80)
            if [ ${#line} -gt 80 ]; then
                key_preview="${key_preview}..."
            fi

            echo -e "\n${YELLOW}Key $line_num:${NC} $key_preview"

            if prompt_user "Remove this key?"; then
                # Remove this line from temp file
                sed -i '' "${line_num}d" "$temp_file" 2>/dev/null || \
                sed -i "${line_num}d" "$temp_file" 2>/dev/null
                print_success "Marked key $line_num for removal"
                keys_removed=$((keys_removed + 1))
            else
                print_info "Kept key $line_num"
            fi
        done < "$auth_keys"

        # If any keys were removed, update the authorized_keys file
        if [ $keys_removed -gt 0 ]; then
            if prompt_user "Apply removal of $keys_removed key(s)?"; then
                cp "$temp_file" "$auth_keys"
                print_success "Updated authorized_keys file"
                SSH_KEYS_REMOVED+=("$keys_removed key(s)")
            else
                print_info "Discarded key removal changes"
            fi
        fi
        rm -f "$temp_file"
    else
        print_success "No authorized_keys file found"
    fi
    echo
}

# Check 7: Run rkhunter malware scan if available
check_malware() {
    print_header "Malware Scan (rkhunter)"
    CHECKS_PERFORMED+=("malware scan")

    if command_exists rkhunter; then
        print_info "Running rkhunter scan..."
        if rkhunter --check --skipcrypto --quiet 2>&1; then
            print_success "rkhunter scan completed - no threats detected"
        else
            print_warning "rkhunter found potential issues - review output above"
            print_warning "Manual review needed - rkhunter findings require human assessment"
        fi
    else
        print_info "rkhunter not available - skipping malware scan"
        print_info "Install with: brew install rkhunter (macOS) or apt-get install rkhunter (Linux)"
    fi
    echo
}

# Print summary of checks performed
print_summary() {
    print_header "Security Audit Summary"

    # Show checks performed
    echo "Checks performed:"
    for check in "${CHECKS_PERFORMED[@]}"; do
        echo -e "  ${GREEN}✓${NC} $check"
    done
    echo

    # Show actions taken
    echo "Actions taken:"
    local any_actions=0

    if [ ${#FILES_DELETED[@]} -gt 0 ]; then
        echo -e "  ${RED}✗${NC} Files deleted: ${#FILES_DELETED[@]}"
        for f in "${FILES_DELETED[@]}"; do
            echo -e "      - $f"
        done
        any_actions=1
    fi

    if [ ${#HOOKS_DELETED[@]} -gt 0 ]; then
        echo -e "  ${RED}✗${NC} Git hooks deleted: ${#HOOKS_DELETED[@]}"
        for h in "${HOOKS_DELETED[@]}"; do
            echo -e "      - $h"
        done
        any_actions=1
    fi

    if [ ${#PROCESSES_KILLED[@]} -gt 0 ]; then
        echo -e "  ${RED}✗${NC} Processes killed: ${#PROCESSES_KILLED[@]}"
        for p in "${PROCESSES_KILLED[@]}"; do
            echo -e "      - $p"
        done
        any_actions=1
    fi

    if [ ${#SSH_KEYS_REMOVED[@]} -gt 0 ]; then
        echo -e "  ${RED}✗${NC} SSH keys removed: ${#SSH_KEYS_REMOVED[@]}"
        for k in "${SSH_KEYS_REMOVED[@]}"; do
            echo -e "      - $k"
        done
        any_actions=1
    fi

    if [ $any_actions -eq 0 ]; then
        echo -e "  ${YELLOW}!${NC} No actions taken (all items skipped or not found)"
    fi

    echo
    print_info "Security audit completed at $(date)"
}

# Main function
main() {
    local target_folder
    target_folder=$(get_target_folder "${1:-}")

    print_header "Security Audit Script"
    print_info "Target folder: $target_folder"
    print_info "Started at: $(date)"
    echo

    # Run all checks
    check_postinstall_scripts "$target_folder"
    check_git_hooks "$target_folder"
    check_user_crontab
    check_root_crontab
    check_suspicious_processes
    check_ssh_keys
    check_malware

    # Print summary
    print_summary
}

# Run main with all arguments
main "$@"
