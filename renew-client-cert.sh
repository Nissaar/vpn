#!/bin/bash

# OpenVPN Certificate Renewal Script
# Renews expired client certificates

set -e

CLIENT_NAME="${1:?Error: Client name required. Usage: $0 <client-name>}"
SERVER_DOMAIN="${2:?Error: Server domain required}"
SERVER_PORT="${3:-1194}"

OPENVPN_CONTAINER="openvpn"
OPENVPN_DIR="/etc/openvpn"
ISSUED_DIR="$OPENVPN_DIR/pki/issued"
KEYS_DIR="$OPENVPN_DIR/pki/private"
CA_CERT="$OPENVPN_DIR/pki/ca.crt"
TA_KEY="$OPENVPN_DIR/ta.key"

OUTPUT_DIR="./client-configs"

echo "[*] Renewing certificate for client: $CLIENT_NAME"

# Check if certificate exists
if ! docker exec $OPENVPN_CONTAINER test -f "$ISSUED_DIR/$CLIENT_NAME.crt"; then
    echo "[!] Certificate not found for $CLIENT_NAME"
    echo "[*] Generating new certificate instead..."
else
    echo "[*] Revoking old certificate..."
    docker exec $OPENVPN_CONTAINER easyrsa revoke "$CLIENT_NAME"
fi

# Generate new key and certificate
echo "[*] Generating new certificate..."
docker exec $OPENVPN_CONTAINER easyrsa gen-req "$CLIENT_NAME" nopass
docker exec $OPENVPN_CONTAINER easyrsa sign-req client "$CLIENT_NAME"

echo "[+] Certificate renewed successfully"

# Copy certificates
mkdir -p "$OUTPUT_DIR"
docker cp "$OPENVPN_CONTAINER:$ISSUED_DIR/$CLIENT_NAME.crt" /tmp/
docker cp "$OPENVPN_CONTAINER:$KEYS_DIR/$CLIENT_NAME.key" /tmp/
docker cp "$OPENVPN_CONTAINER:$CA_CERT" /tmp/
docker cp "$OPENVPN_CONTAINER:$TA_KEY" /tmp/

# Recreate config files
CA_CONTENT=$(cat /tmp/ca.crt)
CERT_CONTENT=$(cat /tmp/$CLIENT_NAME.crt)
KEY_CONTENT=$(cat /tmp/$CLIENT_NAME.key)
TA_CONTENT=$(cat /tmp/ta.key)

cat > "$OUTPUT_DIR/$CLIENT_NAME-linux-embedded.ovpn" <<EOF
client
dev tun
proto udp
remote $SERVER_DOMAIN $SERVER_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_DHE_RSA_WITH_AES_256_GCM_SHA384
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3

# Split tunneling
route-nopull
route 10.0.0.0 255.0.0.0
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4

<ca>
$CA_CONTENT
</ca>

<cert>
$CERT_CONTENT
</cert>

<key>
$KEY_CONTENT
</key>

<tls-auth>
$TA_CONTENT
</tls-auth>
EOF

cat > "$OUTPUT_DIR/$CLIENT_NAME-windows-embedded.ovpn" <<EOF
client
dev tun
proto udp
remote $SERVER_DOMAIN $SERVER_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_DHE_RSA_WITH_AES_256_GCM_SHA384
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3
script-security 2

# Split tunneling
route-nopull
route 10.0.0.0 255.0.0.0
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4

<ca>
$CA_CONTENT
</ca>

<cert>
$CERT_CONTENT
</cert>

<key>
$KEY_CONTENT
</key>

<tls-auth>
$TA_CONTENT
</tls-auth>
EOF

# Cleanup
rm /tmp/ca.crt /tmp/$CLIENT_NAME.crt /tmp/$CLIENT_NAME.key /tmp/ta.key

echo ""
echo "[+] Certificate renewed and configs regenerated!"
echo "New files: $OUTPUT_DIR/$CLIENT_NAME-{linux,windows}-embedded.ovpn"
