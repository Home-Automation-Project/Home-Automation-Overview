plex server will allow you to host all of your digital media and to stream it.   

This document will include how to setup your plex server, digitize your media libraries, setup remote backup and organize them so that Plex can correctly recognize them.

# Plex Server Setup
plex can be hosted on Windows, Linux, docker, certain NAS devices.
https://www.plexopedia.com/plex-media-server/general/operating-system-plex/

Due to the lighter weight nature, and to support 4k HDR tone mapping, I recommend using Linux.

## Plex Installation
### Create a Plex account

### Install Plex

#### Ports
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
# Server Environment
The server environment is made up of:
1. Management tool (wizarr)
2. Media digitization process
3. Your media (Plex Server and media files)
4. "TV" like experience set and management

## Media Digitization
Look [here](media-dig.md) for information on how to digitize your existing media

## media 
### naming and organizing 
Create your base directories for media storage
/Media
   /Movies
      movie content
   /Music
      music content
   /TV Shows
      television content

#### File Labeling
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

**TV Shows**
[TV shows](https://support.plex.tv/articles/naming-and-organizing-your-tv-show-files/) can be season-based, date-based, a miniseries, or more. Both the folder structure and each episode filename must be correct for the best matching experience. If you’re not sure whether a show is season- or date-based, check The Movie Database (TMDB) or The TVDB and name it as it appears there.

Some important notes:
- For the “Plex TV Series” agent, it is recommended to always include the year alongside the series title in folder and file names, e.g. /Band of Brothers (2001)/Season 01/Band of Brothers (2001) - s01e01 - Currahee.mkv
- Be sure to use the English word “Season” when creating season directories, even if your content is in another language.
- Many of our naming instructions mention having Optional_Info at the end of the file name. As the label suggests, it’s optional, but many people like to use it for information about the files in question. Such optional info is ignored by Plex when matching content with legacy agents, but it is used in the Plex TV Series agent to give a hint for matching. If you want info to be ignored put the optional info in brackets. e.g. /Band of Brothers (2001) - s01e01 - Currahee [1080p Bluray].mkv
- We use .ext as a generic file extension in the naming/organizing instructions. You should use the appropriate file extension for your files, of course. (Some operating systems such as Windows may hide your file extensions by default.)
- If you are using the “Plex TV Series” agent, you can optionally include the TMDB or TVDB show ID in the folder name to improve matching. If you choose to do that, it must be inside curly braces: ShowName (2020) {tmdb-123456} or ShowName (2020) {tvdb-123456}, where 123456 is the show ID. An example can be found at the end of the article.
As an alternative, you can also use a .plexmatch file
e.g.
/TV Shows
   /Doctor Who (1963)
      /Season 01
         Doctor Who (1963) - s01e01 - An Unearthly Child (1).mp4
         Doctor Who (1963) - s01e02 - The Cave of Skulls (2).mp4
   /From the Earth to the Moon (1998)
      /Season 01
         From the Earth to the Moon (1998) - s01e01.mp4
         From the Earth to the Moon (1998) - s01e02.mp4
   /Grey's Anatomy (2005)
      /Season 00
         Grey's Anatomy (2005) - s00e01 - Straight to the Heart.mkv
      /Season 01
         Grey's Anatomy (2005) - s01e01 - pt1.avi
         Grey's Anatomy (2005) - s01e01 - pt2.avi
         Grey's Anatomy (2005) - s01e02 - The First Cut is the Deepest.avi
         Grey's Anatomy (2005) - s01e03.mp4
      /Season 02
         Grey's Anatomy (2005) - s02e01-e03.avi
         Grey's Anatomy (2005) - s02e04.m4v
   /The Colbert Report (2005)
      /Season 08
         The Colbert Report (2005) - 2011-11-15 - Elijah Wood.avi
   /The Office (UK) (2001) {tmdb-2996}
      /Season 01
         The Office (UK) - s01e01 - Downsize.mp4
   / The Office (US) (2005) {tvdb-73244}
      /Season 01
         The Office (US) - s01e01 - Pilot.mkv

## backups


