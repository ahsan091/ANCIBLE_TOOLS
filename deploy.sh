#!/bin/bash
# ============================================================================
# GuardianEye SOC Stack - Enterprise Bootstrap Wrapper
# ============================================================================
# Purpose: Single-command deployment experience while keeping Ansible as
#          the source of truth. This wrapper only handles prerequisites.
#
# Usage:
#   chmod +x deploy.sh
#   sudo ./deploy.sh              # Full deployment
#   sudo ./deploy.sh --check      # Dry run
#   sudo ./deploy.sh --tags wazuh # Deploy specific tools
#
# Enterprise Features:
#   - Idempotent (safe to run multiple times)
#   - Non-interactive (no prompts)
#   - Audit trail logging
#   - CI/CD compatible
# ============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Configuration
# ─────────────────────────────────────────────────────────────────────────────
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/guardianeye-socstack-deploy.log"
readonly REQUIRED_ANSIBLE_VERSION="2.14.0"
readonly REQUIRED_UBUNTU_VERSION="20.04"

# Colors for output (only if terminal supports it)
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly NC='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# ─────────────────────────────────────────────────────────────────────────────
# Logging Functions
# ─────────────────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $message" ;;
        OK)    echo -e "${GREEN}[OK]${NC} $message" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" ;;
    esac
    
    # Append to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

log_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       GuardianEye SOC Stack - Ansible Deployment             ║${NC}"
    echo -e "${BLUE}║  Wazuh • TheHive • Shuffle • OpenCTI on Docker Network       ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight Checks
# ─────────────────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "This script must be run as root or with sudo"
        echo "Usage: sudo $0"
        exit 1
    fi
    log OK "Running as root"
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        log ERROR "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log ERROR "Unsupported OS: $ID. Requires Ubuntu or Debian."
        exit 1
    fi
    
    # Version check using sort -V (no bc dependency)
    local version="${VERSION_ID:-0}"
    if [[ "$ID" == "ubuntu" ]]; then
        local min_version="20.04"
        if [[ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n1)" != "$min_version" ]]; then
            log WARN "Ubuntu $version detected. Recommended: 22.04+"
        else
            log OK "OS: $PRETTY_NAME"
        fi
    else
        log OK "OS: $PRETTY_NAME"
    fi
}

check_resources() {
    # Check RAM (minimum 16GB)
    local total_mem_kb
    total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    
    if [[ $total_mem_gb -lt 16 ]]; then
        log WARN "RAM: ${total_mem_gb}GB detected. Minimum 16GB recommended."
    else
        log OK "RAM: ${total_mem_gb}GB"
    fi
    
    # Check disk space (minimum 100GB free)
    local free_space_gb
    free_space_gb=$(df -BG / | awk 'NR==2 {gsub("G",""); print $4}')
    
    if [[ $free_space_gb -lt 100 ]]; then
        log WARN "Disk: ${free_space_gb}GB free. Minimum 100GB recommended."
    else
        log OK "Disk: ${free_space_gb}GB free"
    fi
}

check_internet() {
    if ! curl -sI --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        log ERROR "No internet connectivity. Cannot reach github.com"
        exit 1
    fi
    log OK "Internet connectivity"
}

# ─────────────────────────────────────────────────────────────────────────────
# Dependency Installation
# ─────────────────────────────────────────────────────────────────────────────
install_dependencies() {
    log INFO "Checking and installing dependencies..."
    
    # Update apt cache (only if older than 1 hour)
    local apt_cache="/var/lib/apt/lists"
    if [[ ! -d "$apt_cache" ]] || [[ $(find "$apt_cache" -maxdepth 0 -mmin +60 2>/dev/null) ]]; then
        log INFO "Updating apt cache..."
        apt-get update -qq
    fi
    
    # Install required packages
    local packages_to_install=()
    
    for pkg in ansible git python3 python3-pip jq curl; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            packages_to_install+=("$pkg")
        fi
    done
    
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        log INFO "Installing: ${packages_to_install[*]}"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages_to_install[@]}"
    fi
    
    log OK "System dependencies installed"
}

