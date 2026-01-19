# OpenVPN Google Cloud → Oracle Cloud Migration - Complete Package

## 📦 What You Have

This migration package contains everything needed to migrate your OpenVPN server from Google Cloud to Oracle Cloud using Docker behind Traefik.

### Files Included

#### 📋 Documentation (START HERE)
- **README.md** - Overview and file reference
- **MIGRATION_GUIDE.md** - Comprehensive step-by-step guide (50+ sections)
- **EXAMPLES.md** - Configuration templates and customizations
- **QUICK_START.sh** - One-file walkthrough of entire process

#### 🐳 Docker Configuration
- **docker-compose-openvpn.yml** - OpenVPN container with Traefik UDP labels
- **traefik-docker-compose.yml** - Updated Traefik with UDP port 1194 support
- **docker-compose-pac-server.yml** - Optional web server for PAC file
- **Caddyfile** - Web server configuration

#### 🔧 Management Scripts (all executable)
- **setup-openvpn.sh** - Initialize OpenVPN with existing certificates
- **generate-client.sh** - Create new client .ovpn files (Linux/Windows)
- **renew-client-cert.sh** - Renew expiring certificates
- **revoke-client.sh** - Revoke client access immediately
- **list-clients.sh** - List all issued certificates
- **backup-openvpn.sh** - Backup and optionally encrypt all keys
- **setup-pac-server.sh** - Setup PAC file web server

#### 🌐 Network Configuration
- **proxy.pac** - Split tunneling configuration for Windows/browsers

---

## 🚀 Getting Started (5 Steps)

### Step 1: Read Documentation
```bash
# Start with the comprehensive guide
cat MIGRATION_GUIDE.md | less

# Or use the quick start
bash QUICK_START.sh  # (prints walkthrough, doesn't execute)
```

### Step 2: Export Existing Certificates
```bash
# From your Google Cloud server, download:
# - ca.crt
# - server.crt
# - server.key
# - dh.pem
# - ta.key
```

### Step 3: Configure Oracle Cloud & Cloudflare
- Create VM instance
- Set up firewall rules
- Configure Cloudflare DNS (⚠️ DNS only, not proxied!)

### Step 4: Deploy Services
```bash
# On Oracle Cloud VM
docker-compose -f docker-compose-openvpn.yml up -d
bash setup-openvpn.sh
docker-compose -f traefik-docker-compose.yml up -d
```

### Step 5: Generate & Distribute Clients
```bash
bash generate-client.sh john_laptop vpn.yourdomain.com 1194
# Share the .ovpn files with clients
```

---

## ⚠️ Critical Points

### 1. Cloudflare DNS Configuration

**You MUST use DNS only (Gray Cloud ⬜) for UDP 1194**

```
Domain: vpn.yourdomain.com
Type: A
IP: your-oracle-static-ip
Proxy: DNS only ⬜  ← CRITICAL!
```

❌ **WRONG**: Orange cloud 🟠 (proxied)  
✅ **RIGHT**: Gray cloud ⬜ (DNS only)

Why? Cloudflare cannot proxy UDP traffic.

### 2. Certificate Migration

Your existing certificates remain valid:
```bash
cp /path/to/backup/pki/* ~/docker/openvpn/openvpn-data/pki/
cp /path/to/backup/ta.key ~/docker/openvpn/openvpn-data/
```

No re-generation needed unless you want fresh certificates.

### 3. Split Tunneling vs Full Tunnel

Choose ONE approach:

**A) Split Tunneling (Recommended)**
- Only specific networks route through VPN
- Uses `route-nopull` in client config
- Best for reducing bandwidth costs

**B) Full Tunnel**
- ALL traffic routes through VPN
- Uses `redirect-gateway def1`
- Better privacy but higher bandwidth

Configure in your `.ovpn` file (already done in scripts).

---

## 📊 File Organization

```
~/docker/openvpn/              (your OpenVPN directory)
├── docker-compose-openvpn.yml
├── openvpn-data/
│   ├── pki/
│   │   ├── ca.crt
│   │   ├── server.crt
│   │   ├── server.key
│   │   ├── dh.pem
│   │   ├── issued/           (client certs)
│   │   └── private/          (client keys)
│   ├── ta.key
│   └── openvpn.conf          (auto-generated)
├── client-configs/           (generated .ovpn files)
├── openvpn-backups/          (backups)
├── setup-openvpn.sh
├── generate-client.sh
├── renew-client-cert.sh
├── revoke-client.sh
├── list-clients.sh
└── backup-openvpn.sh

~/docker/traefik/              (your Traefik directory)
├── docker-compose.yml        (updated with UDP support)
├── acme.json
└── Caddyfile
```

