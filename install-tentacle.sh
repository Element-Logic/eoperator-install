#!/usr/bin/env bash
# setup_tentacle.sh
# Main entry point — makes sub-scripts executable and runs them in order.

set -euo pipefail

log()  { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

# Filenames
INSTALL_SCRIPT="./tools/install-octopus-tentacle-tools.sh"
CONFIG_SCRIPT="./tools/configure-tentacle-instance.sh"

# Ensure both scripts exist
if [[ ! -f "$INSTALL_SCRIPT" ]]; then
  fail "Missing $INSTALL_SCRIPT in the current directory"
fi

if [[ ! -f "$CONFIG_SCRIPT" ]]; then
  fail "Missing $CONFIG_SCRIPT in the current directory"
fi

# Make them executable
log "Making sub-scripts executable"
chmod +x "$INSTALL_SCRIPT" "$CONFIG_SCRIPT"
ok "Sub-scripts are executable"

# Step 1. Run installation script
log "=== Running Tentacle install script ==="
sudo "$INSTALL_SCRIPT"
ok "Tentacle installation completed"

# Run configuration script
log "=== Running Tentacle instance configuration script ==="
sudo "$CONFIG_SCRIPT"
ok "Tentacle instance configuration completed"

echo
ok "🎉 All done. Tentacle should now be installed, registered, and running."
echo "👉 Verify in Octopus: Infrastructure → Deployment Targets"
