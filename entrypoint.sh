#!/bin/bash
set -euo pipefail

# Configuration
WIREGUARD_TOOLS_VERSION="${WIREGUARD_TOOLS_VERSION:-v1.0.20250521}"
OUTPUT_DIR="/output"
BUILD_DIR="/tmp/wireguard-tools-build"
TOOLCHAIN_PREFIX="/opt/x-tools"
TOOLCHAIN_CC="${TOOLCHAIN_PREFIX}/arm-unknown-linux-uclibcgnueabihf/bin/arm-unknown-linux-uclibcgnueabihf-gcc"

echo "============================================"
echo "JetKVM WireGuard Tools Builder"
echo "============================================"
echo "WireGuard Tools Version: ${WIREGUARD_TOOLS_VERSION}"
echo "Output Directory: ${OUTPUT_DIR}"
echo "============================================"

# Validate output directory is mounted
if [[ ! -d "${OUTPUT_DIR}" ]]; then
    echo "ERROR: Output directory ${OUTPUT_DIR} does not exist or is not mounted"
    echo "Please run with: docker run --rm -v \$(pwd)/output:/output <image>"
    exit 1
fi

# Create build directory
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Clone wireguard-tools repository
echo "Cloning wireguard-tools repository..."
git clone --depth 1 --branch "${WIREGUARD_TOOLS_VERSION}" \
    https://git.zx2c4.com/wireguard-tools

# Build wireguard-tools
echo "Building wireguard-tools..."
cd wireguard-tools
CFLAGS="-static -Os" CC="${TOOLCHAIN_CC}" make -C src -j "$(nproc)"

# Verify the binary was built
if [[ ! -f "src/wg" ]]; then
    echo "ERROR: Build failed - wg binary not found"
    exit 1
fi

# Copy to output directory
echo "Copying wg binary to output directory..."
cp src/wg "${OUTPUT_DIR}/wg"
chmod +x "${OUTPUT_DIR}/wg"

# Display success message
echo "============================================"
echo "Build completed successfully!"
echo "Output: ${OUTPUT_DIR}/wg"
echo "============================================"
echo "Binary info:"
file "${OUTPUT_DIR}/wg"
ls -lh "${OUTPUT_DIR}/wg"
echo "============================================"
echo "You can now copy this binary to your JetKVM device"
