#!/bin/bash

CONTAINER_NAME="openvpn"
STATUS_FILE="/tmp/openvpn-status.log"

echo "📡 Fetching OpenVPN connection status from container: $CONTAINER_NAME"
echo ""

# Check the raw status file content inside the container for debug
docker exec "$CONTAINER_NAME" cat "$STATUS_FILE"

# Now attempt to filter and display relevant client information
echo ""
docker exec "$CONTAINER_NAME" cat "$STATUS_FILE" | awk '
BEGIN {
    print "Common Name          Real IP              Virtual IP        Connected Since"
    print "--------------------------------------------------------------------------------"
}
# Capture client list section
$1 == "CLIENT_LIST" {
    clients[$2] = sprintf("%-20s %-19s %-17s %s", $2, $3, "-", $6 " " $7 " " $8)
}
# Capture routing table section to match virtual IP
$1 == "ROUTING_TABLE" {
    # Update client info with Virtual IP from ROUTING_TABLE section
    if ($2 in clients) {
        clients[$2] = sprintf("%-20s %-19s %-17s %s", $2, $4, $1, "-")
    }
}
# Exit once global stats section is reached
$1 == "GLOBAL" { exit }
END {
    if (length(clients) == 0) {
        print "No clients found. Please check your OpenVPN logs."
    } else {
        for (client in clients) {
            print clients[client]
        }
    }
    print "✅ Done."
}'

