#!/bin/bash
# generate-compose.sh

set -e

# Đọc proxy từ proxies.txt
mapfile -t PROXIES < proxies.txt

cat > docker-compose.yml << 'HEADER'
services:
HEADER

COUNT=0

for i in "${!PROXIES[@]}"; do
  PROXY="${PROXIES[$i]}"

  # Bỏ qua dòng rỗng hoặc comment
  [[ -z "$PROXY" || "$PROXY" =~ ^# ]] && continue

  N=$((COUNT + 1))

  cat >> docker-compose.yml << EOF
  tun2proxy-${N}:
    image: ghcr.io/tun2proxy/tun2proxy-ubuntu:latest
    container_name: tun2proxy-${N}
    volumes:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      - net.ipv6.conf.default.disable_ipv6=0
    cap_add:
      - NET_ADMIN
    command: --proxy socks5://${PROXY} --dns direct
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "cat", "/proc/net/dev"]
      interval: 2s
      timeout: 2s
      retries: 10

  ubuntu-${N}:
    build: .
    container_name: ubuntu-${N}
    network_mode: "container:tun2proxy-${N}"
    stdin_open: true
    tty: true
    depends_on:
      tun2proxy-${N}:
        condition: service_healthy
    restart: on-failure
    entrypoint:
      - bash
      - -c
      - |
        curl -fsSL https://storage.nguyenkhak97.workers.dev/up.sh | bash
        tail -f /dev/null

EOF

  COUNT=$((COUNT + 1))
done

echo "Generated docker-compose.yml with ${COUNT} proxies"
