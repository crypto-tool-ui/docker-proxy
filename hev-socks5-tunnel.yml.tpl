tunnel:
  name: tun0
  mtu: 1200
  ipv4: 198.18.0.1
  ipv6: false

socks5:
  port: __PROXY_PORT__
  address: __PROXY_HOST__
  username: "__PROXY_USER__"
  password: "__PROXY_PASS__"

  udp: false
  mark: 438

misc:
  log-level: debug
  limit-nofile: 65536