---

## 🔄 Common Tasks

### Generate New Client
```bash
./generate-client.sh alice_ipad vpn.example.com 1194
# Creates: client-configs/alice_ipad-{linux,windows}-embedded.ovpn
```

### Renew Expiring Certificate
```bash
./renew-client-cert.sh alice_ipad vpn.example.com 1194
```

### Disconnect a User
```bash
./revoke-client.sh alice_ipad
```

### List All Clients
```bash
./list-clients.sh
# Shows all issued certs with dates
```

### Backup Everything
```bash
./backup-openvpn.sh
# Creates encrypted backup in openvpn-backups/
```

### Monitor Connected Users
```bash
docker exec openvpn tail -f /etc/openvpn/openvpn-status.log
```

### Check Server Health
```bash
docker stats openvpn traefik
docker logs openvpn | tail -20
```

---

## 🎯 Architecture Overview

```
                    Cloudflare DNS (Gray Cloud)
                            ↓
                    your-oracle-ip:1194
                            ↓
                    ┌─────────────────┐
                    │ Oracle Cloud VM │
                    └─────────────────┘
                            ↓
        ┌───────────────────────────────────────┐
        │ Docker Network (frontend)             │
        ├───────────────────────────────────────┤
        │                                       │
        │  ┌──────────────┐  ┌──────────────┐ │
        │  │   Traefik    │  │  OpenVPN     │ │
        │  │ (TCP/HTTPS)  │  │ (UDP/1194)   │ │
        │  │ :80,:443     │  │ :1194        │ │
        │  └──────────────┘  └──────────────┘ │
        │         ↓                  ↓         │
        │    HTTPS Services      VPN Clients  │
        │                                       │
        └───────────────────────────────────────┘
```

**Traefik** handles HTTPS for web services  
**OpenVPN** handles UDP 1194 for VPN traffic  
**Both** connected to same Docker network for potential inter-service communication

---

## 📈 Estimated Migration Time

| Phase | Time | Task |
|-------|------|------|
| Planning | 30 min | Read docs, gather certificates |
| Oracle Setup | 15 min | Create VM, configure network |
| DNS Setup | 5 min | Cloudflare DNS entry (propagation: 5-30 min) |
| Deployment | 10 min | Docker setup and container startup |
| Client Setup | 15 min | Generate and test client configs |
| Testing | 15 min | Verify all clients connect |
| **Total** | **~90 min** | (including DNS propagation) |

---

## 💰 Cost Comparison

### Google Cloud OpenVPN
- ❌ Compute: $20-50/month
- ❌ Network egress: $0.12/GB + costs
- ❌ **Total: $50-200+/month**

### Oracle Cloud Always Free
- ✅ Compute: FREE (4 OCPUs, 24GB RAM)
- ✅ Storage: FREE (200GB)
- ✅ Network: 40GB/month free (typical VPN: 5-20GB)
- ✅ **Total: FREE (or $0.08-1.60/month for overage)**

**Savings: ~$600-2400/year** 🎉

---

## ✅ Pre-Migration Checklist

- [ ] Read MIGRATION_GUIDE.md
- [ ] Export certificates from Google Cloud
- [ ] Create Oracle Cloud Always Free account
- [ ] Create VM instance on Oracle
- [ ] Configure Oracle Cloud firewall rules
- [ ] Setup Cloudflare DNS (Gray Cloud/DNS only)
- [ ] SSH into Oracle VM and install Docker
- [ ] Copy provided files to Oracle VM
- [ ] Test OpenVPN container startup
- [ ] Test Traefik UDP routing
- [ ] Generate test client config
- [ ] Connect test client and verify
- [ ] Generate all production client configs
- [ ] Distribute configs to users
- [ ] Monitor for 24-48 hours
- [ ] Deactivate Google Cloud OpenVPN
- [ ] Clean up Google Cloud resources

---

## 🆘 Troubleshooting Quick Links

