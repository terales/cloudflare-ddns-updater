# Dynamic DNS (DDNS) for Cloudflare

Minimalist Bash script to update Cloudflare DNS records when your public IP changes.

> **Note:** This is a customized fork of the [original project by K0p1-Git](https://github.com/K0p1-Git/cloudflare-ddns-updater). See key changes section below

## Prerequisites

Ensure your system has the following installed:

*   `bash`
*   `xh` for Cloudflare API requests
*   `dnsutils` on Debian/Ubuntu for the `dig` command for finding public IP
*   `jq` for parsing JSON responses

## Installation

1. Clone the repository:
   ```bash
   git clone <your-repo-url>
   cd cloudflare-ddns-updater
   chmod +x cloudflare_ddns.sh
   ```

## Configuration

To keep your API tokens secure, this script loads configuration from a hidden secrets file.

1. Create the secrets file:
   ```bash
   nano ~/.ddns_secrets
   ```

2. Paste the following configuration and fill in your details:
   ```bash
   # Cloudflare Credentials
   export CF_AUTH_EMAIL="your_email@example.com"
   export CF_API_TOKEN="your_cloudflare_api_token"
   export CF_ZONE_ID="your_zone_id"
   export CF_RECORD_NAME="subdomain.yourdomain.com"

   # Optional Settings
   export CF_TTL=60                             # Default is 60 seconds
   export DISCORD_WEBHOOK_URI="https://discord..." # Leave empty to disable
   ```

3. **Important:** Secure the file so only your user can read it:
   ```bash
   chmod 600 ~/.ddns_secrets
   ```

## Automation (Cron)

Use `crontab` to run the script automatically. Since the script handles caching efficiently, you can run it frequently (e.g., every 1-5 minutes) without hitting API rate limits.

1. Edit your crontab:
   ```bash
   crontab -e
   ```

2. Add the schedule (example: run every 5 minutes):
   ```bash
   */5 * * * * /path/to/cloudflare_ddns.sh
   ```

## Checking logs

A `-t "DDNS-Updater"` flag is used to tags logs

The best way to view these logs in modern systems is using `journalctl`:

**View all logs for your script:**
```bash
# View all logs
journalctl -t DDNS-Updater

# Watch logs in real-time (like `tail -f`)
journalctl -f -t DDNS-Updater

# View only logs from today:
journalctl -t DDNS-Updater --since "today"
```

Note on the `-s` flag. The `-s` flag sends the output to standard error:

* Cron captures this output and discards it as I haven't set up redirection.
* When running manually the output is visible directly in terminal and is saved to the system logs.

## Logic Flow

1. **Get Public IP:** Queries Cloudflare/Google/OpenDNS via `dig`.
2. **Check Cache:** Compares public IP with `/tmp/cloudflare_ddns_server.example.com.cache`.
    *   *Match:* Exit silently (0 network calls).
    *   *Mismatch:* Proceed to update.
3. **Update:**
    *   Tries to `PATCH` Cloudflare immediately using the locally cached Record ID.
    *   If that fails (or ID is missing), performs a `GET` lookup to find the ID, then updates.

## Credits & Reference

*   Original Script by [K0p1-Git](https://github.com/K0p1-Git/cloudflare-ddns-updater)
*   Based on concepts by [Keld Norman](https://www.youtube.com/watch?v=vSIBkH7sxos)

## Key changes from the original project

I have refactored the original script to fit a specific homelab toolkit, applying the following stylistic and functional improvements:

*   **Tooling:**
    * Replaced `curl` with **[`xh`](https://github.com/ducaale/xh)** (faster than `httpie`, better UX than `curl`).
    * Replaced regexes with **[`jq`](https://jqlang.org/)** (easier to read for me).
    * Removed Slack support as I personally don't need it.
    * Removed IPv6 support as my ISP doesn't assign public IPv6 addresses yet.
*   **IP detection:** Switched from HTTP-based services (like ipify) to DNS-based detection using **`dig`**. This is faster and generates less network overhead.
*   **Local caching:** Implemented local caching for both the IP address and the Cloudflare Record ID. If the IP changes, the script attempts a direct `PATCH` request using the cached ID first. This saves an API lookup call during updates.
*   **Security:** Removed hardcoded credentials. Configuration is now handled via secured secrets file (not part of the repo).
*   **Safety:** Enabled bash strict mode (`set -euo pipefail`) for error handling.

## License
[MIT license](LICENSE)
