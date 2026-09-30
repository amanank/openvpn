#!/bin/bash

set -euo pipefail

# Usage:
#   sudo ./remove_openvpn_client.sh <client-name>
#
# Revokes ALL currently-valid certificate records for the specified
# client CN, including duplicate certificates.
#
# Historical PKI records are retained in index.txt as revoked ("R").

CONTAINER="openvpn"
OUTPUT_BASE="./openvpn-data/clients"

CLIENT="${1:-}"

if [ -z "$CLIENT" ]; then
    echo "ERROR: Please provide a client name"
    echo "Usage: $0 <client-name>"
    exit 1
fi

if [[ ! "$CLIENT" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: Invalid client name: $CLIENT"
    exit 1
fi

echo
echo "OpenVPN client removal: $CLIENT"
echo

# ------------------------------------------------------------
# Validate container
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
# Find all V records for this CN
# ------------------------------------------------------------

mapfile -t SERIALS < <(
    docker exec "$CONTAINER" awk -v client="$CLIENT" '
        $1 == "V" && $NF == "/CN=" client {
            print $3
        }
    ' /etc/openvpn/pki/index.txt
)

COUNT="${#SERIALS[@]}"

echo "Valid certificate records found: $COUNT"

if [ "$COUNT" -gt 0 ]; then

    echo
    echo "Certificates to revoke:"

    for SERIAL in "${SERIALS[@]}"; do
        echo "  $SERIAL"
    done

    echo

    # --------------------------------------------------------
    # Revoke each certificate independently.
    #
    # Duplicate CNs cannot reliably be revoked simply by
    # repeatedly calling:
    #
    #     easyrsa revoke <client>
    #
    # EasyRSA operates on pki/issued/<client>.crt.
    #
    # certs_by_serial retains each individual certificate, so
    # place each certificate into the expected issued location
    # before asking EasyRSA to revoke it.
    # --------------------------------------------------------

    for SERIAL in "${SERIALS[@]}"; do

        SERIAL_CERT="/etc/openvpn/pki/certs_by_serial/$SERIAL.pem"
        ISSUED_CERT="/etc/openvpn/pki/issued/$CLIENT.crt"

        echo "Revoking:"
        echo "  Client: $CLIENT"
        echo "  Serial: $SERIAL"

        if ! docker exec "$CONTAINER" test -f "$SERIAL_CERT"; then
            echo
            echo "ERROR: Certificate file not found:"
            echo "  $SERIAL_CERT"
            echo
            echo "Aborting rather than modifying the PKI."
            exit 1
        fi

        docker exec "$CONTAINER" \
            cp "$SERIAL_CERT" "$ISSUED_CERT"

        # -it is required because this CA's private key is
        # password protected and EasyRSA prompts for it.
        docker exec -it "$CONTAINER" \
            easyrsa revoke "$CLIENT"

        echo "Revoked: $SERIAL"
        echo
    done

    # --------------------------------------------------------
    # Generate one new CRL after all revocations
    # --------------------------------------------------------

    echo "Regenerating certificate revocation list..."

    docker exec -it "$CONTAINER" \
        easyrsa gen-crl

else

    echo "No valid certificates need revoking."

fi

# ------------------------------------------------------------
# Clean remaining client-specific files
# ------------------------------------------------------------

echo
echo "Removing remaining client certificate material..."

docker exec "$CONTAINER" rm -f \
    "/etc/openvpn/pki/issued/$CLIENT.crt" \
    "/etc/openvpn/pki/private/$CLIENT.key" \
    "/etc/openvpn/pki/reqs/$CLIENT.req"

# ------------------------------------------------------------
# Remove exported profiles
#
# Support both layouts we've used:
#
# clients/client.ovpn
# clients/client/client.ovpn
# ------------------------------------------------------------

FLAT_PROFILE="$OUTPUT_BASE/$CLIENT.ovpn"
CLIENT_DIR="$OUTPUT_BASE/$CLIENT"

if [ -f "$FLAT_PROFILE" ]; then
    echo "Removing exported profile:"
    echo "  $FLAT_PROFILE"
    rm -f "$FLAT_PROFILE"
fi

if [ -d "$CLIENT_DIR" ]; then
    echo "Removing exported client directory:"
    echo "  $CLIENT_DIR"
    rm -rf "$CLIENT_DIR"
fi

# ------------------------------------------------------------
# Verify PKI state
# ------------------------------------------------------------

REMAINING=$(
    docker exec "$CONTAINER" awk -v client="$CLIENT" '
        $1 == "V" && $NF == "/CN=" client {
            count++
        }
        END {
            print count + 0
        }
    ' /etc/openvpn/pki/index.txt
)

if [ "$REMAINING" -ne 0 ]; then
    echo
    echo "ERROR: $REMAINING valid certificate record(s) still remain."
    echo "Manual investigation is required."
    exit 1
fi

echo
echo "============================================"
echo " OpenVPN client removed"
echo "============================================"
echo "Client:                 $CLIENT"
echo "Certificates revoked:   $COUNT"
echo "Valid records remaining: $REMAINING"
echo
