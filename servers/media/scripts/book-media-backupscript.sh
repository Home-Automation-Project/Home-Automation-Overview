#!/bin/bash

DATE=$(date +%Y-%m-%d)
DEST="/home/pi/backups/$DATE"
mkdir -p "$DEST"

# Backup configs and media
tar -czf "$DEST/configs.tar.gz" -C ~/media-server \
  kavita/config \
  calibre-web/config \
  audiobookshelf/config \
  lazylibrarian/config \
  traefik.yml \
  dynamic.yml \
  docker-compose.yml \
  letsencrypt

tar -czf "$DEST/media.tar.gz" -C ~/media-server/media .

# Optional: remove backups older than 7 days
find /home/pi/backups/* -mtime +7 -exec rm -rf {} \;

echo "Backup completed to $DEST"
