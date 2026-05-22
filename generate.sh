#!/bin/bash
# generate-compose.sh

# Danh sách proxy: "user:pass@host:port"
PROXIES=(

)

cat > docker-compose.yml << 'HEADER'
services:
HEADER

for i in "${!PROXIES[@]}"; do
  N=$((i+1))
  PROXY=${PROXIES[$i]}
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
    command: --proxy socks5://${PROXY} --dns over-tcp
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "cat", "/proc/net/dev"]
      interval: 2s
      timeout: 2s
      retries: 10

  ubuntu-${N}:
    build: .
    network_mode: "container:tun2proxy-${N}"
    stdin_open: true
    tty: true
    depends_on:
      tun2proxy-${N}:
        condition: service_healthy
    restart: on-failure

EOF
done

echo "Generated docker-compose.yml with ${#PROXIES[@]} proxies"
