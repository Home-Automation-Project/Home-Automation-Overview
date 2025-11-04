# Media Storage Setup
Your SAN will need the following folder structure
e.g. 
`mkdir -p ~/media-server/{kavita,calibre-web,audiobookshelf}`

/media
    plex/
        movies/
        tv/
    music/
    pictures/
    notes/
    configs/
        lazylibrarian/
        audiobookshelf/
        calibre-web/
        kavita/
        nzbget/
    books/
        books/
        comics/
        audiobooks/
        downloads/
        metadata/
            audiobookshelf/
            lazylibrarian/

# Attach to SAN
Using NFS for best performance and simplicity
1. `sudo nano /etc/fstab`
2. `192.168.0.50:/media  /mnt/media  nfs  defaults,_netdev  0  0` # where the ip address is that of the SAN
3. Mount the drive
`sudo mkdir -p /mnt/media
sudo mount -a
`
4. Create your folder structure in `/mnt/media`
5. Set permissions
`
sudo chown -R 1000:1000 /mnt/media
sudo chmod -R 775 /mnt/media
`
**NOTE**
* If the SAN has SSD caching, enable it.


# Setup Offsite Backups
## Glacier option
## * Option