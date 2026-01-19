# Example Configurations & Customizations

## Custom OpenVPN Server Configuration

### For Split Tunneling (Recommended)

Edit `openvpn-data/openvpn.conf` and modify the push directives:

```ini
port 1194
proto udp
dev tun

ca /etc/openvpn/pki/ca.crt
cert /etc/openvpn/pki/issued/server.crt
key /etc/openvpn/pki/private/server.key
dh /etc/openvpn/pki/dh.pem
tls-auth /etc/openvpn/ta.key 0

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/ipp.txt

keepalive 10 120
comp-lz4
comp-lz4-dynamic

cipher AES-256-CBC
auth SHA256
tls-version-min 1.2
tls-cipher TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384:TLS_DHE_RSA_WITH_AES_256_GCM_SHA384

# Push specific routes to clients
push "route 10.0.0.0 255.0.0.0"
push "route 192.168.1.0 255.255.255.0"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

status /etc/openvpn/openvpn-status.log
log /etc/openvpn/openvpn.log
verb 3

sndbuf 393216
rcvbuf 393216
txqueuelen 1000

explicit-exit-notify 1
user nobody
group nogroup
persist-key
persist-tun
```

### For Full Tunnel (Route All Traffic)

Replace the push directives with:

```ini
push "redirect-gateway def1"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 1.0.0.1"
```

---

## Example Windows Proxy PAC (Corporate Network)

```javascript
function FindProxyForURL(url, host) {
    // Cloudflare for public internet
    var public_dns = "1.1.1.1";
    
    // Internal company resources
    var internal_domains = [
        "*.corp.example.com",
        "sharepoint.corp.example.com",
        "teams.corp.example.com",
        "mail.corp.example.com",
        "192.168.1.0",
        "10.0.0.0"
    ];
    
    // Always public
    var public_domains = [
        "*.google.com",
        "*.facebook.com",
        "*.github.com",
        "*.stackoverflow.com"
    ];
    
    // Check for public domains (bypass VPN)
    for (var i = 0; i < public_domains.length; i++) {
        if (shExpMatch(host, public_domains[i])) {
            return "DIRECT";
        }
    }
    
    // Check for internal domains (through VPN)
    for (var i = 0; i < internal_domains.length; i++) {
        if (shExpMatch(host, internal_domains[i])) {
            return "DIRECT";  // Accessible when VPN connected
        }
    }
    
    // Default: direct
    return "DIRECT";
}
```

---

## Multiple Traefik Services with OpenVPN

If you want to run multiple services alongside OpenVPN:

```yaml
version: "3.8"

services:
  traefik:
    container_name: traefik
    image: "traefik:latest"
    command:
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.openvpn.address=:1194/udp
      - --providers.docker
      - --providers.docker.endpoint=tcp://dockerproxy:2375
      - --api.insecure=true
      - --api.dashboard=true
    ports:
      - "80:80"
      - "443:443"
      - "1194:1194/udp"
      - "8080:8080"  # Traefik dashboard
    networks:
      - frontend
    restart: unless-stopped

  openvpn:
    container_name: openvpn
    image: "kylemanna/openvpn:latest"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    networks:
      - frontend
    ports:
      - "1194:1194/udp"
    volumes:
      - ./openvpn-data:/etc/openvpn
    sysctls:
      - net.ipv4.ip_forward=1
    labels:
      - "traefik.udp.routers.openvpn.entrypoints=openvpn"
      - "traefik.udp.routers.openvpn.service=openvpn"
      - "traefik.udp.services.openvpn.loadbalancer.server.port=1194"
    restart: unless-stopped

  webapp:
    container_name: webapp
    image: "nginx:latest"
    networks:
      - frontend
    volumes:
      - ./html:/usr/share/nginx/html:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.webapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.webapp.entrypoints=websecure"
      - "traefik.http.routers.webapp.tls.certresolver=leresolver"
      - "traefik.http.services.webapp.loadbalancer.server.port=80"
    restart: unless-stopped

  api:
    container_name: api
    image: "myapp:latest"
    networks:
      - frontend
    environment:
      - DB_HOST=postgres
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.api.rule=Host(`api.example.com`)"
      - "traefik.http.routers.api.entrypoints=websecure"
      - "traefik.http.routers.api.tls.certresolver=leresolver"
      - "traefik.http.services.api.loadbalancer.server.port=8000"
    restart: unless-stopped

networks:
  frontend:
    external:
      name: frontend
```