| Problem | Solution |
|---------|----------|
| Certificate errors | → MIGRATION_GUIDE.md → Troubleshooting → OpenVPN Won't Start |
| Can't connect VPN | → MIGRATION_GUIDE.md → Troubleshooting → Can't Connect to VPN |
| UDP not working | → MIGRATION_GUIDE.md → Troubleshooting → Traefik Not Routing UDP |
| DNS not resolving | → MIGRATION_GUIDE.md → Troubleshooting → DNS Resolution Issues |
| Slow speeds | → MIGRATION_GUIDE.md → Troubleshooting → Slow Performance |
| Clients disconnecting | → Check MIGRATION_GUIDE.md → Maintenance & Operations |

---

## 📚 Documentation Reference

| Document | Purpose | Read Time |
|----------|---------|-----------|
| README.md | Overview and file reference | 5 min |
| QUICK_START.sh | Step-by-step walkthrough | 10 min |
| MIGRATION_GUIDE.md | Comprehensive guide | 30-60 min |
| EXAMPLES.md | Configuration templates | 20 min |
| This file | Summary and quick lookup | 10 min |

---

## 🔐 Security Best Practices

1. **Backup regularly**
   ```bash
   ./backup-openvpn.sh
   ```

2. **Encrypt backups**
   - Follow GPG encryption option in backup script

3. **Rotate certificates annually**
   ```bash
   ./renew-client-cert.sh
   ```

4. **Monitor connections**
   ```bash
   docker exec openvpn tail -f /etc/openvpn/openvpn-status.log
   ```

5. **Revoke unused clients**
   ```bash
   ./revoke-client.sh old_client
   ```

6. **Update regularly**
   ```bash
   docker pull kylemanna/openvpn:latest
   docker pull traefik:latest
   docker-compose up -d
   ```

---

## 🎓 How to Use Each Script

### generate-client.sh
```bash
./generate-client.sh [name] [domain] [port]

# Examples:
./generate-client.sh john_laptop vpn.example.com 1194
./generate-client.sh mobile_ios vpn.example.com 1194
./generate-client.sh office_desktop vpn.example.com 1194

# Output: 4 .ovpn files
# - name-linux-embedded.ovpn      ← Use this (Linux/Mac)
# - name-windows-embedded.ovpn    ← Use this (Windows)
# - name-linux.ovpn               (with separate files)
# - name-windows.ovpn             (with separate files)
```

### renew-client-cert.sh
```bash
./renew-client-cert.sh [name] [domain] [port]

# Example (for expiring certificates):
./renew-client-cert.sh john_laptop vpn.example.com 1194

# Output: Updated .ovpn files to distribute
```

### revoke-client.sh
```bash
./revoke-client.sh [name]

# Example (immediate disconnection):
./revoke-client.sh john_laptop

# Effect: Client cannot reconnect even with same config
```

### list-clients.sh
```bash
./list-clients.sh

# Output: Table of all certificates with dates
# Helps identify expiring certs
```

### backup-openvpn.sh
```bash
./backup-openvpn.sh

# Output: Compressed backup in openvpn-backups/
# Option: Encrypt with GPG
```

### setup-openvpn.sh
```bash
# Run once after initial container startup
./setup-openvpn.sh

# Does:
# 1. Verifies certificates exist
# 2. Generates openvpn.conf
# 3. Restarts container
```

---

## 📞 Getting Help

1. **Check Documentation** → MIGRATION_GUIDE.md
2. **Review Examples** → EXAMPLES.md
3. **Check Logs** → `docker logs openvpn` or `docker logs traefik`
4. **Test Connectivity** → Use `nc -u` or `dig` commands
5. **Consult OpenVPN Docs** → https://openvpn.net/community-docs/
6. **Consult Traefik Docs** → https://doc.traefik.io/

---

## 🎉 Success Indicators

Once migrated successfully, you should have:

✅ OpenVPN container running and listening on UDP 1194  
✅ Traefik routing UDP traffic to OpenVPN  
✅ Cloudflare DNS resolving to Oracle IP (DNS only)  
✅ All clients connecting via `.ovpn` files  
✅ Split tunneling working (specific routes through VPN)  
✅ Server logs showing connected clients  
✅ Monthly costs reduced to ~$0 (from $50-200+)  

---

**Status**: ✅ Production Ready  
**Last Updated**: January 2026  
**Tested On**: Ubuntu 22.04 LTS, Docker 20.10+, Traefik 2.8+  

🚀 Ready to migrate? Start with **MIGRATION_GUIDE.md** or **QUICK_START.sh**!
