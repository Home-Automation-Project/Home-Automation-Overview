# Hosting PIP repo
Here is the setup to host your own PIP repository for your own python packages and libraries

This setup will include:
* Private indices per project/team
* Mirrors/caching of pypi.org (faster/air-gap friendly)
* Users/permissions, search, web UI
* Compatible with pip, twine, Poetry, PDM

## Setup
1. Create docker-compose file
`
version: "3.9"
services:
  devpi:
    image: ghcr.io/devpi/devpi:server
    environment:
      DEVPI_SERVER_HOST: 0.0.0.0
      DEVPI_SERVER_PORT: 3141
    volumes:
      - /srv/devpi:/devpi
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.devpi.rule=Host(`pypi.lan`)"
      - "traefik.http.routers.devpi.entrypoints=websecure"
      - "traefik.http.services.devpi.loadbalancer.server.port=3141"
    restart: unless-stopped
`
2. Setup environment (first time use)
`
docker exec -it <devpi_container> devpi-init
docker exec -it <devpi_container> devpi-gen-config
# optional nginx configs are generated, but Traefik labels above are enough
`
3. Create user + index
Change the user name <user> and password <password> as desired
`
docker exec -it <devpi_container> devpi use http://localhost:3141
docker exec -it <devpi_container> devpi user -c <user> password='<password>'
docker exec -it <devpi_container> devpi login <user> --password='<password>'
docker exec -it <devpi_container> devpi index -c <user>/dev bases=root/pypi volatile=True
`
https://pypi.lan/<user>/dev/simple/

## How to use
1. Upload code
`
python -m build
twine upload --repository-url https://pypi.lan/<user>/dev/ -u <user> -p '<passowrd>' dist/*
`

2. Install package
`pip install --index-url https://<user>:<password>@pypi.lan/<user>/dev/simple mypkg
`
You can chain indices (e.g., your private index bases on root/pypi) so pip resolves first from your private packages and then transparently falls back to cached PyPI—no extra-index-url needed.

## Security & reliability tips

* Prefer --index-url over --extra-index-url to avoid dependency confusion. If you must use extra, pin internal names or block them on public PyPI.
* TLS + DNS: Use a real LAN hostname (e.g., pypi.lan) with a trusted cert (Traefik makes this easy).
* Credentials: Basic auth is fine for a home lab. For teams, devpi user accounts are nicer than sharing a single password.
* Backups: pypiserver = backup /srv/pypi/packages; devpi = backup /srv/devpi (contains files + index state).
* Air-gapped builds: with devpi, pre-warm/cache dependencies by installing once through it; then disable outbound access if needed.
* Cleanup: publish only wheels for your target platforms to keep storage tidy (pipx run build with --wheel).