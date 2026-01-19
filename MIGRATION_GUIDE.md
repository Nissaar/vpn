# OpenVPN Migration from Google Cloud to Oracle Cloud (Docker + Traefik)

## Table of Contents
1. [Pre-Migration Checklist](#pre-migration-checklist)
2. [Oracle Cloud Setup](#oracle-cloud-setup)
3. [Cloudflare DNS Configuration](#cloudflare-dns-configuration)
4. [Docker & OpenVPN Setup](#docker-openvpn-setup)
5. [Traefik UDP Routing](#traefik-udp-routing)
6. [Certificate Migration](#certificate-migration)
7. [Client Configuration](#client-configuration)
8. [Split Tunneling with PAC](#split-tunneling-with-pac)
9. [Verification & Testing](#verification--testing)
10. [Troubleshooting](#troubleshooting)

---

## Pre-Migration Checklist

Before starting the migration, ensure you have:

- [ ] Existing OpenVPN server certificates and keys from Google Cloud
  - [ ] `ca.crt` (Certificate Authority)
  - [ ] `server.crt` (Server certificate)
  - [ ] `server.key` (Server private key)
  - [ ] `dh.pem` (Diffie-Hellman parameters)
  - [ ] `ta.key` (TLS authentication key)

- [ ] List of existing OpenVPN clients
- [ ] Domain name with Cloudflare DNS
- [ ] Oracle Cloud Always Free account (or paid tier)
- [ ] SSH access to both servers
- [ ] Docker and Docker Compose installed on Oracle Cloud VM

### Export Certificates from Google Cloud

```bash
# SSH into your Google Cloud OpenVPN server
ssh -i your-key.pem user@google-cloud-ip

# Locate your OpenVPN certificates
sudo find / -name "ca.crt" 2>/dev/null

# Typically in:
# /etc/openvpn/
# /opt/openvpn/keys/

# Backup and download
sudo tar -czf /tmp/openvpn-certs.tar.gz /etc/openvpn/
scp -i your-key.pem user@google-cloud-ip:/tmp/openvpn-certs.tar.gz ./

# Extract locally
tar -xzf openvpn-certs.tar.gz
```

---

## Oracle Cloud Setup

### 1. Create Virtual Machine

On Oracle Cloud Console:

1. **Compute > Instances > Create Instance**
2. **Image**: Ubuntu 22.04 or Oracle Linux 9 (Always Free eligible)
3. **Shape**: Ampere (ARM) - Always Free eligible (4 OCPUs, 24GB RAM)
4. **Boot volume**: 200GB (free tier includes 200GB)
5. **VCN Network**: Create or select existing
6. **Public IP**: Assign static IP
7. **Add SSH key**: Upload your public key

### 2. Configure Network Security

**Important**: Oracle Cloud uses Network Security Groups (NSGs), not traditional security groups.

```bash
# SSH into your Oracle instance
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
```

### 3. Configure Oracle Cloud Firewall/NSG

In Oracle Cloud Console:

1. **Networking > Virtual Cloud Networks > Your VCN**
2. **Security Lists** (or Network Security Groups)
3. **Add Ingress Rules**:

| Protocol | Port | Source | Purpose |
|----------|------|--------|---------|
| TCP | 80 | 0.0.0.0/0 | HTTP (Let's Encrypt) |
| TCP | 443 | 0.0.0.0/0 | HTTPS |
| UDP | 1194 | 0.0.0.0/0 | OpenVPN |
| TCP | 853 | 0.0.0.0/0 | DNS over TLS |

```bash
# Verify with netstat
sudo netstat -tlnup | grep -E ':(80|443|1194|853)'
```

---

## Cloudflare DNS Configuration

### Important: UDP Port 1194 & Cloudflare

⚠️ **Cloudflare CANNOT proxy UDP traffic on port 1194**. You must use **DNS Only** (Gray Cloud).

### Steps:

1. **Log into Cloudflare Console**
2. **Select your domain**
3. **DNS > Records**
4. **Add/Update A Record**:
   ```
   Type: A
   Name: vpn (or your subdomain)
   IPv4 Address: your-oracle-static-ip
   TTL: Auto
   Proxy status: DNS only ⬜ (CRITICAL - must be gray cloud, not orange)
   ```

5. **Verify DNS**:
   ```bash
   # Should resolve to your Oracle IP
   nslookup vpn.yourdomain.com
   
   # Verify it's NOT proxied by Cloudflare
   dig vpn.yourdomain.com
   # Should show your actual IP, not Cloudflare's IP
   ```

### For HTTPS/Traefik (Optional separate subdomain)

If you want separate HTTPS services:

```
Type: A
Name: api (example)
IPv4 Address: your-oracle-static-ip
Proxy status: Proxied 🟠 (OK for HTTP/HTTPS only)
```

---

## Docker OpenVPN Setup

### 1. Directory Structure

```bash
mkdir -p ~/docker/openvpn/{openvpn-data/pki/{private,issued},client-configs}
cd ~/docker/openvpn

# Copy your existing certificates
# You should have extracted openvpn-certs.tar.gz earlier
cp /path/to/extracted/certs/pki/* ./openvpn-data/pki/
cp /path/to/extracted/certs/ta.key ./openvpn-data/
```

### 2. Deploy OpenVPN Container

```bash
# Copy the provided docker-compose-openvpn.yml
cp docker-compose-openvpn.yml ~/docker/openvpn/

# Start container
cd ~/docker/openvpn
docker-compose up -d

# Wait a moment for initialization
sleep 3

# Check status
docker logs openvpn
docker ps | grep openvpn
```

### 3. Initialize with Existing Certificates

```bash
# Run the setup script
bash setup-openvpn.sh

# The script will:
# 1. Verify certificates exist
# 2. Generate openvpn.conf
# 3. Restart container
```

### 4. Verify Server is Running

```bash
# Check if OpenVPN is listening
docker exec openvpn netstat -tlnup | grep 1194
# Expected output: udp    0    0 0.0.0.0:1194    0.0.0.0:*

# Check logs for errors
docker logs openvpn | tail -20

# Test connectivity (from your local machine after setting up a client)
openvpn --config your-client-config.ovpn
```

---

## Traefik UDP Routing

### 1. Update Traefik Docker Compose

Use the provided `traefik-docker-compose.yml`:

```bash
# Navigate to your Traefik directory
cd ~/docker/traefik

# Backup existing
cp docker-compose.yml docker-compose.yml.bak

# Replace with updated version (supports UDP)
# The key changes:
# - Added: --entrypoints.openvpn.address=:1194/udp
# - Added: - "1194:1194/udp" to ports
# - Added OpenVPN UDP router labels to openvpn service
```

### 2. Key Traefik Changes

In `traefik-docker-compose.yml`:

```yaml
command:
  # ... existing config ...
  - --entrypoints.openvpn.address=:1194/udp

ports:
  - "80:80"
  - "443:443"
  - "853:853"
  - "1194:1194/udp"  # NEW: UDP port
```

### 3. OpenVPN Service Labels

The OpenVPN service labels in `docker-compose-openvpn.yml`:

```yaml
labels:
  - "traefik.udp.routers.openvpn.entrypoints=openvpn"
  - "traefik.udp.routers.openvpn.service=openvpn"
  - "traefik.udp.services.openvpn.loadbalancer.server.port=1194"
```

### 4. Restart Traefik

```bash
cd ~/docker/traefik
docker-compose down
docker-compose up -d

# Verify UDP port is listening
docker exec traefik netstat -tlnup | grep 1194
docker logs traefik | tail -20
```

---

## Certificate Migration

### Migrate Existing Client Certificates

If you want to keep existing client certificates valid:

```bash
# Copy all client certificates from Google Cloud
# Log into Google Cloud server and run:
sudo tar -czf /tmp/openvpn-clients.tar.gz /etc/openvpn/pki/issued/
scp -i key.pem user@gcp-ip:/tmp/openvpn-clients.tar.gz ./

# Extract and copy to Oracle
tar -xzf openvpn-clients.tar.gz
cp -r etc/openvpn/pki/issued/* ~/docker/openvpn/openvpn-data/pki/issued/

# Verify in container
docker exec openvpn ls /etc/openvpn/pki/issued/
```

### Generate New Clients (Optional)

See the **Client Configuration** section below.

---

## Client Configuration

### Generate New Client Config

```bash
# Copy the generate-client.sh script
cp generate-client.sh ~/docker/openvpn/

# Make executable
chmod +x ~/docker/openvpn/generate-client.sh

# Generate for a new client
cd ~/docker/openvpn
./generate-client.sh john_laptop vpn.yourdomain.com 1194

# This creates 4 files in ./client-configs/:
# - john_laptop-linux-embedded.ovpn  (recommended for Linux/Mac)
# - john_laptop-windows-embedded.ovpn (recommended for Windows)
# - john_laptop-linux.ovpn (with separate cert files)
# - john_laptop-windows.ovpn (with separate cert files)
```

### Distribute Client Configs

**For Linux/Mac**:
```bash
# Copy the embedded config
cp client-configs/john_laptop-linux-embedded.ovpn ~/Desktop/

# Install OpenVPN
# macOS: brew install openvpn
# Ubuntu: sudo apt install openvpn

# Connect
openvpn --config john_laptop-linux-embedded.ovpn

# Or with sudo (recommended)
sudo openvpn --config john_laptop-linux-embedded.ovpn
```

**For Windows**:
1. Install [OpenVPN GUI](https://openvpn.net/community-downloads/)
2. Copy `john_laptop-windows-embedded.ovpn` to `%USERPROFILE%\OpenVPN\config\`
3. Double-click from OpenVPN GUI tray icon

### Renew Client Certificates

```bash
# Certificate expiring? Renew it
cd ~/docker/openvpn
./renew-client-cert.sh john_laptop vpn.yourdomain.com 1194

# New config files are automatically generated
```

### Revoke Client Access

```bash
# Immediately disconnect and block a client
cd ~/docker/openvpn
./revoke-client.sh john_laptop
```

---

## Split Tunneling with PAC

### Option 1: OpenVPN-Level Split Tunneling (Recommended)

This is the easiest - configure in your `.ovpn` file:

```ini
client
# ... other config ...

# Don't add default VPN route
route-nopull

# Only route these networks through VPN
route 10.8.0.0 255.255.255.0
route 10.0.0.0 255.0.0.0
route 192.168.1.0 255.255.255.0

# Optional: Push from server side
push "route 10.0.0.0 255.0.0.0"
```

When you connect to OpenVPN:
- Traffic to `10.x.x.x` and `192.168.x.x` goes through VPN
- Everything else goes directly to your ISP

### Option 2: PAC File (Browser/Windows)

For more granular control by domain:

```bash
# The proxy.pac file is already created
# Edit it to add your domains/IPs
vim proxy.pac

# Uncomment and modify these sections:
var vpn_hosts = [
    "*.internal.company.com",
    "intranet.company.com",
    "service1.example.com",
];
```

**Setup PAC in Windows**:
1. Save `proxy.pac` to `C:\Users\YourUser\proxy.pac`
2. **Settings > Network & Internet > Proxy**
3. **Automatic proxy setup**
4. **Use a proxy auto-config (PAC) script**: `file:///C:/Users/YourUser/proxy.pac`
5. Enable when OpenVPN is connected

**Or serve from web**:

```bash
# Use the provided PAC server setup
bash setup-pac-server.sh

# Start PAC server on your Traefik
docker-compose -f docker-compose-pac-server.yml up -d

# Configure clients to use:
# https://vpn.yourdomain.com/proxy.pac
```

### Option 3: Redirect via DNS

For more sophisticated setup with local DNS:

```bash
# Push DNS servers from OpenVPN server
push "dhcp-option DNS 10.8.0.1"

# Run DNS server in container (optional)
# This would intercept DNS and route based on rules
```

---

## Verification & Testing

### Test VPN Connection

```bash
# From client machine, connect and test

# 1. Check you're connected
openvpn status

# 2. Check your IP
curl https://ipinfo.io/ip
# Should be different from your real IP if full tunnel
# OR should be your real IP if split tunnel (and accessing non-VPN site)

# 3. Check VPN-side connectivity
ping 10.8.0.1  # VPN gateway
ping 10.8.0.2  # Another VPN client (if exists)

# 4. Check routing
netstat -r  # Windows: route print
# Should show routes through your VPN interface
```

### Monitor Server

```bash
# Check connected clients
docker exec openvpn tail -f /etc/openvpn/openvpn-status.log

# View logs
docker logs -f openvpn

# Check Traefik routing
docker logs -f traefik | grep -i udp

# Test UDP port from external machine
nc -u your-oracle-ip 1194
```

### Verify DNS Resolution

```bash
# From client machine
nslookup vpn.yourdomain.com
# Should resolve to your Oracle IP

# Verify NOT Cloudflare proxied
dig vpn.yourdomain.com +short
# Should return your actual Oracle IP (not Cloudflare's)

# For DNS over TLS (853)
# dig @vpn.yourdomain.com +tls yourdomain.com
```

---

## Troubleshooting

### OpenVPN Won't Start

```bash
# Check logs
docker logs openvpn

# Common issues:
# 1. Certificate path wrong
# 2. Port already in use
# 3. File permissions

# Solution:
docker exec openvpn ls -la /etc/openvpn/pki/
docker exec openvpn ls -la /etc/openvpn/ta.key
```

### Can't Connect to VPN

```bash
# Test from client side
# 1. Check if server port is open
nc -u -zv vpn.yourdomain.com 1194

# 2. Check OpenVPN logs
docker logs openvpn | grep -i error

# 3. Check if certificate is valid
docker exec openvpn openssl x509 -in /etc/openvpn/pki/ca.crt -noout -text

# 4. Verify client certificate
openssl x509 -in ~/.openvpn/client.crt -noout -text
```

### Traefik Not Routing UDP

```bash
# Check Traefik UDP routers
docker exec traefik traefik routers | grep openvpn

# Verify UDP port listening
docker exec traefik netstat -tlnup | grep 1194

# Check Traefik logs
docker logs traefik | grep -i openvpn

# Verify labels in docker-compose
grep -A 3 "traefik.udp" docker-compose-openvpn.yml
```

### DNS Resolution Issues

```bash
# Test Cloudflare DNS record
dig vpn.yourdomain.com

# Expected: Direct IP address (not Cloudflare's)

# If showing Cloudflare IP:
# 1. Go to Cloudflare Dashboard
# 2. DNS > Records
# 3. Click the record
# 4. Change to "DNS only" (Gray cloud ⬜)
# 5. Wait for DNS propagation (5-30 minutes)

# Force flush DNS
# Windows: ipconfig /flushdns
# macOS: sudo dscacheutil -flushcache
# Linux: sudo resolvectl flush-caches
```

### Slow Performance

If UDP performance is degraded:

```bash
# Increase UDP buffer sizes (already in docker-compose)
# But can adjust in openvpn.conf:
sndbuf 524288  # 512KB (default: 65536)
rcvbuf 524288

# Check for packet loss
ping -c 100 10.8.0.1 | grep loss

# Monitor bandwidth
docker exec openvpn iftop -i tun0
# or: iperf between client and VPN server
```

### Certificate Expiration

```bash
# Check certificate expiration dates
cd ~/docker/openvpn
./list-clients.sh

# Renew expiring certificates
./renew-client-cert.sh john_laptop vpn.yourdomain.com 1194
```

---

## Maintenance & Operations

### Regular Backups

```bash
# Backup all certificates and keys
cd ~/docker/openvpn
./backup-openvpn.sh

# Optional: Encrypt backup with GPG
# Follow the prompt to set password

# Store backup in secure location (S3, encrypted cloud storage, etc.)
```

### Monitor Resources

```bash
# Check Docker resource usage
docker stats openvpn traefik

# Monitor OpenVPN memory/CPU
docker top openvpn
```

### Restart Services

```bash
# Restart OpenVPN (will disconnect all clients)
docker restart openvpn

# Restart Traefik (won't disconnect VPN users)
docker restart traefik

# Full restart (maintenance window)
cd ~/docker/openvpn
docker-compose down
docker-compose up -d
```

### Update Container Images

```bash
# Pull latest images
docker pull kylemanna/openvpn:latest
docker pull traefik:latest

# Restart to apply
docker-compose up -d
```

---

## Post-Migration Checklist

- [ ] All client certificates migrated or regenerated
- [ ] Clients tested and connected successfully
- [ ] DNS verified (not proxied on port 1194)
- [ ] Traefik UDP routing verified
- [ ] Cloudflare DNS pointing to Oracle (DNS only)
- [ ] Oracle Cloud firewall rules configured
- [ ] Backups created and stored securely
- [ ] Monitoring/alerting setup (optional)
- [ ] Google Cloud OpenVPN server deactivated
- [ ] Google Cloud resources cleaned up to reduce costs

---

## Additional Resources

- [OpenVPN Official Docs](https://openvpn.net/community-docs/)
- [Traefik UDP Routing](https://doc.traefik.io/traefik/routing/services/#configuring-udp-services)
- [Cloudflare DNS](https://support.cloudflare.com/hc/en-us/articles/200168836)
- [Oracle Cloud Always Free](https://www.oracle.com/cloud/free/)
- [Split Tunneling Guide](https://openvpn.net/faq/what-is-split-tunneling-and-how-i-do-configure-it-in-openvpn/)

---

## Support & Questions

For issues:
1. Check the **Troubleshooting** section
2. Review Docker/Traefik logs
3. Test connectivity with `nc` or `dig` utilities
4. Consult OpenVPN and Traefik official documentation

---

**Last Updated**: January 2026  
**Status**: Production Ready
