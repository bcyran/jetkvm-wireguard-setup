#!/usr/bin/env bash
#
# JetKVM WireGuard Installation Script
# Based on: https://simonmicro.de/blog/hacking/wireguard-vpn-on-a-jetkvm/
#
# This script:
# 1. Builds the WireGuard 'wg' binary for ARM uClibc (using Docker/Podman)
# 2. Transfers the binary to JetKVM via SSH + base64 encoding
# 3. Deploys your WireGuard configuration
# 4. Sets up boot persistence
#
# Usage:
#   1. Copy .env.example to .env and configure
#   2. Prepare your WireGuard config (see examples/)
#   3. Run: ./install-wireguard.sh
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Load configuration
load_config() {
    local env_file="${SCRIPT_DIR}/.env"

    if [[ ! -f "${env_file}" ]]; then
        log_error "Configuration file not found: ${env_file}"
        log_info "Copy .env.example to .env and customize it:"
        log_info "  cp .env.example .env"
        log_info "  nano .env"
        exit 1
    fi

    log_info "Loading configuration from ${env_file}"
    # shellcheck disable=SC1090
    source "${env_file}"

    # Set defaults
    JETKVM_USER="${JETKVM_USER:-root}"
    JETKVM_SSH_PORT="${JETKVM_SSH_PORT:-22}"
    WIREGUARD_INTERFACE="${WIREGUARD_INTERFACE:-wg0}"
    WIREGUARD_IP="${WIREGUARD_IP:-192.168.2.1/24}"
    FORCE_BUILD="${FORCE_BUILD:-no}"
    BOOT_DELAY="${BOOT_DELAY:-30}"

    # Validate required variables
    if [[ -z "${JETKVM_IP:-}" ]]; then
        log_error "JETKVM_IP is not set in .env"
        exit 1
    fi

    if [[ -z "${WIREGUARD_CONFIG:-}" ]]; then
        log_error "WIREGUARD_CONFIG is not set in .env"
        exit 1
    fi

    if [[ ! -f "${WIREGUARD_CONFIG}" ]]; then
        log_error "WireGuard config file not found: ${WIREGUARD_CONFIG}"
        exit 1
    fi

    log_success "Configuration loaded"
}

# Detect container runtime
detect_container_runtime() {
    if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
        log_info "Using configured container runtime: ${CONTAINER_RUNTIME}"
        if ! command -v "${CONTAINER_RUNTIME}" &> /dev/null; then
            log_error "Configured runtime '${CONTAINER_RUNTIME}' not found"
            exit 1
        fi
        return
    fi

    # Auto-detect (prefer podman)
    if command -v podman &> /dev/null; then
        CONTAINER_RUNTIME="podman"
        log_info "Detected container runtime: podman"
    elif command -v docker &> /dev/null; then
        CONTAINER_RUNTIME="docker"
        log_info "Detected container runtime: docker"
    else
        log_error "No container runtime found. Please install podman or docker."
        exit 1
    fi
}

# Build WireGuard binary
build_wireguard() {
    local output_dir="${SCRIPT_DIR}/output"
    local wg_binary="${output_dir}/wg"

    # Check if binary already exists
    if [[ -f "${wg_binary}" && "${FORCE_BUILD}" != "yes" ]]; then
        log_info "WireGuard binary already exists: ${wg_binary}"
        log_info "Set FORCE_BUILD=yes in .env to force rebuild"
        return
    fi

    log_info "Building WireGuard binary..."
    mkdir -p "${output_dir}"

    # Build Docker image if needed
    local image_name="jetkvm-wireguard-builder"
    if ! ${CONTAINER_RUNTIME} images | grep -q "${image_name}"; then
        log_info "Building container image (this may take 30-60 minutes on first run)..."
        ${CONTAINER_RUNTIME} build -t "${image_name}" "${SCRIPT_DIR}"
    else
        log_info "Using existing container image: ${image_name}"
    fi

    # Build WireGuard binary
    log_info "Compiling WireGuard tools..."
    ${CONTAINER_RUNTIME} run --rm \
        -v "${output_dir}:/output:z" \
        "${image_name}"

    if [[ ! -f "${wg_binary}" ]]; then
        log_error "Build failed: ${wg_binary} not found"
        exit 1
    fi

    log_success "WireGuard binary built successfully"
}

