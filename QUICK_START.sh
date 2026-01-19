#!/bin/bash

# Quick Start Summary for OpenVPN Migration
# Execute these commands in order to migrate your OpenVPN server

# =============================================================================
# STEP 1: ORACLE CLOUD VM SETUP
# =============================================================================
echo "=== STEP 1: Oracle Cloud VM Setup ==="
echo "1. Create VM Instance on Oracle Cloud Console"
echo "   - Image: Ubuntu 22.04 (Always Free eligible)"
echo "   - Shape: Ampere (ARM) 4 OCPUs, 24GB RAM"
echo "   - Boot: 200GB"
echo "2. Add Ingress Rules in Security List/NSG:"
echo "   - TCP 80 (HTTP)"
echo "   - TCP 443 (HTTPS)"
echo "   - UDP 1194 (OpenVPN)"
echo "3. Note your Static Public IP"
echo ""

# =============================================================================
# STEP 2: CLOUDFLARE DNS SETUP
# =============================================================================
echo "=== STEP 2: Cloudflare DNS Setup ==="
echo "1. Log into Cloudflare Dashboard"
echo "2. Select your domain"
echo "3. DNS > Records > Add/Update:"
echo "   Name: vpn"
echo "   Type: A"
echo "   IPv4: <your-oracle-ip>"
echo "   Proxy: DNS only (⬜ Gray Cloud - IMPORTANT!)"
echo ""
echo "CRITICAL: Must be 'DNS only', NOT Cloudflare proxied!"
echo "If proxied (🟠 orange), UDP 1194 won't work!"
echo ""

# =============================================================================
# STEP 3: INSTALL DOCKER & TOOLS
# =============================================================================
echo "=== STEP 3: Install Docker & Tools ==="
cat << 'DOCKER_INSTALL'
# SSH into Oracle VM
ssh -i your-key.pem ubuntu@your-oracle-ip

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify
docker --version
docker-compose --version
DOCKER_INSTALL

# =============================================================================
# STEP 4: SETUP DIRECTORY STRUCTURE
# =============================================================================
echo ""
echo "=== STEP 4: Setup Directory Structure ==="
cat << 'DIR_SETUP'
# Create working directory
mkdir -p ~/docker/openvpn/openvpn-data/pki/{private,issued}
mkdir -p ~/docker/openvpn/client-configs
cd ~/docker/openvpn

