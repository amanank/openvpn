#!/bin/bash

# Usage: ./renew_openvpn_client.sh <client-name>

CLIENT="$1"
CONTAINER="openvpn"
OUTPUT_BASE="./openvpn-data/clients"
OUTPUT_DIR="$OUTPUT_BASE/$CLIENT"

if [ -z "$CLIENT" ]; then
  echo "❌ Please provide a client name"
  echo "Usage: $0 <client-name>"
  exit 1
fi

echo "🔄 Renewing certificate for client: $CLIENT"

# Try revoking anyway (will fail gracefully if cert is invalid)
docker exec -it "$CONTAINER" easyrsa revoke "$CLIENT" || \
  echo "⚠️ Could not revoke $CLIENT (may already be expired/corrupted)"

# Update the CRL
docker exec -it "$CONTAINER" easyrsa gen-crl

# Full cleanup of old cert-related files inside container
docker exec -it "$CONTAINER" bash -c "rm -f \
  /etc/openvpn/pki/issued/$CLIENT.crt \
  /etc/openvpn/pki/private/$CLIENT.key \
  /etc/openvpn/pki/reqs/$CLIENT.req"

# Rebuild certificate (interactive – KEEP THIS)
docker exec -it "$CONTAINER" easyrsa build-client-full "$CLIENT" nopass

# ---- ONLY FIX: clean and use per-client output dir ----
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Generate OVPN file into the correct location
docker exec -it "$CONTAINER" ovpn_getclient "$CLIENT" > \
  "$OUTPUT_DIR/$CLIENT.ovpn"

echo "✅ Renewal complete. Config saved to: $OUTPUT_DIR/$CLIENT.ovpn"

