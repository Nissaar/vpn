# OpenVPN Migration - Files Reference

This directory contains all necessary files and scripts for migrating your OpenVPN server from Google Cloud to Oracle Cloud using Docker behind Traefik.

## Files Overview

### Configuration Files

| File | Purpose |
|------|---------|
| `docker-compose-openvpn.yml` | OpenVPN Docker container configuration |
| `traefik-docker-compose.yml` | Updated Traefik config with UDP support |
| `proxy.pac` | Split tunneling PAC file for Windows/browsers |
| `Caddyfile` | Web server config for hosting PAC file |

### Scripts (make executable with `chmod +x`)

| Script | Purpose |
|--------|---------|
| `QUICK_START.sh` | Step-by-step migration walkthrough |
| `setup-openvpn.sh` | Initialize OpenVPN container with existing certs |
| `generate-client.sh` | Generate new client .ovpn configs |
| `renew-client-cert.sh` | Renew expiring client certificates |
| `revoke-client.sh` | Revoke and disconnect a client |
| `list-clients.sh` | List all issued client certificates |
| `backup-openvpn.sh` | Backup all certificates and keys |
| `setup-pac-server.sh` | Setup web server for PAC file distribution |

### Documentation

| File | Purpose |
|------|---------|
| `MIGRATION_GUIDE.md` | Comprehensive migration guide (READ THIS FIRST) |
| `README.md` | This file |

---

## Quick Start (5 minutes)

1. **Read**: Open [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) and review sections 1-2
2. **Setup Cloudflare**: Follow section "Cloudflare DNS Configuration"
3. **Prepare Oracle VM**: Execute commands from section "Oracle Cloud Setup"
4. **Deploy**: Use [QUICK_START.sh](QUICK_START.sh) as your guide

---

## File Usage

### Setup Phase

```bash
# 1. Initialize directory structure and copy certs
mkdir -p ~/docker/openvpn/openvpn-data/pki/{private,issued}
cp your-certs/* ~/docker/openvpn/openvpn-data/

# 2. Deploy OpenVPN
cp docker-compose-openvpn.yml ~/docker/openvpn/
cd ~/docker/openvpn
docker-compose up -d

# 3. Initialize with existing certs
chmod +x setup-openvpn.sh
./setup-openvpn.sh

# 4. Update Traefik
cp traefik-docker-compose.yml ~/docker/traefik/docker-compose.yml
cd ~/docker/traefik
docker-compose restart
```

### Client Management

```bash
# Generate new client
./generate-client.sh john_laptop vpn.yourdomain.com 1194

# Renew expiring certificate
./renew-client-cert.sh john_laptop vpn.yourdomain.com 1194

# Revoke access
./revoke-client.sh john_laptop

# List all clients
./list-clients.sh

# Backup everything
./backup-openvpn.sh
```

---

## Directory Structure (After Setup)

```
~/docker/openvpn/
├── docker-compose-openvpn.yml
├── openvpn-data/
│   ├── pki/
│   │   ├── ca.crt
│   │   ├── dh.pem
│   │   ├── private/
│   │   │   ├── server.key
│   │   │   └── client1.key
│   │   ├── issued/
│   │   │   ├── server.crt
│   │   │   └── client1.crt
│   │   └── crl.pem
│   ├── ta.key
│   ├── openvpn.conf
│   ├── openvpn-status.log
│   └── scripts/
├── client-configs/
│   ├── client1-linux-embedded.ovpn
│   ├── client1-windows-embedded.ovpn
│   └── ...
├── openvpn-backups/
│   └── openvpn-backup-20260119_120000.tar.gz
├── setup-openvpn.sh
├── generate-client.sh
├── renew-client-cert.sh
└── ... (other scripts)
```

---

## Important Notes

### Cloudflare DNS Configuration

⚠️ **CRITICAL**: For UDP port 1194 to work, you MUST use "DNS only" in Cloudflare, NOT proxied.

- **Correct**: DNS record with ⬜ (Gray Cloud - DNS only)
- **Wrong**: DNS record with 🟠 (Orange Cloud - Proxied)

Why? Cloudflare cannot proxy UDP traffic.

### Certificate Migration

If you have existing client certificates on Google Cloud:

