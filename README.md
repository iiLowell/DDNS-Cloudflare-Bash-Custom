# Cloudflare DNS Updater

A bash script to automatically update Cloudflare DNS A records with your current IP address. Supports both external and internal IP updates, multiple DNS records, and Discord notifications.

## Features

- Update multiple A records simultaneously
- Support for both external and internal IP addresses
- Configurable TTL and proxy settings
- Discord notifications for successful updates and errors
- Multiple external IP detection services (failover support)
- Detailed logging

## Prerequisites

- Bash environment
- `curl` installed
- `nslookup` or `host` command (for DNS queries)
- Cloudflare API Token with DNS edit permissions
- Discord webhook URL (optional, for notifications)

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/DDNS-Cloudflare-Bash-Custom.git
   cd DDNS-Cloudflare-Bash-Custom
   ```

2. Make the script executable:
   ```bash
   chmod +x update-cloudflare-dns.sh
   ```

3. Edit the configuration file with your details:
   ```bash
   nano update-cloudflare-dns.conf
   ```

## Configuration

Edit `update-cloudflare-dns.conf` with your settings:

```bash
# Cloudflare Zone ID
zoneid="your_zone_id"

# Cloudflare API Token
cloudflare_zone_api_token="your_api_token"

# DNS Records to update (comma-separated)
dns_record="example.com,sub.example.com"

# TTL (120-7200, or 1 for automatic)
ttl="120"

# Proxy status (true/false)
proxied="false"

# IP type to use (external/internal)
what_ip="external"

# Discord notifications (yes/no)
notify_me_discord="no"
discord_webhook_url="your_discord_webhook_url"
```

## Usage

### Basic Usage
```bash
./update-cloudflare-dns.sh
```

### With Custom Config File
```bash
./update-cloudflare-dns.sh custom-config.conf
```

## Running Automatically

### Using Cron
Add to crontab to run every 5 minutes:
```bash
*/5 * * * * /bin/bash /path/to/update-cloudflare-dns.sh
```

## Logging

The script creates a log file `update-cloudflare-dns.log` in the same directory, containing the output of the last run.

## Error Handling

- Validates configuration parameters
- Checks for valid IP addresses
- Verifies DNS resolution
- Reports errors via console and Discord (if enabled)
- Continues processing remaining records if one fails

## Discord Notifications

When enabled, the script sends:
- ✅ Success notifications with updated DNS details
- ❌ Error notifications with detailed error messages

## Limitations

- Only supports IPv4 addresses
- TTL must be between 120-7200 seconds (or 1 for automatic)
- Internal IPs cannot be proxied through Cloudflare

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project was originaly released by [fire1ce](https://github.com/fire1ce/DDNS-Cloudflare-Bash) view [their License](https://github.com/fire1ce/DDNS-Cloudflare-Bash?tab=readme-ov-file#license).

## Acknowledgments

- Original project by [fire1ce](https://github.com/fire1ce/DDNS-Cloudflare-Bash)
- Cloudflare for their API
- External IP services: checkip.amazonaws.com, api.ipify.org, and ifconfig.me

This project is a modified version of the original [DDNS-Cloudflare-Bash](https://github.com/fire1ce/DDNS-Cloudflare-Bash) by fire1ce, with added features such as Discord notifications and multiple IP service failover support.
