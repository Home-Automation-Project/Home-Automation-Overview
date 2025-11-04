# Servers and Services

| Domain    | Server |
| -------- | ------- |
| Media streaming (movies/TV shows)  | [Plex](./media//plex/plex-info.md) |
| Audio Books | [Audiobookshelf](./media/book_media_servers.md) |
| Picture backups | [Immich]()  |
| Music streaming (personal library) | [Navidrome + moOde](./media/music.md)  |
| Logging system  | [Loki](loki.md)  |
| Music streaming (personal library) | []() |
| Network Security | []() |
| DNS Routing  |[Traefik]() |
| Monitoring & Alerting | [MQTT, Email, Telegraph](../other/alert_monitoring.md) |
| Library Managment (Books, periodicals, & e-books) | [ Kavita + Calibre-Web + Audiobookshelf + Lazylibrarian](./media/book_media_servers.md) |
| Home Automation Services | [Home Assistant](./home%20automation%20controller/overvview.md)
| VPN | [Wireguard]() |
| Kubernetes cluster | [k3s]() |
| vacations | [AdventureLog]() |
| personal tracker | [dawarich]() |
| Notes/Sites tracking | [Karakeep + Zotero + Obsidian](./notes.md)  |
| PBX (phone system) | []()  |

**NOTE** The ideal setup for your media servers (movies, books, music, files, etc) is to have a separate RAIDed SAN upon which all media will be storead and which will be backed up automatically to an offsite location (preferably cloud).  For this full media overview follow the directions [here](./media/storage.md)