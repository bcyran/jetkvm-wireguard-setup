# JetKVM WireGuard Installation

> **⚠️ AI-Generated Content:** This project was mostly generated using AI assistance.

> **⚠️ Disclaimer:** Use at your own risk. The author takes no responsibility for any issues, damages, or consequences that may arise from using this software.

Automated installation script and Docker-based cross-compilation environment for deploying WireGuard VPN on JetKVM devices. This project is based on the excellent blog post by Simon Beginn: [WireGuard VPN on a JetKVM](https://simonmicro.de/blog/hacking/wireguard-vpn-on-a-jetkvm).

## Overview

The JetKVM device runs on ARM architecture with uClibc instead of the standard glibc, which means you need a specialized cross-compilation toolchain to build binaries that work on the device. This project provides:

1. **Automated installation script** - One-command deployment of WireGuard to your JetKVM
2. **Cross-compilation toolchain** - ARM uClibc toolchain using crosstool-ng
3. **Example configurations** - Pre-configured templates for server and client setups
4. **Boot persistence** - Automatic WireGuard startup on device reboot

## Quick Start (Automated Installation)

### 1. Prerequisites

- Podman or Docker installed on your host machine
- SSH access to your JetKVM device (developer mode enabled)
- WireGuard keys generated (see [Configuration](#configuration) section)

### 2. Configure

```bash
# Copy the example configuration
cp .env.example .env

# Edit the configuration
nano .env
```

Set at minimum:

- `JETKVM_IP` - Your JetKVM device IP address
- `WIREGUARD_CONFIG` - Path to your WireGuard config file (see `examples/`)

### 3. Prepare WireGuard Configuration

Choose a configuration template based on your needs:

**For a WireGuard server:**

```bash
cp examples/wg0-server.conf wg0.conf
nano my-server.conf  # Edit and add your keys
```

**For a WireGuard client:**

```bash
cp examples/wg0-client.conf wg0.conf
nano my-client.conf  # Edit and add your keys
```

**Important:** These configs are for the `wg` command (not `wg-quick`). Do NOT include `Interface.Address` - it will be set via the `.env` file.

### 4. Install

```bash
./install-wireguard.sh
```

That's it! The script will:

- Build the WireGuard binary (first run takes 30-60 minutes for cross-compilation)
- Transfer files to your JetKVM via SSH
- Configure WireGuard
- Set up automatic start on boot

## Configuration

### Generate WireGuard Keys

On your host machine:

```bash
# Generate server/device keys
wg genkey | tee private.key | wg pubkey > public.key

# Generate peer keys (for each client/server you'll connect to)
wg genkey | tee peer-private.key | wg pubkey > peer-public.key
```

### Environment Variables (.env)

| Variable | Description | Default |
|----------|-------------|---------|
| `JETKVM_IP` | IP address of your JetKVM | **Required** |
| `JETKVM_USER` | SSH username | `root` |
| `JETKVM_SSH_PORT` | SSH port | `22` |
| `WIREGUARD_INTERFACE` | Interface name | `wg0` |
| `WIREGUARD_IP` | VPN IP address with subnet | `192.168.2.1/24` |
| `WIREGUARD_CONFIG` | Path to config file | **Required** |
| `CONTAINER_RUNTIME` | `podman` or `docker` | Auto-detect (prefers podman) |
| `FORCE_BUILD` | Force rebuild of binary | `no` |
| `BOOT_DELAY` | Seconds to wait before starting WireGuard on boot | `30` |

### Configuration Examples

See the `examples/` directory for:

- **wg0-server.conf** - Server configuration with one peer
- **wg0-client.conf** - Client configuration connecting to a server

Both files include detailed comments explaining each setting.

## Managing WireGuard on JetKVM

After installation, you can manage WireGuard by SSHing into your JetKVM:

```bash
# Show current status
wg show

# Stop WireGuard
/userdata/wg-starter stop

# Start WireGuard
/userdata/wg-starter start

# Restart WireGuard
/userdata/wg-starter restart

# View boot logs
cat /tmp/wg-starter-log.txt
```

## Advanced Configuration

### Custom WireGuard Tools Version

You can build different versions of wireguard-tools:

```bash
docker run --rm \
  -v $(pwd)/output:/output \
  -e WIREGUARD_TOOLS_VERSION=v1.0.20210914 \
  jetkvm-wireguard-builder
```

### Build-Time Configuration

You can customize the toolchain versions during image build:

```bash
docker build \
  --build-arg UBUNTU_VERSION=24.04 \
  --build-arg CROSSTOOL_NG_VERSION=1.27.0 \
  -t jetkvm-wireguard-builder .
```

**Available Build Arguments:**

- `UBUNTU_VERSION` - Base Ubuntu version (default: `25.10`)
- `CROSSTOOL_NG_VERSION` - crosstool-ng version (default: `1.28.0`)

## Important Notes

### First-Time Build

The initial build takes 30-60 minutes because it compiles:

- Complete GCC cross-compiler for ARM
- Binutils for ARM architecture
- uClibc C library
- Supporting libraries and tools

Subsequent runs use the cached image and complete in seconds.

### wg vs wg-quick

The JetKVM uses BusyBox with a minimal shell environment and does NOT have `bash` available. This means:

- ✅ `wg` command works (compiled C binary)
- ❌ `wg-quick` does NOT work (requires bash)

Because of this, your WireGuard config files must be compatible with the plain `wg` command:

**Remove these directives** (they are wg-quick specific):

- `Interface.Address` - Set via `.env` file instead
- `Interface.DNS`
- `Interface.PostUp` / `Interface.PostDown`
- `Interface.Table`

The installation script handles setting the IP address automatically based on your `.env` configuration.

### Boot Persistence

The installation creates a boot script at `/userdata/wg-starter` and symlinks it to `/etc/init.d/S99wg-starter`.

**Note:** This symlink will be lost during JetKVM firmware updates. After updating firmware, you'll need to:

1. Re-create the symlink:

   ```bash
   ssh root@<jetkvm-ip> "ln -sf /userdata/wg-starter /etc/init.d/S99wg-starter"
   ```

2. Or re-run the installation script (it will skip the build if binary exists)

The `/userdata` partition persists across updates, so your binary and config will remain intact.

### File Transfer Method

This script uses SSH with base64 encoding for file transfer because:

- `scp` doesn't work (JetKVM lacks `sftp-server` binary)
- No firewall ports need to be opened (uses existing SSH connection)
- Base64 is available on all Linux systems
- Transfer integrity is verified via MD5 checksums

## Credits

Based on the blog post: [WireGuard VPN on a JetKVM](https://simonmicro.de/blog/hacking/wireguard-vpn-on-a-jetkvm) by Simon Beginn.
