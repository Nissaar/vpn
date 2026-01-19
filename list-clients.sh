#!/bin/bash

# List all issued OpenVPN client certificates

OPENVPN_CONTAINER="openvpn"
ISSUED_DIR="/etc/openvpn/pki/issued"

echo "[*] OpenVPN Client Certificates:"
echo ""
echo "Certificate Name | Issued Date | Expiration Date | Status"
echo "-----------------------------------------------------------"

docker exec $OPENVPN_CONTAINER bash -c "
cd $ISSUED_DIR
for cert in *.crt; do
    if [ \"\$cert\" != \"server.crt\" ]; then
        ISSUED=\$(openssl x509 -in \"\$cert\" -noout -startdate | cut -d= -f2)
        EXPIRATION=\$(openssl x509 -in \"\$cert\" -noout -enddate | cut -d= -f2)
        NAME=\$(basename \"\$cert\" .crt)
        echo \"\$NAME | \$ISSUED | \$EXPIRATION\"
    fi
done
"

echo ""
echo "[*] Server Certificate:"
docker exec $OPENVPN_CONTAINER openssl x509 -in "$ISSUED_DIR/server.crt" -noout -subject -dates
