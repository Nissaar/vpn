#!/bin/bash

# OpenVPN Client Certificate and Config Generator
# Usage: ./generate-client.sh <client-name> <server-domain> <server-port>

set -e

CLIENT_NAME="${1:?Error: Client name required. Usage: $0 <client-name> <server-domain> <server-port>}"
SERVER_DOMAIN="${2:?Error: Server domain required. Usage: $0 <client-name> <server-domain> <server-port>}"
SERVER_PORT="${3:-1194}"

# Paths
OPENVPN_CONTAINER="openvpn"
OPENVPN_DIR="/etc/openvpn"
KEYS_DIR="$OPENVPN_DIR/pki/private"
ISSUED_DIR="$OPENVPN_DIR/pki/issued"
CA_CERT="$OPENVPN_DIR/pki/ca.crt"
TA_KEY="$OPENVPN_DIR/ta.key"
DH_PARAM="$OPENVPN_DIR/pki/dh.pem"

OUTPUT_DIR="./client-configs"

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "[*] Generating certificate for client: $CLIENT_NAME"

# Generate client key and certificate request
docker exec $OPENVPN_CONTAINER easyrsa gen-req "$CLIENT_NAME" nopass

# Sign the certificate
docker exec $OPENVPN_CONTAINER easyrsa sign-req client "$CLIENT_NAME"

echo "[+] Certificate generated successfully"
echo "[*] Creating .ovpn configuration files..."

# Copy certificates from container
docker cp "$OPENVPN_CONTAINER:$ISSUED_DIR/$CLIENT_NAME.crt" /tmp/
docker cp "$OPENVPN_CONTAINER:$KEYS_DIR/$CLIENT_NAME.key" /tmp/
docker cp "$OPENVPN_CONTAINER:$CA_CERT" /tmp/
docker cp "$OPENVPN_CONTAINER:$TA_KEY" /tmp/

# Create OVPN config for Linux/Mac
cat > "$OUTPUT_DIR/$CLIENT_NAME-linux.ovpn" <<EOF
client
dev tun
proto udp
remote $SERVER_DOMAIN $SERVER_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert $CLIENT_NAME.crt
key $CLIENT_NAME.key
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_DHE_RSA_WITH_AES_256_GCM_SHA384
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3

# Split tunneling - route only specific traffic through VPN
# Comment out the lines below if you want full tunnel
route-nopull
route 10.0.0.0 255.0.0.0
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4
EOF

# Create OVPN config for Windows
cat > "$OUTPUT_DIR/$CLIENT_NAME-windows.ovpn" <<EOF
client
dev tun
proto udp
remote $SERVER_DOMAIN $SERVER_PORT
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert $CLIENT_NAME.crt
key $CLIENT_NAME.key
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_DHE_RSA_WITH_AES_256_GCM_SHA384
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3
script-security 2
up "C:\\\\Program Files\\\\OpenVPN\\\\bin\\\\openvpn-gui.exe"

# Split tunneling - route only specific traffic through VPN
# Comment out the lines below if you want full tunnel
route-nopull
route 10.0.0.0 255.0.0.0
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4
EOF

# Create combined config with embedded certificates (easier distribution)
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
echo "[+] Client configuration generated successfully!"
echo ""
echo "Files created in $OUTPUT_DIR:"
echo "  - $CLIENT_NAME-linux.ovpn (Linux/Mac with separate cert files)"
echo "  - $CLIENT_NAME-windows.ovpn (Windows with separate cert files)"
echo "  - $CLIENT_NAME-linux-embedded.ovpn (Linux/Mac with embedded certs)"
echo "  - $CLIENT_NAME-windows-embedded.ovpn (Windows with embedded certs)"
echo ""
echo "For Linux/Mac users: Use the embedded version (easier, single file)"
echo "For Windows users: Use the embedded version with OpenVPN GUI"
echo ""
echo "To connect:"
echo "  Linux/Mac:  openvpn --config $CLIENT_NAME-linux-embedded.ovpn"
echo "  Windows:    Double-click the .ovpn file with OpenVPN GUI installed"
