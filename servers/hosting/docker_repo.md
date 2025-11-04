# Hosting Docker Images

This will setup HTTPS, a real hostname (e.g., registry.lan), and logins

1. Create basic-auth credentials
# install htpasswd if needed (e.g., 'apache2-utils' on Debian/Ubuntu)
`htpasswd -nbB myuser 'S3cureP@ss' | sed -e 's/\$/\$\$/g' > auth.htpasswd`
# will output "myuser:hash..." ; we’ll mount this file

2. Setup registry
Replace registry.lan with your real DNS (point it to the host’s IP). If you already have Traefik running, remove that service and keep only registry with the labels.
docker-compose script
version: "3.9"

services:
  registry:
    image: registry:2
    environment:
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /var/lib/registry
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Origin: ['*']
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Methods: ['GET, DELETE, PUT, POST, HEAD']
      REGISTRY_HTTP_HEADERS_Access-Control-Allow-Headers: ['Authorization, Accept, Cache-Control']
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: "Registry Realm"
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/auth.htpasswd
      # enable deletions (with GC)
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
    volumes:
      - /srv/registry/data:/var/lib/registry
      - ./auth.htpasswd:/auth/auth.htpasswd:ro
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.registry.rule=Host(`registry.lan`)"
      - "traefik.http.routers.registry.entrypoints=websecure"
      # If using Let's Encrypt via Traefik:
      # - "traefik.http.routers.registry.tls.certresolver=le"
      # Basic auth (Traefik side — defense in depth)
      - "traefik.http.middlewares.regauth.basicauth.usersfile=/auth/auth.htpasswd"
      - "traefik.http.routers.registry.middlewares=regauth"
      - "traefik.http.services.registry.loadbalancer.server.port=5000"
    restart: unless-stopped
  registry-ui:
    image: joxit/docker-registry-ui:latest
    environment:
      - REGISTRY_TITLE=Local Registry
      - REGISTRY_URL=https://registry.lan          # <-- must match your registry HTTPS URL
      - DELETE_IMAGES=true                         # enable delete buttons
      - SINGLE_REGISTRY=true
      - SHOW_CONTENT_DIGEST=true
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.registry-ui.rule=Host(`ui.registry.lan`)" # pick a UI hostname
      - "traefik.http.routers.registry-ui.entrypoints=websecure"
      # reuse same basic-auth middleware if you want login on the UI too:
      - "traefik.http.routers.registry-ui.middlewares=regauth"
      - "traefik.http.services.registry-ui.loadbalancer.server.port=80"
    depends_on:
      - registry
    restart: unless-stopped
`
3. Bring it up: `docker compose up -d`
* Now your registry is at https://registry.lan/
4. Login: `docker login registry.lan`
* Default username: myuser  password: S3cureP@ss
5. How to use
`
docker tag myapp:1.0 registry.lan/myteam/myapp:1.0
docker push registry.lan/myteam/myapp:1.0
docker pull registry.lan/myteam/myapp:1.0
`
6. Access UI
* Browse to https://ui.registry.lan/ and sign in (Traefik basic auth).
* The UI will call the Registry API at https://registry.lan


7. Setup backups
Backing store options: instead of local disk, you can use S3-compatible storage (e.g., MinIO on your LAN). Set REGISTRY_STORAGE=s3 envs accordingly.


## Common gotchas
* Tag format matters: docker tag foo localhost:5000/foo:1.0 (registry prefix must be first).
* DNS/Cert name must match: push/pull using exactly the hostname on your cert (e.g., use registry.lan, not the IP).
* MTU/firewalls: if pushes hang, check MTU on overlay networks and open 443/80 to the host.
* Rootless Docker: if clients run rootless, ensure their cert trust store includes your CA if you use a private CA.

## Garbage Collection (reclaim disk):
* Enable deletes as shown (REGISTRY_STORAGE_DELETE_ENABLED: "true").
* Delete tags/manifests via API or UI.
* Run GC when the registry is stopped:
`
docker stop registry
docker run --rm -v /srv/registry/data:/var/lib/registry registry:2 \
  bin/registry garbage-collect /etc/docker/registry/config.yml
docker start registry
`
* If you’re using only env vars, mount a minimal config that includes storage: delete: enabled: true.

**NOTE**
If you want Team + policies/scanning you will want to add Harbor to your setup