# Copy your existing certificates (from Google Cloud backup)
# You should have: ca.crt, server.crt, server.key, dh.pem, ta.key
cp /path/to/backup/pki/* ./openvpn-data/pki/
cp /path/to/backup/ta.key ./openvpn-data/

# Verify
ls -la openvpn-data/pki/
ls -la openvpn-data/ta.key
DIR_SETUP

# =============================================================================
# STEP 5: DEPLOY OPENVPN
# =============================================================================
echo ""
echo "=== STEP 5: Deploy OpenVPN Container ==="
cat << 'OPENVPN_DEPLOY'
# Copy provided docker-compose file
cp docker-compose-openvpn.yml ~/docker/openvpn/

# Create Traefik frontend network (if not exists)
docker network create frontend || true

# Start OpenVPN
cd ~/docker/openvpn
docker-compose up -d

# Wait for initialization
sleep 3

# Verify running
docker ps | grep openvpn
docker logs openvpn | tail -20

# Check if listening on 1194 UDP
docker exec openvpn netstat -tlnup | grep 1194
OPENVPN_DEPLOY

# =============================================================================
# STEP 6: INITIALIZE OPENVPN
# =============================================================================
echo ""
echo "=== STEP 6: Initialize OpenVPN with Existing Certs ==="
cat << 'OPENVPN_INIT'
# Run setup script
cd ~/docker/openvpn
chmod +x setup-openvpn.sh
./setup-openvpn.sh

# This will:
# 1. Verify certificates exist
# 2. Generate openvpn.conf configuration
# 3. Restart container to apply configuration

# Verify it's working
docker logs openvpn | grep -i "started" || docker logs openvpn | tail -30
OPENVPN_INIT

# =============================================================================
# STEP 7: UPDATE TRAEFIK
# =============================================================================
echo ""
echo "=== STEP 7: Update Traefik for UDP Routing ==="
cat << 'TRAEFIK_UPDATE'
# Backup existing Traefik config
cd ~/docker/traefik
cp docker-compose.yml docker-compose.yml.bak

# Replace with version that supports UDP
# Replace with provided traefik-docker-compose.yml
# Key changes:
# - Added: --entrypoints.openvpn.address=:1194/udp
# - Added: - "1194:1194/udp" port binding

# Restart Traefik
docker-compose down
docker-compose up -d

# Verify UDP port
docker exec traefik netstat -tlnup | grep 1194
docker logs traefik | tail -10
TRAEFIK_UPDATE

# =============================================================================
# STEP 8: GENERATE CLIENT CONFIGS
# =============================================================================
echo ""
echo "=== STEP 8: Generate Client Configurations ==="
cat << 'CLIENT_SETUP'
# Copy script
cp generate-client.sh ~/docker/openvpn/
chmod +x ~/docker/openvpn/generate-client.sh

# Generate config for a client
cd ~/docker/openvpn
./generate-client.sh john_laptop vpn.yourdomain.com 1194

# This creates 4 files:
# - john_laptop-linux-embedded.ovpn (RECOMMENDED for Linux/Mac)
# - john_laptop-windows-embedded.ovpn (RECOMMENDED for Windows)
# - john_laptop-linux.ovpn (separate cert files)
# - john_laptop-windows.ovpn (separate cert files)

# For more clients:
./generate-client.sh jane_desktop vpn.yourdomain.com 1194
./generate-client.sh mobile_user vpn.yourdomain.com 1194
CLIENT_SETUP

# =============================================================================
# STEP 9: DISTRIBUTE & TEST
# =============================================================================
echo ""
echo "=== STEP 9: Distribute & Test Configs ==="
cat << 'TESTING'
# Download configs from server
scp -i key.pem ubuntu@oracle-ip:~/docker/openvpn/client-configs/* ./

# Install OpenVPN Client
# macOS: brew install openvpn
# Ubuntu: sudo apt install openvpn
# Windows: https://openvpn.net/community-downloads/ (GUI)

# Connect (Linux/Mac)
sudo openvpn --config john_laptop-linux-embedded.ovpn

# Connect (Windows)
# 1. Install OpenVPN GUI
# 2. Copy john_laptop-windows-embedded.ovpn to %USERPROFILE%\OpenVPN\config\
# 3. Double-click from GUI

# Test connection
curl https://ipinfo.io/ip
ping 10.8.0.1
TESTING

# =============================================================================
# STEP 10: VERIFY & MONITOR
# =============================================================================
echo ""
echo "=== STEP 10: Verify & Monitor ==="
cat << 'VERIFY'
# Check server status
docker logs openvpn | tail -20

# Check connected clients
docker exec openvpn tail -f /etc/openvpn/openvpn-status.log

# Monitor resources
docker stats openvpn traefik

# Test UDP from external machine
nc -u -zv vpn.yourdomain.com 1194

# Check DNS resolution (must NOT be Cloudflare proxied)
dig vpn.yourdomain.com
VERIFY

# =============================================================================
# ADDITIONAL COMMANDS
# =============================================================================
echo ""
echo "=== Additional Commands ==="
echo ""
echo "List all clients:"
echo "  cd ~/docker/openvpn && ./list-clients.sh"
echo ""
echo "Renew client certificate:"
echo "  cd ~/docker/openvpn && ./renew-client-cert.sh john_laptop vpn.yourdomain.com 1194"
echo ""
echo "Revoke client access:"
echo "  cd ~/docker/openvpn && ./revoke-client.sh john_laptop"
echo ""
echo "Backup certificates:"
echo "  cd ~/docker/openvpn && ./backup-openvpn.sh"
echo ""
echo "View OpenVPN logs:"
echo "  docker logs -f openvpn"
echo ""
echo "Restart services:"
echo "  docker restart openvpn traefik"
echo ""

# =============================================================================
# CLOUDFLARE DNS VERIFICATION
# =============================================================================
echo ""
echo "=== Important: Verify Cloudflare DNS Setup ==="
echo ""
echo "After setting DNS record, verify it's NOT proxied:"
echo ""
echo "1. Run this command:"
echo "   dig vpn.yourdomain.com +short"
echo ""
echo "2. Should return: <your-oracle-ip>"
echo ""
echo "3. Should NOT return: 104.16.x.x or similar Cloudflare IP"
echo ""
echo "If it shows Cloudflare IP:"
echo "   - Go to Cloudflare Dashboard"
echo "   - Click the DNS record"
echo "   - Toggle to 'DNS only' (⬜ Gray cloud)"
echo "   - Wait 5-30 minutes for DNS propagation"
echo ""
echo "IMPORTANT: UDP on port 1194 CANNOT be proxied by Cloudflare!"
echo "Must be 'DNS only' setup or it won't work!"
echo ""

echo "=== Migration Complete ==="