check_ansible_version() {
    local ansible_version
    ansible_version=$(ansible --version 2>/dev/null | head -1 | grep -oP '\d+\.\d+\.\d+' || echo "0.0.0")
    
    # Compare versions using sort -V
    if [[ "$(printf '%s\n' "$REQUIRED_ANSIBLE_VERSION" "$ansible_version" | sort -V | head -n1)" != "$REQUIRED_ANSIBLE_VERSION" ]]; then
        log ERROR "Ansible $ansible_version is older than required $REQUIRED_ANSIBLE_VERSION"
        log ERROR "Please upgrade Ansible manually:"
        log ERROR "  Option 1 (apt): sudo apt install ansible"
        log ERROR "  Option 2 (pip): pip3 install --user ansible"
        exit 1
    fi
    
    log OK "Ansible: $(ansible --version | head -1)"
}

install_galaxy_collections() {
    log INFO "Installing Ansible Galaxy collections..."
    
    local requirements_file="$SCRIPT_DIR/requirements.yml"
    
    if [[ ! -f "$requirements_file" ]]; then
        log ERROR "requirements.yml not found at $requirements_file"
        exit 1
    fi
    
    # Install collections (--force-with-deps ensures updates)
    ansible-galaxy collection install -r "$requirements_file" --force-with-deps
    
    log OK "Galaxy collections installed"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Deployment
# ─────────────────────────────────────────────────────────────────────────────
run_ansible_playbook() {
    local playbook="$SCRIPT_DIR/playbooks/deploy_socstack.yml"
    local inventory="$SCRIPT_DIR/inventory/hosts.yml"
    local extra_args=("$@")
    
    if [[ ! -f "$playbook" ]]; then
        log ERROR "Playbook not found at $playbook"
        exit 1
    fi
    
    if [[ ! -f "$inventory" ]]; then
        log ERROR "Inventory not found at $inventory"
        exit 1
    fi
    
    log INFO "Running Ansible playbook..."
    echo "────────────────────────────────────────────────────────────────" >> "$LOG_FILE"
    echo "Playbook execution started at $(date)" >> "$LOG_FILE"
    echo "Arguments: ${extra_args[*]:-none}" >> "$LOG_FILE"
    echo "────────────────────────────────────────────────────────────────" >> "$LOG_FILE"
    
    # Run playbook with explicit inventory (machine-independent)
    set +e
    ansible-playbook -i "$inventory" "$playbook" "${extra_args[@]}" 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${PIPESTATUS[0]}
    set -e
    
    return $exit_code
}

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
print_success() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              DEPLOYMENT COMPLETED SUCCESSFULLY               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "📋 Audit log: ${YELLOW}$LOG_FILE${NC}"
    echo ""
    echo -e "🌐 Access URLs:"
    echo -e "   Wazuh Dashboard:  ${BLUE}https://localhost:443${NC}"
    echo -e "   TheHive:          ${BLUE}https://localhost:8443${NC}"
    echo -e "   Shuffle:          ${BLUE}http://localhost:3001${NC}"
    echo -e "   OpenCTI:          ${BLUE}http://localhost:8090${NC}"
    echo ""
    echo -e "⚠️  Post-deploy: Visit ${YELLOW}http://localhost:3001/adminsetup${NC} for Shuffle"
    echo ""
}

print_failure() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              DEPLOYMENT FAILED                               ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "📋 Check log for details: ${YELLOW}$LOG_FILE${NC}"
    echo -e "🔧 Troubleshooting: ${YELLOW}tail -100 $LOG_FILE${NC}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────────────────────
main() {
    # Initialize log file
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    echo "GuardianEye SOC Stack Deployment - $(date)" >> "$LOG_FILE"
    echo "═══════════════════════════════════════════════════════════════" >> "$LOG_FILE"
    
    log_header
    
    log INFO "Starting pre-flight checks..."
    check_root
    check_os
    check_resources
    check_internet
    
    log INFO "Ensuring dependencies..."
    install_dependencies
    check_ansible_version
    install_galaxy_collections
    
    log INFO "Starting deployment..."
    
    # Pass through any arguments to ansible-playbook
    if run_ansible_playbook "$@"; then
        print_success
        log OK "Deployment completed successfully"
        exit 0
    else
        print_failure
        log ERROR "Deployment failed"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Script Execution
# ─────────────────────────────────────────────────────────────────────────────
main "$@"
