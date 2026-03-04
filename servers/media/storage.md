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

# Attach SAN that requires creds
1. Install SMB client
   ```sudo apt update
sudo apt install -y cifs-utils```
2. Create mount directory `sudo mkdir -p /mnt/nas`
3. Create credentials file
```sudo mkdir -p /etc/smbcredentials
sudo nano /etc/smbcredentials/nas-dev```
put this in the file (example creds)
```
username=MyUser
password=Mypassword```
4. Lock down permissions
```
sudo chmod 600 /etc/smbcredentials/nas-dev
sudo chown root:root /etc/smbcredentials/nas-dev```
5. Test
```
sudo mount -t cifs //192.168.4.6/public /mnt/nas \
-o credentials=/etc/smbcredentials/nas-dev,uid=1000,gid=1000,iocharset=utf8
```
6. Make permanent
```
sudo nano /etc/fstab

fstab:
//192.168.4.6/public  /mnt/nas  cifs  credentials=/etc/smbcredentials/nas-dev,uid=1000,gid=1000,iocharset=utf8,file_mode=0664,dir_mode=0775,_netdev,nofail  0  0
```
7. Test
```
sudo umount /mnt/nas
sudo mount -a
df -h | grep nas
```
**NOTE**
* If the SAN has SSD caching, enable it.


# Setup Offsite Backups
## Glacier option
## * Option
