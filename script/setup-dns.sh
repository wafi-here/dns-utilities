
#!/bin/bash

# ==========================================================
# DNS SERVER SETUP - BIND9
# OS       : Ubuntu Server
# Service  : BIND9
# ==========================================================

set -Eeuo pipefail

# -------------------- KONFIGURASI -------------------------

DOMAIN_NAME="${DOMAIN_NAME:-pas-paas.local}"
SERVER_IP="${SERVER_IP:-192.168.56.102}"

# -------------------- VALIDASI INPUT ----------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: Jalankan script menggunakan sudo."
    echo "Contoh: sudo ./setup-dns.sh"
    exit 1
fi

if ! [[ "$SERVER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Error: Format IP address tidak valid."
    exit 1
fi

IFS='.' read -r ip1 ip2 ip3 ip4 <<< "$SERVER_IP"

for octet in "$ip1" "$ip2" "$ip3" "$ip4"; do
    if (( 10#$octet > 255 )); then
        echo "Error: IP address tidak valid."
        exit 1
    fi
done

if (( 10#$ip4 == 0 || 10#$ip4 == 255 )); then
    echo "Error: Gunakan IP host yang valid."
    exit 1
fi

if ! [[ "$DOMAIN_NAME" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Error: Format domain tidak valid."
    exit 1
fi

DOMAIN_BASE="${DOMAIN_NAME%.}"
REVERSE_ZONE_NAME="${ip3}.${ip2}.${ip1}.in-addr.arpa"

FORWARD_FILE="/etc/bind/db.${DOMAIN_BASE}"
REVERSE_FILE="/etc/bind/db.${ip3}"

echo "=================================================="
echo " DNS SERVER SETUP"
echo "=================================================="
echo "Domain       : $DOMAIN_NAME"
echo "Server IP    : $SERVER_IP"
echo "Forward DB   : $FORWARD_FILE"
echo "Reverse zone : $REVERSE_ZONE_NAME"
echo "Reverse DB   : $REVERSE_FILE"
echo "=================================================="

# -------------------- INSTALASI BIND9 ---------------------

echo "[1/6] Menginstal BIND9..."

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y bind9 bind9-utils dnsutils

# -------------------- BACKUP KONFIGURASI ------------------

echo "[2/6] Membuat backup konfigurasi..."

BACKUP_DIR="/root/bind9-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp -a /etc/bind/named.conf.local "$BACKUP_DIR/" \
    2>/dev/null || true

# -------------------- KONFIGURASI ZONE --------------------

echo "[3/6] Mengatur named.conf.local..."

cat > /etc/bind/named.conf.local <<EOF
// Forward DNS Zone
zone "$DOMAIN_NAME" {
    type master;
    file "$FORWARD_FILE";
};

// Reverse DNS Zone
zone "$REVERSE_ZONE_NAME" {
    type master;
    file "$REVERSE_FILE";
};
EOF

# -------------------- FORWARD DNS --------------------------

echo "[4/6] Membuat forward zone..."

cat > "$FORWARD_FILE" <<EOF
\$TTL 604800

@   IN  SOA ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
        2026101301 ; Serial
        604800     ; Refresh
        86400      ; Retry
        2419200    ; Expire
        604800     ; Negative Cache TTL
)

@       IN  NS  ns.$DOMAIN_NAME.
ns      IN  A   $SERVER_IP
@       IN  A   $SERVER_IP
www     IN  A   $SERVER_IP
EOF

# -------------------- REVERSE DNS -------------------------

echo "[5/6] Membuat reverse zone..."

cat > "$REVERSE_FILE" <<EOF
\$TTL 604800

@   IN  SOA ns.$DOMAIN_NAME. root.$DOMAIN_NAME. (
        2026101301 ; Serial
        604800     ; Refresh
        86400      ; Retry
        2419200    ; Expire
        604800     ; Negative Cache TTL
)

@       IN  NS  ns.$DOMAIN_NAME.
$ip4    IN  PTR ns.$DOMAIN_NAME.
EOF

# -------------------- VALIDASI ----------------------------

echo "[6/6] Memeriksa konfigurasi DNS..."

named-checkconf

named-checkzone "$DOMAIN_NAME" "$FORWARD_FILE"
named-checkzone "$REVERSE_ZONE_NAME" "$REVERSE_FILE"

# -------------------- AKTIFKAN SERVICE ---------------------

echo "Mengaktifkan service BIND9..."

systemctl enable --now named
systemctl restart named

echo
echo "=================================================="
echo " DNS SERVER BERHASIL DIKONFIGURASI"
echo "=================================================="

systemctl --no-pager --full status named

echo
echo "Pengujian DNS lokal:"
dig @127.0.0.1 "$DOMAIN_NAME" +short
dig @127.0.0.1 "ns.$DOMAIN_NAME" +short

echo
echo "DNS Server IP : $SERVER_IP"
echo "Domain        : $DOMAIN_NAME"
echo "=================================================="
