# Media Servers Setup

## plex

## Books
* Setup using a Raspberry Pi 4 and Kavita + Calibre-Web + Audiobookshelf + LazyLibrarian
* Kavita for comics, manga, and ebooks
* Calibre-Web for traditional ebooks and metadata management
* Audiobookshelf for audiobooks with sync and bookmarks

### Installation and setup
1. Make sure you have: Raspberry Pi 4 (2GB)
2. Raspberry Pi OS Lite (64-bit recommended)
3. Internet connection
4. SSH access or keyboard/monitor
5. External storage (USB SSD recommended for media)
6. Install docker
`sudo apt update && sudo apt upgrade -y`
`sudo apt install vim -y`
`curl -sSL https://get.docker.com | sh`
`sudo usermod -aG docker $USER`
`newgrp docker`
`sudo apt install -y docker-compose`
7. Create Folder Structure
`mkdir -p ~/media-server/{kavita,calibre-web,audiobookshelf}`
./media/books/          # For Calibre-Web
./media/comics/         # For Kavita
./media/audiobooks/     # For Audiobookshelf


`cd ~/media-server`
8. Inside ~/media-server, create a [docker-compose.yml](./scripts/book-media-docker-compose.yml) file
9. Launch the Stack
`cd ~/media-server`
`docker-compose up -d`

### Set to autostart on reboots
1. Enable docker to start
`sudo systemctl enable docker`
2. Create a new systemd unit file (enter path to your stack)
`sudo vim /etc/systemd/system/media-server.service`
* Add this text
```
[Unit]
Description=Media Server Stack (Kavita + Calibre-Web + Audiobookshelf)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=/home/pi/media-server
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
```
* Save the file
4. Enable the Service
`sudo systemctl enable media-server`
* After a reboot (e.g. `sudo reboot`) you can verify services are running with `docker ps`

### Configure Download Service
1. Open LazyLibrarian, click on Settings
2. General Tab
| Setting                 | Value                                  |
| ----------------------- | -------------------------------------- |
| **Books Folder**        | `/books`                               |
| **Download Dir**        | `/downloads`                           |
| **Post-Processing Dir** | `/downloads/complete` or same as above |
| **Interface**           | `0.0.0.0`                              |
| **Port**                | `5299`                                 |
3. Downloaders Tab
| Setting               | Value                              |
| --------------------- | ---------------------------------- |
| **Type**              | NZBGet                             |
| **Host**              | `nzbget` (internal container name) |
| **Port**              | `6789`                             |
| **Username/Password** | `nzbget` / `tegbzn6789` (default)  |
4. Importing Tab
| Setting                  | Value                             |
| ------------------------ | --------------------------------- |
| **Book Library Folder**  | `/books`                          |
| **Scan Interval**        | `360` (or however often you want) |
| ✅ Auto Add Books         | Enabled                           |
| ✅ Post-process downloads | Enabled                           |
5. Audiobooks Download Tab
| Setting                                    | Value                    |
| ------------------------------------------ | ------------------------ |
| **Download Directory**                     | `/downloads/audiobooks`  |
| **AudioBook Library Folder**               | `/media/audiobooks`      |
| ✅ **Use Download Dir for Post Processing** | Yes                      |
| ✅ **Scan Library Folder**                  | Yes                      |
| **Move, Rename & Clean**                   | Enable all               |
| **Post-processing command**                | Optional, or leave blank |
| ✅ **Use NZB/Torrent for Audiobooks**       | Yes (use NZBGet)         |

6. Metadata providers
* Google Books:
✅ Enable it
No API key needed for basic use

* OpenLibrary:
✅ Enable it
No API key required

### Access Your Services
Service	URL	Default Login Info
Kavita	http://<pi-ip>:5000	Set on first run
Calibre-Web	http://<pi-ip>:8083	admin / admin123
Audiobookshelf	http://<pi-ip>:13378	Set on first run
LazyLibrarian http://<pi-ip>:5299
NZBGet http://<pi-ip>:6789   nzbget / tegbzn6789 (default)

## Backups
| What                  | Path                 | Purpose                   |
| --------------------- | -------------------- | ------------------------- |
| Docker volumes/config | `./<service>/config` | App settings, DBs         |
| Media                 | `./media/`           | Books, comics, audiobooks |
| Downloads (optional)  | `./downloads/`       | In-progress items         |
| Docker Compose file   | `docker-compose.yml` | Service definitions       |

### Install dropbox uploader
`cd ~`
`git clone https://github.com/andreafabrizi/Dropbox-Uploader.git`
`cd Dropbox-Uploader`
`chmod +x dropbox_uploader.sh`
`./dropbox_uploader.sh`

### Setup Script
* [Backup Script](./scripts/book-media-backupscript.sh)
1. Create backup script on server
2. Schedule with CRON
`crontab -e`
`0 2 * * * /bin/bash /home/pi/backup.sh`
* Backup to dropbox
# Upload to Dropbox
`~/Dropbox-Uploader/dropbox_uploader.sh upload "$DEST/configs.tar.gz" "/backups/$DATE-configs.tar.gz"`
`~/Dropbox-Uploader/dropbox_uploader.sh upload "$DEST/media.tar.gz" "/backups/$DATE-media.tar.gz"`

## Setup monitoring/alerting
[View documentation](../../other/alert_monitoring.md)