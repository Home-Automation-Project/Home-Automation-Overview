plex server will allow you to host all of your digital media and to stream it.   

This document will include how to setup your plex server, digitize your media libraries, setup remote backup and organize them so that Plex can correctly recognize them.

# Plex Server Setup
plex can be hosted on Windows, Linux, docker, certain NAS devices.
https://www.plexopedia.com/plex-media-server/general/operating-system-plex/

Due to the lighter weight nature, and to support 4k HDR tone mapping I recommend using Linux.

## Plex Installation


**Ports**
The most important port to make sure your firewall allows is the main TCP port the Plex Media Server uses for communication:
TCP: 32400 (access to the Plex Media Server) [required]

The following additional ports are also used within the local network for different services:
UDP: 1900 (access to the Plex DLNA Server)
UDP: 5353 (older Bonjour/Avahi network discovery)
TCP: 8324 (controlling Plex for Roku via Plex Companion)
UDP: 32410, 32412, 32413, 32414 (current GDM network discovery)
TCP: 32469 (access to the Plex DLNA Server)
Warning!: For security, we very strongly recommend that you do not allow any of these “additional” ports through the firewall or to be forwarded in your router, in cases specifically where your Plex Media Server is running on a machine with a public/WAN IP address. This includes those hosted in a data center as well as machines on a “local network” that have been put into the “DMZ” (the “de-militarized zone”) of the network router. This is not a setup that applies to most users.

## Plex Configuration 

# media 

## Digitization 
### Manual digitization
To manually copy your media you will need a computer and a corresponding ROM device (e.g. DVD for DVDs and CDs, Blueray for Blueray, DVD and CDs).
**Rip the disk**.  
You can use MakeMKV.  If the disk cannot be ripped due to being "protected" you can usually use ShrinkDVD to rip it to disk and then use MakeMKV to make your Plex files.
Detailed Instructions

MakeMKV


**DVD Shrink**
1.  Set settings:  Edit > Preferences
2.  Output Files Tab:  Select all three of the following: Remove Macrovision Protection; Remove P-UOPs; Remove Layer Break
3.  Stream Selections Tab:  Audio Language and Coding Types is put to "All Languages" and "AC3 or LPCM"
4.  Exit Settings
5.  Click Open Disk, Select the Drive of your ROM
6.  After scan finishes select all folders it finds and then click on Backup!



## naming and organizing 
Create your base directories for media storage
/Media
   /Movies
      movie content
   /Music
      music content
   /TV Shows
      television content

**File Labeling**
Labeling different editions of the same movie:  https://support.plex.tv/articles/multiple-editions/
Labeling different versions of the same movie:  https://support.plex.tv/articles/200381043-multi-version-movies/


## backups


