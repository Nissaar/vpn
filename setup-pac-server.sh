#!/bin/bash

# Export OpenVPN Config to Server (for hosting PAC file)
# Serves the proxy.pac file via HTTPS through a web container

cat > docker-compose-pac-server.yml <<'EOF'
version: "3.8"

services:
  pac-server:
    container_name: pac-server
    image: caddy:latest
    networks:
      - frontend
    volumes:
      - ./proxy.pac:/var/www/html/proxy.pac:ro
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pac.rule=Host(`vpn.yourdomain.com`) && Path(`/proxy.pac`)"
      - "traefik.http.routers.pac.entrypoints=websecure"
      - "traefik.http.routers.pac.tls.certresolver=leresolver"
      - "traefik.http.services.pac.loadbalancer.server.port=80"
    restart: unless-stopped

networks:
  frontend:
    external:
      name: frontend
EOF

# Create Caddyfile for serving proxy.pac
cat > Caddyfile <<'EOF'
:80 {
    root * /var/www/html
    file_server
    
    # Set proper content-type for PAC files
    header /proxy.pac Content-Type "application/x-ns-proxy-autoconfig"
    
    # CORS headers for cross-origin requests
    header /proxy.pac Access-Control-Allow-Origin "*"
}
EOF

echo "[+] PAC server configuration created!"
echo "    docker-compose-pac-server.yml"
echo "    Caddyfile"
echo ""
echo "To deploy: docker-compose -f docker-compose-pac-server.yml up -d"
