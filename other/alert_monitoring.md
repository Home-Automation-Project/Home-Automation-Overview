# Alert and Monitoring

## Alerts
### Email
1. Install drivers
`sudo apt install -y msmtp msmtp-mta mailutils`
2. Configure msmtp
`sudo vim /etc/msmtprc`
example for gmail setup (note: Use a Gmail App Password, not your regular password. Enable 2FA in your account first.)
```
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile ~/.msmtp.log

account gmail
host smtp.gmail.com
port 587
from your.email@gmail.com
user your.email@gmail.com
password YOUR_APP_PASSWORD

account default : gmail
```
3. Add sending an email to backup scripts, alerts or where needed
For example:
`echo -e "Media server backup completed on $(date)\nFiles uploaded to Dropbox at /backups/$DATE-*" | mail -s "Media Server Backup Complete [$DATE]" your.email@gmail.com`

### Telegraph
Telegram is a free, cloud-based messaging app known for its speed, security, and powerful features. It's available on Android, iOS, Windows, macOS, Linux, and Web.
| Feature                        | Description                                                         |
| ------------------------------ | ------------------------------------------------------------------- |
| **Fast & Lightweight**         | Optimized for speed, even on weak networks                          |
| **Cloud-Synced Messages**      | Access your messages from any device                                |
| **End-to-End Encrypted Chats** | Available in “Secret Chats” mode                                    |
| **File Sharing**               | Send files up to 2GB (or more with premium)                         |
| **Groups & Channels**          | Up to 200,000 members; channels for broadcasting                    |
| **Bots & Automation**          | Telegram supports powerful bots (used in monitoring, backups, etc.) |
| **Open API & Privacy**         | No ads, no tracking, and customizable clients                       |
| **Cross-Platform**             | Fully native apps across desktop and mobile                         |

1. Install Telegram:
Mobile: [Google Play](https://play.google.com/store/apps/details?id=org.telegram.messenger) | [App Store](https://apps.apple.com/app/telegram-messenger/id686449807)
Desktop: [telegram.org](https://telegram.org)
2. Sign up with your phone number (can be virtual)
3. Optional: Join public channels or create groups/bots
#### Install/Setup on server
1. Create a Telegram Bot
* Open Telegram and search for @BotFather
* Start a chat and type `/newbot`
* Follow the prompts
** Name: MediaBackupBot (example)
** Username: must end in bot, e.g. mediabackup_pi_bot
* Save the token you receive
2. Get Your Chat ID
* Open Telegram and search for `@get_id_bot`, or use this direct [link](https://t.me/get_id_bot)
* Start the bot and it will respond with your user ID (save that number as your chat id)
4. Add the ability to send alerts to your scripts as needed
```
# Telegram Alert
TELEGRAM_BOT_TOKEN="token from above"
TELEGRAM_CHAT_ID="id from above"

send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$1"
}
```
Example sending
`send_telegram "✅ Media server backup completed successfully on $(date). Files uploaded to Dropbox."`

### MQTT

## Monitor
### CPU
Script example (here set at 70 degrees Celsius)
```
cpu_temp=$(vcgencmd measure_temp | grep -oP '\d+\.\d+')
temp_limit=70.0

if (( $(echo "$cpu_temp > $temp_limit" | bc -l) )); then
  send_telegram "🔥 WARNING: CPU temperature is $cpu_temp°C on $(hostname)"
fi
```

### Disk Space
Script example
```
disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
usage_limit=85

if [ "$disk_usage" -gt "$usage_limit" ]; then
  send_telegram "⚠️ WARNING: Disk usage on / is at ${disk_usage}% on $(hostname)"
fi
```

### Cron scheduling
Setup Cron (example of running a script called monitor.sh on a schedule)
`crontab -e`
`*/30 * * * * /bin/bash /home/pi/monitor.sh`
* [Cron schedule helper](https://crontab.guru/)