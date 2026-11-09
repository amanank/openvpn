#!/bin/bash

declare -A latest_expiry
declare -A latest_date
declare -A valid_count

CONTAINER_NAME="openvpn"
now_epoch=$(date -u +%s)

while IFS='|' read -r cert_status expiry client
do
    formatted=$(printf "20%s-%s-%s %s:%s:%s UTC" \
        "${expiry:0:2}" \
        "${expiry:2:2}" \
        "${expiry:4:2}" \
        "${expiry:6:2}" \
        "${expiry:8:2}" \
        "${expiry:10:2}")

    expiry_epoch=$(date -u -d "$formatted" +%s)

    # Track latest certificate expiry for this client
    if [[ -z "${latest_expiry[$client]}" || ${latest_expiry[$client]} -lt $expiry_epoch ]]; then
        latest_expiry[$client]=$expiry_epoch
        latest_date[$client]="$formatted"
    fi

    # Count only certificates that are both non-revoked and non-expired
    if [[ "$cert_status" == "V" && "$expiry_epoch" -gt "$now_epoch" ]]; then
        ((valid_count[$client]++))
    fi

done < <(
    docker exec "$CONTAINER_NAME" awk '
    {
        client=$NF
        sub("^/CN=","",client)
        print $1 "|" $2 "|" client
    }
    ' /etc/openvpn/pki/index.txt
)

echo "Fetching client certificate summary from container: $CONTAINER_NAME"
echo "------------------------------------------------------------------------------------------------"
printf "%-10s %-23s %-11s %s\n" "STATUS" "LATEST EXPIRY (UTC)" "VALID CERTS" "CLIENT NAME"
echo "------------------------------------------------------------------------------------------------"

for client in "${!latest_expiry[@]}"
do
    valid=${valid_count[$client]:-0}
    expiry_epoch=${latest_expiry[$client]}
    expiry_date=${latest_date[$client]}

    if (( valid > 1 )); then
        status="MULTIPLE"
    elif (( valid == 1 )); then
        status="VALID"
    elif (( expiry_epoch < now_epoch )); then
        status="EXPIRED"
    else
        status="REVOKED"
    fi

    printf "%-10s %-23s %-11s %s\n" \
        "$status" \
        "$expiry_date" \
        "$valid" \
        "$client"

done | sort -r -k4
