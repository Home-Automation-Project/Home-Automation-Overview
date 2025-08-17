Setting up a "Live TV Channel" of your media on Plex
When I was a kid I loved all of the holiday shows which were on TV and looking in the newspaper for the schedule.  This is what I did to create a channel which cycles through holiday movies.
To create a custom “TV channel” using Plex’s Tuner and IPTV you can integrate custom playlists or IPTV streams to mimic a live TV channel. 

Step 1: Install [xTeVe](https://github.com/xteve-project/xTeVe) (or similar software)
xTeVe acts as a middleman to provide an IPTV tuner interface for Plex.
- [Download xTeVe](https://github.com/xteve-project/xTeVe-Downloads)
- Install xTeVe (Follow the installation instructions for your system. Ensure it runs as a service if you plan to keep it always active)
- Set Up xTeVe
	•	Open xTeVe’s web interface (default is http://localhost:34400 or the IP of your xTeVe host).
	•	Under Settings, configure your directory paths and assign a port.
	•	Add your M3U playlist file (this defines the “channels”).
	•	You can generate your own playlist or use pre-made ones.

Step 2: Create a Custom M3U Playlist

An M3U file defines what episodes or shows play on your “channel.”
	1.	Create the M3U File
Use any text editor to create an .m3u file with the following format:

#EXTM3U
#EXTINF:-1 tvg-id="1" tvg-name="MyChannel" group-title="Custom", Show Name - Episode 1
http://<YOUR_PLEX_SERVER_IP>:32400/library/parts/<MEDIA_FILE_PATH>
#EXTINF:-1 tvg-id="2" tvg-name="MyChannel" group-title="Custom", Show Name - Episode 2
http://<YOUR_PLEX_SERVER_IP>:32400/library/parts/<MEDIA_FILE_PATH>

	•	Replace <YOUR_PLEX_SERVER_IP> with your Plex server’s IP address.
	•	Replace <MEDIA_FILE_PATH> with the file path for each episode you’d like to include.

  2.	Save the File
Save the file as custom_playlist.m3u.

Step 3: Configure xTeVe with the M3U Playlist
	1.	In the xTeVe interface, navigate to Playlist and upload your custom_playlist.m3u.
	2.	Assign an EPG (Electronic Program Guide) file if you want scheduling metadata (optional).
	3.	Map channels in xTeVe to match your playlist.

Step 4: Integrate xTeVe into Plex
	1.	Enable DVR in Plex
	•	Go to Plex > Settings > Live TV & DVR > Set Up Plex DVR.
	•	Plex will search for tuners; it should detect xTeVe as a tuner.
	2.	Select xTeVe as the tuner.
	3.	Follow the setup process to associate channels and EPG metadata.

Step 5: Enjoy Your Custom Channel

Now, your custom channel will appear in Plex under the Live TV & DVR section. You can play it like any other TV channel, and it will follow the sequence you set in your M3U file.

Would you like help creating an M3U file or setting up xTeVe?
