# Hosting Docker Images and Python Packages

### Docker Registry + Private PyPI + Traefik + TLS + UI + Backups

This guide sets up a **complete self‑hosted development infrastructure**
on a **Raspberry Pi 4B**.

It includes:

-   Private **Docker Registry**
-   Private **PyPI (pip) server**
-   **Traefik reverse proxy**
-   **TLS certificates**
-   **Docker Registry Web UI**
-   **PyPI Web UI**
-   **Watchtower automatic container updates**
-   **Nightly NAS backups**
-   Storage located on a **NAS**

------------------------------------------------------------------------

# Network Layout

  Device         Address
  -------------- -------------------
  Raspberry Pi   static via router
  NAS            192.168.4.6

NAS directories:

    /public/pi/dev/images
    /public/pi/dev/mypy

------------------------------------------------------------------------

# Architecture

    Developer PC
       | docker push / pip install
       v
    +--------------------------+
    | Raspberry Pi 4B          |
    |                          |
    | Traefik Reverse Proxy    |
    | Docker Registry          |
    | Registry UI              |
    | PyPI Server              |
    | Watchtower               |
    +------------+-------------+
                 |
                 v
    +--------------------------+
    | NAS 192.168.4.6          |
    |                          |
    | /public/pi/dev/images    |
    | /public/pi/dev/mypy      |
    +--------------------------+

------------------------------------------------------------------------

# 1 Flash Raspberry Pi OS

Flash:

**Raspberry Pi OS Lite (64‑bit)**

Recommended settings in Raspberry Pi Imager:

-   hostname: `pi-dev`
-   enable SSH
-   configure WiFi (if needed)
-   create user/password
-   set timezone

Boot and SSH into the Pi.

------------------------------------------------------------------------

# 2 Update System

``` bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y   ca-certificates   curl   gnupg   git   nfs-common   apache2-utils   ufw
sudo reboot
```

------------------------------------------------------------------------

# 3 Reserve Static IP

Best method: configure your router.

Example:

    hostname: pi-dev
    ip: 192.168.4.20

------------------------------------------------------------------------

# 4 Mount NAS Storage

Create mount directories:

``` bash
sudo mkdir -p /mnt/nas/images
sudo mkdir -p /mnt/nas/mypy
```

Test NFS mount:

``` bash
sudo mount -t nfs 192.168.4.6:/public/pi/dev/images /mnt/nas/images
sudo mount -t nfs 192.168.4.6:/public/pi/dev/mypy /mnt/nas/mypy
```

Persist mounts:

    sudo nano /etc/fstab

Add:

    192.168.4.6:/public/pi/dev/images /mnt/nas/images nfs defaults,_netdev,nofail 0 0
    192.168.4.6:/public/pi/dev/mypy /mnt/nas/mypy nfs defaults,_netdev,nofail 0 0

Test:

``` bash
sudo mount -a
```

------------------------------------------------------------------------

# 5 Install Docker

``` bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
newgrp docker
```

Install compose plugin:

    sudo apt install docker-compose-plugin

Verify:

    docker version
    docker compose version

------------------------------------------------------------------------

# 6 Directory Layout

Create service directory:

``` bash
mkdir -p ~/services/dev-stack
cd ~/services/dev-stack
```

NAS directories used:

    /mnt/nas/images/registry
    /mnt/nas/mypy/packages

Create them:

``` bash
sudo mkdir -p /mnt/nas/images/registry
sudo mkdir -p /mnt/nas/mypy/packages
```

------------------------------------------------------------------------

# 7 Authentication

Docker registry auth:

``` bash
sudo mkdir -p /opt/registry-auth
sudo htpasswd -Bc /opt/registry-auth/htpasswd registryuser
```

PyPI auth:

``` bash
sudo htpasswd -Bc /mnt/nas/mypy/.htpasswd pypiuser
```

------------------------------------------------------------------------

# 8 Docker Compose Stack

Create:

    docker-compose.yml

``` yaml
version: "3"

services:

  traefik:
    image: traefik:v3
    container_name: traefik
    command:
      - "--providers.docker=true"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--api.dashboard=true"
    ports:
      - "80:80"
      - "443:443"
      - "8081:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"

  registry:
    image: registry:2
    container_name: registry
    restart: unless-stopped
    environment:
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
    volumes:
      - /mnt/nas/images/registry:/var/lib/registry
      - /opt/registry-auth:/auth
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.registry.rule=Host(`registry.lthome.com`)"
      - "traefik.http.routers.registry.entrypoints=web"

  registry-ui:
    image: joxit/docker-registry-ui:latest
    container_name: registry-ui
    environment:
      - REGISTRY_TITLE=Docker Registry
      - REGISTRY_URL=http://registry:5000
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.registryui.rule=Host(`registry-ui.lthome.com`)"
      - "traefik.http.routers.registryui.entrypoints=web"

  pypi:
    image: pypiserver/pypiserver:latest
    container_name: pypi
    command: >
      run
      -p 8080
      -a .
      -P /data/.htpasswd
      /data/packages
    volumes:
      - /mnt/nas/mypy:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.pypi.rule=Host(`pypi.lthome.com`)"
      - "traefik.http.routers.pypi.entrypoints=web"

  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: --interval 86400
```

------------------------------------------------------------------------

# 9 Start Stack

    docker compose up -d

Verify:

    docker ps

------------------------------------------------------------------------

# 10 Configure Docker Clients

Edit:

    /etc/docker/daemon.json

Add:

    {
     "insecure-registries": ["registry.lthome.com"]
    }

Restart Docker:

    sudo systemctl restart docker

Push image:

    docker tag myimage registry.lthome.com/myimage
    docker push registry.lthome.com/myimage

------------------------------------------------------------------------

# 11 Configure pip

Create:

    ~/.pip/pip.conf

    [global]
    index-url = http://pypi.lthome.com/simple
    trusted-host = pypi.lthome.com

------------------------------------------------------------------------

# 12 Upload Python Packages

Install build tools:

    pip install build twine

Build:

    python -m build

Upload:

    twine upload --repository-url http://pypi.lthome.com dist/*

------------------------------------------------------------------------

# 13 Firewall

Enable UFW:

    sudo ufw allow 22
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw enable

------------------------------------------------------------------------

# 14 Nightly Backups

Create backup script:

    sudo nano /usr/local/bin/dev-backup.sh

Example:

``` bash
#!/bin/bash

rsync -av /mnt/nas/images /mnt/nas/backups/images
rsync -av /mnt/nas/mypy /mnt/nas/backups/mypy
```

Make executable:

    sudo chmod +x /usr/local/bin/dev-backup.sh

Add cron:

    crontab -e

    0 3 * * * /usr/local/bin/dev-backup.sh

------------------------------------------------------------------------

# 15 Useful URLs

    Traefik Dashboard
    http://pi-ip:8081

    Docker Registry
    http://registry.lthome.com

    Registry UI
    http://registry-ui.lthome.com

    PyPI Server
    http://pypi.lthome.com

------------------------------------------------------------------------

# Future Improvements

Recommended upgrades:

-   automatic TLS via Let's Encrypt
-   Harbor registry
-   full CI/CD builds
-   PyPI mirror caching
-   S3 storage backend
-   monitoring with Prometheus + Grafana

------------------------------------------------------------------------

# End
