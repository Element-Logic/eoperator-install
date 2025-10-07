#!/usr/bin/env bash
set -euo pipefail

# ===== Configuration via .env (optional) =====
if [[ -f ".env" ]]; then
  set -a                    # auto-export all variables defined from now on
  # shellcheck disable=SC1091
  . ./.env                  # source .env (respects quotes and spaces)
  set +a
fi

# ===== Required variables (can also be set as environment variables) =====
: "${OCTOPUS_SERVER_URL:?Set OCTOPUS_SERVER_URL, e.g. https://elementlogic.octopus.app/}"
: "${OCTOPUS_SPACE:?Set OCTOPUS_SPACE, e.g. Element Logic}"
: "${OCTOPUS_API_KEY:?Set OCTOPUS_API_KEY to a valid API key (do NOT hard-code in script)}"
: "${TENTACLE_INSTANCE:=Tentacle}"                # Instance name on this machine
: "${MACHINE_NAME:=eOperator-Ubuntu}"             # Display name in Octopus
: "${MACHINE_ENVIRONMENTS:=Production,ubuntu}"    # Comma-separated
: "${MACHINE_ROLES:=eOperator}"                   # Comma-separated
: "${APP_DIR:=/home/Octopus/Applications}"        # Where Octopus will deploy apps
: "${SERVER_COMMS_PORT:=10943}"                   # Octopus server comms port (default)
: "${CREATE_NEW_CERT:=true}"                      # true|false
: "${RESET_TRUST:=true}"                          # true|false
: "${AUTO_START:=true}"                           # true|false

echo "==> Octopus Server: $OCTOPUS_SERVER_URL"
echo "==> Space:          $OCTOPUS_SPACE"
echo "==> Instance:       $TENTACLE_INSTANCE"
echo "==> Machine name:   $MACHINE_NAME"
echo "==> Environments:   $MACHINE_ENVIRONMENTS"
echo "==> Roles:          $MACHINE_ROLES"
echo "==> App dir:        $APP_DIR"
echo "==> Comms port:     $SERVER_COMMS_PORT"
echo

# ===== Functions =====
apt_has_octopus() {
  if apt-cache policy 2>/dev/null | grep -qE 'https?://apt\.octopus\.com'; then
    return 0
  else
    return 1
  fi
}

# ===== Add Octopus APT repo (once) =====
if ! apt_has_octopus; then
  echo "==> Adding Octopus APT repository…"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends gnupg curl ca-certificates apt-transport-https
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://apt.octopus.com/public.key | sudo gpg --dearmor -o /etc/apt/keyrings/octopus.gpg
  sudo chmod a+r /etc/apt/keyrings/octopus.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/octopus.gpg] https://apt.octopus.com/ stable main" \
    | sudo tee /etc/apt/sources.list.d/octopus.list >/dev/null
else
  echo "==> Octopus APT repository already present. Skipping."
fi

# ===== Install Tentacle (apt) =====
if ! command -v tentacle >/dev/null 2>&1; then
  echo "==> Installing Octopus Tentacle for Linux..."
  # Official repo package name is 'tentacle'
  # If the repo is already configured, this is enough:
  sudo apt-get update -y
  sudo apt-get install -y Tentacle || {
    echo "E: 'tentacle' package not found via default repos."
    echo "   If needed, add the Octopus repo per official docs, then re-run:"
    echo "   https://octopus.com/docs/infrastructure/deployment-targets/tentacle/linux"
    exit 1
  }
else
  echo "==> Tentacle already installed. Skipping apt install."
fi

# ===== Create/Update Instance =====
CONFIG_DIR="/etc/octopus/${TENTACLE_INSTANCE}"
CONFIG_FILE="${CONFIG_DIR}/tentacle.config"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "==> Creating new Tentacle instance: ${TENTACLE_INSTANCE}"
  sudo Tentacle create-instance \
    --instance "${TENTACLE_INSTANCE}" \
    --config "${CONFIG_FILE}" \
    --console

  if [[ "${CREATE_NEW_CERT}" == "true" ]]; then
    sudo Tentacle new-certificate \
      --instance "${TENTACLE_INSTANCE}" \
      --if-blank \
      --console
  fi

  sudo mkdir -p "${APP_DIR}"
  sudo Tentacle configure \
    --instance "${TENTACLE_INSTANCE}" \
    --app "${APP_DIR}" \
    --noListen "True" \
    --console

  # Polling comms (active) to Server
  sudo Tentacle configure \
    --instance "${TENTACLE_INSTANCE}" \
    --trust "https://dummy.invalid" >/dev/null 2>&1 || true  # noop to ensure key exists
else
  echo "==> Instance '${TENTACLE_INSTANCE}' already exists. Updating configuration…"
  sudo Tentacle configure \
    --instance "${TENTACLE_INSTANCE}" \
    --app "${APP_DIR}" \
    --noListen "True" \
    --console
fi

if [[ "${RESET_TRUST}" == "true" ]]; then
  echo "==> Resetting trust to avoid stale thumbprints…"
  sudo Tentacle configure \
    --instance "${TENTACLE_INSTANCE}" \
    --reset-trust \
    --console
fi

# ===== Register with Octopus =====
echo "==> Registering with Octopus (polling) …"
# Use --force so the registration is idempotent (safe to re-run)
sudo Tentacle register-with \
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

# ===== Install/Start service =====
if [[ "${AUTO_START}" == "true" ]]; then
  echo "==> Installing and starting Tentacle service…"
  sudo Tentacle service --instance "${TENTACLE_INSTANCE}" --install --console
  sudo Tentacle service --instance "${TENTACLE_INSTANCE}" --start --console
  sudo systemctl enable "Tentacle@${TENTACLE_INSTANCE}.service" >/dev/null 2>&1 || true
fi

# ===== Show configuration for verification =====
echo
echo "==> Current configuration (JSON):"
sudo Tentacle show-configuration --instance="${TENTACLE_INSTANCE}" | sed 's/API-[-A-Z0-9]*/API-REDACTED/g'

echo
echo "✅ Done. Verify the target appears in Octopus: Infrastructure → Deployment targets."
