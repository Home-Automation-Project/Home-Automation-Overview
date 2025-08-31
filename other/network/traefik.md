# Requirements
Hardware:
* Raspberry Pi 3B (any revision)
* Raspberry Pi OS (Lite or Full)
* Static IP or DHCP reservation
* Optional: Docker (if reverse proxying Docker containers)

Software:
* Traefik v2 (lightweight and ARM-compatible)
* Systemd service (or Docker if preferred)

Note:  If you are only forwarding traffic to docker containers (no physical hosting or databases) then use the docker version of traefik.  Since I have a larger system I will show how to install traefik manually.

# Installation
1. Create directory
```
sudo mkdir -p /etc/traefik
cd /etc/traefik
sudo mkdir -p certs
```
2. Download app
```
cd /usr/local/bin
sudo wget https://github.com/traefik/traefik/releases/latest/download/traefik_linux_armv7.tar.gz
sudo tar -xzf traefik_linux_armv7.tar.gz
sudo rm traefik_linux_armv7.tar.gz
sudo chmod +x traefik
```
3. Create config
```
# /etc/traefik/traefik.yml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

api:
  dashboard: true

providers:
  file:
    directory: "/etc/traefik/dynamic"
    watch: true

log:
  level: INFO
  ```
4. Create dynamic configs (as needed)
`sudo mkdir /etc/traefik/dynamic`
* Https example
```
http:
  routers:
    example:
      rule: "Host(`example.local`)"
      service: example-service
      entryPoints:
        - web
  services:
    example-service:
      loadBalancer:
        servers:
          - url: "http://192.168.1.100:8080"
```
5. Create systemd service file
* `sudo vim /etc/systemd/system/traefik.service`
add the following
```
[Unit]
Description=Traefik
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.yml
Restart=always

[Install]
WantedBy=multi-user.target
```
6. Start system
```
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable traefik
sudo systemctl start traefik
```
# 

