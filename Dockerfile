# JetKVM WireGuard Tools Cross-Compilation Dockerfile
# Based on: https://simonmicro.de/blog/hacking/wireguard-vpn-on-a-jetkvm
#
# This Dockerfile builds a cross-compilation toolchain for ARM uClibc
# and provides an entrypoint to compile wireguard-tools for JetKVM devices.

# Build arguments for configurable versions
ARG UBUNTU_VERSION=25.10
ARG CROSSTOOL_NG_VERSION=1.28.0

FROM ubuntu:${UBUNTU_VERSION}

# Re-declare args after FROM to make them available in this stage
ARG CROSSTOOL_NG_VERSION

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    CT_PREFIX=/opt/x-tools

# Update PATH to include the toolchain
ENV PATH="${CT_PREFIX}/arm-unknown-linux-uclibcgnueabihf/bin:${PATH}"

# Install build dependencies
# Reference: https://github.com/crosstool-ng/crosstool-ng/blob/master/testing/docker/ubuntu22.04/Dockerfile
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    gperf \
    bison \
    flex \
    texinfo \
    help2man \
    make \
    libncurses5-dev \
    python3-dev \
    autoconf \
    automake \
    libtool \
    libtool-bin \
    gawk \
    wget \
    bzip2 \
    xz-utils \
    unzip \
    patch \
    libstdc++6 \
    rsync \
    git \
    meson \
    ninja-build \
    ca-certificates \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user for building the toolchain
# crosstool-ng refuses to run as root for security reasons
RUN useradd -m -s /bin/bash builder && \
    mkdir -p ${CT_PREFIX} && \
    chown -R builder:builder ${CT_PREFIX}

# Build crosstool-ng as non-root user
WORKDIR /tmp/crosstool-ng-build
RUN git clone --depth 1 --branch crosstool-ng-${CROSSTOOL_NG_VERSION} \
    https://github.com/crosstool-ng/crosstool-ng.git . && \
    chown -R builder:builder /tmp/crosstool-ng-build

USER builder
RUN echo "Building crosstool-ng ${CROSSTOOL_NG_VERSION}..." && \
    ./bootstrap && \
    ./configure --enable-local && \
    make -j$(nproc)

# Configure and build the ARM uClibc toolchain
RUN echo "Configuring arm-unknown-linux-uclibcgnueabihf toolchain..." && \
    ./ct-ng arm-unknown-linux-uclibcgnueabihf && \
    echo "Building toolchain (this may take 30-60 minutes)..." && \
    ./ct-ng build && \
    echo "Toolchain build completed!"

# Switch back to root for cleanup and final setup
USER root
RUN rm -rf /tmp/crosstool-ng-build

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create output directory
RUN mkdir -p /output

# Set working directory
WORKDIR /workspace

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
