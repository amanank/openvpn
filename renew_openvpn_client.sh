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

echo "🔍 Checking for active certificates..."

ACTIVE_COUNT=$(docker exec "$CONTAINER" awk -v client="$CLIENT" '
$1=="V" && $NF=="/CN=" client { count++ }
END { print count+0 }
' /etc/openvpn/pki/index.txt)

if [ "$ACTIVE_COUNT" -gt 0 ]; then
  echo "⚠️ Found $ACTIVE_COUNT active certificate(s) for $CLIENT"

  # Revoke all active certificates for this CN
  while docker exec "$CONTAINER" easyrsa revoke "$CLIENT"
  do
    echo "✅ Revoked one certificate for $CLIENT"
  done >/dev/null 2>&1

else
  echo "ℹ️ No active certificates found for $CLIENT"
fi

echo "🔄 Regenerating CRL..."
docker exec -it "$CONTAINER" easyrsa gen-crl

echo "🧹 Cleaning old certificate files..."
docker exec -it "$CONTAINER" bash -c "
rm -f \
  /etc/openvpn/pki/issued/$CLIENT.crt \
  /etc/openvpn/pki/private/$CLIENT.key \
  /etc/openvpn/pki/reqs/$CLIENT.req
"

echo "🔨 Creating new certificate..."
docker exec -it "$CONTAINER" easyrsa build-client-full "$CLIENT" nopass

echo "📁 Preparing output directory..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "📦 Exporting client configuration..."
docker exec "$CONTAINER" ovpn_getclient "$CLIENT" > \
  "$OUTPUT_DIR/$CLIENT.ovpn"

echo
echo "✅ Renewal complete"
echo "📄 Config: $OUTPUT_DIR/$CLIENT.ovpn"