```bash
# Export from Google Cloud
ssh gcp-server
sudo tar -czf /tmp/openvpn-clients.tar.gz /etc/openvpn/pki/issued/

# Download
scp user@gcp-server:/tmp/openvpn-clients.tar.gz ./

# Extract and copy to Oracle
tar -xzf openvpn-clients.tar.gz
cp -r etc/openvpn/pki/issued/* ~/docker/openvpn/openvpn-data/pki/issued/
```

### Traefik UDP Routing

Traefik v2.4+ supports UDP routing. The provided `traefik-docker-compose.yml` includes:

```yaml
- --entrypoints.openvpn.address=:1194/udp
```

This allows Traefik to route UDP traffic to OpenVPN while handling HTTPS for other services.

### Split Tunneling Options

**Option 1 (Recommended)**: OpenVPN config level
```ini
route-nopull
route 10.0.0.0 255.0.0.0
```

**Option 2**: Windows PAC file (for browser proxy)
- Use [proxy.pac](proxy.pac)
- Configure in Windows Network Settings

**Option 3**: Server push routes
```ini
push "route 10.0.0.0 255.0.0.0"
```

---

## Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| OpenVPN won't start | See MIGRATION_GUIDE.md → Troubleshooting → OpenVPN Won't Start |
| Can't connect to VPN | See MIGRATION_GUIDE.md → Troubleshooting → Can't Connect to VPN |
| UDP not routing | See MIGRATION_GUIDE.md → Troubleshooting → Traefik Not Routing UDP |
| DNS not resolving | See MIGRATION_GUIDE.md → Troubleshooting → DNS Resolution Issues |
| Slow performance | See MIGRATION_GUIDE.md → Troubleshooting → Slow Performance |

---

## Security Recommendations

1. **Backup certificates** - Run `./backup-openvpn.sh` regularly
2. **Encrypt backups** - Use GPG encryption option in backup script
3. **Rotate certificates** - Renew every 1-2 years
4. **Monitor connections** - Check `openvpn-status.log` regularly
5. **Revoke unused clients** - Remove access for inactive users
6. **Keep updated** - Update Docker images periodically

```bash
# Regular maintenance schedule
# Daily: Monitor logs
# Weekly: Check client list
# Monthly: Verify backups
# Quarterly: Check certificate expiration
# Annually: Rotate certificates
```

---

## Oracle Cloud Cost Optimization

Your Always Free tier includes:
- ✅ 2 x Compute VMs (4 OCPUs, 24GB RAM each)
- ✅ 200GB storage per instance
- ✅ 40 Gb/month data transfer

Since OpenVPN is typically low bandwidth:
- ✅ Should fit within free tier limits
- Monitor with: `docker stats openvpn`

If you exceed:
- 💰 ~$0.0847/GB for additional data transfer (usually minimal)
- Consider: Always Free tier should be sufficient for typical usage

---

## Maintenance Commands

```bash
# View logs
docker logs openvpn
docker logs traefik

# Monitor resources
docker stats openvpn traefik

# Restart services
docker restart openvpn traefik

# Update images
docker pull kylemanna/openvpn:latest
docker pull traefik:latest
docker-compose up -d

# Check connected clients
docker exec openvpn tail -f /etc/openvpn/openvpn-status.log

# Backup before major changes
./backup-openvpn.sh
```

---

## Post-Migration Tasks

- [ ] Verify all clients can connect
- [ ] Test split tunneling works
- [ ] Monitor server for 24 hours
- [ ] Create first backup
- [ ] Document any customizations
- [ ] Schedule certificate renewal reminders
- [ ] Shutdown Google Cloud OpenVPN instance
- [ ] Remove Google Cloud resources

---

## Support

For detailed troubleshooting, see [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md) sections:
- **Pre-Migration Checklist**
- **Troubleshooting**
- **Verification & Testing**

For OpenVPN documentation: https://openvpn.net/community-docs/  
For Traefik documentation: https://doc.traefik.io/  
For Oracle Cloud: https://www.oracle.com/cloud/free/

---

**Last Updated**: January 2026  
**Status**: Production Ready  
**Tested on**: Ubuntu 22.04 LTS, Docker 20.10+, Traefik 2.8+
