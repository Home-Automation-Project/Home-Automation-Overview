# Media Digitization 
It is always recommended that you retain your physical media as proof of licensing.  I bought large CD holders and put in the disks and put these into storage and threw away the containers to save space

## Movies
### Manual Digitization
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

### Automated Digitization
I would **highly recommend** that you use the **docker setup** which we created in [this project]() which will allow you to launch your entire system through a simple docker-compose.

If you want to manually setup your own system outside docker then you can take a look at the following.
**Front End**
- [Ombi](https://docs.ombi.app/)  Media request interface

[**Collection Managers**](https://wiki.servarr.com/)
- [Radarr](https://wiki.servarr.com/radarr)  Movie collection manager
- [Sonarr](https://wiki.servarr.com/sonarr)  TV collection manager
- [Lidarr](https://wiki.servarr.com/lidarr)  Music collection manager
- [Readarr](https://wiki.servarr.com/readarr)  E-book and audiobook collection manager

**Indexers**
- Jackett

**Downloaders**
- [NZBGet](https://nzbget.com/download/)  Download manager

## Music
