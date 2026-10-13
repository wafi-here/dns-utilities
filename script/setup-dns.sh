#!/bin/bash

# Ensure script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script with sudo or as root."
  exit 1
fi

echo "=== Dynamic BIND9 DNS Server Setup Script ==="
echo "Press Enter to accept defaults shown in [brackets]"
echo ""

# Dynamic User Inputs with Defaults
read -p "Enter Domain Name [pas-paas.local]: " DOMAIN_NAME
DOMAIN_NAME=${DOMAIN_NAME:-pas-paas.local}

read -p "Enter Server IP Address [192.168.56.102]: " SERVER_IP
SERVER_IP=${SERVER_IP:-192.168.56.102}

# Parse Domain Base (e.g., pas-paas from pas-paas.local)
DOMAIN_BASE=$(echo "$DOMAIN_NAME" | cut -d'.' -f1)

# Parse IP octets for Reverse Zone (e.g., 192.168.56.102 -> ip1=192, ip2=168, ip3=56, ip4=102)
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

# 1. Package Installation (Non-interactive to prevent apt from sticking)
echo "[+] Updating repository and installing BIND9 packages..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y bind9 bind9utils bind9-doc[cite: 3]

# 2. Configuring /etc/bind/named.conf.local
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
EOF[cite: 4]

# 3. Exception-Handled Template Database Handling
echo "[+] Preparing template database files safely..."
if [ -f /etc/bind/db.local ]; then
    cp -f /etc/bind/db.local /etc/bind/db.$DOMAIN_BASE
else
    echo "[!] Warning: /etc/bind/db.local not found. Creating file from scratch..."
    touch /etc/bind/db.$DOMAIN_BASE
fi

if [ -f /etc/bind/db.127 ]; then
    cp -f /etc/bind/db.127 /etc/bind/db.$ip3[cite: 5]
else
    echo "[!] Warning: /etc/bind/db.127 not found. Creating file from scratch..."
    touch /etc/bind/db.$ip3
fi

# 4. Configuring Forward Zone File
echo "[+] Generating Forward Zone records..."
cat <<EOF > /etc/bind/db.$DOMAIN_BASE
\$TTL    604800
@       IN      SOA     ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      ns.$DOMAIN_NAME.
ns      IN      A       $SERVER_IP
@       IN      A       $SERVER_IP
EOF[cite: 5, 6]

# 5. Configuring Reverse Zone File
echo "[+] Generating Reverse Zone records..."
cat <<EOF > /etc/bind/db.$ip3
\$TTL    604800
@       IN      SOA     ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
                              1         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL

@       IN      NS      ns.$DOMAIN_NAME.
$ip4    IN      PTR     $DOMAIN_NAME.
EOF[cite: 5, 6]

# 6. Validate Configuration Syntax Before Restarting
echo "[+] Validating BIND configuration syntax..."
named-checkconf
named-checkzone "$DOMAIN_NAME" /etc/bind/db.$DOMAIN_BASE
named-checkzone "$REVERSE_ZONE_NAME" /etc/bind/db.$ip3

if [ $? -ne 0 ]; then
  echo "[-] Configuration syntax error detected! Please check your inputs."
  exit 1
fi

# 7. Restart and Enable BIND9 Service
echo "[+] Restarting and enabling BIND9 service..."
systemctl restart bind9[cite: 7]
systemctl enable bind9

echo ""
echo "=== Setup Completed Successfully! ==="
echo "[+] Checking BIND9 Service Status:"
systemctl status bind9 --no-pager[cite: 7]
