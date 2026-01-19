#!/bin/bash

# Backup OpenVPN Data
# Creates encrypted backup of all certificates and keys

set -e

BACKUP_DIR="./openvpn-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/openvpn-backup-$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "[*] Creating OpenVPN backup..."

# Backup to tar.gz
tar -czf "$BACKUP_FILE" ./openvpn-data/pki ./openvpn-data/ta.key 2>/dev/null || true

if [ -f "$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo "[+] Backup created successfully!"
    echo "    File: $BACKUP_FILE"
    echo "    Size: $SIZE"
    echo ""
    echo "[!] IMPORTANT: Store this backup securely!"
    echo "    This contains all private keys and certificates."
else
    echo "[!] Backup failed!"
    exit 1
fi

# Optional: Encrypt backup with GPG
read -p "Encrypt backup with GPG password? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "[*] Encrypting backup..."
    gpg --symmetric --cipher-algo AES256 "$BACKUP_FILE"
    rm "$BACKUP_FILE"
    echo "[+] Backup encrypted: ${BACKUP_FILE}.gpg"
fi
