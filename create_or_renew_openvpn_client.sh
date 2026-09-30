#!/bin/bash

set -euo pipefail

# Usage:
#   sudo ./create_or_renew_openvpn_client.sh <client-name>
#
# Behaviour:
#   0 valid certificates -> create
#   1 valid certificate  -> revoke and renew
#   >1 valid certificates -> abort; use remove_openvpn_client.sh first

CONTAINER="openvpn"
OUTPUT_BASE="./openvpn-data/clients"

# User who invoked sudo (or current user if not using sudo)
CALLING_USER="${SUDO_USER:-$(id -un)}"
CALLING_GROUP="$(id -gn "$CALLING_USER")"

CLIENT="${1:-}"

if [ -z "$CLIENT" ]; then
    echo "ERROR: Please provide a client name"
    echo "Usage: $0 <client-name>"
    exit 1
fi

if [[ ! "$CLIENT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: Invalid client name: $CLIENT"
    echo "Allowed characters: letters, numbers, '.', '_' and '-'"
    exit 1
fi

OUTPUT_DIR="$OUTPUT_BASE/$CLIENT"
OUTPUT_FILE="$OUTPUT_DIR/$CLIENT.ovpn"

echo "OpenVPN client: $CLIENT"
echo

# ------------------------------------------------------------
# Validate OpenVPN container
# ------------------------------------------------------------

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERROR: Docker container '$CONTAINER' does not exist"
    exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
    echo "ERROR: Docker container '$CONTAINER' is not running"
    exit 1
fi

# ------------------------------------------------------------
# Check existing valid certificates
# ------------------------------------------------------------

echo "Checking PKI..."

VALID_COUNT=$(
    docker exec "$CONTAINER" awk -v client="$CLIENT" '
        $1 == "V" && $NF == "/CN=" client {
            count++
        }
        END {
            print count + 0
        }
    ' /etc/openvpn/pki/index.txt
)

echo "Valid certificate records found: $VALID_COUNT"
echo

# ------------------------------------------------------------
# Refuse ambiguous duplicate state
# ------------------------------------------------------------

if [ "$VALID_COUNT" -gt 1 ]; then

    echo "ERROR: Multiple valid certificate records exist for '$CLIENT'."
    echo
    echo "Automatic renewal has been aborted."
    echo
    echo "Remove all existing certificates first:"
    echo "  sudo ./remove_openvpn_client.sh $CLIENT"
    echo
    echo "Then create the client again:"
    echo "  sudo $0 $CLIENT"

    exit 1
fi

# ------------------------------------------------------------
# Renew existing certificate
# ------------------------------------------------------------

if [ "$VALID_COUNT" -eq 1 ]; then

    echo "Existing certificate found."
    echo "Revoking certificate for '$CLIENT'..."

    docker exec -it "$CONTAINER" \
        easyrsa revoke "$CLIENT"

    echo "Regenerating CRL..."

    docker exec -it "$CONTAINER" \
        easyrsa gen-crl

    ACTION="Renewed"

else

    echo "No valid certificate found."
    echo "Creating new client."

    ACTION="Created"
fi

# ------------------------------------------------------------
# Remove stale certificate material
# ------------------------------------------------------------

echo "Cleaning stale client files..."

docker exec "$CONTAINER" rm -f \
    "/etc/openvpn/pki/issued/$CLIENT.crt" \
    "/etc/openvpn/pki/private/$CLIENT.key" \
    "/etc/openvpn/pki/reqs/$CLIENT.req"

# ------------------------------------------------------------
# Create certificate
# ------------------------------------------------------------

echo "Creating certificate..."

docker exec -it "$CONTAINER" \
    easyrsa build-client-full "$CLIENT" nopass

# ------------------------------------------------------------
# Verify exactly one valid record now exists
# ------------------------------------------------------------

NEW_VALID_COUNT=$(
    docker exec "$CONTAINER" awk -v client="$CLIENT" '
        $1 == "V" && $NF == "/CN=" client {
            count++
        }
        END {
            print count + 0
        }
    ' /etc/openvpn/pki/index.txt
)

if [ "$NEW_VALID_COUNT" -ne 1 ]; then
    echo "ERROR: Expected exactly one valid certificate after creation."
    echo "Found: $NEW_VALID_COUNT"
    exit 1
fi

# ------------------------------------------------------------
# Export OpenVPN profile
# ------------------------------------------------------------

echo "Preparing output directory..."

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "Exporting OpenVPN configuration..."

docker exec "$CONTAINER" \
    ovpn_getclient "$CLIENT" > "$OUTPUT_FILE"

if [ ! -s "$OUTPUT_FILE" ]; then
    echo "ERROR: Exported OpenVPN profile is empty"
    exit 1
fi

# The script normally runs under sudo, so shell redirection creates
# the exported profile as root. Return ownership to the invoking user.
chown "$CALLING_USER:$CALLING_GROUP" "$OUTPUT_FILE"


# Restrict profile because it contains private key material.
chmod 600 "$OUTPUT_FILE"


# ------------------------------------------------------------
# Complete
# ------------------------------------------------------------

echo
echo "============================================"
echo " OpenVPN client ready"
echo "============================================"
echo "Client: $CLIENT"
echo "Action: $ACTION"
echo "Config: $OUTPUT_FILE"
echo "Valid certificates: $NEW_VALID_COUNT"
echo
