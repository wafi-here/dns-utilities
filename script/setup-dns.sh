#!/bin/bash
#
# setup-dns.sh
# Fully dynamic BIND9 DNS Server configuration script for Ubuntu Server 22.04 LTS
# Based on LKPD_Konfigurasi_DNS_Server.pdf practical guidelines
#
# Built-in protections against "stuck" commands:
#   - cp -f          : Force overwrite without interactive prompts
#   - DEBIAN_FRONTEND=noninteractive : Prevent apt interactive dialogs
#   - cat <<EOF      : Write config files without using nano/vi (avoids lockups)
#

set -euo pipefail

# -----------------------------
# 1. Dynamic Parameters & Input
# -----------------------------

# Defaults (can be overridden by environment variables or interactive input)
DOMAIN_NAME="${DOMAIN_NAME:-pas-paas.local}"
SERVER_IP="${SERVER_IP:-192.168.56.102}"

echo "======================================================"
echo "  BIND9 DNS Server Setup Script (Ubuntu 22.04 LTS)"
echo "======================================================"
echo ""
echo "Press Enter to accept defaults shown in [brackets]"
echo ""

# Interactive input with defaults
read -rp "Enter Domain Name [${DOMAIN_NAME}]: " input_domain
DOMAIN_NAME="${input_domain:-$DOMAIN_NAME}"

read -rp "Enter Server IP Address [${SERVER_IP}]: " input_ip
SERVER_IP="${input_ip:-$SERVER_IP}"

# Validate IP format (basic)
if ! [[ "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    echo "[-] Invalid IP address format: $SERVER_IP"
    exit 1
fi

# Extract domain base (everything before first dot)
DOMAIN_BASE=$(echo "$DOMAIN_NAME" | cut -d'.' -f1)
DOMAIN_EXT=$(echo "$DOMAIN_NAME" | cut -d'.' -f2-)

# Parse IP octets for reverse zone
IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$SERVER_IP"
REVERSE_SUBNET="${ip3}.${ip2}.${ip1}"
REVERSE_ZONE_NAME="${REVERSE_SUBNET}.in-addr.arpa"

echo ""
echo "[+] Configuration summary:"
echo "    - Domain Name     : $DOMAIN_NAME"
echo "    - Domain Base     : $DOMAIN_BASE"
echo "    - Server IP       : $SERVER_IP"
echo "    - Reverse Zone    : $REVERSE_ZONE_NAME"
echo "    - Forward Zone DB : /etc/bind/db.$DOMAIN_BASE"
echo "    - Reverse Zone DB : /etc/bind/db.$ip3"
echo ""

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "[-] This script must be run as root (use sudo)."
    exit 1
fi

# -----------------------------
# 2. Package Installation (Non-interactive)
# -----------------------------
echo "[+] Updating repository and installing BIND9 packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq bind9 bind9utils bind9-doc

# -----------------------------
# 3. Configure /etc/bind/named.conf.local
# -----------------------------
echo "[+] Writing configuration to /etc/bind/named.conf.local..."
cat <<EOF > /etc/bind/named.conf.local
// Forward Zone Declaration
zone "$DOMAIN_NAME" {
    type master;
    file "/etc/bind/db.$DOMAIN_BASE";
};

// Reverse Zone Declaration
zone "$REVERSE_ZONE_NAME" {
    type master;
    file "/etc/bind/db.$ip3";
};
EOF

# -----------------------------
# 4. Copy Template Database Files (force overwrite)
# -----------------------------
echo "[+] Copying template database files safely..."
cp -f /etc/bind/db.local /etc/bind/db.$DOMAIN_BASE
cp -f /etc/bind/db.127   /etc/bind/db.$ip3

# -----------------------------
# 5. Configure Forward Zone File
# -----------------------------
echo "[+] Generating Forward Zone records..."
cat <<EOF > /etc/bind/db.$DOMAIN_BASE
\$TTL    604800
@       IN      SOA     ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMAIN_NAME.
ns      IN      A       $SERVER_IP
@       IN      A       $SERVER_IP
www     IN      A       $SERVER_IP
EOF

# -----------------------------
# 6. Configure Reverse Zone File
# -----------------------------
echo "[+] Generating Reverse Zone records..."
cat <<EOF > /etc/bind/db.$ip3
\$TTL    604800
@       IN      SOA     ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              1         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMAIN_NAME.
$ip4    IN      PTR     ns.$DOMAIN_NAME.
EOF

# -----------------------------
# 7. Validate Configuration Syntax
# -----------------------------
echo "[+] Validating BIND configuration syntax..."
named-checkconf

if ! named-checkzone "$DOMAIN_NAME" /etc/bind/db.$DOMAIN_BASE; then
    echo "[-] Forward zone syntax error!"
    exit 1
fi

if ! named-checkzone "$REVERSE_ZONE_NAME" /etc/bind/db.$ip3; then
    echo "[-] Reverse zone syntax error!"
    exit 1
fi

echo "[+] Configuration syntax is valid."

# -----------------------------
# 8. Restart and Enable BIND9 Service
# -----------------------------
echo "[+] Restarting BIND9 service..."
systemctl restart bind9
systemctl enable bind9

echo ""
echo "======================================================"
echo "  Setup Completed Successfully!"
echo "======================================================"
echo ""
echo "[+] BIND9 Service Status:"
systemctl status bind9 --no-pager || true

echo ""
echo "Useful test commands:"
echo "  dig @$SERVER_IP $DOMAIN_NAME"
echo "  dig @$SERVER_IP ns.$DOMAIN_NAME"
echo "  dig -x $SERVER_IP @$SERVER_IP"
echo "  named-checkconf"
echo ""
echo "Zone files created:"
echo "  /etc/bind/named.conf.local"
echo "  /etc/bind/db.$DOMAIN_BASE"
echo "  /etc/bind/db.$ip3"
echo ""
