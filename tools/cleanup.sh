#!/usr/bin/env bash
# cleanup_octopus_tentacle.sh
# Completely remove Octopus Tentacle (and optional Octopus Server) from Ubuntu/WSL.
# Safe to run multiple times; it ignores missing items and keeps going.

set -o nounset
set -o pipefail

log() { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }
run()  { bash -c "$*" || true; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    err "Please run as root: sudo bash $0"
    exit 1
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

systemd_active=false
detect_systemd() {
  if has_cmd systemctl; then
    # On WSL, systemd may or may not be enabled. Treat "is-system-running" != "running" as inactive.
    if systemctl is-system-running --quiet 2>/dev/null; then
      systemd_active=true
    else
      systemd_active=false
    fi
  fi
}

stop_services() {
  log "Stopping Tentacle/Octopus services (if any)..."
  if $systemd_active; then
    run "systemctl stop tentacle"
    run "systemctl disable tentacle"
    run "systemctl stop octopus"
    run "systemctl disable octopus"
  else
    warn "systemd not active; killing Tentacle/Octopus processes directly (WSL or minimal system)..."
  fi

  # Kill lingering processes either way
  run "pkill -f '[Tt]entacle'"
  run "pkill -f '[Oo]ctopus'"
}

purge_packages() {
  log "Purging APT packages..."
  if has_cmd apt-get; then
    run "apt-get remove --purge -y tentacle"
    run "apt-get remove --purge -y octopusdeploy"
    run "apt-get autoremove -y"
    run "apt-get autoclean"
  else
    warn "apt-get not available; skipping package purge."
  fi

  # In case installed via snap
  if has_cmd snap; then
    log "Removing possible Snap packages..."
    run "snap remove tentacle"
    run "snap remove octopusdeploy"
  fi
}

remove_repo_and_key() {
  log "Removing Octopus APT repo and key..."
  run "rm -f /etc/apt/sources.list.d/octopus.list"
  run "rm -f /etc/apt/keyrings/octopus.gpg"
  if has_cmd apt-get; then
    run "apt-get update"
  fi
}

remove_files() {
  log "Deleting config, binaries, logs, and data..."
  # Tentacle / Octopus common paths
  run "rm -rf /etc/octopus"
  run "rm -rf /opt/octopus"
  run "rm -rf /var/log/octopus"
  run "rm -rf /var/lib/octopus"
  # User-scoped configs
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    run "rm -rf ~${SUDO_USER}/.octopus"
  fi
  run "rm -rf ~/.octopus"

  # Remove possible service unit files if lingering
  run "rm -f /etc/systemd/system/tentacle.service"
  run "rm -f /lib/systemd/system/tentacle.service"
  run "rm -f /etc/systemd/system/octopus.service"
  run "rm -f /lib/systemd/system/octopus.service"
  if $systemd_active; then
    run "systemctl daemon-reload"
  fi
}

remove_users() {
  log "Removing tentacle/octopus users if they exist..."
  if id -u tentacle >/dev/null 2>&1; then
    run "deluser --remove-home tentacle"
  fi
  if id -u octopus >/dev/null 2>&1; then
    run "deluser --remove-home octopus"
  fi
}

verify() {
  log "Verification:"
  if has_cmd dpkg; then
    if dpkg -l | egrep -i 'tentacle|octopusdeploy' >/dev/null 2>&1; then
      warn "Packages still present:"
      run "dpkg -l | egrep -i 'tentacle|octopusdeploy'"
    else
      log "No Tentacle/Octopus APT packages installed."
    fi
  fi

  if pgrep -fa '[Tt]entacle|[Oo]ctopus' >/dev/null 2>&1; then
    warn "Processes still running:"
    run "pgrep -fa '[Tt]entacle|[Oo]ctopus'"
  else
    log "No Tentacle/Octopus processes running."
  fi

  if ls /etc/apt/sources.list.d 2>/dev/null | grep -qi octopus; then
    warn "Octopus APT source still present:"
    run "ls -l /etc/apt/sources.list.d/*octopus*"
  else
    log "Octopus APT source removed."
  fi

  leftover_paths=(
    "/etc/octopus"
    "/opt/octopus"
    "/var/log/octopus"
    "/var/lib/octopus"
    "$HOME/.octopus"
  )
  for p in "${leftover_paths[@]}"; do
    if [ -e "$p" ]; then
      warn "Leftover path exists: $p"
    fi
  done
}

main() {
  require_root
  detect_systemd
  stop_services
  purge_packages
  remove_repo_and_key
  remove_files
  remove_users
  verify
  log "Cleanup complete."
}

main "$@"
