#!/bin/bash

# Revoke OpenVPN Client Certificate
# Usage: ./revoke-client.sh <client-name>

set -e

CLIENT_NAME="${1:?Error: Client name required. Usage: $0 <client-name>}"
OPENVPN_CONTAINER="openvpn"

echo "[*] Revoking certificate for client: $CLIENT_NAME"

# Revoke the certificate
docker exec $OPENVPN_CONTAINER easyrsa revoke "$CLIENT_NAME"

# Regenerate CRL (Certificate Revocation List)
docker exec $OPENVPN_CONTAINER easyrsa gen-crl

echo "[+] Certificate revoked successfully!"
echo "[*] The CRL has been updated. Clients using this certificate will be disconnected on next connection attempt."
echo ""
echo "To fully remove this client, delete the .ovpn file from client machines."
