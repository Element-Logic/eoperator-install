#!/usr/bin/env bash
# install_octopus_tentacle_tools.sh
# Purpose: Add Octopus APT repo and install Tentacle CLI & service only.
# Verbose output with clear error messages for each step.

set -euo pipefail

log()  { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "Please run this script as root (e.g., sudo bash $0)"
  fi
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command '$1' is not installed or not in PATH"
}

require_root
check_cmd curl
check_cmd gpg
check_cmd tee
check_cmd dpkg

log "Step 1: Updating APT index"
if apt-get update -y; then
  ok "APT index updated"
else
  fail "APT update failed"
fi

log "Step 2: Installing required packages (gnupg, curl, ca-certificates, apt-transport-https)"
if apt-get install -y --no-install-recommends gnupg curl ca-certificates apt-transport-https; then
  ok "Dependencies installed"
else
  fail "Failed to install dependencies"
fi

log "Step 3: Creating keyring directory /etc/apt/keyrings"
if install -m 0755 -d /etc/apt/keyrings; then
  ok "Keyring directory ready"
else
  fail "Failed to create /etc/apt/keyrings"
fi

KEYRING="/etc/apt/keyrings/octopus.gpg"
REPO_LIST="/etc/apt/sources.list.d/octopus.list"

log "Step 4: Downloading Octopus public key"
if curl -fsSL https://apt.octopus.com/public.key | gpg --dearmor -o "$KEYRING"; then
  ok "Public key added to $KEYRING"
else
  fail "Failed to download or import Octopus public key"
fi

log "Step 5: Setting key permissions"
if chmod a+r "$KEYRING"; then
  ok "Permissions on $KEYRING set"
else
  fail "Failed to chmod $KEYRING"
fi

log "Step 6: Adding Octopus APT repository"
ARCH=$(dpkg --print-architecture)
echo "Architecture detected: $ARCH"
cat <<EOF | tee "$REPO_LIST" >/dev/null
deb [arch=${ARCH} signed-by=${KEYRING}] https://apt.octopus.com/ stable main
EOF

if grep -q "apt.octopus.com" "$REPO_LIST"; then
  ok "Repository added at $REPO_LIST"
else
  fail "Repository file not created correctly"
fi

log "Step 7: Updating APT index again to include Octopus repo"
if apt-get update -y; then
  ok "APT index updated with Octopus repo"
else
  fail "APT update failed after adding Octopus repo"
fi

log "Step 8: Installing 'tentacle' package"
if apt-get install -y tentacle; then
  ok "Tentacle package installed successfully"
else
  fail "Failed to install Tentacle package (check above output)"
fi

log "Step 9: Verifying installation"
if command -v tentacle >/dev/null 2>&1; then
  ok "Tentacle CLI is available: $(command -v tentacle)"
elif command -v Tentacle >/dev/null 2>&1; then
  ok "Tentacle CLI is available (capital T): $(command -v Tentacle)"
else
  fail "Tentacle binary not found in PATH after install"
fi

log "Step 10: Normalizing binary name (creating lowercase symlink if needed)"
BIN_PATH="$(command -v tentacle || command -v Tentacle || true)"
if [ -n "$BIN_PATH" ]; then
  if [ ! -x /usr/local/bin/tentacle ] || [ "$(readlink -f /usr/local/bin/tentacle 2>/dev/null || true)" != "$BIN_PATH" ]; then
    sudo ln -sf "$BIN_PATH" /usr/local/bin/tentacle
    ok "Symlink created: /usr/local/bin/tentacle → $BIN_PATH"
  else
    ok "Symlink already points to $BIN_PATH"
  fi
else
  fail "No Tentacle binary found to symlink"
fi
