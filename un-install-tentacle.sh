#!/usr/bin/env bash
set -euo pipefail
: "${TENTACLE_INSTANCE:=eOperator-Tentacle}"

sudo systemctl stop "Tentacle@${TENTACLE_INSTANCE}.service" || true
sudo tentacle service --instance "${TENTACLE_INSTANCE}" --stop --console || true
sudo tentacle service --instance "${TENTACLE_INSTANCE}" --uninstall --console || true
sudo tentacle delete-instance --instance "${TENTACLE_INSTANCE}" --console || true
sudo rm -rf "/etc/octopus/${TENTACLE_INSTANCE}"

echo "Optionally remove package:"
echo "  sudo apt-get remove -y tentacle"
