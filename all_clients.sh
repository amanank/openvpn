#!/bin/bash

CONTAINER_NAME="openvpn"

echo "Fetching client certificate list from container: $CONTAINER_NAME"
echo "---------------------------------------------------------------"
echo -e "STATUS\tEXPIRY DATE (UTC)\tCLIENT NAME"
echo "---------------------------------------------------------------"

docker exec -i "$CONTAINER_NAME" bash -c '
  cd /etc/openvpn/pki || exit 1
  if [ ! -f index.txt ]; then
    echo "index.txt not found in /etc/openvpn/pki"
    exit 1
  fi

  awk '"'"'{
    status=$1
    expiry=$2
    client=$NF
    sub("CN=","",client)
    # Convert YYMMDDHHMMSSZ -> readable date
    cmd = "date -u -d \"20" substr(expiry,1,2) "-" substr(expiry,3,2) "-" substr(expiry,5,2) " " substr(expiry,7,2) ":" substr(expiry,9,2) ":" substr(expiry,11,2) " UTC\""
    cmd | getline formatted_date
    close(cmd)

    if (status=="V") status_text="VALID"
    else if (status=="E") status_text="EXPIRED"
    else if (status=="R") status_text="REVOKED"
    else status_text=status

    printf "%-8s\t%s\t%s\n", status_text, formatted_date, client
  }'"'"' index.txt
' | sort -k2
