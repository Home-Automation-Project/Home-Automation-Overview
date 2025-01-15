plex server will allow you to host all of your digital media and to stream it.   

This document will include how to setup your plex server, digitize your media libraries, setup remote backup and organize them so that Plex can correctly recognize them.

# Plex Server Setup
plex can be hosted on Windows, Linux, docker, certain NAS devices.
https://www.plexopedia.com/plex-media-server/general/operating-system-plex/

Due to the lighter weight nature, and to support 4k HDR tone mapping, I recommend using Linux.

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

### File Labeling
**Movies**
Movies are labeled with the name of the movie and the release year in parenthases.  e.g. Star Wars (1977)
If you have multiple [**editions**](https://support.plex.tv/articles/multiple-editions/) you can indicate these inside {} with the keyword edition.  e.g. Blade Runner (1982) {edition-Director's Cut}.
Editions represent different releases of an item. So, the “theatrical release” vs the “Special Edition” of The Empire Strikes Back. Or “Theatrical” vs “Director’s Cut” vs “Final Cut” of Blade Runner. Editions would also be appropriate for a 2D vs 3D version of a movie.

If you have multiple [**versions**](https://support.plex.tv/articles/200381043-multi-version-movies/) you can indicate these as MovieName (Release Year) - ArbitraryText.ext.  e.g. Pulp Fiction (1994) - 1080p.mkv  Pulp Fiction (1994) - SD.m4v
Versions all represent the same release of an item. So, you can have multiple versions (1080p vs 480p, HEVC vs H.264, MP4 vs MKV) of The Empire Strikes Back, but they’re all for the same theatrical release of the movie

If you have [**special features**](https://support.plex.tv/articles/local-files-for-trailers-and-extras/), extras, etc you can label them like this.  Movies/MovieName (Release Date)/Descriptive_Name-Extra_Type.ext
Where -Extra_Type is one of:

-behindthescenes
-deleted
-featurette
-interview
-scene
-short
-trailer
-other

e.g.
/Movies
   /Avatar (2009)
      Avatar (2009).mkv
      Arrival-scene.mp4
      Bar Fight-deleted.mp4
      Performance Capture-behindthescenes.mkv
      Sigourney Weaver-interview.mp4
      Stephen Lang-interview.mp4
      Teaser Trailer-trailer.mp4
      Theatrical Trailer #1-trailer.mp4
      Theatrical Trailer #2-trailer.avi

## backups


