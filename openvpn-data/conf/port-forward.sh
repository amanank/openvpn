#!/bin/bash

# Check if dig command is available
if ! command -v dig &> /dev/null; then
    echo "dig command not found. Installing bind-tools..."
    apk add --update bind-tools
fi

host_name="vpn_proxy"

ip_address=$(dig +short $host_name)

echo "IP address of $host_name is: $ip_address"

# Check if IP address is empty
if [ -z "$ip_address" ]; then
    echo "Error: IP address could not be resolved."
    exit 1
fi

# Remove existing forwarding rules for ports 80 and 443
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING

# Forward HTTP (port 80) to the resolved IP address
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $ip_address

# Forward HTTPS (port 443) to the resolved IP address
iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $ip_address


iptables -t nat -A POSTROUTING -j MASQUERADE

# Save the iptables rules
iptables-save > /etc/iptables/rules.v4


# Print iptables forward rules
echo "IP Tables Forward Rules:"
iptables -t nat -nvL
