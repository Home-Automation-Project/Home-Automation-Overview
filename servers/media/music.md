# Music Library
This setup provides both the opportunity to stream your current music library as well as to play locally

## Streaming Setup
The streaming setup uses Navidrome

### Installation
1. Install Docker
```
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
sudo apt install -y docker-compose-plugin
```
2. Make dockerfile
`nano ~/navidrome/docker-compose.yml`
docker file
```
services:
  navidrome:
    image: deluan/navidrome:latest
    container_name: navidrome
    user: 1000:1000
    ports:
      - "4533:4533"
    volumes:
      - ./data:/data
      - ./music:/music:ro
    environment:
      ND_MUSICFOLDER: /music
      ND_DATAFOLDER: /data
      ND_SCANINTERVAL: 1h
      ND_LOGLEVEL: info
      ND_ENABLETRANSCODING: "true"
    restart: unless-stopped
```
3. Start up the application
```
cd ~/navidrome
docker compose up -d
docker logs navidrome
```
### Setup
First launch:
* Create admin user
* Music scan begins automatically
#### Setup Reverse Proxy
Use these labels for your Traefik
```
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.navidrome.rule=Host(`music.yourdomain.com`)"
  - "traefik.http.services.navidrome.loadbalancer.server.port=4533"
```

### Using
Navidrome works with:
* DSub (Android)
* Symfonium (Android – excellent)
* Substreamer (iOS)
* Audinaut (Web)

*Performance Tips for Raspberry Pi*
Setting	Recommendation
* Audio format	FLAC / MP3 fine
* Transcoding	Disable if not needed
* Scan interval	1–6 hours
* Storage	USB 3.0 SSD > HDD
* DB location	Local SD or SSD

## Local Play Setup
The local playing setup uses MoOde (or Volumino)

### Installation
### Setup
