#!/bin/bash
#
# init-config.sh - generate the mandatory, host-side OpenXPKI runtime config
# that must NOT be committed (it contains secrets):
#
#   config/client.key                            CLI authentication private key
#   openxpki-config/config.d/system/cli.yaml     matching public key (CLI auth)
#   openxpki-config/config.d/system/crypto.yaml  svault datavault encryption key
#
# Safe to re-run: cli.yaml is always regenerated from the key; the datavault
# secret is only generated if it has not been set yet (it is never overwritten).
#
# Usage:  ./init-config.sh ["Role Name"]      (default role: "RA Operator")
#
set -euo pipefail

ROLE="${1:-RA Operator}"

cd "$(dirname "${BASH_SOURCE[0]}")"
SYS="openxpki-config/config.d/system"

if [ ! -d openxpki-config ]; then
  echo "ERROR: openxpki-config/ not found. Run 'make init' (or clone the config) first." >&2
  exit 1
fi

# 1. CLI private key (generate only if missing)
mkdir -p config
if [ ! -f config/client.key ]; then
  echo "Generating config/client.key ..."
  openssl ecparam -name prime256v1 -genkey -noout -out config/client.key
fi
chmod 644 config/client.key

# 2. cli.yaml - always (re)generated from the key, with correct indentation
PUB="$(openssl pkey -in config/client.key -pubout)"
{
  echo "# Public keys to authenticate requests over the CLI interface"
  echo "auth:"
  echo "    admin:"
  echo "        key: |"
  echo "$PUB" | sed 's/^/         /'
  echo "        role: $ROLE"
} > "$SYS/cli.yaml"
echo "Wrote $SYS/cli.yaml"

# 3. svault datavault secret - only if it is still the placeholder
if grep -q '##SVAULTKEY##' "$SYS/crypto.yaml"; then
  VAULT="$(openssl rand -hex 32)"
  sed -i.bak "s|.*##SVAULTKEY##.*|        value: $VAULT|" "$SYS/crypto.yaml"
  rm -f "$SYS/crypto.yaml.bak"
  echo ""
  echo "=================================================================="
  echo " Generated datavault secret (svault). SAVE THIS SOMEWHERE SAFE --"
  echo " losing it makes all encrypted data in the database unrecoverable:"
  echo ""
  echo "     $VAULT"
  echo "=================================================================="
else
  echo "svault already set in $SYS/crypto.yaml - leaving it unchanged."
fi

echo ""
echo "Config ready. Start it with:  docker compose up -d web"
echo "                       (or:)  podman-compose up -d web"
