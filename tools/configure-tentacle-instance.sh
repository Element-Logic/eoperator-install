#!/usr/bin/env bash
# configure_tentacle_instance.sh
# Purpose: Create/configure/register a Tentacle instance ONLY (no APT/repo install).
# Requires: Octopus Tentacle CLI already installed (package 'tentacle').

set -euo pipefail

log()  { printf "\033[1;36m[INFO]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[ OK ]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "Please run as root (e.g., sudo bash $0)"
  fi
}

if [[ -f "../.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  . ../.env
  set +a
fi

# ----- Required variables -----
: "${OCTOPUS_SERVER_URL:?Set OCTOPUS_SERVER_URL, e.g. https://example.octopus.app/}"
: "${OCTOPUS_SPACE:?Set OCTOPUS_SPACE, e.g. My Space}"
: "${OCTOPUS_API_KEY:?Set OCTOPUS_API_KEY (do NOT commit to source)}"

# ----- Optional / defaults -----
: "${TENTACLE_INSTANCE:=Tentacle}"
: "${MACHINE_NAME:=eOperator-Ubuntu}"
: "${MACHINE_ENVIRONMENTS:=Production,ubuntu}"
: "${MACHINE_ROLES:=eOperator}"
: "${APP_DIR:=/home/Octopus/Applications}"
: "${SERVER_COMMS_PORT:=10943}"
: "${CREATE_NEW_CERT:=true}"   # true|false
: "${RESET_TRUST:=true}"       # true|false
: "${AUTO_START:=true}"        # true|false

require_root

# ----- Locate Tentacle CLI (handles case differences) -----
detect_tentacle_bin() {
  if command -v Tentacle >/dev/null 2>&1; then
    echo "Tentacle"
  elif command -v tentacle >/dev/null 2>&1; then
    echo "tentacle"
  else
    return 1
  fi
}

if ! TENTACLE_BIN="$(detect_tentacle_bin)"; then
  fail "Tentacle CLI not found. Please install the 'tentacle' package first."
fi

# ----- Show effective configuration (mask API key) -----
API_MASK="${OCTOPUS_API_KEY:0:4}****"
echo
log "Effective configuration:"
echo "  Octopus Server:   $OCTOPUS_SERVER_URL"
echo "  Space:            $OCTOPUS_SPACE"
echo "  Instance:         $TENTACLE_INSTANCE"
echo "  Machine name:     $MACHINE_NAME"
echo "  Environments:     $MACHINE_ENVIRONMENTS"
echo "  Roles:            $MACHINE_ROLES"
echo "  App dir:          $APP_DIR"
echo "  Comms port:       $SERVER_COMMS_PORT"
echo "  Create cert:      $CREATE_NEW_CERT"
echo "  Reset trust:      $RESET_TRUST"
echo "  Auto start:       $AUTO_START"
echo "  API key (masked): $API_MASK"
echo

CONFIG_DIR="/etc/octopus/${TENTACLE_INSTANCE}"
CONFIG_FILE="${CONFIG_DIR}/tentacle.config"

# ----- Create / Update Instance -----
if [[ ! -f "$CONFIG_FILE" ]]; then
  log "Creating Tentacle instance: ${TENTACLE_INSTANCE}"
  "$TENTACLE_BIN" create-instance \
    --instance "${TENTACLE_INSTANCE}" \
    --config "${CONFIG_FILE}" \
    --console
  ok "Instance created"
else
  log "Instance '${TENTACLE_INSTANCE}' already exists at ${CONFIG_FILE}"
fi

# Ensure app directory exists
log "Ensuring application directory exists: ${APP_DIR}"
mkdir -p "${APP_DIR}"
ok "Application directory ready"

# Optionally create a certificate if blank
if [[ "${CREATE_NEW_CERT,,}" == "true" ]]; then
  log "Ensuring certificate exists (new if blank)"
  "$TENTACLE_BIN" new-certificate \
    --instance "${TENTACLE_INSTANCE}" \
    --if-blank \
    --console
  ok "Certificate ensured"
fi

# Base configuration (no listening; polling mode)
log "Applying core configuration (noListen=True, app dir)"
"$TENTACLE_BIN" configure \
  --instance "${TENTACLE_INSTANCE}" \
  --app "${APP_DIR}" \
  --noListen "True" \
  --console
ok "Core configuration applied"

# Touch trust to ensure key material exists, then optionally reset trust
log "Priming trust store"
"$TENTACLE_BIN" configure \
  --instance "${TENTACLE_INSTANCE}" \
  --trust "https://dummy.invalid" >/dev/null 2>&1 || true
ok "Trust primed"

if [[ "${RESET_TRUST,,}" == "true" ]]; then
  log "Resetting trust to avoid stale thumbprints"
  "$TENTACLE_BIN" configure \
    --instance "${TENTACLE_INSTANCE}" \
    --reset-trust \
    --console
  ok "Trust reset"
fi

# ----- Register with Octopus (Polling / Active) -----
log "Registering with Octopus (polling/active)"
"$TENTACLE_BIN" register-with \
  --instance "${TENTACLE_INSTANCE}" \
  --server "${OCTOPUS_SERVER_URL}" \
  --apiKey "${OCTOPUS_API_KEY}" \
  --space "${OCTOPUS_SPACE}" \
  --name "${MACHINE_NAME}" \
  --environment "${MACHINE_ENVIRONMENTS}" \
  --role "${MACHINE_ROLES}" \
  --comms-style "TentacleActive" \
  --server-comms-port "${SERVER_COMMS_PORT}" \
  --force \
  --console
ok "Registration completed"

# ----- Install / Start service -----
if [[ "${AUTO_START,,}" == "true" ]]; then
  log "Installing Tentacle service for instance '${TENTACLE_INSTANCE}'"
  "$TENTACLE_BIN" service --instance "${TENTACLE_INSTANCE}" --install --console || {
    warn "Service install reported a problem (non-fatal in non-systemd environments)"
  }

  log "Starting Tentacle service"
  "$TENTACLE_BIN" service --instance "${TENTACLE_INSTANCE}" --start --console || {
    warn "Service start reported a problem (check logs/systemd availability)"
  }

  # Best-effort enablement on systemd systems
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable "Tentacle@${TENTACLE_INSTANCE}.service" >/dev/null 2>&1 || true
  fi
  ok "Service install/start attempted"
else
  warn "AUTO_START=false; skipping service installation/start"
fi

# ----- Show final configuration -----
echo
log "Current configuration (API key redacted):"
"$TENTACLE_BIN" show-configuration --instance="${TENTACLE_INSTANCE}" \
  | sed 's/API-[-A-Z0-9]*/API-REDACTED/g' || true

echo
ok "✅ Done. Verify the target appears in Octopus: Infrastructure → Deployment targets."