# Transfer file via SSH + base64
transfer_file() {
    local local_file="$1"
    local remote_file="$2"
    local description="${3:-file}"

    log_info "Transferring ${description} to JetKVM..."

    if [[ ! -f "${local_file}" ]]; then
        log_error "Local file not found: ${local_file}"
        exit 1
    fi

    # Transfer using base64 encoding via SSH
    base64 < "${local_file}" \
        | ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
            "base64 -d > ${remote_file}"

    # Verify transfer
    local local_md5
    local remote_md5

    local_md5=$(md5sum "${local_file}" | awk '{print $1}')
    remote_md5=$(ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
        "md5sum ${remote_file}" | awk '{print $1}')

    if [[ "${local_md5}" != "${remote_md5}" ]]; then
        log_error "Transfer verification failed for ${description}"
        log_error "Local MD5:  ${local_md5}"
        log_error "Remote MD5: ${remote_md5}"
        exit 1
    fi

    log_success "Transferred ${description} successfully"
}

# Generate boot persistence script
generate_boot_script() {
    local script_content
    script_content=$(
        cat << 'EOF'
#!/bin/sh
set -x
exec > /tmp/wg-starter-log.txt 2>&1

start() {
    /sbin/modprobe wireguard
    /bin/sleep __BOOT_DELAY__
    /sbin/ip link add dev __INTERFACE__ type wireguard
    /sbin/ip address add dev __INTERFACE__ __IP_ADDRESS__
    /userdata/wg setconf __INTERFACE__ /userdata/__INTERFACE__.conf
    /sbin/ip link set up dev __INTERFACE__
}

stop() {
    /sbin/ip link delete dev __INTERFACE__
}

case "$1" in
    start)
       start
       ;;
    stop)
       stop
       ;;
    restart)
       stop
       start
       ;;
    *)
       echo "Usage: $0 {start|stop|restart}"
esac

exit 0
EOF
    )

    # Replace placeholders
    script_content="${script_content//__BOOT_DELAY__/${BOOT_DELAY}}"
    script_content="${script_content//__INTERFACE__/${WIREGUARD_INTERFACE}}"
    script_content="${script_content//__IP_ADDRESS__/${WIREGUARD_IP}}"

    echo "${script_content}"
}

# Install WireGuard on JetKVM
install_on_jetkvm() {
    local output_dir="${SCRIPT_DIR}/output"
    local wg_binary="${output_dir}/wg"

    log_info "Installing WireGuard on JetKVM..."

    # 1. Transfer wg binary
    transfer_file "${wg_binary}" "/userdata/wg" "wg binary"

    # 2. Make binary executable
    ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
        "chmod +x /userdata/wg"

    # 3. Transfer WireGuard config
    transfer_file "${WIREGUARD_CONFIG}" "/userdata/${WIREGUARD_INTERFACE}.conf" "WireGuard config"

    # 4. Create boot persistence script
    log_info "Creating boot persistence script..."
    local boot_script
    boot_script=$(generate_boot_script)

    echo "${boot_script}" | ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
        "cat > /userdata/wg-starter && chmod +x /userdata/wg-starter"

    # 5. Create symlinks
    log_info "Creating symlinks..."
    ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
        "ln -sf /userdata/wg /usr/bin/wg || true && \
         ln -sf /userdata/wg-starter /etc/init.d/S99wg-starter || true"

    log_success "Installation completed"
}

# Start WireGuard
start_wireguard() {
    log_info "Starting WireGuard interface..."

    ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
        "/userdata/wg-starter start"

    log_success "WireGuard started"
}

# Show status
show_status() {
    log_info "WireGuard status on JetKVM:"
    echo ""

    ssh -p "${JETKVM_SSH_PORT}" "${JETKVM_USER}@${JETKVM_IP}" \
        "/userdata/wg show" || true

    echo ""
    log_info "You can check the boot script logs at: /tmp/wg-starter-log.txt"
}

# Main function
main() {
    echo ""
    log_info "========================================"
    log_info "JetKVM WireGuard Installation Script"
    log_info "========================================"
    echo ""

    load_config
    detect_container_runtime
    build_wireguard
    install_on_jetkvm
    start_wireguard
    show_status

    echo ""
    log_success "========================================"
    log_success "Installation Complete!"
    log_success "========================================"
    echo ""
    log_info "WireGuard is now running on your JetKVM device"
    log_info "The interface will automatically start on boot"
    echo ""
    log_info "Useful commands (run on JetKVM via SSH):"
    log_info "  wg show                    # Show current status"
    log_info "  /userdata/wg-starter stop  # Stop WireGuard"
    log_info "  /userdata/wg-starter start # Start WireGuard"
    log_info "  cat /tmp/wg-starter-log.txt # View boot logs"
    echo ""
}

# Run main function
main "$@"
