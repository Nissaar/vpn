#!/bin/bash

# OpenVPN Server Setup and Migration Script
# This script initializes OpenVPN in Docker container with existing certificates

set -e

OPENVPN_CONTAINER="openvpn"
OPENVPN_DIR="/etc/openvpn"
OVPN_CONF="/etc/openvpn/openvpn.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[*] Starting OpenVPN Server Setup${NC}"

# Wait for container to be running
echo "[*] Waiting for OpenVPN container to be ready..."
sleep 5

# Copy existing certs/keys to container
echo "[*] Copying certificates from local machine..."

if [ ! -d "./openvpn-data/pki" ]; then
    mkdir -p ./openvpn-data/pki/{private,issued}
    echo -e "${YELLOW}[!] PKI directory created. Please copy your existing certificates:${NC}"
    echo "    - ca.crt → ./openvpn-data/pki/"
    echo "    - server.crt → ./openvpn-data/pki/issued/"
    echo "    - server.key → ./openvpn-data/pki/private/"
    echo "    - dh.pem → ./openvpn-data/pki/"
    echo "    - ta.key → ./openvpn-data/"
    echo ""
    echo "Then run this script again."
    exit 1
fi

# Verify required files exist
REQUIRED_FILES=(
    "./openvpn-data/pki/ca.crt"
    "./openvpn-data/pki/issued/server.crt"
    "./openvpn-data/pki/private/server.key"
    "./openvpn-data/pki/dh.pem"
    "./openvpn-data/ta.key"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}[!] Error: Missing required file: $file${NC}"
        exit 1
    fi
done

echo -e "${GREEN}[+] All required certificates found${NC}"

# Generate server config
echo "[*] Generating OpenVPN server configuration..."

docker exec $OPENVPN_CONTAINER bash -c "cat > $OVPN_CONF" <<'SERVERCONF'
port 1194
proto udp
dev tun

# Certificate/Key locations (in container)
ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/issued/server.crt
key /etc/openvpn/pki/private/server.key
dh /etc/openvpn/pki/dh.pem
tls-auth /etc/openvpn/ta.key 0

# Network settings
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/ipp.txt

# Client connectivity
keepalive 10 120
comp-lz4
comp-lz4-dynamic

# Security
cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_DHE_RSA_WITH_AES_256_GCM_SHA384

# Push routes to clients (for split tunneling)
# Uncomment routes you want to push
# push "route 192.168.0.0 255.255.0.0"
# push "route 10.0.0.0 255.0.0.0"

# DNS options
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Logging
status /etc/openvpn/openvpn-status.log
log /etc/openvpn/openvpn.log
verb 3
mute-replay-warnings

# Performance tuning
sndbuf 393216
rcvbuf 393216
txqueuelen 1000

# Security
explicit-exit-notify 1
user nobody
group nogroup
persist-key
persist-tun
SERVERCONF

echo -e "${GREEN}[+] Server configuration generated${NC}"

# Restart container to apply configuration
echo "[*] Restarting OpenVPN container..."
docker restart $OPENVPN_CONTAINER
sleep 3

# Check if container is running
if docker ps | grep -q $OPENVPN_CONTAINER; then
    echo -e "${GREEN}[+] OpenVPN container is running!${NC}"
else
    echo -e "${RED}[!] Error: OpenVPN container failed to start${NC}"
    echo "Check logs with: docker logs $OPENVPN_CONTAINER"
    exit 1
fi

echo ""
echo -e "${GREEN}[+] OpenVPN Server Setup Complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Verify connectivity: docker logs $OPENVPN_CONTAINER"
echo "2. Generate client configs: ./generate-client.sh <client-name> <your-domain.com> 1194"
echo "3. Distribute .ovpn files to clients"
echo ""
