#!/bin/bash
# generate-compose.sh

# Danh sách proxy: "user:pass@host:port"
PROXIES=(
  SITHIMY5202:0rf81r1aanxa@216.98.228.143:5844
  SITHIMY5202:0rf81r1aanxa@72.1.179.56:6450
  SITHIMY5202:0rf81r1aanxa@45.56.160.178:7721
  SITHIMY5202:0rf81r1aanxa@198.145.102.114:5470
  SITHIMY5202:0rf81r1aanxa@9.142.39.191:7361
  SITHIMY5202:0rf81r1aanxa@9.142.30.192:5850
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