---

## Client Configuration Templates

### Linux Split Tunneling

```ini
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3

# Split tunneling - only corporate networks through VPN
route-nopull
route 10.0.0.0 255.0.0.0
route 192.168.0.0 255.255.0.0

# DNS while split tunneling
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf
```

### macOS with Keychain

```ini
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3

# macOS specific
script-security 2
up /usr/local/openvpn/update-systemd-resolved.sh
down /usr/local/openvpn/update-systemd-resolved.sh
down-pre
```

### Windows with TAP-Windows

```ini
client
dev-type tun
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
ca ca.crt
cert client.crt
key client.key
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
verb 3

# Windows specific
script-security 2
tap-sleep 2
ifconfig-nowarn
block-outside-dns
route-delay 2
```

---

## Docker Compose with Network Policies

For enhanced security:

```yaml
version: "3.8"

services:
  openvpn:
    container_name: openvpn
    image: "kylemanna/openvpn:latest"
    cap_add:
      - NET_ADMIN
      - SYS_MODULE
    networks:
      - vpn_network
    ports:
      - "1194:1194/udp"
    volumes:
      - ./openvpn-data:/etc/openvpn
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv4.conf.all.rp_filter=0
    environment:
      - OVPN_DEFROUTE=0
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "test", "-f", "/etc/openvpn/openvpn-status.log"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

networks:
  vpn_network:
    driver: bridge
    ipam:
      config:
        - subnet: 10.8.0.0/24
```

---

## Performance Tuning

### High-Performance Settings

```ini
# Increase buffers for high-throughput
sndbuf 1048576
rcvbuf 1048576

# Compression
comp-lz4
comp-lz4-dynamic

# TLS acceleration
tls-version-min 1.3

# Performance monitoring
status /etc/openvpn/openvpn-status.log 10

# Parallelization
ncp-ciphers AES-256-GCM:AES-128-GCM

# TCP receive buffer
rxbuf 1048576
txbuf 1048576
```

### Low-Bandwidth Settings

```ini
# Reduce overhead
comp-lz4

# Smaller buffer for lower latency
sndbuf 65536
rcvbuf 65536

# Adaptive compression
compress lz4

# Connection settings
keepalive 5 60  # Faster keepalive
```

---

## Monitoring & Logging

### Prometheus Metrics

Add to docker-compose (optional):

```yaml
prometheus:
  image: prom/prometheus:latest
  volumes:
    - ./prometheus.yml:/etc/prometheus/prometheus.yml
    - ./prometheus-data:/prometheus
  ports:
    - "9090:9090"
  networks:
    - frontend
  restart: unless-stopped

node_exporter:
  image: prom/node-exporter:latest
  ports:
    - "9100:9100"
  networks:
    - frontend
  restart: unless-stopped
```

### Logging to Syslog

```ini
# In openvpn.conf
syslog openvpn

# On host:
tail -f /var/log/syslog | grep openvpn
```

---

## Advanced: Multi-Server HA Setup

If you want redundancy:

```bash
# Create multiple OpenVPN instances
docker-compose up -d --scale openvpn=3

# Configure client for failover
remote vpn1.example.com 1194
remote vpn2.example.com 1194
remote vpn3.example.com 1194
remote-random
```

---

## Backup & Restore

### Automated Daily Backup

```bash
#!/bin/bash
# backup-daily.sh

BACKUP_DIR="/backups/openvpn"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

# Create backup
tar -czf "$BACKUP_DIR/openvpn-$TIMESTAMP.tar.gz" \
    ./openvpn-data/pki \
    ./openvpn-data/ta.key

# Clean old backups
find "$BACKUP_DIR" -name "openvpn-*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup created: $BACKUP_DIR/openvpn-$TIMESTAMP.tar.gz"
```

Add to crontab:
```bash
0 2 * * * cd /home/user/docker/openvpn && bash backup-daily.sh
```

### Restore from Backup

```bash
# Restore from backup
tar -xzf openvpn-backup-20260119_120000.tar.gz -C ~/docker/openvpn/

# Restart container
docker restart openvpn
```

---

## Firewall Rules (UFW Example)

```bash
# UFW firewall rules
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow OpenVPN
sudo ufw allow 1194/udp

# Allow DNS over TLS
sudo ufw allow 853/tcp

# Enable
sudo ufw enable

# Check status
sudo ufw status verbose
```

---

**Last Updated**: January 2026
